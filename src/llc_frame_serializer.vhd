library ieee;
  use ieee.std_logic_1164.all;
  use work.can_pkg.all;

entity llc_frame_serializer is
  port (
    -- Clock and reset
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- LLC interface
    llc_i : in    llc_to_mac_if_t;
    llc_o : out   mac_to_llc_if_t;

    -- tx_mac_fsm interface
    -- TODO: Create this interface in can_pkg
    frame_info_o          : out   llc_frame_info_t;
    transfer_status_i     : in    transfer_status_t;
    tx_mac_state_i        : in    tx_mac_state_t;
    llc_frame_bit_o       : out   std_logic;
    llc_frame_bit_valid_o : out   std_logic;
    llc_frame_bit_ready_i : in    std_logic
  );
end entity llc_frame_serializer;

architecture rtl of llc_frame_serializer is

  signal llc_frame_buffer  : byte_t;
  signal state_reg         : tx_mac_llc_ctrl_state_t;
  signal count             : integer range byte_t'left downto 0;
  signal config_byte_reg_0 : byte_t;
  signal config_byte_reg_1 : byte_t;

begin

  tx_mac_llc_ctrl_p : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        llc_o.avalon_st_sink.ready <= '0';
        config_byte_reg_0          <= (others => '0');
        config_byte_reg_1          <= (others => '0');
        llc_frame_buffer           <= (others => '0');
        llc_frame_bit_o            <= '0';
        llc_frame_bit_valid_o      <= '0';
        state_reg                  <= load_config_byte_0;
        count                      <= llc_frame_buffer'left;
      else
        -- Defaults
        llc_frame_bit_valid_o <= '0';
        llc_o.transfer_status <= transfer_status_i;
        frame_info_o          <= get_frame_info(config_byte_reg_0, config_byte_reg_1);
        state_reg             <= state_reg;
        llc_frame_bit_o       <= llc_frame_buffer(llc_frame_buffer'left - 1);

        -- FSM
        case state_reg is
          when load_config_byte_0 =>
            llc_o.avalon_st_sink.ready <= '1';

            -- Grab config byte 0 from LLC and go to load_config_byte_1 state
            if (llc_i.avalon_st_source.valid = '1' and llc_i.avalon_st_source.sop = '1' and tx_mac_state_i = idle) then
              config_byte_reg_0 <= llc_i.avalon_st_source.data;
              state_reg         <= load_config_byte_1;
            end if;

          when load_config_byte_1 =>
            llc_o.avalon_st_sink.ready <= '1';

            -- Grab config byte 1 from LLC and go to load_llc_frame_byte state
            if (llc_i.avalon_st_source.valid = '1' and llc_i.avalon_st_source.sop = '0' and tx_mac_state_i = idle) then
              config_byte_reg_1 <= llc_i.avalon_st_source.data;
              state_reg         <= load_llc_frame_byte;
            end if;

          when load_llc_frame_byte =>
            llc_o.avalon_st_sink.ready <= '1';

            -- Grab next byte of the LLC frame and go to shift_out_bits state
            if (llc_i.avalon_st_source.valid = '1' and llc_i.avalon_st_source.sop = '0') then
              llc_frame_buffer           <= llc_i.avalon_st_source.data;
              llc_frame_bit_o            <= llc_i.avalon_st_source.data(llc_i.avalon_st_source.data'left);
              llc_frame_bit_valid_o      <= '1';
              llc_o.avalon_st_sink.ready <= '0';
              state_reg                  <= shift_out_bits;
            end if;

          when shift_out_bits =>
            llc_o.avalon_st_sink.ready <= '0';

            if (transfer_status_i /= ongoing) then
              -- Reset to load_config_byte_0 when the transfer is not ongoing
              state_reg <= load_config_byte_0;
              count     <= llc_frame_buffer'left;
            elsif (llc_frame_bit_ready_i = '1') then
              if (count = 0) then
                -- Last bit sent, ready for next byte
                state_reg <= load_llc_frame_byte;
                count     <= llc_frame_buffer'left;
              else
                -- Shift out MSB
                llc_frame_bit_valid_o <= '1';
                llc_frame_buffer      <= llc_frame_buffer sll 1;
                count                 <= count - 1;
              end if;
            end if;

          when others =>

        end case;
      end if;
    end if;

  end process tx_mac_llc_ctrl_p;

end architecture rtl;
