--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   MAC serializer for CAN/CAN-FD TX path. Serializes LLC frame
--                bytes into a bit stream for the MAC FSM.
--                Internal LLC frame format (variable length, streamed by
--                can_llc_tx to can_mac_ser_tx):
--                Byte 0:    [7:5]=FORMAT, [4]=FTYP(RTR), [3]=ESI, [2]=BRS
--                Byte 1:    [7:4]=DLC, [3:0]=0000
--                Bytes 2-5: ID (32-bit, MSB first, left-aligned)
--                Bytes 6+:  Data (DLC count, no padding)
--                Responsibilities:
--                1) Extract LLC metadata from config bytes and register at
--                the MAC FSM interface.
--                2) Serialize LLC frame ID and data bytes and present as
--                individual bits to the MAC FSM.
--                3) Skip padding bits in the 32-bit ID stream.
--                4) Forward transfer status from MAC FSM back to LLC.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-31  MRDSA     Converted to company header format
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

entity can_mac_ser_tx is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- LLC interface
    llc_i : in    t_can_llc_mac_tx_if_s2d;
    llc_o : out   t_can_llc_mac_tx_if_d2s;

    -- MAC FSM interface
    tx_mac_fsm_i : in    t_can_mac_ser_fsm_if_d2s;
    tx_mac_fsm_o : out   t_can_mac_ser_fsm_if_s2d
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
  signal count                  : natural range 0 to c_byte_width;
  signal llc_frame_buffer       :std_logic_vector(c_byte_width - 1 downto 0);
  signal id_bits_remaining      : natural range 0 to c_base_id_width + c_extended_id_width;
  signal padding_bits_remaining : natural range 0 to c_llc_id_field_width - c_base_id_width;

begin

  p_fsm : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        state                  <= s_load_config_byte_0;
        count                  <= 0;
        llc_frame_buffer       <= (others => '0');
        id_bits_remaining      <= 0;
        padding_bits_remaining <= 0;

        -- Reset outputs
        llc_o        <= c_mac_to_llc_if_reset;
        tx_mac_fsm_o <= c_ser_fsm_if_s2d_reset;
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
              if (llc_i.avalon_st_source.valid and llc_i.avalon_st_source.startofpacket) then
                tx_mac_fsm_o.llc_metadata.ide  <= llc_i.avalon_st_source.data(c_llc_frame_ide);
                tx_mac_fsm_o.llc_metadata.fdf  <= llc_i.avalon_st_source.data(c_llc_frame_fdf);
                tx_mac_fsm_o.llc_metadata.ftyp <= llc_i.avalon_st_source.data(c_llc_frame_ftyp);
                tx_mac_fsm_o.llc_metadata.brs  <= llc_i.avalon_st_source.data(c_llc_frame_brs);
                tx_mac_fsm_o.llc_metadata.esi  <= llc_i.avalon_st_source.data(c_llc_frame_esi);
                state                          <= s_load_config_byte_1;
              end if;

            -----------------------------------------------------------------
            -- Capture second config byte, extract LLC metadata, and
            -- initialize ID/padding counters.
            -----------------------------------------------------------------
            when s_load_config_byte_1 =>
              if (llc_i.avalon_st_source.valid) then
                -- Extract LLC metadata from config byte pair
                tx_mac_fsm_o.llc_metadata.dlc <= llc_i.avalon_st_source.data(c_llc_frame_dlc_start downto c_llc_frame_dlc_end);
                state                         <= s_load_llc_frame_byte;

                -- ID is right-aligned in 32-bit stream: extended uses 29 bits, basic uses 11
                if (tx_mac_fsm_o.llc_metadata.ide) then
                  id_bits_remaining      <= c_base_id_width + c_extended_id_width;
                  padding_bits_remaining <= c_llc_id_field_width - (c_base_id_width + c_extended_id_width);
                else
                  id_bits_remaining      <= c_base_id_width;
                  padding_bits_remaining <= c_llc_id_field_width - c_base_id_width;
                end if;
              end if;

            -----------------------------------------------------------------
            -- Latch next byte from LLC.
            -----------------------------------------------------------------
            when s_load_llc_frame_byte =>
              if (llc_i.avalon_st_source.valid and llc_o.avalon_st_sink.ready) then
                llc_o.avalon_st_sink.ready <= '0';
                count                      <= 0;
                llc_frame_buffer           <= llc_i.avalon_st_source.data;
                tx_mac_fsm_o.data          <= llc_i.avalon_st_source.data(c_byte_width - 1);
                state                      <= s_shift_out_bits;
              end if;

            -----------------------------------------------------------------
            -- Shift out bits of current byte. Skip padding bits in the ID
            -- stream without presenting them to the MAC FSM.
            -----------------------------------------------------------------
            when s_shift_out_bits =>
              if ((padding_bits_remaining > 0) and (id_bits_remaining = 0)) then
                -- Padding bit: skip silently
                padding_bits_remaining <= padding_bits_remaining - 1;

                if (count = (c_byte_width - 1)) then
                  count <= 0;
                  state <= s_load_llc_frame_byte;
                else
                  count <= count + 1;
                end if;
              else
                -- Real bit: present to MAC FSM
                tx_mac_fsm_o.valid <= '1';
                if (tx_mac_fsm_o.valid and tx_mac_fsm_i.ready) then
                  if (id_bits_remaining > 0) then
                    id_bits_remaining <= id_bits_remaining - 1;
                  end if;
                  if (count = (c_byte_width - 1)) then
                    tx_mac_fsm_o.valid <= '0';
                    state              <= s_load_llc_frame_byte;
                  else
                    -- Shift out and present next bit
                    llc_frame_buffer  <= llc_frame_buffer sll 1; -- shift left
                    tx_mac_fsm_o.data <= llc_frame_buffer(c_byte_width - 2);
                    count             <= count + 1;
                    if ((id_bits_remaining = 1) and (padding_bits_remaining > 0)) then
                      -- Nest bit is start of padding region
                      tx_mac_fsm_o.valid <= '0';
                    end if;
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
