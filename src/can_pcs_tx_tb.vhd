--------------------------------------------------------------------------------
-- Title      : Testbench for CAN Physical Signaling Layer (PCS)
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_pcs_tx_tb.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: PCS-focused verification with two DUT configurations:
--
--              DUT 1 (dut_no_tdc): All default generics (prescaler = 16).
--              TDC disabled. Tests: reset/idle, nominal cadence, TX mapping,
--              bus polarity, data-phase SP-only monitoring.
--
--              DUT 2 (dut_tdc): Prescaler = 2. TDC enabled.
--              Tests: TDC measurement, SSP cadence in data phase,
--              CRC delimiter exit, TDC timeout fallback.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  use osvvm.AlertLogPkg.all;
  use work.can_timing_pkg.all;
  use work.pk_can_types.all;

entity can_pcs_tx_tb is
end entity can_pcs_tx_tb;

architecture test of can_pcs_tx_tb is

  constant clk_period_c : time := 10 ns;
  signal clk       : std_logic := '0';
  signal rst        : std_logic := '1';
  signal test_done  : boolean   := false;

  signal current_test_id : natural := 0;

  -- Timing constants (mid-range ISO Table 12 defaults)
  constant nom_bit_time_tq_c  : integer := 1 + 48 + 16 + 16;  -- 81
  constant data_bit_time_tq_c : integer := 1 + 4 + 4 + 4;     -- 13

  -- DUT 1: prescaler = 16, TDC disabled
  constant no_tdc_prescaler_c    : integer := t_prescaler'high / 2;
  constant no_tdc_nom_bit_clk_c  : integer := nom_bit_time_tq_c * no_tdc_prescaler_c;
  constant no_tdc_data_bit_clk_c : integer := data_bit_time_tq_c * no_tdc_prescaler_c;

  -- DUT 2: prescaler = 2, TDC enabled
  constant tdc_prescaler_c    : integer := 2;
  constant tdc_nom_bit_clk_c  : integer := nom_bit_time_tq_c * tdc_prescaler_c;
  constant tdc_data_bit_clk_c : integer := data_bit_time_tq_c * tdc_prescaler_c;

  constant loopback_delay_clk_c : integer := 50;
  constant loopback_delay_c     : time    := loopback_delay_clk_c * clk_period_c;

  -- DUT 1 signals
  signal mac_to_pcs_1 : t_can_mac_pcs_tx_if_m2s := c_mac_to_pcs_if_reset;
  signal pcs_to_mac_1 : t_can_mac_pcs_tx_if_s2m;
  signal tx_bus_1      : std_logic;
  signal rx_bus_1      : std_logic := c_recessive;

  -- DUT 2 signals
  signal mac_to_pcs_2 : t_can_mac_pcs_tx_if_m2s := c_mac_to_pcs_if_reset;
  signal pcs_to_mac_2 : t_can_mac_pcs_tx_if_s2m;
  signal tx_bus_2      : std_logic;
  signal rx_bus_2      : std_logic := c_recessive;

  signal loopback_enable_2 : boolean   := true;
  signal rx_bus_2_manual   : std_logic := c_recessive;
  signal rx_bus_2_loopback : std_logic := c_recessive;

begin

  clk <= not clk after clk_period_c / 2 when not test_done else '0';

  -- DUT 1: direct loopback
  loopback_1 : process is
  begin
    wait on tx_bus_1;
    rx_bus_1 <= transport tx_bus_1 after loopback_delay_c;
  end process loopback_1;

  -- DUT 2: switchable loopback
  rx_bus_2 <= rx_bus_2_loopback when loopback_enable_2 else rx_bus_2_manual;

  loopback_2 : process is
  begin
    wait on tx_bus_2;
    rx_bus_2_loopback <= transport tx_bus_2 after loopback_delay_c;
  end process loopback_2;

  dut_no_tdc : entity work.can_pcs_tx
    generic map (
      gc_tdc_enable => '0'
    )
    port map (
      clk_i         => clk,
      rst_i         => rst,
      mac_to_pcs_i  => mac_to_pcs_1,
      pcs_to_mac_o  => pcs_to_mac_1,
      tx_bus_o      => tx_bus_1,
      rx_bus_i      => rx_bus_1
    );

  dut_tdc : entity work.can_pcs_tx
    generic map (
      gc_prescaler => tdc_prescaler_c
    )
    port map (
      clk_i         => clk,
      rst_i         => rst,
      mac_to_pcs_i  => mac_to_pcs_2,
      pcs_to_mac_o  => pcs_to_mac_2,
      tx_bus_o      => tx_bus_2,
      rx_bus_i      => rx_bus_2
    );

  test_runner : process is

    procedure wait_clocks (
      num_clocks : positive
    ) is
    begin
      for i in 1 to num_clocks loop
        wait until rising_edge(clk);
      end loop;
    end procedure wait_clocks;

    procedure reset_duts is
    begin
      rst              <= '1';
      mac_to_pcs_1     <= c_mac_to_pcs_if_reset;
      mac_to_pcs_2     <= c_mac_to_pcs_if_reset;
      wait_clocks(5);
      rst <= '0';
      wait_clocks(2);
    end procedure reset_duts;

    --------------------------------------------------------------------------
    -- DUT 1 helpers: drive polarity for hold_clocks, valid stays high
    --------------------------------------------------------------------------
    procedure send_nom_bit_1 (
      pol         : std_logic;
      hold_clocks : positive := no_tdc_nom_bit_clk_c
    ) is
    begin
      mac_to_pcs_1.polarity <= pol;
      mac_to_pcs_1.valid    <= '1';
      wait_clocks(hold_clocks);
    end procedure send_nom_bit_1;

    procedure stop_frame_1 is
    begin
      mac_to_pcs_1 <= c_mac_to_pcs_if_reset;
    end procedure stop_frame_1;

    procedure wait_for_sp_1 (
      max_cycles    : positive;
      variable seen : out boolean;
      constant msg  : string
    ) is
    begin
      seen := false;
      for i in 1 to max_cycles loop
        wait until rising_edge(clk);
        if (pcs_to_mac_1.sp = '1') then
          seen := true;
          exit;
        end if;
      end loop;
      AlertIf(not seen, msg, ERROR);
    end procedure wait_for_sp_1;

    procedure assert_sp_period_1 (
      expected_cycles : positive;
      search_window   : positive;
      constant msg    : string
    ) is
      variable first_seen  : boolean;
      variable second_seen : boolean;
      variable period      : integer := 0;
    begin
      wait_for_sp_1(search_window, first_seen, msg & " (first pulse missing)");
      second_seen := false;
      period      := 0;
      for i in 1 to search_window loop
        wait until rising_edge(clk);
        period := period + 1;
        if (pcs_to_mac_1.sp = '1') then
          second_seen := true;
          exit;
        end if;
      end loop;
      AlertIf(not second_seen, msg & " (second pulse missing)", ERROR);
      AlertIf(period /= expected_cycles,
              msg & " expected " & integer'image(expected_cycles) &
              " cycles, got " & integer'image(period), ERROR);
    end procedure assert_sp_period_1;

    procedure assert_sp_period_1_n (
      expected_cycles : positive;
      num_periods     : positive;
      search_window   : positive;
      constant msg    : string
    ) is
    begin
      for k in 1 to num_periods loop
        assert_sp_period_1(expected_cycles, search_window, msg & " #" & integer'image(k));
      end loop;
    end procedure assert_sp_period_1_n;

    --------------------------------------------------------------------------
    -- DUT 2 helpers
    --------------------------------------------------------------------------
    procedure send_nom_bit_2 (
      pol         : std_logic;
      hold_clocks : positive := tdc_nom_bit_clk_c
    ) is
    begin
      mac_to_pcs_2.polarity <= pol;
      mac_to_pcs_2.valid    <= '1';
      wait_clocks(hold_clocks);
    end procedure send_nom_bit_2;

    procedure stop_frame_2 is
    begin
      mac_to_pcs_2 <= c_mac_to_pcs_if_reset;
    end procedure stop_frame_2;

    procedure wait_for_sp_2 (
      max_cycles    : positive;
      variable seen : out boolean;
      constant msg  : string
    ) is
    begin
      seen := false;
      for i in 1 to max_cycles loop
        wait until rising_edge(clk);
        if (pcs_to_mac_2.sp = '1') then
          seen := true;
          exit;
        end if;
      end loop;
      AlertIf(not seen, msg, ERROR);
    end procedure wait_for_sp_2;

    procedure wait_for_ssp_2 (
      max_cycles    : positive;
      variable seen : out boolean;
      constant msg  : string
    ) is
    begin
      seen := false;
      for i in 1 to max_cycles loop
        wait until rising_edge(clk);
        if (pcs_to_mac_2.ssp = '1') then
          seen := true;
          exit;
        end if;
      end loop;
      AlertIf(not seen, msg, ERROR);
    end procedure wait_for_ssp_2;

    procedure assert_sp_period_2 (
      expected_cycles : positive;
      search_window   : positive;
      constant msg    : string
    ) is
      variable first_seen  : boolean;
      variable second_seen : boolean;
      variable period      : integer := 0;
    begin
      wait_for_sp_2(search_window, first_seen, msg & " (first pulse missing)");
      second_seen := false;
      period      := 0;
      for i in 1 to search_window loop
        wait until rising_edge(clk);
        period := period + 1;
        if (pcs_to_mac_2.sp = '1') then
          second_seen := true;
          exit;
        end if;
      end loop;
      AlertIf(not second_seen, msg & " (second pulse missing)", ERROR);
      AlertIf(period /= expected_cycles,
              msg & " expected " & integer'image(expected_cycles) &
              " cycles, got " & integer'image(period), ERROR);
    end procedure assert_sp_period_2;

    procedure assert_ssp_period_2 (
      expected_cycles : positive;
      search_window   : positive;
      constant msg    : string
    ) is
      variable first_seen  : boolean;
      variable second_seen : boolean;
      variable period      : integer := 0;
    begin
      wait_for_ssp_2(search_window, first_seen, msg & " (first SSP pulse missing)");
      second_seen := false;
      period      := 0;
      for i in 1 to search_window loop
        wait until rising_edge(clk);
        period := period + 1;
        if (pcs_to_mac_2.ssp = '1') then
          second_seen := true;
          exit;
        end if;
      end loop;
      AlertIf(not second_seen, msg & " (second SSP pulse missing)", ERROR);
      AlertIf(period /= expected_cycles,
              msg & " expected " & integer'image(expected_cycles) &
              " cycles, got " & integer'image(period), ERROR);
    end procedure assert_ssp_period_2;

    procedure assert_ssp_period_2_n (
      expected_cycles : positive;
      num_periods     : positive;
      search_window   : positive;
      constant msg    : string
    ) is
    begin
      for k in 1 to num_periods loop
        assert_ssp_period_2(expected_cycles, search_window, msg & " #" & integer'image(k));
      end loop;
    end procedure assert_ssp_period_2_n;

    procedure assert_sp_period_2_n (
      expected_cycles : positive;
      num_periods     : positive;
      search_window   : positive;
      constant msg    : string
    ) is
    begin
      for k in 1 to num_periods loop
        assert_sp_period_2(expected_cycles, search_window, msg & " #" & integer'image(k));
      end loop;
    end procedure assert_sp_period_2_n;

    -- Enter FD data phase on DUT 2:
    -- SOF (nominal) -> FDF with start_tdc (nominal) -> res (nominal) -> BRS with use_data_rate
    procedure enter_fd_data_phase_2 is
    begin
      -- SOF: dominant, nominal
      send_nom_bit_2(c_dominant);
      -- FDF: recessive, start_tdc high so PCS enters measuring state
      mac_to_pcs_2.polarity  <= c_recessive;
      mac_to_pcs_2.start_tdc <= '1';
      wait_clocks(tdc_nom_bit_clk_c * 2);
      mac_to_pcs_2.start_tdc <= '0';
      -- res: dominant, still nominal, TDC measuring
      send_nom_bit_2(c_dominant, tdc_nom_bit_clk_c * 3);
      -- BRS: recessive, assert use_data_rate -> switches to data bit time
      mac_to_pcs_2.polarity      <= c_recessive;
      mac_to_pcs_2.use_data_rate <= '1';
      wait_clocks(tdc_nom_bit_clk_c * 2);
    end procedure enter_fd_data_phase_2;

    variable pulse_seen : boolean;

  begin
    SetLogEnable(INFO, true);
    SetLogEnable(PASSED, true);
    current_test_id <= 0;

    --------------------------------------------------------------------------
    -- Test 1: Reset and idle defaults
    --------------------------------------------------------------------------
    current_test_id <= 1;
    Log("Test 1: Reset and idle defaults (DUT 1)", INFO);
    reset_duts;

    AlertIf(tx_bus_1 /= c_recessive, "TX bus should be recessive after reset", ERROR);
    AlertIf(pcs_to_mac_1.bus_polarity /= c_recessive, "Bus polarity should be recessive", ERROR);

    Log("Test 1 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- Test 2: Idle sample-strobe cadence (nominal timing)
    --------------------------------------------------------------------------
    current_test_id <= 2;
    Log("Test 2: Idle sample-strobe cadence (DUT 1)", INFO);

    assert_sp_period_1_n(
      expected_cycles => no_tdc_nom_bit_clk_c,
      num_periods     => 3,
      search_window   => no_tdc_nom_bit_clk_c * 2,
      msg             => "Idle nominal sample cadence"
    );

    Log("Test 2 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- Test 3: Nominal transmission cadence and TX mapping
    --------------------------------------------------------------------------
    current_test_id <= 3;
    Log("Test 3: Nominal TX cadence and TX mapping (DUT 1)", INFO);

    -- Send dominant SOF
    send_nom_bit_1(c_dominant);

    pulse_seen := false;
    for i in 1 to no_tdc_nom_bit_clk_c loop
      wait until rising_edge(clk);
      if (tx_bus_1 = c_dominant) then
        pulse_seen := true;
        exit;
      end if;
    end loop;
    AlertIf(not pulse_seen, "SOF must drive dominant TX bus", ERROR);

    -- Send recessive
    send_nom_bit_1(c_recessive);

    pulse_seen := false;
    for i in 1 to no_tdc_nom_bit_clk_c loop
      wait until rising_edge(clk);
      if (tx_bus_1 = c_recessive) then
        pulse_seen := true;
        exit;
      end if;
    end loop;
    AlertIf(not pulse_seen, "Recessive bit must drive recessive TX bus", ERROR);

    assert_sp_period_1_n(
      expected_cycles => no_tdc_nom_bit_clk_c,
      num_periods     => 2,
      search_window   => no_tdc_nom_bit_clk_c * 2,
      msg             => "Nominal phase sample cadence"
    );

    stop_frame_1;
    wait_clocks(no_tdc_nom_bit_clk_c);

    Log("Test 3 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- Test 4: Bus polarity indication mapping
    --------------------------------------------------------------------------
    current_test_id <= 4;
    Log("Test 4: Bus polarity indication mapping (DUT 1)", INFO);

    reset_duts;

    send_nom_bit_1(c_dominant);
    wait_clocks(loopback_delay_clk_c + 2);
    AlertIf(pcs_to_mac_1.bus_polarity /= c_dominant, "bus_polarity should be dominant RX", ERROR);

    reset_duts;
    wait_clocks(loopback_delay_clk_c + 2);
    AlertIf(pcs_to_mac_1.bus_polarity /= c_recessive, "bus_polarity should be recessive RX", ERROR);

    Log("Test 4 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- Test 5: TDC-disabled path uses SP in data phase
    --------------------------------------------------------------------------
    current_test_id <= 5;
    Log("Test 5: TDC-disabled data phase uses SP (DUT 1)", INFO);

    reset_duts;

    -- SOF
    send_nom_bit_1(c_dominant);
    -- FDF (start_tdc not used on DUT 1, but set it for completeness)
    mac_to_pcs_1.polarity  <= c_recessive;
    mac_to_pcs_1.start_tdc <= '1';
    wait_clocks(no_tdc_nom_bit_clk_c * 2);
    mac_to_pcs_1.start_tdc <= '0';
    -- res
    send_nom_bit_1(c_dominant, no_tdc_nom_bit_clk_c);
    -- BRS -> data phase
    mac_to_pcs_1.polarity      <= c_recessive;
    mac_to_pcs_1.use_data_rate <= '1';
    wait_clocks(no_tdc_nom_bit_clk_c);
    -- Data bits in data phase
    mac_to_pcs_1.polarity <= c_dominant;
    wait_clocks(no_tdc_data_bit_clk_c * 5);

    wait_for_sp_1(
      max_cycles => no_tdc_data_bit_clk_c * 2,
      seen       => pulse_seen,
      msg        => "No-TDC DUT did not generate data-phase sample pulse"
    );
    assert_sp_period_1(
      expected_cycles => no_tdc_data_bit_clk_c,
      search_window   => no_tdc_nom_bit_clk_c * 2,
      msg             => "No-TDC DUT data-phase sample cadence"
    );

    mac_to_pcs_1.use_data_rate <= '0';
    stop_frame_1;
    wait_clocks(no_tdc_nom_bit_clk_c);

    Log("Test 5 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- Test 6: TDC measurement and SSP cadence in FD data phase
    --------------------------------------------------------------------------
    current_test_id <= 6;
    Log("Test 6: TDC measurement and SSP cadence (DUT 2)", INFO);

    reset_duts;
    loopback_enable_2 <= true;

    enter_fd_data_phase_2;
    -- Data bits in data phase
    mac_to_pcs_2.polarity <= c_dominant;
    wait_clocks(tdc_data_bit_clk_c * 5);

    wait_for_ssp_2(3 * tdc_nom_bit_clk_c, pulse_seen, "Data phase SSP pulse not observed");

    assert_ssp_period_2_n(
      expected_cycles => tdc_data_bit_clk_c,
      num_periods     => 3,
      search_window   => tdc_nom_bit_clk_c * 2,
      msg             => "SSP cadence in data field"
    );

    Log("Test 6 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- Test 7: Stuff bit keeps SSP monitoring (still in data phase)
    --------------------------------------------------------------------------
    current_test_id <= 7;
    Log("Test 7: SSP monitoring continues in data phase (DUT 2)", INFO);

    -- Still in data phase, change polarity (simulates stuff bit)
    mac_to_pcs_2.polarity <= c_recessive;
    wait_clocks(tdc_data_bit_clk_c * 4);

    wait_for_ssp_2(2 * tdc_data_bit_clk_c, pulse_seen, "SSP pulse not observed after polarity change");
    assert_ssp_period_2_n(
      expected_cycles => tdc_data_bit_clk_c,
      num_periods     => 2,
      search_window   => tdc_nom_bit_clk_c * 2,
      msg             => "SSP cadence continues"
    );

    Log("Test 7 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- Test 8: CRC field uses SSP monitoring
    --------------------------------------------------------------------------
    current_test_id <= 8;
    Log("Test 8: SSP monitoring for CRC (DUT 2)", INFO);

    mac_to_pcs_2.polarity <= c_dominant;
    wait_clocks(tdc_data_bit_clk_c * 4);

    wait_for_ssp_2(2 * tdc_data_bit_clk_c, pulse_seen, "CRC-field SSP pulse not observed");
    assert_ssp_period_2_n(
      expected_cycles => tdc_data_bit_clk_c,
      num_periods     => 2,
      search_window   => tdc_nom_bit_clk_c * 2,
      msg             => "SSP cadence in CRC field"
    );

    Log("Test 8 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- Test 9: Exit data phase (MAC drops use_data_rate)
    --------------------------------------------------------------------------
    current_test_id <= 9;
    Log("Test 9: Exit data phase (DUT 2)", INFO);

    -- MAC drops use_data_rate (CRC delimiter)
    mac_to_pcs_2.use_data_rate <= '0';
    mac_to_pcs_2.polarity      <= c_recessive;
    wait_clocks(tdc_nom_bit_clk_c * 2);

    -- Now in nominal phase again
    mac_to_pcs_2.polarity <= c_recessive;
    wait_clocks(tdc_nom_bit_clk_c * 2);

    assert_sp_period_2_n(
      expected_cycles => tdc_nom_bit_clk_c,
      num_periods     => 2,
      search_window   => tdc_nom_bit_clk_c * 2,
      msg             => "Nominal cadence after data phase exit"
    );

    stop_frame_2;
    wait_clocks(tdc_nom_bit_clk_c);

    Log("Test 9 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- Test 10: TDC timeout fallback when RX edge never arrives
    --------------------------------------------------------------------------
    current_test_id <= 10;
    Log("Test 10: TDC timeout fallback (DUT 2)", INFO);

    reset_duts;
    loopback_enable_2 <= false;
    rx_bus_2_manual   <= c_recessive;

    -- SOF
    send_nom_bit_2(c_dominant);
    -- FDF with start_tdc
    mac_to_pcs_2.polarity  <= c_recessive;
    mac_to_pcs_2.start_tdc <= '1';
    wait_clocks(tdc_nom_bit_clk_c * 2);
    mac_to_pcs_2.start_tdc <= '0';
    -- res (hold long enough for TDC to timeout)
    mac_to_pcs_2.polarity <= c_dominant;
    wait_clocks(c_max_transmitter_delay + 40);
    -- Data phase
    mac_to_pcs_2.polarity      <= c_dominant;
    mac_to_pcs_2.use_data_rate <= '1';
    wait_clocks(tdc_data_bit_clk_c * 4);

    -- Drop back to nominal
    mac_to_pcs_2.use_data_rate <= '0';
    wait_clocks(tdc_nom_bit_clk_c * 2);

    assert_sp_period_2_n(
      expected_cycles => tdc_nom_bit_clk_c,
      num_periods     => 2,
      search_window   => tdc_nom_bit_clk_c * 2,
      msg             => "Nominal cadence after TDC timeout"
    );

    stop_frame_2;
    loopback_enable_2 <= true;
    rx_bus_2_manual   <= c_recessive;
    wait_clocks(tdc_nom_bit_clk_c);

    Log("Test 10 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- Test 11: Timing helper functions
    --------------------------------------------------------------------------
    current_test_id <= 11;
    Log("Test 11: Timing helper functions", INFO);

    AlertIf(calculate_tdc_delay(0, 49) /= 0,
            "Delay 0 should map to TDC delay 0", ERROR);
    AlertIf(calculate_tdc_delay(49, 49) /= 1,
            "Delay 49 should map to TDC delay 1", ERROR);
    AlertIf(calculate_tdc_delay(98, 49) /= 2,
            "Delay 98 should map to TDC delay 2", ERROR);
    AlertIf(calculate_tdc_delay(1600, 49) /= c_tdc_polarity_depth - 1,
            "Large delay should clamp to TDC depth-1", ERROR);

    AlertIf(not should_use_tdc(
              100_000_000,
              tdc_prescaler_c,
              1, 4, 4, 4,
              pcs_to_pma_propagation_delay_ns => 400),
            "Fast FD timing should request TDC", ERROR);

    AlertIf(should_use_tdc(
              1_000_000,
              32, 1, 128, 128, 128,
              pcs_to_pma_propagation_delay_ns => 10),
            "Very slow timing should not require TDC", ERROR);

    Log("Test 11 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- Summary
    --------------------------------------------------------------------------
    Log("================================================================================", INFO);
    Log("All can_pcs_tx unit tests completed", INFO);
    Log("================================================================================", INFO);

    ReportAlerts;
    test_done <= true;
    wait;

  end process test_runner;

end architecture test;
