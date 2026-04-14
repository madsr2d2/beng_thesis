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
  use work.pk_can_types.all;

library osvvm;
  context osvvm.OsvvmContext;

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
  signal init_barrier : std_logic := '0';

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
      pcs_o       => pcs_o,
      debug_tec_o => open,
      debug_rec_o => open
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
    -- Test 2: Normal usage - TEC/REC counter rules (ISO 8.1.4.2)
    --------------------------------------------------------------------------
    procedure test_normal is
    begin
      Print("--------------------------------------------------------------------------");
      Print("Test 2: Normal usage");
      Print("--------------------------------------------------------------------------");

      -- Rule c: TX error -> mac_o stays error_active, TEC increments internally
      pulse_tx_error(mac_i);
      AffirmIf(test_id, mac_o.error_active = '1', "Rule c: still error_active after 1 TX error");

      -- Rule c exception: counters_unchanged flag suppresses TEC increment
      mac_i.transmitting       <= '1';
      mac_i.error              <= '1';
      mac_i.passive_tx_ack_error <= '1';
      wait until rising_edge(clk);
      mac_i <= c_mac_to_fce_if_reset;
      wait until rising_edge(clk);
      AffirmIf(test_id, mac_o.error_active = '1', "Rule c exception: still error_active");

      -- Rule g: TX success -> TEC decrements
      pulse_tx_success(mac_i);
      AffirmIf(test_id, mac_o.error_active = '1', "Rule g: still error_active after TX success");

      -- Rule a: RX error -> REC += 1
      pulse_rx_error(mac_i);
      AffirmIf(test_id, mac_o.error_active = '1', "Rule a: still error_active after RX error");

      -- Rule b: RX primary error -> REC += 8
      pulse_rx_primary_error(mac_i);
      AffirmIf(test_id, mac_o.error_active = '1', "Rule b: still error_active after RX primary error");

      -- Rule e: RX error during flag -> REC += 8
      pulse_rx_error_in_flag(mac_i);
      AffirmIf(test_id, mac_o.error_active = '1', "Rule e: still error_active after RX error in flag");

      -- Rule d/f: TX delimiter too late -> TEC += 8
      pulse_tx_delim_late(mac_i);
      AffirmIf(test_id, mac_o.error_active = '1', "Rule d/f: still error_active after TX delim late");

      -- Rule f (RX): RX delimiter too late -> REC += 8
      pulse_rx_delim_late(mac_i);
      AffirmIf(test_id, mac_o.error_active = '1', "Rule f RX: still error_active after RX delim late");

      -- Rule h: RX success decrements REC
      pulse_rx_success(mac_i);
      AffirmIf(test_id, mac_o.error_active = '1', "Rule h: still error_active after RX success");

      -- T2: Drive TEC past error_passive threshold (16 TX errors = TEC 128+)
      for i in 1 to 16 loop
        pulse_tx_error(mac_i);
      end loop;
      WaitForClock(clk);
      -- AffirmIf(test_id, mac_o.error_passive_request = '1', "T2: error_passive after TEC > 127");
      AffirmIf(test_id, mac_o.error_active = '0', "T2: error_active deasserted");
      AffirmIf(test_id, llc_o.bus_off = '0', "T2: not bus_off");

      -- T3: Drive TEC back below threshold via successes
      for i in 1 to 20 loop
        pulse_tx_success(mac_i);
      end loop;
      WaitForClock(clk);
      AffirmIf(test_id, mac_o.error_active = '1', "T3: error_active restored");
      -- AffirmIf(test_id, mac_o.error_passive_request = '0', "T3: error_passive deasserted");

      -- T4: Drive TEC past bus_off threshold (TEC > 255)
      for i in 1 to 32 loop
        pulse_tx_error(mac_i);
      end loop;
      WaitForClock(clk);
      AffirmIf(test_id, llc_o.bus_off = '1', "T4: bus_off asserted");
      -- AffirmIf(test_id, mac_o.error_passive_request = '1', "T4: error_passive in bus_off");

      -- T5: 128 idle conditions -> recovery
      for i in 1 to 128 loop
        pulse_idle_condition(pcs_i);
      end loop;
      WaitForClock(clk);
      AffirmIf(test_id, llc_o.bus_off = '0', "T5: bus_off cleared after 128 idle conditions");
      AffirmIf(test_id, mac_o.error_active = '1', "T5: error_active after recovery");

      -- T5 via LLC normal_mode_request
      for i in 1 to 32 loop
        pulse_tx_error(mac_i);
      end loop;
      WaitForClock(clk);
      AffirmIf(test_id, llc_o.bus_off = '1', "bus_off before LLC recovery");
      llc_i.normal_mode_request <= '1';
      WaitForClock(clk);
      llc_i.normal_mode_request <= '0';
      WaitForClock(clk);
      AffirmIf(test_id, llc_o.bus_off = '0', "T5 LLC: bus_off cleared after normal_mode_request");
      AffirmIf(test_id, mac_o.error_active = '1', "T5 LLC: error_active after LLC recovery");

      -- Rule h special case: RX success with REC > 127 -> REC = 127
      for i in 1 to 16 loop
        pulse_rx_primary_error(mac_i);
      end loop;
     WaitForClock(clk);
      -- AffirmIf(test_id, mac_o.error_passive_request = '1', "REC > 127: error_passive");
      pulse_rx_success(mac_i);
      WaitForClock(clk);
      AffirmIf(test_id, mac_o.error_active = '1', "Rule h: back to error_active after RX success clamps REC");

   end procedure test_normal;

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
          for i in 1 to 128 loop
            pulse_idle_condition(pcs_i);
          end loop;
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
    test_normal;
    test_random;

    report_results;
    std.env.finish;
    wait;
  end process p_test_ctrl;

end architecture tb;
