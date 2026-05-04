--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2024 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:   
--
-- Revision log:  Date:       Initial:  JIRA:
--                2024-01-24  AFNI:     [TRIT-3166] Add a generic CRC module to MAN-IP
--                2024-03-06  AFNI:     [TRIT-3167] Optimize eth_ch
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;


package pk_gen_crc is

  -- Redefined here as to not include other packages.
  constant c_bits_in_1_byte : integer := 8;

  ----------------------------------------------------------
  -- Flips all bits in the std_logic_vector.
  ----------------------------------------------------------
  pure function f_reverse_order(
    data : std_logic_vector
  ) return std_logic_vector;

  ----------------------------------------------------------
  -- Flips all the bits in each byte.
  ----------------------------------------------------------
  pure function f_reverse_bits_in_bytes(
    data : std_logic_vector
  ) return std_logic_vector;

end package;

package body pk_gen_crc is

  ----------------------------------------------------------
  -- Flips all bits in the std_logic_vector.
  ----------------------------------------------------------
  pure function f_reverse_order(
    data : std_logic_vector
  ) return std_logic_vector is
    variable v_output : std_logic_vector(data'reverse_range);
  begin
    for i in data'range loop
      v_output(i) := data(i);
    end loop;
    return v_output;
  end function;

  ----------------------------------------------------------
  -- Flips all the bits in each byte.
  ----------------------------------------------------------
  pure function f_reverse_bits_in_bytes(
    data : std_logic_vector
  ) return std_logic_vector is
    variable v_output            : std_logic_vector(data'range);
    constant c_bytes             : integer := data'length / 8;
    constant c_last_whole_byte   : integer := (c_bytes * 8) + data'low;
  begin
    -- If there are a byte or less in the data input.
    if data'length <= c_bits_in_1_byte then
      v_output := f_reverse_order(data);
    else
      -- Do the all the whole bytes.
      for b in 0 to c_bytes - 1 loop
        v_output((((b + 1) * 8) - 1) + data'low downto (b * 8) + data'low) := 
        f_reverse_order(data((((b + 1) * 8) - 1) + data'low downto (b * 8) + data'low));
      end loop;
      
      -- Do the rest of the 7 or less bits.
      if c_last_whole_byte /= data'length then
        v_output(data'high downto c_last_whole_byte) := f_reverse_order(data(data'high downto c_last_whole_byte));
      end if;
    end if;
    return v_output;
  end function;

end package body; 
