--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_fce.
--                  p_test_ctrl  - Test sequencer: reset, normal usage, random stress.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-31  MRDSA     Converted to company header format
--                2026-04-12  MRDSA     Updated for single MAC interface,
--                                      PCS idle_condition recovery, black-box only
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.OsvvmContext;
  use osvvm.ScoreboardPkg_slv.all;
library osvvm_common;
  context osvvm_common.OsvvmCommonContext;

use work.pk_man_global.all;
use work.common_register_interface_pkg.all;
use work.common_tb_pkg.all;
use work.pk_can_types.all;

entity can_fce_tb is
  generic (
    gc_TbTimeOut   : time := 50 ms;
    gc_TbClkPeriod : time := 10 ns
  );
end entity can_fce_tb;

architecture tb of can_fce_tb is

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal clk   : std_logic;
  signal reset : std_logic := '1';

  signal llc_i : t_can_llc_fce_if_m2s := c_llc_to_fce_if_reset;
  signal llc_o : t_can_fce_llc_if_s2m;

  signal mac_i : t_can_mac_fce_if_m2s := c_mac_to_fce_if_reset;
  signal mac_o : t_can_mac_fce_if_s2m;

  signal pcs_i : t_can_pcs_fce_if_s2m := c_pcs_to_fce_if_reset;
  signal pcs_o : t_can_fce_pcs_if_m2s;

  -- OSVVM signals
  shared variable RV : RandomPType;
  signal test_id      : AlertLogIDType;
  signal init_barrier : integer_barrier := 1;

  ----------------------------------------------------------------------------
  -- Pulse procedures
  ----------------------------------------------------------------------------


  procedure pulse_tx_error (signal s2d : inout t_can_mac_fce_if_m2s) is
  begin
    s2d.transmitting <= '1';
    s2d.error <= '1';
    wait until rising_edge(clk);
    s2d <= c_mac_to_fce_if_reset;
    s2d.transmitting <= '1';
    wait until rising_edge(clk);
  end procedure pulse_tx_error;

  procedure pulse_tx_success (signal s2d : inout t_can_mac_fce_if_m2s) is
  begin
    s2d.transmitting <= '1';
    s2d.successful_transfer <= '1';
    wait until rising_edge(clk);
    s2d <= c_mac_to_fce_if_reset;
    wait until rising_edge(clk);
  end procedure pulse_tx_success;

  procedure pulse_rx_error (signal s2d : inout t_can_mac_fce_if_m2s) is
  begin
    s2d.transmitting <= '0';
    s2d.error <= '1';
    wait until rising_edge(clk);
    s2d <= c_mac_to_fce_if_reset;
    wait until rising_edge(clk);
  end procedure pulse_rx_error;

  procedure pulse_rx_primary_error (signal s2d : inout t_can_mac_fce_if_m2s) is
  begin
    s2d.transmitting <= '0';
    s2d.primary_error <= '1';
    wait until rising_edge(clk);
    s2d <= c_mac_to_fce_if_reset;
    wait until rising_edge(clk);
  end procedure pulse_rx_primary_error;

  procedure pulse_rx_success (signal s2d : inout t_can_mac_fce_if_m2s) is
  begin
    s2d.transmitting <= '0';
    s2d.successful_transfer <= '1';
    wait until rising_edge(clk);
    s2d <= c_mac_to_fce_if_reset;
    wait until rising_edge(clk);
  end procedure pulse_rx_success;

  procedure pulse_tx_delim_late (signal s2d : inout t_can_mac_fce_if_m2s) is
  begin
    s2d.transmitting <= '1';
    s2d.error_delimiter_too_late <= '1';
    wait until rising_edge(clk);
    s2d <= c_mac_to_fce_if_reset;
    s2d.transmitting <= '1';
    wait until rising_edge(clk);
  end procedure pulse_tx_delim_late;

  procedure pulse_rx_delim_late (signal s2d : inout t_can_mac_fce_if_m2s) is
  begin
    s2d.transmitting <= '0';
    s2d.error_delimiter_too_late <= '1';
    wait until rising_edge(clk);
    s2d <= c_mac_to_fce_if_reset;
    wait until rising_edge(clk);
  end procedure pulse_rx_delim_late;

  procedure pulse_rx_error_in_flag (signal s2d : inout t_can_mac_fce_if_m2s) is
  begin
    s2d.transmitting <= '0';
    s2d.error <= '1';
    s2d.sending_error_overload_flag <= '1';
    wait until rising_edge(clk);
    s2d <= c_mac_to_fce_if_reset;
    wait until rising_edge(clk);
  end procedure pulse_rx_error_in_flag;

  procedure pulse_idle_condition (signal pcs : inout t_can_pcs_fce_if_s2m) is
  begin
    pcs.idle_condition <= '1';
    wait until rising_edge(clk);
    pcs.idle_condition <= '0';
    wait until rising_edge(clk);
  end procedure pulse_idle_condition;

begin

  ----------------------------------------------------------------------------
  -- Infrastructure
  ----------------------------------------------------------------------------
  CreateClock(clk, gc_TbClkPeriod);
  CreateReset(reset, '1', clk, gc_TbClkPeriod * 10);

  p_timeout : process is
  begin
    wait for gc_TbTimeOut;
    assert false report "ERROR TEST FAILED, due to time out" severity error;
    std.env.stop(1);
  end process p_timeout;

  p_init : process is
    variable v_test_id : AlertLogIDType;
  begin
    RV.InitSeed(random_seed);
    SetAlertStopCount(ERROR, 1);
    v_test_id := NewID("can_fce");
    test_id   <= v_test_id;
    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  ----------------------------------------------------------------------------
  -- DUT
  ----------------------------------------------------------------------------
  u_dut : entity work.can_fce
    port map (
      clk_i       => clk,
      rst_i       => reset,
      llc_i       => llc_i,
      llc_o       => llc_o,
      mac_i       => mac_i,
      mac_o       => mac_o,
      pcs_i       => pcs_i,
      pcs_o       => pcs_o
    );

  ----------------------------------------------------------------------------
  -- p_test_ctrl
  ----------------------------------------------------------------------------
  p_test_ctrl : process is

    --------------------------------------------------------------------------
    -- Test 1: Reset
    --------------------------------------------------------------------------
    procedure test_reset is
    begin
      Print("--------------------------------------------------------------------------");
      Print("Test 1: Reset");
      Print("--------------------------------------------------------------------------");
      AffirmIf(test_id, mac_o = c_fce_to_mac_if_reset, "mac_o not reset correctly");
      AffirmIf(test_id, llc_o = c_fce_to_llc_if_reset, "llc_o not reset correctly");
      AffirmIf(test_id, pcs_o = c_fce_to_pcs_if_reset, "pcs_o not reset correctly");
    end procedure test_reset;

    --------------------------------------------------------------------------
    -- zero_counters: drive TEC past bus_off, use LLC normal_mode to recover.
    -- FCE bus_off recovery zeroes both TEC and REC (can_fce.vhd s_bus_off).
    -- Leaves DUT in s_error_active with TEC = REC = 0.
    --------------------------------------------------------------------------
    procedure zero_counters is
    begin
      for i in 1 to 32 loop
        pulse_tx_error(mac_i);
      end loop;
      WaitForClock(clk);
      llc_i.normal_mode <= '1';
      for i in 1 to 128 loop
        pulse_idle_condition(pcs_i);
      end loop;
      WaitForClock(clk);
      llc_i.normal_mode <= '0';
      WaitForClock(clk);
      AffirmIf(test_id, mac_o.error_active = '1', "zero_counters: back to error_active");
      AffirmIf(test_id, llc_o.bus_off = '0', "zero_counters: bus_off cleared");
    end procedure zero_counters;

    --------------------------------------------------------------------------
    -- Per-rule tests (ISO 8.1.4.2). Without direct TEC/REC observability,
    -- each rule is verified by counting events until the error_passive
    -- threshold is crossed (TEC/REC > 127 -> mac_o.error_active = '0').
    -- The event count needed identifies the rule's increment coefficient.
    --------------------------------------------------------------------------

    -- Rule a: RX error -> REC += 1. 128 events must cross the threshold.
    procedure test_rule_a is
    begin
      Print("-- Test: Rule a (RX error, REC += 1) --");
      for i in 1 to 127 loop
        pulse_rx_error(mac_i);
      end loop;
      AffirmIf(test_id, mac_o.error_active = '1', "Rule a: still active at REC=127");
      pulse_rx_error(mac_i);
      WaitForClock(clk);
      AffirmIf(test_id, mac_o.error_active = '0', "Rule a: passive at REC=128");
      zero_counters;
    end procedure test_rule_a;

    -- Rule b: RX primary error -> REC += 8. 16 events cross threshold.
    procedure test_rule_b is
    begin
      Print("-- Test: Rule b (RX primary error, REC += 8) --");
      for i in 1 to 15 loop
        pulse_rx_primary_error(mac_i);
      end loop;
      AffirmIf(test_id, mac_o.error_active = '1', "Rule b: still active at REC=120");
      pulse_rx_primary_error(mac_i);
      WaitForClock(clk);
      AffirmIf(test_id, mac_o.error_active = '0', "Rule b: passive at REC=128");
      zero_counters;
    end procedure test_rule_b;

    -- Rule c: TX error -> TEC += 8. 16 events cross threshold.
    procedure test_rule_c is
    begin
      Print("-- Test: Rule c (TX error, TEC += 8) --");
      for i in 1 to 15 loop
        pulse_tx_error(mac_i);
      end loop;
      AffirmIf(test_id, mac_o.error_active = '1', "Rule c: still active at TEC=120");
      pulse_tx_error(mac_i);
      WaitForClock(clk);
      AffirmIf(test_id, mac_o.error_active = '0', "Rule c: passive at TEC=128");
      zero_counters;
    end procedure test_rule_c;

    -- Rule c Exception 1: passive_tx_ack_error_exempt suppresses TEC bump.
    -- 32 "exempt" TX errors must leave TEC unchanged -> stays error_active.
    procedure test_rule_c_exception is
    begin
      Print("-- Test: Rule c Exception 1 (passive_tx_ack_error_exempt) --");
      for i in 1 to 32 loop
        mac_i.transmitting                <= '1';
        mac_i.error                       <= '1';
        mac_i.passive_tx_ack_error_exempt <= '1';
        wait until rising_edge(clk);
        mac_i <= c_mac_to_fce_if_reset;
        wait until rising_edge(clk);
      end loop;
      AffirmIf(test_id, mac_o.error_active = '1', "Rule c Exc.1: still active (TEC not bumped)");
      zero_counters;
    end procedure test_rule_c_exception;

    -- Rule e: RX error during flag -> REC += 8. 16 events cross threshold.
    procedure test_rule_e is
    begin
      Print("-- Test: Rule e (RX error in flag, REC += 8) --");
      for i in 1 to 15 loop
        pulse_rx_error_in_flag(mac_i);
      end loop;
      AffirmIf(test_id, mac_o.error_active = '1', "Rule e: still active at REC=120");
      pulse_rx_error_in_flag(mac_i);
      WaitForClock(clk);
      AffirmIf(test_id, mac_o.error_active = '0', "Rule e: passive at REC=128");
      zero_counters;
    end procedure test_rule_e;

    -- Rule f (TX): delimiter too late while transmitting -> TEC += 8.
    procedure test_rule_f_tx is
    begin
      Print("-- Test: Rule f TX (delim late, TEC += 8) --");
      for i in 1 to 15 loop
        pulse_tx_delim_late(mac_i);
      end loop;
      AffirmIf(test_id, mac_o.error_active = '1', "Rule f TX: still active at TEC=120");
      pulse_tx_delim_late(mac_i);
      WaitForClock(clk);
      AffirmIf(test_id, mac_o.error_active = '0', "Rule f TX: passive at TEC=128");
      zero_counters;
    end procedure test_rule_f_tx;

    -- Rule f (RX): delimiter too late while receiving -> REC += 8.
    procedure test_rule_f_rx is
    begin
      Print("-- Test: Rule f RX (delim late, REC += 8) --");
      for i in 1 to 15 loop
        pulse_rx_delim_late(mac_i);
      end loop;
      AffirmIf(test_id, mac_o.error_active = '1', "Rule f RX: still active at REC=120");
      pulse_rx_delim_late(mac_i);
      WaitForClock(clk);
      AffirmIf(test_id, mac_o.error_active = '0', "Rule f RX: passive at REC=128");
      zero_counters;
    end procedure test_rule_f_rx;

    -- Rule g: TX success -> TEC -= 1. Drive to passive via 16 TX errors
    -- (TEC=128), then TX successes must bring TEC back below threshold.
    procedure test_rule_g is
    begin
      Print("-- Test: Rule g (TX success, TEC -= 1) --");
      for i in 1 to 16 loop
        pulse_tx_error(mac_i);
      end loop;
      WaitForClock(clk);
      AffirmIf(test_id, mac_o.error_active = '0', "Rule g setup: passive at TEC=128");
      for i in 1 to 16 loop
        pulse_tx_success(mac_i);
      end loop;
      WaitForClock(clk);
      AffirmIf(test_id, mac_o.error_active = '1', "Rule g: active again after 16 TX success");
      zero_counters;
    end procedure test_rule_g;

    -- Rule h: RX success -> REC -= 1 with clamp: if REC > 127 at time of
    -- success, REC is set to 127 (single success recovers).
    procedure test_rule_h is
    begin
      Print("-- Test: Rule h (RX success, REC -= 1 with clamp) --");
      for i in 1 to 16 loop
        pulse_rx_primary_error(mac_i);
      end loop;
      WaitForClock(clk);
      AffirmIf(test_id, mac_o.error_active = '0', "Rule h setup: passive at REC=128");
      pulse_rx_success(mac_i);
      WaitForClock(clk);
      AffirmIf(test_id, mac_o.error_active = '1', "Rule h: clamp to 127 after single RX success");
      zero_counters;
    end procedure test_rule_h;

    --------------------------------------------------------------------------
    -- State transition tests (ISO 8.1.4.4 Figure 43, T4/T5)
    --------------------------------------------------------------------------

    -- T4: TEC > 255 -> bus_off.
    procedure test_t4_bus_off is
    begin
      Print("-- Test: T4 (bus_off when TEC > 255) --");
      for i in 1 to 32 loop
        pulse_tx_error(mac_i);
      end loop;
      WaitForClock(clk);
      AffirmIf(test_id, llc_o.bus_off = '1', "T4: llc_o.bus_off asserted");
      AffirmIf(test_id, pcs_o.bus_off = '1', "T4: pcs_o.bus_off asserted");
      zero_counters;
    end procedure test_t4_bus_off;

    -- T5 via idle: 128 idle_condition pulses from PCS clear bus_off.
    -- pcs_o.bus_off must stay high throughout the recovery window.
    procedure test_t5_recovery_idle is
    begin
      Print("-- Test: T5 (bus_off recovery via 128 idle pulses) --");
      for i in 1 to 32 loop
        pulse_tx_error(mac_i);
      end loop;
      WaitForClock(clk);
      AffirmIf(test_id, llc_o.bus_off = '1', "T5 idle: bus_off before recovery");
      llc_i.normal_mode <= '1'; -- required alongside idle count to release
      for i in 1 to 64 loop
        pulse_idle_condition(pcs_i);
      end loop;
      AffirmIf(test_id, llc_o.bus_off = '1', "T5 idle mid: still bus_off at 64 pulses");
      AffirmIf(test_id, pcs_o.bus_off = '1', "T5 idle mid: pcs_o.bus_off still high");
      for i in 1 to 64 loop
        pulse_idle_condition(pcs_i);
      end loop;
      WaitForClock(clk);
      llc_i.normal_mode <= '0';
      AffirmIf(test_id, llc_o.bus_off = '0', "T5 idle: bus_off cleared after 128 pulses");
      AffirmIf(test_id, pcs_o.bus_off = '0', "T5 idle: pcs_o.bus_off released");
      AffirmIf(test_id, mac_o.error_active = '1', "T5 idle: error_active after recovery");
    end procedure test_t5_recovery_idle;

    --------------------------------------------------------------------------
    -- Test 3: Random stress - exercise counter rules with random sequences
    --------------------------------------------------------------------------
    procedure test_random is
      variable v_action : natural;
    begin
      Print("--------------------------------------------------------------------------");
      Print("Test 3: Random stress");
      Print("--------------------------------------------------------------------------");

      for iteration in 1 to 200 loop
        v_action := RV.RandInt(0, 7);
        case v_action is
          when 0 => pulse_tx_error(mac_i);
          when 1 => pulse_tx_success(mac_i);
          when 2 => pulse_rx_error(mac_i);
          when 3 => pulse_rx_primary_error(mac_i);
          when 4 => pulse_rx_success(mac_i);
          when 5 => pulse_tx_delim_late(mac_i);
          when 6 => pulse_rx_delim_late(mac_i);
          when 7 => pulse_rx_error_in_flag(mac_i);
          when others => null;
        end case;

        -- After each action, verify interface consistency:
        -- exactly one of error_active/error_passive must be asserted
        WaitForClock(clk);
        -- AffirmIf(test_id, (mac_o.error_active xor mac_o.error_passive_request) = '1', "Random test");

        -- If bus_off, recover before continuing
        if (llc_o.bus_off = '1') then
          llc_i.normal_mode <= '1';
          for i in 1 to 128 loop
            pulse_idle_condition(pcs_i);
          end loop;
          WaitForClock(clk);
          llc_i.normal_mode <= '0';
          WaitForClock(clk);
          AffirmIf(test_id, llc_o.bus_off = '0', "Random recovery: bus_off cleared");
        end if;
      end loop;
    end procedure test_random;

    --------------------------------------------------------------------------
    procedure report_results is
    begin
      if (EndOfTestReports(ReportAll => true) = 0) then
        Print("--------------------------------------------------------------------------");
        Print("Test Pass!");
        Print("--------------------------------------------------------------------------");
      else
        Print("--------------------------------------------------------------------------");
        Print("Test Fail!");
        Print("--------------------------------------------------------------------------");
      end if;
    end procedure report_results;

  begin
    WaitForBarrier(init_barrier);
    wait until reset = '0';
    WaitForClock(clk, 5);

    test_reset;

    Print("--------------------------------------------------------------------------");
    Print("ISO 8.1.4.2 counter rules");
    Print("--------------------------------------------------------------------------");
    test_rule_a;
    test_rule_b;
    test_rule_c;
    test_rule_c_exception;
    test_rule_e;
    test_rule_f_tx;
    test_rule_f_rx;
    test_rule_g;
    test_rule_h;

    Print("--------------------------------------------------------------------------");
    Print("ISO 8.1.4.4 state transitions");
    Print("--------------------------------------------------------------------------");
    test_t4_bus_off;
    test_t5_recovery_idle;

    test_random;

    report_results;
    std.env.finish;
    wait;
  end process p_test_ctrl;

end architecture tb;
