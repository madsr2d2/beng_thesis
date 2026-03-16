--------------------------------------------------------------------------------
-- Title      : CAN Bus LLC Transmit Controller
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_llc_tx.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Logical Link Control (LLC) sub-layer for CAN transmission.
--              Accepts full frame bytes on Avalon-ST from LLC user, buffers the
--              frame, and handles replay for retransmissions.
--
-- Protocol references: ISO 11898-1:2015 Section 6.4
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;
  use work.can_protocol_pkg.all;

entity can_llc_tx is
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- LLC user interface (Avalon-ST input stream)
    llc_user_i : in    t_can_user_llc_tx_if_s2d;
    llc_user_o : out   t_can_user_llc_tx_if_d2s;

    -- MAC interface (Avalon-ST output stream)
    mac_i : in    t_can_llc_mac_tx_if_d2s;
    mac_o : out   t_can_llc_mac_tx_if_s2d
  );
end entity can_llc_tx;

architecture rtl of can_llc_tx is

  ---------------------------------------------------------------------------
  -- Local state encoding
  ---------------------------------------------------------------------------
  constant c_st_idle            : std_logic_vector(2 downto 0) := "000";
  constant c_st_capture_frame   : std_logic_vector(2 downto 0) := "001";
  constant c_st_send_frame      : std_logic_vector(2 downto 0) := "010";
  constant c_st_wait_for_result : std_logic_vector(2 downto 0) := "011";
  constant c_st_wait_for_idle   : std_logic_vector(2 downto 0) := "100";

  ---------------------------------------------------------------------------
  -- Constants
  ---------------------------------------------------------------------------
  constant c_llc_header_bytes    : integer := 6; -- cfg0+cfg1+id3..id0
  constant c_max_llc_frame_bytes : integer := c_llc_header_bytes + c_max_data_bytes;

  ---------------------------------------------------------------------------
  -- Types
  ---------------------------------------------------------------------------
  type t_llc_frame_buffer is array (0 to c_max_llc_frame_bytes - 1) of t_byte;

  ---------------------------------------------------------------------------
  -- Registered state signals
  ---------------------------------------------------------------------------
  signal state              : std_logic_vector(2 downto 0);
  signal frame_buf          : t_llc_frame_buffer;
  signal frame_len_bytes    : integer range 0 to c_max_llc_frame_bytes;
  signal capture_index      : integer range 0 to c_max_llc_frame_bytes - 1;
  signal tx_index           : integer range 0 to c_max_llc_frame_bytes - 1;
  signal expected_len_bytes : integer range 0 to c_max_llc_frame_bytes;
  signal retx_count         : integer range 0 to retransmission_limit_c;
  signal mac_status_armed   : boolean;

begin

  p_llc_fsm : process (clk) is

    variable accepted_idx_v : integer;
    variable expected_len_v : integer;
    variable format_v       : std_logic_vector(2 downto 0);
    variable dlc_v          : t_dlc;
    variable data_len_v     : integer;
    variable cfg_valid_v    : boolean;

    -- Helper: check if format is valid
    function is_valid_format (fmt : std_logic_vector(2 downto 0)) return boolean is
    begin
      return fmt = c_llc_fmt_cb or fmt = c_llc_fmt_ce or
             fmt = c_llc_fmt_fb or fmt = c_llc_fmt_fe;
    end function is_valid_format;

  begin

    if rising_edge(clk) then
      if (rst = '1') then
        state              <= c_st_idle;
        frame_len_bytes    <= 0;
        capture_index      <= 0;
        tx_index           <= 0;
        expected_len_bytes <= 0;
        retx_count         <= 0;
        mac_status_armed   <= false;
        frame_buf          <= (others => (others => '0'));

        llc_user_o.avalon_st_sink.ready <= '1';
        llc_user_o.transfer_status      <= c_ongoing;

        mac_o.avalon_st_source.data  <= (others => '0');
        mac_o.avalon_st_source.valid <= '0';
        mac_o.avalon_st_source.sop   <= '0';
        mac_o.avalon_st_source.eop   <= '0';
      else
        -- Defaults.
        llc_user_o.avalon_st_sink.ready <= '0';
        mac_o.avalon_st_source.valid    <= '0';
        mac_o.avalon_st_source.sop      <= '0';
        mac_o.avalon_st_source.eop      <= '0';

        case state is
          when c_st_idle =>
            llc_user_o.avalon_st_sink.ready <= '1';
            retx_count                      <= 0;
            mac_status_armed                <= false;
            frame_len_bytes                 <= 0;
            capture_index                   <= 0;
            tx_index                        <= 0;
            expected_len_bytes              <= 0;

            if (llc_user_i.avalon_st_source.valid = '1' and llc_user_i.avalon_st_source.sop = '1') then
              -- Canonical LLC frame requires at least 6 header bytes.
              if (llc_user_i.avalon_st_source.eop = '1') then
                llc_user_o.transfer_status <= c_aborted;
                state                      <= c_st_idle;
              else
                llc_user_o.transfer_status <= c_ongoing;
                frame_buf(0)               <= llc_user_i.avalon_st_source.data;
                capture_index              <= 1;
                state                      <= c_st_capture_frame;
              end if;
            end if;

          when c_st_capture_frame =>
            llc_user_o.avalon_st_sink.ready <= '1';

            -- Abort only while still buffering and MAC has not started.
            if (llc_user_i.abort_request = '1') then
              llc_user_o.transfer_status <= c_aborted;
              state                      <= c_st_idle;
            elsif (llc_user_i.avalon_st_source.valid = '1') then
              expected_len_v := expected_len_bytes;
              cfg_valid_v    := true;
              if (capture_index < c_max_llc_frame_bytes) then
                frame_buf(capture_index) <= llc_user_i.avalon_st_source.data;
                accepted_idx_v           := capture_index;

                if (capture_index = 1) then
                  format_v := frame_buf(0)(c_llc_frame_config_byte_0_format_start downto c_llc_frame_config_byte_0_format_end);
                  if (not is_valid_format(format_v)) then
                    cfg_valid_v                := false;
                    llc_user_o.transfer_status <= c_aborted;
                    state                      <= c_st_idle;
                  else
                    dlc_v              := t_dlc(
                                                to_integer(
                                                            unsigned(
                                                                      llc_user_i.avalon_st_source.data(
                                                                                                        c_llc_frame_config_byte_1_dlc_start downto c_llc_frame_config_byte_1_dlc_end
                                                                                                      )
                                                                    )
                                                          )
                                              );
                    data_len_v         := dlc_to_data_length(dlc_v, format_v);
                    expected_len_v     := c_llc_header_bytes + data_len_v;
                    expected_len_bytes <= expected_len_v;
                  end if;
                end if;

                if (not cfg_valid_v) then
                  null;
                elsif (llc_user_i.avalon_st_source.eop = '1' and accepted_idx_v + 1 < c_llc_header_bytes) then
                  llc_user_o.transfer_status <= c_aborted;
                  state                      <= c_st_idle;
                elsif (llc_user_i.avalon_st_source.eop = '1') then
                  if (expected_len_v > 0 and accepted_idx_v + 1 = expected_len_v) then
                    frame_len_bytes <= expected_len_v;
                    tx_index        <= 0;
                    state           <= c_st_send_frame;
                  else
                    llc_user_o.transfer_status <= c_aborted;
                    state                      <= c_st_idle;
                  end if;
                elsif (expected_len_v > 0 and accepted_idx_v + 1 = expected_len_v) then
                  -- Expected end reached without EOP.
                  llc_user_o.transfer_status <= c_aborted;
                  state                      <= c_st_idle;
                elsif (capture_index < c_max_llc_frame_bytes - 1) then
                  capture_index <= capture_index + 1;
                else
                  llc_user_o.transfer_status <= c_aborted;
                  state                      <= c_st_idle;
                end if;
              else
                llc_user_o.transfer_status <= c_aborted;
                state                      <= c_st_idle;
              end if;
            end if;

          when c_st_send_frame =>
            if (mac_i.transfer_status = c_ongoing) then
              mac_status_armed <= true;
            end if;

            -- Monitor terminal status even while sending (ISO: arbitration loss/bit error can happen early)
            if (mac_status_armed and mac_i.transfer_status /= c_ongoing) then
              case mac_i.transfer_status is
                when c_lost_arb =>
                  tx_index <= 0;
                  state    <= c_st_send_frame;
                when c_disturbed =>
                  if (retx_count >= retransmission_limit_c) then
                    llc_user_o.transfer_status <= c_aborted;
                    state                      <= c_st_idle;
                  else
                    retx_count <= retx_count + 1;
                    state      <= c_st_wait_for_idle;
                  end if;
                when others =>
                  llc_user_o.transfer_status <= mac_i.transfer_status;
                  state                      <= c_st_idle;
              end case;
            elsif (tx_index < frame_len_bytes) then
              mac_o.avalon_st_source.data  <= frame_buf(tx_index);
              mac_o.avalon_st_source.valid <= '1';
              if (tx_index = 0) then
                mac_o.avalon_st_source.sop <= '1';
              end if;
              if (tx_index = frame_len_bytes - 1) then
                mac_o.avalon_st_source.eop <= '1';
              end if;

              if (mac_i.avalon_st_sink.ready = '1') then
                if (tx_index = frame_len_bytes - 1) then
                  state <= c_st_wait_for_result;
                else
                  tx_index <= tx_index + 1;
                end if;
              end if;
            else
              state <= c_st_wait_for_result;
            end if;

          when c_st_wait_for_result =>
            if (not mac_status_armed) then
              if (mac_i.transfer_status = c_ongoing) then
                mac_status_armed <= true;
              end if;
            else
              case mac_i.transfer_status is
                when c_transmitted =>
                  llc_user_o.transfer_status <= c_transmitted;
                  state                      <= c_st_idle;

                when c_lost_arb =>
                  tx_index <= 0;
                  state    <= c_st_send_frame;

                when c_disturbed =>
                  if (retx_count >= retransmission_limit_c) then
                    llc_user_o.transfer_status <= c_aborted;
                    state                      <= c_st_idle;
                  else
                    retx_count <= retx_count + 1;
                    state      <= c_st_wait_for_idle;
                  end if;

                when c_aborted =>
                  llc_user_o.transfer_status <= c_aborted;
                  state                      <= c_st_idle;

                when others =>
                  null;
              end case;
            end if;

          when c_st_wait_for_idle =>
            -- Abort is accepted between attempts.
            if (llc_user_i.abort_request = '1') then
              llc_user_o.transfer_status <= c_aborted;
              state                      <= c_st_idle;
            elsif (mac_i.avalon_st_sink.ready = '1') then
              tx_index <= 0;
              state    <= c_st_send_frame;
            end if;

          when others =>
            state <= c_st_idle;

        end case;
      end if;
    end if;

  end process p_llc_fsm;

end architecture rtl;

--------------------------------------------------------------------------------
-- Architecture: legacy_rtl
-- Accepts the 71-byte legacy LLC frame format directly and performs in-place
-- conversion to the internal variable-length format before streaming to MAC.
--------------------------------------------------------------------------------

architecture legacy_rtl of can_llc_tx is

  ---------------------------------------------------------------------------
  -- Local state encoding
  ---------------------------------------------------------------------------
  constant c_st_idle            : std_logic_vector(2 downto 0) := "000";
  constant c_st_capture_frame   : std_logic_vector(2 downto 0) := "001";
  constant c_st_send_frame      : std_logic_vector(2 downto 0) := "010";
  constant c_st_wait_for_result : std_logic_vector(2 downto 0) := "011";
  constant c_st_wait_for_idle   : std_logic_vector(2 downto 0) := "100";

  ---------------------------------------------------------------------------
  -- Constants
  ---------------------------------------------------------------------------
  constant c_llc_header_bytes    : integer := 6; -- cfg0+cfg1+id3..id0
  constant c_max_llc_frame_bytes : integer := c_llc_header_bytes + c_max_data_bytes;

  ---------------------------------------------------------------------------
  -- Registered state signals
  ---------------------------------------------------------------------------
  signal state            : std_logic_vector(2 downto 0);
  signal frame_buf        : t_legacy_frame;
  signal frame_len_bytes  : integer range 0 to c_max_llc_frame_bytes;
  signal capture_index    : integer range 0 to c_legacy_frame_len - 1;
  signal tx_index         : integer range 0 to c_max_llc_frame_bytes - 1;
  signal retx_count       : integer range 0 to retransmission_limit_c;
  signal mac_status_armed : boolean;

begin

  p_llc_fsm : process (clk) is

    variable format_v   : std_logic_vector(2 downto 0);
    variable dlc_v      : t_dlc;
    variable data_len_v : integer;
    variable is_ext_v   : boolean;

    -- Conversion results (computed on EOP, written into frame_buf)
    variable cfg0_v : t_byte;
    variable cfg1_v : t_byte;
    variable id0_v  : t_byte;
    variable id1_v  : t_byte;
    variable id2_v  : t_byte;
    variable id3_v  : t_byte;

    -- Helper: check if format is valid
    function is_valid_format (fmt : std_logic_vector(2 downto 0)) return boolean is
    begin
      return fmt = c_llc_fmt_cb or fmt = c_llc_fmt_ce or
             fmt = c_llc_fmt_fb or fmt = c_llc_fmt_fe;
    end function is_valid_format;

    ---------------------------------------------------------------------------
    -- Build config_byte_1 from legacy byte 4
    ---------------------------------------------------------------------------
    procedure build_config_byte_1 (
      buf    : in    t_legacy_frame;
      result : out   t_byte
    ) is
    begin

      -- [7:4] = DLC from legacy byte 4 bits [3:0]
      -- [3:0] = "0000"
      result(7 downto 4) := buf(c_legacy_fmt_dlc_byte)(3 downto 0);
      result(3 downto 0) := "0000";

    end procedure build_config_byte_1;

    ---------------------------------------------------------------------------
    -- Repack ID from right-aligned legacy layout to left-aligned bytes
    ---------------------------------------------------------------------------
    procedure repack_id (
      buf    : in    t_legacy_frame;
      is_ext : in    boolean;
      id0    : out   t_byte;
      id1    : out   t_byte;
      id2    : out   t_byte;
      id3    : out   t_byte
    ) is

      variable raw_id_v : std_logic_vector(31 downto 0);

    begin

      raw_id_v := (others => '0');

      if (is_ext) then
        -- 29-bit ID: left-align in 32 bits
        raw_id_v(31 downto 3) := buf(0)(4 downto 0) & buf(1) & buf(2) & buf(3);
      else
        -- 11-bit ID: left-align in 32 bits
        raw_id_v(31 downto 21) := buf(2)(2 downto 0) & buf(3);
      end if;

      id0 := raw_id_v(31 downto 24);
      id1 := raw_id_v(23 downto 16);
      id2 := raw_id_v(15 downto 8);
      id3 := raw_id_v(7 downto 0);

    end procedure repack_id;

  begin

    if rising_edge(clk) then
      if (rst = '1') then
        state            <= c_st_idle;
        frame_len_bytes  <= 0;
        capture_index    <= 0;
        tx_index         <= 0;
        retx_count       <= 0;
        mac_status_armed <= false;
        frame_buf        <= (others => (others => '0'));

        llc_user_o.avalon_st_sink.ready <= '1';
        llc_user_o.transfer_status      <= c_ongoing;

        mac_o.avalon_st_source.data  <= (others => '0');
        mac_o.avalon_st_source.valid <= '0';
        mac_o.avalon_st_source.sop   <= '0';
        mac_o.avalon_st_source.eop   <= '0';
      else
        -- Defaults.
        llc_user_o.avalon_st_sink.ready <= '0';
        mac_o.avalon_st_source.valid    <= '0';
        mac_o.avalon_st_source.sop      <= '0';
        mac_o.avalon_st_source.eop      <= '0';

        case state is
          when c_st_idle =>
            llc_user_o.avalon_st_sink.ready <= '1';
            retx_count                      <= 0;
            mac_status_armed                <= false;
            frame_len_bytes                 <= 0;
            capture_index                   <= 0;
            tx_index                        <= 0;

            if (llc_user_i.avalon_st_source.valid = '1' and llc_user_i.avalon_st_source.sop = '1') then
              -- Legacy frame is always 71 bytes. Single-byte SOP+EOP is invalid.
              if (llc_user_i.avalon_st_source.eop = '1') then
                llc_user_o.transfer_status <= c_aborted;
                state                      <= c_st_idle;
              else
                llc_user_o.transfer_status <= c_ongoing;
                frame_buf(0)               <= llc_user_i.avalon_st_source.data;
                capture_index              <= 1;
                state                      <= c_st_capture_frame;
              end if;
            end if;

          when c_st_capture_frame =>
            llc_user_o.avalon_st_sink.ready <= '1';

            -- Abort while still buffering (MAC has not started).
            if (llc_user_i.abort_request = '1') then
              llc_user_o.transfer_status <= c_aborted;
              state                      <= c_st_idle;
            elsif (llc_user_i.avalon_st_source.valid = '1') then
              if (capture_index < c_legacy_frame_len) then
                frame_buf(capture_index) <= llc_user_i.avalon_st_source.data;

                if (llc_user_i.avalon_st_source.eop = '1') then
                  if (capture_index = c_legacy_frame_len - 1) then
                    -- Full 71-byte legacy frame received. Perform in-place conversion.

                    -- Decode format from byte 4 (already in frame_buf from a prior cycle)
                    format_v := frame_buf(c_legacy_fmt_dlc_byte)(6 downto 4);

                    if (not is_valid_format(format_v)) then
                      llc_user_o.transfer_status <= c_aborted;
                      state                      <= c_st_idle;
                    else
                      is_ext_v := frame_buf(c_legacy_fmt_dlc_byte)(6) = '1';

                      -- Build config_byte_0: needs bytes 4 and 70.
                      -- Byte 70 is the current input (not yet in frame_buf signal).
                      cfg0_v(7)          := frame_buf(c_legacy_fmt_dlc_byte)(6);
                      cfg0_v(6)          := frame_buf(c_legacy_fmt_dlc_byte)(5);
                      cfg0_v(5)          := frame_buf(c_legacy_fmt_dlc_byte)(4);
                      cfg0_v(4)          := llc_user_i.avalon_st_source.data(0); -- RTR
                      cfg0_v(3)          := llc_user_i.avalon_st_source.data(1); -- ESI
                      cfg0_v(2)          := llc_user_i.avalon_st_source.data(2); -- BRS
                      cfg0_v(1 downto 0) := "00";

                      -- Build config_byte_1 from byte 4 (already buffered)
                      build_config_byte_1(frame_buf, cfg1_v);

                      -- Repack ID from bytes 0-3 (already buffered)
                      repack_id(frame_buf, is_ext_v, id0_v, id1_v, id2_v, id3_v);

                      -- Compute data length
                      dlc_v := t_dlc(
                                      to_integer(
                                                  unsigned(
                                                            frame_buf(c_legacy_fmt_dlc_byte)(3 downto 0)
                                                          )
                                                )
                                    );
                      data_len_v := dlc_to_data_length(dlc_v, format_v);

                      -- Shift data bytes up by one slot (index 5+i -> 6+i).
                      for i in data_len_v - 1 downto 0 loop
                        frame_buf(c_llc_header_bytes + i) <= frame_buf(c_legacy_data_offset + i);
                      end loop;

                      -- Write converted header into frame_buf
                      frame_buf(0) <= cfg0_v;
                      frame_buf(1) <= cfg1_v;
                      frame_buf(2) <= id0_v;
                      frame_buf(3) <= id1_v;
                      frame_buf(4) <= id2_v;
                      frame_buf(5) <= id3_v;

                      frame_len_bytes <= c_llc_header_bytes + data_len_v;
                      tx_index        <= 0;
                      state           <= c_st_send_frame;
                    end if;
                  else
                    -- EOP arrived before byte 70 - incomplete legacy frame.
                    llc_user_o.transfer_status <= c_aborted;
                    state                      <= c_st_idle;
                  end if;
                elsif (capture_index < c_legacy_frame_len - 1) then
                  capture_index <= capture_index + 1;
                else
                  -- Reached byte 70 without EOP - protocol error.
                  llc_user_o.transfer_status <= c_aborted;
                  state                      <= c_st_idle;
                end if;
              else
                -- Overflow beyond 71 bytes.
                llc_user_o.transfer_status <= c_aborted;
                state                      <= c_st_idle;
              end if;
            end if;

          -----------------------------------------------------------------
          -- send_frame, wait_for_result, wait_for_idle are identical to rtl
          -----------------------------------------------------------------

          when c_st_send_frame =>
            if (mac_i.transfer_status = c_ongoing) then
              mac_status_armed <= true;
            end if;

            -- Monitor terminal status even while sending
            if (mac_status_armed and mac_i.transfer_status /= c_ongoing) then
              case mac_i.transfer_status is
                when c_lost_arb =>
                  tx_index <= 0;
                  state    <= c_st_send_frame;
                when c_disturbed =>
                  if (retx_count >= retransmission_limit_c) then
                    llc_user_o.transfer_status <= c_aborted;
                    state                      <= c_st_idle;
                  else
                    retx_count <= retx_count + 1;
                    state      <= c_st_wait_for_idle;
                  end if;
                when others =>
                  llc_user_o.transfer_status <= mac_i.transfer_status;
                  state                      <= c_st_idle;
              end case;
            elsif (tx_index < frame_len_bytes) then
              mac_o.avalon_st_source.data  <= frame_buf(tx_index);
              mac_o.avalon_st_source.valid <= '1';
              if (tx_index = 0) then
                mac_o.avalon_st_source.sop <= '1';
              end if;
              if (tx_index = frame_len_bytes - 1) then
                mac_o.avalon_st_source.eop <= '1';
              end if;

              if (mac_i.avalon_st_sink.ready = '1') then
                if (tx_index = frame_len_bytes - 1) then
                  state <= c_st_wait_for_result;
                else
                  tx_index <= tx_index + 1;
                end if;
              end if;
            else
              state <= c_st_wait_for_result;
            end if;

          when c_st_wait_for_result =>
            if (not mac_status_armed) then
              if (mac_i.transfer_status = c_ongoing) then
                mac_status_armed <= true;
              end if;
            else
              case mac_i.transfer_status is
                when c_transmitted =>
                  llc_user_o.transfer_status <= c_transmitted;
                  state                      <= c_st_idle;

                when c_lost_arb =>
                  tx_index <= 0;
                  state    <= c_st_send_frame;

                when c_disturbed =>
                  if (retx_count >= retransmission_limit_c) then
                    llc_user_o.transfer_status <= c_aborted;
                    state                      <= c_st_idle;
                  else
                    retx_count <= retx_count + 1;
                    state      <= c_st_wait_for_idle;
                  end if;

                when c_aborted =>
                  llc_user_o.transfer_status <= c_aborted;
                  state                      <= c_st_idle;

                when others =>
                  null;
              end case;
            end if;

          when c_st_wait_for_idle =>
            -- Abort is accepted between attempts.
            if (llc_user_i.abort_request = '1') then
              llc_user_o.transfer_status <= c_aborted;
              state                      <= c_st_idle;
            elsif (mac_i.avalon_st_sink.ready = '1') then
              tx_index <= 0;
              state    <= c_st_send_frame;
            end if;

          when others =>
            state <= c_st_idle;

        end case;
      end if;
    end if;

  end process p_llc_fsm;

end architecture legacy_rtl;
