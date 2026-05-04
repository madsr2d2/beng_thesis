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
--                2024-08-26  AVBE:     [TRIT-3592] Fixing osvvm library
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.pk_gen_crc.all;
use work.pk_gen_crc_tb.all;

use work.common_tb_pkg.all;

library osvvm;
use osvvm.ScoreBoardPkg_slv.all;
use osvvm.CoveragePkg.all;
use osvvm.AlertLogPkg.all;
use osvvm.RandomBasePkg.all;
use osvvm.RandomPkg.all;

entity gen_crc_model_tb is
  generic(
    -- Constant Generics which can be set before simulation start to test multiple settings. 
    gc_TbTimeOut   : time := 5 ms;      -- Simulator Time out. If the test exceeds this time an error will occur.
    -- MINIMUM 10 us
    gc_TbClkPeriod : time := 10 ns      -- Set the test clock period, Default 100MHz
  );
end entity;

architecture tb of gen_crc_model_tb is

  constant c_data_width : integer := 32;

  signal clk_i   : std_logic := '0';
  signal reset_i : std_logic := '1';
  
  
  signal test_start : std_logic := '0';
  signal test_end   : std_logic := '0';


  shared variable RV : RandomPType;
begin

  clk_i <= not clk_i after gc_TbClkPeriod / 2;

  p_timeout : process
  begin
    wait for gc_TbTimeOut;

    wait for 1 us;

    report "Time Out detected";
    assert (false) report "ERROR TEST FAILED, due to time out" severity error;

    std.env.stop(1);
  end process p_timeout;

  g_test_loop_16 : for test in 0 to c_test_crc_16_reference - 1 generate
    constant c_crc_width      : integer                                    := 16;
    constant c_crc_poly       : std_logic_vector(c_crc_width - 1 downto 0) := c_test_crc_16(test).poly;
    constant c_crc_init       : std_logic_vector(c_crc_width - 1 downto 0) := c_test_crc_16(test).init;
    constant c_crc_xor        : std_logic_vector(c_crc_width - 1 downto 0) := c_test_crc_16(test).xor_val;
    constant c_reverse_input  : integer                                    := c_test_crc_16(test).ref_input;
    constant c_reverse_output : boolean                                    := c_test_crc_16(test).ref_output;

    signal start_crc_i  : std_logic;
    signal data_i       : std_logic_vector(c_data_width - 1 downto 0);
    signal data_valid_i : std_logic;
    signal crc_o        : std_logic_vector(c_crc_width - 1 downto 0);
  begin

    u_dut : entity work.gen_crc_model
      generic map(
        gc_data_width => c_data_width,
        gc_crc_width  => c_crc_width,
        gc_crc_poly   => c_crc_poly,
        gc_xor_value  => c_crc_xor,
        gc_crc_init   => c_crc_init,
        gc_ref_input  => c_reverse_input,
        gc_ref_output => c_reverse_output
      )
      port map(
        clk_i        => clk_i,
        start_crc_i  => start_crc_i,
        data_i       => data_i,
        data_valid_i => data_valid_i,
        crc_o        => crc_o
      );

    p_check : process
      variable v_expected_value : std_logic_vector(c_crc_width - 1 downto 0);
    begin
      data_i       <= (others => '0');
      data_valid_i <= '0';
      start_crc_i  <= '0';
      
      
      sync(test_start);

      data_i           <= c_test_numbers(0);
      data_valid_i     <= '1';
      start_crc_i      <= '1';
      wait_fall_edges(clk_i, 1);
      v_expected_value := c_expected_numbers(test)(0);
      verify_value(crc_o, v_expected_value, "Data was incorrect, " & integer'image(test));
      start_crc_i      <= '0';

      for i in 1 to c_data_tests - 1 loop
        data_i           <= c_test_numbers(i);
        wait_fall_edges(clk_i, 1);
        v_expected_value := c_expected_numbers(test)(i);
        verify_value(crc_o, v_expected_value, "Data was incorrect, " & integer'image(test));
      end loop;

      sync(test_end);
      wait;
    end process;

  end generate;

  g_test_loop_32 : for test in 0 to c_test_crc_32_reference - 1 generate
    constant c_crc_width      : integer                                    := 32;
    constant c_crc_poly       : std_logic_vector(c_crc_width - 1 downto 0) := c_test_crc_32(test).poly;
    constant c_crc_init       : std_logic_vector(c_crc_width - 1 downto 0) := c_test_crc_32(test).init;
    constant c_crc_xor        : std_logic_vector(c_crc_width - 1 downto 0) := c_test_crc_32(test).xor_val;
    constant c_reverse_input  : integer                                    := c_test_crc_32(test).ref_input;
    constant c_reverse_output : boolean                                    := c_test_crc_32(test).ref_output;

    signal start_crc_i  : std_logic;
    signal data_i       : std_logic_vector(c_data_width - 1 downto 0);
    signal data_valid_i : std_logic;
    signal crc_o        : std_logic_vector(c_crc_width - 1 downto 0);
  begin

    u_dut : entity work.gen_crc_model
      generic map(
        gc_data_width => c_data_width,
        gc_crc_width  => c_crc_width,
        gc_crc_poly   => c_crc_poly,
        gc_xor_value  => c_crc_xor,
        gc_crc_init   => c_crc_init,
        gc_ref_input  => c_reverse_input,
        gc_ref_output => c_reverse_output
      )
      port map(
        clk_i        => clk_i,
        start_crc_i  => start_crc_i,
        data_i       => data_i,
        data_valid_i => data_valid_i,
        crc_o        => crc_o
      );

    p_check : process
      variable v_expected_value : std_logic_vector(c_crc_width - 1 downto 0);
    begin
      data_i       <= (others => '0');
      data_valid_i <= '0';
      start_crc_i  <= '0';
      
      sync(test_start);

      data_i           <= c_test_numbers(0);
      data_valid_i     <= '1';
      start_crc_i      <= '1';
      wait_fall_edges(clk_i, 1);
      v_expected_value := c_expected_numbers_32(test)(0);
      verify_value(crc_o, v_expected_value, "Data was incorrect, " & integer'image(test));
      start_crc_i      <= '0';

      for i in 1 to c_data_tests - 1 loop
        data_i           <= c_test_numbers(i);
        wait_fall_edges(clk_i, 1);
        v_expected_value := c_expected_numbers_32(test)(i);
        verify_value(crc_o, v_expected_value, "Data was incorrect, " & integer'image(test));
      end loop;

      sync(test_end);
      wait;
    end process;

  end generate;


  p_test : process is
  begin
    RV.InitSeed(random_seed);

    reset_i <= '1';
    wait_fall_edges(clk_i, 10);
    reset_i <= '0';
    wait_fall_edges(clk_i, 10);

    
    Message("###################");
    Message("Test Start");
    Message("###################");
    sync(test_start);
    
    
    sync(test_end);
    Message("###################");
    Message("Test Passed");
    Message("###################");
    std.env.stop;
  end process;


end architecture; 
