library ieee;
  use ieee.std_logic_1164.all;

entity shift_reg_with_empty is
  generic (
    width : integer := 8
  );
  port (
    clk      : in    std_logic;
    rst      : in    std_logic;
    ctrl     : in    std_logic_vector(1 downto 0);
    d        : in    std_logic_vector(width - 1 downto 0);
    q        : out   std_logic_vector(width - 1 downto 0);
    max_tick : out   std_logic
  );
end entity shift_reg_with_empty;

architecture rtl of shift_reg_with_empty is

  signal count_rst : std_logic;
  signal count_en  : std_logic;

begin

  u_reg : entity work.shift_reg
    generic map (
      width => width
    )
    port map (
      clk  => clk,
      rst  => rst,
      ctrl => ctrl,
      d    => d,
      q    => q
    );

  u_counter : entity work.counter
    generic map (
      max_val => width
    )

    port map (
      clk      => clk,
      rst      => count_rst,
      en       => count_en,
      max_tick => max_tick
    );

  count_rst <= '1' when rst = '1' or ctrl = "11" else '0';
  count_en  <= '1' when ctrl = "01" or ctrl = "10" else '0';

end architecture rtl;

