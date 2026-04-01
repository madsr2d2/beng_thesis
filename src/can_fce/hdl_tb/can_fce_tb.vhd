--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Unit tests for can_fce.vhd, verifying TEC/REC counter rules
--                and state transitions per ISO 11898-1:2015 Section 8.1.4.
--                Tests all three FCE interfaces: LLC, MAC, and PCS.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-31  MRDSA     Converted to company header format
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

library osvvm;
  use osvvm.AlertLogPkg.all;

entity can_fce_tb is
end entity can_fce_tb;

architecture tb of can_fce_tb is

  constant clk_period   : time    := 10 ns;
  constant nom_bit_time : natural := 20;

  -- FCE state encoding (matches DUT constants)
  constant c_error_active  : std_logic_vector(1 downto 0) := "00";
  constant c_error_passive : std_logic_vector(1 downto 0) := "01";
  constant c_bus_off       : std_logic_vector(1 downto 0) := "10";

  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';

  signal llc_i    : t_can_llc_fce_if_m2s := c_llc_to_fce_if_reset;
  signal llc_o    : t_can_fce_llc_if_s2m;

  signal tx_mac_i : t_can_mac_fce_if_m2s := c_mac_to_fce_if_reset;
  signal tx_mac_o : t_can_mac_fce_if_s2m;
  signal rx_mac_i : t_can_mac_fce_if_m2s := c_mac_to_fce_if_reset;
  signal rx_mac_o : t_can_mac_fce_if_s2m;

  signal pcs_i    : t_can_pcs_fce_if_s2m := c_pcs_to_fce_if_reset;
  signal pcs_o    : t_can_fce_pcs_if_m2s;

  signal rx_bus   : std_logic := '1';

  signal debug_tec   : natural range 0 to 511;
  signal debug_rec   : natural range 0 to 255;
  signal debug_state : std_logic_vector(1 downto 0);

  signal alert_id : AlertLogIDType;

  procedure pulse_tx_error (
    signal s2d : inout t_can_mac_fce_if_m2s
  ) is
  begin
    s2d.transmitting <= '1';
    s2d.error        <= '1';
    wait for clk_period;
    s2d              <= c_mac_to_fce_if_reset;
    s2d.transmitting <= '1';
    wait for clk_period;
  end procedure pulse_tx_error;

  procedure pulse_tx_success (
    signal s2d : inOut t_can_mac_fce_if_m2s
  ) is
  begin
    s2d.transmitting        <= '1';
    s2d.successful_transfer <= '1';
    wait for clk_period;
    s2d                     <= c_mac_to_fce_if_reset;
    wait for clk_period;
  end procedure pulse_tx_success;

  procedure pulse_rx_error (
    signal s2d : inout t_can_mac_fce_if_m2s
  ) is
  begin
    s2d.transmitting <= '0';
    s2d.error        <= '1';
    wait for clk_period;
    s2d              <= c_mac_to_fce_if_reset;
    wait for clk_period;
  end procedure pulse_rx_error;

  procedure pulse_rx_primary_error (
    signal s2d : inout t_can_mac_fce_if_m2s
  ) is
  begin
    s2d.transmitting  <= '0';
    s2d.primary_error <= '1';
    wait for clk_period;
    s2d               <= c_mac_to_fce_if_reset;
    wait for clk_period;
  end procedure pulse_rx_primary_error;

  procedure pulse_rx_success (
    signal s2d : inout t_can_mac_fce_if_m2s
  ) is
  begin
    s2d.transmitting        <= '0';
    s2d.successful_transfer <= '1';
    wait for clk_period;
    s2d                     <= c_mac_to_fce_if_reset;
    wait for clk_period;
  end procedure pulse_rx_success;

  procedure pulse_tx_delim_late (
    signal s2d : inout t_can_mac_fce_if_m2s
  ) is
  begin
    s2d.transmitting             <= '1';
    s2d.error_delimiter_too_late <= '1';
    wait for clk_period;
    s2d                          <= c_mac_to_fce_if_reset;
    s2d.transmitting             <= '1';
    wait for clk_period;
  end procedure pulse_tx_delim_late;

begin

  clk <= not clk after clk_period / 2;

  dut : entity work.can_fce
    generic map (
      gc_nom_bit_time => nom_bit_time
    )
    port map (
      clk_i         => clk,
      rst_i         => rst,
      llc_i         => llc_i,
      llc_o         => llc_o,
      tx_mac_i      => tx_mac_i,
      tx_mac_o      => tx_mac_o,
      rx_mac_i      => rx_mac_i,
      rx_mac_o      => rx_mac_o,
      pcs_i         => pcs_i,
      pcs_o         => pcs_o,
      rx_bus_i      => rx_bus,
      debug_tec_o   => debug_tec,
      debug_rec_o   => debug_rec,
      debug_state_o => debug_state
    );

  main_proc : process is

    variable test_count : natural := 0;
    variable pass_count : natural := 0;

    procedure check (
      constant name     : in string;
      constant got      : in natural;
      constant expected : in natural
    ) is
    begin
      if (got = expected) then
        pass_count := pass_count + 1;
      else
        Alert(alert_id, name & ": got " & natural'image(got) &
              ", expected " & natural'image(expected), ERROR);
      end if;
      test_count := test_count + 1;
    end procedure check;

    procedure check_state (
      constant name     : in string;
      constant got      : in std_logic_vector(1 downto 0);
      constant expected : in std_logic_vector(1 downto 0)
    ) is
    begin
      if (got = expected) then
        pass_count := pass_count + 1;
      else
        Alert(alert_id, name & ": state mismatch", ERROR);
      end if;
      test_count := test_count + 1;
    end procedure check_state;

    procedure check_sl (
      constant name     : in string;
      constant got      : in std_logic;
      constant expected : in std_logic
    ) is
    begin
      if (got = expected) then
        pass_count := pass_count + 1;
      else
        Alert(alert_id, name & ": got " & std_logic'image(got) &
              ", expected " & std_logic'image(expected), ERROR);
      end if;
      test_count := test_count + 1;
    end procedure check_sl;

  begin

    alert_id <= GetAlertLogID("can_fce_tb");
    wait for 0 ns;

    wait for 5 * clk_period;
    rst <= '0';
    wait for 2 * clk_period;

    ---------------------------------------------------------------------------
    -- Test 1: Reset state
    ---------------------------------------------------------------------------
    report "Test 1: Reset state";
    check("TEC after reset", debug_tec, 0);
    check("REC after reset", debug_rec, 0);
    check_state("State after reset", debug_state, c_error_active);
    check_sl("LLC bus_off deasserted", llc_o.bus_off, '0');
    check_sl("MAC error_active asserted", tx_mac_o.error_active_request, '1');

    ---------------------------------------------------------------------------
    -- Test 2: Rule c - TX error -> TEC += 8
    ---------------------------------------------------------------------------
    report "Test 2: Rule c - TX error";
    pulse_tx_error(tx_mac_i);
    check("TEC after TX error", debug_tec, 8);
    check("REC unchanged", debug_rec, 0);

    ---------------------------------------------------------------------------
    -- Test 3: Rule c exception - counters_unchanged
    ---------------------------------------------------------------------------
    report "Test 3: Counters unchanged exception";
    tx_mac_i.transmitting       <= '1';
    tx_mac_i.error              <= '1';
    tx_mac_i.counters_unchanged <= '1';
    wait for clk_period;
    tx_mac_i                    <= c_mac_to_fce_if_reset;
    wait for clk_period;
    check("TEC unchanged with exception", debug_tec, 8);

    ---------------------------------------------------------------------------
    -- Test 4: Rule g - TX success -> TEC -= 1
    ---------------------------------------------------------------------------
    report "Test 4: Rule g - TX success";
    pulse_tx_success(tx_mac_i);
    check("TEC after success", debug_tec, 7);

    ---------------------------------------------------------------------------
    -- Test 5: T2 - TEC crosses 128 -> error_passive
    ---------------------------------------------------------------------------
    report "Test 5: T2 transition to error_passive";
    for i in 1 to 16 loop
      pulse_tx_error(tx_mac_i);
    end loop;
    check("TEC after 16 errors", debug_tec, 135);
    check_state("State is error_passive", debug_state, c_error_passive);
    check_sl("MAC error_passive asserted", tx_mac_o.error_passive_request, '1');

    ---------------------------------------------------------------------------
    -- Test 6: T3 - TEC back to 127 -> error_active
    ---------------------------------------------------------------------------
    report "Test 6: T3 transition back to error_active";
    for i in 1 to 9 loop
      pulse_tx_success(tx_mac_i);
    end loop;
    check("TEC after 9 successes", debug_tec, 126);
    check_state("State is error_active", debug_state, c_error_active);

    ---------------------------------------------------------------------------
    -- Test 7: T4 - TEC crosses 256 -> bus_off
    ---------------------------------------------------------------------------
    report "Test 7: T4 transition to bus_off";
    for i in 1 to 17 loop
      pulse_tx_error(tx_mac_i);
    end loop;
    check("TEC after bus_off threshold", debug_tec, 262);
    check_state("State is bus_off", debug_state, c_bus_off);
    check_sl("LLC bus_off asserted", llc_o.bus_off, '1');

    ---------------------------------------------------------------------------
    -- Test 8: T5 - 128 idle conditions -> error_active, counters = 0
    ---------------------------------------------------------------------------
    report "Test 8: T5 bus-off recovery";
    rx_bus <= '1';
    wait for (139 * nom_bit_time + 10) * clk_period;
    check("TEC after recovery", debug_tec, 0);
    check("REC after recovery", debug_rec, 0);
    check_state("State after recovery", debug_state, c_error_active);
    check_sl("LLC bus_off deasserted after recovery", llc_o.bus_off, '0');

    ---------------------------------------------------------------------------
    -- Test 9: Rule a - RX error -> REC += 1
    ---------------------------------------------------------------------------
    report "Test 9: Rule a - RX error";
    pulse_rx_error(rx_mac_i);
    check("REC after RX error", debug_rec, 1);
    check("TEC unchanged", debug_tec, 0);

    ---------------------------------------------------------------------------
    -- Test 10: Rule h - RX success with REC > 127 -> REC = 127
    ---------------------------------------------------------------------------
    report "Test 10: Rule h - RX success with REC > 127";
    for i in 1 to 16 loop
      pulse_rx_primary_error(rx_mac_i);
    end loop;
    check("REC before success", debug_rec, 129);
    pulse_rx_success(rx_mac_i);
    check("REC set to 127 after success", debug_rec, 127);

    ---------------------------------------------------------------------------
    -- Test 11: Rule d/f - delimiter_too_late -> TEC += 8 (transmitting)
    ---------------------------------------------------------------------------
    report "Test 11: Rule d/f - delimiter too late";
    pulse_rx_success(rx_mac_i);
    check("REC after success", debug_rec, 126);
    pulse_tx_delim_late(tx_mac_i);
    check("TEC after delim late", debug_tec, 8);

    ---------------------------------------------------------------------------
    -- Test 12: LLC normal_mode_request during bus-off -> recovery
    ---------------------------------------------------------------------------
    report "Test 12: LLC normal_mode_request recovery";
    -- Drive into bus_off first
    for i in 1 to 32 loop
      pulse_tx_error(tx_mac_i);
    end loop;
    check_state("State is bus_off", debug_state, c_bus_off);

    -- Issue normal_mode_request
    llc_i.normal_mode_request <= '1';
    wait for clk_period;
    llc_i.normal_mode_request <= '0';
    wait for clk_period;

    check("TEC after normal_mode", debug_tec, 0);
    check("REC after normal_mode", debug_rec, 0);
    check_state("State after normal_mode", debug_state, c_error_active);
    check_sl("LLC bus_off deasserted", llc_o.bus_off, '0');

    ---------------------------------------------------------------------------
    -- Summary
    ---------------------------------------------------------------------------
    report "========================================";
    report "FCE Tests: " & natural'image(pass_count) & " / " &
           natural'image(test_count) & " passed";
    report "========================================";

    ReportAlerts;
    std.env.stop(0);

  end process main_proc;

end architecture tb;
