--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-15
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

entity can_types_p_tb is
  generic (
    -- Constant Generics which can be set before simulation start to test multiple settings.
    gc_TbTimeOut   : time := 2 ms;   -- Simulator Time out. If the test exceeds this time an error will occur.
    gc_TbClkPeriod : time := 10 ns      -- Set the test clock period, Default 100MHz
    --
  );
end entity;

architecture tb of can_types_p_tb is
  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  -- Test ids
  signal test_id          : AlertLogIDType;
  signal reset_id         : AlertLogIDType;

  signal clk   : std_logic := '0';
  signal reset : std_logic := '1';


  shared variable RV : RandomPType;

begin
  p_init : process
    variable v_test_id : AlertLogIDType;
  begin
    RV.InitSeed(random_seed);
    SetAlertStopCount(ERROR, 10);

    v_test_id := NewId("can_types_p");
    test_id   <= v_test_id;
    reset_id  <= NewId("Reset at Output", v_test_id);

    wait for 0 ns;
    --    SetLogEnable(test_id, INFO, true);

    wait for 0 ns;

    wait;
  end process;

  ----------------------------------------------------
  -- Clock gen
  ----------------------------------------------------
  clk <= not clk after gc_TbClkPeriod / 2;

  ----------------------------------------------------
  -- Simulation Time out monitor.
  -- Terminates the simulation when a timeout event is detected
  ----------------------------------------------------
  p_timeout : process
  begin
    WaitForClock(clk, gc_TbTimeOut);

    WaitForClock(clk, 1 us);

    report "Time Out detected";
    assert (false) report "ERROR TEST FAILED, due to time out" severity error;

    std.env.stop(1);
  end process p_timeout;

  ----------------------------------------------------
  -- Dut
  ----------------------------------------------------

  
  ----------------------------------------------------
  -- Helper modules
  ----------------------------------------------------


  
  ----------------------------------------------------
  -- Main test process
  ----------------------------------------------------
  p_main_tester : process

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
    AffirmIf(reset_id, RV.RandInt(0, 10) = RV.RandInt(11, 20), "Test ", " was incorrect");

    reset <= '0';
    WaitForClock(clk, 200);

    Message("################################################################################");
    Message("TEST Start");
    Message("################################################################################");

    Message("###############################");
    Message("1st Test");
    Message("###############################");

    wait for 10 us;
    ReportNonZeroAlerts;
    Message("################################################################################");
    if GetAlertCount = 0 then
      Message("TEST PASSED!!");
    else
      Message("TEST FAILED :(");
    end if;
    Message("################################################################################");
    wait for 100 us;
    std.env.stop;
    wait;
  end process;

end architecture;

-- eof
