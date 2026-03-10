--------------------------------------------------------------------------------
-- Title      : CAN Fault Confinement Entity Testbench
-- Project    : CAN Bus Node
--------------------------------------------------------------------------------
-- File       : can_fce_tb.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Unit tests for can_fce.vhd, verifying TEC/REC counter rules
--              and state transitions per ISO 11898-1:2015 Section 8.1.4.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;

library osvvm;
  use osvvm.AlertLogPkg.all;

entity can_fce_tb is
end entity can_fce_tb;

architecture tb of can_fce_tb is

  constant clk_period    : time    := 10 ns;
  constant nom_bit_time  : integer := 20; -- Short for fast bus-off recovery tests

  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal tx_mac_i : can_mac_fce_if_s2d_t := mac_to_fce_if_reset_c;
  signal tx_mac_o : can_mac_fce_if_d2s_t;
  signal rx_mac_i : can_mac_fce_if_s2d_t := mac_to_fce_if_reset_c;
  signal rx_mac_o : can_mac_fce_if_d2s_t;
  signal rx_bus   : std_logic := '1'; -- Recessive by default
  signal ctrl     : can_fce_ctrl_t := fce_ctrl_reset_c;
  signal status   : can_fce_status_t;

  signal alert_id : AlertLogIDType;

  -- Helper: pulse a signal for one clock cycle
  procedure pulse_tx_error (
    signal s2d : inout can_mac_fce_if_s2d_t
  ) is
  begin
    s2d.transmitting <= true;
    s2d.error        <= true;
    wait for clk_period;
    s2d <= mac_to_fce_if_reset_c;
    s2d.transmitting <= true;
    wait for clk_period;
  end procedure pulse_tx_error;

  procedure pulse_tx_success (
    signal s2d : inOut can_mac_fce_if_s2d_t
  ) is
  begin
    s2d.transmitting        <= true;
    s2d.successful_transfer <= true;
    wait for clk_period;
    s2d <= mac_to_fce_if_reset_c;
    wait for clk_period;
  end procedure pulse_tx_success;

  procedure pulse_rx_error (
    signal s2d : inout can_mac_fce_if_s2d_t
  ) is
  begin
    s2d.transmitting <= false;
    s2d.error        <= true;
    wait for clk_period;
    s2d <= mac_to_fce_if_reset_c;
    wait for clk_period;
  end procedure pulse_rx_error;

  procedure pulse_rx_primary_error (
    signal s2d : inout can_mac_fce_if_s2d_t
  ) is
  begin
    s2d.transmitting  <= false;
    s2d.primary_error <= true;
    wait for clk_period;
    s2d <= mac_to_fce_if_reset_c;
    wait for clk_period;
  end procedure pulse_rx_primary_error;

  procedure pulse_rx_success (
    signal s2d : inout can_mac_fce_if_s2d_t
  ) is
  begin
    s2d.transmitting        <= false;
    s2d.successful_transfer <= true;
    wait for clk_period;
    s2d <= mac_to_fce_if_reset_c;
    wait for clk_period;
  end procedure pulse_rx_success;

  procedure pulse_tx_delim_late (
    signal s2d : inout can_mac_fce_if_s2d_t
  ) is
  begin
    s2d.transmitting             <= true;
    s2d.error_delimiter_too_late <= true;
    wait for clk_period;
    s2d <= mac_to_fce_if_reset_c;
    s2d.transmitting <= true;
    wait for clk_period;
  end procedure pulse_tx_delim_late;

begin

  -- Clock generation
  clk <= not clk after clk_period / 2;

  -- DUT instantiation
  dut : entity work.can_fce
    generic map (
      nom_bit_time => nom_bit_time
    )
    port map (
      clk_i    => clk,
      rst_i    => rst,
      tx_mac_i => tx_mac_i,
      tx_mac_o => tx_mac_o,
      rx_mac_i => rx_mac_i,
      rx_mac_o => rx_mac_o,
      rx_bus_i => rx_bus,
      ctrl_i   => ctrl,
      status_o => status
    );

  main_proc : process is

    variable test_count  : integer := 0;
    variable pass_count  : integer := 0;

    procedure check (
      constant name     : in string;
      constant got      : in integer;
      constant expected : in integer
    ) is
    begin
      if (got = expected) then
        pass_count := pass_count + 1;
      else
        Alert(alert_id, name & ": got " & integer'image(got) &
              ", expected " & integer'image(expected), ERROR);
      end if;
      test_count := test_count + 1;
    end procedure check;

    procedure check_state (
      constant name     : in string;
      constant got      : in fce_state_t;
      constant expected : in fce_state_t
    ) is
    begin
      if (got = expected) then
        pass_count := pass_count + 1;
      else
        Alert(alert_id, name & ": got " & fce_state_t'image(got) &
              ", expected " & fce_state_t'image(expected), ERROR);
      end if;
      test_count := test_count + 1;
    end procedure check_state;

  begin

    alert_id <= GetAlertLogID("can_fce_tb");
    wait for 0 ns;

    -- Release reset
    wait for 5 * clk_period;
    rst <= '0';
    wait for 2 * clk_period;

    ---------------------------------------------------------------------------
    -- Test 1: Reset state
    ---------------------------------------------------------------------------
    report "Test 1: Reset state";
    check("TEC after reset", status.tec, 0);
    check("REC after reset", status.rec, 0);
    check_state("State after reset", status.state, error_active);

    ---------------------------------------------------------------------------
    -- Test 2: Rule c - TX error -> TEC += 8
    ---------------------------------------------------------------------------
    report "Test 2: Rule c - TX error";
    pulse_tx_error(tx_mac_i);
    check("TEC after TX error", status.tec, 8);
    check("REC unchanged", status.rec, 0);

    ---------------------------------------------------------------------------
    -- Test 3: Rule c exception - counters_unchanged
    ---------------------------------------------------------------------------
    report "Test 3: Counters unchanged exception";
    tx_mac_i.transmitting      <= true;
    tx_mac_i.error             <= true;
    tx_mac_i.counters_unchanged <= true;
    wait for clk_period;
    tx_mac_i <= mac_to_fce_if_reset_c;
    wait for clk_period;
    check("TEC unchanged with exception", status.tec, 8);

    ---------------------------------------------------------------------------
    -- Test 4: Rule g - TX success -> TEC -= 1
    ---------------------------------------------------------------------------
    report "Test 4: Rule g - TX success";
    pulse_tx_success(tx_mac_i);
    check("TEC after success", status.tec, 7);

    ---------------------------------------------------------------------------
    -- Test 5: T2 - TEC crosses 128 -> error_passive
    ---------------------------------------------------------------------------
    report "Test 5: T2 transition to error_passive";
    -- TEC is 7, need > 127. That's 121 more -> 16 pulses of +8 = 128 -> TEC = 135
    for i in 1 to 16 loop
      pulse_tx_error(tx_mac_i);
    end loop;
    -- TEC should be 7 + 128 = 135
    check("TEC after 16 errors", status.tec, 135);
    check_state("State is error_passive", status.state, error_passive);

    ---------------------------------------------------------------------------
    -- Test 6: T3 - TEC back to 127 -> error_active
    ---------------------------------------------------------------------------
    report "Test 6: T3 transition back to error_active";
    -- TEC = 135, need <= 127. That's 9 successes -> TEC = 126
    for i in 1 to 9 loop
      pulse_tx_success(tx_mac_i);
    end loop;
    check("TEC after 9 successes", status.tec, 126);
    check_state("State is error_active", status.state, error_active);

    ---------------------------------------------------------------------------
    -- Test 7: T4 - TEC crosses 256 -> bus_off
    ---------------------------------------------------------------------------
    report "Test 7: T4 transition to bus_off";
    -- TEC = 126, need > 255. That's 130 more -> 17 errors of +8 = 136 -> TEC = 262
    for i in 1 to 17 loop
      pulse_tx_error(tx_mac_i);
    end loop;
    -- TEC = 126 + 136 = 262
    check("TEC after bus_off threshold", status.tec, 262);
    check_state("State is bus_off", status.state, bus_off);

    ---------------------------------------------------------------------------
    -- Test 8: T5 - 128 idle conditions -> error_active, counters = 0
    ---------------------------------------------------------------------------
    report "Test 8: T5 bus-off recovery";
    -- Bus is already recessive. Each idle condition requires 11 recessive bits
    -- sampled at nom_bit_time intervals. Need to wait for shift register to fill
    -- and then 128 idle detections.
    -- Each idle detection: shift reg fills after 11 ticks, then counts.
    -- Total: wait long enough for 128 + 11 idle detections worth of prescaler ticks.
    rx_bus <= '1'; -- Keep bus recessive
    -- Wait for 139 idle detections * nom_bit_time clock cycles
    wait for (139 * nom_bit_time + 10) * clk_period;
    check("TEC after recovery", status.tec, 0);
    check("REC after recovery", status.rec, 0);
    check_state("State after recovery", status.state, error_active);

    ---------------------------------------------------------------------------
    -- Test 9: Rule a - RX error -> REC += 1
    ---------------------------------------------------------------------------
    report "Test 9: Rule a - RX error";
    pulse_rx_error(rx_mac_i);
    check("REC after RX error", status.rec, 1);
    check("TEC unchanged", status.tec, 0);

    ---------------------------------------------------------------------------
    -- Test 10: Rule h - RX success with REC > 127 -> REC = 127
    ---------------------------------------------------------------------------
    report "Test 10: Rule h - RX success with REC > 127";
    -- First get REC > 127: REC = 1, need 127 more via primary errors (16 * 8 = 128)
    for i in 1 to 16 loop
      pulse_rx_primary_error(rx_mac_i);
    end loop;
    -- REC = 1 + 128 = 129
    check("REC before success", status.rec, 129);
    pulse_rx_success(rx_mac_i);
    check("REC set to 127 after success", status.rec, 127);

    ---------------------------------------------------------------------------
    -- Test 11: Rule d/f - delimiter_too_late -> TEC += 8 (transmitting)
    ---------------------------------------------------------------------------
    report "Test 11: Rule d/f - delimiter too late";
    -- First reduce REC back to avoid error_passive complications
    -- REC = 127, need <= 127 -> already at 127, one success brings it to 126
    pulse_rx_success(rx_mac_i);
    check("REC after success", status.rec, 126);
    pulse_tx_delim_late(tx_mac_i);
    check("TEC after delim late", status.tec, 8);

    ---------------------------------------------------------------------------
    -- Summary
    ---------------------------------------------------------------------------
    report "========================================";
    report "FCE Tests: " & integer'image(pass_count) & " / " &
           integer'image(test_count) & " passed";
    report "========================================";

    ReportAlerts;
    std.env.stop(0);

  end process main_proc;

end architecture tb;
