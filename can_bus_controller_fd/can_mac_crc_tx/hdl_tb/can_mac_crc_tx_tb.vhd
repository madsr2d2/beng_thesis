--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_mac_crc_tx.
--                  1. Reset zeroes the CRC output.
--                  2. CRC-15 (Classic CAN): start, feed bits, verify output.
--                  3. CRC-17 (FD): start, feed bits, verify output.
--                  4. CRC-21 (FD): start, feed bits, verify output.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-15  TMYAES    [TRIT-4336] Initial implementation
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pk_man_global.all;
use work.common_register_interface_pkg.all;
use work.common_tb_pkg.all;
use work.pk_can_types.all;

library osvvm;
context osvvm.OsvvmContext;

entity can_mac_crc_tx_tb is
  generic (
    gc_TbTimeOut   : time := 2 ms;
    gc_TbClkPeriod : time := 10 ns
  );
end entity;

architecture tb of can_mac_crc_tx_tb is

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  constant c_crc_zero : t_crc_vector := (others => '0');

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal crc_i : t_can_mac_fsm_crc_tx_if_m2s := c_mac_fsm_to_crc_if_reset;
  signal crc_o : t_can_mac_fsm_crc_tx_if_s2m;

  signal test_id  : AlertLogIDType;
  signal reset_id : AlertLogIDType;

  signal clk   : std_logic := '0';
  signal reset : std_logic := '1';

  shared variable RV : RandomPType;

begin

  ----------------------------------------------------------------------------
  -- Initialisation
  ----------------------------------------------------------------------------
  p_init : process
    variable v_test_id : AlertLogIDType;
  begin
    RV.InitSeed(random_seed);
    SetAlertStopCount(ERROR, 10);

    v_test_id := NewId("can_mac_crc_tx");
    test_id   <= v_test_id;
    reset_id  <= NewId("Reset", v_test_id);

    wait for 0 ns;

    wait;
  end process;

  ----------------------------------------------------------------------------
  -- Clock / reset
  ----------------------------------------------------------------------------
  CreateClock(clk, gc_TbClkPeriod);
  CreateReset(reset, '1', clk, gc_TbClkPeriod * 5);

  ----------------------------------------------------------------------------
  -- Timeout watchdog
  ----------------------------------------------------------------------------
  p_timeout : process
  begin
    WaitForClock(clk, gc_TbTimeOut);
    WaitForClock(clk, 1 us);
    report "Time Out detected";
    assert false report "ERROR TEST FAILED, due to time out" severity error;
    std.env.stop(1);
  end process p_timeout;

  ----------------------------------------------------------------------------
  -- DUT
  ----------------------------------------------------------------------------
  u_dut : entity work.can_mac_crc_tx
    port map (
      clk_i => clk,
      rst_i => reset,
      crc_i => crc_i,
      crc_o => crc_o
    );

  -- -------------------------------------------------------------------------
  -- Main test process
  -- -------------------------------------------------------------------------
  p_main_tester : process
    variable v_snap : t_crc_vector;
  begin
    wait until reset = '0';
    WaitForClock(clk);

    -- -----------------------------------------------------------------------
    -- Test 1: Reset zeroes CRC output
    -- -----------------------------------------------------------------------
    Message("################################################################################");
    Message("Test 1: Reset output");
    Message("################################################################################");
    AffirmIf(reset_id, crc_o.crc = c_crc_zero,
             "CRC output not zero after reset");

    -- -----------------------------------------------------------------------
    -- Test 2: CRC-15 (poly_select = "00")
    -- -----------------------------------------------------------------------
    Message("################################################################################");
    Message("Test 2: CRC-15");
    Message("################################################################################");
    crc_i.crc_poly_select <= "00";
    crc_i.start           <= '1';
    crc_i.valid           <= '0';
    WaitForClock(clk);
    crc_i.start <= '0';

    for i in 0 to 31 loop
      crc_i.data  <= '1' when RV.RandBool else '0';
      crc_i.valid <= '1';
      WaitForClock(clk);
    end loop;
    crc_i.valid <= '0';
    WaitForClock(clk, 2);

    AffirmIf(test_id, crc_o.crc /= c_crc_zero,
             "CRC-15: output still zero after data");
    v_snap := crc_o.crc;
    WaitForClock(clk, 5);
    AffirmIf(test_id, crc_o.crc = v_snap,
             "CRC-15: output changed with valid=false");

    -- -----------------------------------------------------------------------
    -- Test 3: CRC-17 (poly_select = "01")
    -- -----------------------------------------------------------------------
    Message("################################################################################");
    Message("Test 3: CRC-17");
    Message("################################################################################");
    crc_i.crc_poly_select <= "00";
    crc_i.crc_poly_select <= "01";
    crc_i.start           <= '1';
    crc_i.valid           <= '0';
    WaitForClock(clk);
    crc_i.start <= '0';

    for i in 0 to 31 loop
      crc_i.data  <= '1' when RV.RandBool else '0';
      crc_i.valid <= '1';
      WaitForClock(clk);
    end loop;
    crc_i.valid <= '0';
    WaitForClock(clk, 2);

    AffirmIf(test_id, crc_o.crc /= c_crc_zero,
             "CRC-17: output still zero after data");
    v_snap := crc_o.crc;
    WaitForClock(clk, 5);
    AffirmIf(test_id, crc_o.crc = v_snap,
             "CRC-17: output changed with valid=false");

    -- -----------------------------------------------------------------------
    -- Test 4: CRC-21 (poly_select = "10")
    -- -----------------------------------------------------------------------
    Message("################################################################################");
    Message("Test 4: CRC-21");
    Message("################################################################################");
    crc_i.crc_poly_select <= "10";
    crc_i.start           <= '1';
    crc_i.valid           <= '0';
    WaitForClock(clk);
    crc_i.start <= '0';

    for i in 0 to 31 loop
      crc_i.data  <= '1' when RV.RandBool else '0';
      crc_i.valid <= '1';
      WaitForClock(clk);
    end loop;
    crc_i.valid <= '0';
    WaitForClock(clk, 2);

    AffirmIf(test_id, crc_o.crc /= c_crc_zero,
             "CRC-21: output still zero after data");
    v_snap := crc_o.crc;
    WaitForClock(clk, 5);
    AffirmIf(test_id, crc_o.crc = v_snap,
             "CRC-21: output changed with valid=false");

    -- -----------------------------------------------------------------------
    -- Done
    -- -----------------------------------------------------------------------
    WaitForClock(clk, 5);
    ReportNonZeroAlerts;
    Message("################################################################################");
    if GetAlertCount = 0 then
      Message("TEST PASSED!!");
    else
      Message("TEST FAILED :(");
    end if;
    Message("################################################################################");
    EndOfTestReports(ReportAll => TRUE);
    std.env.finish;
  end process p_main_tester;

end architecture tb;

-- eof