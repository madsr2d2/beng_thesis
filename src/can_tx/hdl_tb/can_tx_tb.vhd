--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Integration testbench for can_tx top-level entity.
--                Tests full transmit path: LLC user request -> bus output.
--                Test scenarios:
--                1. Successful CC Basic transmission (happy path)
--                2. Abort before MAC acceptance (send_config_0 state)
--                3. Abort ignored after MAC acceptance
--                4. CC Extended format smoke test (no ACK)
--                5. FD Basic format smoke test (no ACK)
--                6. FD Extended format smoke test (no ACK)
--                7. Retransmission limit exceeded (7 attempts, no ACK)
--                8. FD format pressure smoke (repeated FD basic/extended submissions)
--                9. (removed - broken bit error test)
--                10. Dominant during intermission triggers overload flag
--                11. FD Basic ACK injection via bus monitor
--                12. Arbitration Loss Withdrawal
--                13. Remote Frame Support (RTR=1)
--                14. Bit Rate Switching Timing Validation
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-31  MRDSA     Converted to company header format
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

library osvvm;
  context osvvm.OsvvmContext;

entity can_tx_tb is
end entity can_tx_tb;

architecture tb of can_tx_tb is

  -- Clock and reset
  constant clk_period_c : time := 10 ns; -- 100 MHz
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- Bit timing constants (matching can_tx defaults)
  constant nom_prescaler_c  : natural := 4;
  constant nom_sync_seg_c   : natural := 1;
  constant nom_prop_seg_c   : natural := 24;
  constant nom_phase_seg1_c : natural := 15;
  constant nom_phase_seg2_c : natural := 10;
  constant nom_bit_time_tq_c : natural := nom_sync_seg_c + nom_prop_seg_c + nom_phase_seg1_c + nom_phase_seg2_c;
  constant nom_bit_time_clk_c : natural := nom_bit_time_tq_c * nom_prescaler_c; -- 200 clocks
  constant nom_sp_tq_c : natural := nom_sync_seg_c + nom_prop_seg_c + nom_phase_seg1_c; -- 40 TQ

  -- Sample point offset in clock cycles from start of bit
  constant c_sp_offset_clk_c : natural := nom_prescaler_c * (nom_sync_seg_c + nom_prop_seg_c + nom_phase_seg1_c);

  -- DUT signals
  signal llc_user_i : t_can_user_llc_tx_if_s2d;
  signal llc_user_o : t_can_user_llc_tx_if_d2s;
  signal fce_i      : t_can_mac_fce_if_s2m;
  signal fce_o      : t_can_mac_fce_if_m2s;
  signal tx_bus_o   : std_logic;
  signal rx_bus_i   : std_logic;

  -- ACK target position (logical bit index) shared between test process and bus monitor
  signal monitor_ack_position : natural := 0;

  -- Bus model control
  signal inject_ack   : boolean := true;
  signal bus_override_monitor    : std_logic := c_recessive;
  signal bus_override_monitor_en : boolean := false;
  signal bus_override_test       : std_logic := c_recessive;
  signal bus_override_test_en    : boolean := false;

  -- Test tracking
  signal test_done : boolean := false;
  signal current_test_id : natural range 0 to 15 := 0;
  constant test_idle_c : natural := 0;
  constant test_1_c    : natural := 1;
  constant test_2_c    : natural := 2;
  constant test_3_c    : natural := 3;
  constant test_4_c    : natural := 4;
  constant test_5_c    : natural := 5;
  constant test_6_c    : natural := 6;
  constant test_7_c    : natural := 7;
  constant test_8_c    : natural := 8;
  constant test_10_c   : natural := 10;
  constant test_11_c   : natural := 11;
  constant test_12_c   : natural := 12;
  constant test_13_c   : natural := 13;
  constant test_14_c   : natural := 14;
  constant test_done_c : natural := 15;

  -- Bitstream capture buffers
  constant max_raw_bits_c : natural := c_max_mac_frame_length * 2;

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
      rx_bus_i       => rx_bus_i
    );

  -- Bus model: loopback with optional ACK injection and test override
  rx_bus_i <= bus_override_test    when bus_override_test_en else
              bus_override_monitor when bus_override_monitor_en else
              tx_bus_o;

  -- FCE: error-active node
  fce_i.error_passive_request <= '0';
  fce_i.error_active_request  <= '1';

  -- =========================================================================
  -- Bus Monitor Process: Handles automatic ACK injection
  --
  -- Counts logical frame bit positions from SOF, tracking dynamic stuff bits.
  -- The ISO 11898-1 stuffing rule: after 5 consecutive same-polarity bits the
  -- transmitter inserts one opposite-polarity stuff bit.  Stuff bits are
  -- transparent to the protocol layer and must NOT be counted in frame_pos.
  --
  -- Algorithm:
  --   - consec counts successive same-polarity non-stuff bits seen on tx_bus_o.
  --   - next_is_stuff is set true after consec reaches 5.
  --   - When next_is_stuff is true, the next bit time is skipped (frame_pos not
  --     incremented, stuff counter restarted from that bit's polarity).
  --   - tx_bus_o is sampled at c_sp_offset_clk_c clocks into each bit time,
  --     with a +2 clock offset to account for the PCS pipeline delay (tx_bus_o
  --     is registered one cycle after valid rises; the prescaler may add another).
  --   - ACK is injected at the START of the ACK bit time so that the override
  --     is already dominant when the PCS sample point fires.  The override is
  --     held for the entire nominal bit time and released at the bit boundary.
  -- =========================================================================
  bus_monitor : process is
    variable clk_count      : natural  := 0;
    variable frame_pos      : natural  := -1;
    variable consec         : natural  := 0;
    variable last_pol       : std_logic := c_recessive;
    variable next_is_stuff  : boolean  := false;
    variable armed          : boolean  := false;
    variable tracking       : boolean  := false;
    variable ack_target     : natural  := 0;
    variable sampled_pol    : std_logic := c_recessive;
    variable prev_tx_bus    : std_logic := c_recessive;
  begin
    wait until rst = '0';
    loop
      wait until rising_edge(clk);

      -- Reset monitor state when rst is asserted
      if (rst = '1') then
        armed         := false;
        tracking      := false;
        frame_pos     := -1;
        consec        := 0;
        next_is_stuff := false;
        bus_override_monitor_en <= false;
        prev_tx_bus   := c_recessive;
        next;
      end if;

      -- Arm the monitor when fce_o.transmitting fires (SOF hasn't appeared yet)
      if (fce_o.transmitting = '1' and not armed and not tracking) then
        armed      := true;
        ack_target := monitor_ack_position;
      end if;

      -- Start bit counting on the actual SOF edge (recessive -> dominant on tx_bus_o)
      if (armed and not tracking and prev_tx_bus = c_recessive and tx_bus_o = c_dominant) then
        report "bus_monitor: SOF edge at t=" & time'image(now) severity note;
        tracking       := true;
        armed          := false;
        frame_pos      := 0;            -- SOF is logical bit 0
        clk_count      := 0;            -- will be incremented below to 1
        consec         := 0;            -- will count SOF as first bit at bit-end
        last_pol       := c_recessive;  -- so SOF (dominant) triggers consec=1
        next_is_stuff  := false;
      end if;

      -- Stop tracking if frame ends abnormally (error flag, arb loss, etc.)
      if (tracking and fce_o.transmitting = '0') then
        tracking               := false;
        frame_pos              := -1;
        bus_override_monitor_en <= false;
      end if;

      if tracking then
        clk_count := clk_count + 1;

        -- At the sample point: capture tx_bus_o for stuff bit counting.
        if (clk_count = c_sp_offset_clk_c) then
          sampled_pol := tx_bus_o;
          report "bus_monitor: SP clk=" & natural'image(clk_count) &
                 " pol=" & std_logic'image(tx_bus_o) &
                 " fpos=" & natural'image(frame_pos) &
                 " consec=" & natural'image(consec) &
                 " stuff=" & boolean'image(next_is_stuff) &
                 " t=" & time'image(now) severity note;
        end if;

        -- At the end of the nominal bit time: update frame position and inject ACK
        if (clk_count = nom_bit_time_clk_c) then
          clk_count               := 0;
          bus_override_monitor_en <= false;

          if next_is_stuff then
            next_is_stuff := false;
            consec        := 1;
            last_pol      := sampled_pol;
          else
            frame_pos := frame_pos + 1;
            if (sampled_pol = last_pol) then
              consec := consec + 1;
              if (consec = 5) then
                next_is_stuff := true;
              end if;
            else
              consec   := 1;
              last_pol := sampled_pol;
            end if;
          end if;

          -- Assert ACK override at the START of the ACK slot bit
          if (inject_ack and frame_pos = ack_target) then
            report "bus_monitor: ACK inject at frame_pos=" & natural'image(frame_pos) &
                   " t=" & time'image(now) severity note;
            bus_override_monitor    <= c_dominant;
            bus_override_monitor_en <= true;
          end if;

          -- Stop tracking once well past the ACK slot
          if (frame_pos > ack_target + 10) then
            tracking  := false;
            frame_pos := -1;
          end if;
        end if;
      end if;

      prev_tx_bus := tx_bus_o;
    end loop;
  end process bus_monitor;

  -- =========================================================================
  -- Main Test Process
  -- =========================================================================
  test_runner : process is

    variable alert_id        : AlertLogIDType;
    variable dlc_v           : natural;
    variable frame_meta_v    : t_llc_metadata;
    variable frame_params_v  : t_frame_params;
    variable bit_position_v  : natural;

    -- Local frame descriptor (flat fields, no nested records)
    variable ide_v  : std_logic := '0';
    variable fdf_v  : std_logic := '0';
    variable ftyp_v : std_logic := '0';
    variable esi_v  : std_logic := '0';
    variable brs_v  : std_logic := '0';
    variable dlc_vec_v : std_logic_vector(3 downto 0) := "0001";
    variable id_v   : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(16#555#, 32));
    variable data_v : std_logic_vector(c_max_data_bytes * 8 - 1 downto 0) := (others => '0');

    -- Helper: build default LLC frame (CC Basic, DLC=1, ID=0x555, data=0xAA)
    procedure setup_default_frame is
    begin
      id_v      := std_logic_vector(to_unsigned(16#555#, 32));
      ide_v     := '0';
      fdf_v     := '0';
      ftyp_v    := '0';
      esi_v     := '0';
      brs_v     := '0';
      dlc_vec_v := "0001";
      data_v    := (others => '0');
      data_v(c_max_data_bytes * 8 - 1 downto c_max_data_bytes * 8 - 8) := x"AA";
    end procedure setup_default_frame;

    procedure send_user_byte (
      value :std_logic_vector(c_byte_width - 1 downto 0);
      sop   : std_logic;
      eop   : std_logic
    ) is
    begin
      llc_user_i.avalon_st_source.data  <= value;
      llc_user_i.avalon_st_source.valid <= '1';
      llc_user_i.avalon_st_source.startofpacket   <= sop;
      llc_user_i.avalon_st_source.endofpacket   <= eop;
      loop
        WaitForClock(clk);
        exit when llc_user_o.avalon_st_sink.ready = '1';
      end loop;
    end procedure send_user_byte;

    -- Helper: stream frame as 71-byte legacy LLC format to can_llc_tx(legacy_rtl).
    procedure submit_frame is

      variable id_29_v           : std_logic_vector(28 downto 0);
      variable is_extended_v     : boolean;
      variable byte0_v           :std_logic_vector(c_byte_width - 1 downto 0);
      variable byte1_v           :std_logic_vector(c_byte_width - 1 downto 0);
      variable byte2_v           :std_logic_vector(c_byte_width - 1 downto 0);
      variable byte3_v           :std_logic_vector(c_byte_width - 1 downto 0);
      variable byte4_v           :std_logic_vector(c_byte_width - 1 downto 0);
      variable byte69_v          :std_logic_vector(c_byte_width - 1 downto 0);
      variable byte70_v          :std_logic_vector(c_byte_width - 1 downto 0);
      variable data_byte_count_v : natural;
      variable data_bit_start_v  : natural;

    begin

      id_29_v       := id_v(28 downto 0);
      is_extended_v := ide_v = '1';

      if is_extended_v then
        byte0_v := "000" & id_29_v(28 downto 24);
        byte1_v := id_29_v(23 downto 16);
        byte2_v := id_29_v(15 downto 8);
        byte3_v := id_29_v(7 downto 0);
      else
        byte0_v := (others => '0');
        byte1_v := (others => '0');
        byte2_v := "00000" & id_29_v(10 downto 8);
        byte3_v := id_29_v(7 downto 0);
      end if;

      byte4_v  := "0" & ide_v & fdf_v & "0" & dlc_vec_v;
      byte69_v := "0000000" & ide_v;
      byte70_v := "00000" & brs_v & esi_v & ftyp_v;

      data_byte_count_v := dlc_to_data_length(
                              to_integer(unsigned(dlc_vec_v)),
                              fdf_v
                            );

      send_user_byte(byte0_v, '1', '0');
      send_user_byte(byte1_v, '0', '0');
      send_user_byte(byte2_v, '0', '0');
      send_user_byte(byte3_v, '0', '0');
      send_user_byte(byte4_v, '0', '0');

      for i in 0 to 63 loop
        if i < data_byte_count_v then
          data_bit_start_v := data_v'left - i * 8;
          send_user_byte(data_v(data_bit_start_v downto data_bit_start_v - 7), '0', '0');
        else
          send_user_byte((others => '0'), '0', '0');
        end if;
      end loop;

      send_user_byte(byte69_v, '0', '0');
      send_user_byte(byte70_v, '0', '1');

      llc_user_i.avalon_st_source.valid          <= '0';
      llc_user_i.avalon_st_source.startofpacket  <= '0';
      llc_user_i.avalon_st_source.endofpacket    <= '0';

    end procedure submit_frame;

    -- Helper: compute and publish the ACK slot logical bit position for the
    -- current frame variables (ide_v, fdf_v, dlc_vec_v, ftyp_v, brs_v, esi_v).
    -- Must be called before submit_frame so that the bus monitor reads the
    -- correct value when fce_o.transmitting fires.
    procedure update_ack_position is
      variable meta_v   : t_llc_metadata;
      variable params_v : t_frame_params;
    begin
      meta_v.ide  := ide_v;
      meta_v.fdf  := fdf_v;
      meta_v.dlc  := dlc_vec_v;
      meta_v.ftyp := ftyp_v;
      meta_v.brs  := brs_v;
      meta_v.esi  := esi_v;
      params_v              := get_frame_params(meta_v);
      monitor_ack_position  <= params_v.crc_delimiter + c_ack_slot_offset;
    end procedure update_ack_position;

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
        WaitForClock(clk);
        wait until falling_edge(clk);
        if (llc_user_o.transfer_status /= c_ongoing) then
          AffirmIf(alert_id,
            llc_user_o.transfer_status = exp_status,
            test_name & ": expected status, got " & to_hstring(llc_user_o.transfer_status));
          return;
        end if;
      end loop;
      Alert(alert_id, test_name & ": TIMEOUT after " & time'image(timeout));
    end procedure wait_for_completion;

    -- Helper: wait until fce_o.transmitting pulses (frame SOF) with timeout
    procedure wait_for_sof (
      timeout   : time;
      test_name : string
    ) is
      variable start_time : time;
    begin
      start_time := now;
      while (now - start_time < timeout) loop
        WaitForClock(clk);
        wait until falling_edge(clk);
        if (fce_o.transmitting = '1') then
          return;
        end if;
      end loop;
      Alert(alert_id, test_name & ": SOF TIMEOUT after " & time'image(timeout));
    end procedure wait_for_sof;

    -- Helper: wait until error/overload flag begins (sending_error_overload_flag rises)
    procedure wait_for_error_flag (
      timeout   : time;
      test_name : string
    ) is
      variable start_time : time;
    begin
      start_time := now;
      while (now - start_time < timeout) loop
        WaitForClock(clk);
        wait until falling_edge(clk);
        if (fce_o.sending_error_overload_flag = '1') then
          return;
        end if;
      end loop;
      Alert(alert_id, test_name & ": error/overload flag TIMEOUT after " & time'image(timeout));
    end procedure wait_for_error_flag;

    -- Helper: wait until FSM enters intermission after arbitration loss.
    -- The LLC hides c_lost_arb from the user (auto-retries), so detect
    -- intermission by watching fce_o.transmitting fall after SOF was seen.
    procedure wait_for_intermission (
      timeout   : time;
      test_name : string
    ) is
      variable start_time : time;
      variable saw_tx     : boolean := false;
    begin
      start_time := now;
      while (now - start_time < timeout) loop
        WaitForClock(clk);
        wait until falling_edge(clk);
        if (fce_o.transmitting = '1') then
          saw_tx := true;
        end if;
        if (saw_tx and fce_o.transmitting = '0') then
          return;
        end if;
      end loop;
      Alert(alert_id, test_name & ": intermission TIMEOUT after " & time'image(timeout));
    end procedure wait_for_intermission;

    -- Helper: inject bit error by overriding bus for one bit time
    procedure inject_bit_error is
    begin
      if (tx_bus_o = c_dominant) then
        bus_override_test <= c_recessive;
      else
        bus_override_test <= c_dominant;
      end if;
      bus_override_test_en <= true;
      WaitForClock(clk, nom_bit_time_clk_c);
      bus_override_test_en <= false;
    end procedure inject_bit_error;

    -- Helper: reset FSM and wait for MAC ready
    procedure reset_and_prepare is
    begin
      rst <= '1';
      WaitForClock(clk, 2 * nom_bit_time_clk_c);
      rst <= '0';
      llc_user_i.avalon_st_source.valid <= '0';
      llc_user_i.abort_request <= '0';
      WaitForClock(clk, 20 * nom_bit_time_clk_c);
    end procedure reset_and_prepare;

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
    WaitForClock(clk, 5);
    rst <= '0';
    WaitForClock(clk);

    -- =======================================================================
    -- Test 1: Successful CC Basic transmission (happy path)
    -- =======================================================================
    current_test_id <= test_1_c;
    Log(alert_id, "Test 1: Successful CC Basic transmission");
    inject_ack <= true;

    setup_default_frame;
    update_ack_position;
    WaitForClock(clk);
    wait until falling_edge(clk);

    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '1', "Test 1: tx_ready high before submit");

    submit_frame;

    WaitForClock(clk);
    wait until falling_edge(clk);
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '0', "Test 1: tx_ready low during transmission");

    wait_for_completion(300 us, c_transmitted, "Test 1");
    WaitForClock(clk);
    wait until falling_edge(clk);

    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '1', "Test 1: tx_ready high after completion");

    WaitForClock(clk, 20 * nom_bit_time_clk_c);

    -- =======================================================================
    -- Test 2: Abort before MAC acceptance (send_config_0)
    -- =======================================================================
    current_test_id <= test_2_c;
    Log(alert_id, "Test 2: Abort before MAC acceptance");
    inject_ack <= true;
    setup_default_frame;
    WaitForClock(clk);

    send_user_byte("00000" & id_v(10 downto 8), '1', '0');
    llc_user_i.avalon_st_source.valid <= '0';
    llc_user_i.avalon_st_source.startofpacket   <= '0';

    llc_user_i.abort_request <= '1';
    WaitForClock(clk);
    llc_user_i.abort_request <= '0';
    WaitForClock(clk);
    wait until falling_edge(clk);

    AffirmIf(alert_id,
      llc_user_o.transfer_status = c_aborted,
      "Test 2: transfer_status = aborted, got " & to_hstring(llc_user_o.transfer_status));

    WaitForClock(clk);
    wait until falling_edge(clk);
    AffirmIf(alert_id,
      llc_user_o.avalon_st_sink.ready = '1',
      "Test 2: tx_ready = 1 after abort");

    WaitForClock(clk, 20 * nom_bit_time_clk_c);

    -- =======================================================================
    -- Test 3: Abort ignored after MAC acceptance
    -- =======================================================================
    current_test_id <= test_3_c;
    Log(alert_id, "Test 3: Abort ignored after MAC acceptance");
    inject_ack <= true;
    setup_default_frame;
    update_ack_position;
    WaitForClock(clk);

    submit_frame;

    wait_for_sof(200 us, "Test 3 SOF");

    llc_user_i.abort_request <= '1';
    WaitForClock(clk);
    llc_user_i.abort_request <= '0';

    wait_for_completion(300 us, c_transmitted, "Test 3");

    WaitForClock(clk);
    wait until falling_edge(clk);
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '1', "Test 3: tx_ready high after completion");

    WaitForClock(clk, 20 * nom_bit_time_clk_c);

    -- =======================================================================
    -- Test 4: CC Extended format smoke test (no ACK -> aborted)
    -- =======================================================================
    current_test_id <= test_4_c;
    Log(alert_id, "Test 4: CC Extended format smoke test (no ACK)");
    inject_ack <= false;
    setup_default_frame;
    ide_v := '1';
    fdf_v := '0';
    id_v(28 downto 0) := std_logic_vector(to_unsigned(16#1ABCDEF#, 29));
    WaitForClock(clk);

    submit_frame;

    wait_for_completion(2 ms, c_aborted, "Test 4");
    WaitForClock(clk);
    wait until falling_edge(clk);
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '1', "Test 4: tx_ready high after completion");
    WaitForClock(clk, 20 * nom_bit_time_clk_c);

    -- =======================================================================
    -- Test 5: FD Basic format smoke test (no ACK -> aborted)
    -- =======================================================================
    current_test_id <= test_5_c;
    Log(alert_id, "Test 5: FD Basic format smoke test (no ACK)");
    inject_ack <= false;
    setup_default_frame;
    ide_v := '0';
    fdf_v := '1';
    brs_v    := '0';
    dlc_vec_v    := std_logic_vector(to_unsigned(9, 4));
    WaitForClock(clk);

    submit_frame;
    WaitForClock(clk);
    wait until falling_edge(clk);
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '0', "Test 5: tx_ready low after submit");
    wait_for_sof(80 us, "Test 5");
    WaitForClock(clk, 2);
    rst <= '1';
    WaitForClock(clk, 5);
    rst <= '0';
    llc_user_i.avalon_st_source.valid <= '0';
    llc_user_i.abort_request <= '0';
    WaitForClock(clk);
    WaitForClock(clk, 20 * nom_bit_time_clk_c);

    -- =======================================================================
    -- Test 6: FD Extended format smoke test (no ACK -> aborted)
    -- =======================================================================
    current_test_id <= test_6_c;
    Log(alert_id, "Test 6: FD Extended format smoke test (no ACK)");
    inject_ack <= false;
    setup_default_frame;
    ide_v := '1';
    fdf_v := '1';
    brs_v    := '0';
    dlc_vec_v    := std_logic_vector(to_unsigned(10, 4));
    id_v(28 downto 0) := std_logic_vector(to_unsigned(16#1234567#, 29));
    WaitForClock(clk);

    submit_frame;
    WaitForClock(clk);
    wait until falling_edge(clk);
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '0', "Test 6: tx_ready low after submit");
    wait_for_sof(120 us, "Test 6");
    WaitForClock(clk, 2);
    rst <= '1';
    WaitForClock(clk, 5);
    rst <= '0';
    llc_user_i.avalon_st_source.valid <= '0';
    llc_user_i.abort_request <= '0';
    WaitForClock(clk);
    WaitForClock(clk, 20 * nom_bit_time_clk_c);

    -- =======================================================================
    -- Test 7: Retransmission limit exceeded
    -- =======================================================================
    current_test_id <= test_7_c;
    Log(alert_id, "Test 7: Retransmission limit exceeded");
    inject_ack <= false;
    setup_default_frame;
    WaitForClock(clk);

    submit_frame;

    wait_for_completion(2 ms, c_aborted, "Test 7");

    WaitForClock(clk);
    wait until falling_edge(clk);
    AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '1', "Test 7: tx_ready high after retransmission limit");

    -- =======================================================================
    -- Test 8: FD format pressure smoke (repeated submissions)
    -- =======================================================================
    current_test_id <= test_8_c;
    Log(alert_id, "Test 8: FD format pressure smoke");
    inject_ack <= false;

    for iter in 0 to 11 loop
      rst <= '1';
      WaitForClock(clk, 5);
      rst <= '0';
      llc_user_i.avalon_st_source.valid <= '0';
      llc_user_i.abort_request <= '0';
      WaitForClock(clk);

      setup_default_frame;
      dlc_v := (iter mod 8) + 8;
      dlc_vec_v := std_logic_vector(to_unsigned(dlc_v, 4));
      id_v  := std_logic_vector(to_unsigned(16#100# + iter, 32));
      if ((iter mod 2) = 0) then
        ide_v := '0';
        fdf_v := '1';
      else
        ide_v := '1';
        fdf_v := '1';
      end if;

      WaitForClock(clk);
      WaitForClock(clk);

      submit_frame;
      WaitForClock(clk);
      wait until falling_edge(clk);
      AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '0', "Test 8: tx_ready low after submit");
      wait_for_sof(140 us, "Test 8");
      WaitForClock(clk, 10);
    end loop;

    -- =======================================================================
    -- Test 10: Dominant during intermission triggers overload flag
    -- =======================================================================
    current_test_id <= test_10_c;
    Log(alert_id, "Test 10: Dominant during intermission triggers overload flag");

    rst <= '1';
    WaitForClock(clk, 2 * nom_bit_time_clk_c);
    rst <= '0';
    llc_user_i.avalon_st_source.valid <= '0';
    llc_user_i.abort_request <= '0';
    WaitForClock(clk);
    WaitForClock(clk, 20 * nom_bit_time_clk_c);

    inject_ack <= true;
    setup_default_frame;
    update_ack_position;
    WaitForClock(clk);

    submit_frame;

    -- Wait for the first frame to complete successfully, then inject dominant
    -- during intermission to trigger an overload flag.
    wait_for_completion(300 us, c_transmitted, "Test 10 first frame");

    -- Inject dominant into the intermission window
    bus_override_test <= c_dominant;
    bus_override_test_en <= true;
    WaitForClock(clk, nom_bit_time_clk_c);
    bus_override_test_en <= false;

    wait_for_error_flag(20 us, "Test 10");
    wait until falling_edge(clk);
    AffirmIf(alert_id,
      fce_o.sending_error_overload_flag = '1',
      "Test 10: sending_error_overload_flag asserted during overload flag transmission");

    -- Wait enough time for overload flag + delimiter to complete, then hard reset.
    WaitForClock(clk, 20 * nom_bit_time_clk_c);

    reset_and_prepare;

    inject_ack <= true;
    setup_default_frame;
    update_ack_position;
    WaitForClock(clk);

    submit_frame;
    wait_for_completion(300 us, c_transmitted, "Test 10 second frame");

    WaitForClock(clk);
    wait until falling_edge(clk);
    AffirmIf(alert_id,
      llc_user_o.avalon_st_sink.ready = '1',
      "Test 10: tx_ready high after recovery");

    WaitForClock(clk, 20 * nom_bit_time_clk_c);

    -- =======================================================================
    -- Test 11: FD Basic ACK injection via bus monitor
    -- =======================================================================
    current_test_id <= test_11_c;
    Log(alert_id, "Test 11: FD Basic ACK injection via bus monitor");

    inject_ack <= true;

    setup_default_frame;
    ide_v := '0';
    fdf_v := '1';
    update_ack_position;
    WaitForClock(clk);

    submit_frame;

    wait_for_completion(500 us, c_transmitted, "Test 11");

    WaitForClock(clk, 20 * nom_bit_time_clk_c);

    -- =======================================================================
    -- Test 12: Arbitration Loss Withdrawal
    -- =======================================================================
    current_test_id <= test_12_c;
    Log(alert_id, "Test 12: Arbitration Loss Withdrawal (monitored dominant while sending recessive ID)");

    inject_ack <= true;
    setup_default_frame;
    id_v := (others => '1');
    update_ack_position;
    WaitForClock(clk);

    submit_frame;

    -- Wait until SOF fires, then hold for one ID bit time before we are at
    -- the first base-ID bit (bit position 1 in the frame).  Then inject a
    -- dominant to simulate arbitration loss (our ID is all-recessive '1's).
    wait_for_sof(80 us, "Test 12 SOF");
    WaitForClock(clk, nom_bit_time_clk_c);

    bus_override_test    <= c_dominant;
    bus_override_test_en <= true;
    WaitForClock(clk, nom_bit_time_clk_c);
    bus_override_test_en <= false;

    -- After arb loss the FSM enters intermission (3 bit times) then retries.
    -- Wait for intermission to pass, then verify no error flag was raised.
    WaitForClock(clk, 5 * nom_bit_time_clk_c);
    wait until falling_edge(clk);
    AffirmIf(alert_id, fce_o.sending_error_overload_flag = '0', "Test 12: No error flag on arbitration loss");

    -- LLC auto-retries after arb loss; wait for the retransmitted frame to complete.
    wait_for_completion(1 ms, c_transmitted, "Test 12 retry completion");

    WaitForClock(clk, 20 * nom_bit_time_clk_c);

    -- =======================================================================
    -- Test 13: Remote Frame Support (RTR=1)
    -- =======================================================================
    current_test_id <= test_13_c;
    Log(alert_id, "Test 13: Remote Frame Support (RTR=1, DLC=8, Data omitted)");

    inject_ack <= true;
    setup_default_frame;
    ftyp_v   := '1';
    dlc_vec_v    := "1000";
    update_ack_position;
    WaitForClock(clk);

    submit_frame;

    -- RTR is bit position 12 in a CC Basic frame (SOF=0, 11-bit ID=1-11, RTR=12).
    -- Wait until SOF fires, advance 12 nominal bit times, then sample at the
    -- sample point within that bit (c_sp_offset_clk_c clocks into the bit).
    wait_for_sof(100 us, "Test 13 SOF arrival");
    WaitForClock(clk, 12 * nom_bit_time_clk_c + c_sp_offset_clk_c);
    wait until falling_edge(clk);
    AffirmIf(alert_id, tx_bus_o = c_recessive, "Test 13: RTR must be recessive");

    wait_for_completion(300 us, c_transmitted, "Test 13 completion");

    WaitForClock(clk, 20 * nom_bit_time_clk_c);

    -- =======================================================================
    -- Test 14: Bit Rate Switching Timing Validation
    -- =======================================================================
    current_test_id <= test_14_c;
    Log(alert_id, "Test 14: Bit Rate Switching Timing (Entry at BRS SP, Exit at CRC Delim SP)");

    rst <= '1'; WaitForClock(clk, 5); rst <= '0';

    while (llc_user_o.avalon_st_sink.ready = '0') loop
      WaitForClock(clk);
    end loop;

    setup_default_frame;
    ide_v := '0';
    fdf_v := '1';
    brs_v    := '1';
    WaitForClock(clk);

    submit_frame;

    -- BRS is bit position 14 in a FD Basic frame (SOF=0, ID=1-11, RRS=12, IDE=13, BRS=14).
    -- Wait for SOF to fire then advance 14 bit times to land in the BRS slot.
    wait_for_sof(80 us, "Test 14 SOF");
    WaitForClock(clk, 14 * nom_bit_time_clk_c);

    WaitForClock(clk, 10000);

    WaitForClock(clk, 20 * nom_bit_time_clk_c);

    -- =======================================================================
    -- Done
    -- =======================================================================
    current_test_id <= test_done_c;
    WaitForClock(clk, 10);
    ReportAlerts;
    test_done <= true;
    wait;

  end process test_runner;

end architecture tb;
