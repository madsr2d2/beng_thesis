library ieee;
  use ieee.std_logic_1164.all;

entity parity is
  generic (
    width_g : positive := 8
  );
  port (
    data_i : in    std_logic_vector(width_g - 1 downto 0);
    data_o : out   std_logic
  );
end entity parity;

architecture rtl of parity is

begin

  process (data_i) is

    variable parity_bit_v : std_logic;

  begin

    parity_bit_v := '0';

    -- XOR all bits together for even parity
    for i in data_i'range loop

      parity_bit_v := parity_bit_v xor data_i(i);

    end loop;

    data_o <= parity_bit_v;

  end process;

end architecture rtl;
