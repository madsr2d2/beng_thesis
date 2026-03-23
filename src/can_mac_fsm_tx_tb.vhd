--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Black-box testbench for can_mac_fsm_tx. Instantiates the FSM
--                directly with lightweight stand-ins for PCS, serializer, bit
--                stuffer, CRC, and FCE. Covers all 8 FSM states, ACK handling,
--                error detection, arbitration loss, overload, and quiet-phase
--                transitions.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-23  TMYAES:   Initial implementation
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.osvvmcontext;
  use work.pk_can_types.all;

entity can_mac_fsm_tx_tb is
  generic (
    gc_tbtimeout   : time := 50 ms;
    gc_tbclkperiod : time := 10 ns
  );
end entity can_mac_fsm_tx_tb;

architecture tb of can_mac_fsm_tx_tb is

  ---------------------------------------------------------------------------
  -- Constants
  ---------------------------------------------------------------------------
  constant c_sp_interval : integer := 10;

  ---------------------------------------------------------------------------
  -- DUT port signals
  ---------------------------------------------------------------------------
  signal clk_i     : std_logic;
  signal rst_i     : std_logic := '1';
  signal mac_ser_i : t_can_mac_ser_fsm_tx_if_s2m := c_tx_mac_ser_to_fsm_if_reset;
  signal mac_ser_o : t_can_mac_ser_fsm_tx_if_m2s;
  signal pcs_i     : t_can_mac_pcs_tx_if_s2m     := c_pcs_to_mac_if_reset;
  signal pcs_o     : t_can_mac_pcs_tx_if_m2s;
  signal bs_fd_i   : t_can_mac_fsm_bs_tx_if_s2m  := c_can_mac_fsm_bs_tx_if_s2m_reset;
  signal bs_fd_o   : t_can_mac_fsm_bs_tx_if_m2s;
  signal crc_i     : t_can_mac_fsm_crc_tx_if_s2m;
  signal crc_o     : t_can_mac_fsm_crc_tx_if_m2s;
  signal fce_i     : t_can_mac_fce_if_s2m        := c_fce_to_mac_if_reset;
  signal fce_o     : t_can_mac_fce_if_m2s;

  ---------------------------------------------------------------------------
  -- Stand-in control signals
  ---------------------------------------------------------------------------

  -- PCS
  signal pcs_sp_enable       : boolean   := true;
  signal pcs_bus_override    : std_logic := c_recessive;
  signal pcs_bus_override_en : boolean   := false;
  signal sp_strobe           : std_logic := '0';

  -- Serializer
  signal ser_frame_valid  : boolean        := false;
  signal ser_metadata     : t_llc_metadata := c_llc_metadata_reset;
  signal ser_data_pattern : std_logic      := c_recessive;

  -- FCE
  signal fce_error_passive : std_logic := '0';
  signal fce_error_active  : std_logic := '1';
  signal fce_bus_off       : std_logic := '0';

begin

  ---------------------------------------------------------------------------
  -- OSVVM infrastructure
  ---------------------------------------------------------------------------
  CreateClock(clk_i, gc_tbclkperiod);
  CreateReset(rst_i, '1', clk_i, gc_tbclkperiod * 5);

  ---------------------------------------------------------------------------
  -- DUT
  ---------------------------------------------------------------------------
  u_dut : entity work.can_mac_fsm_tx
    port map (
      clk_i              => clk_i,
      rst_i              => rst_i,
      mac_ser_i          => mac_ser_i,
      mac_ser_o          => mac_ser_o,
      pcs_i              => pcs_i,
      pcs_o              => pcs_o,
      bs_fd_i            => bs_fd_i,
      bs_fd_o            => bs_fd_o,
      crc_i              => crc_i,
      crc_o              => crc_o,
      fce_i              => fce_i,
      fce_o              => fce_o
    );

  ---------------------------------------------------------------------------
  -- Stand-ins: PCS (all pcs_i fields driven from one process)
  ---------------------------------------------------------------------------
  p_pcs_sp_counter : process (clk_i) is

    variable sp_count : integer range 0 to c_sp_interval - 1 := 0;

  begin

    if rising_edge(clk_i) then
      sp_strobe <= '0';
      if (rst_i = '1') then
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

  end process p_pcs_sp_counter;

  -- PCS interface driven combinationally from sp_strobe and control signals
  pcs_i.sp           <= sp_strobe;
  pcs_i.ssp          <= '0';
  pcs_i.tdc_delay    <= (others => '0');
  pcs_i.bus_polarity <= pcs_bus_override when pcs_bus_override_en else pcs_o.polarity;

  ---------------------------------------------------------------------------
  -- Stand-ins: Serializer
  ---------------------------------------------------------------------------
  mac_ser_i.valid        <= '1' when ser_frame_valid else '0';
  mac_ser_i.llc_metadata <= ser_metadata;
  mac_ser_i.data         <= ser_data_pattern;

  ---------------------------------------------------------------------------
  -- Stand-ins: Bit stuffer (no stuff bits)
  ---------------------------------------------------------------------------
  bs_fd_i.valid <= '0';
  bs_fd_i.data  <= c_recessive;
  bs_fd_i.sbc   <= (others => '0');

  ---------------------------------------------------------------------------
  -- Stand-ins: CRC (all zeros)
  ---------------------------------------------------------------------------
  crc_i.crc <= (others => '0');

  ---------------------------------------------------------------------------
  -- Stand-ins: FCE
  ---------------------------------------------------------------------------
  fce_i.error_passive_request <= fce_error_passive;
  fce_i.error_active_request  <= fce_error_active;
  fce_i.bus_off               <= fce_bus_off;

  ---------------------------------------------------------------------------
  -- Timeout
  ---------------------------------------------------------------------------
  p_timeout : process is
  begin

    wait for gc_tbtimeout;
    Alert("Testbench timeout", FAILURE);
    std.env.finish;

  end process p_timeout;

  ---------------------------------------------------------------------------
  -- Init
  ---------------------------------------------------------------------------
  p_init : process is
  begin

    SetTestName("can_mac_fsm_tx_tb");
    SetAlertStopCount(ERROR, 5);
    wait;

  end process p_init;

  ---------------------------------------------------------------------------
  -- Main stimulus
  ---------------------------------------------------------------------------
  p_stim : process is

    variable tid : alertlogidtype;
    variable fp  : t_frame_params;

    -- Wait for N SP strobes. Uses sp_strobe transition (delta 1) then
    -- syncs to the next rising edge so the FSM has processed the SP.
    procedure wait_n_sp (
      n : in integer
    ) is
    begin

      for i in 1 to n loop
        wait until sp_strobe = '1';
        wait until rising_edge(clk_i);
      end loop;

    end procedure wait_n_sp;

    -- Wait until fce_o.transmitting pulses (frame entry detected)
    procedure wait_for_frame_entry (
      timeout_sp : in integer := 200
    ) is
    begin

      for i in 1 to timeout_sp * c_sp_interval loop
        wait until rising_edge(clk_i);
        if (fce_o.transmitting = '1') then
          return;
        end if;
      end loop;
      Alert(tid, "wait_for_frame_entry timeout", ERROR);

    end procedure wait_for_frame_entry;

    -- Wait until mac_ser_o.transfer_status matches expected
    procedure wait_for_transfer_status (
      expected   : in std_logic_vector(2 downto 0);
      timeout_sp : in integer := 500;
      msg        : in string
    ) is
    begin

      for i in 1 to timeout_sp * c_sp_interval loop
        wait until rising_edge(clk_i);
        if (mac_ser_o.transfer_status = expected) then
          return;
        end if;
      end loop;
      Alert(tid, "transfer_status timeout: " & msg, ERROR);

    end procedure wait_for_transfer_status;

    -- Wait until fce_o.sending_error_overload_flag pulses
    procedure wait_for_error_flag_entry (
      timeout_sp : in integer := 500
    ) is
    begin

      for i in 1 to timeout_sp * c_sp_interval loop
        wait until rising_edge(clk_i);
        if (fce_o.sending_error_overload_flag = '1') then
          return;
        end if;
      end loop;
      Alert(tid, "wait_for_error_flag_entry timeout", ERROR);

    end procedure wait_for_error_flag_entry;

    -- Transmit a frame with ACK injection and verify success
    procedure transmit_and_verify (
      meta : in t_llc_metadata;
      msg  : in string
    ) is

      variable v_fp       : t_frame_params;
      variable v_ack_sp   : integer;
      variable v_eof_stop : integer;

    begin

      v_fp       := get_frame_params(meta);
      v_ack_sp   := v_fp.crc_delimiter + c_ack_slot_offset;
      v_eof_stop := v_fp.crc_delimiter + c_eof_start_offset + c_eof_field_width;

      ser_metadata    <= meta;
      ser_frame_valid <= true;

      wait_for_frame_entry;

      -- Count SPs until ACK monitoring point, inject dominant, then let FSM
      -- finish the frame naturally. c_transmitted is a single-clock pulse so
      -- wait_for_transfer_status must be polling before it fires.
      for sp in 1 to v_ack_sp + 1 loop
        if (sp = v_ack_sp + 1) then
          pcs_bus_override    <= c_dominant;
          pcs_bus_override_en <= true;
        end if;
        wait_n_sp(1);
      end loop;
      pcs_bus_override_en <= false;

      wait_for_transfer_status(c_transmitted, 200, msg);
      AffirmIf(tid, mac_ser_o.transfer_status = c_transmitted, msg & " transmitted");

      ser_frame_valid <= false;

      -- Wait for intermission + idle
      wait_n_sp(c_intermission_width + 2);

    end procedure transmit_and_verify;

  begin

    wait for 0 ns;
    tid := GetAlertLogID("can_mac_fsm_tx_tb");
    wait until rst_i = '0';
    WaitForClock(clk_i);

    ---------------------------------------------------------------------------
    -- Group 1: Reintegration & Quiet Phase
    ---------------------------------------------------------------------------

    -- Test 1: Dominant resets reintegration counter
    -- After reset, FSM is in s_bus_reintegration. 5 recessive SPs, then
    -- 1 dominant (resets counter), then 11 more recessive -> idle.
    wait_n_sp(5);
    pcs_bus_override    <= c_dominant;
    pcs_bus_override_en <= true;
    wait_n_sp(1);
    pcs_bus_override_en <= false;
    wait_n_sp(c_bus_idle_condition_width);

    ser_metadata    <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid <= true;
    wait_for_frame_entry(50);
    AffirmIf(tid, fce_o.transmitting = '1', "T1: dominant resets reintegration counter");
    ser_frame_valid <= false;

    -- Let the frame fail (no ACK) and recover to idle for next test
    wait_for_transfer_status(c_disturbed, 500, "T1 cleanup");
    wait_n_sp(c_error_sequence_width + c_intermission_width + c_bus_idle_condition_width + 5);

    -- Test 2: Reintegration to idle (11 recessive SPs)
    -- After T1 cleanup the FSM passed through intermission + reintegration
    -- and should now be at idle. Verify by starting a frame.
    ser_metadata    <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid <= true;
    wait_for_frame_entry(50);
    AffirmIf(tid, fce_o.transmitting = '1', "T2: reintegration to idle");
    ser_frame_valid <= false;

    -- Cleanup
    wait_for_transfer_status(c_disturbed, 500, "T2 cleanup");
    wait_n_sp(c_error_sequence_width + c_intermission_width + c_bus_idle_condition_width + 5);

    ---------------------------------------------------------------------------
    -- Group 2: Happy Path Transmission
    ---------------------------------------------------------------------------

    -- Test 3: CB happy path
    transmit_and_verify(
      (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0'),
      "T3: CB happy path"
    );

    -- Test 4: CE happy path
    transmit_and_verify(
      (format => c_llc_fmt_ce, dlc => x"1", ftyp => '0', brs => '0', esi => '0'),
      "T4: CE happy path"
    );

    -- Test 5: FB happy path
    transmit_and_verify(
      (format => c_llc_fmt_fb, dlc => x"1", ftyp => '0', brs => '1', esi => '0'),
      "T5: FB happy path"
    );

    -- Test 6: FE happy path
    transmit_and_verify(
      (format => c_llc_fmt_fe, dlc => x"1", ftyp => '0', brs => '1', esi => '0'),
      "T6: FE happy path"
    );

    ---------------------------------------------------------------------------
    -- Group 3: ACK Error
    ---------------------------------------------------------------------------

    -- Test 7: ACK error (no dominant during ACK)
    fp := get_frame_params((format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0'));
    ser_metadata    <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid <= true;

    wait_for_frame_entry;
    -- No ACK injection - let all SPs pass with loopback (recessive ACK)
    wait_for_transfer_status(c_disturbed, 500, "T7: ACK error");
    AffirmIf(tid, mac_ser_o.transfer_status = c_disturbed, "T7: ACK error detected");

    ser_frame_valid <= false;
    -- Wait for error flag + intermission + idle
    wait_n_sp(c_error_sequence_width + c_intermission_width + c_bus_idle_condition_width + 5);

    ---------------------------------------------------------------------------
    -- Group 4: Bit Error
    ---------------------------------------------------------------------------

    -- Test 8: Bit error -> active error flag
    fp := get_frame_params((format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0'));
    ser_metadata    <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid <= true;

    wait_for_frame_entry;
    -- Wait a few SPs into the frame then inject bit error
    -- At SP 5, inject opposite polarity (dominant when FSM sent recessive data)
    wait_n_sp(5);
    pcs_bus_override    <= c_dominant;
    pcs_bus_override_en <= true;
    wait_n_sp(1);
    pcs_bus_override_en <= false;

    wait_for_error_flag_entry(50);
    AffirmIf(tid, fce_o.sending_error_overload_flag = '1', "T8: bit error -> error flag");
    AffirmIf(tid, mac_ser_o.transfer_status = c_disturbed, "T8: transfer disturbed");

    ser_frame_valid <= false;
    wait_n_sp(c_error_sequence_width + c_intermission_width + c_bus_idle_condition_width + 5);

    -- Test 9: Bit error -> passive error flag
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
    -- Passive error flag: polarity should be recessive during flag phase
    AffirmIf(tid, pcs_o.polarity = c_recessive, "T9: passive EF recessive polarity");
    AffirmIf(tid, mac_ser_o.transfer_status = c_disturbed, "T9: transfer disturbed");

    ser_frame_valid <= false;
    fce_error_passive <= '0';
    fce_error_active  <= '1';

    -- Passive EF + intermission + suspend (8, since was_previous_frame_tx) + idle condition
    wait_n_sp(c_error_sequence_width + c_intermission_width + c_suspend_transmission_width + c_bus_idle_condition_width + 5);

    ---------------------------------------------------------------------------
    -- Group 5: Arbitration Loss
    ---------------------------------------------------------------------------

    -- Test 10: Lost arbitration
    -- ser_data_pattern = c_recessive means all ID bits are recessive.
    -- Inject dominant at the first ID bit SP -> polarity mismatch on arb field -> lost_arb
    ser_data_pattern <= c_recessive;
    ser_metadata     <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid  <= true;

    wait_for_frame_entry;
    -- SP 1 monitors SOF (dominant). SP 2 is where first ID bit is monitored.
    -- The FSM transmits bit 1 (first ID bit) at SP 1. At SP 2, it monitors that bit.
    -- With recessive data, the ID bit is recessive. Inject dominant at SP 2.
    wait_n_sp(2);
    pcs_bus_override    <= c_dominant;
    pcs_bus_override_en <= true;
    wait_n_sp(1);
    pcs_bus_override_en <= false;

    wait_for_transfer_status(c_lost_arb, 50, "T10: lost arbitration");
    AffirmIf(tid, mac_ser_o.transfer_status = c_lost_arb, "T10: lost arb status");

    ser_frame_valid <= false;
    wait_n_sp(c_intermission_width + c_bus_idle_condition_width + 5);

    ---------------------------------------------------------------------------
    -- Group 6: Overload
    ---------------------------------------------------------------------------

    -- Test 11: Dominant during 1st intermission bit -> overload flag
    -- First, run a successful frame to get into intermission
    transmit_and_verify(
      (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0'),
      "T11 setup: frame for intermission"
    );

    -- Now we should be at idle. We need to get to intermission.
    -- Start and complete another frame.
    fp := get_frame_params((format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0'));
    ser_metadata    <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid <= true;

    wait_for_frame_entry;
    -- Inject ACK at correct position, then let frame finish and go to intermission
    for sp in 1 to fp.crc_delimiter + c_ack_slot_offset + 1 loop
      if (sp = fp.crc_delimiter + c_ack_slot_offset + 1) then
        pcs_bus_override    <= c_dominant;
        pcs_bus_override_en <= true;
      end if;
      wait_n_sp(1);
    end loop;
    pcs_bus_override_en <= false;

    -- Wait for frame to complete and enter intermission
    wait_for_transfer_status(c_transmitted, 200, "T11 setup: frame completion");

    -- Wait a few SPs for FSM to enter intermission, then inject dominant
    wait_n_sp(1);
    pcs_bus_override    <= c_dominant;
    pcs_bus_override_en <= true;
    wait_n_sp(1);
    pcs_bus_override_en <= false;

    -- Should trigger overload flag
    wait_for_error_flag_entry(50);
    AffirmIf(tid, fce_o.sending_error_overload_flag = '1', "T11: overload flag triggered");

    ser_frame_valid <= false;
    wait_n_sp(c_error_sequence_width + c_intermission_width + c_bus_idle_condition_width + 5);

    ---------------------------------------------------------------------------
    -- Group 7: Error Delimiter Too Late
    ---------------------------------------------------------------------------

    -- Test 12: error_delimiter_too_late
    -- Trigger a bit error, then during delimiter inject 8 dominant bits
    ser_metadata    <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid <= true;

    wait_for_frame_entry;
    -- Inject bit error at SP 5
    wait_n_sp(5);
    pcs_bus_override    <= c_dominant;
    pcs_bus_override_en <= true;
    wait_n_sp(1);
    pcs_bus_override_en <= false;

    -- Wait for error flag entry
    wait_for_error_flag_entry(50);

    -- Error flag: 6 bits flag. During delimiter (bits 6-13), inject dominant.
    -- Wait through flag field (6 SPs)
    wait_n_sp(c_error_flag_width);

    -- Now in delimiter phase. Inject dominant for 8 consecutive SPs.
    pcs_bus_override    <= c_dominant;
    pcs_bus_override_en <= true;
    -- Wait and check for error_delimiter_too_late pulse
    for i in 1 to c_error_delimiter_width loop
      wait_n_sp(1);
    end loop;
    pcs_bus_override_en <= false;

    -- Pulse fires at delta 1 of the SP clock; WaitForClock lets it propagate.
    WaitForClock(clk_i);
    AffirmIf(tid, fce_o.error_delimiter_too_late = '1', "T12: error delimiter too late");

    ser_frame_valid <= false;
    wait_n_sp(c_error_sequence_width + c_intermission_width + c_bus_idle_condition_width + 10);

    ---------------------------------------------------------------------------
    -- Group 8: Primary Error
    ---------------------------------------------------------------------------

    -- Test 13: primary_error during active error flag
    ser_metadata    <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid <= true;

    wait_for_frame_entry;
    -- Trigger bit error
    wait_n_sp(5);
    pcs_bus_override    <= c_dominant;
    pcs_bus_override_en <= true;
    wait_n_sp(1);
    pcs_bus_override_en <= false;

    wait_for_error_flag_entry(50);

    -- During active error flag, FSM transmits dominant, loopback returns dominant.
    -- primary_error fires when dominant is detected during the flag field.
    wait_n_sp(1);
    WaitForClock(clk_i);
    AffirmIf(tid, fce_o.primary_error = '1', "T13: primary error during active EF");

    ser_frame_valid <= false;
    wait_n_sp(c_error_sequence_width + c_intermission_width + c_bus_idle_condition_width + 10);

    ---------------------------------------------------------------------------
    -- Group 9: Counters Unchanged (passive ACK error)
    ---------------------------------------------------------------------------

    -- Test 14: counters_unchanged for passive ACK error
    fce_error_passive <= '1';
    fce_error_active  <= '0';

    fp := get_frame_params((format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0'));
    ser_metadata    <= (format => c_llc_fmt_cb, dlc => x"1", ftyp => '0', brs => '0', esi => '0');
    ser_frame_valid <= true;

    wait_for_frame_entry;
    -- No ACK injection -> ACK error at delimiter
    -- Wait for error flag entry
    wait_for_error_flag_entry(500);

    -- Passive error flag: all recessive (no dominant seen during flag).
    -- counters_unchanged fires at the last SP of the error sequence.
    wait_n_sp(c_error_sequence_width);
    WaitForClock(clk_i);
    AffirmIf(tid, fce_o.counters_unchanged = '1', "T14: counters unchanged");

    ser_frame_valid   <= false;
    fce_error_passive <= '0';
    fce_error_active  <= '1';
    wait_n_sp(c_intermission_width + c_suspend_transmission_width + c_bus_idle_condition_width + 5);

    ---------------------------------------------------------------------------
    -- Done
    ---------------------------------------------------------------------------
    EndOfTestReports(reportall => TRUE);
    std.env.finish;
    wait;

  end process p_stim;

end architecture tb;

-- eof
