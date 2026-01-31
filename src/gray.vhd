library ieee;
  use ieee.std_logic_1164.all;

entity gray is
  generic (
    width_g : positive := 3
  );
  port (
    data_i : in    std_logic_vector(width_g - 1 downto 0);
    data_o : out   std_logic_vector(width_g - 1 downto 0) -- data_i in gray code
  );
end entity gray;

architecture rtl of gray is

begin

  data_o(width_g - 1) <= data_i(width_g - 1);

  gen_gray : for i in 0 to width_g - 2 generate
    data_o(i) <= data_i(i) xor data_i(i + 1);
  end generate gen_gray;

end architecture rtl;

