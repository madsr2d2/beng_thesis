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
--              The large prescaler makes data bit time >> 1 us and fails the
--              prescaler validity check (must be 1 or 2), so TDC is disabled.
--              Tests: reset/idle, nominal cadence, TX mapping, bus polarity,
--              data-phase SP-only monitoring.
--
--              DUT 2 (dut_tdc): Default generics with prescaler overridden to 2.
--              Data bit time = 260 ns (< 1 us threshold) and prescaler is valid,
--              so TDC is enabled. Tests: TDC measurement, SSP cadence in data/
--              stuff/CRC fields, CRC delimiter exit, TDC timeout fallback.
--
--              Both DUTs share the same mid-range ISO 11898-1 Table 12 timing
--              segments (the entity defaults).
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  use osvvm.AlertLogPkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;
  use work.can_types_pkg.all;

entity can_pcs_tx_tb is
end entity can_pcs_tx_tb;

architecture test of can_pcs_tx_tb is

  ------------------------------------------------------------------------------
  -- Clock / reset
  ------------------------------------------------------------------------------
  constant clk_period_c : time := 10 ns; -- 100 MHz
  signal clk       : std_logic := '0';
  signal rst        : std_logic := '1';
  signal test_done  : boolean   := false;

  -- Waveform marker: 0 = idle/reset, 1..N = test id, last = done.
  signal current_test_id : natural := 0;

  ------------------------------------------------------------------------------
  -- Timing constants derived from entity defaults (mid-range ISO Table 12)
  --
  -- The entity declares:
  --   prescaler      := prescaler'high / 2          = 16
  --   nom_prop_seg   := nominal_prop_seg'high / 2   = 48
  --   nom_phase_seg1 := nominal_phase_seg1'high / 2 = 16
  --   nom_phase_seg2 := nominal_phase_seg2'high / 2 = 16
  --   data_prop_seg  := data_prop_seg'high / 2      = 4
  --   data_phase_seg1:= data_phase_seg1'high / 2    = 4
  --   data_phase_seg2:= data_phase_seg2'high / 2    = 4
  --   ssp_offset     := ssp_offset'high / 2         = 31
  --   nom_sync_seg / data_sync_seg                  = 1
  ------------------------------------------------------------------------------
  constant nom_bit_time_tq_c  : integer := 1 + 48 + 16 + 16;  -- 81
  constant data_bit_time_tq_c : integer := 1 + 4 + 4 + 4;     -- 13
  constant ssp_offset_c       : integer := ssp_offset'high / 2; -- 31

  -- DUT 1: default prescaler (16) - TDC disabled
  constant no_tdc_prescaler_c    : integer := prescaler'high / 2; -- 16
  constant no_tdc_nom_bit_clk_c  : integer := nom_bit_time_tq_c * no_tdc_prescaler_c;  -- 1296
  constant no_tdc_data_bit_clk_c : integer := data_bit_time_tq_c * no_tdc_prescaler_c; -- 208

  -- DUT 2: prescaler = 2 - TDC enabled
  constant tdc_prescaler_c    : integer := 2;
  constant tdc_nom_bit_clk_c  : integer := nom_bit_time_tq_c * tdc_prescaler_c;  -- 162
  constant tdc_data_bit_clk_c : integer := data_bit_time_tq_c * tdc_prescaler_c; -- 26

  ------------------------------------------------------------------------------
  -- Loopback delay (shared by both DUTs, only meaningful for TDC DUT)
  ------------------------------------------------------------------------------
  constant loopback_delay_clk_c : integer := 50;
  constant loopback_delay_c     : time    := loopback_delay_clk_c * clk_period_c;

  -- Expected FIFO index for DUT 2 after TDC measurement:
  --   TDCV physical  = loopback_delay - rx_capture_latency = 50 - 1 = 49 clocks
  --   offset in clks = ssp_offset * prescaler = 31 * 2 = 62
  --   tx pipeline    = 2 clocks
  --   total clks     = 49 + 62 + 2 = 113
  --   total TQ       = ceil(113 / 2) = 57
  --   fifo_index     = 57 / 13 = 4
  constant expected_fifo_index_c : integer := 4;

  ------------------------------------------------------------------------------
  -- DUT 1 (no TDC) signals
  ------------------------------------------------------------------------------
  signal mac_to_pcs_1 : can_mac_pcs_tx_if_m2s_t := (
    data  => unknown_mac_frame_bit_c,
    valid => false
  );
  signal pcs_to_mac_1 : can_mac_pcs_tx_if_s2m_t;
  signal tx_bus_1      : std_logic;
  signal rx_bus_1      : std_logic := recessive_bit_c;

  ------------------------------------------------------------------------------
  -- DUT 2 (TDC) signals
  ------------------------------------------------------------------------------
  signal mac_to_pcs_2 : can_mac_pcs_tx_if_m2s_t := (
    data  => unknown_mac_frame_bit_c,
    valid => false
  );
  signal pcs_to_mac_2 : can_mac_pcs_tx_if_s2m_t;
  signal tx_bus_2      : std_logic;
  signal rx_bus_2      : std_logic := recessive_bit_c;

  -- Loopback control (DUT 2 only, DUT 1 uses direct loopback)
  signal loopback_enable_2 : boolean   := true;
  signal rx_bus_2_manual   : std_logic := recessive_bit_c;
  signal rx_bus_2_loopback : std_logic := recessive_bit_c;

begin

  ------------------------------------------------------------------------------
  -- Clock generation
  ------------------------------------------------------------------------------
  clk <= not clk after clk_period_c / 2 when not test_done else '0';

  ------------------------------------------------------------------------------
  -- Loopback wiring
  ------------------------------------------------------------------------------

  -- DUT 1: direct loopback (no TDC, delay irrelevant)
  loopback_1 : process is
  begin
    wait on tx_bus_1;
    rx_bus_1 <= transport tx_bus_1 after loopback_delay_c;
  end process loopback_1;

  -- DUT 2: switchable loopback for TDC measurement and timeout tests
  rx_bus_2 <= rx_bus_2_loopback when loopback_enable_2 else rx_bus_2_manual;

  loopback_2 : process is
  begin
    wait on tx_bus_2;
    rx_bus_2_loopback <= transport tx_bus_2 after loopback_delay_c;
  end process loopback_2;

  ------------------------------------------------------------------------------
  -- DUT 1: all default generics (prescaler = 16, TDC disabled)
  ------------------------------------------------------------------------------
  dut_no_tdc : entity work.can_pcs_tx
    generic map (
      tdc_enable => false
    )
    port map (
      clk           => clk,
      rst           => rst,
      mac_to_pcs_i  => mac_to_pcs_1,
      pcs_to_mac_o  => pcs_to_mac_1,
      tx_bus_o      => tx_bus_1,
      rx_bus_i      => rx_bus_1,
      debug_state_o => open
    );

  ------------------------------------------------------------------------------
  -- DUT 2: prescaler = 2, all other generics default (TDC enabled)
  ------------------------------------------------------------------------------
  dut_tdc : entity work.can_pcs_tx
    generic map (
      prescaler => tdc_prescaler_c
    )
    port map (
      clk           => clk,
      rst           => rst,
      mac_to_pcs_i  => mac_to_pcs_2,
      pcs_to_mac_o  => pcs_to_mac_2,
      tx_bus_o      => tx_bus_2,
      rx_bus_i      => rx_bus_2,
      debug_state_o => open
    );

  ------------------------------------------------------------------------------
  -- Main test process
  ------------------------------------------------------------------------------
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
      rst <= '1';
      mac_to_pcs_1.valid <= false;
      mac_to_pcs_1.data  <= unknown_mac_frame_bit_c;
      mac_to_pcs_2.valid <= false;
      mac_to_pcs_2.data  <= unknown_mac_frame_bit_c;
      wait_clocks(5);
      rst <= '0';
      wait_clocks(2);
    end procedure reset_duts;

    --------------------------------------------------------------------------
    -- DUT 1 helpers
    --------------------------------------------------------------------------
    procedure send_bit_1 (
      bit_to_send : mac_frame_bit_t;
      hold_clocks : positive := no_tdc_nom_bit_clk_c
    ) is
    begin
      mac_to_pcs_1.data  <= bit_to_send;
      mac_to_pcs_1.valid <= true;
      wait_clocks(hold_clocks);
    end procedure send_bit_1;

    procedure stop_frame_1 is
    begin
      mac_to_pcs_1.valid <= false;
      mac_to_pcs_1.data  <= unknown_mac_frame_bit_c;
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
        if (pcs_to_mac_1.sample_strobe = '1') then
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
        if (pcs_to_mac_1.sample_strobe = '1') then
          second_seen := true;
          exit;
        end if;
      end loop;

      AlertIf(not second_seen, msg & " (second pulse missing)", ERROR);
      AlertIf(period /= expected_cycles,
              msg & " expected " & integer'image(expected_cycles) &
              " cycles, got " & integer'image(period),
              ERROR);
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
    procedure send_bit_2 (
      bit_to_send : mac_frame_bit_t;
      hold_clocks : positive := tdc_nom_bit_clk_c
    ) is
    begin
      mac_to_pcs_2.data  <= bit_to_send;
      mac_to_pcs_2.valid <= true;
      wait_clocks(hold_clocks);
    end procedure send_bit_2;

    procedure stop_frame_2 is
    begin
      mac_to_pcs_2.valid <= false;
      mac_to_pcs_2.data  <= unknown_mac_frame_bit_c;
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
        if (pcs_to_mac_2.sample_strobe = '1') then
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
        if (pcs_to_mac_2.sample_strobe = '1' and pcs_to_mac_2.strobe_type = ssp_strobe) then
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
        if (pcs_to_mac_2.sample_strobe = '1') then
          second_seen := true;
          exit;
        end if;
      end loop;

      AlertIf(not second_seen, msg & " (second pulse missing)", ERROR);
      AlertIf(period /= expected_cycles,
              msg & " expected " & integer'image(expected_cycles) &
              " cycles, got " & integer'image(period),
              ERROR);
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
        if (pcs_to_mac_2.sample_strobe = '1' and pcs_to_mac_2.strobe_type = ssp_strobe) then
          second_seen := true;
          exit;
        end if;
      end loop;

      AlertIf(not second_seen, msg & " (second SSP pulse missing)", ERROR);
      AlertIf(period /= expected_cycles,
              msg & " expected " & integer'image(expected_cycles) &
              " cycles, got " & integer'image(period),
              ERROR);
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

    -- Enter FD data phase on DUT 2 (TDC path): SOF -> FDF -> res -> BRS -> data
    procedure enter_fd_data_phase_2 is
    begin
      send_bit_2((polarity => dominant, bit_name => sof_bit));
      send_bit_2((polarity => recessive, bit_name => fdf_bit), tdc_nom_bit_clk_c * 2);
      send_bit_2((polarity => dominant, bit_name => res_bit), tdc_nom_bit_clk_c * 3);
      send_bit_2((polarity => recessive, bit_name => brs_bit), tdc_nom_bit_clk_c * 2);
    end procedure enter_fd_data_phase_2;

    variable pulse_seen : boolean;

  begin
    SetLogEnable(INFO, true);
    SetLogEnable(PASSED, true);
    current_test_id <= 0;

    --------------------------------------------------------------------------
    -- DUT 1 TESTS (no TDC, prescaler = 16)
    --------------------------------------------------------------------------

    --------------------------------------------------------------------------
    -- Test 1: Reset and idle defaults
    --------------------------------------------------------------------------
    current_test_id <= 1;
    Log("Test 1: Reset and idle defaults (DUT 1)", INFO);
    reset_duts;

    AlertIf(tx_bus_1 /= recessive_bit_c, "TX bus should be recessive after reset", ERROR);
    AlertIf(pcs_to_mac_1.bus_polarity /= recessive, "Bus polarity should decode recessive", ERROR);
    AlertIf(pcs_to_mac_1.fifo_index /= 0, "FIFO index should be 0 after reset", ERROR);

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
    AlertIf(pcs_to_mac_1.fifo_index /= 0, "FIFO index must remain 0 in idle", ERROR);

    Log("Test 2 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- Test 3: Nominal transmission cadence and TX mapping
    --------------------------------------------------------------------------
    current_test_id <= 3;
    Log("Test 3: Nominal TX cadence and TX mapping (DUT 1)", INFO);

    send_bit_1((polarity => dominant, bit_name => sof_bit));

    -- Wait for TX bus to reflect dominant
    pulse_seen := false;
    for i in 1 to no_tdc_nom_bit_clk_c loop
      wait until rising_edge(clk);
      if (tx_bus_1 = dominant_bit_c) then
        pulse_seen := true;
        exit;
      end if;
    end loop;
    AlertIf(not pulse_seen, "SOF must drive dominant TX bus", ERROR);

    send_bit_1((polarity => recessive, bit_name => base_id_bit));

    pulse_seen := false;
    for i in 1 to no_tdc_nom_bit_clk_c loop
      wait until rising_edge(clk);
      if (tx_bus_1 = recessive_bit_c) then
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
    AlertIf(pcs_to_mac_1.fifo_index /= 0, "Nominal phase must use FIFO index 0", ERROR);

    stop_frame_1;
    wait_clocks(no_tdc_nom_bit_clk_c);

    Log("Test 3 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- Test 4: Bus polarity indication mapping
    --------------------------------------------------------------------------
    current_test_id <= 4;
    Log("Test 4: Bus polarity indication mapping (DUT 1)", INFO);

    reset_duts;

    -- Force dominant via loopback: send dominant bit
    send_bit_1((polarity => dominant, bit_name => sof_bit));
    wait_clocks(loopback_delay_clk_c + 2);
    AlertIf(pcs_to_mac_1.bus_polarity /= dominant, "bus_polarity should decode dominant RX", ERROR);

    -- Reset puts TX recessive; wait for loopback to propagate recessive back
    reset_duts;
    wait_clocks(loopback_delay_clk_c + 2);
    AlertIf(pcs_to_mac_1.bus_polarity /= recessive, "bus_polarity should decode recessive RX", ERROR);

    Log("Test 4 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- Test 5: TDC-disabled path uses SP in data phase, FIFO index 0
    --------------------------------------------------------------------------
    current_test_id <= 5;
    Log("Test 5: TDC-disabled data phase uses SP (DUT 1)", INFO);

    reset_duts;

    send_bit_1((polarity => dominant, bit_name => sof_bit));
    send_bit_1((polarity => recessive, bit_name => fdf_bit), no_tdc_nom_bit_clk_c * 2);
    send_bit_1((polarity => dominant, bit_name => res_bit), no_tdc_nom_bit_clk_c);
    send_bit_1((polarity => recessive, bit_name => brs_bit), no_tdc_nom_bit_clk_c);
    send_bit_1((polarity => dominant, bit_name => data_bit), no_tdc_data_bit_clk_c * 5);

    wait_for_sp_1(
      max_cycles => no_tdc_data_bit_clk_c * 2,
      seen       => pulse_seen,
      msg        => "No-TDC DUT did not generate data-phase sample pulse"
    );
    AlertIf(pcs_to_mac_1.fifo_index /= 0,
            "No-TDC DUT must keep FIFO index at 0 in data phase",
            ERROR);
    assert_sp_period_1(
      expected_cycles => no_tdc_data_bit_clk_c,
      search_window   => no_tdc_nom_bit_clk_c * 2,
      msg             => "No-TDC DUT data-phase sample cadence"
    );

    stop_frame_1;
    wait_clocks(no_tdc_nom_bit_clk_c);

    Log("Test 5 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- DUT 2 TESTS (TDC enabled, prescaler = 2)
    --------------------------------------------------------------------------

    --------------------------------------------------------------------------
    -- Test 6: TDC measurement and SSP cadence in FD data phase
    --------------------------------------------------------------------------
    current_test_id <= 6;
    Log("Test 6: TDC measurement and SSP cadence (DUT 2)", INFO);

    reset_duts;
    loopback_enable_2 <= true;

    enter_fd_data_phase_2;
    send_bit_2((polarity => dominant, bit_name => data_bit), tdc_data_bit_clk_c * 5);

    wait_for_ssp_2(3 * tdc_nom_bit_clk_c, pulse_seen, "Data phase SSP pulse not observed");

    AlertIf(pcs_to_mac_2.fifo_index /= expected_fifo_index_c,
            "Unexpected FIFO index after TDC measurement. Expected " &
            integer'image(expected_fifo_index_c) & ", got " &
            integer'image(pcs_to_mac_2.fifo_index),
            ERROR);

    assert_ssp_period_2_n(
      expected_cycles => tdc_data_bit_clk_c,
      num_periods     => 3,
      search_window   => tdc_nom_bit_clk_c * 2,
      msg             => "SSP cadence in data field"
    );

    Log("Test 6 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- Test 7: Stuff bit keeps SSP monitoring
    --------------------------------------------------------------------------
    current_test_id <= 7;
    Log("Test 7: SSP monitoring on stuff bits (DUT 2)", INFO);

    send_bit_2((polarity => recessive, bit_name => stuff_bit), tdc_data_bit_clk_c * 4);

    wait_for_ssp_2(2 * tdc_data_bit_clk_c, pulse_seen, "Stuff-bit SSP pulse not observed");
    AlertIf(pcs_to_mac_2.fifo_index /= expected_fifo_index_c,
            "Stuff-bit monitoring should keep TDC FIFO index",
            ERROR);
    assert_ssp_period_2_n(
      expected_cycles => tdc_data_bit_clk_c,
      num_periods     => 2,
      search_window   => tdc_nom_bit_clk_c * 2,
      msg             => "SSP cadence on stuff bits"
    );

    Log("Test 7 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- Test 8: CRC field uses SSP monitoring
    --------------------------------------------------------------------------
    current_test_id <= 8;
    Log("Test 8: SSP monitoring for CRC field (DUT 2)", INFO);

    send_bit_2((polarity => dominant, bit_name => crc_bit), tdc_data_bit_clk_c * 4);

    wait_for_ssp_2(2 * tdc_data_bit_clk_c, pulse_seen, "CRC-field SSP pulse not observed");
    AlertIf(pcs_to_mac_2.fifo_index /= expected_fifo_index_c,
            "CRC field monitoring should use TDC FIFO index",
            ERROR);
    assert_ssp_period_2_n(
      expected_cycles => tdc_data_bit_clk_c,
      num_periods     => 2,
      search_window   => tdc_nom_bit_clk_c * 2,
      msg             => "SSP cadence in CRC field"
    );

    Log("Test 8 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- Test 9: Exit data phase on CRC delimiter
    --------------------------------------------------------------------------
    current_test_id <= 9;
    Log("Test 9: CRC delimiter exits data phase (DUT 2)", INFO);

    send_bit_2((polarity => recessive, bit_name => crc_delimiter_bit), tdc_data_bit_clk_c * 2);
    send_bit_2((polarity => recessive, bit_name => ack_delimiter_bit), tdc_nom_bit_clk_c * 2);

    AlertIf(pcs_to_mac_2.fifo_index /= 0,
            "After CRC delimiter, monitor must be nominal (FIFO index 0)",
            ERROR);
    assert_sp_period_2_n(
      expected_cycles => tdc_nom_bit_clk_c,
      num_periods     => 2,
      search_window   => tdc_nom_bit_clk_c * 2,
      msg             => "Nominal cadence after CRC delimiter"
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
    rx_bus_2_manual   <= recessive_bit_c;

    send_bit_2((polarity => dominant, bit_name => sof_bit));
    send_bit_2((polarity => recessive, bit_name => fdf_bit), tdc_nom_bit_clk_c * 2);
    send_bit_2((polarity => dominant, bit_name => res_bit), max_transmitter_delay_c + 40);
    send_bit_2((polarity => dominant, bit_name => data_bit), tdc_data_bit_clk_c * 4);

    AlertIf(pcs_to_mac_2.fifo_index /= 0,
            "Timeout path must not latch non-zero FIFO index",
            ERROR);
    assert_sp_period_2_n(
      expected_cycles => tdc_nom_bit_clk_c,
      num_periods     => 2,
      search_window   => tdc_nom_bit_clk_c * 2,
      msg             => "Nominal cadence after TDC timeout"
    );

    stop_frame_2;
    loopback_enable_2 <= true;
    rx_bus_2_manual   <= recessive_bit_c;
    wait_clocks(tdc_nom_bit_clk_c);

    Log("Test 10 PASSED", PASSED);

    --------------------------------------------------------------------------
    -- Test 11: Timing helper functions
    --------------------------------------------------------------------------
    current_test_id <= 11;
    Log("Test 11: Timing helper functions", INFO);

    AlertIf(calculate_fifo_delay_index(0, 49) /= 0,
            "Delay 0 should map to FIFO index 0", ERROR);
    AlertIf(calculate_fifo_delay_index(49, 49) /= 1,
            "Delay 49 should map to FIFO index 1", ERROR);
    AlertIf(calculate_fifo_delay_index(98, 49) /= 2,
            "Delay 98 should map to FIFO index 2", ERROR);
    AlertIf(calculate_fifo_delay_index(1600, 49) /= transmitted_bits_fifo_depth_c - 1,
            "Large delay should clamp to FIFO depth-1", ERROR);

    AlertIf(not should_use_tdc(
              system_clock_freq_c,
              tdc_prescaler_c,
              1, 4, 4, 4,
              pcs_to_pma_propagation_delay_ns => 400),
            "Fast FD timing should request TDC", ERROR);

    AlertIf(should_use_tdc(
              1_000_000,
              32, 1, 128, 128, 128,
              pcs_to_pma_propagation_delay_ns => 10),
            "Very slow timing with tiny propagation delay should not require TDC", ERROR);

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
