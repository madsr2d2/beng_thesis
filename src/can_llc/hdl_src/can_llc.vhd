--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Logical Link Control (LLC) sub-layer for CAN transmission.
--                Accepts the legacy 71-byte frame format from the user, converts
--                it to the internal frame format, buffers it, and drives the
--                MAC TX byte stream. Handles automatic retransmission on
--                c_lost_arb / c_disturbed (no retransmission count limit) and
--                holds-and-resumes the frame across bus-off recovery windows.
--                Protocol references: ISO 11898-1:2015 sections 6.4 and 8.1.4.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-31  MRDSA     Converted to company header format
--                2026-04-30  MRDSA     Single legacy-only architecture; drop
--                                      retransmission limit; add bus-off
--                                      hold-and-resume + FCE-LLC ports
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

entity can_llc is
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- LLC user interface (Avalon-ST source, legacy 71-byte frame)
    llc_user_i : in    t_can_user_llc_tx_if_s2d;
    llc_user_o : out   t_can_user_llc_tx_if_d2s;

    -- MAC TX interface (Avalon-ST source, internal frame format)
    mac_i : in    t_can_llc_mac_tx_if_d2s;
    mac_o : out   t_can_llc_mac_tx_if_s2d;

    -- FCE interface (bus-off status in, normal_mode out)
    fce_i : in    t_can_fce_llc_if_s2m;
    fce_o : out   t_can_llc_fce_if_m2s
  );
end entity can_llc;

architecture rtl of can_llc is

  ---------------------------------------------------------------------------
  -- States
  ---------------------------------------------------------------------------
  constant c_st_idle         : std_logic_vector(2 downto 0) := "000";
  constant c_st_capture      : std_logic_vector(2 downto 0) := "001";
  constant c_st_send         : std_logic_vector(2 downto 0) := "010";
  constant c_st_wait_result  : std_logic_vector(2 downto 0) := "011";
  constant c_st_wait_idle    : std_logic_vector(2 downto 0) := "100";
  constant c_st_bus_off_hold : std_logic_vector(2 downto 0) := "101";

  ---------------------------------------------------------------------------
  -- Constants
  ---------------------------------------------------------------------------
  constant c_llc_header_bytes    : natural := 6; -- cfg0 + cfg1 + 4 ID bytes
  constant c_max_llc_frame_bytes : natural := c_llc_header_bytes + c_max_data_bytes;

  ---------------------------------------------------------------------------
  -- Registered state signals
  ---------------------------------------------------------------------------
  signal state            : std_logic_vector(2 downto 0);
  signal frame_buf        : t_legacy_frame;
  signal frame_len_bytes  : natural range 0 to c_max_llc_frame_bytes;
  signal capture_index    : natural range 0 to c_legacy_frame_len - 1;
  signal tx_index         : natural range 0 to c_max_llc_frame_bytes - 1;
  signal mac_status_armed : boolean;

begin

  -- ISO 8.1.4.5: bus-off recovery is gated by normal_mode = '1'. We always
  -- request normal operation; user-initiated abort (abort_request) is
  -- handled inside the FSM rather than via normal_mode.
  fce_o.normal_mode <= '1';

  p_llc_fsm : process (clk) is

    variable ide_v      : std_logic;
    variable fdf_v      : std_logic;
    variable dlc_v      : natural range 0 to c_dlc_max;
    variable data_len_v : natural;
    variable is_ext_v   : boolean;

    -- Conversion results computed on EOP, written into frame_buf
    variable cfg0_v : std_logic_vector(c_byte_width - 1 downto 0);
    variable cfg1_v : std_logic_vector(c_byte_width - 1 downto 0);
    variable id0_v  : std_logic_vector(c_byte_width - 1 downto 0);
    variable id1_v  : std_logic_vector(c_byte_width - 1 downto 0);
    variable id2_v  : std_logic_vector(c_byte_width - 1 downto 0);
    variable id3_v  : std_logic_vector(c_byte_width - 1 downto 0);

    -----------------------------------------------------------------------
    -- Build internal cfg1 (DLC nibble) from legacy byte 4.
    -----------------------------------------------------------------------
    procedure build_config_byte_1 (
      buf    : in    t_legacy_frame;
      result : out   std_logic_vector(c_byte_width - 1 downto 0)
    ) is
    begin
      result(7 downto 4) := buf(c_legacy_fmt_dlc_byte)(3 downto 0);
      result(3 downto 0) := "0000";
    end procedure build_config_byte_1;

    -----------------------------------------------------------------------
    -- Repack ID from right-aligned legacy bytes 0..3 to left-aligned
    -- internal bytes 2..5 (32 bits, MSB first).
    -----------------------------------------------------------------------
    procedure repack_id (
      buf    : in    t_legacy_frame;
      is_ext : in    boolean;
      id0    : out   std_logic_vector(c_byte_width - 1 downto 0);
      id1    : out   std_logic_vector(c_byte_width - 1 downto 0);
      id2    : out   std_logic_vector(c_byte_width - 1 downto 0);
      id3    : out   std_logic_vector(c_byte_width - 1 downto 0)
    ) is
      variable raw_id_v : std_logic_vector(31 downto 0);
    begin
      raw_id_v := (others => '0');
      if (is_ext) then
        raw_id_v(31 downto 3)  := buf(0)(4 downto 0) & buf(1) & buf(2) & buf(3);
      else
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
        mac_status_armed <= false;
        frame_buf        <= (others => (others => '0'));

        llc_user_o.avalon_st_sink.ready      <= '1';
        llc_user_o.transfer_status           <= c_ongoing;
        mac_o.avalon_st_source.data          <= (others => '0');
        mac_o.avalon_st_source.valid         <= '0';
        mac_o.avalon_st_source.startofpacket <= '0';
        mac_o.avalon_st_source.endofpacket   <= '0';
      else
        -- Defaults
        llc_user_o.avalon_st_sink.ready      <= '0';
        mac_o.avalon_st_source.valid         <= '0';
        mac_o.avalon_st_source.startofpacket <= '0';
        mac_o.avalon_st_source.endofpacket   <= '0';

        -- Bus-off has priority over the active TX states. Idle/capture stay
        -- functional so the user can still submit a frame; it will sit in
        -- the buffer until bus-off recovery completes.
        if (fce_i.bus_off = '1') and
           (state = c_st_send or state = c_st_wait_result or state = c_st_wait_idle) then
          state            <= c_st_bus_off_hold;
          mac_status_armed <= false;
        else
          case state is

            -----------------------------------------------------------------
            -- Wait for SOP from user (legacy 71-byte frame).
            -----------------------------------------------------------------
            when c_st_idle =>
              llc_user_o.avalon_st_sink.ready <= '1';
              mac_status_armed                <= false;
              frame_len_bytes                 <= 0;
              capture_index                   <= 0;
              tx_index                        <= 0;

              if (llc_user_i.avalon_st_source.valid = '1' and llc_user_i.avalon_st_source.startofpacket = '1') then
                if (llc_user_i.avalon_st_source.endofpacket = '1') then
                  -- Single-byte SOP+EOP is invalid for a 71-byte frame.
                  llc_user_o.transfer_status <= c_aborted;
                  state                      <= c_st_idle;
                else
                  llc_user_o.transfer_status <= c_ongoing;
                  frame_buf(0)               <= llc_user_i.avalon_st_source.data;
                  capture_index              <= 1;
                  state                      <= c_st_capture;
                end if;
              end if;

            -----------------------------------------------------------------
            -- Buffer 71 legacy bytes; convert header on EOP.
            -----------------------------------------------------------------
            when c_st_capture =>
              llc_user_o.avalon_st_sink.ready <= '1';

              if (llc_user_i.abort_request = '1') then
                llc_user_o.transfer_status <= c_aborted;
                state                      <= c_st_idle;
              elsif (llc_user_i.avalon_st_source.valid = '1') then
                if (capture_index < c_legacy_frame_len) then
                  frame_buf(capture_index) <= llc_user_i.avalon_st_source.data;

                  if (llc_user_i.avalon_st_source.endofpacket = '1') then
                    if (capture_index = c_legacy_frame_len - 1) then
                      -- Full 71 bytes received -- convert to internal format.
                      ide_v    := frame_buf(c_legacy_fmt_dlc_byte)(6);
                      fdf_v    := frame_buf(c_legacy_fmt_dlc_byte)(5);
                      is_ext_v := ide_v = '1';

                      -- cfg0 needs byte 70 (current input) and byte 4 (already buffered).
                      cfg0_v(c_llc_frame_ide)  := ide_v;
                      cfg0_v(c_llc_frame_fdf)  := fdf_v;
                      cfg0_v(5)                := '0';
                      cfg0_v(c_llc_frame_ftyp) := llc_user_i.avalon_st_source.data(0);  -- RTR
                      cfg0_v(c_llc_frame_esi)  := llc_user_i.avalon_st_source.data(1);  -- ESI
                      cfg0_v(c_llc_frame_brs)  := llc_user_i.avalon_st_source.data(2);  -- BRS
                      cfg0_v(1 downto 0)       := "00";

                      build_config_byte_1(frame_buf, cfg1_v);
                      repack_id(frame_buf, is_ext_v, id0_v, id1_v, id2_v, id3_v);

                      dlc_v      := to_integer(unsigned(frame_buf(c_legacy_fmt_dlc_byte)(3 downto 0)));
                      data_len_v := dlc_to_data_length(dlc_v, fdf_v);

                      -- Shift legacy data bytes (5..) up to internal position (6..).
                      for i in data_len_v - 1 downto 0 loop
                        frame_buf(c_llc_header_bytes + i) <= frame_buf(c_legacy_data_offset + i);
                      end loop;

                      frame_buf(0) <= cfg0_v;
                      frame_buf(1) <= cfg1_v;
                      frame_buf(2) <= id0_v;
                      frame_buf(3) <= id1_v;
                      frame_buf(4) <= id2_v;
                      frame_buf(5) <= id3_v;

                      frame_len_bytes <= c_llc_header_bytes + data_len_v;
                      tx_index        <= 0;
                      state           <= c_st_send;
                    else
                      -- EOP arrived before byte 70 -- malformed frame.
                      llc_user_o.transfer_status <= c_aborted;
                      state                      <= c_st_idle;
                    end if;
                  elsif (capture_index < c_legacy_frame_len - 1) then
                    capture_index <= capture_index + 1;
                  else
                    -- Reached byte 70 without EOP -- malformed frame.
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
            -- Stream the converted frame to the MAC.
            -----------------------------------------------------------------
            when c_st_send =>
              if (mac_i.transfer_status = c_ongoing) then
                mac_status_armed <= true;
              end if;

              -- Terminal status during streaming (e.g. bit error before
              -- the frame is fully written) is handled inline.
              if (mac_status_armed and mac_i.transfer_status /= c_ongoing) then
                case mac_i.transfer_status is
                  when c_lost_arb | c_disturbed =>
                    tx_index         <= 0;
                    mac_status_armed <= false;
                    state            <= c_st_wait_idle;
                  when others =>
                    llc_user_o.transfer_status <= mac_i.transfer_status;
                    state                      <= c_st_idle;
                end case;
              elsif (tx_index < frame_len_bytes) then
                mac_o.avalon_st_source.data  <= frame_buf(tx_index);
                mac_o.avalon_st_source.valid <= '1';
                if (tx_index = 0) then
                  mac_o.avalon_st_source.startofpacket <= '1';
                end if;
                if (tx_index = frame_len_bytes - 1) then
                  mac_o.avalon_st_source.endofpacket <= '1';
                end if;

                if (mac_i.avalon_st_sink.ready = '1') then
                  if (tx_index = frame_len_bytes - 1) then
                    state <= c_st_wait_result;
                  else
                    tx_index <= tx_index + 1;
                  end if;
                end if;
              else
                state <= c_st_wait_result;
              end if;

            -----------------------------------------------------------------
            -- Wait for the MAC's terminal transfer status.
            -----------------------------------------------------------------
            when c_st_wait_result =>
              if (not mac_status_armed) then
                if (mac_i.transfer_status = c_ongoing) then
                  mac_status_armed <= true;
                end if;
              else
                case mac_i.transfer_status is
                  when c_transmitted =>
                    llc_user_o.transfer_status <= c_transmitted;
                    state                      <= c_st_idle;
                  when c_lost_arb | c_disturbed =>
                    tx_index         <= 0;
                    mac_status_armed <= false;
                    state            <= c_st_wait_idle;
                  when c_aborted =>
                    llc_user_o.transfer_status <= c_aborted;
                    state                      <= c_st_idle;
                  when others =>
                    null;
                end case;
              end if;

            -----------------------------------------------------------------
            -- Wait for MAC ready before retransmission. Honour user abort
            -- between attempts.
            -----------------------------------------------------------------
            when c_st_wait_idle =>
              if (llc_user_i.abort_request = '1') then
                llc_user_o.transfer_status <= c_aborted;
                state                      <= c_st_idle;
              elsif (mac_i.avalon_st_sink.ready = '1') then
                tx_index <= 0;
                state    <= c_st_send;
              end if;

            -----------------------------------------------------------------
            -- Park during bus-off. Frame buffer is preserved; once the FCE
            -- clears bus_off the FSM resumes from byte 0 (TEC has been
            -- reset to 0 by the FCE recovery sequence).
            -----------------------------------------------------------------
            when c_st_bus_off_hold =>
              if (fce_i.bus_off = '0') then
                tx_index         <= 0;
                mac_status_armed <= false;
                state            <= c_st_wait_idle;
              end if;

            when others =>
              state <= c_st_idle;

          end case;
        end if;
      end if;
    end if;

  end process p_llc_fsm;

end architecture rtl;
