library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

entity mod_n is
  generic (
    width_g   : positive := 8;
    modulus_g : positive := 8
  );
  port (
    data_i : in    std_logic_vector(width_g - 1 downto 0);
    data_o : out   std_logic_vector(integer(ceil(log2(real(modulus_g)))) - 1 downto 0)
  );
end entity mod_n;

architecture rtl of mod_n is

begin

  data_o <= std_logic_vector(to_unsigned(to_integer(unsigned(data_i)) mod modulus_g, data_o'length));

end architecture rtl;
