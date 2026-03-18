--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-15  TMYAES    [TRIT-4336] Initial implementation
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pk_man_global.all;
use work.pk_can_types.all;

entity can_mac_crc_tx is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;
    crc_i : in    t_can_mac_fsm_crc_tx_if_m2s;
    crc_o : out   t_can_mac_fsm_crc_tx_if_s2m
  );
end entity can_mac_crc_tx;

architecture rtl of can_mac_crc_tx is

  ---------------------------------------------------------------------------
  -- Internal CRC output signals
  ---------------------------------------------------------------------------
  signal crc15_out : std_logic_vector(c_crc_15_length - 1 downto 0);
  signal crc17_out : std_logic_vector(c_crc_17_length - 1 downto 0);
  signal crc21_out : std_logic_vector(c_crc_21_length - 1 downto 0);

  signal sel_crc15  : std_logic;
  signal sel_crc17  : std_logic;
  signal sel_crc21  : std_logic;
  signal start   : std_logic;
  signal valid   : std_logic;

begin

  sel_crc15 <= '1' when crc_i.crc_poly_select = "00" else '0';
  sel_crc17 <= '1' when crc_i.crc_poly_select = "01" else '0';
  sel_crc21 <= '1' when crc_i.crc_poly_select = "10" else '0';
  start  <= '1' when crc_i.start else '0';
  valid  <= '1' when crc_i.valid else '0';

  ---------------------------------------------------------------------------
  -- Component Instantiations
  ---------------------------------------------------------------------------
  u_crc15 : entity work.gen_crc
    generic map (
      gc_data_width => 1,
      gc_crc_width  => c_crc_15_length,
      gc_crc_poly   => c_crc_poly_15_vec,
      gc_xor_value  => (c_crc_15_length - 1 downto 0 => '0'),
      gc_crc_init   => c_crc_init_15_vec,
      gc_ref_input  => 0,
      gc_ref_output => false
    )
    port map (
      clk_i        => clk_i,
      reset_i      => rst_i,
      start_crc_i  => start and sel_crc15,
      data_i(0)    => crc_i.data,
      data_valid_i => valid and sel_crc15,
      crc_o        => crc15_out
    );

  u_crc17 : entity work.gen_crc
    generic map (
      gc_data_width => 1,
      gc_crc_width  => c_crc_17_length,
      gc_crc_poly   => c_crc_poly_17_vec,
      gc_xor_value  => (c_crc_17_length - 1 downto 0 => '0'),
      gc_crc_init   => c_crc_init_17_vec,
      gc_ref_input  => 0,
      gc_ref_output => false
    )
    port map (
      clk_i        => clk_i,
      reset_i      => rst_i,
      start_crc_i  => start and sel_crc17,
      data_i(0)    => crc_i.data,
      data_valid_i => valid and sel_crc17,
      crc_o        => crc17_out
    );

  u_crc21 : entity work.gen_crc
    generic map (
      gc_data_width => 1,
      gc_crc_width  => c_crc_21_length,
      gc_crc_poly   => c_crc_poly_21_vec,
      gc_xor_value  => (c_crc_21_length - 1 downto 0 => '0'),
      gc_crc_init   => c_crc_init_21_vec,
      gc_ref_input  => 0,
      gc_ref_output => false
    )
    port map (
      clk_i        => clk_i,
      reset_i      => rst_i,
      start_crc_i  => start and sel_crc21,
      data_i(0)    => crc_i.data,
      data_valid_i => valid and sel_crc21,
      crc_o        => crc21_out
    );

p_output_reg : process (clk_i) is

begin
  if rising_edge(clk_i) then
    if rst_i = '1' then
      crc_o.crc <= (others => '0');
      
    else
      -- Output mux: crc_o reflects the currently selected engine's registered output
      crc_o.crc <= crc15_out & (t_crc_vector'left - c_crc_15_length downto 0 => '0') when crc_i.crc_poly_select = "00" else
                   crc17_out & (t_crc_vector'left - c_crc_17_length downto 0 => '0') when crc_i.crc_poly_select = "01" else
                   crc21_out                                                         when crc_i.crc_poly_select = "10" else
                   (others => '0');
      
    end if;
  end if;
end process p_output_reg;


end architecture rtl;

-- eof