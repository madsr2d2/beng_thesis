library ieee;
  use ieee.std_logic_1164.all;

entity shift_reg is
  generic (
    width_g : integer := 8
  );
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- Control and status
    shift_i : in    std_logic;
    load_i  : in    std_logic;
    empty_o : out   std_logic;

    -- Data IO
    data_i   : in    std_logic_vector(width_g - 1 downto 0);
    data_o   : out   std_logic_vector(width_g - 1 downto 0);
    serial_i : in    std_logic;
    serial_o : out   std_logic
  );
end entity shift_reg;

architecture rtl of shift_reg is

  signal count : integer range 0 to width_g - 1;

begin

  shift_reg_proc : process (clk_i, rst_i) is
  begin

    if (rst_i = '1') then
      data_o   <= (others => '0');
      serial_o <= '0';
      count    <= 0;
      empty_o  <= '0';
    elsif (rising_edge(clk_i)) then
      if (load_i = '1') then
        data_o   <= data_i;                                                  -- load
        count    <= 0;                                                       -- reset count
        empty_o  <= '0';                                                     -- set empty flag low
        serial_o <= data_i(data_i'left);                                     -- Set serial_o to MSB of data_o
      else
        if (shift_i = '1') then
          data_o   <= data_o(data_o'left - 1 downto 0) & serial_i;           -- Shift in serial_i bit from right
          serial_o <= data_o(data_o'left);
          count    <= count + 1;
          if (count = data_o'left) then
            empty_o <= '1';
            count   <= 0;
          end if;
        end if;
      end if;
    end if;

  end process shift_reg_proc;

end architecture rtl;

