--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2025 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:   Stuff bit generator for CAN-bus. When valid_o is '1', stuff_bit_o contains the bit to be inserted in RX at the next sample_rx pulse.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2025-06-06  TMYAES:   [TRIT-3880] [FPGA] CAN-bus controller
--                2025-08-08  AFNI:     [TRIT-4042] [FPGA] Integrate can-bus controller into the io_ext
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pk_man_global.all;

entity can_stuff_bit_gen
 is
  port(
    clk_i             : in  std_logic;
    reset_i           : in  std_logic;
    rx_i              : in  std_logic;
    sample_rx_i       : in  std_logic;
    stuff_bit_o       : out std_logic;
    stuff_bit_valid_o : out std_logic
  );
end entity;

architecture rtl of can_stuff_bit_gen is
  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  constant c_max_consecutive_identical_bits : integer := 5;

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal rx_prev : std_logic;
  signal count   : integer range 0 to c_max_consecutive_identical_bits + 1;

begin

  ----------------------------------------------------------------------------
  -- Processes
  ----------------------------------------------------------------------------
  p_can_stuff_bit_gen : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if reset_i = '1' then
        stuff_bit_o       <= '1';
        stuff_bit_valid_o <= '0';
        rx_prev           <= '1';
        count             <= 0;
      else
        if sample_rx_i = '1' then
          stuff_bit_valid_o <= '0';
          count             <= 1;
          rx_prev           <= rx_i;

          if rx_i = rx_prev then
            count <= count + 1;
            if count = (c_max_consecutive_identical_bits - 1) then
              count             <= 0;
              stuff_bit_o       <= not rx_i;
              stuff_bit_valid_o <= '1';
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture;

-- eof
