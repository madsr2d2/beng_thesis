--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Test bench for can_fce. Tests error counter and bus-off logic (ISO : 8.1.4.2-4) 
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-04-10  TMYAES:   [TRIT-4336] [FPGA] CAN FD extensions of TRIT-3880
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pk_can_types.all;

library osvvm;
context osvvm.OsvvmContext;

entity can_fce_tb is
  generic(
    gc_TbTimeOut   : time := 50 ms;
    gc_TbClkPeriod : time := 10 ns
  );
end entity can_fce_tb;

architecture tb of can_fce_tb is

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal clk              : std_logic;
  signal reset            : std_logic            := '1';
  -- DUT interface -----------------------------------------------------------
  signal llc_i            : t_can_llc_fce_if_m2s := c_llc_to_fce_if_reset;
  signal llc_o            : t_can_fce_llc_if_s2m;
  signal mac_i            : t_can_mac_fce_if_m2s := c_mac_to_fce_if_reset;
  signal mac_o            : t_can_mac_fce_if_s2m;
  signal pcs_i            : t_can_pcs_fce_if_s2m := c_pcs_to_fce_if_reset;
  signal pcs_o            : t_can_fce_pcs_if_m2s;
  ----------------------------------------------------------------------------
  signal test_id          : AlertLogIDType;
  signal bus_off          : AlertLogIDType;
  signal bus_off_recovery : AlertLogIDType;
  signal rule_a           : AlertLogIDType;
  signal rule_b           : AlertLogIDType;
  signal rule_c_d         : AlertLogIDType;
  signal rule_e           : AlertLogIDType;
  signal rule_f           : AlertLogIDType;
  signal rule_g           : AlertLogIDType;
  signal rule_h           : AlertLogIDType;
  signal init_barrier     : std_logic            := '0';

  ----------------------------------------------------------------------------
  -- Pulse procedures
  ----------------------------------------------------------------------------
  procedure pulse_tx_error(signal s2d : inout t_can_mac_fce_if_m2s) is
  begin
    s2d.transmitting <= '1';
    s2d.error        <= '1';
    wait until rising_edge(clk);
    s2d              <= c_mac_to_fce_if_reset;
    s2d.transmitting <= '1';
    wait until rising_edge(clk);
  end procedure pulse_tx_error;
  procedure pulse_tx_success(signal s2d : inout t_can_mac_fce_if_m2s) is
  begin
    s2d.transmitting        <= '1';
    s2d.successful_transfer <= '1';
    wait until rising_edge(clk);
    s2d                     <= c_mac_to_fce_if_reset;
    wait until rising_edge(clk);
  end procedure pulse_tx_success;

  procedure pulse_rx_error(signal s2d : inout t_can_mac_fce_if_m2s) is
  begin
    s2d.transmitting <= '0';
    s2d.error        <= '1';
    wait until rising_edge(clk);
    s2d              <= c_mac_to_fce_if_reset;
    wait until rising_edge(clk);
  end procedure pulse_rx_error;

  procedure pulse_rx_primary_error(signal s2d : inout t_can_mac_fce_if_m2s) is
  begin
    s2d.transmitting  <= '0';
    s2d.primary_error <= '1';
    wait until rising_edge(clk);
    s2d               <= c_mac_to_fce_if_reset;
    wait until rising_edge(clk);
  end procedure pulse_rx_primary_error;

  procedure pulse_rx_success(signal s2d : inout t_can_mac_fce_if_m2s) is
  begin
    s2d.transmitting        <= '0';
    s2d.successful_transfer <= '1';
    wait until rising_edge(clk);
    s2d                     <= c_mac_to_fce_if_reset;
    wait until rising_edge(clk);
  end procedure pulse_rx_success;

  procedure pulse_tx_delim_late(signal s2d : inout t_can_mac_fce_if_m2s) is
  begin
    s2d.transmitting             <= '1';
    s2d.error_delimiter_too_late <= '1';
    wait until rising_edge(clk);
    s2d                          <= c_mac_to_fce_if_reset;
    s2d.transmitting             <= '1';
    wait until rising_edge(clk);
  end procedure pulse_tx_delim_late;

  procedure pulse_rx_delim_late(signal s2d : inout t_can_mac_fce_if_m2s) is
  begin
    s2d.transmitting             <= '0';
    s2d.error_delimiter_too_late <= '1';
    wait until rising_edge(clk);
    s2d                          <= c_mac_to_fce_if_reset;
    wait until rising_edge(clk);
  end procedure pulse_rx_delim_late;

  procedure pulse_rx_error_in_flag(signal s2d : inout t_can_mac_fce_if_m2s) is
  begin
    s2d.transmitting                <= '0';
    s2d.error                       <= '1';
    s2d.sending_error_overload_flag <= '1';
    wait until rising_edge(clk);
    s2d                             <= c_mac_to_fce_if_reset;
    wait until rising_edge(clk);
  end procedure pulse_rx_error_in_flag;
  procedure pulse_idle_condition(signal pcs : inout t_can_pcs_fce_if_s2m) is
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

  p_timeout : process is
  begin
    wait for gc_TbTimeOut;
    assert false report "ERROR TEST FAILED, due to time out" severity error;
    std.env.stop(1);
  end process p_timeout;

  p_init : process is
    variable v_test_id          : AlertLogIDType;
    variable v_rule_a           : AlertLogIDType;
    variable v_rule_b           : AlertLogIDType;
    variable v_rule_c_d         : AlertLogIDType;
    variable v_rule_e           : AlertLogIDType;
    variable v_rule_f           : AlertLogIDType;
    variable v_rule_g           : AlertLogIDType;
    variable v_rule_h           : AlertLogIDType;
    variable v_bus_off          : AlertLogIDType;
    variable v_bus_off_recovery : AlertLogIDType;
  begin
    SetAlertStopCount(ERROR, 1);
    v_test_id          := NewID("can_fce");
    v_bus_off          := NewID("can_bus_off");
    v_bus_off_recovery := NewID("can_bus_off_recovery");
    v_rule_a           := NewID("fce_rule_a");
    v_rule_b           := NewID("fce_rule_b");
    v_rule_c_d         := NewID("fce_rule_c/d");
    v_rule_e           := NewID("fce_rule_e");
    v_rule_f           := NewID("fce_rule_f");
    v_rule_g           := NewID("fce_rule_g");
    v_rule_h           := NewID("fce_rule_h");
    test_id            <= v_test_id;
    bus_off            <= v_bus_off;
    bus_off_recovery   <= v_bus_off_recovery;
    rule_a             <= v_rule_a;
    rule_b             <= v_rule_b;
    rule_c_d           <= v_rule_c_d;
    rule_e             <= v_rule_e;
    rule_f             <= v_rule_f;
    rule_g             <= v_rule_g;
    rule_h             <= v_rule_h;
    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  ----------------------------------------------------------------------------
  -- DUT
  ----------------------------------------------------------------------------
  u_dut : entity work.can_fce
    port map(
      clk_i => clk,
      rst_i => reset,
      llc_i => llc_i,
      llc_o => llc_o,
      mac_i => mac_i,
      mac_o => mac_o,
      pcs_i => pcs_i,
      pcs_o => pcs_o
    );

  ----------------------------------------------------------------------------
  -- p_test_ctrl
  ----------------------------------------------------------------------------
  p_test_ctrl : process is
    --------------------------------------------------------------------------
    -- Test 1: Reset
    --------------------------------------------------------------------------
    procedure reset_dut is
    begin
      reset <= '1';
      WaitForClock(clk, 5);
      reset <= '0';
      WaitForClock(clk, 5);
    end procedure reset_dut;

    procedure test_reset is
    begin
      reset_dut;
      AffirmIf(test_id, mac_o = c_fce_to_mac_if_reset, "mac_o not reset correctly");
      AffirmIf(test_id, llc_o = c_fce_to_llc_if_reset, "llc_o not reset correctly");
      AffirmIf(test_id, pcs_o = c_fce_to_pcs_if_reset, "pcs_o not reset correctly");
    end procedure test_reset;

    --------------------------------------------------------------------------
    -- Test 2: Error counter tests (ISO : 8.1.4.2)
    --------------------------------------------------------------------------
    -- Rule a: RX error -> REC += 1 ------------------------------------------
    procedure test_rule_a is
    begin
      reset_dut;
      for i in 1 to 127 loop
        pulse_rx_error(mac_i);
      end loop;
      AffirmIf(rule_a, mac_o.error_active = '1', "Rule a: still active at REC=127");
      pulse_rx_error(mac_i);
      WaitForClock(clk);
      AffirmIf(rule_a, mac_o.error_active = '0', "Rule a: passive at REC=128");
    end procedure test_rule_a;

    -- Rule b: RX primary error -> REC += 8 ----------------------------------
    procedure test_rule_b is
    begin
      reset_dut;
      for i in 1 to 15 loop
        pulse_rx_primary_error(mac_i);
      end loop;
      AffirmIf(rule_b, mac_o.error_active = '1', "Rule b: still active at REC=120");
      pulse_rx_primary_error(mac_i);
      WaitForClock(clk);
      AffirmIf(rule_b, mac_o.error_active = '0', "Rule b: passive at REC=128");
    end procedure test_rule_b;

    -- Rule c/d: TX error -> TEC += 8 ----------------------------------------
    procedure test_rule_c_d is
    begin
      reset_dut;
      for i in 1 to 15 loop
        pulse_tx_error(mac_i);
      end loop;
      AffirmIf(rule_c_d, mac_o.error_active = '1', "Rule c: still active at TEC=120");
      pulse_tx_error(mac_i);
      WaitForClock(clk);
      AffirmIf(rule_c_d, mac_o.error_active = '0', "Rule c: passive at TEC=128");
    end procedure test_rule_c_d;

    -- Rule c Except. 1: passive_tx_ack_error_exempt_1 suppresses TEC count --
    procedure test_rule_c_exception is
    begin
      reset_dut;
      for i in 1 to 16 loop
        mac_i.transmitting                  <= '1';
        mac_i.error                         <= '1';
        mac_i.passive_tx_ack_error_exempt_1 <= '1';
        wait until rising_edge(clk);
      end loop;
      AffirmIf(rule_c_d, mac_o.error_active = '1', "Rule c Exc.1: still active");
    end procedure test_rule_c_exception;

    -- Rule e: RX error during flag -> REC += 8 ------------------------------
    procedure test_rule_e is
    begin
      reset_dut;
      for i in 1 to 15 loop
        pulse_rx_error_in_flag(mac_i);
      end loop;
      AffirmIf(rule_e, mac_o.error_active = '1', "Rule e: still active at REC=120");
      pulse_rx_error_in_flag(mac_i);
      WaitForClock(clk);
      AffirmIf(rule_e, mac_o.error_active = '0', "Rule e: passive at REC=128");
    end procedure test_rule_e;

    -- Rule f (TX): delimiter too late while transmitting -> TEC += 8 --------
    procedure test_rule_f_tx is
    begin
      reset_dut;
      for i in 1 to 15 loop
        pulse_tx_delim_late(mac_i);
      end loop;
      AffirmIf(rule_f, mac_o.error_active = '1', "Rule f TX: still active at TEC=120");
      pulse_tx_delim_late(mac_i);
      WaitForClock(clk);
      AffirmIf(rule_f, mac_o.error_active = '0', "Rule f TX: passive at TEC=128");
    end procedure test_rule_f_tx;

    -- Rule f (RX): delimiter too late while receiving -> REC += 8 -----------
    procedure test_rule_f_rx is
    begin
      reset_dut;
      for i in 1 to 15 loop
        pulse_rx_delim_late(mac_i);
      end loop;
      AffirmIf(rule_f, mac_o.error_active = '1', "Rule f RX: still active at REC=120");
      pulse_rx_delim_late(mac_i);
      WaitForClock(clk);
      AffirmIf(rule_f, mac_o.error_active = '0', "Rule f RX: passive at REC=128");
    end procedure test_rule_f_rx;

    -- Rule g: TX success -> TEC -= 1 ----------------------------------------
    procedure test_rule_g is
    begin
      reset_dut;
      for i in 1 to 16 loop
        pulse_tx_error(mac_i);
      end loop;
      WaitForClock(clk);
      AffirmIf(rule_g, mac_o.error_active = '0', "Rule g setup: passive at TEC=128");
      pulse_tx_success(mac_i);
      WaitForClock(clk);
      AffirmIf(rule_g, mac_o.error_active = '1', "Rule g: active again after success at TCE=128");
    end procedure test_rule_g;

    -- Rule h: RX success -> REC -= 1 ----------------------------------------
    procedure test_rule_h is
    begin
      reset_dut;
      for i in 1 to 16 loop
        pulse_rx_primary_error(mac_i);
      end loop;
      WaitForClock(clk);
      AffirmIf(rule_h, mac_o.error_active = '0', "Rule h setup: passive at REC=128");
      pulse_rx_success(mac_i);
      WaitForClock(clk);
      AffirmIf(rule_h, mac_o.error_active = '1', "Rule h: active again after success at REC=128");
    end procedure test_rule_h;

    --------------------------------------------------------------------------
    -- Bus-off test
    --------------------------------------------------------------------------
    procedure test_bus_off is
    begin
      reset_dut;
      for i in 1 to 32 loop
        pulse_tx_error(mac_i);
      end loop;
      WaitForClock(clk);
      AffirmIf(bus_off, llc_o.bus_off = '1', "llc_o.bus_off asserted");
      AffirmIf(bus_off, pcs_o.bus_off = '1', "pcs_o.bus_off asserted");
    end procedure test_bus_off;

    procedure test_bus_off_recovery is
    begin
      reset_dut;
      for i in 1 to 32 loop
        pulse_tx_error(mac_i);
      end loop;
      WaitForClock(clk);
      AffirmIf(bus_off_recovery, llc_o.bus_off = '1', "Bus_off before recovery");
      llc_i.normal_mode <= '1';                                                 -- required alongside idle count to release bus-off

      for i in 1 to 64 loop
        pulse_idle_condition(pcs_i);
      end loop;
      AffirmIf(bus_off_recovery, pcs_o.bus_off = '1', "pcs_o.bus_off still high after 64 idle_condition strobes");

      for i in 1 to 64 loop
        pulse_idle_condition(pcs_i);
      end loop;
      WaitForClock(clk);
      llc_i.normal_mode <= '0';

      AffirmIf(bus_off_recovery, llc_o.bus_off = '0', "llc_o.bus_off cleared after 128 pulses");
      AffirmIf(bus_off_recovery, pcs_o.bus_off = '0', "pcs_o.bus_off cleared after 128 pulses");
      AffirmIf(bus_off_recovery, mac_o.error_active = '1', "error_active after recovery");
    end procedure test_bus_off_recovery;

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
    Print("--------------------------------------------------------------------------");
    Print("Test 1: Reset");
    Print("--------------------------------------------------------------------------");
    test_reset;
    Print("--------------------------------------------------------------------------");
    Print("Test 2: Error counter rules");
    Print("--------------------------------------------------------------------------");
    test_rule_a;
    test_rule_b;
    test_rule_c_d;
    test_rule_c_exception;
    test_rule_e;
    test_rule_f_tx;
    test_rule_f_rx;
    test_rule_g;
    test_rule_h;
    Print("--------------------------------------------------------------------------");
    Print("Test 3: Bus-off rules");
    Print("--------------------------------------------------------------------------");
    test_bus_off;
    test_bus_off_recovery;
    report_results;
    std.env.finish;
  end process p_test_ctrl;
end architecture tb;
