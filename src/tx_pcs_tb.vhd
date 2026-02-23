--------------------------------------------------------------------------------
-- Title      : Testbench for CAN Physical Signaling Layer (PCS)
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : tx_pcs_tb.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Exhaustive PCS-focused verification:
--              1. Reset/idle defaults
--              2. Nominal sample-strobe cadence in idle and transmission
--              3. FD TDC measurement path (FDF->res)
--              4. SSP-based monitoring in data/stuff bits
--              5. SP-based monitoring outside data/stuff bits
--              6. Data phase exit on CRC delimiter
--              7. TDC timeout fallback path
--              8. Bus polarity indication mapping
--              9. Timing helper function coverage
--              10. TDC-disabled policy path (SP in data phase, fifo_index=0)
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  use osvvm.AlertLogPkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;
  use work.can_types_pkg.all;

entity tx_pcs_tb is
end entity tx_pcs_tb;

architecture test of tx_pcs_tb is

  ------------------------------------------------------------------------------
  -- Clock/reset
  ------------------------------------------------------------------------------
  constant clk_period_c : time := 10 ns; -- 100 MHz
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal test_done : boolean := false;
  -- Waveform marker for active test:
  -- 0=idle/reset, 1..12=test id, 13=done.
  signal current_test_id : integer range 0 to 13 := 0;
  constant test_idle_c : integer := 0;
  constant test_1_c    : integer := 1;
  constant test_2_c    : integer := 2;
  constant test_3_c    : integer := 3;
  constant test_4_c    : integer := 4;
  constant test_5_c    : integer := 5;
  constant test_6_c    : integer := 6;
  constant test_7_c    : integer := 7;
  constant test_8_c    : integer := 8;
  constant test_9_c    : integer := 9;
  constant test_10_c   : integer := 10;
  constant test_11_c   : integer := 11;
  constant test_12_c   : integer := 12;
  constant test_done_c : integer := 13;

  ------------------------------------------------------------------------------
  -- DUT configuration constants
  ------------------------------------------------------------------------------
  constant nom_prescaler_c  : prescalar    := 2;
  constant nom_sync_seg_c   : sync_seg     := 1;
  constant nom_prop_seg_c   : nom_prop_seg := 8;
  constant nom_phase_seg1_c : phase_seg1   := 8;
  constant nom_phase_seg2_c : phase_seg2   := 8;

  constant data_prescaler_c  : prescalar     := 1;
  constant data_sync_seg_c   : sync_seg      := 1;
  constant data_prop_seg_c   : data_prop_seg := 4;
  constant data_phase_seg1_c : phase_seg1    := 4;
  constant data_phase_seg2_c : phase_seg2    := 4;
  constant ssp_offset_c      : ssp_offset    := 5;

  constant nom_bit_time_tq_c   : integer := nom_sync_seg_c + nom_prop_seg_c + nom_phase_seg1_c + nom_phase_seg2_c;
  constant data_bit_time_tq_c  : integer := data_sync_seg_c + data_prop_seg_c + data_phase_seg1_c + data_phase_seg2_c;
  constant nom_bit_time_clk_c  : integer := nom_bit_time_tq_c * nom_prescaler_c;
  constant data_bit_time_clk_c : integer := data_bit_time_tq_c * data_prescaler_c;
  constant data_prescaler_ps2_c : prescalar := 2;
  constant data_bit_time_clk_ps2_c : integer := data_bit_time_tq_c * data_prescaler_ps2_c;

  ------------------------------------------------------------------------------
  -- Loopback setup (simulated TX->RX delay for TDC)
  ------------------------------------------------------------------------------
  constant loopback_delay_clocks_c : integer := 50;
  constant loopback_delay_c        : time    := loopback_delay_clocks_c * clk_period_c;
  constant expected_fifo_index_c   : integer := (loopback_delay_clocks_c + ssp_offset_c) / data_bit_time_tq_c;
  constant delay_with_offset_tq_ps2_c : integer :=
    (loopback_delay_clocks_c + (ssp_offset_c * data_prescaler_ps2_c) + 1 + data_prescaler_ps2_c - 1) / data_prescaler_ps2_c;
  constant expected_fifo_index_ps2_c : integer := delay_with_offset_tq_ps2_c / data_bit_time_tq_c;
  constant no_tdc_system_clock_freq_c : integer := 1_000_000;
  constant no_tdc_pma_delay_ns_c      : integer := 10;

  signal loopback_enable : boolean := true;
  signal rx_bus_manual   : std_logic := recessive_bit_c;
  signal rx_bus_loopback : std_logic := recessive_bit_c;
  signal rx_bus          : std_logic := recessive_bit_c;

  ------------------------------------------------------------------------------
  -- DUT I/O
  ------------------------------------------------------------------------------
  signal mac_to_pcs : mac_to_pcs_if_t := (
    data  => unknown_mac_frame_bit_c,
    valid => false
  );
  signal pcs_to_mac : pcs_to_mac_if_t;
  signal tx_bus     : std_logic;

  -- Secondary DUT instance: same timing but TDC policy forced disabled.
  signal mac_to_pcs_no_tdc : mac_to_pcs_if_t := (
    data  => unknown_mac_frame_bit_c,
    valid => false
  );
  signal pcs_to_mac_no_tdc : pcs_to_mac_if_t;
  signal tx_bus_no_tdc     : std_logic;
  signal rx_bus_no_tdc     : std_logic := recessive_bit_c;
  signal mac_to_pcs_ps2 : mac_to_pcs_if_t := (
    data  => unknown_mac_frame_bit_c,
    valid => false
  );
  signal pcs_to_mac_ps2 : pcs_to_mac_if_t;
  signal tx_bus_ps2     : std_logic;
  signal rx_bus_ps2     : std_logic := recessive_bit_c;

begin

  ------------------------------------------------------------------------------
  -- Clock generation
  ------------------------------------------------------------------------------
  clk <= not clk after clk_period_c / 2 when not test_done else '0';

  ------------------------------------------------------------------------------
  -- RX source mux: either delayed loopback or manual drive
  ------------------------------------------------------------------------------
  rx_bus <= rx_bus_loopback when loopback_enable else rx_bus_manual;

  loopback_proc : process is
  begin
    wait on tx_bus;
    rx_bus_loopback <= transport tx_bus after loopback_delay_c;
  end process loopback_proc;

  loopback_no_tdc_proc : process is
  begin
    wait on tx_bus_no_tdc;
    rx_bus_no_tdc <= transport tx_bus_no_tdc after loopback_delay_c;
  end process loopback_no_tdc_proc;

  loopback_ps2_proc : process is
  begin
    wait on tx_bus_ps2;
    rx_bus_ps2 <= transport tx_bus_ps2 after loopback_delay_c;
  end process loopback_ps2_proc;

  ------------------------------------------------------------------------------
  -- DUT
  ------------------------------------------------------------------------------
  dut : entity work.tx_pcs
    generic map (
      nom_prescaler   => nom_prescaler_c,
      nom_sync_seg    => nom_sync_seg_c,
      nom_prop_seg    => nom_prop_seg_c,
      nom_phase_seg1  => nom_phase_seg1_c,
      nom_phase_seg2  => nom_phase_seg2_c,
      data_prescaler  => data_prescaler_c,
      data_sync_seg   => data_sync_seg_c,
      data_prop_seg   => data_prop_seg_c,
      data_phase_seg1 => data_phase_seg1_c,
      data_phase_seg2 => data_phase_seg2_c,
      ssp_offset      => ssp_offset_c
    )
    port map (
      clk          => clk,
      rst          => rst,
      mac_to_pcs_i => mac_to_pcs,
      pcs_to_mac_o => pcs_to_mac,
      tx_bus_o     => tx_bus,
      rx_bus_i     => rx_bus
    );

  dut_no_tdc : entity work.tx_pcs
    generic map (
      nom_prescaler   => nom_prescaler_c,
      nom_sync_seg    => nom_sync_seg_c,
      nom_prop_seg    => nom_prop_seg_c,
      nom_phase_seg1  => nom_phase_seg1_c,
      nom_phase_seg2  => nom_phase_seg2_c,
      data_prescaler  => data_prescaler_c,
      data_sync_seg   => data_sync_seg_c,
      data_prop_seg   => data_prop_seg_c,
      data_phase_seg1 => data_phase_seg1_c,
      data_phase_seg2 => data_phase_seg2_c,
      ssp_offset      => ssp_offset_c,
      system_clock_freq_hz            => no_tdc_system_clock_freq_c,
      pcs_to_pma_propagation_delay_ns => no_tdc_pma_delay_ns_c
    )
    port map (
      clk          => clk,
      rst          => rst,
      mac_to_pcs_i => mac_to_pcs_no_tdc,
      pcs_to_mac_o => pcs_to_mac_no_tdc,
      tx_bus_o     => tx_bus_no_tdc,
      rx_bus_i     => rx_bus_no_tdc
    );

  dut_ps2 : entity work.tx_pcs
    generic map (
      nom_prescaler   => nom_prescaler_c,
      nom_sync_seg    => nom_sync_seg_c,
      nom_prop_seg    => nom_prop_seg_c,
      nom_phase_seg1  => nom_phase_seg1_c,
      nom_phase_seg2  => nom_phase_seg2_c,
      data_prescaler  => data_prescaler_ps2_c,
      data_sync_seg   => data_sync_seg_c,
      data_prop_seg   => data_prop_seg_c,
      data_phase_seg1 => data_phase_seg1_c,
      data_phase_seg2 => data_phase_seg2_c,
      ssp_offset      => ssp_offset_c
    )
    port map (
      clk          => clk,
      rst          => rst,
      mac_to_pcs_i => mac_to_pcs_ps2,
      pcs_to_mac_o => pcs_to_mac_ps2,
      tx_bus_o     => tx_bus_ps2,
      rx_bus_i     => rx_bus_ps2
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

    procedure reset_dut is
    begin
      rst <= '1';
      mac_to_pcs.valid <= false;
      mac_to_pcs.data <= unknown_mac_frame_bit_c;
      mac_to_pcs_no_tdc.valid <= false;
      mac_to_pcs_no_tdc.data <= unknown_mac_frame_bit_c;
      mac_to_pcs_ps2.valid <= false;
      mac_to_pcs_ps2.data <= unknown_mac_frame_bit_c;
      wait_clocks(5);
      rst <= '0';
      wait_clocks(2);
    end procedure reset_dut;

    procedure send_bit (
      bit_to_send : mac_frame_bit_t;
      hold_clocks : positive := nom_bit_time_clk_c
    ) is
    begin
      mac_to_pcs.data <= bit_to_send;
      mac_to_pcs.valid <= true;
      wait_clocks(hold_clocks);
    end procedure send_bit;

    procedure stop_frame is
    begin
      mac_to_pcs.valid <= false;
      mac_to_pcs.data <= unknown_mac_frame_bit_c;
    end procedure stop_frame;

    procedure send_bit_no_tdc (
      bit_to_send : mac_frame_bit_t;
      hold_clocks : positive := nom_bit_time_clk_c
    ) is
    begin
      mac_to_pcs_no_tdc.data <= bit_to_send;
      mac_to_pcs_no_tdc.valid <= true;
      wait_clocks(hold_clocks);
    end procedure send_bit_no_tdc;

    procedure stop_frame_no_tdc is
    begin
      mac_to_pcs_no_tdc.valid <= false;
      mac_to_pcs_no_tdc.data <= unknown_mac_frame_bit_c;
    end procedure stop_frame_no_tdc;

    procedure send_bit_ps2 (
      bit_to_send : mac_frame_bit_t;
      hold_clocks : positive := nom_bit_time_clk_c
    ) is
    begin
      mac_to_pcs_ps2.data <= bit_to_send;
      mac_to_pcs_ps2.valid <= true;
      wait_clocks(hold_clocks);
    end procedure send_bit_ps2;

    procedure stop_frame_ps2 is
    begin
      mac_to_pcs_ps2.valid <= false;
      mac_to_pcs_ps2.data <= unknown_mac_frame_bit_c;
    end procedure stop_frame_ps2;

    procedure wait_for_sample_pulse_no_tdc (
      max_cycles    : positive;
      variable seen : out boolean;
      constant msg  : string
    ) is
    begin
      seen := false;
      for i in 1 to max_cycles loop
        wait until rising_edge(clk);
        if (pcs_to_mac_no_tdc.sample_strobe = '1') then
          seen := true;
          exit;
        end if;
      end loop;
      AlertIf(not seen, msg, ERROR);
    end procedure wait_for_sample_pulse_no_tdc;

    procedure wait_for_sample_pulse_ps2 (
      max_cycles    : positive;
      variable seen : out boolean;
      constant msg  : string
    ) is
    begin
      seen := false;
      for i in 1 to max_cycles loop
        wait until rising_edge(clk);
        if (pcs_to_mac_ps2.sample_strobe = '1') then
          seen := true;
          exit;
        end if;
      end loop;
      AlertIf(not seen, msg, ERROR);
    end procedure wait_for_sample_pulse_ps2;

    procedure assert_next_sample_period_no_tdc (
      expected_cycles : positive;
      search_window   : positive;
      constant msg    : string
    ) is
      variable first_seen  : boolean;
      variable second_seen : boolean;
      variable period      : integer := 0;
    begin
      wait_for_sample_pulse_no_tdc(search_window, first_seen, msg & " (first pulse missing)");

      second_seen := false;
      period := 0;
      for i in 1 to search_window loop
        wait until rising_edge(clk);
        period := period + 1;
        if (pcs_to_mac_no_tdc.sample_strobe = '1') then
          second_seen := true;
          exit;
        end if;
      end loop;

      AlertIf(not second_seen, msg & " (second pulse missing)", ERROR);
      AlertIf(period /= expected_cycles,
              msg & " (expected " & integer'image(expected_cycles) &
              " cycles, got " & integer'image(period) & ")",
              ERROR);
    end procedure assert_next_sample_period_no_tdc;

    procedure assert_next_sample_period_ps2 (
      expected_cycles : positive;
      search_window   : positive;
      constant msg    : string
    ) is
      variable first_seen  : boolean;
      variable second_seen : boolean;
      variable period      : integer := 0;
    begin
      wait_for_sample_pulse_ps2(search_window, first_seen, msg & " (first pulse missing)");

      second_seen := false;
      period := 0;
      for i in 1 to search_window loop
        wait until rising_edge(clk);
        period := period + 1;
        if (pcs_to_mac_ps2.sample_strobe = '1') then
          second_seen := true;
          exit;
        end if;
      end loop;

      AlertIf(not second_seen, msg & " (second pulse missing)", ERROR);
      AlertIf(period /= expected_cycles,
              msg & " (expected " & integer'image(expected_cycles) &
              " cycles, got " & integer'image(period) & ")",
              ERROR);
    end procedure assert_next_sample_period_ps2;

    procedure wait_for_sample_pulse (
      max_cycles    : positive;
      variable seen : out boolean;
      constant msg  : string
    ) is
    begin
      seen := false;
      for i in 1 to max_cycles loop
        wait until rising_edge(clk);
        if (pcs_to_mac.sample_strobe = '1') then
          seen := true;
          exit;
        end if;
      end loop;
      AlertIf(not seen, msg, ERROR);
    end procedure wait_for_sample_pulse;

    procedure wait_for_ssp_sample_pulse (
      max_cycles    : positive;
      variable seen : out boolean;
      constant msg  : string
    ) is
    begin
      seen := false;
      for i in 1 to max_cycles loop
        wait until rising_edge(clk);
        if (pcs_to_mac.sample_strobe = '1' and pcs_to_mac.strobe_type = ssp_strobe) then
          seen := true;
          exit;
        end if;
      end loop;
      AlertIf(not seen, msg, ERROR);
    end procedure wait_for_ssp_sample_pulse;

    procedure wait_for_ssp_sample_pulse_ps2 (
      max_cycles    : positive;
      variable seen : out boolean;
      constant msg  : string
    ) is
    begin
      seen := false;
      for i in 1 to max_cycles loop
        wait until rising_edge(clk);
        if (pcs_to_mac_ps2.sample_strobe = '1' and pcs_to_mac_ps2.strobe_type = ssp_strobe) then
          seen := true;
          exit;
        end if;
      end loop;
      AlertIf(not seen, msg, ERROR);
    end procedure wait_for_ssp_sample_pulse_ps2;

    procedure assert_no_sample_pulse (
      max_cycles : positive;
      constant msg : string
    ) is
      variable seen : boolean;
    begin
      seen := false;
      for i in 1 to max_cycles loop
        wait until rising_edge(clk);
        if (pcs_to_mac.sample_strobe = '1') then
          seen := true;
          exit;
        end if;
      end loop;
      AlertIf(seen, msg, ERROR);
    end procedure assert_no_sample_pulse;

    procedure wait_for_tx_level (
      expected_level : std_logic;
      max_cycles     : positive;
      constant msg   : string
    ) is
      variable seen : boolean := false;
    begin
      for i in 1 to max_cycles loop
        wait until rising_edge(clk);
        if (tx_bus = expected_level) then
          seen := true;
          exit;
        end if;
      end loop;
      AlertIf(not seen, msg, ERROR);
    end procedure wait_for_tx_level;

    procedure assert_next_sample_period (
      expected_cycles : positive;
      search_window   : positive;
      constant msg    : string
    ) is
      variable first_seen  : boolean;
      variable second_seen : boolean;
      variable period      : integer := 0;
    begin
      wait_for_sample_pulse(search_window, first_seen, msg & " (first pulse missing)");

      second_seen := false;
      period := 0;
      for i in 1 to search_window loop
        wait until rising_edge(clk);
        period := period + 1;
        if (pcs_to_mac.sample_strobe = '1') then
          second_seen := true;
          exit;
        end if;
      end loop;

      AlertIf(not second_seen, msg & " (second pulse missing)", ERROR);
      AlertIf(period /= expected_cycles,
              msg & " (expected " & integer'image(expected_cycles) &
              " cycles, got " & integer'image(period) & ")",
              ERROR);

      wait until rising_edge(clk);
      AlertIf(pcs_to_mac.sample_strobe /= '0', msg & " (strobe must be one cycle wide)", ERROR);
    end procedure assert_next_sample_period;

    procedure assert_sample_period_n_times (
      expected_cycles : positive;
      num_periods     : positive;
      search_window   : positive;
      constant msg    : string
    ) is
    begin
      for k in 1 to num_periods loop
        assert_next_sample_period(expected_cycles, search_window, msg & " #" & integer'image(k));
      end loop;
    end procedure assert_sample_period_n_times;

    procedure assert_next_ssp_sample_period (
      expected_cycles : positive;
      search_window   : positive;
      constant msg    : string
    ) is
      variable first_seen  : boolean;
      variable second_seen : boolean;
      variable period      : integer := 0;
    begin
      wait_for_ssp_sample_pulse(search_window, first_seen, msg & " (first SSP pulse missing)");

      second_seen := false;
      period := 0;
      for i in 1 to search_window loop
        wait until rising_edge(clk);
        period := period + 1;
        if (pcs_to_mac.sample_strobe = '1' and pcs_to_mac.strobe_type = ssp_strobe) then
          second_seen := true;
          exit;
        end if;
      end loop;

      AlertIf(not second_seen, msg & " (second SSP pulse missing)", ERROR);
      AlertIf(period /= expected_cycles,
              msg & " (expected " & integer'image(expected_cycles) &
              " cycles, got " & integer'image(period) & ")",
              ERROR);
    end procedure assert_next_ssp_sample_period;

    procedure assert_ssp_sample_period_n_times (
      expected_cycles : positive;
      num_periods     : positive;
      search_window   : positive;
      constant msg    : string
    ) is
    begin
      for k in 1 to num_periods loop
        assert_next_ssp_sample_period(expected_cycles, search_window, msg & " #" & integer'image(k));
      end loop;
    end procedure assert_ssp_sample_period_n_times;

    procedure assert_next_ssp_sample_period_ps2 (
      expected_cycles : positive;
      search_window   : positive;
      constant msg    : string
    ) is
      variable first_seen  : boolean;
      variable second_seen : boolean;
      variable period      : integer := 0;
    begin
      wait_for_ssp_sample_pulse_ps2(search_window, first_seen, msg & " (first SSP pulse missing)");

      second_seen := false;
      period := 0;
      for i in 1 to search_window loop
        wait until rising_edge(clk);
        period := period + 1;
        if (pcs_to_mac_ps2.sample_strobe = '1' and pcs_to_mac_ps2.strobe_type = ssp_strobe) then
          second_seen := true;
          exit;
        end if;
      end loop;

      AlertIf(not second_seen, msg & " (second SSP pulse missing)", ERROR);
      AlertIf(period /= expected_cycles,
              msg & " (expected " & integer'image(expected_cycles) &
              " cycles, got " & integer'image(period) & ")",
              ERROR);
    end procedure assert_next_ssp_sample_period_ps2;

    function is_data_monitor_bit (
      bit_name : mac_frame_bit_name_t
    ) return boolean is
    begin
      return (bit_name = data_bit or bit_name = stuff_bit);
    end function is_data_monitor_bit;

    variable pulse_seen : boolean;

  begin
    SetLogEnable(INFO, true);
    SetLogEnable(PASSED, true);
    current_test_id <= test_idle_c;

    ----------------------------------------------------------------------------
    -- Test 1: Reset and idle defaults
    ----------------------------------------------------------------------------
    current_test_id <= test_1_c;
    Log("Test 1: Reset and idle defaults", INFO);
    reset_dut;

    AlertIf(tx_bus /= recessive_bit_c, "TX bus should be recessive after reset", ERROR);
    AlertIf(pcs_to_mac.bus_polarity /= recessive, "Bus polarity should decode recessive", ERROR);
    AlertIf(pcs_to_mac.fifo_index /= 0, "FIFO index should be 0 after reset", ERROR);

    Log("Test 1 PASSED", PASSED);

    ----------------------------------------------------------------------------
    -- Test 2: Idle sample-strobe cadence (nominal timing)
    ----------------------------------------------------------------------------
    current_test_id <= test_2_c;
    Log("Test 2: Idle sample-strobe cadence", INFO);

    assert_sample_period_n_times(
      expected_cycles => nom_bit_time_clk_c,
      num_periods     => 3,
      search_window   => nom_bit_time_clk_c * 2,
      msg             => "Idle nominal sample cadence"
    );
    AlertIf(pcs_to_mac.fifo_index /= 0, "FIFO index must remain 0 in idle", ERROR);

    Log("Test 2 PASSED", PASSED);

    ----------------------------------------------------------------------------
    -- Test 3: Nominal transmission cadence and TX mapping
    ----------------------------------------------------------------------------
    current_test_id <= test_3_c;
    Log("Test 3: Nominal transmission cadence and TX mapping", INFO);

    send_bit((polarity => dominant, bit_name => sof_bit));
    wait_for_tx_level(dominant_bit_c, nom_bit_time_clk_c, "SOF must drive dominant TX bus");

    send_bit((polarity => recessive, bit_name => base_id_bit));
    wait_for_tx_level(recessive_bit_c, nom_bit_time_clk_c, "Recessive bit must drive recessive TX bus");

    assert_sample_period_n_times(
      expected_cycles => nom_bit_time_clk_c,
      num_periods     => 2,
      search_window   => nom_bit_time_clk_c * 2,
      msg             => "Nominal phase sample cadence"
    );
    AlertIf(pcs_to_mac.fifo_index /= 0, "Nominal phase must use FIFO index 0", ERROR);

    Log("Test 3 PASSED", PASSED);

    ----------------------------------------------------------------------------
    -- Test 4: TDC measurement and SSP cadence in FD data phase
    ----------------------------------------------------------------------------
    current_test_id <= test_4_c;
    Log("Test 4: TDC measurement and SSP cadence", INFO);

    reset_dut;
    loopback_enable <= true;
    rx_bus_manual <= recessive_bit_c;

    -- Enter FD sequence that triggers delay measurement at res_bit.
    send_bit((polarity => dominant, bit_name => sof_bit));
    send_bit((polarity => recessive, bit_name => fdf_bit), nom_bit_time_clk_c * 2);

    -- Keep res bit active long enough for delayed RX edge to arrive.
    send_bit((polarity => dominant, bit_name => res_bit), nom_bit_time_clk_c * 3);

    -- Transition bit (required by updated PCS state machine)
    send_bit((polarity => recessive, bit_name => brs_bit), nom_bit_time_clk_c * 2);

    -- Move into data field; monitor should switch to SSP once state is transmitting_data.
    send_bit((polarity => dominant, bit_name => data_bit), data_bit_time_clk_c * 5);

    wait_for_ssp_sample_pulse(3 * nom_bit_time_clk_c, pulse_seen, "Data phase SSP pulse not observed");
    AlertIf(not is_data_monitor_bit(mac_to_pcs.data.bit_name),
            "Test setup error: expected data/stuff monitor bit",
            FAILURE);

    -- Expected measured delay: 50 clocks + offset 5 -> fifo index 4.
    AlertIf(pcs_to_mac.fifo_index /= expected_fifo_index_c,
            "Unexpected FIFO index after TDC measurement. Expected " &
            integer'image(expected_fifo_index_c) & ", got " &
            integer'image(pcs_to_mac.fifo_index),
            ERROR);

    assert_ssp_sample_period_n_times(
      expected_cycles => data_bit_time_clk_c,
      num_periods     => 3,
      search_window   => nom_bit_time_clk_c * 2,
      msg             => "SSP cadence in data field"
    );

    Log("Test 4 PASSED", PASSED);

    ----------------------------------------------------------------------------
    -- Test 5: Stuff bit keeps SSP monitoring
    ----------------------------------------------------------------------------
    current_test_id <= test_5_c;
    Log("Test 5: SSP monitoring on stuff bits", INFO);

    send_bit((polarity => recessive, bit_name => stuff_bit), data_bit_time_clk_c * 4);

    wait_for_ssp_sample_pulse(2 * data_bit_time_clk_c, pulse_seen, "Stuff-bit SSP pulse not observed");
    AlertIf(pcs_to_mac.fifo_index /= expected_fifo_index_c,
            "Stuff-bit monitoring should keep TDC FIFO index",
            ERROR);
    assert_ssp_sample_period_n_times(
      expected_cycles => data_bit_time_clk_c,
      num_periods     => 2,
      search_window   => nom_bit_time_clk_c * 2,
      msg             => "SSP cadence on stuff bits"
    );

    Log("Test 5 PASSED", PASSED);

    ----------------------------------------------------------------------------
    -- Test 6: Data phase bits (including CRC) use SSP monitoring
    ----------------------------------------------------------------------------
    current_test_id <= test_6_c;
    Log("Test 6: SSP monitoring for CRC field", INFO);

    send_bit((polarity => dominant, bit_name => crc_bit), data_bit_time_clk_c * 4);

    wait_for_ssp_sample_pulse(2 * data_bit_time_clk_c, pulse_seen, "CRC-field SSP pulse not observed");
    AlertIf(pcs_to_mac.fifo_index /= expected_fifo_index_c,
            "CRC field monitoring should use TDC FIFO index",
            ERROR);

    assert_ssp_sample_period_n_times(
      expected_cycles => data_bit_time_clk_c,
      num_periods     => 2,
      search_window   => nom_bit_time_clk_c * 2,
      msg             => "SSP cadence in CRC field"
    );

    Log("Test 6 PASSED", PASSED);

    ----------------------------------------------------------------------------
    -- Test 7: Exit data phase on CRC delimiter
    ----------------------------------------------------------------------------
    current_test_id <= test_7_c;
    Log("Test 7: CRC delimiter exits data phase", INFO);

    send_bit((polarity => recessive, bit_name => crc_delimiter_bit), data_bit_time_clk_c * 2);
    send_bit((polarity => recessive, bit_name => ack_delimiter_bit), nom_bit_time_clk_c * 2);

    AlertIf(pcs_to_mac.fifo_index /= 0, "After CRC delimiter, monitor must be nominal (FIFO index 0)", ERROR);
    assert_sample_period_n_times(
      expected_cycles => nom_bit_time_clk_c,
      num_periods     => 2,
      search_window   => nom_bit_time_clk_c * 2,
      msg             => "Nominal cadence after CRC delimiter"
    );

    stop_frame;
    wait_clocks(nom_bit_time_clk_c);

    Log("Test 7 PASSED", PASSED);

    ----------------------------------------------------------------------------
    -- Test 8: TDC timeout fallback when RX edge never arrives
    ----------------------------------------------------------------------------
    current_test_id <= test_8_c;
    Log("Test 8: TDC timeout fallback", INFO);

    reset_dut;
    loopback_enable <= false;
    rx_bus_manual <= recessive_bit_c;

    send_bit((polarity => dominant, bit_name => sof_bit));
    send_bit((polarity => recessive, bit_name => fdf_bit), nom_bit_time_clk_c * 2);
    send_bit((polarity => dominant, bit_name => res_bit), max_transmitter_delay_c + 40);
    send_bit((polarity => dominant, bit_name => data_bit), data_bit_time_clk_c * 4);

    AlertIf(pcs_to_mac.fifo_index /= 0, "Timeout path must not latch non-zero FIFO index", ERROR);
    assert_sample_period_n_times(
      expected_cycles => nom_bit_time_clk_c,
      num_periods     => 2,
      search_window   => nom_bit_time_clk_c * 2,
      msg             => "Nominal cadence after TDC timeout"
    );

    stop_frame;
    loopback_enable <= true;
    rx_bus_manual <= recessive_bit_c;
    wait_clocks(nom_bit_time_clk_c);

    Log("Test 8 PASSED", PASSED);

    ----------------------------------------------------------------------------
    -- Test 9: Bus polarity indication mapping
    ----------------------------------------------------------------------------
    current_test_id <= test_9_c;
    Log("Test 9: bus_polarity indication mapping", INFO);

    loopback_enable <= false;
    rx_bus_manual <= dominant_bit_c;
    wait_clocks(2);
    AlertIf(pcs_to_mac.bus_polarity /= dominant, "bus_polarity should decode dominant RX", ERROR);

    rx_bus_manual <= recessive_bit_c;
    wait_clocks(2);
    AlertIf(pcs_to_mac.bus_polarity /= recessive, "bus_polarity should decode recessive RX", ERROR);

    loopback_enable <= true;
    Log("Test 9 PASSED", PASSED);

    ----------------------------------------------------------------------------
    -- Test 10: Timing helper functions
    ----------------------------------------------------------------------------
    current_test_id <= test_10_c;
    Log("Test 10: Timing helper functions", INFO);

    AlertIf(calculate_fifo_delay_index(0, 49) /= 0, "Delay 0 should map to FIFO index 0", ERROR);
    AlertIf(calculate_fifo_delay_index(49, 49) /= 1, "Delay 49 should map to FIFO index 1", ERROR);
    AlertIf(calculate_fifo_delay_index(98, 49) /= 2, "Delay 98 should map to FIFO index 2", ERROR);
    AlertIf(calculate_fifo_delay_index(1600, 49) /= transmitted_bits_fifo_depth_c - 1,
            "Large delay should clamp to FIFO depth-1",
            ERROR);

    AlertIf(not should_use_tdc(
              system_clock_freq_c,
              data_prescaler_c,
              data_sync_seg_c,
              data_prop_seg_c,
              data_phase_seg1_c,
              data_phase_seg2_c,
              pcs_to_pma_propagation_delay_ns => 400),
            "Fast FD timing should request TDC",
            ERROR);

    AlertIf(should_use_tdc(
              1_000_000,  -- very slow clock
              32,
              1,
              128,
              128,
              128,
              pcs_to_pma_propagation_delay_ns => 10),
            "Very slow timing with tiny propagation delay should not require TDC",
            ERROR);

    Log("Test 10 PASSED", PASSED);

    ----------------------------------------------------------------------------
    -- Test 11: TDC disabled policy path uses SP in data phase
    ----------------------------------------------------------------------------
    current_test_id <= test_11_c;
    Log("Test 11: TDC-disabled path uses SP and FIFO index 0", INFO);

    reset_dut;
    send_bit_no_tdc((polarity => dominant, bit_name => sof_bit));
    send_bit_no_tdc((polarity => recessive, bit_name => fdf_bit), nom_bit_time_clk_c * 2);
    -- With TDC disabled, res bit transitions to brs_bit at nominal rate.
    send_bit_no_tdc((polarity => dominant, bit_name => res_bit), nom_bit_time_clk_c);
    send_bit_no_tdc((polarity => recessive, bit_name => brs_bit), nom_bit_time_clk_c);
    send_bit_no_tdc((polarity => dominant, bit_name => data_bit), data_bit_time_clk_c * 5);

    wait_for_sample_pulse_no_tdc(
      max_cycles => data_bit_time_clk_c * 2,
      seen       => pulse_seen,
      msg        => "No-TDC DUT did not generate data-phase sample pulse"
    );
    AlertIf(pcs_to_mac_no_tdc.fifo_index /= 0,
            "No-TDC DUT must keep FIFO index at 0 in data phase",
            ERROR);
    assert_next_sample_period_no_tdc(
      expected_cycles => data_bit_time_clk_c,
      search_window   => nom_bit_time_clk_c * 2,
      msg             => "No-TDC DUT data-phase sample cadence"
    );

    stop_frame_no_tdc;
    wait_clocks(nom_bit_time_clk_c);

    Log("Test 11 PASSED", PASSED);

    ----------------------------------------------------------------------------
    -- Test 12: TDC measurement with data_prescaler = 2
    ----------------------------------------------------------------------------
    current_test_id <= test_12_c;
    Log("Test 12: TDC measurement with data_prescaler=2", INFO);

    reset_dut;
    send_bit_ps2((polarity => dominant, bit_name => sof_bit));
    send_bit_ps2((polarity => recessive, bit_name => fdf_bit), nom_bit_time_clk_c * 2);
    send_bit_ps2((polarity => dominant, bit_name => res_bit), nom_bit_time_clk_c * 3);
    send_bit_ps2((polarity => recessive, bit_name => brs_bit), nom_bit_time_clk_c * 2);
    send_bit_ps2((polarity => dominant, bit_name => data_bit), data_bit_time_clk_ps2_c * 5);

    wait_for_ssp_sample_pulse_ps2(
      max_cycles => 3 * nom_bit_time_clk_c,
      seen       => pulse_seen,
      msg        => "Prescaler=2 DUT did not generate data-phase SSP pulse"
    );
    AlertIf(pcs_to_mac_ps2.fifo_index /= expected_fifo_index_ps2_c,
            "Unexpected FIFO index for prescaler=2. Expected " &
            integer'image(expected_fifo_index_ps2_c) & ", got " &
            integer'image(pcs_to_mac_ps2.fifo_index),
            ERROR);
    assert_next_ssp_sample_period_ps2(
      expected_cycles => data_bit_time_clk_ps2_c,
      search_window   => nom_bit_time_clk_c * 3,
      msg             => "Prescaler=2 DUT data-phase SSP cadence"
    );

    stop_frame_ps2;
    wait_clocks(nom_bit_time_clk_c);

    Log("Test 12 PASSED", PASSED);

    ----------------------------------------------------------------------------
    -- Summary
    ----------------------------------------------------------------------------
    Log("================================================================================", INFO);
    Log("All tx_pcs unit tests completed", INFO);
    Log("================================================================================", INFO);

    ReportAlerts;
    current_test_id <= test_done_c;
    test_done <= true;
    wait;

  end process test_runner;

end architecture test;
