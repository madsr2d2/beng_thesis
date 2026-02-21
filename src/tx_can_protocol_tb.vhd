--------------------------------------------------------------------------------
-- Title      : CAN TX Protocol Testbench
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : tx_can_protocol_tb.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Protocol-focused TX integration testbench.
--              Keeps handshake smoke checks in tx_can_tb and concentrates here
--              on logical frame correctness on the observed bus stream.
--
-- Scope in this bench:
--   - CC basic and CC extended end-to-end protocol checks
--   - De-stuffing and logical stream reconstruction
--   - Frame-structure checks: SOF, CRC delimiter, ACK delimiter, EOF, length
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_protocol_pkg.all;
  use work.can_types_pkg.all;

library osvvm;
  use osvvm.AlertLogPkg.all;

entity tx_can_protocol_tb is
end entity tx_can_protocol_tb;

architecture tb of tx_can_protocol_tb is

  ------------------------------------------------------------------------------
  -- Clock/reset
  ------------------------------------------------------------------------------
  constant clk_period_c : time := 10 ns;
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal test_done : boolean := false;

  ------------------------------------------------------------------------------
  -- Timing constants (match tx_can defaults)
  ------------------------------------------------------------------------------
  constant nom_prescaler_c  : integer := 2;
  constant nom_sync_seg_c   : integer := 1;
  constant nom_prop_seg_c   : integer := 8;
  constant nom_phase_seg1_c : integer := 8;
  constant nom_phase_seg2_c : integer := 8;
  constant nom_bit_time_tq_c : integer := nom_sync_seg_c + nom_prop_seg_c + nom_phase_seg1_c + nom_phase_seg2_c;
  constant nom_bit_time_clk_c : integer := nom_bit_time_tq_c * nom_prescaler_c;

  ------------------------------------------------------------------------------
  -- DUT interfaces
  ------------------------------------------------------------------------------
  signal llc_user_i : llc_user_to_llc_if_t;
  signal llc_user_o : llc_to_llc_user_if_t;
  signal fce_i      : fce_to_mac_if_t;
  signal fce_o      : mac_to_fce_if_t;
  signal tx_bus_o   : std_logic;
  signal rx_bus_i   : std_logic;

  ------------------------------------------------------------------------------
  -- Bus/ACK model control
  ------------------------------------------------------------------------------
  signal inject_ack      : boolean := true;
  signal bus_override    : std_logic := recessive_bit_c;
  signal bus_override_en : boolean := false;

  ------------------------------------------------------------------------------
  -- Protocol checker control
  ------------------------------------------------------------------------------
  signal checker_enable         : boolean := false;
  signal checker_request_id     : integer := 0;
  signal checker_done_id        : integer := 0;
  signal checker_expected_frame : llc_frame_t;
  signal checker_expected_params : frame_params_t := frame_params_reset_c;

  constant max_raw_bits_c : integer := max_mac_frame_length_c * 2;
  type raw_bits_t is array (0 to max_raw_bits_c - 1) of std_logic;
  type logical_bits_t is array (0 to max_mac_frame_length_c - 1) of std_logic;

begin

  clk <= not clk after clk_period_c / 2 when not test_done;

  dut : entity work.tx_can
    generic map (
      nom_prescaler  => nom_prescaler_c,
      nom_sync_seg   => nom_sync_seg_c,
      nom_prop_seg   => nom_prop_seg_c,
      nom_phase_seg1 => nom_phase_seg1_c,
      nom_phase_seg2 => nom_phase_seg2_c,
      data_prescaler => 1,
      data_sync_seg  => 1,
      data_prop_seg  => 4,
      data_phase_seg1 => 4,
      data_phase_seg2 => 4,
      ssp_offset_cfg => 4
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

  -- Loopback + optional ACK-slot override.
  rx_bus_i <= bus_override when bus_override_en else tx_bus_o;
  fce_i.error_passive <= false;

  ------------------------------------------------------------------------------
  -- Protocol checker
  ------------------------------------------------------------------------------
  protocol_checker : process is
    variable alert_id : AlertLogIDType;
    variable params_v : frame_params_t;
    variable raw_bits_v : raw_bits_t;
    variable logical_bits_v : logical_bits_t;
    variable raw_count_v : integer;
    variable logical_count_v : integer;
    variable frame_position_v : integer;
    variable consecutive_count_v : integer;
    variable last_polarity_v : std_logic;
    variable sampled_bit_v : std_logic;
    variable is_stuff_bit_v : boolean;
    variable ack_inject_hold_bits_v : integer range 0 to 1;
    variable req_id_v : integer;
  begin
    alert_id := GetAlertLogID("tx_can_protocol_tb/checker");
    wait until rst = '0';

    loop
      wait until tx_bus_o = dominant_bit_c and tx_bus_o'event;

      if (not checker_enable) then
        next;
      end if;

      req_id_v := checker_request_id;
      params_v := checker_expected_params;
      raw_count_v := 1;
      logical_count_v := 1;
      frame_position_v := 0;
      consecutive_count_v := 1;
      last_polarity_v := dominant_bit_c;
      raw_bits_v(0) := dominant_bit_c;
      logical_bits_v(0) := dominant_bit_c;
      ack_inject_hold_bits_v := 0;
      bus_override_en <= false;

      for bit_idx in 1 to 260 loop
        if (raw_count_v >= max_raw_bits_c) then
          exit;
        end if;

        if (ack_inject_hold_bits_v > 0) then
          bus_override_en <= true;
          bus_override <= dominant_bit_c;
        else
          bus_override_en <= false;
        end if;

        wait for nom_bit_time_clk_c * clk_period_c;

        sampled_bit_v := tx_bus_o;
        is_stuff_bit_v := false;
        raw_bits_v(raw_count_v) := sampled_bit_v;
        raw_count_v := raw_count_v + 1;

        -- Dynamic stuffing applies only up to the CRC sequence (excluding
        -- CRC delimiter) and only when opposite-polarity stuff bit is seen.
        if (frame_position_v < params_v.crc_stop - 1 and
            consecutive_count_v >= 5 and
            sampled_bit_v /= last_polarity_v) then
          is_stuff_bit_v := true;
          consecutive_count_v := 1;
          last_polarity_v := sampled_bit_v;
        else
          logical_bits_v(logical_count_v) := sampled_bit_v;
          logical_count_v := logical_count_v + 1;
          frame_position_v := frame_position_v + 1;

          if (sampled_bit_v = last_polarity_v) then
            consecutive_count_v := consecutive_count_v + 1;
          else
            consecutive_count_v := 1;
            last_polarity_v := sampled_bit_v;
          end if;
        end if;

        if (ack_inject_hold_bits_v > 0) then
          bus_override_en <= false;
          ack_inject_hold_bits_v := ack_inject_hold_bits_v - 1;
        end if;

        if (not is_stuff_bit_v and inject_ack and ack_inject_hold_bits_v = 0 and
            frame_position_v = params_v.ack_slot) then
          ack_inject_hold_bits_v := 1;
        end if;

        if (frame_position_v >= params_v.eof_stop - 1) then
          exit;
        end if;
      end loop;

      -- Basic logical frame structure checks.
      AffirmIf(alert_id, logical_count_v = params_v.eof_stop,
               "Logical frame length check, expected " & integer'image(params_v.eof_stop) &
               " got " & integer'image(logical_count_v));
      AffirmIf(alert_id, logical_bits_v(sof_c) = dominant_bit_c, "SOF must be dominant");
      AffirmIf(alert_id, logical_bits_v(params_v.ack_delimiter) = recessive_bit_c, "ACK delimiter must be recessive");
      for p in params_v.eof_start to params_v.eof_stop - 1 loop
        AffirmIf(alert_id, logical_bits_v(p) = recessive_bit_c,
                 "EOF bit must be recessive at pos " & integer'image(p));
      end loop;

      checker_done_id <= req_id_v;
    end loop;
  end process protocol_checker;

  ------------------------------------------------------------------------------
  -- Test runner
  ------------------------------------------------------------------------------
  test_runner : process is
    variable alert_id : AlertLogIDType;
    variable frame_v : llc_frame_t;
    variable config_0_v : byte_t;
    variable config_1_v : byte_t;

    procedure wait_clocks (
      n : positive
    ) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
    end procedure wait_clocks;

    procedure set_frame_inputs is
    begin
      llc_user_i.abort_request <= '0';
      llc_user_i.avalon_st_source.data  <= (others => '0');
      llc_user_i.avalon_st_source.valid <= '0';
      llc_user_i.avalon_st_source.sop   <= '0';
      llc_user_i.avalon_st_source.eop   <= '0';
    end procedure set_frame_inputs;

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

    procedure submit_frame (
      frame : llc_frame_t
    ) is
      variable data_byte_count_v : integer;
      variable data_bit_start_v  : integer;
      variable id_stream_v       : std_logic_vector(31 downto 0);
      variable id3_v             : byte_t;
      variable id2_v             : byte_t;
      variable id1_v             : byte_t;
      variable id0_v             : byte_t;
    begin
      case frame.format is
        when cc_basic =>
          config_0_v := llc_frame_format_cb_encoding_c & frame.ftyp & frame.esi & frame.brs & "00";
        when cc_extended =>
          config_0_v := llc_frame_format_ce_encoding_c & frame.ftyp & frame.esi & frame.brs & "00";
        when fd_basic =>
          config_0_v := llc_frame_format_fb_encoding_c & frame.ftyp & frame.esi & frame.brs & "00";
        when fd_extended =>
          config_0_v := llc_frame_format_fe_encoding_c & frame.ftyp & frame.esi & frame.brs & "00";
        when others =>
          config_0_v := (others => '0');
      end case;
      config_1_v := frame.dlc & "0000";
      data_byte_count_v := dlc_to_data_length(
                             dlc_t(to_integer(unsigned(frame.dlc))),
                             frame.format
                           );
      id_stream_v := pack_llc_id_bytes(frame.id, frame.format);
      id3_v := id_stream_v(31 downto 24);
      id2_v := id_stream_v(23 downto 16);
      id1_v := id_stream_v(15 downto 8);
      id0_v := id_stream_v(7 downto 0);

      send_user_byte(config_0_v, '1', '0');
      send_user_byte(config_1_v, '0', '0');
      send_user_byte(id3_v, '0', '0');
      send_user_byte(id2_v, '0', '0');
      send_user_byte(id1_v, '0', '0');
      if (data_byte_count_v = 0) then
        send_user_byte(id0_v, '0', '1');
      else
        send_user_byte(id0_v, '0', '0');
        for i in 0 to data_byte_count_v - 1 loop
          data_bit_start_v := frame.data'left - i * 8;
          if (i = data_byte_count_v - 1) then
            send_user_byte(frame.data(data_bit_start_v downto data_bit_start_v - 7), '0', '1');
          else
            send_user_byte(frame.data(data_bit_start_v downto data_bit_start_v - 7), '0', '0');
          end if;
        end loop;
      end if;

      llc_user_i.avalon_st_source.valid <= '0';
      llc_user_i.avalon_st_source.sop   <= '0';
      llc_user_i.avalon_st_source.eop   <= '0';
    end procedure submit_frame;

    procedure wait_for_transfer_status (
      exp_status : transfer_status_t;
      timeout    : time;
      constant test_name : string
    ) is
      variable t0 : time := now;
    begin
      while (now - t0 < timeout) loop
        wait until rising_edge(clk);
        exit when llc_user_o.transfer_status = exp_status;
      end loop;
      AffirmIf(alert_id, llc_user_o.transfer_status = exp_status,
               test_name & ": expected status " & transfer_status_t'image(exp_status) &
               " got " & transfer_status_t'image(llc_user_o.transfer_status));
    end procedure wait_for_transfer_status;

    procedure wait_for_checker_done (
      req_id : integer;
      timeout : time;
      constant test_name : string
    ) is
      variable t0 : time := now;
      variable done_v : boolean := false;
    begin
      while (now - t0 < timeout) loop
        wait until rising_edge(clk);
        if (checker_done_id = req_id) then
          done_v := true;
          exit;
        end if;
      end loop;
      AlertIf(not done_v, test_name & ": checker timeout");
    end procedure wait_for_checker_done;

    procedure run_classic_protocol_test (
      constant test_name : string;
      constant frame     : llc_frame_t
    ) is
      variable req_id_v : integer;
    begin
      Log(alert_id, test_name);

      set_frame_inputs;
      inject_ack <= true;
      checker_enable <= false;
      req_id_v := checker_request_id + 1;
      checker_request_id <= req_id_v;

      case frame.format is
        when cc_basic =>
          config_0_v := llc_frame_format_cb_encoding_c & frame.ftyp & frame.esi & frame.brs & "00";
        when cc_extended =>
          config_0_v := llc_frame_format_ce_encoding_c & frame.ftyp & frame.esi & frame.brs & "00";
        when others =>
          config_0_v := (others => '0');
      end case;
      config_1_v := frame.dlc & "0000";

      checker_expected_frame <= frame;
      checker_expected_params <= calculate_frame_params(config_0_v, config_1_v);

      wait until rising_edge(clk);
      checker_enable <= true;
      submit_frame(frame);
      wait_clocks(2);
      AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '0', test_name & ": tx_ready should drop after submit");
      wait_for_transfer_status(transmitted, 220 us, test_name);
      wait_for_checker_done(req_id_v, 220 us, test_name);

      checker_enable <= false;
      wait_clocks(2);
      AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '1', test_name & ": tx_ready should return high");
      wait_clocks(20);
    end procedure run_classic_protocol_test;

  begin
    alert_id := GetAlertLogID("tx_can_protocol_tb");
    SetLogEnable(INFO, true);
    SetLogEnable(PASSED, true);

    llc_user_i.avalon_st_source.data  <= (others => '0');
    llc_user_i.avalon_st_source.valid <= '0';
    llc_user_i.avalon_st_source.sop   <= '0';
    llc_user_i.avalon_st_source.eop   <= '0';
    llc_user_i.abort_request <= '0';

    rst <= '1';
    wait_clocks(5);
    rst <= '0';
    wait_clocks(2);

    -- Test 1: CC basic data frame (DLC=1)
    frame_v.id     := (others => '0');
    frame_v.id(10 downto 0) := std_logic_vector(to_unsigned(16#555#, 11));
    frame_v.format := cc_basic;
    frame_v.ftyp   := '0';
    frame_v.brs    := '0';
    frame_v.esi    := '0';
    frame_v.dlc    := std_logic_vector(to_unsigned(1, 4));
    frame_v.data   := (others => '0');
    frame_v.data(max_data_bytes_c * byte_width_c - 1 downto max_data_bytes_c * byte_width_c - 8) := x"A5";
    run_classic_protocol_test("Test 1: CC basic data frame protocol check", frame_v);

    -- Test 2: CC extended data frame (DLC=2)
    frame_v.id     := std_logic_vector(to_unsigned(16#1ABCDE1#, 29));
    frame_v.format := cc_extended;
    frame_v.ftyp   := '0';
    frame_v.brs    := '0';
    frame_v.esi    := '0';
    frame_v.dlc    := std_logic_vector(to_unsigned(2, 4));
    frame_v.data   := (others => '0');
    frame_v.data(max_data_bytes_c * byte_width_c - 1 downto max_data_bytes_c * byte_width_c - 8) := x"12";
    frame_v.data(max_data_bytes_c * byte_width_c - 9 downto max_data_bytes_c * byte_width_c - 16) := x"34";
    run_classic_protocol_test("Test 2: CC extended data frame protocol check", frame_v);

    Log(alert_id, "All tx_can protocol tests completed", PASSED);
    ReportAlerts;
    test_done <= true;
    wait;
  end process test_runner;

end architecture tb;
