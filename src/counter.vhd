library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

entity counter is
  generic (
    max_val : natural := 255
  );
  port (
    clk      : in    std_logic;
    rst      : in    std_logic;
    en       : in    std_logic;
    q        : out   std_logic_vector(integer(ceil(log2(real(max_val + 1)))) - 1 downto 0);
    max_tick : out   std_logic
  );
end entity counter;

architecture rtl of counter is

  function get_width (
    n : natural
  ) return integer is
  begin

    if (n = 0) then
      return 1;
    else
      return integer(ceil(log2(real(n + 1))));
    end if;

  end function get_width;

  constant width     : integer                      := get_width(max_val);
  constant max_val_c : unsigned(width - 1 downto 0) := to_unsigned(max_val, width);
  signal   count_reg : unsigned(width - 1 downto 0);

begin

  count_proc : process (clk, rst) is
  begin

    if (rst = '1') then
      count_reg <= (others => '0');
    elsif (rising_edge(clk)) then
      if (en = '1') then
        if (count_reg = max_val_c) then
          count_reg <= (others => '0');
        else
          count_reg <= count_reg + 1;
        end if;
      end if;
    end if;

  end process count_proc;

  q        <= std_logic_vector(count_reg);
  max_tick <= '1' when count_reg = max_val_c else
              '0';

end architecture rtl;
