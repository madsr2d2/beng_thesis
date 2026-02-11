library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_pkg.all;

entity mac_tx is
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- LLC interface (Logical Link Control)
    llc_i : in    llc_to_mac_if_t;
    llc_o : out   mac_to_llc_if_t;

    -- PCS interface (Physical Coding Sublayer)
    pcs_i : in    pcs_mac_if_t;
    pcs_o : out   mac_pcs_if_t
  );
end entity mac_tx;

architecture rtl of mac_tx is

  -- mac_fsm state register
  signal mac_layer_tx_state : tx_mac_fsm_state_t;

  -- Counts the transmitted MAC frame bits - excluding stuff bits
  signal mac_frame_bit_count : integer  range 0 to  max_mac_frame_length_c;

  -- Holds the LLC frame config byte (byte 0)
  signal config_reg : std_logic_vector(byte_width_c - 1 downto 0);

  -- bs_fd interface
  signal bs_fd_to_mac_fsm : bs_fd_to_mac_fsm_if_t;
  signal mac_fsm_to_bs_fd : mac_fsm_to_bs_fd_if_t;

  -- Shift register A interface (This shift register holds the LLC frame byte begin transmitted)
  signal sr_a_to_mac_fsm : shift_reg_out_t;
  signal mac_fam_to_sr_a : shift_reg_in_if_t;

  -- Shift register B interface (This shift register holds the last 8 transmitted bits)
  signal sr_b_to_mac_fsm : shift_reg_out_t;
  signal mac_fam_to_sr_b : shift_reg_in_if_t;

  -- CRC interface
  signal crc_to_mac_fsm : crc_to_mac_fsm_if_t;
  signal mac_fsm_to_crc : mac_fsm_to_crc_if_t;

-- TX bit
-- signal tx_bit : std_logic;
-- RX bit
-- signal rx_bit : std_logic;

begin

  -- mac_fsm_to_bs_fd.data <= tx_bit;

  -- Synchronous MAC FSM
  p_mac_fsm : process (clk) is
  begin

    if rising_edge(clk) then
      if (rst = '1') then
        mac_layer_tx_state             <= idle;
        mac_frame_bit_count            <= 0;
        config_reg                     <= (others => '0');
        mac_fsm_to_bs_fd.data          <= '0';
        mac_fsm_to_bs_fd.data_valid    <= '0';
        mac_fsm_to_crc.shift           <= '0';
        mac_fsm_to_crc.data            <= '0';
        mac_fsm_to_crc.crc_poly_select <= (others => '0');
        mac_fam_to_sr_a.load           <= '0';
        mac_fam_to_sr_a.shift          <= '0';
        mac_fam_to_sr_a.data_in        <= (others => '0');
        mac_fam_to_sr_a.serial_in      <= '0';
        mac_fam_to_sr_b.load           <= '0';
        mac_fam_to_sr_b.shift          <= '0';
        mac_fam_to_sr_b.data_in        <= (others => '0');
        mac_fam_to_sr_b.serial_in      <= '0';
      else

        case mac_layer_tx_state is

          when idle =>
            if (llc_i.avalon_st_source.sop = '1') then
            -- TODO: load config reg with the first byte from the LLC layer and go to transmitting_mac_frame state
            end if;
          when transmitting =>
          when error =>
        end case;

      end if;
    end if;

  end process p_mac_fsm;

-- TODO: Uncomment when modules are implemented
-- bit_stuffer_fd_inst : entity work.bit_stuffer_fd
--   port map (
--     bs_fd_i => mac_fsm_to_bs_fd,
--     bs_fd_o => bs_fd_to_mac_fsm
--   );
--
-- shift_reg_a_inst : entity work.shift_reg
--   port map (
--     sr_i => mac_fam_to_sr_a,
--     sr_o => sr_a_to_mac_fsm
--   );
--
-- shift_reg_b_inst : entity work.shift_reg
--   port map (
--     sr_i => mac_fam_to_sr_b,
--     sr_o => sr_b_to_mac_fsm
--   );
--
-- crc_fd_inst : entity work.crc_fd
--   port map (
--     crc_i => mac_fsm_to_crc,
--     crc_o => crc_to_mac_fsm
--   );

end architecture rtl;
