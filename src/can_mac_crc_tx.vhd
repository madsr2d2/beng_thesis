--------------------------------------------------------------------------------
-- Title      : CAN FD CRC Engine Wrapper
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : can_mac_crc_tx.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Wrapper for the CAN/CAN-FD CRC generation logic.
--              Instantiates dedicated engines for CRC15, CRC17, and CRC21
--              and selects the appropriate output based on frame configuration.
--
-- Note       : Currently utilises a dummy gen_crc entity that mirrors the
--              interface of the legacy gen_crc CRC engine.  Replace the
--              can_mac_crc_dummy_tx architecture with the real implementation once
--              the serial-input polynomial engine is available.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;

--------------------------------------------------------------------------------
-- Dummy gen_crc Entity  (matches legacy gen_crc interface)
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;

entity can_mac_crc_dummy_tx is
  generic (
    gc_data_width  : integer                    := 1;
    gc_crc_width   : integer                    := 15;
    gc_crc_poly    : std_logic_vector           := b"100_0101_1001_1001";
    gc_xor_value   : std_logic_vector           := (14 downto 0 => '0');
    gc_crc_init    : std_logic_vector           := (14 downto 0 => '0');
    gc_ref_input   : integer                    := 0;
    gc_ref_output  : boolean                    := false
  );
  port (
    clk_i        : in    std_logic;
    reset_i      : in    std_logic;
    start_crc_i  : in    std_logic;
    data_i       : in    std_logic_vector(gc_data_width - 1 downto 0);
    data_valid_i : in    std_logic;
    crc_o        : out   std_logic_vector(gc_crc_width - 1 downto 0)
  );
end entity can_mac_crc_dummy_tx;

architecture rtl of can_mac_crc_dummy_tx is
begin

  -- Stub: return the polynomial constant as a fixed CRC result.
  -- Replace with real serial CRC engine once available.
  crc_o <= gc_crc_poly(gc_crc_width - 1 downto 0);

end architecture rtl;

--------------------------------------------------------------------------------
-- Main CRC Engine Wrapper
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;

entity can_mac_crc_tx is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;
    crc_i : in    can_mac_fsm_crc_tx_if_s2d_t;
    crc_o : out   can_mac_fsm_crc_tx_if_d2s_t
  );
end entity can_mac_crc_tx;

architecture rtl of can_mac_crc_tx is

  ---------------------------------------------------------------------------
  -- Internal CRC output signals
  ---------------------------------------------------------------------------
  signal crc15_out    : std_logic_vector(crc_15_length_c - 1 downto 0);
  signal crc17_out    : std_logic_vector(crc_17_length_c - 1 downto 0);
  signal crc21_out    : std_logic_vector(crc_21_length_c - 1 downto 0);
  signal data_valid_s : std_logic;
  signal start_crc_s  : std_logic;
  signal sel_crc15_s  : std_logic;
  signal sel_crc17_s  : std_logic;
  signal sel_crc21_s  : std_logic;

begin

  -- =========================================================================
  -- Component Instantiations
  -- =========================================================================
  u_crc15 : entity work.can_mac_crc_dummy_tx
    generic map (
      gc_data_width => 1,
      gc_crc_width  => crc_15_length_c,
      gc_crc_poly   => crc_poly_15_vec_c,
      gc_xor_value  => (crc_15_length_c - 1 downto 0 => '0'),
      gc_crc_init   => crc_init_15_vec_c,
      gc_ref_input  => 0,
      gc_ref_output => false
    )
    port map (
      clk_i        => clk_i,
      reset_i      => rst_i,
      start_crc_i  => start_crc_s and sel_crc15_s,
      data_i(0)    => crc_i.data,
      data_valid_i => data_valid_s and sel_crc15_s,
      crc_o        => crc15_out
    );

  u_crc17 : entity work.can_mac_crc_dummy_tx
    generic map (
      gc_data_width => 1,
      gc_crc_width  => crc_17_length_c,
      gc_crc_poly   => crc_poly_17_vec_c,
      gc_xor_value  => (crc_17_length_c - 1 downto 0 => '0'),
      gc_crc_init   => crc_init_17_vec_c,
      gc_ref_input  => 0,
      gc_ref_output => false
    )
    port map (
      clk_i        => clk_i,
      reset_i      => rst_i,
      start_crc_i  => start_crc_s and sel_crc17_s,
      data_i(0)    => crc_i.data,
      data_valid_i => data_valid_s and sel_crc17_s,
      crc_o        => crc17_out
    );

  u_crc21 : entity work.can_mac_crc_dummy_tx
    generic map (
      gc_data_width => 1,
      gc_crc_width  => crc_21_length_c,
      gc_crc_poly   => crc_poly_21_vec_c,
      gc_xor_value  => (crc_21_length_c - 1 downto 0 => '0'),
      gc_crc_init   => crc_init_21_vec_c,
      gc_ref_input  => 0,
      gc_ref_output => false
    )
    port map (
      clk_i        => clk_i,
      reset_i      => rst_i,
      start_crc_i  => start_crc_s and sel_crc21_s,
      data_i(0)    => crc_i.data,
      data_valid_i => data_valid_s and sel_crc21_s,
      crc_o        => crc21_out
    );

  fsm_sequential : process (clk_i) is
    variable v_crc_o       : can_mac_fsm_crc_tx_if_d2s_t;
    variable sel_v         : std_logic_vector(1 downto 0);
    variable data_valid_v  : std_logic;
    variable start_crc_v   : std_logic;
    variable sel_crc15_v   : std_logic;
    variable sel_crc17_v   : std_logic;
    variable sel_crc21_v   : std_logic;
  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        crc_o       <= (crc => (others => '0'));
        data_valid_s <= '0';
        start_crc_s  <= '0';
        sel_crc15_s  <= '0';
        sel_crc17_s  <= '0';
        sel_crc21_s  <= '0';
      else
        sel_v        := crc_i.crc_poly_select;
        data_valid_v := '1' when crc_i.valid else '0';
        start_crc_v  := '1' when crc_i.start else '0';
        sel_crc15_v  := '1' when sel_v = "00" else '0';
        sel_crc17_v  := '1' when sel_v = "01" else '0';
        sel_crc21_v  := '1' when sel_v = "10" else '0';
        v_crc_o := crc_o;

        case sel_v is
          when "00" =>
            v_crc_o.crc := crc15_out & (crc_vector_t'left - crc_15_length_c downto 0 => '0');
          when "01" =>
            v_crc_o.crc := crc17_out & (crc_vector_t'left - crc_17_length_c downto 0 => '0');
          when "10" =>
            v_crc_o.crc := crc21_out & (crc_vector_t'left - crc_21_length_c downto 0 => '0');
          when others =>
            v_crc_o.crc := (others => '0');
        end case;

        -- Register all outputs
        crc_o        <= v_crc_o;
        data_valid_s <= data_valid_v;
        start_crc_s  <= start_crc_v;
        sel_crc15_s  <= sel_crc15_v;
        sel_crc17_s  <= sel_crc17_v;
        sel_crc21_s  <= sel_crc21_v;
      end if;
    end if;

  end process fsm_sequential;

end architecture rtl;
