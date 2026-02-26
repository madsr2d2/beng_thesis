--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2025 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:   Testbench for can_node_clock.vhd
--
-- Revision log:  Date:       Initial:  JIRA:
--                2025-04-30  TMYAES:   [TRIT-3880] [FPGA] CAN-bus controller
--                2025-08-08  AFNI:     [TRIT-4042] [FPGA] Integrate can-bus controller into the io_ext
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pk_man_global.all;
use work.common_register_interface_pkg.all;
use work.common_tb_pkg.all;
use work.pk_can_bus_controller.all;

library osvvm;
context osvvm.OsvvmContext;

entity can_node_clock_tb is
  generic(
    gc_TbTimeOut      : time    := 5000 ms;                                     -- Timeout for simulation
    gc_TbClkPeriod    : time    := 10 ns;                                       -- 100 MHz clock
    gc_bit_rate_hz    : integer := 500_000;                                     -- CAN baud rate
    gc_bin_size       : integer := 100;                                         -- Size of test coverage bins
    gc_frames_to_send : integer := 5000                                         -- Number of frames to send
  );
end entity;

architecture tb of can_node_clock_tb is

  pure function f_time_str(
    constant c_time : time
  ) return string is
  begin
    return integer'image(c_time / 1 ns) & " ns";
  end function;

  function real_min(a, b : real) return real is
  begin
    if a < b then
      return a;
    else
      return b;
    end if;
  end function;

  function integer_min(a, b : integer) return integer is
  begin
    if a < b then
      return a;
    else
      return b;
    end if;
  end function;

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  constant c_tb_seg1         : integer := 6;
  constant c_tb_seg2         : integer := 5;
  constant c_tb_prop_seg     : integer := 8;
  constant c_sync_jump_width : integer := 3;

  -- ISO 11898-1:2024, Sec.: 7.3.2
  -- constant c_min_rx_sample_pulse_arrival_time : integer := c_baud_rate_prescaler * (c_sync_seg_length + c_tb_prop_seg + c_min_phase_seg1_length - c_sync_jump_width);
  -- constant c_max_rx_sample_pulse_arrival_time : integer := c_baud_rate_prescaler * (c_sync_seg_length + c_tb_prop_seg + c_max_phase_seg1_length + c_sync_jump_width);
  constant c_min_rx_sample_point : real := 0.4;                                 -- 40% of the bit period
  constant c_max_rx_sample_point : real := 0.92;                                -- 92% of the bit period

  constant c_min_mac_frame_length : integer := 50;
  constant c_max_mac_frame_length : integer := 111;

  constant c_nominal_bit_time : time := 1 sec / gc_bit_rate_hz;


  constant c_bit_length      : integer := c_tb_seg1 + c_tb_seg2 + c_tb_prop_seg + c_sync_seg_length;
  constant c_clock_delta_1   : real    := real(integer_min(c_tb_seg1, c_tb_seg2)) / real((2 * (13 * c_bit_length - c_tb_seg2)));
  constant c_clock_delta_2   : real    := real(c_sync_jump_width) / real((20 * c_bit_length));
  constant c_clock_delta     : real    := real_min(c_clock_delta_1, c_clock_delta_2); -- For the current values it gives 0.75%
  constant c_max_clock_delta : real    := 0.012;                                -- +-1.0 % delta Clock delta.

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal clk   : std_logic := '0';
  signal reset : std_logic := '1';

  signal bit_clk : std_logic;                                                   -- Used to sync the checker for the when a bit is sent out to the bus.

  signal rx        : std_logic;
  signal rx_sync   : std_logic;
  signal sample_rx : std_logic;
  signal transmit  : std_logic;


  signal frame_req : integer := 0;
  signal frame_ack : integer := 0;

  signal send_worst : boolean;

  -- Test IDs
  signal test_id  : AlertLogIDType;
  signal reset_id : AlertLogIDType;

  signal source_id : AlertLogIDType;

  shared variable RV         : RandomPType;
  shared variable v_bit_time : time := c_nominal_bit_time;
  

begin
  ----------------------------------------------------------------------------
  -- Initialization
  ----------------------------------------------------------------------------
  p_init : process
    variable v_test_id : AlertLogIDType;
  begin
    RV.InitSeed(random_seed);
    SetAlertStopCount(ERROR, 10);
    v_test_id := NewId("can_node_clock");

    test_id   <= v_test_id;
    reset_id  <= NewId("Reset Output Check", v_test_id);
    source_id <= NewId("Source", v_test_id);

    wait for 0 ns;
    -- SetLogEnable(source_id, INFO, true);
    wait for 0 ns;
    wait;
  end process;

  ----------------------------------------------------------------------------
  -- Clock generator
  ----------------------------------------------------------------------------
  clk <= not clk after gc_TbClkPeriod / 2;

  ----------------------------------------------------------------------------
  -- Simulation Time out monitor
  ----------------------------------------------------------------------------
  p_timeout : process
  begin
    WaitForClock(clk, gc_TbTimeOut);

    Message("################################################################################");
    Message("TIMEOUT detected - stopping simulation.");
    Message("################################################################################");

    AlertIf(test_id, True, "Timeout Detected");
    std.env.stop(1);
  end process;

  ----------------------------------------------------------------------------
  -- DUT
  ----------------------------------------------------------------------------
  u_dut : entity work.can_node_clock
    generic map(
      gc_bit_rate_hz                => gc_bit_rate_hz,
      gc_default_prop_seg_length    => c_tb_prop_seg,
      gc_default_phase_seg_1_length => c_tb_seg1,
      gc_default_phase_seg_2_length => c_tb_seg2,
      gc_sync_jump_width            => c_sync_jump_width
    )
    port map(
      clk_i       => clk,
      reset_i     => reset,
      rx_i        => rx_sync,
      sample_rx_o => sample_rx,
      transmit_o  => transmit
    );

  u_sync : entity work.synchronizer
    generic map(
      gc_width => 1,
      gc_depth => 2
    )
    port map(
      clk_i      => clk,
      async_i(0) => rx,
      sync_o(0)  => rx_sync
    );

  p_bit_source : process
    variable v_frame_length    : integer := 0;
    variable v_delta_frequency : real;
    variable v_last_bits       : std_logic_vector(4 downto 0);

    impure function rand_rx_bit return std_logic is
      variable v_return_val : std_logic;
    begin
      if (and(v_last_bits) = '1') or (nor(v_last_bits) = '1') then              -- Bit stuffing
        v_return_val := not v_last_bits(0);

      -- This string here is the worst that can happen for the synchronisation.
      -- It makes 1 sync, and then have 4 zeros more and then 1 stuff bit, and 4 ones and finally a new synchronization
      -- So if send worst, do not change the bits.
      elsif RV.DistBool((40, 60)) and (not send_worst) then                     -- A chance to change 
        v_return_val := not v_last_bits(0);
      else
        v_return_val := v_last_bits(0);                                         -- A chance to keep
      end if;
      v_last_bits := v_last_bits(3 downto 0) & v_return_val;
      return v_return_val;
    end function;

  begin
    bit_clk <= '0';
    rx      <= '1';
    wait for 0 ns;
    wait for 0 ns;
    loop
      if frame_ack >= frame_req then
        wait until frame_ack /= frame_req;
        WaitForClock(clk);
      end if;
      if send_worst then
        if RV.RandBool then
          v_delta_frequency := 1.0 + c_max_clock_delta;
        else
          v_delta_frequency := 1.0 - c_max_clock_delta;
        end if;
        v_frame_length := c_max_mac_frame_length;
      else
        v_delta_frequency := 1.0 + (RV.RandReal(-c_max_clock_delta, c_max_clock_delta));
        v_frame_length    := RV.RandInt(c_min_mac_frame_length, c_max_mac_frame_length);
      end if;
      v_bit_time := c_nominal_bit_time * v_delta_frequency;
      Log(source_id, "Sending frame with: length: " & integer'image(v_frame_length) & " bits, bit time is now: " & f_time_str(v_bit_time), INFO);

      -- TODO test that the sample is correct, if the rx does to 0, just 1 CC before the

      for i in 0 to v_frame_length - 2 loop
        if i = 0 then
          rx          <= '0';
          v_last_bits := B"11110";
        else
          rx <= rand_rx_bit;
        end if;
        bit_clk <= '1', '0' after v_bit_time / 2;
        wait for v_bit_time;
      end loop;
      rx <= '1';
      Increment(frame_ack);

      -- A minimum inter frame
      for i in 0 to RV.RandInt(0, 10) loop
        bit_clk <= '1', '0' after v_bit_time / 2;
        WaitForClock(clk, v_bit_time);
      end loop;

      bit_clk <= '1', '0' after v_bit_time / 2;
      wait for 0 ns;
    end loop;
  end process;

  ----------------------------------------------------------------------------
  -- Main test process
  ----------------------------------------------------------------------------
  p_main_tester : process
    variable v_start_time     : time;
    variable v_time_to_sample : time;

    variable v_min_rx_sample_pulse_arrival_time : time;
    variable v_max_rx_sample_pulse_arrival_time : time;
  begin
    wait for 0 ns;
    wait for 0 ns;
    WaitForClock(clk, 1);

    Message("################################################################################");
    Message("Output at Reset");
    Message("################################################################################");
    reset <= '1';
    WaitForClock(clk, 200);
    AffirmIf(reset_id, sample_rx = '0', "sample_rx_o: " & "'" & std_logic'image(sample_rx) & "'", "Expected: " & "'0'");
    AffirmIf(reset_id, transmit = '0', "transmit_o: " & "'" & std_logic'image(transmit) & "'", "Expected: " & "'0'");

    reset <= '0';
    WaitForClock(clk, 200);

    Message("################################################################################");
    Message("Normal usage");
    Message("################################################################################");
    Message("Sending random frames...");

    -- Send frames
    for i in 0 to gc_frames_to_send loop

      -- Set information processing time. Must be between 0 and phase_seg2_length (ISO 11898-1:2024, Sec.: 7.3.2)
      -- v_information_processing_time := c_baud_rate_prescaler * RV.RandInt(0, c_default_phase_seg2_length - 1);

      -- Reset DUT (Hard sync)
      WaitForClock(clk, 1);
      reset      <= '1', '0' after gc_TbClkPeriod + 1 ns;
      WaitForClock(clk, RV.RandTime(c_nominal_bit_time, c_nominal_bit_time * 10));
      send_worst <= false;
      if RV.DistBool((99, 1)) then
        send_worst <= true;
      end if;
      Increment(frame_req);
      wait for 0 ns;
      wait until rx_sync = '0';

      while frame_req /= frame_ack loop
        WaitForClock(bit_clk);

        -- Wait for sample_rx pulse
        v_start_time     := now;
        wait until sample_rx = '1';
        WaitForClock(clk);
        v_time_to_sample := now - v_start_time;

        v_min_rx_sample_pulse_arrival_time := ((c_min_rx_sample_point * v_bit_time) / gc_TbClkPeriod) * gc_TbClkPeriod;
        v_max_rx_sample_pulse_arrival_time := ((c_max_rx_sample_point * v_bit_time) / gc_TbClkPeriod) * gc_TbClkPeriod;
        -- Affirm that the sample pulse arrives within the limits
        if frame_req /= frame_ack then
          AffirmIf(test_id, v_time_to_sample >= v_min_rx_sample_pulse_arrival_time, "sample_rx_o pulse arrived too early: v_time_to_sample = " & f_time_str(v_time_to_sample), "Expected = " & f_time_str(v_min_rx_sample_pulse_arrival_time));
          AffirmIf(test_id, v_time_to_sample <= v_max_rx_sample_pulse_arrival_time, "sample_rx_o pulse arrived too late: v_time_to_sample = " & f_time_str(v_time_to_sample), "Expected = " & f_time_str(v_max_rx_sample_pulse_arrival_time));
        end if;
      end loop;


    end loop;

    wait for 100 us;
    Message("");
    Message("################################################################################");
    if GetAlertCount = 0 then
      Message("TEST PASSED!!");
    else
      Message("TEST FAILED :(");
    end if;
    Message("################################################################################");
    ReportAlerts;
    wait for 100 us;
    std.env.stop(1);

  end process;

end architecture;

-- eof
