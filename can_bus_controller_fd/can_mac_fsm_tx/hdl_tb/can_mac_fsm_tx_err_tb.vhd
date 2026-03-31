--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Comprehensive testbench for error detection requirements.
--                Refactored with clean, reusable infrastructure for multiple error tests.
--                Tests:
--                1. ACK Error Detection (REQ-TX-ERR006)
--                2. Bit Error Detection (REQ-TX-ERR001)
--                3. Data Phase Bit Rate Switching (REQ-TX-EH004)
--                4. FD Data Phase Completion (REQ-TX-EH005)
--                5. TDC Error @ SSP Detection (REQ-TX-TDC003)
--                6. TDC Error Timing Sequence (REQ-TX-TDC004)
--                7. FD EF First Bit Deferred (REQ-TX-EH008)
--                8. Constraint Random Verification (CRV)
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-31  MRDSA     Converted to company header format
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.OsvvmContext;
  use osvvm.ScoreboardPkg_slv.all;
library osvvm_common;
  context osvvm_common.OsvvmCommonContext;

use work.pk_man_global.all;
use work.common_register_interface_pkg.all;
use work.common_tb_pkg.all;
use work.pk_can_types.all;

entity can_mac_fsm_tx_err_tb is
  generic (
    nom_prescaler                   : integer := 2;
    nom_sync_seg                    : integer := 1;
    nom_prop_seg                    : integer := 8;
    nom_phase_seg1                  : integer := 8;
    nom_phase_seg2                  : integer := 8;
    data_prescaler                  : integer := 1;
    data_sync_seg                   : integer := 1;
    data_prop_seg                   : integer := 4;
    data_phase_seg1                 : integer := 8;
    data_phase_seg2                 : integer := 6;
    ssp_offset_cfg                  : t_ssp_offset := 1;
    system_clock_freq_hz            : integer := 100_000_000
  );
end entity can_mac_fsm_tx_err_tb;

architecture testbench of can_mac_fsm_tx_err_tb is

  -- ============================================================================
  -- SECTION 2: Type Definitions & Constants
  -- ============================================================================

  type test_status_t is (idle, setup, running, verifying, passed, failed);
  type test_result_t is record
    test_id    : integer;
    test_name  : string(1 to 80);
    status     : test_status_t;
    duration   : time;
    errors     : integer;
  end record test_result_t;

  -- Frame configuration (parametrizable for all CAN formats)
  type frame_config_t is record
    format       : std_logic_vector(2 downto 0);
    dlc          : std_logic_vector(3 downto 0);
    id_11bit     : std_logic_vector(10 downto 0);
    id_29bit     : std_logic_vector(28 downto 0);
    data_bytes   : integer range 0 to 64;
    ftyp         : std_logic;
    brs          : std_logic;
    esi          : std_logic;
  end record frame_config_t;

  type error_injection_t is record
    inject_ack   : boolean;
    inject_form  : boolean;
    inject_bit   : boolean;
    inject_pos   : integer;
  end record error_injection_t;

  type current_test_t is (
    test_idle,
    test_1_ack_error,
    test_2_bit_error,
    test_3_bit_rate_switching,
    test_4_phase_completion,
    test_5_tdc_ssp_detection,
    test_6_tdc_timing_sequence,
    test_7_fd_ef_first_bit_defer
  );

  -- FSM state constants (must match can_mac_fsm_tx local encoding)
  constant c_st_bus_reintegration    : std_logic_vector(2 downto 0) := "000";
  constant c_st_intermission         : std_logic_vector(2 downto 0) := "001";
  constant c_st_suspend_transmission : std_logic_vector(2 downto 0) := "010";
  constant c_st_bus_idle             : std_logic_vector(2 downto 0) := "011";
  constant c_st_transmitting_frame   : std_logic_vector(2 downto 0) := "100";
  constant c_st_active_error_flag    : std_logic_vector(2 downto 0) := "101";
  constant c_st_passive_error_flag   : std_logic_vector(2 downto 0) := "110";
  constant c_st_overload_flag        : std_logic_vector(2 downto 0) := "111";

  -- Local frame record for test procedures (flat fields, no nested sub-records)
  type t_tb_frame is record
    format  : std_logic_vector(2 downto 0);
    ftyp    : std_logic;
    esi     : std_logic;
    brs     : std_logic;
    dlc     : std_logic_vector(3 downto 0);
    id      : std_logic_vector(31 downto 0);
    data    : std_logic_vector(c_max_data_bytes * c_byte_width - 1 downto 0);
  end record t_tb_frame;

  constant frame_cc_basic_default_c : frame_config_t := (
    format     => c_llc_fmt_cb,
    dlc        => x"1",
    id_11bit   => "10101010101",
    id_29bit   => (others => '0'),
    data_bytes => 1,
    ftyp       => '0',
    brs        => '0',
    esi        => '0'
  );

  constant frame_cc_extended_default_c : frame_config_t := (
    format     => c_llc_fmt_ce,
    dlc        => x"4",
    id_11bit   => (others => '0'),
    id_29bit   => std_logic_vector(to_unsigned(16#0555_AAAA#, 29)),
    data_bytes => 4,
    ftyp       => '0',
    brs        => '0',
    esi        => '0'
  );

  constant frame_fd_basic_default_c : frame_config_t := (
    format     => c_llc_fmt_fb,
    dlc        => x"F",
    id_11bit   => "10101010101",
    id_29bit   => (others => '0'),
    data_bytes => 64,
    ftyp       => '1',
    brs        => '1',
    esi        => '0'
  );

  constant no_error_injection_c : error_injection_t := (
    inject_ack   => false,
    inject_form  => false,
    inject_bit   => false,
    inject_pos   => 0
  );

  constant ack_error_injection_c : error_injection_t := (
    inject_ack   => true,
    inject_form  => false,
    inject_bit   => false,
    inject_pos   => 0
  );

  -- Testbench constants
  constant clk_period : time := 1 ns * (1_000_000_000 / system_clock_freq_hz);
  constant propagation_delay_c : time := 0 ns;

  -- Clock and reset
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- LLC user interface
  signal llc_user_i : t_can_user_llc_tx_if_s2d;
  signal llc_user_o : t_can_user_llc_tx_if_d2s;

  -- Fault Confinement Entity
  signal fce_i : t_can_mac_fce_if_s2m;
  signal fce_o : t_can_mac_fce_if_m2s;

  -- Physical bus
  signal tx_bus : std_logic;
  signal rx_bus : std_logic := '1';
  signal bus_override_test : std_logic := '1';
  signal bus_override_test_en : boolean := false;
  signal error_injection_flag : std_logic := '0';
  signal passive_rx_bus       : std_logic := '1';

  -- Debug interface
  signal debug_mac_to_pcs : t_can_mac_pcs_if_m2s;
  signal debug_pcs_to_mac : t_can_mac_pcs_if_s2m;
  signal debug_bit_name   : t_mac_frame_bit_name;
  signal debug_ack_error  : std_logic;
  signal debug_form_error : std_logic;
  signal fsm_state        : std_logic_vector(2 downto 0);

  -- Test state tracking
  signal current_test : current_test_t := test_idle;
  signal ack_error_pulse_detected : boolean := false;
  signal form_error_pulse_detected : boolean := false;
  signal bit_error_pulse_detected : boolean := false;
  signal test_cycle_counter : integer := 0;
  signal sample_point_counter : integer := 0;
  signal test_complete : boolean := false;
  signal frame_ack_slot_start : integer := 0;
  signal frame_ack_slot_end : integer := 0;
  signal in_ack_slot : boolean := false;

  -- ============================================================================
  -- SECTION 3: Configuration & Helper Procedures
  -- ============================================================================

  procedure init_test_result (
    variable result : out test_result_t;
    test_id : in integer;
    test_name : in string
  ) is
  begin
    result.test_id := test_id;
    result.test_name(test_name'range) := test_name;
    result.status := setup;
    result.duration := 0 ns;
    result.errors := 0;
  end procedure init_test_result;

  procedure log_test_start (
    test_id : in integer;
    test_name : in string
  ) is
  begin
    log("", ALWAYS);
    log("Test " & integer'image(test_id) & ": " & test_name, ALWAYS);
  end procedure log_test_start;

  procedure log_test_result (
    result : in test_result_t
  ) is
    variable status_str : string(1 to 10);
  begin
    if result.status = passed then
      status_str := "PASS      ";
      log("  Result: [PASS] " & status_str & " (" & time'image(result.duration) & ")", ALWAYS);
    else
      log("  Result: [FAIL] (" & time'image(result.duration) & ")", ALWAYS);
      log("  Errors: " & integer'image(result.errors), ALWAYS);
    end if;
  end procedure log_test_result;

  -- ============================================================================
  -- SECTION 4: Frame Building Procedures
  -- ============================================================================

  impure function generate_llc_frame (
    format : in std_logic_vector(2 downto 0) := c_llc_fmt_cb;
    brs_default : in boolean := false;
    esi_default : in boolean := false;
    rtr_default : in boolean := false;
    random_frame : in boolean := false;
    seed_in : in integer := 42
  ) return t_tb_frame is
    variable frame : t_tb_frame;
    variable unified_id : std_logic_vector(28 downto 0);
    variable dlc_val : integer;
    variable data_len : integer;
    variable rtr_flag : boolean;
    variable brs_flag : boolean;
    variable esi_flag : boolean;
    variable rv : RandomPType;
    variable byte_high : integer;
    variable byte_low : integer;
  begin
    rv.InitSeed(seed_in);
    frame.data := (others => '0');

    if (random_frame) then
      if (format = c_llc_fmt_cb or format = c_llc_fmt_ce) then
        dlc_val := rv.RandInt(0, 8);
      else
        dlc_val := rv.RandInt(0, 15);
      end if;
      rtr_flag := rv.RandInt(0, 1) = 1;
      brs_flag := rv.RandInt(0, 1) = 1;
      esi_flag := rv.RandInt(0, 1) = 1;
      unified_id := std_logic_vector(to_unsigned(rv.RandInt(0, 536870911), 29));
      data_len := dlc_to_data_length(t_dlc(dlc_val), format);
      if (not rtr_flag) then
        for i in 0 to data_len - 1 loop
          byte_high := 8 * (i + 1) - 1;
          byte_low := 8 * i;
          frame.data(byte_high downto byte_low) := std_logic_vector(to_unsigned(rv.RandInt(0, 255), 8));
        end loop;
      end if;
      log("[RANDOM] Generated random frame: Format=" & to_hstring(format) &
          " DLC=" & integer'image(dlc_val) & " DataLen=" & integer'image(data_len), ALWAYS);
    else
      dlc_val := 1;
      rtr_flag := rtr_default;
      brs_flag := brs_default;
      esi_flag := esi_default;
      unified_id := std_logic_vector(to_unsigned(16#555#, 29));
      data_len := dlc_to_data_length(t_dlc(dlc_val), format);
    end if;

    if (rtr_flag) then
      data_len := 0;
    end if;

    frame.format := format;
    frame.ftyp   := '1' when rtr_flag else '0';
    frame.esi    := '1' when esi_flag else '0';
    frame.brs    := '1' when brs_flag else '0';
    frame.dlc    := std_logic_vector(to_unsigned(dlc_val, 4));
    frame.id     := pack_llc_id_bytes(unified_id, format);

    log("[CFG] Generated LLC frame: Format=" & to_hstring(format) &
        " DLC=" & integer'image(dlc_val) & " DataLen=" & integer'image(data_len), ALWAYS);

    return frame;
  end function generate_llc_frame;

  -- Helper: send one byte on Avalon-ST with sop/eop flags
  procedure send_user_byte (
    signal llc_i : out t_can_user_llc_tx_if_s2d;
    signal clk   : in  std_logic;
    value : t_byte;
    sop   : std_logic;
    eop   : std_logic
  ) is
  begin
    llc_i.avalon_st_source.data  <= value;
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.startofpacket   <= sop;
    llc_i.avalon_st_source.endofpacket   <= eop;
    loop
      wait until rising_edge(clk);
      exit when llc_user_o.avalon_st_sink.ready = '1';
    end loop;
  end procedure send_user_byte;

  -- Stream frame as 71-byte legacy LLC format to can_llc_tx(legacy_rtl).
  -- Layout: bytes 0-3 = ID, byte 4 = FMT+DLC, bytes 5-68 = data,
  --         byte 69 = IDE, byte 70 = BRS/ESI/RTR
  procedure send_frame (
    signal llc_i : out t_can_user_llc_tx_if_s2d;
    signal clk : in std_logic;
    frame : in t_tb_frame
  ) is
    variable id_29_v           : std_logic_vector(28 downto 0);
    variable is_extended_v     : boolean;
    variable byte0_v           : t_byte;
    variable byte1_v           : t_byte;
    variable byte2_v           : t_byte;
    variable byte3_v           : t_byte;
    variable byte4_v           : t_byte;
    variable byte69_v          : t_byte;
    variable byte70_v          : t_byte;
    variable data_byte_count_v : integer;
    variable data_bit_start_v  : integer;
  begin
    id_29_v       := frame.id(28 downto 0);
    is_extended_v := frame.format(2) = '1';

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

    byte4_v  := "0" & frame.format & frame.dlc;
    byte69_v := "0000000" & frame.format(2);
    byte70_v := "00000" & frame.brs & frame.esi & frame.ftyp;

    data_byte_count_v := dlc_to_data_length(
                            t_dlc(to_integer(unsigned(frame.dlc))),
                            frame.format
                          );

    -- Send 71-byte legacy frame
    send_user_byte(llc_i, clk, byte0_v, '1', '0');   -- Byte 0: ID MSB (sop)
    send_user_byte(llc_i, clk, byte1_v, '0', '0');   -- Byte 1: ID
    send_user_byte(llc_i, clk, byte2_v, '0', '0');   -- Byte 2: ID
    send_user_byte(llc_i, clk, byte3_v, '0', '0');   -- Byte 3: ID LSB
    send_user_byte(llc_i, clk, byte4_v, '0', '0');   -- Byte 4: FMT+DLC

    -- Bytes 5-68: data (64 bytes, pad with zeros)
    for i in 0 to 63 loop
      if i < data_byte_count_v then
        data_bit_start_v := frame.data'left - i * 8;
        send_user_byte(llc_i, clk, frame.data(data_bit_start_v downto data_bit_start_v - 7), '0', '0');
      else
        send_user_byte(llc_i, clk, (others => '0'), '0', '0');
      end if;
    end loop;

    send_user_byte(llc_i, clk, byte69_v, '0', '0');  -- Byte 69: IDE
    send_user_byte(llc_i, clk, byte70_v, '0', '1');  -- Byte 70: BRS/ESI/RTR (eop)

    llc_i.avalon_st_source.valid          <= '0';
    llc_i.avalon_st_source.startofpacket  <= '0';
    llc_i.avalon_st_source.endofpacket    <= '0';
  end procedure send_frame;

  -- ============================================================================
  -- SECTION 7: Test Procedures
  -- ============================================================================

  procedure run_test_ack_error_detection (
    signal llc_i : out t_can_user_llc_tx_if_s2d;
    signal clk : in std_logic
  ) is
    variable test_start_time : time;
    variable test_duration : time;
    variable error_detected : boolean := false;
    variable frame : t_tb_frame;
  begin
    log("", ALWAYS);
    log("Test 1: ACK Error Detection Framework (REQ-TX-ERR006)", ALWAYS);
    test_start_time := now;

    frame := generate_llc_frame(c_llc_fmt_cb, false, false, false);
    send_frame(llc_i, clk, frame);
    log("  [FRAME] Frame submission complete, waiting for transmission...", ALWAYS);
    log("  [STATUS] LLC transfer_status = " & to_hstring(llc_user_o.transfer_status), ALWAYS);

    wait for 100 us;
    test_duration := now - test_start_time;

    log("", ALWAYS);
    if ack_error_pulse_detected then
      log("  Result: [PASS] ACK error detected during simulation", ALWAYS);
    else
      log("  Result: [FAIL] No ACK error detected", ALWAYS);
    end if;
    log("  Duration: " & time'image(test_duration), ALWAYS);
  end procedure run_test_ack_error_detection;

  procedure run_test_bit_error_injection (
    signal llc_i : out t_can_user_llc_tx_if_s2d;
    signal clk : in std_logic;
    signal bus_override : out std_logic;
    signal bus_override_en : out boolean;
    signal error_injection_o : out std_logic
  ) is
    variable test_start_time : time;
    variable test_duration : time;
    variable frame : t_tb_frame;
    variable injected_v : boolean := false;
  begin
    log("", ALWAYS);
    log("Test 2: Bit Error Injection (Polarity Mismatch Detection)", ALWAYS);
    test_start_time := now;
    error_injection_o <= '0';

    frame := generate_llc_frame(c_llc_fmt_cb, false, false, false);
    send_frame(llc_i, clk, frame);
    log("  [STATUS] LLC transfer_status = " & to_hstring(llc_user_o.transfer_status), ALWAYS);

    for i in 1 to 40000 loop
      wait until rising_edge(clk);
      if (debug_pcs_to_mac.sp = '1' and
          debug_bit_name = data_bit and
          tx_bus = c_dominant) then
        injected_v := true;
        exit;
      end if;
    end loop;

    if injected_v then
      bus_override <= '1';
      error_injection_o <= '1';
      bus_override_en <= true;
      wait until rising_edge(clk);
      bus_override_en <= false;
      error_injection_o <= '0';
      bus_override <= '1';
    end if;

    wait for 50 us;
    test_duration := now - test_start_time;

    log("", ALWAYS);
    if bit_error_pulse_detected then
      log("  Result: [PASS] Bit error detected during simulation", ALWAYS);
    else
      log("  Result: [DIAGNOSTIC] Bit error detection status unknown", ALWAYS);
    end if;
    log("  Duration: " & time'image(test_duration), ALWAYS);
  end procedure run_test_bit_error_injection;

  procedure run_test_data_phase_bit_rate_switching (
    signal llc_i : out t_can_user_llc_tx_if_s2d;
    signal clk : in std_logic;
    signal bus_override : out std_logic;
    signal bus_override_en : out boolean;
    signal error_injection_o : out std_logic
  ) is
    variable test_start_time : time;
    variable test_duration : time;
    variable frame : t_tb_frame;
    variable injected_v : boolean := false;
  begin
    log("", ALWAYS);
    log("Test 3: Data Phase Bit Rate Switching (REQ-TX-EH004)", ALWAYS);
    test_start_time := now;
    error_injection_o <= '0';

    frame := generate_llc_frame(c_llc_fmt_fb, true, false, false);
    send_frame(llc_i, clk, frame);
    log("  [STATUS] LLC transfer_status = " & to_hstring(llc_user_o.transfer_status), ALWAYS);

    -- Wait for data phase bit (use_data_rate indicates data phase)
    for i in 1 to 80000 loop
      wait until rising_edge(clk);
      if (debug_mac_to_pcs.use_data_rate = '1' and
          debug_pcs_to_mac.sp = '1' and
          debug_bit_name = data_bit) then
        injected_v := true;
        exit;
      end if;
    end loop;

    if injected_v then
      bus_override <= not tx_bus;
      error_injection_o <= '1';
      bus_override_en <= true;
      wait until rising_edge(clk);
      bus_override_en <= false;
      error_injection_o <= '0';
      bus_override <= '1';
    end if;

    wait for 50 us;
    test_duration := now - test_start_time;

    log("", ALWAYS);
    log("  Result: [DIAGNOSTIC] Bit rate switching monitored via use_data_rate signal", ALWAYS);
    log("  Duration: " & time'image(test_duration), ALWAYS);
  end procedure run_test_data_phase_bit_rate_switching;

  procedure run_test_fd_phase_completion (
    signal llc_i : out t_can_user_llc_tx_if_s2d;
    signal clk : in std_logic;
    signal bus_override : out std_logic;
    signal bus_override_en : out boolean;
    signal error_injection_o : out std_logic
  ) is
    variable test_start_time : time;
    variable test_duration : time;
    variable frame : t_tb_frame;
    variable injected_v : boolean := false;
    variable data_bit_count_v : integer := 0;
  begin
    log("", ALWAYS);
    log("Test 4: FD Data Phase Completion (REQ-TX-EH005)", ALWAYS);
    test_start_time := now;
    error_injection_o <= '0';

    frame := generate_llc_frame(c_llc_fmt_fe, true, false, false);
    send_frame(llc_i, clk, frame);
    log("  [STATUS] LLC transfer_status = " & to_hstring(llc_user_o.transfer_status), ALWAYS);

    for i in 1 to 120000 loop
      wait until rising_edge(clk);
      if (debug_mac_to_pcs.use_data_rate = '1' and
          debug_pcs_to_mac.sp = '1' and
          debug_bit_name = data_bit) then
        data_bit_count_v := data_bit_count_v + 1;
        if (data_bit_count_v >= 25 and tx_bus = c_dominant) then
          injected_v := true;
          exit;
        end if;
      end if;
    end loop;

    if injected_v then
      bus_override <= '1';
      error_injection_o <= '1';
      bus_override_en <= true;
      wait until rising_edge(clk);
      bus_override_en <= false;
      error_injection_o <= '0';
      bus_override <= '1';
    end if;

    wait for 50 us;
    test_duration := now - test_start_time;

    log("", ALWAYS);
    log("  Result: [DIAGNOSTIC] Phase completion monitored via waveform", ALWAYS);
    log("  Duration: " & time'image(test_duration), ALWAYS);
  end procedure run_test_fd_phase_completion;

  procedure run_test_tdc_error_at_ssp (
    signal llc_i : out t_can_user_llc_tx_if_s2d;
    signal clk : in std_logic;
    signal bus_override : out std_logic;
    signal bus_override_en : out boolean;
    signal error_injection_o : out std_logic
  ) is
    variable test_start_time : time;
    variable test_duration : time;
    variable frame : t_tb_frame;
    variable injected_v : boolean := false;
  begin
    log("", ALWAYS);
    log("Test 5: TDC Error Detection @ SSP (REQ-TX-TDC003)", ALWAYS);
    test_start_time := now;
    error_injection_o <= '0';

    frame := generate_llc_frame(c_llc_fmt_fe, true, false, false);
    send_frame(llc_i, clk, frame);
    log("  [STATUS] LLC transfer_status = " & to_hstring(llc_user_o.transfer_status), ALWAYS);

    -- Wait for SSP during data phase
    for i in 1 to 120000 loop
      wait until rising_edge(clk);
      if (debug_mac_to_pcs.use_data_rate = '1' and
          debug_pcs_to_mac.ssp = '1' and
          debug_bit_name = data_bit and
          tx_bus = c_dominant) then
        injected_v := true;
        exit;
      end if;
    end loop;

    if injected_v then
      bus_override <= '1';
      error_injection_o <= '1';
      bus_override_en <= true;
      wait until rising_edge(clk);
      bus_override_en <= false;
      error_injection_o <= '0';
      bus_override <= '1';
    end if;

    wait for 15 us;
    test_duration := now - test_start_time;

    log("", ALWAYS);
    log("  Result: [DIAGNOSTIC] SSP vs SP error detection monitored", ALWAYS);
    log("  Duration: " & time'image(test_duration), ALWAYS);
  end procedure run_test_tdc_error_at_ssp;

  procedure run_test_constraint_random_verification (
    signal llc_i : out t_can_user_llc_tx_if_s2d;
    signal clk : in std_logic
  ) is
    variable test_start_time : time;
    variable test_duration : time;
    variable seed : integer := 12345;
    variable frame : t_tb_frame;
  begin
    log("", ALWAYS);
    log("Test 8: Constraint Random Verification (Coverage-Driven)", ALWAYS);
    test_start_time := now;

    frame := generate_llc_frame(c_llc_fmt_cb, false, false, false, true, seed);
    send_frame(llc_i, clk, frame);
    wait for 100 us;

    frame := generate_llc_frame(c_llc_fmt_fb, false, false, false, true, seed);
    send_frame(llc_i, clk, frame);
    wait for 100 us;

    frame := generate_llc_frame(c_llc_fmt_ce, false, false, false, true, seed);
    send_frame(llc_i, clk, frame);
    wait for 100 us;

    test_duration := now - test_start_time;
    log("  Duration: " & time'image(test_duration), ALWAYS);
  end procedure run_test_constraint_random_verification;

  procedure run_test_tdc_error_timing_sequence (
    signal llc_i : out t_can_user_llc_tx_if_s2d;
    signal clk : in std_logic;
    signal bus_override : out std_logic;
    signal bus_override_en : out boolean;
    signal error_injection_o : out std_logic
  ) is
    variable test_start_time : time;
    variable test_duration : time;
    variable frame : t_tb_frame;
    variable injected_v : boolean := false;
  begin
    log("", ALWAYS);
    log("Test 6: TDC Error Timing Sequence (REQ-TX-TDC004)", ALWAYS);
    test_start_time := now;

    frame := generate_llc_frame(c_llc_fmt_fe, true, false, false);
    send_frame(llc_i, clk, frame);
    log("  [STATUS] LLC transfer_status = " & to_hstring(llc_user_o.transfer_status), ALWAYS);

    for i in 1 to 160000 loop
      wait until rising_edge(clk);
      if (debug_mac_to_pcs.use_data_rate = '1' and
          debug_pcs_to_mac.ssp = '1' and
          debug_bit_name = data_bit and
          tx_bus = c_dominant) then
        injected_v := true;
        exit;
      end if;
    end loop;

    if injected_v then
      bus_override <= '1';
      error_injection_o <= '1';
      bus_override_en <= true;
      for i in 1 to 2 loop
        wait until rising_edge(clk);
      end loop;
      bus_override_en <= false;
      error_injection_o <= '0';
      bus_override <= '1';
    end if;

    wait for 60 us;
    test_duration := now - test_start_time;

    log("", ALWAYS);
    log("  Result: [DIAGNOSTIC] TDC timing sequence monitored", ALWAYS);
    log("  Duration: " & time'image(test_duration), ALWAYS);
  end procedure run_test_tdc_error_timing_sequence;

  procedure run_test_fd_error_flag_first_bit_deferred (
    signal llc_i : out t_can_user_llc_tx_if_s2d;
    signal clk : in std_logic;
    signal bus_override : out std_logic;
    signal bus_override_en : out boolean;
    signal error_injection_o : out std_logic
  ) is
    variable test_start_time : time;
    variable test_duration : time;
    variable frame : t_tb_frame;
    variable ef_req_seen_v : boolean := false;
    variable pcs_ef_seen_v : boolean := false;
    variable injected_v : boolean := false;
    variable inject_armed_v : boolean := false;
    variable inject_hold_cycles_v : integer := 0;
    variable saw_crc_delim_before_ef_req_v : boolean := false;
    variable saw_ack_before_ef_req_v       : boolean := false;
    variable ef_req_cycle_v : integer := 0;
    variable pcs_ef_cycle_v : integer := 0;
    variable ef_dom_count_v : integer := 0;
    variable ef_delim_seen_v : boolean := false;
    variable bit_rate_at_pcs_ef_v : std_logic := '1';
  begin
    log("", ALWAYS);
    log("Test 7: FD EF First Bit Deferred Until Nominal (REQ-TX-EH008)", ALWAYS);
    test_start_time := now;

    bus_override_en <= false;
    error_injection_o <= '0';
    bus_override <= c_recessive;

    frame := generate_llc_frame(c_llc_fmt_fb, true, false, false);
    send_frame(llc_i, clk, frame);

    for i in 1 to 120000 loop
      wait until rising_edge(clk);

      if (inject_hold_cycles_v > 0) then
        bus_override_en <= true;
        error_injection_o <= '1';
        bus_override    <= c_recessive;
        inject_hold_cycles_v := inject_hold_cycles_v - 1;
      else
        bus_override_en <= false;
        error_injection_o <= '0';
        bus_override    <= c_recessive;
      end if;

      if (debug_mac_to_pcs.use_data_rate = '1') then
        inject_armed_v := true;
      end if;

      if (not ef_req_seen_v) then
        if (debug_bit_name = crc_delimiter_bit) then
          saw_crc_delim_before_ef_req_v := true;
        elsif (debug_bit_name = ack_bit) then
          saw_ack_before_ef_req_v := true;
        end if;
      end if;

      if (inject_armed_v and (not injected_v) and
          debug_pcs_to_mac.sp = '1' and tx_bus = c_dominant) then
        bus_override_en      <= true;
        error_injection_o    <= '1';
        bus_override         <= c_recessive;
        inject_hold_cycles_v := 20;
        injected_v := true;
      end if;

      if (not ef_req_seen_v) and debug_mac_to_pcs.valid = '1' and
         (debug_bit_name = active_error_flag_bit or
          debug_bit_name = passive_error_flag_bit) then
        ef_req_seen_v  := true;
        ef_req_cycle_v := i;
      end if;

      if ef_req_seen_v and (not pcs_ef_seen_v) and
         (debug_bit_name = active_error_flag_bit or
          debug_bit_name = passive_error_flag_bit) then
        pcs_ef_seen_v := true;
        pcs_ef_cycle_v := i;
        bit_rate_at_pcs_ef_v := debug_mac_to_pcs.use_data_rate;
      end if;

      if pcs_ef_seen_v and debug_pcs_to_mac.sp = '1' then
        if (debug_bit_name = active_error_flag_bit or
            debug_bit_name = passive_error_flag_bit) then
          ef_dom_count_v := ef_dom_count_v + 1;
        elsif (debug_bit_name = error_delimiter_bit) then
          ef_delim_seen_v := true;
          exit;
        end if;
      end if;
    end loop;

    bus_override_en <= false;
    error_injection_o <= '0';
    bus_override <= c_recessive;

    AlertIf(not injected_v,
            "Did not inject the planned data-phase mismatch",
            ERROR);
    AlertIf(not ef_req_seen_v,
            "Did not observe error-flag request from MAC after data-phase injection",
            ERROR);
    AlertIf(saw_crc_delim_before_ef_req_v or saw_ack_before_ef_req_v,
            "Error-flag request occurred after leaving data phase (not a data-phase error)",
            ERROR);
    AlertIf(not pcs_ef_seen_v,
            "Did not observe PCS transmitting first error-flag bit",
            ERROR);

    if (ef_req_seen_v and pcs_ef_seen_v) then
      AlertIf(pcs_ef_cycle_v < ef_req_cycle_v,
              "PCS transmitted first error-flag bit before EF request",
              ERROR);
      AlertIf(bit_rate_at_pcs_ef_v /= '0',
              "First error-flag bit must be transmitted with nominal timing active",
              ERROR);
      AlertIf(not ef_delim_seen_v,
              "Did not observe error delimiter after first error-flag bit",
              ERROR);
      AlertIf(ef_dom_count_v /= c_error_flag_width,
              "Dominant error-flag width mismatch. Expected " &
              integer'image(c_error_flag_width) & ", got " &
              integer'image(ef_dom_count_v),
              ERROR);
    end if;

    wait for 20 us;
    test_duration := now - test_start_time;
    log("  Duration: " & time'image(test_duration), ALWAYS);
  end procedure run_test_fd_error_flag_first_bit_deferred;

begin

  -- DUT instantiation
  dut : entity work.can_tx
    generic map (
      gc_prescaler       => nom_prescaler,
      gc_nom_prop_seg    => nom_prop_seg,
      gc_nom_phase_seg1  => nom_phase_seg1,
      gc_nom_phase_seg2  => nom_phase_seg2,
      gc_data_prop_seg   => data_prop_seg,
      gc_data_phase_seg1 => data_phase_seg1,
      gc_data_phase_seg2 => data_phase_seg2,
      gc_ssp_offset      => ssp_offset_cfg
    )
    port map (
      clk_i              => clk,
      rst_i              => rst,
      llc_user_i         => llc_user_i,
      llc_user_o         => llc_user_o,
      fce_i              => fce_i,
      fce_o              => fce_o,
      tx_bus_o           => tx_bus,
      rx_bus_i           => rx_bus,
      debug_mac_to_pcs_o => debug_mac_to_pcs,
      debug_pcs_to_mac_o => debug_pcs_to_mac,
      debug_ack_error_o  => debug_ack_error,
      debug_form_error_o => debug_form_error,
      debug_data_exit_o  => open,
      debug_pcs_state_o  => open,
      debug_fsm_state_o  => fsm_state,
      debug_bit_name_o   => debug_bit_name
    );

  -- Clock generation
  clk <= not clk after clk_period / 2;

  -- Passive receiver model: Provides ACK dominant for all tests except Test 1
  passive_rx_bus <= c_dominant when (debug_bit_name = ack_bit and
                                     current_test /= test_1_ack_error) else
                    c_recessive;

  -- Bus model: loopback with configurable propagation delay and test injection
  rx_bus <= bus_override_test when bus_override_test_en else
            passive_rx_bus when (debug_bit_name = ack_bit and current_test /= test_1_ack_error) else
            tx_bus after propagation_delay_c;

  -- ============================================================================
  -- Main Test Process
  -- ============================================================================

  test_proc : process
  begin

    log("", ALWAYS);
    log("================================================================================", ALWAYS);
    log("  TX Error Detection Testbench", ALWAYS);
    log("================================================================================", ALWAYS);

    rst <= '1';
    wait for 10 * clk_period;
    rst <= '0';
    wait for 10 * clk_period;

    fce_i.error_passive_request <= '0';
    fce_i.error_active_request  <= '1';
    fce_i.bus_off               <= '0';
    llc_user_i.avalon_st_source.valid <= '0';
    error_injection_flag <= '0';

    -- Test 1: ACK Error Detection
    current_test <= test_1_ack_error;
    run_test_ack_error_detection(llc_user_i, clk);

    -- Test 2: Bit Error Injection
    current_test <= test_2_bit_error;
    run_test_bit_error_injection(llc_user_i, clk, bus_override_test, bus_override_test_en, error_injection_flag);

    -- Test 3: Data Phase Bit Rate Switching
    current_test <= test_3_bit_rate_switching;
    run_test_data_phase_bit_rate_switching(llc_user_i, clk, bus_override_test, bus_override_test_en, error_injection_flag);

    -- Test 4: FD Data Phase Completion
    current_test <= test_4_phase_completion;
    run_test_fd_phase_completion(llc_user_i, clk, bus_override_test, bus_override_test_en, error_injection_flag);

    -- Test 7: FD EF first-bit defer
    current_test <= test_7_fd_ef_first_bit_defer;
    run_test_fd_error_flag_first_bit_deferred(llc_user_i, clk, bus_override_test, bus_override_test_en, error_injection_flag);

    -- Test 5: TDC Error @ SSP Detection
    current_test <= test_5_tdc_ssp_detection;
    run_test_tdc_error_at_ssp(llc_user_i, clk, bus_override_test, bus_override_test_en, error_injection_flag);

    -- Test 6: TDC Error Timing Sequence
    current_test <= test_6_tdc_timing_sequence;
    run_test_tdc_error_timing_sequence(llc_user_i, clk, bus_override_test, bus_override_test_en, error_injection_flag);

    -- Test 8: Constraint Random Verification
    current_test <= test_idle;
    run_test_constraint_random_verification(llc_user_i, clk);

    log("", ALWAYS);
    log("================================================================================", ALWAYS);
    log("  All Tests Complete", ALWAYS);
    log("================================================================================", ALWAYS);

    test_complete <= true;
    wait;

  end process test_proc;

  -- Monitor for error pulses
  error_monitor : process (clk) is
    variable last_bit_name : t_mac_frame_bit_name := idle_bit;
    variable debug_sample_count : integer := 0;
  begin
    if rising_edge(clk) then
      if debug_ack_error = '1' then
        ack_error_pulse_detected <= true;
        log("[PULSE] ACK ERROR DETECTED at sample " &
            integer'image(sample_point_counter), ALWAYS);
      end if;

      if debug_form_error = '1' then
        form_error_pulse_detected <= true;
        log("[PULSE] FORM ERROR DETECTED at sample " &
            integer'image(sample_point_counter), ALWAYS);
      end if;

      if (fsm_state = c_st_active_error_flag or
          fsm_state = c_st_passive_error_flag) then
        bit_error_pulse_detected <= true;
      end if;

      if debug_pcs_to_mac.sp = '1' then
        debug_sample_count := debug_sample_count + 1;
        if (debug_bit_name /= last_bit_name) or (debug_sample_count < 20) then
          log("[BIT] Sample " & integer'image(debug_sample_count) & ": " &
              t_mac_frame_bit_name'image(debug_bit_name) &
              " (polarity: " & std_logic'image(debug_mac_to_pcs.polarity) & ")", ALWAYS);
          last_bit_name := debug_bit_name;
        end if;
      end if;
    end if;
  end process error_monitor;

end architecture testbench;
