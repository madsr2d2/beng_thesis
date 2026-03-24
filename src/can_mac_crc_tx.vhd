--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   CRC engine wrapper for CAN/CAN-FD TX path. Instantiates
--                dedicated engines for CRC-15, CRC-17, and CRC-21 and selects
--                the appropriate output based on frame configuration.
--
--                Note: Currently uses a dummy gen_crc entity that returns a
--                fixed polynomial value. Replace with the real serial-input
--                gen_crc engine once available.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-15  TMYAES    Initial implementation
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Dummy gen_crc entity (matches real gen_crc interface)

library ieee;
  use ieee.std_logic_1164.all;

entity gen_crc is
  generic (
    gc_data_width : integer          := 1;
    gc_crc_width  : integer          := 15;
    gc_crc_poly   : std_logic_vector := b"100_0101_1001_1001";
    gc_xor_value  : std_logic_vector := (14 downto 0 => '0');
    gc_crc_init   : std_logic_vector := (14 downto 0 => '0');
    gc_ref_input  : integer          := 0;
    gc_ref_output : boolean          := false
  );
  port (
    clk_i        : in    std_logic;
    reset_i      : in    std_logic;
    start_crc_i  : in    std_logic;
    data_i       : in    std_logic_vector(gc_data_width - 1 downto 0);
    data_valid_i : in    std_logic;
    crc_o        : out   std_logic_vector(gc_crc_width - 1 downto 0)
  );
end entity gen_crc;

architecture rtl of gen_crc is
begin
  -- Stub: return the polynomial constant as a fixed CRC result.
  crc_o <= gc_crc_poly(gc_crc_width - 1 downto 0);
end architecture rtl;

-- Main CRC engine wrapper

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
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

  signal crc15_out : std_logic_vector(c_crc_15_length - 1 downto 0);
  signal crc17_out : std_logic_vector(c_crc_17_length - 1 downto 0);
  signal crc21_out : std_logic_vector(c_crc_21_length - 1 downto 0);

  signal sel_crc15 : std_logic;
  signal sel_crc17 : std_logic;
  signal sel_crc21 : std_logic;
  signal valid     : std_logic;

begin

  sel_crc15 <= '1' when crc_i.crc_poly_select = "00" else '0';
  sel_crc17 <= '1' when crc_i.crc_poly_select = "01" else '0';
  sel_crc21 <= '1' when crc_i.crc_poly_select = "10" else '0';
  valid     <= crc_i.valid;

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
      start_crc_i  => rst_i and sel_crc15,
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
      start_crc_i  => rst_i and sel_crc17,
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
      start_crc_i  => rst_i and sel_crc21,
      data_i(0)    => crc_i.data,
      data_valid_i => valid and sel_crc21,
      crc_o        => crc21_out
    );

  p_output_reg : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        crc_o.crc <= (others => '0');
      else
        case crc_i.crc_poly_select is
          when "00" =>
            crc_o.crc <= crc15_out & (t_crc_vector'left - c_crc_15_length downto 0 => '0');
          when "01" =>
            crc_o.crc <= crc17_out & (t_crc_vector'left - c_crc_17_length downto 0 => '0');
          when "10" =>
            crc_o.crc <= crc21_out;
          when others =>
            crc_o.crc <= (others => '0');
        end case;
      end if;
    end if;

  end process p_output_reg;

end architecture rtl;

-- eof
