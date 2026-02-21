--------------------------------------------------------------------------------
-- Title      : CAN FD CRC Engine Wrapper
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : crc_fd.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Wrapper for the CAN/CAN-FD CRC generation logic.
--              Instantiates dedicated engines for CRC15, CRC17, and CRC21
--              and selects the appropriate output based on frame configuration.
--
-- Note       : Currently utilizes dummy entities for architectural validation.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;

--------------------------------------------------------------------------------
-- Dummy CRC Entities
--------------------------------------------------------------------------------

-- Dummy CRC15
library ieee;
  use ieee.std_logic_1164.all;
  use work.can_types_pkg.all;
entity dummy_crc15 is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;
    valid : in    boolean;
    data  : in    std_logic;
    crc_o : out   crc_vector_t
  );
end entity dummy_crc15;
architecture rtl of dummy_crc15 is
begin
  crc_o(14 downto 0) <= crc_poly_15_vec_c(14 downto 0);
  crc_o(crc_o'left downto 15) <= (others => '0');
end architecture;

-- Dummy CRC17
library ieee;
  use ieee.std_logic_1164.all;
  use work.can_types_pkg.all;
entity dummy_crc17 is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;
    valid : in    boolean;
    data  : in    std_logic;
    crc_o : out   crc_vector_t
  );
end entity dummy_crc17;
architecture rtl of dummy_crc17 is
begin
  crc_o(19 downto 0) <= crc_poly_17_vec_c;
  crc_o(crc_o'left downto 20) <= (others => '0');
end architecture;

-- Dummy CRC21
library ieee;
  use ieee.std_logic_1164.all;
  use work.can_types_pkg.all;
entity dummy_crc21 is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;
    valid : in    boolean;
    data  : in    std_logic;
    crc_o : out   crc_vector_t
  );
end entity dummy_crc21;
architecture rtl of dummy_crc21 is
begin
  crc_o <= crc_poly_21_vec_c;
end architecture;

--------------------------------------------------------------------------------
-- Main CRC Engine Wrapper
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;

entity crc_fd is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;
    crc_i : in    mac_fsm_to_crc_if_t;
    crc_o : out   crc_to_mac_fsm_if_t
  );
end entity crc_fd;

architecture rtl of crc_fd is

  ---------------------------------------------------------------------------
  -- Internal signals
  ---------------------------------------------------------------------------
  signal crc15_out : crc_vector_t;
  signal crc17_out : crc_vector_t;
  signal crc21_out : crc_vector_t;

  ---------------------------------------------------------------------------
  -- Combinational next-cycle signals (driven by output_logic)
  ---------------------------------------------------------------------------
  signal next_crc_o : crc_to_mac_fsm_if_t;

begin

  -- =========================================================================
  -- Component Instantiations
  -- =========================================================================
  
  u_crc15 : entity work.dummy_crc15
    port map (
      clk_i => clk_i,
      rst_i => rst_i,
      valid => crc_i.valid,
      data  => crc_i.data,
      crc_o => crc15_out
    );

  u_crc17 : entity work.dummy_crc17
    port map (
      clk_i => clk_i,
      rst_i => rst_i,
      valid => crc_i.valid,
      data  => crc_i.data,
      crc_o => crc17_out
    );

  u_crc21 : entity work.dummy_crc21
    port map (
      clk_i => clk_i,
      rst_i => rst_i,
      valid => crc_i.valid,
      data  => crc_i.data,
      crc_o => crc21_out
    );

  ---------------------------------------------------------------------------
  -- Process 1: output_logic (combinational Mealy)
  ---------------------------------------------------------------------------
  output_logic : process (all) is
  begin

    -------------------------------------------------------------------------
    -- Output defaults: hold current registered values
    -------------------------------------------------------------------------
    next_crc_o <= crc_o;

    -------------------------------------------------------------------------
    -- Logic evaluation
    -------------------------------------------------------------------------
    case crc_i.crc_poly_select is
      when "00" =>
        next_crc_o.crc <= crc15_out;
      when "01" =>
        next_crc_o.crc <= crc17_out;
      when "10" =>
        next_crc_o.crc <= crc21_out;
      when others =>
        next_crc_o.crc <= (others => '0');
    end case;

  end process output_logic;

  ---------------------------------------------------------------------------
  -- Process 2: state_update (clocked)
  ---------------------------------------------------------------------------
  state_update : process (clk_i) is
  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        crc_o <= (crc => (others => '0'));
      else
        crc_o <= next_crc_o;
      end if;
    end if;

  end process state_update;

end architecture rtl;
