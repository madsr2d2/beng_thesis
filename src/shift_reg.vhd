library ieee;
  use ieee.std_logic_1164.all;
  use work.can_pkg.all;

entity shift_reg is
  port (
    sr_i : in    shift_reg_in_if_t;
    sr_o : out   shift_reg_out_t
  );
end entity shift_reg;

architecture rtl of shift_reg is

  constant width    : integer := 8;
  signal   count    : integer range 0 to width - 1;
  signal   data_reg : std_logic_vector(width - 1 downto 0);

begin

  shift_reg_proc : process (sr_i.clk, sr_i.rst) is
  begin

    if (sr_i.rst = '1') then
      data_reg        <= (others => '0');
      sr_o.serial_out <= '0';
      sr_o.empty      <= '0';
      count           <= width - 1;
    elsif (rising_edge(sr_i.clk)) then
      if (sr_i.load = '1') then
        data_reg        <= sr_i.data_in;                                            -- Load
        count           <= width - 1;                                               -- Reset count
        sr_o.empty      <= '0';                                                     -- Clear empty flag
        sr_o.serial_out <= sr_i.data_in(sr_i.data_in'left);                         -- Set serial_out to MSB of data_in
      else
        if (sr_i.shift = '1') then
          data_reg        <= data_reg(data_reg'left - 1 downto 0) & sr_i.serial_in; -- Shift in serial_in bit from right
          sr_o.serial_out <= data_reg(data_reg'left);                               -- Set serial_out to MSB of data_reg
          count           <= count - 1;                                             -- Decrement count
          if (count = 0) then
            sr_o.empty <= '1';                                                      -- Raise empty flag
            count      <= width - 1;
          else
            sr_o.empty <= '0';                                                      -- Clear empty flag
          end if;
        end if;
      end if;
    end if;

  end process shift_reg_proc;

  -- Assign parallel output
  sr_o.data_out <= data_reg;

end architecture rtl;

