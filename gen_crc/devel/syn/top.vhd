--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2023 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:   
--
-- Revision log:  Date:       Initial:  JIRA:
--                2024-01-24  AFNI:     [TRIT-3144] Add a dual clock fifo as a wrapper
--                2024-02-26  AFNI:     [TRIT-3294] Update alint pro rule
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity gen_crc_top is
  generic(
    gc_data_width : natural              := 32;
    gc_crc_width  : natural              := 32;
    gc_crc_poly   : std_logic_vector     := X"04C11DB7";
    gc_xor_value  : std_logic_vector     := X"FF22FFFF";
    gc_crc_init   : std_logic_vector     := X"FFF123FF";
    gc_ref_input  : integer range 0 to 2 := 1;
    gc_ref_output : boolean              := true
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




architecture rtl of gen_crc_top is

begin

  u_dut : entity work.gen_crc
    generic map(
        gc_data_width => gc_data_width,
        gc_crc_width  => gc_crc_width,
        gc_crc_poly   => gc_crc_poly,
        gc_xor_value  => gc_xor_value,
        gc_crc_init   => gc_crc_init,
        gc_ref_input  => gc_ref_input,
        gc_ref_output => gc_ref_output
    )
    port map(
      clk_i        => clk_i,
      reset_i      => reset_i,
      start_crc_i  => start_crc_i,
      data_i       => data_i,
      data_valid_i => data_valid_i,
      crc_o        => crc_o
    );
  
  

end architecture;


--#############################################################################
-- EOF
