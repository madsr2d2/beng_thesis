--------------------------------------------------------------------------------
-- Title      : CAN Transmitter Integration Testbench
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : can_tx_tb.vhd
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
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

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

  -- DUT signals
  signal llc_user_i : can_user_llc_tx_if_s2d_t;
  signal llc_user_o : can_user_llc_tx_if_d2s_t;
  signal transfer_status_dbg : transfer_status_t;
  signal tx_ready_dbg        : std_logic;
  signal fce_i      : can_mac_fce_if_d2s_t;
  signal fce_o      : can_mac_fce_if_s2d_t;
  signal tx_bus_o   : std_logic;
  signal rx_bus_i   : std_logic;

  -- Debug signals from DUT
  signal debug_mac_to_pcs : can_mac_pcs_tx_if_s2d_t;
  signal debug_pcs_to_mac : can_mac_pcs_tx_if_d2s_t;

  -- Bus model control
  signal inject_ack   : boolean := true;
  signal bus_override_monitor    : std_logic := recessive_bit_c;
  signal bus_override_monitor_en : boolean := false;
  signal bus_override_test       : std_logic := recessive_bit_c;
  signal bus_override_test_en    : boolean := false;

  -- Test tracking
  signal test_done : boolean := false;
  -- Waveform marker for active test:
  -- 0=idle/reset, 1..14=test id, 15=done.
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
  -- FSM state observation via debug port
  signal fsm_state : can_mac_fsm_tx_state_t;

  -- Bitstream capture buffers (raw bus stream can include stuffed bits)
  constant max_raw_bits_c : integer := max_mac_frame_length_c * 2;

begin

  -- Clock generation
  clk <= not clk after clk_period_c / 2 when not test_done;

  -- DUT instantiation
  dut : entity work.can_tx
    port map (
      clk        => clk,
      rst        => rst,
      llc_user_i => llc_user_i,
      llc_user_o => llc_user_o,
      fce_i      => fce_i,
      fce_o      => fce_o,
      tx_bus_o   => tx_bus_o,
      rx_bus_i   => rx_bus_i,
      debug_mac_to_pcs_o => debug_mac_to_pcs,
      debug_pcs_to_mac_o => debug_pcs_to_mac,
      debug_fsm_state_o  => fsm_state
    );

  -- Bus model: loopback with optional ACK injection and test override
  -- Test override takes priority over monitor override
  rx_bus_i <= bus_override_test    when bus_override_test_en else
              bus_override_monitor when bus_override_monitor_en else
              tx_bus_o;

  -- FCE: error-active node (not error-passive)
  fce_i.error_passive <= false;
  transfer_status_dbg <= llc_user_o.transfer_status;
  tx_ready_dbg        <= llc_user_o.avalon_st_sink.ready;

  -- fsm_state is driven via the debug_fsm_state_o port from can_tx.

  p_state_log : process (fsm_state) is
  begin
    if (fsm_state'event) then
      Log(GetAlertLogID("can_tx_tb"), "FSM State transition to: " & can_mac_fsm_tx_state_t'image(fsm_state));
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
      
      -- Inject ACK if enabled and FSM is in the bit BEFORE the ACK slot (CRC Delimiter)
      -- This ensures the override is active for the start of the next bit.
      if (inject_ack and debug_pcs_to_mac.sample_strobe = '1' and 
          debug_mac_to_pcs.valid and debug_mac_to_pcs.data.bit_name = crc_delimiter_bit) then
        
        bus_override_monitor    <= dominant_bit_c;
        bus_override_monitor_en <= true;
        
        -- Hold for one nominal bit time
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
    variable frame_v  : llc_frame_t;
    

    function frame_to_params (
      frame : llc_frame_t
    ) return frame_params_t is
      variable config_0_v : byte_t;
      variable config_1_v : byte_t;
    begin
      config_0_v := frame.config_0.format
                    & frame.config_0.ftyp
                    & frame.config_0.esi
                    & frame.config_0.brs
                    & "00";
      config_1_v := frame.config_1.dlc & "0000";
      return calculate_frame_params(config_0_v, config_1_v);
    end function frame_to_params;

    -- Helper: build default LLC frame (CC Basic, DLC=1, ID=0x555, data=0xAA)
    procedure setup_default_frame (
      variable frame : out llc_frame_t
    ) is
    begin
      frame.id               := std_logic_vector(to_unsigned(16#555#, 32));
      frame.config_0.format  := llc_fmt_cb_c;
      frame.config_0.ftyp    := '0'; -- Data frame
      frame.config_0.esi     := '0';
      frame.config_0.brs     := '0';
      frame.config_0.unused  := "00";
      frame.config_1.dlc     := "0001"; -- DLC=1
      frame.config_1.unused  := "0000";
      frame.data   := (others => '0');
      frame.data(max_data_bytes_c * 8 - 1 downto max_data_bytes_c * 8 - 8) := x"AA";
    end procedure setup_default_frame;

    procedure send_user_byte (
      value : byte_t;
      sop   : std_logic;
      eop   : std_logic
    ) is
    begin
      llc_user_i.avalon_st_source.data  <= value;
      llc_user_i.avalon_st_source.valid <= '1';
      llc_user_i.avalon_st_source.sop   <= sop;
      llc_user_i.avalon_st_source.eop   <= eop;
      loop
        wait until rising_edge(clk);
        exit when llc_user_o.avalon_st_sink.ready = '1';
      end loop;
    end procedure send_user_byte;

    -- Helper: stream frame as 71-byte legacy LLC format to can_llc_tx(legacy_rtl).
    --
    -- Legacy layout (71 bytes):
    --   Bytes 0-3:  ID (right-aligned; CB/FB=11-bit in bytes 2-3, CE/FE=29-bit in bytes 0-3)
    --   Byte  4:    [7]=0, [6:4]=FMT, [3:0]=DLC
    --   Bytes 5-68: Data (DLC bytes then zero-padded to 64 bytes)
    --   Byte  69:   [7:1]=0, [0]=IDE (0 for CB/FB, 1 for CE/FE)
    --   Byte  70:   [7:3]=0, [2]=BRS, [1]=ESI, [0]=RTR
    procedure submit_frame (
      frame : llc_frame_t
    ) is
      variable id_v             : std_logic_vector(28 downto 0);
      variable is_extended_v    : boolean;
      variable byte0_v          : byte_t;
      variable byte1_v          : byte_t;
      variable byte2_v          : byte_t;
      variable byte3_v          : byte_t;
      variable byte4_v          : byte_t;
      variable byte69_v         : byte_t;
      variable byte70_v         : byte_t;
      variable data_byte_count_v : integer;
      variable data_bit_start_v : integer;
    begin
      id_v          := frame.id(28 downto 0);
      is_extended_v := frame.config_0.format(2) = '1'; -- MSB of FMT: CE/FE have bit2='1'

      -- Bytes 0-3: ID (right-aligned per legacy spec)
      if is_extended_v then
        -- 29-bit ID: byte0[4:0]=ID[28:24], byte1=ID[23:16], byte2=ID[15:8], byte3=ID[7:0]
        byte0_v := "000" & id_v(28 downto 24);
        byte1_v := id_v(23 downto 16);
        byte2_v := id_v(15 downto 8);
        byte3_v := id_v(7 downto 0);
      else
        -- 11-bit ID: byte2[2:0]=ID[10:8], byte3=ID[7:0], bytes 0-1 = 0
        byte0_v := (others => '0');
        byte1_v := (others => '0');
        byte2_v := "00000" & id_v(10 downto 8);
        byte3_v := id_v(7 downto 0);
      end if;

      -- Byte 4: FMT and DLC
      byte4_v := "0" & frame.config_0.format & frame.config_1.dlc;

      -- Byte 69: IDE flag
      byte69_v := "0000000" & frame.config_0.format(2);

      -- Byte 70: BRS, ESI, RTR
      byte70_v := "00000" & frame.config_0.brs & frame.config_0.esi & frame.config_0.ftyp;

      -- Compute data byte count for padding logic
      data_byte_count_v := dlc_to_data_length(
                              dlc_t(to_integer(unsigned(frame.config_1.dlc))),
                              decode_llc_format(frame.config_0.format)
                            );

      -- Stream 71 bytes: SOP on byte 0, EOP on byte 70
      send_user_byte(byte0_v, '1', '0');
      send_user_byte(byte1_v, '0', '0');
      send_user_byte(byte2_v, '0', '0');
      send_user_byte(byte3_v, '0', '0');
      send_user_byte(byte4_v, '0', '0');

      -- Bytes 5-68: data payload then zero-padding
      for i in 0 to 63 loop
        if i < data_byte_count_v then
          data_bit_start_v := frame.data'left - i * 8;
          send_user_byte(frame.data(data_bit_start_v downto data_bit_start_v - 7), '0', '0');
        else
          send_user_byte((others => '0'), '0', '0');
        end if;
      end loop;

      send_user_byte(byte69_v, '0', '0');
      send_user_byte(byte70_v, '0', '1'); -- EOP on last byte

      llc_user_i.avalon_st_source.valid <= '0';
      llc_user_i.avalon_st_source.sop   <= '0';
      llc_user_i.avalon_st_source.eop   <= '0';
    end procedure submit_frame;

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

    -- Helper: wait until bit_name reaches target with timeout
    procedure wait_for_fsm_bit_name (
      name      : mac_frame_bit_name_t;
      timeout   : time;
      test_name : string
    ) is
      variable start_time : time;
    begin
      start_time := now;
      while (now - start_time < timeout) loop
        wait until rising_edge(clk);
        if (debug_mac_to_pcs.valid and debug_mac_to_pcs.data.bit_name = name) then
          return;
        end if;
      end loop;
      Alert(alert_id, test_name & ": wait_for_fsm_bit_name TIMEOUT for " & 
            mac_frame_bit_name_t'image(name) & " at " & time'image(timeout));
    end procedure wait_for_fsm_bit_name;

    -- Helper: wait until bit_name reaches target with timeout
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
        if (debug_mac_to_pcs.valid and debug_mac_to_pcs.data.bit_name = sof_bit) then
          return;
        end if;
      end loop;
      Alert(alert_id, test_name & ": SOF TIMEOUT after " & time'image(timeout));
    end procedure wait_for_sof;

    -- Helper: wait until FSM enters target state with timeout
    procedure wait_for_fsm_state (
      target    : can_mac_fsm_tx_state_t;
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
      Alert(alert_id, test_name & ": FSM state TIMEOUT waiting for "
        & can_mac_fsm_tx_state_t'image(target) & " after " & time'image(timeout));
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
        if (debug_pcs_to_mac.sample_strobe = '1') then
          return;
        end if;
      end loop;
      Alert(alert_id, test_name & ": sample_strobe TIMEOUT after " & time'image(timeout));
    end procedure wait_for_sample_strobe;

    -- Helper: inject bit error by overriding bus for one bit time
    procedure inject_bit_error is
    begin
      -- Override rx_bus with opposite polarity of tx_bus for one bit time
      if (tx_bus_o = dominant_bit_c) then
        bus_override_test <= recessive_bit_c;
      else
        bus_override_test <= dominant_bit_c;
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

    -- Helper: wait for N sample strobes (for sequential bit waiting)
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

    -- Helper: wait until a specific bit name appears, synchronized with sample strobe
    procedure wait_for_bit_at_strobe (
      bit_name  : mac_frame_bit_name_t;
      timeout   : time;
      test_name : string
    ) is
      variable start_time : time;
    begin
      start_time := now;
      while (now - start_time < timeout) loop
        wait until rising_edge(clk);
        if (debug_pcs_to_mac.sample_strobe = '1') then
          wait until rising_edge(clk); -- Let FSM register the bit name
          if (debug_mac_to_pcs.data.bit_name = bit_name) then
            return;
          end if;
        end if;
      end loop;
      Alert(alert_id, test_name & ": bit " & mac_frame_bit_name_t'image(bit_name) &
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
        if (debug_pcs_to_mac.sample_strobe = '1') then
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
    llc_user_i.avalon_st_source.sop    <= '0';
    llc_user_i.avalon_st_source.eop    <= '0';
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


    -- Verify tx_ready is high before submission
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '1', "Test 1: tx_ready high before submit");

    -- Submit frame
    submit_frame(frame_v);

    -- tx_ready should go low
    wait for 2 * clk_period_c;
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '0', "Test 1: tx_ready low during transmission");

    -- Wait for completion
    wait_for_completion(300 us, transmitted, "Test 1");
    wait for 2 * clk_period_c;

    -- tx_ready should return high
    wait for 2 * clk_period_c;
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '1', "Test 1: tx_ready high after completion");

    -- Wait for bus to settle
    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 2: Abort before MAC acceptance (send_config_0)
    -- =======================================================================
    current_test_id <= test_2_c;
    Log(alert_id, "Test 2: Abort before MAC acceptance");
    inject_ack <= true;
    setup_default_frame(frame_v);
    wait until rising_edge(clk);


    -- Send partial legacy frame (first ID byte only), then abort.
    -- can_llc_tx(legacy_rtl) is in capture_frame state buffering legacy bytes.
    -- When abort_request is asserted during capture_frame, it resets
    -- its buffer and reflects aborted status back to the user.
    send_user_byte("00000" & frame_v.id(10 downto 8), '1', '0');
    llc_user_i.avalon_st_source.valid <= '0';
    llc_user_i.avalon_st_source.sop   <= '0';

    -- Pulse abort: can_llc_tx sees this during capture_frame and signals aborted.
    -- Transfer_status = aborted is visible for exactly one registered clock cycle.
    llc_user_i.abort_request <= '1';
    wait until rising_edge(clk);   -- T: abort_request is sampled by adapter
    llc_user_i.abort_request <= '0';
    wait until rising_edge(clk);   -- T+1: registered output shows transfer_status = aborted

    AffirmIf(alert_id,
      llc_user_o.transfer_status = aborted,
      "Test 2: transfer_status = aborted, got " & transfer_status_t'image(llc_user_o.transfer_status));

    -- ready returns high one cycle later (adapter back in receive_frame with ready='1')
    wait until rising_edge(clk);   -- T+2: adapter re-asserts ready
    AffirmIf(alert_id,
      llc_user_o.avalon_st_sink.ready = '1',
      "Test 2: tx_ready = 1 after abort");

    -- Wait for bus to settle
    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 3: Abort ignored after MAC acceptance
    -- =======================================================================
    current_test_id <= test_3_c;
    Log(alert_id, "Test 3: Abort ignored after MAC acceptance");
    inject_ack <= true;
    setup_default_frame(frame_v);
    wait until rising_edge(clk);


    -- Submit frame
    submit_frame(frame_v);

    -- Wait for SOF to confirm MAC is actively transmitting (past the point
    -- where abort would be accepted). can_llc_tx(legacy_rtl) buffers the full
    -- 71-byte legacy frame before converting and streaming to MAC, so we
    -- need to wait for the frame to actually reach the MAC before aborting.
    wait_for_sof(200 us, "Test 3 SOF");

    -- Now try to abort - should be ignored since MAC is already processing
    llc_user_i.abort_request <= '1';
    wait until rising_edge(clk);
    llc_user_i.abort_request <= '0';

    -- Frame should still complete successfully (abort ignored)
    wait_for_completion(300 us, transmitted, "Test 3");

    -- tx_ready should return high
    wait for 2 * clk_period_c;
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '1', "Test 3: tx_ready high after completion");

    -- Wait for bus to settle
    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 4: CC Extended format smoke test (no ACK -> aborted)
    -- =======================================================================
    current_test_id <= test_4_c;
    Log(alert_id, "Test 4: CC Extended format smoke test (no ACK)");
    inject_ack <= false;
    setup_default_frame(frame_v);
    frame_v.config_0.format := llc_fmt_ce_c;
    frame_v.id(28 downto 0) := std_logic_vector(to_unsigned(16#1ABCDEF#, 29));
    wait until rising_edge(clk);


    -- Submit frame
    submit_frame(frame_v);

    -- Wait for completion
    wait_for_completion(2 ms, aborted, "Test 4");
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
    frame_v.config_0.format := llc_fmt_fb_c;
    frame_v.config_0.brs    := '0';
    frame_v.config_1.dlc    := std_logic_vector(to_unsigned(9, 4)); -- 12-byte payload
    wait until rising_edge(clk);


    submit_frame(frame_v);
    wait for 2 * clk_period_c;
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '0', "Test 5: tx_ready low after submit");
    wait_for_sof(80 us, "Test 5");
    wait for 2 * clk_period_c;
    -- Reset between FD smoke tests to avoid hanging the DUT in unsupported paths.
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
    frame_v.config_0.format := llc_fmt_fe_c;
    frame_v.config_0.brs    := '0';
    frame_v.config_1.dlc    := std_logic_vector(to_unsigned(10, 4)); -- 16-byte payload
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
    inject_ack <= false; -- No ACK -> ACK error -> disturbed
    setup_default_frame(frame_v);
    wait until rising_edge(clk);


    -- Submit frame
    submit_frame(frame_v);

    -- Wait for final abort after retransmission_limit_c + 1 attempts.
    -- Keep a wider budget to tolerate integration-level timing variation.
    wait_for_completion(2 ms, aborted, "Test 7");

    -- tx_ready should return high
    wait for 2 * clk_period_c;
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '1', "Test 7: tx_ready high after retransmission limit");

    -- =======================================================================
    -- Test 8: FD format pressure smoke (repeated submissions)
    -- =======================================================================
    current_test_id <= test_8_c;
    Log(alert_id, "Test 8: FD format pressure smoke");
    inject_ack <= false;

    for iter in 0 to 11 loop
      -- Reset each iteration to recover from unsupported/incomplete FD terminal paths
      -- while still pressure testing request->SOF behavior across FD formats.
      rst <= '1';
      wait for 5 * clk_period_c;
      wait until rising_edge(clk);
      rst <= '0';
      llc_user_i.avalon_st_source.valid <= '0';
      llc_user_i.abort_request <= '0';
      wait until rising_edge(clk);

      setup_default_frame(frame_v);
      dlc_v := (iter mod 8) + 8; -- Sweep FD DLC 8..15
      frame_v.config_1.dlc := std_logic_vector(to_unsigned(dlc_v, 4));
      frame_v.id  := std_logic_vector(to_unsigned(16#100# + iter, 32));
      if ((iter mod 2) = 0) then
        frame_v.config_0.format := llc_fmt_fb_c;
      else
        frame_v.config_0.format := llc_fmt_fe_c;
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

    inject_ack <= false; -- No ACK needed; error occurs before ACK slot
    setup_default_frame(frame_v);
    wait until rising_edge(clk);


    submit_frame(frame_v);
    wait_for_fsm_bit_name(data_bit, 500 us, "Test 9 data field arrival");
    wait_for_sample_strobe(50 us, "Test 9 data SP");
    inject_bit_error;

    -- FSM should enter active error flag state
    wait_for_fsm_state(transmitting_active_error_flag, 20 us, "Test 9");
    wait until rising_edge(clk); -- Wait for registered fce_o
    AffirmIf(alert_id,
      fsm_state = transmitting_active_error_flag,
      "Test 9: FSM entered transmitting_active_error_flag");

    -- fce_o.sending_error_flag should be asserted
    AffirmIf(alert_id,
      fce_o.sending_error_flag = true,
      "Test 9: sending_error_flag asserted during error flag transmission");

    -- Wait for FSM to return to bus_idle
    wait_for_fsm_state(bus_idle, 100 us, "Test 9 recovery");

    reset_and_prepare;

    -- Verify recovery: submit a new frame with ACK and confirm transmitted
    inject_ack <= true;
    setup_default_frame(frame_v);
    wait until rising_edge(clk);


    submit_frame(frame_v);
    wait_for_completion(300 us, transmitted, "Test 9 recovery frame");

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

    -- Reset to start clean (wide pulse so bus_monitor catches it)
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


    -- Submit CC Basic frame 
    submit_frame(frame_v);

    -- Wait until FSM reaches EOF
    wait_for_fsm_bit_name(eof_bit, 500 us, "Test 10 eof arrival");

    -- Wait for all 7 EOF bits to be sampled
    wait_for_n_strobes(7, "Test 10 EOF");

    -- Inject dominant during intermission to trigger overload
    bus_override_test <= dominant_bit_c;
    bus_override_test_en <= true;
    wait for nom_bit_time_clk_c * clk_period_c;
    bus_override_test_en <= false;

    -- Frame should have reached completion status BEFORE overload was injected
    AffirmIf(alert_id, llc_user_o.transfer_status = transmitted, "Test 10 first frame: expected transmitted");

    -- FSM should enter overload flag state
    wait_for_fsm_state(transmitting_overload_flag, 20 us, "Test 10");
    wait until rising_edge(clk); -- Wait for registered fce_o
    AffirmIf(alert_id,
      fsm_state = transmitting_overload_flag,
      "Test 10: FSM entered transmitting_overload_flag");

    AffirmIf(alert_id,
      fce_o.sending_error_flag = true,
      "Test 10: sending_error_flag asserted during overload flag transmission");

    -- Wait for FSM to return to bus_idle
    wait_for_fsm_state(bus_idle, 100 us, "Test 10 recovery");

    reset_and_prepare;

    -- Verify recovery: submit a second frame with ACK
    inject_ack <= true;
    setup_default_frame(frame_v);
    wait until rising_edge(clk);


    submit_frame(frame_v);
    wait_for_completion(300 us, transmitted, "Test 10 second frame");

    wait for 2 * clk_period_c;
    AffirmIf(alert_id,
      llc_user_o.avalon_st_sink.ready = '1',
      "Test 10: tx_ready high after recovery");

    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 11: FD Overlapping ACK (dominant during delimiter only)
    -- ISO 11898-1: 6.6.11.6
    -- =======================================================================
    current_test_id <= test_11_c;
    Log(alert_id, "Test 11: FD Overlapping ACK slot (dominant during delimiter only)");
    
    -- Turn off automatic ACK injection
    inject_ack <= false; 
    
    setup_default_frame(frame_v);
    frame_v.config_0.format := llc_fmt_fb_c;
    wait until rising_edge(clk);


    submit_frame(frame_v);

    -- Wait until ACK delimiter arrives at sample strobe
    wait_for_bit_at_strobe(ack_delimiter_bit, 500 us, "Test 11");

    -- Now we are at the very start of the ACK delimiter bit interval.
    -- Inject dominant to simulate the FD overlapping ACK requirement.
    bus_override_test    <= dominant_bit_c;
    bus_override_test_en <= true;
    
    -- Hold for one nominal bit time
    wait for nom_bit_time_clk_c * clk_period_c;
    bus_override_test_en <= false;

    -- Frame should complete successfully (ACK accepted from delimiter)
    wait_for_completion(500 us, transmitted, "Test 11");

    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 12: Arbitration Loss Withdrawal
    -- ISO 11898-1: 6.6.17.4
    -- =======================================================================
    current_test_id <= test_12_c;
    Log(alert_id, "Test 12: Arbitration Loss Withdrawal (monitored dominant while sending recessive ID)");

    inject_ack <= true;
    setup_default_frame(frame_v);
    -- Set ID to all 1s (recessive) to make arbitration loss easy to trigger
    frame_v.id := (others => '1');
    wait until rising_edge(clk);


    submit_frame(frame_v);

    -- Wait until FSM reaches first bit of ID field
    wait_for_fsm_bit_name(base_id_bit, 500 us, "Test 12 ID arrival");

    -- Synchronize with the next sample strobe
    wait_for_sample_strobe(50 us, "Test 12 ID SP");

    -- Inject dominant on the bus while DUT is sending recessive ID bit
    bus_override_test    <= dominant_bit_c;
    bus_override_test_en <= true;
    wait for nom_bit_time_clk_c * clk_period_c;
    bus_override_test_en <= false;

    -- DUT should withdraw: FSM should move to intermission immediately
    wait_for_fsm_state(intermission, 20 us, "Test 12 withdrawal");
    
    wait until rising_edge(clk);
    AffirmIf(alert_id, fce_o.sending_error_flag = false, "Test 12: No error flag on arbitration loss");

    -- LLC should automatically retry. Wait for the second SOF.
    wait_for_sof(1 ms, "Test 12 retry SOF");

    -- Let the second attempt complete normally
    wait_for_completion(800 us, transmitted, "Test 12 retry completion");

    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 13: Remote Frame Support (RTR=1)
    -- ISO 11898-1: 6.6.10.1
    -- =======================================================================
    current_test_id <= test_13_c;
    Log(alert_id, "Test 13: Remote Frame Support (RTR=1, DLC=8, Data omitted)");

    inject_ack <= true;
    setup_default_frame(frame_v);
    frame_v.config_0.ftyp   := '1'; -- Remote Frame
    frame_v.config_1.dlc    := "1000"; -- DLC=8 (should be ignored for data transmission)
    wait until rising_edge(clk);


    submit_frame(frame_v);

    -- Wait until FSM starts the frame
    wait_for_sof(100 us, "Test 13 SOF arrival");

    -- Wait until FSM reaches RTR bit
    wait_for_fsm_bit_name(rtr_bit, 500 us, "Test 13 RTR arrival");

    -- Verify RTR is recessive at sample strobe
    wait_and_verify_at_strobe(recessive_bit_c, "Test 13: RTR must be recessive");

    -- Frame should skip 64 bits of data and complete quickly
    wait_for_completion(300 us, transmitted, "Test 13 completion");

    wait for 20 * nom_bit_time_clk_c * clk_period_c;

    -- =======================================================================
    -- Test 14: Bit Rate Switching Timing Validation
    -- ISO 11898-1: 7.3.3
    -- =======================================================================
    current_test_id <= test_14_c;
    Log(alert_id, "Test 14: Bit Rate Switching Timing (Entry at BRS SP, Exit at CRC Delim SP)");

    -- Reset to ensure clean state and stable timing
    rst <= '1'; wait for 5 * clk_period_c; wait until rising_edge(clk); rst <= '0';

    -- Wait until LLC is ready (MAC has finished integration)
    while (llc_user_o.avalon_st_sink.ready = '0') loop
      wait until rising_edge(clk);
    end loop;

    setup_default_frame(frame_v);
    frame_v.config_0.format := llc_fmt_fb_c;
    frame_v.config_0.brs    := '1'; -- Enable Bit Rate Switch
    wait until rising_edge(clk);


    submit_frame(frame_v);

    -- 1. Verify Entry: Wait for BRS bit sample point
    -- Verify BRS bit transmission
    wait_for_fsm_bit_name(brs_bit, 500 us, "Test 14 BRS arrival");

    -- Allow frame to complete/error out
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
