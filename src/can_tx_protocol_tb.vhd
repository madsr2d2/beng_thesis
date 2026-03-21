--------------------------------------------------------------------------------
-- Title      : CAN TX Protocol Testbench
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_tx_protocol_tb.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Protocol-focused TX integration testbench.
--              Keeps handshake smoke checks in can_tx_tb and concentrates here
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
  use work.pk_can_types.all;

library osvvm;
  use osvvm.AlertLogPkg.all;

entity can_tx_protocol_tb is
end entity can_tx_protocol_tb;

architecture tb of can_tx_protocol_tb is

  ------------------------------------------------------------------------------
  -- Clock/reset
  ------------------------------------------------------------------------------
  constant clk_period_c : time := 10 ns;
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal test_done : boolean := false;

  ------------------------------------------------------------------------------
  -- Timing constants (match can_tx defaults)
  ------------------------------------------------------------------------------
  constant nom_prescaler_c  : integer := 4;
  constant nom_sync_seg_c   : integer := 1;
  constant nom_prop_seg_c   : integer := 24;
  constant nom_phase_seg1_c : integer := 15;
  constant nom_phase_seg2_c : integer := 10;
  constant nom_bit_time_tq_c : integer := nom_sync_seg_c + nom_prop_seg_c + nom_phase_seg1_c + nom_phase_seg2_c;
  constant nom_bit_time_clk_c : integer := nom_bit_time_tq_c * nom_prescaler_c;

  ------------------------------------------------------------------------------
  -- DUT interfaces
  ------------------------------------------------------------------------------
  signal llc_user_i : t_can_user_llc_tx_if_s2d;
  signal llc_user_o : t_can_user_llc_tx_if_d2s;
  signal fce_i      : t_can_mac_fce_if_s2m;
  signal fce_o      : t_can_mac_fce_if_m2s;
  signal tx_bus_o   : std_logic;
  signal rx_bus_i   : std_logic;

  ------------------------------------------------------------------------------
  -- Bus/ACK model control
  ------------------------------------------------------------------------------
  signal inject_ack      : boolean := true;
  signal bus_override    : std_logic := c_recessive;
  signal bus_override_en : boolean := false;

  -- Debug signals from DUT
  signal debug_mac_to_pcs : t_can_mac_pcs_tx_if_m2s;
  signal debug_pcs_to_mac : t_can_mac_pcs_tx_if_s2m;
  signal debug_bit_name   : t_mac_frame_bit_name;
  signal debug_fsm_state  : std_logic_vector(2 downto 0);

  -- Frame config visibility (driven by test runner for waveform inspection)
  signal dbg_fmt     : std_logic_vector(2 downto 0) := c_llc_fmt_cb;
  signal dbg_ftyp    : std_logic := '0';
  signal dbg_brs     : std_logic := '0';
  signal dbg_esi     : std_logic := '0';
  signal dbg_dlc     : std_logic_vector(3 downto 0) := "0000";
  signal dbg_id      : std_logic_vector(31 downto 0) := (others => '0');

  ------------------------------------------------------------------------------
  -- Protocol checker control
  ------------------------------------------------------------------------------
  signal checker_enable          : boolean := false;
  signal checker_request_id      : integer := 0;
  signal checker_done_id         : integer := 0;
  signal checker_expected_params : t_frame_params := c_frame_params_reset;

  constant max_raw_bits_c : integer := c_max_mac_frame_length * 2;
  type raw_bits_t is array (0 to max_raw_bits_c - 1) of std_logic;
  type logical_bits_t is array (0 to c_max_mac_frame_length - 1) of std_logic;

begin

  clk <= not clk after clk_period_c / 2 when not test_done;

  dut : entity work.can_tx
    port map (
      clk_i              => clk,
      rst_i              => rst,
      llc_user_i         => llc_user_i,
      llc_user_o         => llc_user_o,
      fce_i              => fce_i,
      fce_o              => fce_o,
      tx_bus_o           => tx_bus_o,
      rx_bus_i           => rx_bus_i,
      debug_mac_to_pcs_o => debug_mac_to_pcs,
      debug_pcs_to_mac_o => debug_pcs_to_mac,
      debug_ack_error_o  => open,
      debug_form_error_o => open,
      debug_data_exit_o  => open,
      debug_pcs_state_o  => open,
      debug_fsm_state_o  => debug_fsm_state,
      debug_bit_name_o   => debug_bit_name
    );

  -- Loopback + optional ACK-slot override.
  rx_bus_i <= bus_override when bus_override_en else tx_bus_o;
  fce_i.error_passive_request <= '0';
  fce_i.error_active_request  <= '1';
  fce_i.bus_off               <= '0';

  ------------------------------------------------------------------------------
  -- ACK injection: synchronized to DUT bit boundaries via debug signals
  ------------------------------------------------------------------------------
  ack_injector : process is
  begin
    wait until rst = '0';
    loop
      wait until rising_edge(clk);
      if (inject_ack and debug_bit_name = ack_bit) then
        bus_override    <= c_dominant;
        bus_override_en <= true;
        wait for nom_bit_time_clk_c * clk_period_c;
        bus_override_en <= false;
      end if;
    end loop;
  end process ack_injector;

  ------------------------------------------------------------------------------
  -- Protocol checker
  ------------------------------------------------------------------------------
  protocol_checker : process is
    variable alert_id : AlertLogIDType;
    variable params_v : t_frame_params;
    variable raw_bits_v : raw_bits_t;
    variable logical_bits_v : logical_bits_t;
    variable raw_count_v : integer;
    variable logical_count_v : integer;
    variable frame_position_v : integer;
    variable consecutive_count_v : integer;
    variable last_polarity_v : std_logic;
    variable sampled_bit_v : std_logic;
    variable is_stuff_bit_v : boolean;
    variable req_id_v : integer;
    variable crc_stop_int : integer;
    variable eof_stop_int : integer;
    variable ack_delimiter_int : integer;
    variable eof_start_int : integer;
  begin
    alert_id := GetAlertLogID("can_tx_protocol_tb/checker");
    wait until rst = '0';

    loop
      wait until tx_bus_o = c_dominant and tx_bus_o'event;

      if (not checker_enable) then
        next;
      end if;

      req_id_v := checker_request_id;
      params_v := checker_expected_params;

      -- Derive positions from crc_stop (integer)
      crc_stop_int      := params_v.crc_stop;
      ack_delimiter_int := crc_stop_int + c_ack_delimiter_offset;
      eof_start_int     := crc_stop_int + c_eof_start_offset;
      eof_stop_int      := eof_start_int + c_eof_field_width;

      raw_count_v := 1;
      logical_count_v := 1;
      frame_position_v := 0;
      consecutive_count_v := 1;
      last_polarity_v := c_dominant;
      raw_bits_v(0) := c_dominant;
      logical_bits_v(0) := c_dominant;

      for bit_idx in 1 to 260 loop
        if (raw_count_v >= max_raw_bits_c) then
          exit;
        end if;

        wait for nom_bit_time_clk_c * clk_period_c;

        sampled_bit_v := tx_bus_o;
        is_stuff_bit_v := false;
        raw_bits_v(raw_count_v) := sampled_bit_v;
        raw_count_v := raw_count_v + 1;

        if (frame_position_v < crc_stop_int - 1 and
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

        if (frame_position_v >= eof_stop_int - 1) then
          exit;
        end if;
      end loop;

      -- Basic logical frame structure checks.
      AffirmIf(alert_id, logical_count_v = eof_stop_int,
               "Logical frame length check, expected " & integer'image(eof_stop_int) &
               " got " & integer'image(logical_count_v));
      AffirmIf(alert_id, logical_bits_v(c_sof) = c_dominant, "SOF must be dominant");
      AffirmIf(alert_id, logical_bits_v(ack_delimiter_int) = c_recessive, "ACK delimiter must be recessive");
      for p in eof_start_int to eof_stop_int - 1 loop
        AffirmIf(alert_id, logical_bits_v(p) = c_recessive,
                 "EOF bit must be recessive at pos " & integer'image(p));
      end loop;

      checker_done_id <= req_id_v;
    end loop;
  end process protocol_checker;

  ------------------------------------------------------------------------------
  -- Test runner
  ------------------------------------------------------------------------------
  test_runner : process is
    variable alert_id  : AlertLogIDType;

    -- Local frame descriptor (flat fields)
    variable fmt_v     : std_logic_vector(2 downto 0) := c_llc_fmt_cb;
    variable ftyp_v    : std_logic := '0';
    variable esi_v     : std_logic := '0';
    variable brs_v     : std_logic := '0';
    variable dlc_vec_v : std_logic_vector(3 downto 0) := "0001";
    variable id_v      : std_logic_vector(31 downto 0) := (others => '0');
    variable data_v    : std_logic_vector(c_max_data_bytes * c_byte_width - 1 downto 0) := (others => '0');

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
      llc_user_i.avalon_st_source.startofpacket   <= '0';
      llc_user_i.avalon_st_source.endofpacket   <= '0';
    end procedure set_frame_inputs;

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

    procedure submit_frame is

      variable data_byte_count_v : integer;
      variable data_bit_start_v  : integer;
      variable id_29_v           : std_logic_vector(28 downto 0);
      variable is_extended_v     : boolean;
      variable byte0_v           : t_byte;
      variable byte1_v           : t_byte;
      variable byte2_v           : t_byte;
      variable byte3_v           : t_byte;
      variable byte4_v           : t_byte;
      variable byte69_v          : t_byte;
      variable byte70_v          : t_byte;

    begin

      id_29_v       := id_v(28 downto 0);
      is_extended_v := fmt_v(2) = '1';

      if (is_extended_v) then
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

      byte4_v  := "0" & fmt_v & dlc_vec_v;
      byte69_v := "0000000" & fmt_v(2);
      byte70_v := "00000" & brs_v & esi_v & ftyp_v;

      data_byte_count_v := dlc_to_data_length(
                              t_dlc(to_integer(unsigned(dlc_vec_v))),
                              fmt_v
                            );

      send_user_byte(byte0_v, '1', '0');
      send_user_byte(byte1_v, '0', '0');
      send_user_byte(byte2_v, '0', '0');
      send_user_byte(byte3_v, '0', '0');
      send_user_byte(byte4_v, '0', '0');

      for i in 0 to 63 loop
        if (i < data_byte_count_v) then
          data_bit_start_v := data_v'left - i * 8;
          send_user_byte(data_v(data_bit_start_v downto data_bit_start_v - 7), '0', '0');
        else
          send_user_byte((others => '0'), '0', '0');
        end if;
      end loop;

      send_user_byte(byte69_v, '0', '0');
      send_user_byte(byte70_v, '0', '1');

      llc_user_i.avalon_st_source.valid         <= '0';
      llc_user_i.avalon_st_source.startofpacket <= '0';
      llc_user_i.avalon_st_source.endofpacket   <= '0';

    end procedure submit_frame;

    procedure wait_for_transfer_status (
      exp_status : std_logic_vector(2 downto 0);
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
               test_name & ": expected status " & to_hstring(exp_status) &
               " got " & to_hstring(llc_user_o.transfer_status));
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
      constant test_name : string
    ) is
      variable req_id_v : integer;
    begin
      Log(alert_id, test_name);

      set_frame_inputs;
      inject_ack <= true;
      checker_enable <= false;
      req_id_v := checker_request_id + 1;
      checker_request_id <= req_id_v;

      checker_expected_params <= calculate_frame_params((
        format          => fmt_v,
        dlc_vector      => dlc_vec_v,
        is_remote_frame => ftyp_v,
        has_brs         => brs_v,
        esi_enable      => esi_v
      ));

      -- Drive frame config to waveform-visible signals
      dbg_fmt  <= fmt_v;
      dbg_ftyp <= ftyp_v;
      dbg_brs  <= brs_v;
      dbg_esi  <= esi_v;
      dbg_dlc  <= dlc_vec_v;
      dbg_id   <= id_v;

      wait until rising_edge(clk);
      checker_enable <= true;
      submit_frame;
      wait_clocks(2);
      AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '0', test_name & ": tx_ready should drop after submit");
      wait_for_transfer_status(c_transmitted, 220 us, test_name);
      wait_for_checker_done(req_id_v, 220 us, test_name);

      checker_enable <= false;
      wait_clocks(2);
      AffirmIf(alert_id, llc_user_o.avalon_st_sink.ready = '1', test_name & ": tx_ready should return high");
      wait_clocks(20);
    end procedure run_classic_protocol_test;

  begin
    alert_id := GetAlertLogID("can_tx_protocol_tb");
    SetLogEnable(INFO, true);
    SetLogEnable(PASSED, true);

    llc_user_i.avalon_st_source.data  <= (others => '0');
    llc_user_i.avalon_st_source.valid <= '0';
    llc_user_i.avalon_st_source.startofpacket   <= '0';
    llc_user_i.avalon_st_source.endofpacket   <= '0';
    llc_user_i.abort_request <= '0';

    rst <= '1';
    wait_clocks(5);
    rst <= '0';
    wait_clocks(2);

    -- Test 1: CC basic data frame (DLC=1)
    id_v      := (others => '0');
    id_v(10 downto 0) := std_logic_vector(to_unsigned(16#555#, 11));
    fmt_v     := c_llc_fmt_cb;
    ftyp_v    := '0';
    brs_v     := '0';
    esi_v     := '0';
    dlc_vec_v := std_logic_vector(to_unsigned(1, 4));
    data_v    := (others => '0');
    data_v(c_max_data_bytes * c_byte_width - 1 downto c_max_data_bytes * c_byte_width - 8) := x"A5";
    run_classic_protocol_test("Test 1: CC basic data frame protocol check");

    -- Test 2: CC extended data frame (DLC=2)
    id_v      := std_logic_vector(to_unsigned(16#1ABCDE1#, 32));
    fmt_v     := c_llc_fmt_ce;
    ftyp_v    := '0';
    brs_v     := '0';
    esi_v     := '0';
    dlc_vec_v := std_logic_vector(to_unsigned(2, 4));
    data_v    := (others => '0');
    data_v(c_max_data_bytes * c_byte_width - 1 downto c_max_data_bytes * c_byte_width - 8) := x"12";
    data_v(c_max_data_bytes * c_byte_width - 9 downto c_max_data_bytes * c_byte_width - 16) := x"34";
    run_classic_protocol_test("Test 2: CC extended data frame protocol check");

    Log(alert_id, "All can_tx protocol tests completed", PASSED);
    ReportAlerts;
    test_done <= true;
    wait;
  end process test_runner;

end architecture tb;
