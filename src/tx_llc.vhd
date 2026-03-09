--------------------------------------------------------------------------------
-- Title      : CAN Bus LLC Transmit Controller
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : tx_llc.vhd
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
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;

entity tx_llc is
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- LLC user interface (Avalon-ST input stream)
    llc_user_i : in    llc_user_to_llc_if_t;
    llc_user_o : out   llc_to_llc_user_if_t;

    -- MAC interface (Avalon-ST output stream)
    mac_i : in    mac_to_llc_if_t;
    mac_o : out   llc_to_mac_if_t
  );
end entity tx_llc;

architecture rtl of tx_llc is

  ---------------------------------------------------------------------------
  -- Constants
  ---------------------------------------------------------------------------
  constant llc_header_bytes_c    : integer := 6; -- cfg0+cfg1+id3..id0
  constant max_llc_frame_bytes_c : integer := llc_header_bytes_c + max_data_bytes_c;

  ---------------------------------------------------------------------------
  -- Types
  ---------------------------------------------------------------------------
  type llc_frame_buffer_t is array (0 to max_llc_frame_bytes_c - 1) of byte_t;

  ---------------------------------------------------------------------------
  -- Registered state signals (driven by state_update)
  ---------------------------------------------------------------------------
  signal state              : tx_llc_state_t;
  signal frame_buf          : llc_frame_buffer_t;
  signal frame_len_bytes    : integer range 0 to max_llc_frame_bytes_c;
  signal capture_index      : integer range 0 to max_llc_frame_bytes_c - 1;
  signal tx_index           : integer range 0 to max_llc_frame_bytes_c - 1;
  signal expected_len_bytes : integer range 0 to max_llc_frame_bytes_c;
  signal retx_count         : integer range 0 to retransmission_limit_c;
  signal mac_status_armed   : boolean;

  ---------------------------------------------------------------------------
  -- Debug signals
  ---------------------------------------------------------------------------
  signal state_dbg      : integer range 0 to 4 := 0;
  signal mac_status_dbg : integer range 0 to 4 := 0;

  ---------------------------------------------------------------------------
  -- Procedures and Functions
  ---------------------------------------------------------------------------
  function decode_llc_format (
    cfg0 : byte_t
  ) return can_format_t is
  begin

    case cfg0(llc_frame_config_byte_0_format_start downto llc_frame_config_byte_0_format_end) is
      when llc_fmt_cb_c => return cc_basic;
      when llc_fmt_ce_c => return cc_extended;
      when llc_fmt_fb_c => return fd_basic;
      when llc_fmt_fe_c => return fd_extended;
      when others => return unknown;
    end case;

  end function decode_llc_format;

begin

  with state select state_dbg <=
    0 when idle,
    1 when capture_frame,
    2 when send_frame,
    3 when wait_for_result,
    4 when wait_for_idle;

  with mac_i.transfer_status select mac_status_dbg <=
    0 when ongoing,
    1 when transmitted,
    2 when disturbed,
    3 when lost_arbitration,
    4 when aborted;

  p_llc_fsm : process (clk) is

    variable accepted_idx_v : integer;
    variable expected_len_v : integer;
    variable format_v       : can_format_t;
    variable dlc_v          : dlc_t;
    variable data_len_v     : integer;
    variable cfg_valid_v    : boolean;

  begin

    if rising_edge(clk) then
      if (rst = '1') then
        state              <= idle;
        frame_len_bytes    <= 0;
        capture_index      <= 0;
        tx_index           <= 0;
        expected_len_bytes <= 0;
        retx_count         <= 0;
        mac_status_armed   <= false;
        frame_buf          <= (others => (others => '0'));

        llc_user_o.avalon_st_sink.ready <= '1';
        llc_user_o.transfer_status      <= ongoing;

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
          when idle =>
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
                llc_user_o.transfer_status <= aborted;
                state                      <= idle;
              else
                llc_user_o.transfer_status <= ongoing;
                frame_buf(0)               <= llc_user_i.avalon_st_source.data;
                capture_index              <= 1;
                state                      <= capture_frame;
              end if;
            end if;

          when capture_frame =>
            llc_user_o.avalon_st_sink.ready <= '1';

            -- Abort only while still buffering and MAC has not started.
            if (llc_user_i.abort_request = '1') then
              llc_user_o.transfer_status <= aborted;
              state                      <= idle;
            elsif (llc_user_i.avalon_st_source.valid = '1') then
              expected_len_v := expected_len_bytes;
              cfg_valid_v    := true;
              if (capture_index < max_llc_frame_bytes_c) then
                frame_buf(capture_index) <= llc_user_i.avalon_st_source.data;
                accepted_idx_v           := capture_index;

                if (capture_index = 1) then
                  format_v := decode_llc_format(frame_buf(0));
                  if (format_v = unknown) then
                    cfg_valid_v                := false;
                    llc_user_o.transfer_status <= aborted;
                    state                      <= idle;
                  else
                    dlc_v              := dlc_t(
                                                to_integer(
                                                            unsigned(
                                                                      llc_user_i.avalon_st_source.data(
                                                                                                        llc_frame_config_byte_1_dlc_start downto llc_frame_config_byte_1_dlc_end
                                                                                                      )
                                                                    )
                                                          )
                                              );
                    data_len_v         := dlc_to_data_length(dlc_v, format_v);
                    expected_len_v     := llc_header_bytes_c + data_len_v;
                    expected_len_bytes <= expected_len_v;
                  end if;
                end if;

                if (not cfg_valid_v) then
                  null;
                elsif (llc_user_i.avalon_st_source.eop = '1' and accepted_idx_v + 1 < llc_header_bytes_c) then
                  llc_user_o.transfer_status <= aborted;
                  state                      <= idle;
                elsif (llc_user_i.avalon_st_source.eop = '1') then
                  if (expected_len_v > 0 and accepted_idx_v + 1 = expected_len_v) then
                    frame_len_bytes <= expected_len_v;
                    tx_index        <= 0;
                    state           <= send_frame;
                  else
                    llc_user_o.transfer_status <= aborted;
                    state                      <= idle;
                  end if;
                elsif (expected_len_v > 0 and accepted_idx_v + 1 = expected_len_v) then
                  -- Expected end reached without EOP.
                  llc_user_o.transfer_status <= aborted;
                  state                      <= idle;
                elsif (capture_index < max_llc_frame_bytes_c - 1) then
                  capture_index <= capture_index + 1;
                else
                  llc_user_o.transfer_status <= aborted;
                  state                      <= idle;
                end if;
              else
                llc_user_o.transfer_status <= aborted;
                state                      <= idle;
              end if;
            end if;

          when send_frame =>
            if (mac_i.transfer_status = ongoing) then
              mac_status_armed <= true;
            end if;

            -- Monitor terminal status even while sending (ISO: arbitration loss/bit error can happen early)
            if (mac_status_armed and mac_i.transfer_status /= ongoing) then
              case mac_i.transfer_status is
                when lost_arbitration =>
                  tx_index <= 0;
                  state    <= send_frame;
                when disturbed =>
                  if (retx_count >= retransmission_limit_c) then
                    llc_user_o.transfer_status <= aborted;
                    state                      <= idle;
                  else
                    retx_count <= retx_count + 1;
                    state      <= wait_for_idle;
                  end if;
                when others =>
                  llc_user_o.transfer_status <= mac_i.transfer_status;
                  state                      <= idle;
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
                  state <= wait_for_result;
                else
                  tx_index <= tx_index + 1;
                end if;
              end if;
            else
              state <= wait_for_result;
            end if;

          when wait_for_result =>
            if (not mac_status_armed) then
              if (mac_i.transfer_status = ongoing) then
                mac_status_armed <= true;
              end if;
            else
              case mac_i.transfer_status is
                when transmitted =>
                  llc_user_o.transfer_status <= transmitted;
                  state                      <= idle;

                when lost_arbitration =>
                  tx_index <= 0;
                  state    <= send_frame;

                when disturbed =>
                  if (retx_count >= retransmission_limit_c) then
                    llc_user_o.transfer_status <= aborted;
                    state                      <= idle;
                  else
                    retx_count <= retx_count + 1;
                    state      <= wait_for_idle;
                  end if;

                when aborted =>
                  llc_user_o.transfer_status <= aborted;
                  state                      <= idle;

                when others =>
                  null;
              end case;
            end if;

          when wait_for_idle =>
            -- Abort is accepted between attempts.
            if (llc_user_i.abort_request = '1') then
              llc_user_o.transfer_status <= aborted;
              state                      <= idle;
            elsif (mac_i.avalon_st_sink.ready = '1') then
              tx_index <= 0;
              state    <= send_frame;
            end if;

          when others =>
            state <= idle;

        end case;
      end if;
    end if;

  end process p_llc_fsm;

end architecture rtl;
