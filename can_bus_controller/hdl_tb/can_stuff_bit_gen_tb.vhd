--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2025 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:   Testbench for can_stuff_bit_gen.
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

use work.common_register_interface_pkg.all;
use work.common_tb_pkg.all;

library osvvm;
context osvvm.OsvvmContext;

entity can_stuff_bit_gen_tb is
  generic(
    gc_TbTimeOut         : time    := 500 ms;
    gc_TbClkPeriod       : time    := 10 ns;
    gc_bit_string_length : integer := 10000                                     -- Length of the bit string to be streamed to the DUT.
  );
end entity;

architecture tb of can_stuff_bit_gen_tb is
  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  -- Test ids
  signal test_id  : AlertLogIDType;
  signal reset_id : AlertLogIDType;

  signal clk       : std_logic := '0';
  signal reset     : std_logic := '1';
  signal stuff_bit : std_logic;
  signal valid     : std_logic;
  signal rx        : std_logic := '1';
  signal sample_rx : std_logic;

  signal transmit : std_logic;

  shared variable RV : RandomPType;

  ----------------------------------------------------------------------------
  -- This procedure generates the following std_logic_vector arrays. 
  -- bit_array: Random bit string.
  -- stuff_marks: '1' at the position following 5 identical bits.
  -- stuff_bit_array: The bit to be inserted at the position of the stuff marks.
  ----------------------------------------------------------------------------
  procedure gen_random_bitstring_with_stuff_markers(
    variable bit_array       : out t_sl_array;
    variable stuff_marks     : out t_sl_array;
    variable stuff_bit_array : out t_sl_array
  ) is
    variable run_len  : integer   := 1;
    variable prev_bit : std_logic := '0';
  begin
    for i in bit_array'range loop
      -- Generate random bit
      bit_array(i) := '0' when i = bit_array'low else '1' when RV.RandBool else '0';

      -- Generate stuff marker and stuff bit
      run_len            := run_len + 1 when bit_array(i) = prev_bit else 1;
      stuff_marks(i)     := '1' when run_len = 5 else '0';
      stuff_bit_array(i) := not prev_bit when run_len = 5 else '0';

      if run_len = 5 then
        run_len := 1;
      end if;

      prev_bit := bit_array(i);
    end loop;
  end procedure;

begin
  p_init : process
    variable v_test_id : AlertLogIDType;
  begin
    RV.InitSeed(random_seed);
    SetAlertStopCount(ERROR, 10);

    v_test_id := NewId("<ModuleName>");
    test_id   <= v_test_id;
    reset_id  <= NewId("Reset at Output", v_test_id);

    wait for 0 ns;
    --    SetLogEnable(test_id, INFO, true);

    wait for 0 ns;

    wait;
  end process;

  ----------------------------------------------------------------------------
  -- Clock gen
  ----------------------------------------------------------------------------
  clk <= not clk after gc_TbClkPeriod / 2;

  ----------------------------------------------------------------------------
  -- Simulation Time out monitor.
  -- Terminates the simulation when a timeout event is detected
  ----------------------------------------------------------------------------
  p_timeout : process
  begin
    WaitForClock(clk, gc_TbTimeOut);

    WaitForClock(clk, 1 us);

    report "Time Out detected";
    assert (false) report "ERROR TEST FAILED, due to time out" severity error;

    std.env.stop(1);
  end process p_timeout;

  ----------------------------------------------------------------------------
  -- Dut
  ----------------------------------------------------------------------------
  u_dut : entity work.can_stuff_bit_gen
    port map(
      clk_i             => clk,
      reset_i           => reset,
      rx_i              => rx,
      sample_rx_i       => sample_rx,
      stuff_bit_o       => stuff_bit,
      stuff_bit_valid_o => valid
    );

  ----------------------------------------------------------------------------
  -- Helper modules
  ----------------------------------------------------------------------------
  -- Node clock generating the sample_rx pulse
  u_can_node_clock : entity work.can_node_clock
    port map(
      clk_i       => clk,
      reset_i     => '0',
      rx_i        => rx,
      sample_rx_o => sample_rx,
      transmit_o  => transmit
    );

  ----------------------------------------------------------------------------
  -- Main test process
  ----------------------------------------------------------------------------
  p_main_tester : process
    variable v_bit_string      : t_sl_array(0 to gc_bit_string_length);
    variable v_stuff_mask      : t_sl_array(0 to gc_bit_string_length);
    variable v_stuff_bit_array : t_sl_array(0 to gc_bit_string_length);
    variable v_stuff_bit       : std_logic;
  begin
    reset <= '0';
    wait for 0 ns;
    wait for 0 ns;
    WaitForClock(clk, 1);

    reset <= '1';
    WaitForClock(clk, 200);
    Message("################################################################################");
    Message("Output at Reset");
    Message("################################################################################");
    Message("valid = " & std_logic'image(valid));
    Message("stuff_bit = " & std_logic'image(stuff_bit));
    AffirmIf(reset_id, valid = '0', "valid_o = " & std_logic'image(valid), "Expected valid_o ='0'");
    AffirmIf(reset_id, stuff_bit = '1', "stuff_bit_o = " & std_logic'image(stuff_bit), "Expected stuff_bit_o ='1'");

    Message("");

    reset <= '0';
    WaitForClock(clk, 200);
    Message("################################################################################");
    Message("Output after reset");
    Message("################################################################################");
    Message("valid = " & std_logic'image(valid));
    Message("stuff_bit = " & std_logic'image(stuff_bit));
    AffirmIf(reset_id, valid = '0', "valid_o = " & std_logic'image(valid), "Expected valid_o ='0'");
    AffirmIf(reset_id, stuff_bit = '1', "stuff_bit_o = " & std_logic'image(stuff_bit), "Expected stuff_bit_o ='1'");

    Message("");

    Message("################################################################################");
    Message("Normal Usage");
    Message("################################################################################");

    Message("Generating random bit string (" & integer'image(gc_bit_string_length) & " bits), stuff markers and stuff bits...");
    gen_random_bitstring_with_stuff_markers(v_bit_string, v_stuff_mask, v_stuff_bit_array);

    Message("Streaming random bit string to DUT and checking stuff bit insertions...");
    -- Iterate through the bit string, wait for sample_rx pulse and validate stuff bit insertions.
    for i in v_bit_string'range loop
      rx <= v_bit_string(i);
      wait until sample_rx = '1';
      if v_stuff_mask(i) = '1' then
        v_stuff_bit := v_stuff_bit_array(i);
        AffirmIf(test_id, stuff_bit = v_stuff_bit, "stuff_bit = " & std_logic'image(stuff_bit), "Expected stuff_bit = " & std_logic'image(v_stuff_bit));
      end if;
    end loop;

    Message("");

    ReportAlerts;
    Message("################################################################################");
    if GetAlertCount = 0 then
      Message("TEST PASSED!!");
    else
      Message("TEST FAILED :(");
    end if;
    Message("################################################################################");
    wait for 100 us;
    std.env.stop;
  end process;

end architecture;

-- eof
