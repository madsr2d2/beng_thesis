--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2024 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:   gc_ref_input:
--                0 no reflection
--                1 bits in byte reflection
--                2 all bit reflection
--                gc_ref_output: false no reflection.
--                true all bit reflection.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2024-01-24  AFNI:     [TRIT-3166] Add a generic CRC module to MAN-IP
--                2024-01-30  AFNI:     [TRIT-2412] MAN-IO CRC increase
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.pk_gen_crc.all;


--@alint rule_state off STARC_VHDL.2.1.2.6
--  Specify the range for std_logic_vector (except for function specification).
--  AFNI(2024-01-24): The generics is change to constants in the top to prevent the wrong simulation/synthesis.
entity gen_crc is
  generic(
    gc_data_width : natural              := 32;
    gc_crc_width  : natural              := 16;
    gc_crc_poly   : std_logic_vector     := X"1021";
    gc_xor_value  : std_logic_vector     := X"0000";
    gc_crc_init   : std_logic_vector     := X"FFFF"; -- The initialization value for the crc calculation when the start_crc_i is asserted.
    gc_ref_input  : integer range 0 to 2 := 0;
    gc_ref_output : boolean              := false
  );
  port(
    -- Clock and reset
    clk_i        : in  std_logic;       -- Clock
    reset_i      : in  std_logic;       -- Reset synchronous

    start_crc_i  : in  std_logic;       -- Start of calculation
    data_i       : in  std_logic_vector(gc_data_width - 1 downto 0);
    data_valid_i : in  std_logic;
    
    crc_o        : out std_logic_vector(gc_crc_width - 1 downto 0)
  );
end entity;
--@alint rule_state on STARC_VHDL.2.1.2.6

architecture rtl of gen_crc is

  -- Constraning generics to specify bit order.
  constant c_crc_poly : std_logic_vector(gc_crc_width - 1 downto 0) := gc_crc_poly;
  constant c_xor_value : std_logic_vector(gc_crc_width - 1 downto 0) := gc_xor_value;
  constant c_crc_init : std_logic_vector(gc_crc_width - 1 downto 0) := gc_crc_init;


  signal crc   : std_logic_vector(gc_crc_width - 1 downto 0);
  signal crc_r : std_logic_vector(gc_crc_width - 1 downto 0);
  signal data  : std_logic_vector(gc_data_width - 1 downto 0);
  
  
begin

  -- data_i handling. Will either not reflected it, reflect it bits in bytes og all bits.
  g_non_reverse_input : if gc_ref_input = 0 generate
    data <= data_i;
  end generate;
  g_bits_in_bytes_reflection_input : if gc_ref_input = 1 generate
    data <= f_reverse_bits_in_bytes(data_i);
  end generate;
  g_whole_bit_reverse_input : if gc_ref_input = 2 generate
    data <= f_reverse_order(data_i);
  end generate;
  

  -- Calculate CRC
  p_crc : process(clk_i) is
    variable v_crc_tmp : std_logic_vector(gc_crc_width - 1 downto 0);
    variable v_crc_fb  : std_logic;
  begin
    if rising_edge(clk_i) then
      if reset_i = '1' then
        crc_r       <= c_crc_init;

      else
        if (start_crc_i = '1') and (data_valid_i = '0') then
          crc_r <= c_crc_init;

        elsif data_valid_i = '1' then

          -- Mimic an LFSR in the code and let synthesis sort out the (big) XOR gates
          if start_crc_i = '1' then
            v_crc_tmp := c_crc_init;
          else
            v_crc_tmp := crc_r;            
          end if;

          for d_idx in data'range loop
            v_crc_fb                 := v_crc_tmp(v_crc_tmp'high) xor data(d_idx);
            for c_idx in v_crc_tmp'high downto v_crc_tmp'low + 1 loop
              if c_crc_poly(c_idx) = '1' then
                v_crc_tmp(c_idx) := v_crc_tmp(c_idx - 1) xor v_crc_fb;
              else
                v_crc_tmp(c_idx) := v_crc_tmp(c_idx - 1);
              end if;
            end loop;
            v_crc_tmp(v_crc_tmp'low) := v_crc_fb;
          end loop;

          crc_r <= v_crc_tmp;
          
        end if;
      end if;
    end if;
  end process;
  
  -- Output
  crc   <= crc_r xor c_xor_value;
  -- The crc_o can either be reflected or not.
  g_non_reverse_output : if not gc_ref_output generate
    crc_o <= crc;
  end generate;
  g_reverse_output : if gc_ref_output generate
    crc_o <= f_reverse_order(crc);
  end generate;
  
end architecture; 
