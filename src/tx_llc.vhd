--------------------------------------------------------------------------------
-- Title      : CAN LLC Transmit Controller
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : tx_llc.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Logical Link Control sub-layer for CAN transmission.
--              Implements ISO 11898-1 Section 6.4 responsibilities:
--   - Accepts L_Data.Request(Frame, Handle) from LLC user
--   - Buffers complete LLC frame locally before transmission
--   - Streams config bytes + data bytes to MAC via Avalon-ST (sop/eop/valid/ready)
--   - Monitors transfer_status from MAC for success/failure
--   - Re-arbitration: automatically restarts on lost_arbitration (no counter increment)
--   - Retransmission: retries on disturbed up to retransmission_limit_c (min 6)
--   - Abort: stops on user abort_request or retransmission limit reached
--
-- Config byte encoding:
--   Byte 0: FORMAT[7:5] & FTYP[4] & ESI[3] & BRS[2] & "00"
--   Byte 1: DLC[7:4] & "0000"
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_pkg.all;

entity tx_llc is
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- LLC user interface (application-facing)
    llc_user_i : in    llc_user_to_llc_if_t;
    llc_user_o : out   llc_to_llc_user_if_t;

    -- MAC interface (Avalon-ST to tx_mac_ser)
    mac_i : in    mac_to_llc_if_t;
    mac_o : out   llc_to_mac_if_t
  );
end entity tx_llc;

architecture rtl of tx_llc is

  -- FSM state register
  signal llc_state : tx_llc_state_t;

  -- Frame buffer (latched on tx_request)
  signal frame_buf : llc_frame_t;

  -- Byte counter for data streaming
  signal byte_count : integer range 0 to max_data_bytes_c - 1;

  -- Total number of data bytes to send for current frame
  signal data_byte_count : integer range 0 to max_data_bytes_c;

  -- Retransmission counter (reset on success or new request)
  signal retx_count : integer range 0 to retransmission_limit_c;

  -- Config bytes (built from frame buffer)
  signal config_byte_0 : byte_t;
  signal config_byte_1 : byte_t;

  -- Helper: encode can_format_t to 3-bit config byte format field
  function format_to_encoding (
    fmt : can_format_t
  ) return std_logic_vector is
  begin

    case fmt is
      when cc_basic    => return llc_frame_format_cb_encoding;
      when cc_extended => return llc_frame_format_ce_encoding;
      when fd_basic    => return llc_frame_format_fb_encoding;
      when fd_extended => return llc_frame_format_fe_encoding;
      when others      => return "000";
    end case;

  end function format_to_encoding;

begin

  -- Build config bytes from frame buffer
  config_byte_0 <= format_to_encoding(frame_buf.format)
                    & frame_buf.ftyp
                    & frame_buf.esi
                    & frame_buf.brs
                    & "00";
  config_byte_1 <= frame_buf.dlc & "0000";

  -- Main clocked process
  p_llc_fsm : process (clk) is

    variable data_byte_index_v : integer;
    variable data_bit_start_v  : integer;

  begin

    if rising_edge(clk) then
      if (rst = '1') then
        llc_state <= idle;
        byte_count      <= 0;
        data_byte_count <= 0;
        retx_count      <= 0;
        frame_buf       <= (id     => (others => '0'),
                            format => unknown,
                            ftyp   => '0',
                            brs    => '0',
                            esi    => '0',
                            dlc    => (others => '0'),
                            data   => (others => '0'));

        -- Default outputs
        llc_user_o.transfer_status <= ongoing;
        llc_user_o.tx_ready        <= '1';
        mac_o.avalon_st_source.data  <= (others => '0');
        mac_o.avalon_st_source.valid <= '0';
        mac_o.avalon_st_source.sop   <= '0';
        mac_o.avalon_st_source.eop   <= '0';
      else
        -- Default: clear Avalon-ST valid (one-shot handshake)
        mac_o.avalon_st_source.valid <= '0';
        mac_o.avalon_st_source.sop   <= '0';
        mac_o.avalon_st_source.eop   <= '0';

        -- Abort handling: only in states where MAC hasn't started processing
        if ((llc_state = send_config_0 or llc_state = wait_for_idle)
            and llc_user_i.abort_request = '1') then
          llc_user_o.transfer_status <= aborted;
          llc_user_o.tx_ready        <= '1';
          llc_state                  <= idle;
        else

          case llc_state is

            -- =============================================================
            -- IDLE: Wait for tx_request from LLC user
            -- =============================================================
            when idle =>
              llc_user_o.tx_ready <= '1';

              if (llc_user_i.tx_request = '1') then
                -- Latch frame into buffer
                frame_buf       <= llc_user_i.frame;
                retx_count      <= 0;
                byte_count      <= 0;
                data_byte_count <= dlc_to_data_length(
                                     dlc_t(to_integer(unsigned(llc_user_i.frame.dlc))),
                                     llc_user_i.frame.format
                                   );
                llc_user_o.tx_ready        <= '0';
                llc_user_o.transfer_status <= ongoing;
                llc_state                  <= send_config_0;
              end if;

            -- =============================================================
            -- SEND_CONFIG_0: Stream config byte 0 with sop='1'
            -- =============================================================
            when send_config_0 =>
              llc_user_o.tx_ready <= '0';
              mac_o.avalon_st_source.data  <= config_byte_0;
              mac_o.avalon_st_source.valid <= '1';
              mac_o.avalon_st_source.sop   <= '1';
              mac_o.avalon_st_source.eop   <= '0';

              if (mac_i.avalon_st_sink.ready = '1') then
                llc_state <= send_config_1;
              end if;

            -- =============================================================
            -- SEND_CONFIG_1: Stream config byte 1
            -- =============================================================
            when send_config_1 =>
              llc_user_o.tx_ready <= '0';
              mac_o.avalon_st_source.data  <= config_byte_1;
              mac_o.avalon_st_source.valid <= '1';
              mac_o.avalon_st_source.sop   <= '0';
              mac_o.avalon_st_source.eop   <= '0';

              if (mac_i.avalon_st_sink.ready = '1') then
                if (data_byte_count = 0) then
                  -- No data bytes: send eop with config byte 1
                  mac_o.avalon_st_source.eop <= '1';
                  llc_state                  <= wait_for_result;
                else
                  byte_count <= 0;
                  llc_state  <= send_data;
                end if;
              end if;

            -- =============================================================
            -- SEND_DATA: Stream data bytes sequentially
            -- =============================================================
            when send_data =>
              llc_user_o.tx_ready <= '0';

              -- Extract data byte N from frame_buf.data (MSB-first: byte 0 = data(511 downto 504))
              data_byte_index_v := byte_count;
              data_bit_start_v  := frame_buf.data'left - data_byte_index_v * 8;

              mac_o.avalon_st_source.data  <= frame_buf.data(data_bit_start_v downto data_bit_start_v - 7);
              mac_o.avalon_st_source.valid <= '1';
              mac_o.avalon_st_source.sop   <= '0';

              -- Last data byte gets eop
              if (byte_count = data_byte_count - 1) then
                mac_o.avalon_st_source.eop <= '1';
              else
                mac_o.avalon_st_source.eop <= '0';
              end if;

              if (mac_i.avalon_st_sink.ready = '1') then
                if (byte_count = data_byte_count - 1) then
                  llc_state <= wait_for_result;
                else
                  byte_count <= byte_count + 1;
                end if;
              end if;

            -- =============================================================
            -- WAIT_FOR_RESULT: Monitor MAC transfer_status
            -- =============================================================
            when wait_for_result =>
              llc_user_o.tx_ready <= '0';

              case mac_i.transfer_status is
                when transmitted =>
                  llc_user_o.transfer_status <= transmitted;
                  llc_user_o.tx_ready        <= '1';
                  llc_state                  <= idle;

                when lost_arbitration =>
                  -- Re-arbitration: restart without incrementing retx counter
                  llc_state <= wait_for_idle;

                when disturbed =>
                  -- Increment retransmission counter
                  if (retx_count >= retransmission_limit_c) then
                    llc_user_o.transfer_status <= aborted;
                    llc_user_o.tx_ready        <= '1';
                    llc_state                  <= idle;
                  else
                    retx_count <= retx_count + 1;
                    llc_state  <= wait_for_idle;
                  end if;

                when aborted =>
                  llc_user_o.transfer_status <= aborted;
                  llc_user_o.tx_ready        <= '1';
                  llc_state                  <= idle;

                when ongoing =>
                  null; -- Keep waiting
              end case;

            -- =============================================================
            -- WAIT_FOR_IDLE: Wait for MAC to return to ongoing (bus idle)
            -- =============================================================
            when wait_for_idle =>
              llc_user_o.tx_ready <= '0';

              if (mac_i.transfer_status = ongoing) then
                -- Restart transmission from config byte 0
                byte_count <= 0;
                llc_state  <= send_config_0;
              end if;

          end case;

        end if;
      end if;
    end if;

  end process p_llc_fsm;

end architecture rtl;
