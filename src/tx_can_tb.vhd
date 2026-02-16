--------------------------------------------------------------------------------
-- Title      : CAN Transmitter Integration Testbench
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : tx_can_tb.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Integration testbench for tx_can top-level entity.
--              Tests full transmit path: LLC user request -> bus output.
--
-- Test scenarios:
--   1. Successful CC Basic transmission (happy path)
--   2. Abort before MAC acceptance (send_config_0 state)
--   3. Abort ignored after MAC acceptance
--   4. Retransmission limit exceeded (7 attempts, no ACK)
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

library osvvm;
  use osvvm.AlertLogPkg.all;

entity tx_can_tb is
end entity tx_can_tb;

architecture tb of tx_can_tb is

  -- Clock and reset
  constant clk_period_c : time := 10 ns; -- 100 MHz
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- Bit timing generics (matching tx_can defaults)
  constant nom_prescaler_c  : integer := 2;
  constant nom_sync_seg_c   : integer := 1;
  constant nom_prop_seg_c   : integer := 8;
  constant nom_phase_seg1_c : integer := 8;
  constant nom_phase_seg2_c : integer := 8;
  constant nom_bit_time_tq_c : integer := nom_sync_seg_c + nom_prop_seg_c + nom_phase_seg1_c + nom_phase_seg2_c;
  constant nom_bit_time_clk_c : integer := nom_bit_time_tq_c * nom_prescaler_c; -- 50 clocks
  constant nom_sp_tq_c : integer := nom_sync_seg_c + nom_prop_seg_c + nom_phase_seg1_c; -- 17 TQ
  constant nom_sp_clk_c : integer := nom_sp_tq_c * nom_prescaler_c; -- 34 clocks

  -- DUT signals
  signal llc_user_i : llc_user_to_llc_if_t;
  signal llc_user_o : llc_to_llc_user_if_t;
  signal fce_i      : fce_to_mac_if_t;
  signal fce_o      : mac_to_fce_if_t;
  signal tx_bus_o   : std_logic;
  signal rx_bus_i   : std_logic;

  -- Bus model control
  signal inject_ack   : boolean := true;
  signal bus_override  : std_logic := recessive_bit_c;
  signal bus_override_en : boolean := false;

  -- Test tracking
  signal test_done : boolean := false;

begin

  -- Clock generation
  clk <= not clk after clk_period_c / 2 when not test_done;

  -- DUT instantiation
  dut : entity work.tx_can
    generic map (
      nom_prescaler        => nom_prescaler_c,
      nom_sync_seg         => nom_sync_seg_c,
      nom_prop_seg         => nom_prop_seg_c,
      nom_phase_seg1       => nom_phase_seg1_c,
      nom_phase_seg2       => nom_phase_seg2_c,
      data_prescaler       => 1,
      data_sync_seg        => 1,
      data_prop_seg        => 4,
      data_phase_seg1      => 4,
      data_phase_seg2      => 4,
      ssp_offset           => 4
    )
    port map (
      clk        => clk,
      rst        => rst,
      llc_user_i => llc_user_i,
      llc_user_o => llc_user_o,
      fce_i      => fce_i,
      fce_o      => fce_o,
      tx_bus_o   => tx_bus_o,
      rx_bus_i   => rx_bus_i
    );

  -- Bus model: loopback with optional ACK injection and override
  -- rx_bus_i follows tx_bus_o (loopback) unless overridden
  rx_bus_i <= bus_override when bus_override_en else tx_bus_o;

  -- FCE: error-active node (not error-passive)
  fce_i.error_passive <= false;

  -- =========================================================================
  -- Bus Monitor Process: Tracks frame position and injects ACK
  -- =========================================================================
  bus_monitor : process is

    -- Stuff bit tracking
    variable consecutive_count_v : integer := 0;
    variable last_polarity_v     : std_logic := recessive_bit_c;
    variable frame_position_v    : integer := 0;
    variable is_stuff_bit_v      : boolean := false;

    -- Frame parameters for ACK position calculation
    variable params_v : frame_params_t;

    -- Config bytes for CC Basic, DLC=1
    -- Byte 0: FORMAT=000, FTYP=0, ESI=0, BRS=0, unused=00 => 0x00
    -- Byte 1: DLC=0001, unused=0000 => 0x10
    constant config_byte_0_c : byte_t := "00000000";
    constant config_byte_1_c : byte_t := "00010000";

  begin

    -- Wait for reset release
    wait until rst = '0';

    -- Calculate frame params for the test frame
    params_v := calculate_frame_params(config_byte_0_c, config_byte_1_c);

    -- Main monitoring loop
    loop
      -- Wait for SOF (tx_bus goes dominant from recessive idle)
      wait until tx_bus_o = dominant_bit_c and tx_bus_o'event;

      -- Reset tracking for new frame
      consecutive_count_v := 1;
      last_polarity_v     := dominant_bit_c;
      frame_position_v    := 0; -- SOF = position 0

      -- Track each subsequent bit at nominal bit time boundaries
      for bit_idx in 1 to 200 loop
        -- Wait one nominal bit time
        wait for nom_bit_time_clk_c * clk_period_c;

        -- Sample current bus polarity
        is_stuff_bit_v := false;

        -- Check for stuff bit: after 5 consecutive same-polarity bits
        if (consecutive_count_v >= 5) then
          is_stuff_bit_v      := true;
          consecutive_count_v := 1;
          last_polarity_v     := tx_bus_o;
        else
          -- Real frame bit
          frame_position_v := frame_position_v + 1;

          if (tx_bus_o = last_polarity_v) then
            consecutive_count_v := consecutive_count_v + 1;
          else
            consecutive_count_v := 1;
            last_polarity_v     := tx_bus_o;
          end if;
        end if;

        -- ACK injection: override bus to dominant at ACK slot position
        if (not is_stuff_bit_v and frame_position_v = params_v.ack_slot and inject_ack) then
          bus_override_en <= true;
          bus_override    <= dominant_bit_c;
          wait for nom_bit_time_clk_c * clk_period_c;
          bus_override_en <= false;
          -- Continue tracking after ACK
          frame_position_v    := frame_position_v + 1;
          consecutive_count_v := 1;
          last_polarity_v     := dominant_bit_c;
        end if;

        -- Exit loop when frame ends (past EOF)
        if (frame_position_v >= params_v.eof_stop) then
          exit;
        end if;
      end loop;

    end loop;

  end process bus_monitor;

  -- =========================================================================
  -- Main Test Process
  -- =========================================================================
  test_runner : process is

    variable alert_id : AlertLogIDType;

    -- Helper: build default LLC frame (CC Basic, DLC=1, ID=0x555, data=0xAA)
    procedure setup_default_frame (
      signal llc_user : out llc_user_to_llc_if_t
    ) is
    begin
      llc_user.frame.format <= cc_basic;
      llc_user.frame.id     <= std_logic_vector(to_unsigned(16#555#, 29));
      llc_user.frame.dlc    <= "0001"; -- DLC=1
      llc_user.frame.ftyp   <= '0';   -- Data frame
      llc_user.frame.brs    <= '0';
      llc_user.frame.esi    <= '0';
      llc_user.frame.data   <= (others => '0');
      llc_user.frame.data(max_data_bytes_c * 8 - 1 downto max_data_bytes_c * 8 - 8) <= x"AA";
      llc_user.tx_request    <= '0';
      llc_user.abort_request <= '0';
    end procedure setup_default_frame;

    -- Helper: pulse tx_request for one clock
    procedure submit_request (
      signal llc_user : out llc_user_to_llc_if_t
    ) is
    begin
      llc_user.tx_request <= '1';
      wait until rising_edge(clk);
      llc_user.tx_request <= '0';
    end procedure submit_request;

    -- Helper: wait for transfer completion with timeout
    procedure wait_for_completion (
      timeout      : time;
      exp_status   : transfer_status_t;
      test_name    : string
    ) is
      variable start_time : time;
    begin
      start_time := now;
      while (now - start_time < timeout) loop
        wait until rising_edge(clk);
        if (llc_user_o.transfer_status /= ongoing) then
          AffirmIf(alert_id,
            llc_user_o.transfer_status = exp_status,
            test_name & ": expected " & transfer_status_t'image(exp_status) &
            " got " & transfer_status_t'image(llc_user_o.transfer_status));
          return;
        end if;
      end loop;
      Alert(alert_id, test_name & ": TIMEOUT after " & time'image(timeout));
    end procedure wait_for_completion;

  begin

    alert_id := GetAlertLogID("tx_can_tb");

    -- Initialize inputs
    llc_user_i.frame.format <= cc_basic;
    llc_user_i.frame.id     <= (others => '0');
    llc_user_i.frame.dlc    <= (others => '0');
    llc_user_i.frame.ftyp   <= '0';
    llc_user_i.frame.brs    <= '0';
    llc_user_i.frame.esi    <= '0';
    llc_user_i.frame.data   <= (others => '0');
    llc_user_i.tx_request    <= '0';
    llc_user_i.abort_request <= '0';

    -- Reset
    rst <= '1';
    wait for 5 * clk_period_c;
    wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);

    -- =======================================================================
    -- Test 1: Successful CC Basic transmission (happy path)
    -- =======================================================================
    Log(alert_id, "Test 1: Successful CC Basic transmission");
    inject_ack <= true;
    setup_default_frame(llc_user_i);
    wait until rising_edge(clk);

    -- Verify tx_ready is high before submission
    AffirmIf(alert_id, llc_user_o.tx_ready = '1', "Test 1: tx_ready high before submit");

    -- Submit frame
    submit_request(llc_user_i);

    -- tx_ready should go low
    wait for 2 * clk_period_c;
    AffirmIf(alert_id, llc_user_o.tx_ready = '0', "Test 1: tx_ready low during transmission");

    -- Wait for completion
    wait_for_completion(100 us, transmitted, "Test 1");

    -- tx_ready should return high
    wait for 2 * clk_period_c;
    AffirmIf(alert_id, llc_user_o.tx_ready = '1', "Test 1: tx_ready high after completion");

    -- Wait for bus to settle
    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 2: Abort before MAC acceptance (send_config_0)
    -- =======================================================================
    Log(alert_id, "Test 2: Abort before MAC acceptance");
    inject_ack <= true;
    setup_default_frame(llc_user_i);
    wait until rising_edge(clk);

    -- Submit frame
    llc_user_i.tx_request <= '1';
    wait until rising_edge(clk);
    llc_user_i.tx_request <= '0';

    -- Immediately pulse abort on the NEXT clock (LLC is in send_config_0)
    llc_user_i.abort_request <= '1';
    wait until rising_edge(clk);
    llc_user_i.abort_request <= '0';

    -- Wait a few clocks for abort to take effect
    wait for 5 * clk_period_c;

    AffirmIf(alert_id,
      llc_user_o.transfer_status = aborted,
      "Test 2: transfer_status = aborted, got " & transfer_status_t'image(llc_user_o.transfer_status));
    AffirmIf(alert_id,
      llc_user_o.tx_ready = '1',
      "Test 2: tx_ready = 1 after abort");

    -- Wait for bus to settle
    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 3: Abort ignored after MAC acceptance
    -- =======================================================================
    Log(alert_id, "Test 3: Abort ignored after MAC acceptance");
    inject_ack <= true;
    setup_default_frame(llc_user_i);
    wait until rising_edge(clk);

    -- Submit frame
    submit_request(llc_user_i);

    -- Wait several clocks so LLC passes send_config_0 into send_config_1/send_data
    wait for 10 * clk_period_c;

    -- Now try to abort - should be ignored since MAC is already processing
    llc_user_i.abort_request <= '1';
    wait until rising_edge(clk);
    llc_user_i.abort_request <= '0';

    -- Frame should still complete successfully (abort ignored)
    wait_for_completion(100 us, transmitted, "Test 3");

    -- tx_ready should return high
    wait for 2 * clk_period_c;
    AffirmIf(alert_id, llc_user_o.tx_ready = '1', "Test 3: tx_ready high after completion");

    -- Wait for bus to settle
    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 4: Retransmission limit exceeded
    -- =======================================================================
    Log(alert_id, "Test 4: Retransmission limit exceeded");
    inject_ack <= false; -- No ACK -> ACK error -> disturbed
    setup_default_frame(llc_user_i);
    wait until rising_edge(clk);

    -- Submit frame
    submit_request(llc_user_i);

    -- Wait for final abort after retransmission_limit_c + 1 = 7 attempts
    -- Each attempt: ~50 bit times frame + 6 error flag + 8 delimiter + 3 intermission = ~67 bit times
    -- 67 * 50 clk/bit * 7 attempts = ~23450 clocks ~ 235 us
    wait_for_completion(400 us, aborted, "Test 4");

    -- tx_ready should return high
    wait for 2 * clk_period_c;
    AffirmIf(alert_id, llc_user_o.tx_ready = '1', "Test 4: tx_ready high after retransmission limit");

    -- =======================================================================
    -- Done
    -- =======================================================================
    wait for 10 * clk_period_c;
    ReportAlerts;
    test_done <= true;
    wait;

  end process test_runner;

end architecture tb;
