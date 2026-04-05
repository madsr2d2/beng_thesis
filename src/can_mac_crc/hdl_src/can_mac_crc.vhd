--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   CRC engine wrapper for CAN/CAN-FD TX path. Instantiates
--                dedicated serial CRC engines for CRC-15, CRC-17, and CRC-21
--                and selects the appropriate output based on frame configuration.
--                Implements the algorithm from ISO 11898-1: Sec. 6.6.4.4.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-15  TMYAES    Initial implementation
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Serial CRC engine (ISO 11898-1: Sec. 6.6.4.4)

library ieee;
  use ieee.std_logic_1164.all;

entity gen_crc is
  generic (
    gc_data_width : natural          := 1;
    gc_crc_width  : natural          := 15;
    gc_crc_poly   : std_logic_vector := b"100_0101_1001_1001";
    gc_xor_value  : std_logic_vector := (14 downto 0 => '0');
    gc_crc_init   : std_logic_vector := (14 downto 0 => '0');
    gc_ref_input  : natural          := 0;
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

  signal crc_reg : std_logic_vector(gc_crc_width - 1 downto 0);

begin

  -- State register: accumulates CRC one bit per clock
  p_crc : process (clk_i) is
    variable v_crc_next : std_logic;
    variable v_shifted  : std_logic_vector(gc_crc_width - 1 downto 0);
  begin
    if rising_edge(clk_i) then
      if (reset_i = '1' or start_crc_i = '1') then
        crc_reg <= gc_crc_init(gc_crc_width - 1 downto 0);
      elsif (data_valid_i = '1') then
        v_crc_next := data_i(0) xor crc_reg(crc_reg'high);
        v_shifted  := crc_reg sll 1;
        if (v_crc_next = '1') then
          crc_reg <= v_shifted xor gc_crc_poly(gc_crc_width - 1 downto 0);
        else
          crc_reg <= v_shifted;
        end if;
      end if;
    end if;
  end process p_crc;

  -- Combinational output: present the updated CRC in the same cycle as
  -- the data input, matching the zero-latency interface the wrapper expects.
  p_crc_out : process (all) is
    variable v_fb      : std_logic;
    variable v_shifted : std_logic_vector(gc_crc_width - 1 downto 0);
  begin
    if (data_valid_i = '1') then
      v_fb      := data_i(0) xor crc_reg(crc_reg'high);
      v_shifted := crc_reg sll 1;
      if (v_fb = '1') then
        crc_o <= v_shifted xor gc_crc_poly(gc_crc_width - 1 downto 0);
      else
        crc_o <= v_shifted;
      end if;
    else
      crc_o <= crc_reg;
    end if;
  end process p_crc_out;

end architecture rtl;

-- Main CRC engine wrapper

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

entity can_mac_crc is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;
    crc_i : in    t_can_mac_fsm_crc_if_m2s;
    crc_o : out   t_can_mac_fsm_crc_if_s2m
  );
end entity can_mac_crc;

architecture rtl of can_mac_crc is

  signal crc15_out : std_logic_vector(c_crc_15_length - 1 downto 0);
  signal crc17_out : std_logic_vector(c_crc_17_length - 1 downto 0);
  signal crc21_out : std_logic_vector(c_crc_21_length - 1 downto 0);

begin


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
      start_crc_i  => '0',
      data_i(0)    => crc_i.data_cc,
      data_valid_i => crc_i.valid_cc,
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
      start_crc_i  => '0',
      data_i(0)    => crc_i.data_fd,
      data_valid_i => crc_i.valid_fd,
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
      start_crc_i  => '0',
      data_i(0)    => crc_i.data_fd,
      data_valid_i => crc_i.valid_fd,
      crc_o        => crc21_out
    );

  p_output_reg : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        crc_o.crc <= (others => '0');
      else
        case crc_i.crc_poly_select is
          when c_crc_poly_15_sel =>
            crc_o.crc <= crc15_out & (c_crc_21_length - 1 - c_crc_15_length downto 0 => '0');
          when c_crc_poly_17_sel =>
            crc_o.crc <= crc17_out & (c_crc_21_length - 1 - c_crc_17_length downto 0 => '0');
          when c_crc_poly_21_sel =>
            crc_o.crc <= crc21_out;
          when others =>
            crc_o.crc <= (others => '0');
        end case;
      end if;
    end if;

  end process p_output_reg;

end architecture rtl;

-- eof
