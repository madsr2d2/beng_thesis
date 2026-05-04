--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2024 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:   Model to verify that the crc works as intended.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2024-01-24  AFNI:     [TRIT-3166] Add a generic CRC module to MAN-IP
--                2024-08-26  AVBE:     [TRIT-3592] Fixing osvvm library
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.pk_gen_crc.all;

use work.common_tb_pkg.all;

library osvvm;
use osvvm.ScoreBoardPkg_slv.all;
use osvvm.CoveragePkg.all;
use osvvm.AlertLogPkg.all;
use osvvm.RandomBasePkg.all;
use osvvm.RandomPkg.all;

entity gen_crc_model is
  generic(
    gc_data_width : natural              := 32;
    gc_crc_width  : natural              := 16;
    gc_crc_poly   : std_logic_vector     := X"1021";
    gc_xor_value  : std_logic_vector     := X"0000";
    gc_crc_init   : std_logic_vector     := X"FFFF";
    gc_ref_input  : integer range 0 to 2 := 0;
    gc_ref_output : boolean              := false
  );
  port(
    -- Clock and reset
    clk_i        : in  std_logic;       -- Clock

    start_crc_i  : in  std_logic;       -- Start of calculation
    data_i       : in  std_logic_vector(gc_data_width - 1 downto 0);
    data_valid_i : in  std_logic;
      
    crc_o        : out std_logic_vector(gc_crc_width - 1 downto 0)
  );
end entity;

architecture tb of gen_crc_model is

  constant c_crc_poly  : std_logic_vector(gc_crc_width - 1 downto 0) := gc_crc_poly;
  constant c_xor_value : std_logic_vector(gc_crc_width - 1 downto 0) := gc_xor_value;
  constant c_crc_init  : std_logic_vector(gc_crc_width - 1 downto 0) := gc_crc_init;


  signal crc  : std_logic_vector(gc_crc_width - 1 downto 0);
  signal data : std_logic_vector(gc_data_width - 1 downto 0);
  
  
begin

  g_non_reverse_input : if gc_ref_input = 0 generate
    data <= data_i;
  end generate;
  g_bits_in_bytes_reflection_input : if gc_ref_input = 1 generate
    data <= f_reverse_bits_in_bytes(data_i);
  end generate;
  g_whole_bit_reverse_input : if gc_ref_input = 2 generate
    data <= f_reverse_order(data_i);
  end generate;
  g_non_reverse_output : if not gc_ref_output generate
    crc_o <= crc;
  end generate;
  g_reverse_output : if gc_ref_output generate
    crc_o <= f_reverse_order(crc);
  end generate;

  p_crc : process is
    variable v_crc    : std_logic_vector(gc_crc_width - 1 downto 0);
    variable v_crc_fb : std_logic;
  begin
    loop
      wait until rising_edge(clk_i);
      if (start_crc_i = '1') then
        v_crc := c_crc_init;
      end if;
      if data_valid_i = '1' then
        for d_idx in data'range loop
          v_crc_fb         := v_crc(v_crc'high) xor data(d_idx);
          for c_idx in v_crc'high downto v_crc'low + 1 loop
            if c_crc_poly(c_idx) = '1' then
              v_crc(c_idx) := v_crc(c_idx - 1) xor v_crc_fb;
            else
              v_crc(c_idx) := v_crc(c_idx - 1);
            end if;
          end loop;
          v_crc(v_crc'low) := v_crc_fb;
        end loop;
      end if;
      crc <= v_crc xor c_xor_value;
    end loop;
  end process;


end architecture; 
