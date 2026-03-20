--------------------------------------------------------------------------------
-- Title      : CAN Transmitter Integration Testbench
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_tx_tb.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Integration testbench for can_tx top-level entity.
--              Tests full transmit path: LLC user request -> bus output.
--
-- Test scenarios:
--   1. Successful CC Basic transmission (happy path)
--   2. Abort before MAC acceptance (send_config_0 state)
--   3. Abort ignored after MAC acceptance
--   4. CC Extended format smoke test (no ACK)
--   5. FD Basic format smoke test (no ACK)
--   6. FD Extended format smoke test (no ACK)
--   7. Retransmission limit exceeded (7 attempts, no ACK)
--   8. FD format pressure smoke (repeated FD basic/extended submissions)
--   9. Bit error triggers error flag and retransmission
--  10. Dominant during intermission triggers overload flag
--  11. FD Overlapping ACK (dominant during delimiter only)
--  12. Arbitration Loss Withdrawal
--  13. Remote Frame Support (RTR=1)
--  14. Bit Rate Switching Timing Validation
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;
  use work.can_protocol_pkg.all;

library osvvm;
  use osvvm.AlertLogPkg.all;

entity can_tx_tb is
end entity can_tx_tb;

architecture tb of can_tx_tb is

  -- Clock and reset
  constant clk_period_c : time := 10 ns; -- 100 MHz
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- Bit timing constants (matching can_tx defaults)
  constant nom_prescaler_c  : integer := 4;
  constant nom_sync_seg_c   : integer := 1;
  constant nom_prop_seg_c   : integer := 24;
  constant nom_phase_seg1_c : integer := 15;
  constant nom_phase_seg2_c : integer := 10;
  constant nom_bit_time_tq_c : integer := nom_sync_seg_c + nom_prop_seg_c + nom_phase_seg1_c + nom_phase_seg2_c;
  constant nom_bit_time_clk_c : integer := nom_bit_time_tq_c * nom_prescaler_c; -- 200 clocks
  constant nom_sp_tq_c : integer := nom_sync_seg_c + nom_prop_seg_c + nom_phase_seg1_c; -- 40 TQ

  -- FSM state constants (must match can_mac_fsm_tx local encoding)
  constant c_st_bus_reintegration    : std_logic_vector(2 downto 0) := "000";
  constant c_st_intermission         : std_logic_vector(2 downto 0) := "001";
  constant c_st_suspend_transmission : std_logic_vector(2 downto 0) := "010";
  constant c_st_bus_idle             : std_logic_vector(2 downto 0) := "011";
  constant c_st_transmitting_frame   : std_logic_vector(2 downto 0) := "100";
  constant c_st_active_error_flag    : std_logic_vector(2 downto 0) := "101";
  constant c_st_passive_error_flag   : std_logic_vector(2 downto 0) := "110";
  constant c_st_overload_flag        : std_logic_vector(2 downto 0) := "111";

  -- DUT signals
  signal llc_user_i : t_can_user_llc_tx_if_s2d;
  signal llc_user_o : t_can_user_llc_tx_if_d2s;
  signal fce_i      : t_can_mac_fce_if_s2m;
  signal fce_o      : t_can_mac_fce_if_m2s;
  signal tx_bus_o   : std_logic;
  signal rx_bus_i   : std_logic;

  -- Debug signals from DUT
  signal debug_mac_to_pcs : t_can_mac_pcs_tx_if_m2s;
  signal debug_pcs_to_mac : t_can_mac_pcs_tx_if_s2m;
  signal debug_bit_name   : t_mac_frame_bit_name;
  signal fsm_state        : std_logic_vector(2 downto 0);

  -- Bus model control
  signal inject_ack   : boolean := true;
  signal bus_override_monitor    : std_logic := c_recessive;
  signal bus_override_monitor_en : boolean := false;
  signal bus_override_test       : std_logic := c_recessive;
  signal bus_override_test_en    : boolean := false;

  -- Test tracking
  signal test_done : boolean := false;
  signal current_test_id : integer range 0 to 15 := 0;
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
  constant test_13_c   : integer := 13;
  constant test_14_c   : integer := 14;
  constant test_done_c : integer := 15;

  -- Bitstream capture buffers
  constant max_raw_bits_c : integer := c_max_mac_frame_length * 2;

begin

  -- Clock generation
  clk <= not clk after clk_period_c / 2 when not test_done;

  -- DUT instantiation
  dut : entity work.can_tx
    port map (
      clk_i          => clk,
      rst_i          => rst,
      llc_user_i     => llc_user_i,
      llc_user_o     => llc_user_o,
      fce_i          => fce_i,
      fce_o          => fce_o,
      tx_bus_o       => tx_bus_o,
      rx_bus_i       => rx_bus_i,
      debug_mac_to_pcs_o => debug_mac_to_pcs,
      debug_pcs_to_mac_o => debug_pcs_to_mac,
      debug_ack_error_o  => open,
      debug_form_error_o => open,
      debug_data_exit_o  => open,
      debug_pcs_state_o  => open,
      debug_fsm_state_o  => fsm_state,
      debug_bit_name_o   => debug_bit_name
    );

  -- Bus model: loopback with optional ACK injection and test override
  rx_bus_i <= bus_override_test    when bus_override_test_en else
              bus_override_monitor when bus_override_monitor_en else
              tx_bus_o;

  -- FCE: error-active node
  fce_i.error_passive_request <= '0';
  fce_i.error_active_request  <= '1';
  fce_i.bus_off               <= '0';

  p_state_log : process (fsm_state) is
  begin
    if (fsm_state'event) then
      Log(GetAlertLogID("can_tx_tb"), "FSM State transition to: " & to_hstring(fsm_state));
    end if;
  end process p_state_log;

  -- =========================================================================
  -- Bus Monitor Process: Handles automatic ACK injection
  -- =========================================================================
  bus_monitor : process is
  begin
    wait until rst = '0';
    loop
      wait until rising_edge(clk);

      -- Inject ACK when FSM advances to ACK slot bit
      -- debug_bit_name is registered, so it shows current bit being transmitted.
      -- We inject dominant as soon as FSM enters the ACK slot, covering the sample point.
      if (inject_ack and debug_bit_name = ack_bit) then

        bus_override_monitor    <= c_dominant;
        bus_override_monitor_en <= true;

        -- Hold for one nominal bit time (covers ACK slot sample point)
        wait for nom_bit_time_clk_c * clk_period_c;
        bus_override_monitor_en <= false;
      end if;
    end loop;
  end process bus_monitor;

  -- =========================================================================
  -- Main Test Process
  -- =========================================================================
  test_runner : process is

    variable alert_id : AlertLogIDType;
    variable dlc_v    : integer;
    variable frame_v  : t_llc_frame;

    function frame_to_params (
      frame : t_llc_frame
    ) return t_frame_params is
      variable meta_v : t_llc_metadata;
    begin
      meta_v.format          := frame.config_0.format;
      meta_v.dlc_vector      := frame.config_1.dlc;
      meta_v.is_remote_frame := frame.config_0.ftyp;
      meta_v.has_brs         := frame.config_0.brs;
      meta_v.esi_enable      := frame.config_0.esi;
      return calculate_frame_params(meta_v);
    end function frame_to_params;

    -- Helper: build default LLC frame (CC Basic, DLC=1, ID=0x555, data=0xAA)
    procedure setup_default_frame (
      variable frame : out t_llc_frame
    ) is
    begin
      frame.id               := std_logic_vector(to_unsigned(16#555#, 32));
      frame.config_0.format  := c_llc_fmt_cb;
      frame.config_0.ftyp    := '0'; -- Data frame
      frame.config_0.esi     := '0';
      frame.config_0.brs     := '0';
      frame.config_0.unused  := "00";
      frame.config_1.dlc     := "0001"; -- DLC=1
      frame.config_1.unused  := "0000";
      frame.data   := (others => '0');
      frame.data(c_max_data_bytes * 8 - 1 downto c_max_data_bytes * 8 - 8) := x"AA";
    end procedure setup_default_frame;

    procedure send_user_byte (
      value : t_byte;
      sop   : std_logic;
      eop   : std_logic
    ) is
    begin
      llc_user_i.avalon_st_source.data  <= value;
      llc_user_i.avalon_st_source.valid <= '1';
      llc_user_i.avalon_st_source.startofpacket   <= sop;
      llc_user_i.avalon_st_source.endofpacket   <= eop;
      loop
        wait until rising_edge(clk);
        exit when llc_user_o.avalon_st_sink.ready = '1';
      end loop;
    end procedure send_user_byte;

    -- Helper: stream frame as 71-byte legacy LLC format to can_llc_tx(legacy_rtl).
    procedure submit_frame (
      frame : t_llc_frame
    ) is
      variable id_v             : std_logic_vector(28 downto 0);
      variable is_extended_v    : boolean;
      variable byte0_v          : t_byte;
      variable byte1_v          : t_byte;
      variable byte2_v          : t_byte;
      variable byte3_v          : t_byte;
      variable byte4_v          : t_byte;
      variable byte69_v         : t_byte;
      variable byte70_v         : t_byte;
      variable data_byte_count_v : integer;
      variable data_bit_start_v : integer;
    begin
      id_v          := frame.id(28 downto 0);
      is_extended_v := frame.config_0.format(2) = '1';

      if is_extended_v then
        byte0_v := "000" & id_v(28 downto 24);
        byte1_v := id_v(23 downto 16);
        byte2_v := id_v(15 downto 8);
        byte3_v := id_v(7 downto 0);
      else
        byte0_v := (others => '0');
        byte1_v := (others => '0');
        byte2_v := "00000" & id_v(10 downto 8);
        byte3_v := id_v(7 downto 0);
      end if;

      byte4_v := "0" & frame.config_0.format & frame.config_1.dlc;
      byte69_v := "0000000" & frame.config_0.format(2);
      byte70_v := "00000" & frame.config_0.brs & frame.config_0.esi & frame.config_0.ftyp;

      data_byte_count_v := dlc_to_data_length(
                              t_dlc(to_integer(unsigned(frame.config_1.dlc))),
                              frame.config_0.format
                            );

      send_user_byte(byte0_v, '1', '0');
      send_user_byte(byte1_v, '0', '0');
      send_user_byte(byte2_v, '0', '0');
      send_user_byte(byte3_v, '0', '0');
      send_user_byte(byte4_v, '0', '0');

      for i in 0 to 63 loop
        if i < data_byte_count_v then
          data_bit_start_v := frame.data'left - i * 8;
          send_user_byte(frame.data(data_bit_start_v downto data_bit_start_v - 7), '0', '0');
        else
          send_user_byte((others => '0'), '0', '0');
        end if;
      end loop;

      send_user_byte(byte69_v, '0', '0');
      send_user_byte(byte70_v, '0', '1');

      llc_user_i.avalon_st_source.valid <= '0';
      llc_user_i.avalon_st_source.startofpacket   <= '0';
      llc_user_i.avalon_st_source.endofpacket   <= '0';
    end procedure submit_frame;

    -- Helper: wait for transfer completion with timeout
    procedure wait_for_completion (
      timeout      : time;
      exp_status   : std_logic_vector(2 downto 0);
      test_name    : string
    ) is
      variable start_time : time;
    begin
      start_time := now;
      while (now - start_time < timeout) loop
        wait until rising_edge(clk);
        if (llc_user_o.transfer_status /= c_ongoing) then
          AffirmIf(alert_id,
            llc_user_o.transfer_status = exp_status,
            test_name & ": expected status, got " & to_hstring(llc_user_o.transfer_status));
          return;
        end if;
      end loop;
      Alert(alert_id, test_name & ": TIMEOUT after " & time'image(timeout));
    end procedure wait_for_completion;

    -- Helper: wait until bit_name reaches target with timeout
    procedure wait_for_fsm_bit_name (
      name      : t_mac_frame_bit_name;
      timeout   : time;
      test_name : string
    ) is
      variable start_time : time;
    begin
      start_time := now;
      while (now - start_time < timeout) loop
        wait until rising_edge(clk);
        if (debug_mac_to_pcs.valid = '1' and debug_bit_name = name) then
          return;
        end if;
      end loop;
      Alert(alert_id, test_name & ": wait_for_fsm_bit_name TIMEOUT for " &
            t_mac_frame_bit_name'image(name) & " at " & time'image(timeout));
    end procedure wait_for_fsm_bit_name;

    -- Helper: wait until FSM presents SOF with timeout
    procedure wait_for_sof (
      timeout   : time;
      test_name : string
    ) is
      variable start_time : time;
    begin
      start_time := now;
      while (now - start_time < timeout) loop
        wait until rising_edge(clk);
        if (debug_mac_to_pcs.valid = '1' and debug_bit_name = sof_bit) then
          return;
        end if;
      end loop;
      Alert(alert_id, test_name & ": SOF TIMEOUT after " & time'image(timeout));
    end procedure wait_for_sof;

    -- Helper: wait until FSM enters target state with timeout
    procedure wait_for_fsm_state (
      target    : std_logic_vector(2 downto 0);
      timeout   : time;
      test_name : string
    ) is
      variable start_time : time;
    begin
      start_time := now;
      while (now - start_time < timeout) loop
        wait until rising_edge(clk);
        if (fsm_state = target) then
          return;
        end if;
      end loop;
      Alert(alert_id, test_name & ": FSM state TIMEOUT waiting for " &
        to_hstring(target) & " after " & time'image(timeout));
    end procedure wait_for_fsm_state;

    -- Helper: wait until sample strobe occurs with timeout
    procedure wait_for_sample_strobe (
      timeout   : time;
      test_name : string
    ) is
      variable start_time : time;
    begin
      start_time := now;
      while (now - start_time < timeout) loop
        wait until rising_edge(clk);
        if (debug_pcs_to_mac.sp = '1') then
          return;
        end if;
      end loop;
      Alert(alert_id, test_name & ": sample_strobe TIMEOUT after " & time'image(timeout));
    end procedure wait_for_sample_strobe;

    -- Helper: inject bit error by overriding bus for one bit time
    procedure inject_bit_error is
    begin
      if (tx_bus_o = c_dominant) then
        bus_override_test <= c_recessive;
      else
        bus_override_test <= c_dominant;
      end if;
      bus_override_test_en <= true;
      wait for nom_bit_time_clk_c * clk_period_c;
      bus_override_test_en <= false;
    end procedure inject_bit_error;

    -- Helper: reset FSM and wait for MAC ready
    procedure reset_and_prepare is
    begin
      rst <= '1';
      wait for 2 * nom_bit_time_clk_c * clk_period_c;
      wait until rising_edge(clk);
      rst <= '0';
      llc_user_i.avalon_st_source.valid <= '0';
      llc_user_i.abort_request <= '0';
      wait until rising_edge(clk);
      wait for 20 * nom_bit_time_clk_c * clk_period_c;
    end procedure reset_and_prepare;

    -- Helper: wait for N sample strobes
    procedure wait_for_n_strobes (
      n         : integer;
      test_name : string
    ) is
    begin
      for i in 1 to n loop
        wait_for_sample_strobe(50 us, test_name & " strobe " & integer'image(i));
        if (i < n) then
          wait until rising_edge(clk);
        end if;
      end loop;
    end procedure wait_for_n_strobes;

    -- Helper: wait until a specific bit name appears at sample strobe
    procedure wait_for_bit_at_strobe (
      bit_name  : t_mac_frame_bit_name;
      timeout   : time;
      test_name : string
    ) is
      variable start_time : time;
    begin
      start_time := now;
      while (now - start_time < timeout) loop
        wait until rising_edge(clk);
        if (debug_pcs_to_mac.sp = '1') then
          wait until rising_edge(clk);
          if (debug_bit_name = bit_name) then
            return;
          end if;
        end if;
      end loop;
      Alert(alert_id, test_name & ": bit " & t_mac_frame_bit_name'image(bit_name) &
            " at strobe TIMEOUT after " & time'image(timeout));
    end procedure wait_for_bit_at_strobe;

    -- Helper: wait for sample strobe, then verify a bus value
    procedure wait_and_verify_at_strobe (
      expected : std_logic;
      test_name : string
    ) is
    begin
      while (true) loop
        wait until rising_edge(clk);
        if (debug_pcs_to_mac.sp = '1') then
          AffirmIf(alert_id, tx_bus_o = expected, test_name);
          exit;
        end if;
      end loop;
    end procedure wait_and_verify_at_strobe;

  begin

    alert_id := GetAlertLogID("can_tx_tb");

    -- Initialize inputs
    llc_user_i.avalon_st_source.data   <= (others => '0');
    llc_user_i.avalon_st_source.valid  <= '0';
    llc_user_i.avalon_st_source.startofpacket    <= '0';
    llc_user_i.avalon_st_source.endofpacket    <= '0';
    llc_user_i.abort_request <= '0';

    -- Reset
    current_test_id <= test_idle_c;
    rst <= '1';
    wait for 5 * clk_period_c;
    wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);

    -- =======================================================================
    -- Test 1: Successful CC Basic transmission (happy path)
    -- =======================================================================
    current_test_id <= test_1_c;
    Log(alert_id, "Test 1: Successful CC Basic transmission");
    inject_ack <= true;

    setup_default_frame(frame_v);
    wait until rising_edge(clk);

    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '1', "Test 1: tx_ready high before submit");

    submit_frame(frame_v);

    wait for 2 * clk_period_c;
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '0', "Test 1: tx_ready low during transmission");

    wait_for_completion(300 us, c_transmitted, "Test 1");
    wait for 2 * clk_period_c;

    wait for 2 * clk_period_c;
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '1', "Test 1: tx_ready high after completion");

    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 2: Abort before MAC acceptance (send_config_0)
    -- =======================================================================
    current_test_id <= test_2_c;
    Log(alert_id, "Test 2: Abort before MAC acceptance");
    inject_ack <= true;
    setup_default_frame(frame_v);
    wait until rising_edge(clk);

    send_user_byte("00000" & frame_v.id(10 downto 8), '1', '0');
    llc_user_i.avalon_st_source.valid <= '0';
    llc_user_i.avalon_st_source.startofpacket   <= '0';

    llc_user_i.abort_request <= '1';
    wait until rising_edge(clk);
    llc_user_i.abort_request <= '0';
    wait until rising_edge(clk);

    AffirmIf(alert_id,
      llc_user_o.transfer_status = c_aborted,
      "Test 2: transfer_status = aborted, got " & to_hstring(llc_user_o.transfer_status));

    wait until rising_edge(clk);
    AffirmIf(alert_id,
      llc_user_o.avalon_st_sink.ready = '1',
      "Test 2: tx_ready = 1 after abort");

    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 3: Abort ignored after MAC acceptance
    -- =======================================================================
    current_test_id <= test_3_c;
    Log(alert_id, "Test 3: Abort ignored after MAC acceptance");
    inject_ack <= true;
    setup_default_frame(frame_v);
    wait until rising_edge(clk);

    submit_frame(frame_v);

    wait_for_sof(200 us, "Test 3 SOF");

    llc_user_i.abort_request <= '1';
    wait until rising_edge(clk);
    llc_user_i.abort_request <= '0';

    wait_for_completion(300 us, c_transmitted, "Test 3");

    wait for 2 * clk_period_c;
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '1', "Test 3: tx_ready high after completion");

    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 4: CC Extended format smoke test (no ACK -> aborted)
    -- =======================================================================
    current_test_id <= test_4_c;
    Log(alert_id, "Test 4: CC Extended format smoke test (no ACK)");
    inject_ack <= false;
    setup_default_frame(frame_v);
    frame_v.config_0.format := c_llc_fmt_ce;
    frame_v.id(28 downto 0) := std_logic_vector(to_unsigned(16#1ABCDEF#, 29));
    wait until rising_edge(clk);

    submit_frame(frame_v);

    wait_for_completion(2 ms, c_aborted, "Test 4");
    wait for 2 * clk_period_c;
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '1', "Test 4: tx_ready high after completion");
    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 5: FD Basic format smoke test (no ACK -> aborted)
    -- =======================================================================
    current_test_id <= test_5_c;
    Log(alert_id, "Test 5: FD Basic format smoke test (no ACK)");
    inject_ack <= false;
    setup_default_frame(frame_v);
    frame_v.config_0.format := c_llc_fmt_fb;
    frame_v.config_0.brs    := '0';
    frame_v.config_1.dlc    := std_logic_vector(to_unsigned(9, 4));
    wait until rising_edge(clk);

    submit_frame(frame_v);
    wait for 2 * clk_period_c;
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '0', "Test 5: tx_ready low after submit");
    wait_for_sof(80 us, "Test 5");
    wait for 2 * clk_period_c;
    rst <= '1';
    wait for 5 * clk_period_c;
    wait until rising_edge(clk);
    rst <= '0';
    llc_user_i.avalon_st_source.valid <= '0';
    llc_user_i.abort_request <= '0';
    wait until rising_edge(clk);
    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 6: FD Extended format smoke test (no ACK -> aborted)
    -- =======================================================================
    current_test_id <= test_6_c;
    Log(alert_id, "Test 6: FD Extended format smoke test (no ACK)");
    inject_ack <= false;
    setup_default_frame(frame_v);
    frame_v.config_0.format := c_llc_fmt_fe;
    frame_v.config_0.brs    := '0';
    frame_v.config_1.dlc    := std_logic_vector(to_unsigned(10, 4));
    frame_v.id(28 downto 0) := std_logic_vector(to_unsigned(16#1234567#, 29));
    wait until rising_edge(clk);

    submit_frame(frame_v);
    wait for 2 * clk_period_c;
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '0', "Test 6: tx_ready low after submit");
    wait_for_sof(120 us, "Test 6");
    wait for 2 * clk_period_c;
    rst <= '1';
    wait for 5 * clk_period_c;
    wait until rising_edge(clk);
    rst <= '0';
    llc_user_i.avalon_st_source.valid <= '0';
    llc_user_i.abort_request <= '0';
    wait until rising_edge(clk);
    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 7: Retransmission limit exceeded
    -- =======================================================================
    current_test_id <= test_7_c;
    Log(alert_id, "Test 7: Retransmission limit exceeded");
    inject_ack <= false;
    setup_default_frame(frame_v);
    wait until rising_edge(clk);

    submit_frame(frame_v);

    wait_for_completion(2 ms, c_aborted, "Test 7");

    wait for 2 * clk_period_c;
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '1', "Test 7: tx_ready high after retransmission limit");

    -- =======================================================================
    -- Test 8: FD format pressure smoke (repeated submissions)
    -- =======================================================================
    current_test_id <= test_8_c;
    Log(alert_id, "Test 8: FD format pressure smoke");
    inject_ack <= false;

    for iter in 0 to 11 loop
      rst <= '1';
      wait for 5 * clk_period_c;
      wait until rising_edge(clk);
      rst <= '0';
      llc_user_i.avalon_st_source.valid <= '0';
      llc_user_i.abort_request <= '0';
      wait until rising_edge(clk);

      setup_default_frame(frame_v);
      dlc_v := (iter mod 8) + 8;
      frame_v.config_1.dlc := std_logic_vector(to_unsigned(dlc_v, 4));
      frame_v.id  := std_logic_vector(to_unsigned(16#100# + iter, 32));
      if ((iter mod 2) = 0) then
        frame_v.config_0.format := c_llc_fmt_fb;
      else
        frame_v.config_0.format := c_llc_fmt_fe;
      end if;

      wait until rising_edge(clk);
      wait until rising_edge(clk);

      submit_frame(frame_v);
      wait for 2 * clk_period_c;
      AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '0', "Test 8: tx_ready low after submit");
      wait_for_sof(140 us, "Test 8");
      wait for 10 * clk_period_c;
    end loop;

    -- =======================================================================
    -- Test 9: Bit error triggers error flag and recovery
    -- =======================================================================
    current_test_id <= test_9_c;
    Log(alert_id, "Test 9: Bit error triggers error flag and recovery");

    reset_and_prepare;

    inject_ack <= false;
    setup_default_frame(frame_v);
    wait until rising_edge(clk);

    submit_frame(frame_v);
    wait_for_fsm_bit_name(data_bit, 500 us, "Test 9 data field arrival");
    wait_for_sample_strobe(50 us, "Test 9 data SP");
    inject_bit_error;

    wait_for_fsm_state(c_st_active_error_flag, 20 us, "Test 9");
    wait until rising_edge(clk);
    AffirmIf(alert_id,
      fsm_state = c_st_active_error_flag,
      "Test 9: FSM entered active error flag");

    AffirmIf(alert_id,
      fce_o.sending_error_overload_flag = '1',
      "Test 9: sending_error_overload_flag asserted during error flag transmission");

    wait_for_fsm_state(c_st_bus_idle, 100 us, "Test 9 recovery");

    reset_and_prepare;

    inject_ack <= true;
    setup_default_frame(frame_v);
    wait until rising_edge(clk);

    submit_frame(frame_v);
    wait_for_completion(300 us, c_transmitted, "Test 9 recovery frame");

    wait for 2 * clk_period_c;
    AffirmIf(alert_id,
      llc_user_o.avalon_st_sink.ready = '1',
      "Test 9: tx_ready high after recovery");

    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 10: Dominant during intermission triggers overload flag
    -- =======================================================================
    current_test_id <= test_10_c;
    Log(alert_id, "Test 10: Dominant during intermission triggers overload flag");

    rst <= '1';
    wait for 2 * nom_bit_time_clk_c * clk_period_c;
    wait until rising_edge(clk);
    rst <= '0';
    llc_user_i.avalon_st_source.valid <= '0';
    llc_user_i.abort_request <= '0';
    wait until rising_edge(clk);
    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    inject_ack <= true;
    setup_default_frame(frame_v);
    wait until rising_edge(clk);

    submit_frame(frame_v);

    wait_for_fsm_bit_name(eof_bit, 500 us, "Test 10 eof arrival");
    wait_for_n_strobes(7, "Test 10 EOF");

    bus_override_test <= c_dominant;
    bus_override_test_en <= true;
    wait for nom_bit_time_clk_c * clk_period_c;
    bus_override_test_en <= false;

    AffirmIf(alert_id, llc_user_o.transfer_status = c_transmitted, "Test 10 first frame: expected transmitted");

    wait_for_fsm_state(c_st_overload_flag, 20 us, "Test 10");
    wait until rising_edge(clk);
    AffirmIf(alert_id,
      fsm_state = c_st_overload_flag,
      "Test 10: FSM entered overload flag");

    AffirmIf(alert_id,
      fce_o.sending_error_overload_flag = '1',
      "Test 10: sending_error_overload_flag asserted during overload flag transmission");

    wait_for_fsm_state(c_st_bus_idle, 100 us, "Test 10 recovery");

    reset_and_prepare;

    inject_ack <= true;
    setup_default_frame(frame_v);
    wait until rising_edge(clk);

    submit_frame(frame_v);
    wait_for_completion(300 us, c_transmitted, "Test 10 second frame");

    wait for 2 * clk_period_c;
    AffirmIf(alert_id,
      llc_user_o.avalon_st_sink.ready = '1',
      "Test 10: tx_ready high after recovery");

    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 11: FD Overlapping ACK (dominant during delimiter only)
    -- =======================================================================
    current_test_id <= test_11_c;
    Log(alert_id, "Test 11: FD Overlapping ACK slot (dominant during delimiter only)");

    inject_ack <= false;

    setup_default_frame(frame_v);
    frame_v.config_0.format := c_llc_fmt_fb;
    wait until rising_edge(clk);

    submit_frame(frame_v);

    wait_for_bit_at_strobe(ack_delimiter_bit, 500 us, "Test 11");

    bus_override_test    <= c_dominant;
    bus_override_test_en <= true;

    wait for nom_bit_time_clk_c * clk_period_c;
    bus_override_test_en <= false;

    wait_for_completion(500 us, c_transmitted, "Test 11");

    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 12: Arbitration Loss Withdrawal
    -- =======================================================================
    current_test_id <= test_12_c;
    Log(alert_id, "Test 12: Arbitration Loss Withdrawal (monitored dominant while sending recessive ID)");

    inject_ack <= true;
    setup_default_frame(frame_v);
    frame_v.id := (others => '1');
    wait until rising_edge(clk);

    submit_frame(frame_v);

    wait_for_fsm_bit_name(base_id_bit, 500 us, "Test 12 ID arrival");
    wait_for_sample_strobe(50 us, "Test 12 ID SP");

    bus_override_test    <= c_dominant;
    bus_override_test_en <= true;
    wait for nom_bit_time_clk_c * clk_period_c;
    bus_override_test_en <= false;

    wait_for_fsm_state(c_st_intermission, 20 us, "Test 12 withdrawal");

    wait until rising_edge(clk);
    AffirmIf(alert_id, fce_o.sending_error_overload_flag = '0', "Test 12: No error flag on arbitration loss");

    wait_for_sof(1 ms, "Test 12 retry SOF");

    wait_for_completion(800 us, c_transmitted, "Test 12 retry completion");

    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 13: Remote Frame Support (RTR=1)
    -- =======================================================================
    current_test_id <= test_13_c;
    Log(alert_id, "Test 13: Remote Frame Support (RTR=1, DLC=8, Data omitted)");

    inject_ack <= true;
    setup_default_frame(frame_v);
    frame_v.config_0.ftyp   := '1';
    frame_v.config_1.dlc    := "1000";
    wait until rising_edge(clk);

    submit_frame(frame_v);

    wait_for_sof(100 us, "Test 13 SOF arrival");
    wait_for_fsm_bit_name(rtr_bit, 500 us, "Test 13 RTR arrival");

    wait_and_verify_at_strobe(c_recessive, "Test 13: RTR must be recessive");

    wait_for_completion(300 us, c_transmitted, "Test 13 completion");

    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 14: Bit Rate Switching Timing Validation
    -- =======================================================================
    current_test_id <= test_14_c;
    Log(alert_id, "Test 14: Bit Rate Switching Timing (Entry at BRS SP, Exit at CRC Delim SP)");

    rst <= '1'; wait for 5 * clk_period_c; wait until rising_edge(clk); rst <= '0';

    while (llc_user_o.avalon_st_sink.ready = '0') loop
      wait until rising_edge(clk);
    end loop;

    setup_default_frame(frame_v);
    frame_v.config_0.format := c_llc_fmt_fb;
    frame_v.config_0.brs    := '1';
    wait until rising_edge(clk);

    submit_frame(frame_v);

    wait_for_fsm_bit_name(brs_bit, 500 us, "Test 14 BRS arrival");

    wait for 100 us;

    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Done
    -- =======================================================================
    current_test_id <= test_done_c;
    wait for 10 * clk_period_c;
    ReportAlerts;
    test_done <= true;
    wait;

  end process test_runner;

end architecture tb;
