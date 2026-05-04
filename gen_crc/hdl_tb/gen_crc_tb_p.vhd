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
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.pk_man_global.all;

package pk_gen_crc_tb is

  type t_test_crc_setting is record
    poly       : std_logic_vector;
    init       : std_logic_vector;
    xor_val    : std_logic_vector;
    ref_input  : integer;
    ref_output : boolean;
  end record;

  type t_test_crc_array is array (natural range <>) of t_test_crc_setting;

  -- Only the first 3 have the reference data tested.
  constant c_test_crc_16_reference : integer := 3;
  constant c_test_crc_16 : t_test_crc_array := (
    (poly => X"8005", init => X"0000", xor_val => X"0000", ref_input => 1, ref_output => true), -- 0 => CRC-16/ARC
    (poly => X"1021", init => X"FFFF", xor_val => X"0000", ref_input => 0, ref_output => false), -- 1 => CRC-16/CCITT-FALSE
    (poly => X"3D65", init => X"0000", xor_val => X"FFFF", ref_input => 1, ref_output => true), -- 2 => CRC-16/DNP
    (poly => X"1021", init => X"0000", xor_val => X"FFFF", ref_input => 1, ref_output => true) -- 3 => CRC-16/KERMIT
  );

  -- Only the first 2 have the reference data tested.
  constant c_test_crc_32_reference : integer := 2;
  constant c_test_crc_32 : t_test_crc_array := (
    (poly => X"04C11DB7", init => X"FFFFFFFF", xor_val => X"FFFFFFFF", ref_input => 1, ref_output => true), -- 0 => CRC-32
    (poly => X"04C11DB7", init => X"FFFFFFFF", xor_val => X"00000000", ref_input => 0, ref_output => false), -- 1 => CRC-32/MPEG-2
    (poly => X"04C12DB7", init => X"FFF123FF", xor_val => X"00000000", ref_input => 2, ref_output => true), -- 2 => CRC-32/DIY-1
    (poly => X"1EDC6F41", init => X"FFFFFFFF", xor_val => X"FFFFFFFF", ref_input => 1, ref_output => true) -- 3 => CRC-32C
  );

  type t_slv_array_2d is array (natural range <>) of t_slv_array;

  constant c_data_tests : integer := 6;

  constant c_test_numbers : t_slv_array := (
    X"68C7A5CB",
    X"4140265e",
    X"0dbf0414",
    X"db09c58c",
    X"3cbb222a",
    X"0dd26a54"
  );

  constant c_expected_numbers : t_slv_array_2d := (
    (X"5A97", X"1782", X"FBA9", X"7EE8", X"B2B0", X"2D0B"), -- 0 => CRC-16/ARC            
    (X"711A", X"A29D", X"484F", X"4BEB", X"A83A", X"A133"), -- 1 => CRC-16/CCITT-FALSE    
    (X"BE62", X"16A8", X"30EF", X"2AB6", X"E5A0", X"9629") -- 2 => CRC-16/DNP  
  );
  constant c_expected_numbers_32 : t_slv_array_2d := (
    (X"94F0D3A1", X"A4BDD1BA", X"1DCEE968", X"E39D94D1", X"B7A58F47", X"C4E8A2E5"), -- 0 => CRC-32          
    (X"D9B1E333", X"DCBD0A06", X"75305FB8", X"23D9928F", X"0867EB24", X"DCCAD79A") -- 1 => CRC-32/MPEG-2   
  );

  
end package; 
