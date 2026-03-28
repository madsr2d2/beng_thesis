--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_mac_fsm_tx.
--                  p_pcs_standin      - PCS stand-in (SP strobe generation, bus loopback with override).
--                  p_fce_monitor      - Continuous FCE output monitor.
--                  p_test_ctrl        - Coverage-driven test sequencer (quiet phase, happy path,
--                                       ACK/bit/arb errors, overload, delimiter too late, primary error).
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-23  TMYAES    [TRIT-4355] Initial implementation
--                2026-03-28  MRDSA     [TRIT-4355] Rewritten with OSVVM coverage and company TB style
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

library osvvm;
  context osvvm.OsvvmContext;

entity can_mac_fsm_tx_tb is
  generic (
    gc_TbTimeOut   : time := 50 ms;
    gc_TbClkPeriod : time := 10 ns
  );
end entity can_mac_fsm_tx_tb;

architecture tb of can_mac_fsm_tx_tb is

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  constant c_sp_interval   : integer := 10;
  constant c_cb_cov_bin    : integer := to_integer(unsigned(c_llc_fmt_cb));
  constant c_ce_cov_bin    : integer := to_integer(unsigned(c_llc_fmt_ce));
  constant c_fb_cov_bin    : integer := to_integer(unsigned(c_llc_fmt_fb));
  constant c_fe_cov_bin    : integer := to_integer(unsigned(c_llc_fmt_fe));
  constant c_bin_num       : integer := 1;

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal clk   : std_logic;
  signal reset : std_logic := '1';

  -- DUT interface
  signal mac_ser_i : t_can_mac_ser_fsm_tx_if_s2m := c_tx_mac_ser_to_fsm_if_reset;
  signal mac_ser_o : t_can_mac_ser_fsm_tx_if_m2s;
  signal pcs_i     : t_can_mac_pcs_tx_if_s2m     := c_pcs_to_mac_if_reset;
  signal pcs_o     : t_can_mac_pcs_tx_if_m2s;
  signal bs_fd_i   : t_can_mac_fsm_bs_tx_if_s2m  := c_can_mac_fsm_bs_tx_if_s2m_reset;
  signal bs_fd_o   : t_can_mac_fsm_bs_tx_if_m2s;
  signal bs_fd_rst : std_logic;
  signal crc_i     : t_can_mac_fsm_crc_tx_if_s2m;
  signal crc_o     : t_can_mac_fsm_crc_tx_if_m2s;
  signal crc_rst   : std_logic;
  signal fce_i     : t_can_mac_fce_if_s2m        := c_fce_to_mac_if_reset;
  signal fce_o     : t_can_mac_fce_if_m2s;

  -- Stand-in control
  signal pcs_sp_enable       : boolean   := true;
  signal pcs_bus_override    : std_logic := c_recessive;
  signal pcs_bus_override_en : boolean   := false;
  signal sp_strobe           : std_logic := '0';
  signal ser_frame_valid     : boolean        := false;
  signal ser_metadata        : t_llc_metadata := c_llc_metadata_reset;
  signal ser_data_pattern    : std_logic      := c_recessive;
  signal fce_error_passive   : std_logic := '0';
  signal fce_error_active    : std_logic := '1';
  signal fce_bus_off         : std_logic := '0';

  -- OSVVM signals
  shared variable RV  : RandomPType;
  signal test_id      : AlertLogIDType;
  signal fmt_cov      : CoverageIDType;
  signal init_barrier : std_logic := '0';

begin

  ----------------------------------------------------------------------------
  -- Infrastructure
  ----------------------------------------------------------------------------
  CreateClock(clk, gc_TbClkPeriod);
  CreateReset(reset, '1', clk, gc_TbClkPeriod * 5);

  p_timeout : process is
  begin
    wait for gc_TbTimeOut;
    Alert("Testbench timeout", FAILURE);
    std.env.finish;
  end process p_timeout;

  p_init : process is
    variable v_test_id : AlertLogIDType;
    variable v_fmt_cov : CoverageIDType;
  begin
    SetAlertStopCount(ERROR, 5);
    SetLogEnable(INFO, TRUE);
    v_test_id := NewID("can_mac_fsm_tx");
    v_fmt_cov := NewID("Format Coverage", v_test_id);

    AddBins(v_fmt_cov, GenBin(c_bin_num, (c_cb_cov_bin, c_ce_cov_bin, c_fb_cov_bin, c_fe_cov_bin)));

    test_id <= v_test_id;
    fmt_cov <= v_fmt_cov;

    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  ----------------------------------------------------------------------------
  -- DUT
  ----------------------------------------------------------------------------
  u_dut : entity work.can_mac_fsm_tx
    port map (
      clk_i     => clk,
      rst_i     => reset,
      mac_ser_i => mac_ser_i,
      mac_ser_o => mac_ser_o,
      pcs_i     => pcs_i,
      pcs_o     => pcs_o,
      bs_fd_i   => bs_fd_i,
      bs_fd_o   => bs_fd_o,
      bs_fd_rst => bs_fd_rst,
      crc_i     => crc_i,
      crc_o     => crc_o,
      crc_rst   => crc_rst,
      fce_i     => fce_i,
      fce_o     => fce_o
    );

  ----------------------------------------------------------------------------
  -- PCS stand-in (SP strobe + bus loopback with override)
  ----------------------------------------------------------------------------
  p_pcs_standin : process (clk) is
    variable sp_count : integer range 0 to c_sp_interval - 1 := 0;
  begin
    if rising_edge(clk) then
      sp_strobe <= '0';
      if (reset = '1') then
        sp_count := 0;
      elsif (pcs_sp_enable) then
        if (sp_count = c_sp_interval - 1) then
          sp_strobe <= '1';
          sp_count  := 0;
        else
          sp_count := sp_count + 1;
        end if;
      end if;
    end if;
  end process p_pcs_standin;

  pcs_i.sp           <= sp_strobe;
  pcs_i.ssp          <= '0';
  pcs_i.tdc_delay    <= (others => '0');
  pcs_i.bus_polarity <= pcs_bus_override when pcs_bus_override_en else pcs_o.polarity;

  ----------------------------------------------------------------------------
  -- Stand-ins: Serializer, Bit stuffer, CRC, FCE
  ----------------------------------------------------------------------------
  mac_ser_i.valid        <= '1' when ser_frame_valid else '0';
  mac_ser_i.llc_metadata <= ser_metadata;
  mac_ser_i.data         <= ser_data_pattern;

  bs_fd_i.valid <= '0';
  bs_fd_i.data  <= c_recessive;
  bs_fd_i.sbc   <= (others => '0');

  crc_i.crc <= (others => '0');

  fce_i.error_passive_request <= fce_error_passive;
  fce_i.error_active_request  <= fce_error_active;
  fce_i.bus_off               <= fce_bus_off;

  ----------------------------------------------------------------------------
  -- FCE output monitor
  ----------------------------------------------------------------------------
  p_fce_monitor : process is
    variable v_prev_error               : std_logic := '0';
    variable v_prev_successful          : std_logic := '0';
    variable v_prev_delimiter_too_late  : std_logic := '0';
    variable v_prev_primary_error       : std_logic := '0';
    variable v_prev_counters_unchanged  : std_logic := '0';
  begin
    WaitForBarrier(init_barrier);
    wait until reset = '0';

    loop
      wait until rising_edge(clk);
      if (fce_o.error = '1' and v_prev_error = '0') then
        Log(test_id, "FCE: error pulse", INFO);
      end if;
      if (fce_o.successful_transfer = '1' and v_prev_successful = '0') then
        Log(test_id, "FCE: successful transfer", INFO);
      end if;
      if (fce_o.error_delimiter_too_late = '1' and v_prev_delimiter_too_late = '0') then
        Log(test_id, "FCE: error delimiter too late", INFO);
      end if;
      if (fce_o.primary_error = '1' and v_prev_primary_error = '0') then
        Log(test_id, "FCE: primary error", INFO);
      end if;
      if (fce_o.counters_unchanged = '1' and v_prev_counters_unchanged = '0') then
        Log(test_id, "FCE: counters unchanged", INFO);
      end if;
      v_prev_error              := fce_o.error;
      v_prev_successful         := fce_o.successful_transfer;
      v_prev_delimiter_too_late := fce_o.error_delimiter_too_late;
      v_prev_primary_error      := fce_o.primary_error;
      v_prev_counters_unchanged := fce_o.counters_unchanged;
    end loop;
  end process p_fce_monitor;

  ----------------------------------------------------------------------------
  -- Test sequencer
  ----------------------------------------------------------------------------
  p_test_ctrl : process is
    variable v_fp   : t_frame_params;
    variable v_meta : t_llc_metadata;

    procedure wait_n_sp (
      n : in integer
    ) is
    begin
      for i in 1 to n loop
        wait until sp_strobe = '1';
        wait until rising_edge(clk);
      end loop;
    end procedure wait_n_sp;

    procedure wait_for_frame_entry (
      timeout_sp : in integer := 200
    ) is
    begin
      for i in 1 to timeout_sp * c_sp_interval loop
        wait until rising_edge(clk);
        if (fce_o.transmitting = '1') then
          return;
        end if;
      end loop;
      Alert(test_id, "wait_for_frame_entry timeout", ERROR);
    end procedure wait_for_frame_entry;

    procedure wait_for_transfer_status (
      expected   : in std_logic_vector(2 downto 0);
      timeout_sp : in integer := 500;
      msg        : in string
    ) is
    begin
      for i in 1 to timeout_sp * c_sp_interval loop
        wait until rising_edge(clk);
        if (mac_ser_o.transfer_status = expected) then
          return;
        end if;
      end loop;
      Alert(test_id, "transfer_status timeout: " & msg, ERROR);
    end procedure wait_for_transfer_status;

    procedure wait_for_error_flag_entry (
      timeout_sp : in integer := 500
    ) is
    begin
      for i in 1 to timeout_sp * c_sp_interval loop
        wait until rising_edge(clk);
        if (fce_o.sending_error_overload_flag = '1') then
          return;
        end if;
      end loop;
      Alert(test_id, "wait_for_error_flag_entry timeout", ERROR);
    end procedure wait_for_error_flag_entry;

    procedure transmit_and_verify (
      meta : in t_llc_metadata;
      msg  : in string
    ) is
      variable v_fp     : t_frame_params;
      variable v_ack_sp : integer;
    begin
      v_fp     := get_frame_params(meta);
      v_ack_sp := v_fp.crc_delimiter + c_ack_slot_offset;

      ser_metadata    <= meta;
      ser_frame_valid <= true;

      wait_for_frame_entry;

      for sp in 1 to v_ack_sp + 1 loop
        if (sp = v_ack_sp + 1) then
          pcs_bus_override    <= c_dominant;
          pcs_bus_override_en <= true;
        end if;
        wait_n_sp(1);
      end loop;
      pcs_bus_override_en <= false;

      wait_for_transfer_status(c_transmitted, 200, msg);
      AffirmIf(test_id, mac_ser_o.transfer_status = c_transmitted, msg & " transmitted");

      ser_frame_valid <= false;
      wait_n_sp(c_intermission_width + 2);
    end procedure transmit_and_verify;

    procedure wait_for_error_recovery is
    begin
      wait_for_transfer_status(c_disturbed, 500, "error recovery");
      wait_n_sp(c_error_sequence_width + c_intermission_width + c_bus_idle_condition_width + 5);
    end procedure wait_for_error_recovery;

  begin
    WaitForBarrier(init_barrier);
    wait until reset = '0';
    WaitForClock(clk);

    ---------------------------------------------------------------------------
    -- Group 1: Reintegration & Quiet Phase
    ---------------------------------------------------------------------------

    -- Test 1: Dominant resets reintegration counter
    Log(test_id, "T1: Dominant resets reintegration counter", INFO);
    wait_n_sp(5);
    pcs_bus_override    <= c_dominant;
    pcs_bus_override_en <= true;
    wait_n_sp(1);
    pcs_bus_override_en <= false;
    wait_n_sp(c_bus_idle_condition_width);

    ser_metadata    <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid <= true;
    wait_for_frame_entry(50);
    AffirmIf(test_id, fce_o.transmitting = '1', "T1: dominant resets reintegration counter");
    ser_frame_valid <= false;
    wait_for_error_recovery;

    -- Test 2: Reintegration to idle
    Log(test_id, "T2: Reintegration to idle", INFO);
    ser_metadata    <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid <= true;
    wait_for_frame_entry(50);
    AffirmIf(test_id, fce_o.transmitting = '1', "T2: reintegration to idle");
    ser_frame_valid <= false;
    wait_for_error_recovery;

    ---------------------------------------------------------------------------
    -- Group 2: Happy Path Transmission (coverage-driven format)
    ---------------------------------------------------------------------------
    Log(test_id, "Group 2: Happy path (all formats)", INFO);

    happy_path_loop : while not IsCovered(fmt_cov) loop
      v_meta.dlc  := x"1";
      v_meta.ftyp := '0';
      v_meta.esi  := '0';

      -- Coverage-driven format
      v_meta.format := std_logic_vector(to_unsigned(GetRandPoint(fmt_cov), 3));

      -- FD formats require BRS
      if (v_meta.format(1) = '1') then
        v_meta.brs := '1';
      else
        v_meta.brs := '0';
      end if;

      transmit_and_verify(v_meta, "Happy path fmt=" & to_string(v_meta.format));
      ICover(fmt_cov, to_integer(unsigned(v_meta.format)));
    end loop happy_path_loop;

    ---------------------------------------------------------------------------
    -- Group 3: ACK Error
    ---------------------------------------------------------------------------
    Log(test_id, "T7: ACK error (no dominant during ACK)", INFO);
    v_fp := get_frame_params((format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0'));
    ser_metadata    <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid <= true;

    wait_for_frame_entry;
    wait_for_transfer_status(c_disturbed, 500, "T7: ACK error");
    AffirmIf(test_id, mac_ser_o.transfer_status = c_disturbed, "T7: ACK error detected");

    ser_frame_valid <= false;
    wait_n_sp(c_error_sequence_width + c_intermission_width + c_bus_idle_condition_width + 5);

    ---------------------------------------------------------------------------
    -- Group 4: Bit Error
    ---------------------------------------------------------------------------

    -- Test 8: Bit error -> active error flag
    Log(test_id, "T8: Bit error -> active error flag", INFO);
    ser_metadata    <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid <= true;

    wait_for_frame_entry;
    wait_n_sp(5);
    pcs_bus_override    <= c_dominant;
    pcs_bus_override_en <= true;
    wait_n_sp(1);
    pcs_bus_override_en <= false;

    wait_for_error_flag_entry(50);
    AffirmIf(test_id, fce_o.sending_error_overload_flag = '1', "T8: bit error -> error flag");
    AffirmIf(test_id, mac_ser_o.transfer_status = c_disturbed, "T8: transfer disturbed");

    ser_frame_valid <= false;
    wait_n_sp(c_error_sequence_width + c_intermission_width + c_bus_idle_condition_width + 5);

    -- Test 9: Bit error -> passive error flag
    Log(test_id, "T9: Bit error -> passive error flag", INFO);
    fce_error_passive <= '1';
    fce_error_active  <= '0';

    ser_metadata    <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid <= true;

    wait_for_frame_entry;
    wait_n_sp(5);
    pcs_bus_override    <= c_dominant;
    pcs_bus_override_en <= true;
    wait_n_sp(1);
    pcs_bus_override_en <= false;

    wait_for_error_flag_entry(50);
    AffirmIf(test_id, pcs_o.polarity = c_recessive, "T9: passive EF recessive polarity");
    AffirmIf(test_id, mac_ser_o.transfer_status = c_disturbed, "T9: transfer disturbed");

    ser_frame_valid   <= false;
    fce_error_passive <= '0';
    fce_error_active  <= '1';
    wait_n_sp(c_error_sequence_width + c_intermission_width + c_suspend_transmission_width + c_bus_idle_condition_width + 5);

    ---------------------------------------------------------------------------
    -- Group 5: Arbitration Loss
    ---------------------------------------------------------------------------
    Log(test_id, "T10: Lost arbitration", INFO);
    ser_data_pattern <= c_recessive;
    ser_metadata     <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid  <= true;

    wait_for_frame_entry;
    wait_n_sp(2);
    pcs_bus_override    <= c_dominant;
    pcs_bus_override_en <= true;
    wait_n_sp(1);
    pcs_bus_override_en <= false;

    wait_for_transfer_status(c_lost_arb, 50, "T10: lost arbitration");
    AffirmIf(test_id, mac_ser_o.transfer_status = c_lost_arb, "T10: lost arb status");

    ser_frame_valid <= false;
    wait_n_sp(c_intermission_width + c_bus_idle_condition_width + 5);

    ---------------------------------------------------------------------------
    -- Group 6: Overload
    ---------------------------------------------------------------------------
    Log(test_id, "T11: Overload flag", INFO);

    -- Setup: transmit a frame to get into intermission
    transmit_and_verify(
      (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0'),
      "T11 setup"
    );

    -- Transmit another frame, then inject dominant in intermission
    v_fp := get_frame_params((format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0'));
    ser_metadata    <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid <= true;

    wait_for_frame_entry;
    for sp in 1 to v_fp.crc_delimiter + c_ack_slot_offset + 1 loop
      if (sp = v_fp.crc_delimiter + c_ack_slot_offset + 1) then
        pcs_bus_override    <= c_dominant;
        pcs_bus_override_en <= true;
      end if;
      wait_n_sp(1);
    end loop;
    pcs_bus_override_en <= false;

    wait_for_transfer_status(c_transmitted, 200, "T11 setup: frame completion");

    -- Inject dominant during 1st intermission bit
    wait_n_sp(1);
    pcs_bus_override    <= c_dominant;
    pcs_bus_override_en <= true;
    wait_n_sp(1);
    pcs_bus_override_en <= false;

    wait_for_error_flag_entry(50);
    AffirmIf(test_id, fce_o.sending_error_overload_flag = '1', "T11: overload flag triggered");

    ser_frame_valid <= false;
    wait_n_sp(c_error_sequence_width + c_intermission_width + c_bus_idle_condition_width + 5);

    ---------------------------------------------------------------------------
    -- Group 7: Error Delimiter Too Late
    ---------------------------------------------------------------------------
    Log(test_id, "T12: Error delimiter too late", INFO);
    ser_metadata    <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid <= true;

    wait_for_frame_entry;
    wait_n_sp(5);
    pcs_bus_override    <= c_dominant;
    pcs_bus_override_en <= true;
    wait_n_sp(1);
    pcs_bus_override_en <= false;

    wait_for_error_flag_entry(50);
    wait_n_sp(c_error_flag_width);

    -- Inject dominant through entire delimiter
    pcs_bus_override    <= c_dominant;
    pcs_bus_override_en <= true;
    for i in 1 to c_error_delimiter_width loop
      wait_n_sp(1);
    end loop;
    pcs_bus_override_en <= false;

    WaitForClock(clk);
    AffirmIf(test_id, fce_o.error_delimiter_too_late = '1', "T12: error delimiter too late");

    ser_frame_valid <= false;
    wait_n_sp(c_error_sequence_width + c_intermission_width + c_bus_idle_condition_width + 10);

    ---------------------------------------------------------------------------
    -- Group 8: Primary Error
    ---------------------------------------------------------------------------
    Log(test_id, "T13: Primary error during active EF", INFO);
    ser_metadata    <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid <= true;

    wait_for_frame_entry;
    wait_n_sp(5);
    pcs_bus_override    <= c_dominant;
    pcs_bus_override_en <= true;
    wait_n_sp(1);
    pcs_bus_override_en <= false;

    wait_for_error_flag_entry(50);
    wait_n_sp(1);
    WaitForClock(clk);
    AffirmIf(test_id, fce_o.primary_error = '1', "T13: primary error during active EF");

    ser_frame_valid <= false;
    wait_n_sp(c_error_sequence_width + c_intermission_width + c_bus_idle_condition_width + 10);

    ---------------------------------------------------------------------------
    -- Group 9: Counters Unchanged (passive ACK error)
    ---------------------------------------------------------------------------
    Log(test_id, "T14: Counters unchanged (passive ACK error)", INFO);
    fce_error_passive <= '1';
    fce_error_active  <= '0';

    ser_metadata    <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid <= true;

    wait_for_frame_entry;
    wait_for_error_flag_entry(500);

    wait_n_sp(c_error_sequence_width);
    WaitForClock(clk);
    AffirmIf(test_id, fce_o.counters_unchanged = '1', "T14: counters unchanged");

    ser_frame_valid   <= false;
    fce_error_passive <= '0';
    fce_error_active  <= '1';
    wait_n_sp(c_intermission_width + c_suspend_transmission_width + c_bus_idle_condition_width + 5);

    ---------------------------------------------------------------------------
    -- Done
    ---------------------------------------------------------------------------
    WriteBin(fmt_cov);
    EndOfTestReports(ReportAll => TRUE);
    std.env.finish;
    wait;

  end process p_test_ctrl;

end architecture tb;

-- eof
