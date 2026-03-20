--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   MAC serializer for CAN/CAN-FD TX path. Serializes LLC frame bytes into a bit stream for the MAC FSM.
--                
--                **Internal** LLC frame format: (variable length, streamed by can_llc_tx to can_mac_ser_tx):
--                  Byte 0:       [7:5]=FORMAT, [4]=FTYP(RTR), [3]=ESI, [2]=BRS, [1:0]=00
--                  Byte 1:       [7:4]=DLC, [3:0]=0000
--                  Bytes 2-5:    ID (32-bit, MSB first, left-aligned; CB/FB uses [31:21], CE/FE uses [31:3])
--                  Bytes 6+:     Data (DLC count, no padding)
--                  Note: The **internal** LLC frame format is different from the LLC frame format (used for the LLC-User interface).  
--                        The **Internal** LLC frame format has config bytes first, allowing the MAC FSM to start streaming out ID/DATA bits as soon as possible. 
-- 
--                Responsibilities:
--                  1) Extract LLC metadata (format, DLC, flags) from config bytes and register at the MAC FSM interface.
--                  2) Serialize LLC frame ID and data bytes and present as individual bits to the MAC FSM.
--                  3) Skip padding bits in the 32-bit ID stream (unused MSBs above the actual ID width).
--                  4) Forward transfer status from MAC FSM back to LLC.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-16  TMYAES    [TRIT-4340] Initial implementation
--                2026-03-20  TMYAES    [TRIT-4345] Update: Removed procedures, changed to new JIRA ID, formatting and naming adjustments.
--                2026-03-20  TMYAES    [TRIT-4345] Update: **Internal** LLC frame format description added to header.
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_man_global.all;
  use work.pk_can_types.all;

entity can_mac_ser_tx is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- LLC interface
    llc_i : in    t_can_llc_mac_tx_if_s2d;
    llc_o : out   t_can_llc_mac_tx_if_d2s;

    -- MAC FSM interface
    tx_mac_fsm_i : in    t_can_mac_ser_fsm_tx_if_m2s;
    tx_mac_fsm_o : out   t_can_mac_ser_fsm_tx_if_s2m
  );
end entity can_mac_ser_tx;

architecture rtl of can_mac_ser_tx is

------------------------------------------------------------------------ 
-- Types
------------------------------------------------------------------------
  type t_state is (
    s_load_config_byte_0,
    s_load_config_byte_1,
    s_load_llc_frame_byte,
    s_shift_out_bits
  );

------------------------------------------------------------------------ 
-- Signals
------------------------------------------------------------------------
  signal state                  : t_state;
  signal count                  : integer range 0 to t_byte'left + 1;  -- bit index within current byte
  signal llc_frame_buffer       : t_byte;
  signal config_byte_0          : t_byte;
  signal id_bits_remaining      : integer range 0 to c_base_id_width + c_extended_id_width;
  signal padding_bits_remaining : integer range 0 to c_llc_id_stream_width - c_base_id_width;

begin
  p_fsm : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        state                  <= s_load_config_byte_0;
        count                  <= 0;
        llc_frame_buffer       <= (others => '0');
        config_byte_0          <= (others => '0');
        id_bits_remaining      <= 0;
        padding_bits_remaining <= 0;

        -- Reset outputs
        llc_o        <= c_mac_to_llc_if_reset;
        tx_mac_fsm_o <= c_tx_mac_ser_to_fsm_if_reset;
      else
        -- Default outputs: clear valid, forward status, don't accept LLC data during shift
        tx_mac_fsm_o.valid         <= '0';
        llc_o.transfer_status      <= tx_mac_fsm_i.transfer_status;
        llc_o.avalon_st_sink.ready <= '0' when (state = s_shift_out_bits) else '1';

        if (tx_mac_fsm_i.transfer_status /= c_ongoing) then
          -- Transfer ended (completed, error, or abort): return to idle
          count <= 0;
          state <= s_load_config_byte_0;
        else
          case state is
            -----------------------------------------------------------------
            -- Capture first config byte from LLC on SOP.
            -----------------------------------------------------------------
            when s_load_config_byte_0 =>
              if (llc_i.avalon_st_source.valid = '1') and (llc_i.avalon_st_source.startofpacket = '1') then
                config_byte_0 <= llc_i.avalon_st_source.data;
                state         <= s_load_config_byte_1;
              end if;

            -----------------------------------------------------------------
            -- Capture second config byte, extract LLC metadata, and
            -- initialize ID/padding counters.
            -----------------------------------------------------------------
            when s_load_config_byte_1 =>
              if (llc_i.avalon_st_source.valid = '1') then
                -- Extract LLC metadata from config byte pair
                tx_mac_fsm_o.llc_metadata.format          <= config_byte_0(c_llc_frame_config_byte_0_format_start downto c_llc_frame_config_byte_0_format_end);
                tx_mac_fsm_o.llc_metadata.dlc_vector      <= llc_i.avalon_st_source.data(c_llc_frame_config_byte_1_dlc_start downto c_llc_frame_config_byte_1_dlc_end);
                tx_mac_fsm_o.llc_metadata.is_remote_frame <= config_byte_0(c_llc_frame_config_byte_0_ftyp);
                tx_mac_fsm_o.llc_metadata.has_brs         <= config_byte_0(c_llc_frame_config_byte_0_brs);
                tx_mac_fsm_o.llc_metadata.esi_enable      <= config_byte_0(c_llc_frame_config_byte_0_esi);
                state <= s_load_llc_frame_byte;

                -- ID is right-aligned in 32-bit stream: extended uses 29 bits, basic uses 11
                if (config_byte_0(c_llc_frame_config_byte_0_extended_bit) = '1') then
                  id_bits_remaining      <= c_base_id_width + c_extended_id_width;
                  padding_bits_remaining <= c_llc_id_stream_width - (c_base_id_width + c_extended_id_width);
                else
                  id_bits_remaining      <= c_base_id_width;
                  padding_bits_remaining <= c_llc_id_stream_width - c_base_id_width;
                end if;
              end if;

            -----------------------------------------------------------------
            -- Latch next byte from LLC and present MSB to MAC FSM.
            -----------------------------------------------------------------
            when s_load_llc_frame_byte =>
              if (llc_i.avalon_st_source.valid = '1') then
                count            <= 1;
                llc_frame_buffer <= llc_i.avalon_st_source.data;
                state <= s_shift_out_bits;

                -- Suppress valid during padding: MSBs above actual ID width are not frame data
                if (id_bits_remaining > 0) or (padding_bits_remaining = 0) then
                  tx_mac_fsm_o.data  <= llc_i.avalon_st_source.data(c_byte_width - 1);
                  tx_mac_fsm_o.valid <= '1';
                end if;
              end if;

            -----------------------------------------------------------------
            -- Shift out remaining bits of current byte. Skip padding bits
            -- in the ID stream without presenting them to the MAC FSM.
            -----------------------------------------------------------------
            when s_shift_out_bits =>
              -- Consume padding bits.
              if (id_bits_remaining = 0) and (padding_bits_remaining > 0) then
                padding_bits_remaining <= padding_bits_remaining - 1;

                if count = (c_byte_width - 1) then
                  count <= 0;
                  state <= s_load_llc_frame_byte;
                else
                  count <= count + 1;
                end if;

              -- Present normal bits to MAC FSM.
              else
                tx_mac_fsm_o.valid <= '1';
                if (tx_mac_fsm_i.ready = '1') then
                  if (id_bits_remaining > 0) then
                    id_bits_remaining <= id_bits_remaining - 1;
                  end if;

                  if count = (c_byte_width - 1) then
                    tx_mac_fsm_o.valid <= '0';
                    state <= s_load_llc_frame_byte;
                  else
                    -- MSB bit was presented in the load_llc_frame_byte state, so we start from MSB-1 here
                    tx_mac_fsm_o.data <= llc_frame_buffer(c_byte_width - 1 - count);
                    count             <= count + 1;
                  end if;
                end if;
              end if;
            
            when others =>
              state <= s_load_config_byte_0;
          end case;
        end if;
      end if;
    end if;
  end process p_fsm;
end architecture rtl;

-- eof
