--------------------------------------------------------------------------------
-- Title      : LLC Frame Format Adapter (Legacy → Internal)
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : llc_frame_adapter.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Translates the 71-byte legacy LLC frame format (as defined in
--   the project report) to the internal variable-length streaming format
--   expected by tx_llc.
--
--   Legacy format (71 bytes, fixed):
--     Bytes 0-3:  ID bytes (right-aligned, format-dependent)
--     Byte  4:    [7]=reserved, [6:4]=FMT, [3:0]=DLC
--     Bytes 5-68: Data field (0-64 bytes, zero-padded to fill)
--     Byte  69:   [7:1]=reserved, [0]=IDE (redundant, not forwarded)
--     Byte  70:   [7:3]=reserved, [2]=BRS, [1]=ESI, [0]=RTR
--
--   Internal format (variable length, SOP on first byte):
--     Byte 0 (SOP=1): [7:5]=FMT, [4]=FTYP(RTR), [3]=ESI, [2]=BRS, [1:0]=00
--     Byte 1:         [7:4]=DLC, [3:0]=0000
--     Bytes 2-5:      ID bytes (left-aligned 32-bit vector, MSB first)
--     Bytes 6+:       Data bytes (DLC count only, no padding), EOP on last
--
--   Core constraint: BRS/ESI/RTR needed at byte 0 of internal format arrive
--   at byte 70 of the legacy format. The full 71-byte buffer must be received
--   before any internal byte is emitted.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;

entity llc_frame_adapter is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;
    -- User-facing (legacy format input)
    legacy_llc_i : in    llc_user_to_llc_if_t;
    legacy_llc_o : out   llc_to_llc_user_if_t;
    -- Internal-facing (converted format output to tx_llc)
    llc_o : out   llc_user_to_llc_if_t;
    llc_i : in    llc_to_llc_user_if_t
  );
end entity llc_frame_adapter;

architecture rtl of llc_frame_adapter is

  ---------------------------------------------------------------------------
  -- Types
  ---------------------------------------------------------------------------
  type adapter_state_t is (
    receive_frame,  -- Buffer incoming legacy bytes; wait for EOP (byte 70)
    emit_config_0,  -- Send SOP + config_byte_0 (built from bytes 4 and 70)
    emit_config_1,  -- Send config_byte_1 (from byte 4)
    emit_id_bytes,  -- Send repacked ID bytes (4 bytes, MSB first)
    emit_data_bytes -- Send data bytes (DLC count only), EOP on last
  );

  -- legacy_frame_len_c, legacy_fmt_dlc_byte_c, legacy_data_offset_c,
  -- legacy_flags_byte_c and legacy_frame_t are defined in can_types_pkg.

  type id_bytes_t is array (0 to 3) of byte_t;

  ---------------------------------------------------------------------------
  -- Signals
  ---------------------------------------------------------------------------
  signal state           : adapter_state_t;
  signal frame_buf       : legacy_frame_t;
  signal id_bytes        : id_bytes_t;
  signal rx_index        : integer range 0 to legacy_frame_len_c - 1;
  signal id_tx_index     : integer range 0 to 3;
  signal tx_index        : integer range 0 to legacy_frame_len_c - 1;
  signal data_byte_count : integer range 0 to max_data_bytes_c;

begin

  fsm_sequential : process (clk_i) is

    variable v_state           : adapter_state_t;
    variable v_frame_buf       : legacy_frame_t;
    variable v_id_bytes        : id_bytes_t;
    variable v_rx_index        : integer range 0 to legacy_frame_len_c - 1;
    variable v_id_tx_index     : integer range 0 to 3;
    variable v_tx_index        : integer range 0 to legacy_frame_len_c - 1;
    variable v_data_byte_count : integer range 0 to max_data_bytes_c;

    variable v_legacy_llc_o : llc_to_llc_user_if_t;
    variable v_llc_o        : llc_user_to_llc_if_t;

    -- Named guard variables
    variable legacy_valid_v     : boolean;
    variable legacy_eop_v       : boolean;
    variable downstream_ready_v : boolean;
    variable is_extended_v      : boolean;
    variable is_last_id_byte_v  : boolean;
    variable is_last_data_v     : boolean;
    variable no_data_v          : boolean;
    variable abort_v            : boolean;
    variable status_override_v  : boolean; -- True when abort set a non-ongoing status

    ---------------------------------------------------------------------------
    -- Build config_byte_0 from buffered legacy bytes
    ---------------------------------------------------------------------------
    procedure build_config_byte_0 (
      signal buf : in    legacy_frame_t;
      result     : out   byte_t
    ) is
    begin

      -- [7:5] = FMT from legacy byte 4 bits [6:4]
      -- [4]   = RTR from legacy byte 70 bit [0]
      -- [3]   = ESI from legacy byte 70 bit [1]
      -- [2]   = BRS from legacy byte 70 bit [2]
      -- [1:0] = "00"
      result(7)          := buf(legacy_fmt_dlc_byte_c)(6);
      result(6)          := buf(legacy_fmt_dlc_byte_c)(5);
      result(5)          := buf(legacy_fmt_dlc_byte_c)(4);
      result(4)          := buf(legacy_flags_byte_c)(0); -- RTR
      result(3)          := buf(legacy_flags_byte_c)(1); -- ESI
      result(2)          := buf(legacy_flags_byte_c)(2); -- BRS
      result(1 downto 0) := "00";

    end procedure build_config_byte_0;

    ---------------------------------------------------------------------------
    -- Build config_byte_1 from legacy byte 4
    ---------------------------------------------------------------------------
    procedure build_config_byte_1 (
      signal buf : in    legacy_frame_t;
      result     : out   byte_t
    ) is
    begin

      -- [7:4] = DLC from legacy byte 4 bits [3:0]
      -- [3:0] = "0000"
      result(7 downto 4) := buf(legacy_fmt_dlc_byte_c)(3 downto 0);
      result(3 downto 0) := "0000";

    end procedure build_config_byte_1;

    ---------------------------------------------------------------------------
    -- Repack ID from right-aligned legacy layout to left-aligned id_bytes
    ---------------------------------------------------------------------------
    procedure repack_id (
      signal   buf    : in    legacy_frame_t;
      variable is_ext : in    boolean;
      variable result : out   id_bytes_t
    ) is

      variable raw_id_v : std_logic_vector(31 downto 0);

    begin

      raw_id_v := (others => '0');

      if (is_ext) then
        -- 29-bit ID: byte0[4:0] & byte1 & byte2 & byte3 → left-align in 32 bits
        -- id_buf[31:3] = raw_id[28:0], id_buf[2:0] = "000"
        raw_id_v(31 downto 3) := buf(0)(4 downto 0) & buf(1) & buf(2) & buf(3);
      else
        -- 11-bit ID: byte2[2:0] & byte3 → left-align in 32 bits
        -- id_buf[31:21] = raw_id[10:0], rest = zeros
        raw_id_v(31 downto 21) := buf(2)(2 downto 0) & buf(3);
      end if;

      result(0) := raw_id_v(31 downto 24);
      result(1) := raw_id_v(23 downto 16);
      result(2) := raw_id_v(15 downto 8);
      result(3) := raw_id_v(7 downto 0);

    end procedure repack_id;

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        state           <= receive_frame;
        rx_index        <= 0;
        id_tx_index     <= 0;
        tx_index        <= legacy_data_offset_c;
        data_byte_count <= 0;
        frame_buf       <= (others => (others => '0'));
        id_bytes        <= (others => (others => '0'));

        legacy_llc_o <= (avalon_st_sink => (ready => '0'), transfer_status => ongoing);
        llc_o        <=
        (
          avalon_st_source => (data => (others => '0'), valid => '0', sop => '0', eop => '0'),
          abort_request    => '0'
        );
      else
        -- Evaluate guards
        legacy_valid_v     := legacy_llc_i.avalon_st_source.valid = '1';
        legacy_eop_v       := legacy_llc_i.avalon_st_source.eop = '1';
        downstream_ready_v := llc_i.avalon_st_sink.ready = '1';
        is_extended_v      := frame_buf(legacy_fmt_dlc_byte_c)(6) = '1';
        abort_v            := legacy_llc_i.abort_request = '1';
        is_last_id_byte_v  := id_tx_index = 3;
        is_last_data_v     := tx_index = legacy_data_offset_c + data_byte_count - 1;
        no_data_v          := data_byte_count = 0;

        -- Defaults: hold registered values
        v_state           := state;
        v_frame_buf       := frame_buf;
        v_id_bytes        := id_bytes;
        v_rx_index        := rx_index;
        v_id_tx_index     := id_tx_index;
        v_tx_index        := tx_index;
        v_data_byte_count := data_byte_count;

        -- Default output values (de-assert pulses)
        v_legacy_llc_o.avalon_st_sink.ready := '0';
        v_legacy_llc_o.transfer_status      := ongoing;
        status_override_v                   := false;

        v_llc_o.avalon_st_source.valid := '0';
        v_llc_o.avalon_st_source.sop   := '0';
        v_llc_o.avalon_st_source.eop   := '0';
        v_llc_o.avalon_st_source.data  := (others => '0');
        v_llc_o.abort_request          := legacy_llc_i.abort_request;

        -------------------------------------------------------------------
        -- State + output logic
        -------------------------------------------------------------------
        case state is

          when receive_frame =>
            -- Accept legacy bytes until EOP (byte 70).
            -- An abort_request during receive resets the buffer and signals
            -- aborted status back to the user for one cycle, but only if
            -- bytes have been buffered (rx_index > 0). When the adapter is
            -- idle (rx_index = 0, no frame in progress), abort is ignored.
            if (abort_v and rx_index > 0) then
              v_rx_index                     := 0;
              v_legacy_llc_o.transfer_status := aborted;
              status_override_v              := true;
            else
              v_legacy_llc_o.avalon_st_sink.ready := '1';
            end if;

            if (legacy_valid_v and not abort_v) then
              v_frame_buf(rx_index) := legacy_llc_i.avalon_st_source.data;

              if (legacy_eop_v) then
                -- Full 71-byte frame buffered; compute derived values
                v_data_byte_count := dlc_to_data_length(
                                                        dlc_t(to_integer(unsigned(v_frame_buf(legacy_fmt_dlc_byte_c)(3 downto 0)))),
                                                        decode_llc_format(v_frame_buf(legacy_fmt_dlc_byte_c)(6 downto 4))
                                                      );

                repack_id(frame_buf, is_extended_v, v_id_bytes);
                v_rx_index := 0;
                v_state    := emit_config_0;
              elsif (rx_index < legacy_frame_len_c - 1) then
                v_rx_index := rx_index + 1;
              end if;
            end if;

          when emit_config_0 =>
            -- Present SOP + config_byte_0 to downstream
            v_llc_o.avalon_st_source.valid := '1';
            v_llc_o.avalon_st_source.sop   := '1';
            build_config_byte_0(frame_buf, v_llc_o.avalon_st_source.data);

            if (downstream_ready_v) then
              v_state := emit_config_1;
            end if;

          when emit_config_1 =>
            -- Present config_byte_1 to downstream
            v_llc_o.avalon_st_source.valid := '1';
            build_config_byte_1(frame_buf, v_llc_o.avalon_st_source.data);

            if (downstream_ready_v) then
              v_id_tx_index := 0;
              v_state       := emit_id_bytes;
            end if;

          when emit_id_bytes =>
            -- Stream 4 repacked ID bytes, MSB first
            v_llc_o.avalon_st_source.valid := '1';
            v_llc_o.avalon_st_source.data  := id_bytes(id_tx_index);

            -- EOP on last ID byte when frame has no data payload
            if (is_last_id_byte_v and no_data_v) then
              v_llc_o.avalon_st_source.eop := '1';
            end if;

            if (downstream_ready_v) then
              if (is_last_id_byte_v) then
                if (no_data_v) then
                  -- No data: frame complete, return to receive
                  v_state := receive_frame;
                else
                  v_tx_index := legacy_data_offset_c;
                  v_state    := emit_data_bytes;
                end if;
              else
                v_id_tx_index := id_tx_index + 1;
              end if;
            end if;

          when emit_data_bytes =>
            -- Stream N data bytes from frame_buf[5..5+N-1]
            v_llc_o.avalon_st_source.valid := '1';
            v_llc_o.avalon_st_source.data  := frame_buf(tx_index);

            if (is_last_data_v) then
              v_llc_o.avalon_st_source.eop := '1';
            end if;

            if (downstream_ready_v) then
              if (is_last_data_v) then
                v_state := receive_frame;
              else
                v_tx_index := tx_index + 1;
              end if;
            end if;

          when others =>
            null;

        end case;

        -------------------------------------------------------------------
        -- Pass downstream transfer_status through only when the adapter is
        -- staying in (or returning to) receive_frame.  During emit states,
        -- hold ongoing so residual status from a prior frame is not visible
        -- to the user while the new frame is being queued.
        -------------------------------------------------------------------
        if (v_state = receive_frame and not status_override_v) then
          v_legacy_llc_o.transfer_status := llc_i.transfer_status;
        end if;

        -------------------------------------------------------------------
        -- Register outputs
        -------------------------------------------------------------------
        state           <= v_state;
        frame_buf       <= v_frame_buf;
        id_bytes        <= v_id_bytes;
        rx_index        <= v_rx_index;
        id_tx_index     <= v_id_tx_index;
        tx_index        <= v_tx_index;
        data_byte_count <= v_data_byte_count;

        legacy_llc_o <= v_legacy_llc_o;
        llc_o        <= v_llc_o;

      end if;
    end if;

  end process fsm_sequential;

end architecture rtl;
