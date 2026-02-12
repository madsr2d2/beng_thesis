library ieee;
  use ieee.std_logic_1164.all;
  use work.can_pkg.all;

entity tx_mac_ser is
  port (
    -- Clock and reset
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- LLC interface
    llc_i : in    llc_to_mac_if_t;
    llc_o : out   mac_to_llc_if_t;

    -- tx_mac_fsm interface
    tx_mac_fsm_i : in    tx_mac_fsm_to_ser_if_t;
    tx_mac_fsm_o : out   tx_mac_ser_to_fsm_if_t
  );
end entity tx_mac_ser;

architecture rtl of tx_mac_ser is

  -- Frame buffer for serialization
  signal llc_frame_buffer : byte_t;
  -- State register: load config bytes → load data bytes → shift bits
  signal state_reg : tx_mac_ser_state_t;
  -- Remaining bits to shift (7..0, counting down)
  signal count : integer range byte_t'left downto 0;
  -- Config byte 0: FORMAT[7:5], FTYP[4], ESI[3], BRS[2]
  signal config_byte_reg_0 : byte_t;
  -- Config byte 1: DLC[7:4]
  signal config_byte_reg_1 : byte_t;
  -- Cached frame parameters (calculated once per frame, reduces redundant calculations)
  signal frame_params_reg : frame_params_t;
  signal params_valid : std_logic;

begin

  -- Serializer FSM: loads frame config and data bytes, then shifts bits to tx_mac_fsm
  -- Avalon-ST protocol: config byte 0 has SOP='1', all others have SOP='0'
  tx_mac_llc_ctrl_p : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        llc_o.avalon_st_sink.ready <= '0';
        config_byte_reg_0          <= (others => '0');
        config_byte_reg_1          <= (others => '0');
        llc_frame_buffer           <= (others => '0');
        tx_mac_fsm_o.data          <= dominant;
        tx_mac_fsm_o.valid         <= '0';
        state_reg                  <= load_config_byte_0;
        count                      <= llc_frame_buffer'left;
        frame_params_reg           <= frame_params_reset_c;
        params_valid               <= '0';
      else
        -- Defaults
        llc_o.avalon_st_sink.ready <= '0';
        tx_mac_fsm_o.valid         <= '0';
        llc_o.transfer_status      <= tx_mac_fsm_i.transfer_status;
        tx_mac_fsm_o.frame_info    <= get_frame_info(config_byte_reg_0, config_byte_reg_1);
        state_reg                  <= state_reg;
        frame_params_reg           <= frame_params_reg;
        params_valid               <= params_valid;

        -- FSM
        case state_reg is

          when load_config_byte_0 =>
            -- Config byte 0: wait for valid data with SOP='1'
            llc_o.avalon_st_sink.ready <= '1';
            if (llc_i.avalon_st_source.valid = '1' and llc_i.avalon_st_source.sop = '1') then
              config_byte_reg_0 <= llc_i.avalon_st_source.data;
              state_reg         <= load_config_byte_1;
            end if;

          when load_config_byte_1 =>
            -- Config byte 1: wait for valid data with SOP='0'
            llc_o.avalon_st_sink.ready <= '1';
            if (llc_i.avalon_st_source.valid = '1' and llc_i.avalon_st_source.sop = '0') then
              config_byte_reg_1 <= llc_i.avalon_st_source.data;
              -- Calculate frame parameters once (cached for all bits in this frame)
              frame_params_reg  <= calculate_frame_params(config_byte_reg_0, llc_i.avalon_st_source.data);
              params_valid      <= '1';
              state_reg         <= load_llc_frame_byte;
            end if;

          when load_llc_frame_byte =>
            llc_o.avalon_st_sink.ready <= '1';
            -- Data byte: wait for valid data with SOP='0'
            -- Load byte and output MSB immediately (no wasted cycle)
            if (llc_i.avalon_st_source.valid = '1' and llc_i.avalon_st_source.sop = '0') then
              llc_frame_buffer           <= llc_i.avalon_st_source.data;
              tx_mac_fsm_o.data          <= bit_to_polarity(llc_i.avalon_st_source.data(llc_i.avalon_st_source.data'left));
              tx_mac_fsm_o.valid         <= '1';
              state_reg                  <= shift_out_bits;
              llc_o.avalon_st_sink.ready <= '0';
            end if;

          when shift_out_bits =>
            -- Exit on transfer status change
            if (tx_mac_fsm_i.transfer_status /= ongoing) then
              state_reg    <= load_config_byte_0;
              count        <= llc_frame_buffer'left;
              params_valid <= '0';
            -- Output next bit when tx_mac_fsm is ready
            elsif (tx_mac_fsm_i.ready = '1') then
              if (count = 0) then
                -- All 8 bits sent (1 on load + 7 shifts), fetch next byte
                state_reg                  <= load_llc_frame_byte;
                count                      <= llc_frame_buffer'left;
                llc_o.avalon_st_sink.ready <= '1';
              else
                -- Output [left-1]; MSB already sent on load
                tx_mac_fsm_o.data  <= bit_to_polarity(llc_frame_buffer(llc_frame_buffer'left - 1));
                tx_mac_fsm_o.valid <= '1';
                llc_frame_buffer   <= llc_frame_buffer sll 1;
                count              <= count - 1;
              end if;
            end if;

          when others =>

        end case;
      end if;
    end if;

  end process tx_mac_llc_ctrl_p;

end architecture rtl;
