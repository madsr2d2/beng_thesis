library ieee;
  use ieee.std_logic_1164.all;

entity shift_reg is
  generic (
    width : integer := 8
  );
  port (
    clk  : in    std_logic;
    rst  : in    std_logic;
    ctrl : in    std_logic_vector(1 downto 0);
    d    : in    std_logic_vector(width - 1 downto 0);
    q    : out   std_logic_vector(width - 1 downto 0)
  );
end entity shift_reg;

architecture rtl of shift_reg is

  signal reg : std_logic_vector(width - 1 downto 0);

begin

  shift_proc : process (clk, rst) is
  begin

    if (rst = '1') then
      reg <= (others => '0');
    elsif (rising_edge(clk)) then
      case ctrl is
        when "00" =>
          reg <= reg;                            -- No operation
        when "01" =>
          reg <= reg(width - 2 downto 0) & '0';  -- Shift in 0 from right
        when "10" =>
          reg <= reg(width - 2 downto 0) & '1';  -- Shift in 1 from right
        when "11" =>
          reg <= d;                              -- load
        when others =>
          null;
      end case;
    end if;

  end process shift_proc;

  q <= reg;

end architecture rtl;

