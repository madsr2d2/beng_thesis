--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2023 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:   
--
-- Revision log:  Date:       Initial:  JIRA:
--                2024-01-30  AFNI:     [TRIT-2412] MAN-IO CRC increase
--                2024-02-26  AFNI:     [TRIT-3294] Update alint pro rule
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity crc_32_top is
  generic(
    gc_data_width : natural              := 32;
    gc_crc_width  : natural              := 32
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




architecture rtl of crc_32_top is

  function f_bit_reverse (a : in std_logic_vector)
    return std_logic_vector is
    variable v_result : std_logic_vector(a'length-1 downto 0);
  begin
    for i in 0 to a'length-1 loop
      v_result(i) := a(a'high - i);
    end loop;
    return v_result;
  end;

  signal crc    : std_logic_vector(31 downto 0);  -- crc register
  signal data   : std_logic_vector(31 downto 0);


begin

  data <= f_bit_reverse(data_i(31 downto 24)) & f_bit_reverse(data_i(23 downto 16)) &
          f_bit_reverse(data_i(15 downto 8)) & f_bit_reverse(data_i(7 downto 0));

  p_crc : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if(reset_i = '1') then
        crc <= (others => '1');
      else
        if start_crc_i = '1' then
          crc <= (others => '1');
        elsif data_valid_i = '1' then
          --@alint rule_state off STARC_VHDL.3.1.4.5 
          --   The maximum number of characters in one line should be about 110
          --   FKRI(2022-01-07): Kept long to keep readability of remaining code
          crc(0)  <= crc(0) xor crc(6) xor crc(9) xor crc(10) xor crc(12) xor crc(16) xor crc(24) xor crc(25) xor crc(26) xor crc(28) xor crc(29) xor crc(30) xor crc(31) xor data(0) xor data(6) xor data(9) xor data(10) xor data(12) xor data(16) xor data(24) xor data(25) xor data(26) xor data(28) xor data(29) xor data(30) xor data(31);
          crc(1)  <= crc(0) xor crc(1) xor crc(6) xor crc(7) xor crc(9) xor crc(11) xor crc(12) xor crc(13) xor crc(16) xor crc(17) xor crc(24) xor crc(27) xor crc(28) xor data(0) xor data(1) xor data(6) xor data(7) xor data(9) xor data(11) xor data(12) xor data(13) xor data(16) xor data(17) xor data(24) xor data(27) xor data(28);
          crc(2)  <= crc(0) xor crc(1) xor crc(2) xor crc(6) xor crc(7) xor crc(8) xor crc(9) xor crc(13) xor crc(14) xor crc(16) xor crc(17) xor crc(18) xor crc(24) xor crc(26) xor crc(30) xor crc(31) xor data(0) xor data(1) xor data(2) xor data(6) xor data(7) xor data(8) xor data(9) xor data(13) xor data(14) xor data(16) xor data(17) xor data(18) xor data(24) xor data(26) xor data(30) xor data(31);
          crc(3)  <= crc(1) xor crc(2) xor crc(3) xor crc(7) xor crc(8) xor crc(9) xor crc(10) xor crc(14) xor crc(15) xor crc(17) xor crc(18) xor crc(19) xor crc(25) xor crc(27) xor crc(31) xor data(1) xor data(2) xor data(3) xor data(7) xor data(8) xor data(9) xor data(10) xor data(14) xor data(15) xor data(17) xor data(18) xor data(19) xor data(25) xor data(27) xor data(31);
          crc(4)  <= crc(0) xor crc(2) xor crc(3) xor crc(4) xor crc(6) xor crc(8) xor crc(11) xor crc(12) xor crc(15) xor crc(18) xor crc(19) xor crc(20) xor crc(24) xor crc(25) xor crc(29) xor crc(30) xor crc(31) xor data(0) xor data(2) xor data(3) xor data(4) xor data(6) xor data(8) xor data(11) xor data(12) xor data(15) xor data(18) xor data(19) xor data(20) xor data(24) xor data(25) xor data(29) xor data(30) xor data(31);
          crc(5)  <= crc(0) xor crc(1) xor crc(3) xor crc(4) xor crc(5) xor crc(6) xor crc(7) xor crc(10) xor crc(13) xor crc(19) xor crc(20) xor crc(21) xor crc(24) xor crc(28) xor crc(29) xor data(0) xor data(1) xor data(3) xor data(4) xor data(5) xor data(6) xor data(7) xor data(10) xor data(13) xor data(19) xor data(20) xor data(21) xor data(24) xor data(28) xor data(29);
          crc(6)  <= crc(1) xor crc(2) xor crc(4) xor crc(5) xor crc(6) xor crc(7) xor crc(8) xor crc(11) xor crc(14) xor crc(20) xor crc(21) xor crc(22) xor crc(25) xor crc(29) xor crc(30) xor data(1) xor data(2) xor data(4) xor data(5) xor data(6) xor data(7) xor data(8) xor data(11) xor data(14) xor data(20) xor data(21) xor data(22) xor data(25) xor data(29) xor data(30);
          crc(7)  <= crc(0) xor crc(2) xor crc(3) xor crc(5) xor crc(7) xor crc(8) xor crc(10) xor crc(15) xor crc(16) xor crc(21) xor crc(22) xor crc(23) xor crc(24) xor crc(25) xor crc(28) xor crc(29) xor data(0) xor data(2) xor data(3) xor data(5) xor data(7) xor data(8) xor data(10) xor data(15) xor data(16) xor data(21) xor data(22) xor data(23) xor data(24) xor data(25) xor data(28) xor data(29);
          crc(8)  <= crc(0) xor crc(1) xor crc(3) xor crc(4) xor crc(8) xor crc(10) xor crc(11) xor crc(12) xor crc(17) xor crc(22) xor crc(23) xor crc(28) xor crc(31) xor data(0) xor data(1) xor data(3) xor data(4) xor data(8) xor data(10) xor data(11) xor data(12) xor data(17) xor data(22) xor data(23) xor data(28) xor data(31);
          crc(9)  <= crc(1) xor crc(2) xor crc(4) xor crc(5) xor crc(9) xor crc(11) xor crc(12) xor crc(13) xor crc(18) xor crc(23) xor crc(24) xor crc(29) xor data(1) xor data(2) xor data(4) xor data(5) xor data(9) xor data(11) xor data(12) xor data(13) xor data(18) xor data(23) xor data(24) xor data(29);
          crc(10) <= crc(0) xor crc(2) xor crc(3) xor crc(5) xor crc(9) xor crc(13) xor crc(14) xor crc(16) xor crc(19) xor crc(26) xor crc(28) xor crc(29) xor crc(31) xor data(0) xor data(2) xor data(3) xor data(5) xor data(9) xor data(13) xor data(14) xor data(16) xor data(19) xor data(26) xor data(28) xor data(29) xor data(31);
          crc(11) <= crc(0) xor crc(1) xor crc(3) xor crc(4) xor crc(9) xor crc(12) xor crc(14) xor crc(15) xor crc(16) xor crc(17) xor crc(20) xor crc(24) xor crc(25) xor crc(26) xor crc(27) xor crc(28) xor crc(31) xor data(0) xor data(1) xor data(3) xor data(4) xor data(9) xor data(12) xor data(14) xor data(15) xor data(16) xor data(17) xor data(20) xor data(24) xor data(25) xor data(26) xor data(27) xor data(28) xor data(31);
          crc(12) <= crc(0) xor crc(1) xor crc(2) xor crc(4) xor crc(5) xor crc(6) xor crc(9) xor crc(12) xor crc(13) xor crc(15) xor crc(17) xor crc(18) xor crc(21) xor crc(24) xor crc(27) xor crc(30) xor crc(31) xor data(0) xor data(1) xor data(2) xor data(4) xor data(5) xor data(6) xor data(9) xor data(12) xor data(13) xor data(15) xor data(17) xor data(18) xor data(21) xor data(24) xor data(27) xor data(30) xor data(31);
          crc(13) <= crc(1) xor crc(2) xor crc(3) xor crc(5) xor crc(6) xor crc(7) xor crc(10) xor crc(13) xor crc(14) xor crc(16) xor crc(18) xor crc(19) xor crc(22) xor crc(25) xor crc(28) xor crc(31) xor data(1) xor data(2) xor data(3) xor data(5) xor data(6) xor data(7) xor data(10) xor data(13) xor data(14) xor data(16) xor data(18) xor data(19) xor data(22) xor data(25) xor data(28) xor data(31);
          crc(14) <= crc(2) xor crc(3) xor crc(4) xor crc(6) xor crc(7) xor crc(8) xor crc(11) xor crc(14) xor crc(15) xor crc(17) xor crc(19) xor crc(20) xor crc(23) xor crc(26) xor crc(29) xor data(2) xor data(3) xor data(4) xor data(6) xor data(7) xor data(8) xor data(11) xor data(14) xor data(15) xor data(17) xor data(19) xor data(20) xor data(23) xor data(26) xor data(29);
          crc(15) <= crc(3) xor crc(4) xor crc(5) xor crc(7) xor crc(8) xor crc(9) xor crc(12) xor crc(15) xor crc(16) xor crc(18) xor crc(20) xor crc(21) xor crc(24) xor crc(27) xor crc(30) xor data(3) xor data(4) xor data(5) xor data(7) xor data(8) xor data(9) xor data(12) xor data(15) xor data(16) xor data(18) xor data(20) xor data(21) xor data(24) xor data(27) xor data(30);
          crc(16) <= crc(0) xor crc(4) xor crc(5) xor crc(8) xor crc(12) xor crc(13) xor crc(17) xor crc(19) xor crc(21) xor crc(22) xor crc(24) xor crc(26) xor crc(29) xor crc(30) xor data(0) xor data(4) xor data(5) xor data(8) xor data(12) xor data(13) xor data(17) xor data(19) xor data(21) xor data(22) xor data(24) xor data(26) xor data(29) xor data(30);
          crc(17) <= crc(1) xor crc(5) xor crc(6) xor crc(9) xor crc(13) xor crc(14) xor crc(18) xor crc(20) xor crc(22) xor crc(23) xor crc(25) xor crc(27) xor crc(30) xor crc(31) xor data(1) xor data(5) xor data(6) xor data(9) xor data(13) xor data(14) xor data(18) xor data(20) xor data(22) xor data(23) xor data(25) xor data(27) xor data(30) xor data(31);
          crc(18) <= crc(2) xor crc(6) xor crc(7) xor crc(10) xor crc(14) xor crc(15) xor crc(19) xor crc(21) xor crc(23) xor crc(24) xor crc(26) xor crc(28) xor crc(31) xor data(2) xor data(6) xor data(7) xor data(10) xor data(14) xor data(15) xor data(19) xor data(21) xor data(23) xor data(24) xor data(26) xor data(28) xor data(31);
          crc(19) <= crc(3) xor crc(7) xor crc(8) xor crc(11) xor crc(15) xor crc(16) xor crc(20) xor crc(22) xor crc(24) xor crc(25) xor crc(27) xor crc(29) xor data(3) xor data(7) xor data(8) xor data(11) xor data(15) xor data(16) xor data(20) xor data(22) xor data(24) xor data(25) xor data(27) xor data(29);
          crc(20) <= crc(4) xor crc(8) xor crc(9) xor crc(12) xor crc(16) xor crc(17) xor crc(21) xor crc(23) xor crc(25) xor crc(26) xor crc(28) xor crc(30) xor data(4) xor data(8) xor data(9) xor data(12) xor data(16) xor data(17) xor data(21) xor data(23) xor data(25) xor data(26) xor data(28) xor data(30);
          crc(21) <= crc(5) xor crc(9) xor crc(10) xor crc(13) xor crc(17) xor crc(18) xor crc(22) xor crc(24) xor crc(26) xor crc(27) xor crc(29) xor crc(31) xor data(5) xor data(9) xor data(10) xor data(13) xor data(17) xor data(18) xor data(22) xor data(24) xor data(26) xor data(27) xor data(29) xor data(31);
          crc(22) <= crc(0) xor crc(9) xor crc(11) xor crc(12) xor crc(14) xor crc(16) xor crc(18) xor crc(19) xor crc(23) xor crc(24) xor crc(26) xor crc(27) xor crc(29) xor crc(31) xor data(0) xor data(9) xor data(11) xor data(12) xor data(14) xor data(16) xor data(18) xor data(19) xor data(23) xor data(24) xor data(26) xor data(27) xor data(29) xor data(31);
          crc(23) <= crc(0) xor crc(1) xor crc(6) xor crc(9) xor crc(13) xor crc(15) xor crc(16) xor crc(17) xor crc(19) xor crc(20) xor crc(26) xor crc(27) xor crc(29) xor crc(31) xor data(0) xor data(1) xor data(6) xor data(9) xor data(13) xor data(15) xor data(16) xor data(17) xor data(19) xor data(20) xor data(26) xor data(27) xor data(29) xor data(31);
          crc(24) <= crc(1) xor crc(2) xor crc(7) xor crc(10) xor crc(14) xor crc(16) xor crc(17) xor crc(18) xor crc(20) xor crc(21) xor crc(27) xor crc(28) xor crc(30) xor data(1) xor data(2) xor data(7) xor data(10) xor data(14) xor data(16) xor data(17) xor data(18) xor data(20) xor data(21) xor data(27) xor data(28) xor data(30);
          crc(25) <= crc(2) xor crc(3) xor crc(8) xor crc(11) xor crc(15) xor crc(17) xor crc(18) xor crc(19) xor crc(21) xor crc(22) xor crc(28) xor crc(29) xor crc(31) xor data(2) xor data(3) xor data(8) xor data(11) xor data(15) xor data(17) xor data(18) xor data(19) xor data(21) xor data(22) xor data(28) xor data(29) xor data(31);
          crc(26) <= crc(0) xor crc(3) xor crc(4) xor crc(6) xor crc(10) xor crc(18) xor crc(19) xor crc(20) xor crc(22) xor crc(23) xor crc(24) xor crc(25) xor crc(26) xor crc(28) xor crc(31) xor data(0) xor data(3) xor data(4) xor data(6) xor data(10) xor data(18) xor data(19) xor data(20) xor data(22) xor data(23) xor data(24) xor data(25) xor data(26) xor data(28) xor data(31);
          crc(27) <= crc(1) xor crc(4) xor crc(5) xor crc(7) xor crc(11) xor crc(19) xor crc(20) xor crc(21) xor crc(23) xor crc(24) xor crc(25) xor crc(26) xor crc(27) xor crc(29) xor data(1) xor data(4) xor data(5) xor data(7) xor data(11) xor data(19) xor data(20) xor data(21) xor data(23) xor data(24) xor data(25) xor data(26) xor data(27) xor data(29);
          crc(28) <= crc(2) xor crc(5) xor crc(6) xor crc(8) xor crc(12) xor crc(20) xor crc(21) xor crc(22) xor crc(24) xor crc(25) xor crc(26) xor crc(27) xor crc(28) xor crc(30) xor data(2) xor data(5) xor data(6) xor data(8) xor data(12) xor data(20) xor data(21) xor data(22) xor data(24) xor data(25) xor data(26) xor data(27) xor data(28) xor data(30);
          crc(29) <= crc(3) xor crc(6) xor crc(7) xor crc(9) xor crc(13) xor crc(21) xor crc(22) xor crc(23) xor crc(25) xor crc(26) xor crc(27) xor crc(28) xor crc(29) xor crc(31) xor data(3) xor data(6) xor data(7) xor data(9) xor data(13) xor data(21) xor data(22) xor data(23) xor data(25) xor data(26) xor data(27) xor data(28) xor data(29) xor data(31);
          crc(30) <= crc(4) xor crc(7) xor crc(8) xor crc(10) xor crc(14) xor crc(22) xor crc(23) xor crc(24) xor crc(26) xor crc(27) xor crc(28) xor crc(29) xor crc(30) xor data(4) xor data(7) xor data(8) xor data(10) xor data(14) xor data(22) xor data(23) xor data(24) xor data(26) xor data(27) xor data(28) xor data(29) xor data(30);
          crc(31) <= crc(5) xor crc(8) xor crc(9) xor crc(11) xor crc(15) xor crc(23) xor crc(24) xor crc(25) xor crc(27) xor crc(28) xor crc(29) xor crc(30) xor crc(31) xor data(5) xor data(8) xor data(9) xor data(11) xor data(15) xor data(23) xor data(24) xor data(25) xor data(27) xor data(28) xor data(29) xor data(30) xor data(31);
          --@alint rule_state on STARC_VHDL.3.1.4.5 
        end if;
      end if;
    end if;
  end process p_crc;

  ----------------------------------------------
  -- Tveak and output CRC
  ----------------------------------------------
  p_out : process(clk_i)
    variable v_crc : std_logic_vector(31 downto 0);
  begin
    if rising_edge(clk_i) then
      if(reset_i = '1') then
        crc_o       <= ( others => '0');
      else
        v_crc := f_bit_reverse(crc);
        v_crc := not(v_crc);
        v_crc := v_crc(7 downto 0) & v_crc(15 downto 8) & v_crc(23 downto 16) & v_crc(31 downto 24);
        crc_o <= v_crc;
      end if;
    end if;
  end process p_out;

  

  

end architecture;


--#############################################################################
-- EOF
