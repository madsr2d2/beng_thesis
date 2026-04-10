--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_mac_tx (ser + fsm + bs + crc).
--                  p_llc_vc           - LLC Avalon-ST source VC (byte driver).
--                  p_pcs_vc           - PCS sink VC (bit-level self-checking, ACK injection).
--                  p_test_ctrl        - Coverage-driven test sequencer with reference model.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-28  TMYAES    [TRIT-4355] Initial implementation
--                2026-04-02  TMYAES    [TRIT-4355] Refactored: full bus stream reference model
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;
  use work.pk_can_tb.all;


library osvvm;
  context osvvm.OsvvmContext;
  use osvvm.ScoreboardPkg_slv.all;
library osvvm_common;
  context osvvm_common.OsvvmCommonContext;

entity can_mac_tx_tb is
  generic (
    gc_TbTimeOut   : time := 500 ms;
    gc_TbClkPeriod : time := 10 ns
  );
end entity can_mac_tx_tb;

architecture tb of can_mac_tx_tb is

  ----------------------------------------------------------------------------
  -- Types
  ----------------------------------------------------------------------------
  type injection_type is (ack, ack_delim, ack_error, error, lost_arb, reactive_overload, error_delimiter_too_late);

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  -- Nominal bit timing (ISO 7.3.2, midpoint of subtype ranges in pk_can_types)
  constant c_sp    : natural := c_sync_seg + (t_nominal_prop_seg'high - t_nominal_prop_seg'low) / 2 + (t_nominal_phase_seg1'high - t_nominal_phase_seg1'low) / 2;
  constant c_bit_time : natural := c_sp + (t_nominal_phase_seg2'high - t_nominal_phase_seg2'low) / 2;

  -- Data phase bit timing (phase_seg2 >= IPT = pipeline_depth + 1 = 4)
  constant c_data_sp    : natural := c_sync_seg + (t_data_prop_seg'high - t_data_prop_seg'low) / 2 + (t_data_phase_seg1'high - t_data_phase_seg1'low) / 2;
  constant c_data_ssp    : natural := c_data_sp / 2; -- Just some position before the SP in the bit time
  constant c_data_bit_time : natural := c_data_sp + t_data_phase_seg2'high;

  -- Coverage constants
  constant c_bin_at_least  : natural := 5;
  constant c_min_err_pos   : natural := 13;  -- Below 13 is lost_arb region (SOF + 11-bit ID + RTR = 13) 
  constant c_max_err_pos   : natural := 580; -- largest FE ack_pos - 2 with worst-case stuff bits (~580)
  constant c_pos_bin_num   : natural := 50;

  -- PCS VC subtypes (0 = activate SP strobe, 1..7 = injection types)
  constant c_pcs_active               : natural := 0;
  constant c_inj_ack                  : natural := 1;
  constant c_inj_ack_error            : natural := 2;
  constant c_inj_error                : natural := 3;
  constant c_inj_lost_arb             : natural := 4;
  constant c_inj_reactive_overload    : natural := 5;
  constant c_inj_error_delim_too_late : natural := 6;
  constant c_inj_ack_delim            : natural := 7;

  signal inj_type : injection_type;

  -- FCE state coverage bins
  constant c_fce_active  : natural := 0;
  constant c_fce_passive : natural := 1;

  -- FCE latch bit positions (pulse events from fce_o)
  constant c_fce_successful_transfer  : natural := 0;
  constant c_fce_error                : natural := 1;
  constant c_fce_primary_error        : natural := 2;
  constant c_fce_counters_unchanged   : natural := 3;
  constant c_fce_error_delim_too_late : natural := 4;
  constant c_fce_latch_width          : natural := 5;

  -- Transaction record data width
  constant c_rec_width : natural := 16;
  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal clk   : std_logic;
  signal reset : std_logic;

  -- DUT interface
  signal llc_i : t_can_llc_mac_tx_if_s2d;
  signal llc_o : t_can_llc_mac_tx_if_d2s;
  signal pcs_i : t_can_mac_pcs_if_s2m := c_pcs_to_mac_if_reset;
  signal pcs_o : t_can_mac_pcs_if_m2s;
  signal fce_i : t_can_mac_fce_if_s2m    := c_fce_to_mac_if_reset;
  signal fce_o : t_can_mac_fce_if_m2s;

  signal bus_override    : std_logic := c_recessive;
  signal bus_override_en : boolean   := false;
  signal status_latch    : std_logic_vector(2 downto 0) := c_ongoing;
  signal fce_latch       : std_logic_vector(c_fce_latch_width - 1 downto 0) := (others => '0');

  -- OSVVM signals
  shared variable RV  : RandomPType;
  signal test_id         : AlertLogIDType;
  signal reset_check_id  : AlertLogIDType;
  signal status_check_id : AlertLogIDType;
  signal stream_check_id : AlertLogIDType;
  signal fce_check_id    : AlertLogIDType;
  signal ide_cov      : CoverageIDType;
  signal fdf_cov      : CoverageIDType;
  signal ftyp_cov      : CoverageIDType;
  signal esi_cov      : CoverageIDType;
  signal brs_cov      : CoverageIDType;
  signal dlc_cov      : CoverageIDType;
  signal inj_cov      : CoverageIDType;
  signal pos_cov      : CoverageIDType;
  signal fce_cov      : CoverageIDType;
  signal init_barrier : std_logic := '0';

  signal llc_rec : StreamRecType(
    DataToModel    (c_rec_width - 1 downto 0),
    ParamToModel   (c_rec_width - 1 downto 0),
    DataFromModel  (c_rec_width - 1 downto 0),
    ParamFromModel (c_rec_width - 1 downto 0)
  );
  signal pcs_rec : StreamRecType(
    DataToModel    (c_rec_width - 1 downto 0),
    ParamToModel   (c_rec_width - 1 downto 0),
    DataFromModel  (c_rec_width - 1 downto 0),
    ParamFromModel (c_rec_width - 1 downto 0)
  );
  signal fce_rec : StreamRecType(
    DataToModel    (c_rec_width - 1 downto 0),
    ParamToModel   (c_rec_width - 1 downto 0),
    DataFromModel  (c_rec_width - 1 downto 0),
    ParamFromModel (c_rec_width - 1 downto 0)
  );

  ----------------------------------------------------------------------------
  -- Random frame and expected bus stream generator
  ----------------------------------------------------------------------------
  procedure gen_frame (
    variable frame       : out t_llc_frame;
    variable metadata    : out t_llc_metadata;
    variable last_byte   : out natural;
    variable stream      : out t_bus_stream;
    variable error_state : out natural
  ) is
    variable is_passive : boolean;
  begin
    -- Generate random frame bytes
    for i in frame'range loop
      frame(i) := RV.RandSlv(8);
    end loop;
    -- Coverage-driven generation of configuration bytes
    error_state := GetRandPoint(fce_cov);
    is_passive  := error_state = c_fce_passive;
    frame(0)(c_llc_frame_ide) := std_logic(to_unsigned(GetRandPoint(ide_cov), 1)(0));
    frame(0)(c_llc_frame_fdf) := std_logic(to_unsigned(GetRandPoint(fdf_cov), 1)(0));
    frame(0)(c_llc_frame_esi) := std_logic(to_unsigned(GetRandPoint(esi_cov), 1)(0));
    frame(0)(c_llc_frame_brs) := std_logic(to_unsigned(GetRandPoint(brs_cov), 1)(0));
    frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end) := std_logic_vector(to_unsigned(GetRandPoint(dlc_cov), 4));
    -- Get metadata and expected bus stream for the generated frame
    metadata  := extract_metadata(frame(0), frame(1));
    last_byte := c_llc_frame_data_byte + dlc_to_data_length(to_integer(unsigned(metadata.dlc)), metadata.fdf) - 1;
    stream    := build_bus_stream(frame, metadata, is_passive);
  end procedure gen_frame;
  ----------------------------------------------------------------------------

  ----------------------------------------------------------------------------
  -- Error/overload helper procedures
  ----------------------------------------------------------------------------
  procedure fill (stream : inout t_bus_stream; idx : inout natural; count : in natural; pol : in std_logic) is
  begin
    for i in 0 to count - 1 loop
      stream.bits(idx) := pol;
      idx := idx + 1;
    end loop;
  end procedure fill;

  procedure add_flag_and_delim (stream : inout t_bus_stream; idx : inout natural; flag_pol : in std_logic) is
  begin
    fill(stream, idx, c_error_flag_width, flag_pol);
    fill(stream, idx, c_error_delimiter_width, c_recessive);
  end procedure add_flag_and_delim;

  procedure add_ifs (stream : inout t_bus_stream; idx : inout natural; is_passive : in boolean) is
  begin
    fill(stream, idx, c_intermission_width, c_recessive);
    if (is_passive) then
      fill(stream, idx, c_suspend_transmission_width, c_recessive);
    end if;
  end procedure add_ifs;

  procedure clamp_metadata (stream : inout t_bus_stream; inject_pos : in natural) is
  begin
    if (stream.fdf_pos >= 0 and inject_pos < stream.fdf_pos) then
      stream.fdf_pos := -1;
    end if;
    if (stream.data_phase_start >= 0 and inject_pos < stream.data_phase_start) then
      stream.data_phase_start := -1;
      stream.data_phase_end   := -1;
    elsif (stream.data_phase_start >= 0 and inject_pos <= stream.data_phase_end) then
      stream.data_phase_end := inject_pos;
    end if;
  end procedure clamp_metadata;

  procedure truncate_error (stream : inout t_bus_stream; inject_pos : in natural; is_passive : in boolean := false) is
    variable idx      : natural   := inject_pos;
    variable flag_pol : std_logic := c_dominant;
  begin
    if (is_passive) then
      flag_pol := c_recessive;
    end if;
    clamp_metadata(stream, inject_pos);
    add_flag_and_delim(stream, idx, flag_pol);
    add_ifs(stream, idx, is_passive);
    stream.len := idx;
  end procedure truncate_error;

  procedure truncate_reactive_overload (stream : inout t_bus_stream; inject_pos : in natural; is_passive : in boolean := false) is
    variable idx      : natural   := inject_pos + 1;
    variable flag_pol : std_logic := c_dominant;
  begin
    if (is_passive) then
      flag_pol := c_recessive;
    end if;
    clamp_metadata(stream, inject_pos);
    add_flag_and_delim(stream, idx, flag_pol);
    add_flag_and_delim(stream, idx, c_dominant);
    add_ifs(stream, idx, is_passive);
    stream.len := idx;
  end procedure truncate_reactive_overload;
  ----------------------------------------------------------------------------

begin

  ----------------------------------------------------------------------------
  -- Infrastructure
  ----------------------------------------------------------------------------
  -- Clock and reset
  CreateClock(clk, gc_TbClkPeriod);
  CreateReset(reset, '1', clk, gc_TbClkPeriod * 10);

  -- Timeout process
  p_timeout : process is
  begin
    wait for gc_TbTimeOut;
    assert false report "ERROR TEST FAILED, due to time out" severity error;
    std.env.stop(1);
  end process p_timeout;

  -- Test initialization
  p_init : process is
    variable v_test_id    : AlertLogIDType;
    variable v_reset_id   : AlertLogIDType;
    variable v_status_id  : AlertLogIDType;
    variable v_stream_id  : AlertLogIDType;
    variable v_fce_chk_id : AlertLogIDType;
    variable v_ide_cov    : CoverageIDType;
    variable v_fdf_cov    : CoverageIDType;
    variable v_ftyp_cov   : CoverageIDType;
    variable v_esi_cov    : CoverageIDType;
    variable v_brs_cov    : CoverageIDType;
    variable v_dlc_cov    : CoverageIDType;
    variable v_inj_cov    : CoverageIDType;
    variable v_pos_cov    : CoverageIDType;
    variable v_fce_cov    : CoverageIDType;
  begin
    SetAlertStopCount(ERROR, 1);
    v_test_id         := NewID("can_mac_tx");
    v_reset_id        := NewID("Reset check", v_test_id);
    v_status_id       := NewID("Transfer Status check", v_test_id);
    v_stream_id       := NewID("Bus stream check", v_test_id);
    v_fce_chk_id      := NewID("FCE event check", v_test_id);
    v_ide_cov         := NewID("IDE Coverage", v_test_id);
    v_fdf_cov         := NewID("FDF Coverage", v_test_id);
    v_ftyp_cov        := NewID("FTYP Coverage", v_test_id);
    v_esi_cov         := NewID("ESI Coverage", v_test_id);
    v_brs_cov         := NewID("BRS Coverage", v_test_id);
    v_dlc_cov         := NewID("DLC Coverage", v_test_id);
    v_inj_cov         := NewID("Error Injection Coverage", v_test_id);
    v_pos_cov         := NewID("Error Injection Position Coverage", v_test_id);
    v_fce_cov         := NewID("FCE State Coverage", v_test_id);
    pcs_rec.BurstFifo <= NewID("PCS VC Burst fifo");

    AddBins(v_ide_cov, GenBin(c_bin_at_least, (0, 1)));
    AddBins(v_fdf_cov, GenBin(c_bin_at_least, (0, 1)));
    AddBins(v_ftyp_cov, GenBin(c_bin_at_least, (0, 1)));
    AddBins(v_esi_cov, GenBin(c_bin_at_least, (0, 1)));
    AddBins(v_brs_cov, GenBin(c_bin_at_least, (0, 1)));
    AddBins(v_dlc_cov, GenBin(c_bin_at_least, 0, c_dlc_max, c_dlc_max + 1));
    AddBins(v_inj_cov, GenBin(c_bin_at_least, (c_inj_ack, c_inj_ack_delim, c_inj_ack_error, c_inj_error, c_inj_lost_arb, c_inj_reactive_overload, c_inj_error_delim_too_late)));
    AddBins(v_pos_cov, GenBin(c_bin_at_least, c_min_err_pos, c_max_err_pos, c_pos_bin_num));
    AddBins(v_fce_cov, GenBin(c_bin_at_least, (c_fce_active, c_fce_passive)));

    test_id         <= v_test_id;
    reset_check_id  <= v_reset_id;
    status_check_id <= v_status_id;
    stream_check_id <= v_stream_id;
    fce_check_id    <= v_fce_chk_id;
    ide_cov         <= v_ide_cov;
    fdf_cov         <= v_fdf_cov;
    ftyp_cov        <= v_ftyp_cov;
    esi_cov         <= v_esi_cov;
    brs_cov         <= v_brs_cov;
    dlc_cov         <= v_dlc_cov;
    inj_cov         <= v_inj_cov;
    pos_cov         <= v_pos_cov;
    fce_cov         <= v_fce_cov;

    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  ----------------------------------------------------------------------------
  -- DUT
  ----------------------------------------------------------------------------
  u_dut : entity work.can_mac_tx
    port map (
      clk   => clk,
      rst   => reset,
      llc_i => llc_i,
      llc_o => llc_o,
      pcs_i => pcs_i,
      pcs_o => pcs_o,
      fce_i => fce_i,
      fce_o => fce_o
    );

  ----------------------------------------------------------------------------
  -- Transfer status latch (Used for status check in LLC VC)
  ----------------------------------------------------------------------------
  p_status_latch : process (clk) is
  begin
    if rising_edge(clk) then
      if (reset = '1' or llc_i.avalon_st_source.startofpacket = '1') then
        status_latch <= llc_o.transfer_status;
      else
        status_latch <= llc_o.transfer_status when llc_o.transfer_status /= c_ongoing;
      end if;
    end if;
  end process p_status_latch;

  ----------------------------------------------------------------------------
  -- FCE event latch (Used for checks in FCE VC)
  ----------------------------------------------------------------------------
  p_fce_latch : process (clk) is
  begin
    if rising_edge(clk) then
      if (reset = '1' or llc_i.avalon_st_source.startofpacket = '1') then
        fce_latch <= (others => '0');
      else
        fce_latch(c_fce_successful_transfer)  <= fce_o.successful_transfer when fce_o.successful_transfer;
        fce_latch(c_fce_error)                <= fce_o.error when fce_o.error;
        fce_latch(c_fce_primary_error)        <= fce_o.primary_error when fce_o.primary_error ;
        fce_latch(c_fce_counters_unchanged)   <= fce_o.counters_unchanged when fce_o.counters_unchanged;
        fce_latch(c_fce_error_delim_too_late) <= fce_o.error_delimiter_too_late when fce_o.error_delimiter_too_late;
      end if;
    end if;
  end process p_fce_latch;

  ----------------------------------------------------------------------------
  -- FCE Verification Component
  ----------------------------------------------------------------------------
  p_fce_vc : process is
  begin
    -- Node error state defaults
    fce_i.error_passive_request <= '0';
    fce_i.error_active_request  <= '1';
    WaitForBarrier(init_barrier);
    fce_vc_loop : loop
      WaitForTransaction(fce_rec.Rdy, fce_rec.Ack);
      case fce_rec.Operation is
        when SEND =>
          -- Set node error state
          fce_i.error_passive_request <= fce_rec.DataToModel(0);
          fce_i.error_active_request  <= fce_rec.DataToModel(1);
        when CHECK =>
          wait until rising_edge(clk);
          AffirmIfEqual(fce_check_id, fce_latch, std_logic_vector(fce_rec.DataToModel(c_fce_latch_width - 1 downto 0)), "FCE events");
        when others => null;
      end case;
    end loop;
  end process p_fce_vc;

  ----------------------------------------------------------------------------
  -- LLC Verification Component
  ----------------------------------------------------------------------------
  p_llc_vc : process is
  begin
    WaitForBarrier(init_barrier);
    llc_vc_loop : loop
      WaitForTransaction(llc_rec.Rdy, llc_rec.Ack);
      case llc_rec.Operation is
        when SEND =>
          -- Avalon-ST send
          llc_i.avalon_st_source.valid         <= '1';
          llc_i.avalon_st_source.data          <= SafeResize(std_logic_vector(llc_rec.DataToModel), c_byte_width);
          llc_i.avalon_st_source.startofpacket <= llc_rec.ParamToModel(1);
          llc_i.avalon_st_source.endofpacket   <= llc_rec.ParamToModel(0);
          wait until rising_edge(clk) and llc_o.avalon_st_sink.ready = '1';
          llc_i.avalon_st_source.valid <= '0';
        when CHECK =>
          -- Transfer status check
          wait until rising_edge(clk);
          AffirmIfEqual(status_check_id, status_latch, std_logic_vector(llc_rec.DataToModel(2 downto 0)), "Transfer status");
        when others => null;
      end case;
    end loop;
  end process p_llc_vc;

  ----------------------------------------------------------------------------
  -- PCS Verification Component
  ----------------------------------------------------------------------------
  p_pcs_vc : process is
    variable v_bus_idx             : natural;
    variable v_inject_pos          : natural;
    variable v_subtype             : natural;
    variable v_expected            : std_logic_vector(2 downto 0);
    variable v_sp_active           : boolean := false;
    variable v_checking            : boolean := false;
    variable v_burst_check_pending : boolean := false;
    variable v_tq_count            : natural range 0 to c_bit_time - 1 := 0;

    -- Bit timing model (bus delay = 0, TDC delay testing in can_pcs_tx_tb)
    variable v_active_bt  : natural := c_bit_time;
    variable v_active_sp  : natural := c_sp;
    variable v_ssp_armed  : boolean := false;

    --------------------------------------------------------------------------
    -- Arm/disarm bus override at programmed position(s)
    --------------------------------------------------------------------------
    procedure arm_bus_injection is
    begin
      -- Primary injection position
      if (v_bus_idx = v_inject_pos) then
        if (v_subtype = c_inj_ack or v_subtype = c_inj_ack_delim or v_subtype = c_inj_lost_arb) then
          bus_override <= c_dominant;
        end if;
        if (v_subtype /= c_inj_ack_error) then
          bus_override_en <= true;
        end if;
      elsif (v_bus_idx = v_inject_pos + 1) then
        bus_override_en <= false;
      end if;
      -- Secondary injection: reactive overload (dominant at last error delimiter bit)
      if (v_subtype = c_inj_reactive_overload) then
        if (v_bus_idx = v_inject_pos + c_error_sequence_width) then
          bus_override    <= c_dominant;
          bus_override_en <= true;
        elsif (v_bus_idx = v_inject_pos + c_error_sequence_width + 1) then
          bus_override_en <= false;
        end if;
      -- Secondary injection: error delimiter too late (dominant during full delimiter)
      elsif (v_subtype = c_inj_error_delim_too_late) then
        if (v_bus_idx = v_inject_pos + 1 + c_error_flag_width) then
          bus_override    <= c_dominant;
          bus_override_en <= true;
        elsif (v_bus_idx = v_inject_pos + 1 + c_error_flag_width + c_error_delimiter_width) then
          bus_override_en <= false;
        end if;
      end if;
    end procedure arm_bus_injection;

  begin
    pcs_i.sample_point           <= '0';
    pcs_i.secondary_sample_point <= '0';
    pcs_i.tdc_delay    <= (others => '0');
    pcs_i.bus_polarity <= c_recessive;
    bus_override_en    <= false;
    WaitForBarrier(init_barrier);
    FinishTransaction(pcs_rec.Ack);

    pcs_vc_loop : loop
      wait until rising_edge(clk);

      --------------------------------------------------------------------------
      -- Bit time model
      --------------------------------------------------------------------------
      pcs_i.sample_point           <= '0';
      pcs_i.secondary_sample_point <= '0';

      if (v_sp_active) then
        -- Latch bit timing at bit boundary from DUT data rate signal
        if (v_tq_count = 0) then
          if (pcs_o.use_data_rate = '1') then
            v_active_bt := c_data_bit_time;
            v_active_sp := c_data_sp;
          else
            v_active_bt := c_bit_time;
            v_active_sp := c_sp;
            v_ssp_armed := false;
          end if;
        end if;

        -- Zero-delay loopback
        pcs_i.bus_polarity <= pcs_o.polarity;

        -- ACK / arb-loss / ack-delim override (persistent for one bit time)
        if (bus_override_en and not (v_subtype = c_inj_error or v_subtype = c_inj_reactive_overload or v_subtype = c_inj_error_delim_too_late)) then
          pcs_i.bus_polarity <= bus_override;
        end if;

        -- Sample point strobe
        if (v_tq_count = v_active_sp) then
          if (bus_override_en and (v_subtype = c_inj_error or v_subtype = c_inj_reactive_overload or v_subtype = c_inj_error_delim_too_late)) then
            pcs_i.bus_polarity <= not pcs_o.polarity;
          end if;
          pcs_i.sample_point <= '1';
          if (pcs_o.use_data_rate = '1') then
            v_ssp_armed := true;
          end if;
        end if;

        -- Secondary sample point strobe (data phase only, ISO 7.3.4).
        -- Suppress first data-phase SP so polarity_history(0) is populated.
        if (pcs_o.use_data_rate = '1' and v_tq_count = c_data_ssp and v_ssp_armed) then
          if (bus_override_en and (v_subtype = c_inj_error or v_subtype = c_inj_reactive_overload or v_subtype = c_inj_error_delim_too_late)) then
            pcs_i.bus_polarity <= not pcs_o.polarity;
          end if;
          pcs_i.secondary_sample_point <= '1';
          pcs_i.tdc_delay <= (others => '0');
        end if;

        -- Advance TQ counter (wraps at active bit time)
        if (v_tq_count = v_active_bt - 1) then
          v_tq_count := 0;
        else
          v_tq_count := v_tq_count + 1;
        end if;
      end if;

      --------------------------------------------------------------------------
      -- Bit checking: pop-and-compare at each bit boundary.
      -- Gate on valid='1' for the first bit; v_bus_idx > 0 keeps checking
      -- through IFS where the DUT deasserts valid.
      --------------------------------------------------------------------------
      if (v_checking and v_tq_count = 0 and (v_bus_idx > 0 or pcs_o.valid = '1')) then
        v_expected := Pop(pcs_rec.BurstFifo);
        AffirmIfEqual(stream_check_id, pcs_o.polarity, v_expected(0), "polarity");
        AffirmIfEqual(stream_check_id, pcs_o.use_data_rate, v_expected(1), "use_data_rate");
        AffirmIfEqual(stream_check_id, pcs_o.start_tdc, v_expected(2), "start_tdc");
        arm_bus_injection;
        v_bus_idx := v_bus_idx + 1;
        -- Stream done: stop checking, unblock pending CHECK_BURST
        if (Empty(pcs_rec.BurstFifo)) then
          v_checking := false;
          if (v_burst_check_pending) then
            v_burst_check_pending := false;
            FinishTransaction(pcs_rec.Ack);
          end if;
        end if;
      end if;

      --------------------------------------------------------------------------
      -- Transaction dispatch
      --------------------------------------------------------------------------
      if TransactionPending(pcs_rec.Rdy, pcs_rec.Ack) then
        case pcs_rec.Operation is
          when SEND_ASYNC =>
            v_subtype := to_integer(unsigned(pcs_rec.DataToModel));
            if (v_subtype = c_pcs_active) then
              v_sp_active := true;
              v_tq_count  := 0;
              v_bus_idx   := 0;
              v_active_bt := c_bit_time;
              v_active_sp  := c_sp;
              v_ssp_armed  := false;
              bus_override_en <= false;
              pcs_i.tdc_delay <= (others => '0');
            else
              v_inject_pos := to_integer(unsigned(pcs_rec.ParamToModel));
              v_checking   := true;
            end if;
            FinishTransaction(pcs_rec.Ack);
          when CHECK_BURST =>
            if (v_checking) then
              v_burst_check_pending := true;
            else
              FinishTransaction(pcs_rec.Ack);
            end if;
          when others =>
            FinishTransaction(pcs_rec.Ack);
        end case;
      end if;
    end loop;
  end process p_pcs_vc;

  ----------------------------------------------------------------------------
  -- Test sequencer
  ----------------------------------------------------------------------------
  p_test_ctrl : process is
    variable v_frame       : t_llc_frame;
    variable v_metadata    : t_llc_metadata;
    variable v_last_byte   : natural;
    variable v_stream      : t_bus_stream;
    variable v_error_state : natural;
    variable v_frame_count : natural := 0;
    variable v_inj_type    : natural;
    variable v_inj_pos     : natural;
    variable v_exp_status  : std_logic_vector(2 downto 0);
    variable v_exp_fce     : std_logic_vector(c_fce_latch_width - 1 downto 0);

    --------------------------------------------------------------------------
    -- Test 1: Verify all DUT outputs are in reset state
    --------------------------------------------------------------------------
    procedure test_reset is
    begin
      Print("--------------------------------------------------------------------------");
      Print("Test 1: Reset");
      Print("--------------------------------------------------------------------------");
      AffirmIf(reset_check_id, pcs_o = c_mac_to_pcs_if_reset, "pcs_o not reset correctly");
      AffirmIf(reset_check_id, fce_o = c_mac_to_fce_if_reset, "fce_o not reset correctly");
      AffirmIf(reset_check_id, llc_o = c_mac_to_llc_if_reset, "llc_o not reset correctly");
    end procedure test_reset;

    --------------------------------------------------------------------------
    -- Test 2: Verify FSM stays silent during 11-SP bus reintegration
    --------------------------------------------------------------------------
    procedure test_bus_reintegration is
    begin
      Print("--------------------------------------------------------------------------");
      Print("Test 2: Bus reintegration");
      Print("--------------------------------------------------------------------------");
      SendAsync(pcs_rec, std_logic_vector(to_unsigned(c_pcs_active, c_rec_width)));
      for sp_idx in 0 to c_bus_idle_condition_width - 2 loop
        wait until rising_edge(clk) and pcs_i.sample_point = '1';
        AffirmIf(reset_check_id, pcs_o.valid = '0',
                 "Reintegration: valid=0 at SP " & to_string(sp_idx));
      end loop;
      wait until rising_edge(clk) and pcs_i.sample_point = '1';
      AffirmIf(reset_check_id, pcs_o.valid = '0',
               "Bus idle: valid=0 (no pending frame)");
    end procedure test_bus_reintegration;

    --------------------------------------------------------------------------
    -- Injection preparation: one procedure per scenario.
    -- Each sets v_inj_pos, v_exp_status, v_exp_fce and optionally
    -- truncates v_stream to model the error/overload tail.
    --------------------------------------------------------------------------
    procedure prepare_ack is
    begin
      -- Inject dominant one bit early to absorb TB arm-to-latch delay
      v_inj_type   := c_inj_ack;
      v_inj_pos    := v_stream.ack_pos - 1;
      v_exp_status := c_transmitted;
      v_exp_fce(c_fce_successful_transfer) := '1';
      inj_type <= ack;
    end procedure prepare_ack;

    procedure prepare_ack_delim is
    begin
      -- FD-only: dominant ACK at s_ack bc=1 (ISO 6.6.11.6)
      v_inj_type   := c_inj_ack_delim;
      v_inj_pos    := v_stream.ack_pos;
      v_exp_status := c_transmitted;
      v_exp_fce(c_fce_successful_transfer) := '1';
      inj_type <= ack_delim;
    end procedure prepare_ack_delim;

    procedure prepare_ack_error is
    begin
      v_inj_type   := c_inj_ack_error;
      v_inj_pos    := v_stream.ack_pos;
      v_exp_status := c_disturbed;
      v_exp_fce(c_fce_error) := '1';
      inj_type <= ack_error;
      if (v_error_state = c_fce_passive) then
        -- ISO 8.1.4.2 rule c) Exception 1: counters_unchanged
        v_exp_fce(c_fce_counters_unchanged) := '1';
      else
        v_exp_fce(c_fce_primary_error) := '1';
      end if;
      -- Error detected at first EOF bit (CC: slot+delim=2, FD: slot+delim=3)
      if (v_metadata.fdf = '1') then
        truncate_error(v_stream, v_stream.ack_pos + 3, v_error_state = c_fce_passive);
      else
        truncate_error(v_stream, v_stream.ack_pos + 2, v_error_state = c_fce_passive);
      end if;
    end procedure prepare_ack_error;

    procedure prepare_bit_error is
      variable v_candidate : natural;
    begin
      -- Coverage-driven position within [arb_end, ack_pos-2]
      -- Arb field excluded (ISO 6.6.21.2.a Exception 1)
      v_inj_type := c_inj_error;
      v_inj_pos  := RV.RandInt(v_stream.arb_end, v_stream.ack_pos - 2);
      inj_type <= error;
      for attempt in 0 to 9 loop
        v_candidate := GetRandPoint(pos_cov);
        if (v_candidate >= v_stream.arb_end and v_candidate <= v_stream.ack_pos - 2) then
          v_inj_pos := v_candidate;
          exit;
        end if;
      end loop;
      -- Skip first data-phase bit (SSP warmup suppresses error detection)
      if (v_stream.data_phase_start >= 0 and v_inj_pos = v_stream.data_phase_start) then
        v_inj_pos := v_inj_pos + 1;
      end if;
      v_exp_status := c_disturbed;
      v_exp_fce(c_fce_error) := '1';
      if not (v_error_state = c_fce_passive) then
        v_exp_fce(c_fce_primary_error) := '1';
      end if;
      truncate_error(v_stream, v_inj_pos + 1, v_error_state = c_fce_passive);
    end procedure prepare_bit_error;

    procedure prepare_lost_arb is
    begin
      v_inj_type   := c_inj_lost_arb;
      v_exp_status := c_lost_arb;
      -- Force recessive MSB in first ID byte so arbiter loses immediately
      v_frame(2)(c_byte_width - 1) := c_recessive;
      v_metadata := extract_metadata(v_frame(0), v_frame(1));
      v_stream   := build_bus_stream(v_frame, v_metadata, v_error_state = c_fce_passive);
      v_inj_pos               := 1;
      v_stream.len             := v_inj_pos + 1;
      v_stream.fdf_pos         := -1;
      v_stream.data_phase_start := -1;
      v_stream.data_phase_end  := -1;
      inj_type <= lost_arb;
    end procedure prepare_lost_arb;

    procedure prepare_reactive_overload is
    begin
      -- Bit error + dominant at last error delimiter bit triggers overload
      v_inj_type   := c_inj_reactive_overload;
      v_inj_pos    := RV.RandInt(v_stream.arb_end, v_stream.ack_pos - 2);
      v_exp_status := c_disturbed;
      v_exp_fce(c_fce_error) := '1';
      inj_type <= reactive_overload;
      if not (v_error_state = c_fce_passive) then
        v_exp_fce(c_fce_primary_error) := '1';
      end if;
      truncate_reactive_overload(v_stream, v_inj_pos, v_error_state = c_fce_passive);
    end procedure prepare_reactive_overload;

    procedure prepare_error_delim_too_late is
    begin
      -- Bit error + 8 dominant during error delimiter
      v_inj_type   := c_inj_error_delim_too_late;
      v_inj_pos    := RV.RandInt(v_stream.arb_end, v_stream.ack_pos - 2);
      v_exp_status := c_disturbed;
      v_exp_fce(c_fce_error) := '1';
      v_exp_fce(c_fce_error_delim_too_late) := '1';
      inj_type <= error_delimiter_too_late;
      if not (v_error_state = c_fce_passive) then
        v_exp_fce(c_fce_primary_error) := '1';
      end if;
      truncate_reactive_overload(v_stream, v_inj_pos, v_error_state = c_fce_passive);
    end procedure prepare_error_delim_too_late;

    --------------------------------------------------------------------------
    -- Submit frame to DUT and verify all three outputs
    --------------------------------------------------------------------------
    procedure submit_and_verify is
      variable v_entry    : std_logic_vector(2 downto 0);
      variable v_fdf      : integer := v_stream.fdf_pos;
      variable v_dp_start : integer := v_stream.data_phase_start;
      variable v_dp_end   : integer := v_stream.data_phase_end;
    begin
      -- Clamp data-phase bounds for injection types that truncate the stream
      case v_inj_type is
        when c_inj_lost_arb =>
          v_fdf      := -1;
          v_dp_start := -1;
          v_dp_end   := -1;
        when c_inj_error | c_inj_reactive_overload | c_inj_error_delim_too_late =>
          if (v_fdf >= 0 and v_inj_pos < v_fdf) then
            v_fdf := -1;
          end if;
          if (v_dp_start >= 0 and v_inj_pos < v_dp_start) then
            v_dp_start := -1;
            v_dp_end   := -1;
          elsif (v_dp_start >= 0 and v_inj_pos <= v_dp_end) then
            v_dp_end := v_inj_pos;
          end if;
        when others =>
          null;
      end case;
      -- Configure PCS VC: reset bit-time model, then arm injection
      SendAsync(pcs_rec, std_logic_vector(to_unsigned(c_pcs_active, c_rec_width)));
      SendAsync(pcs_rec, std_logic_vector(to_unsigned(v_inj_type, c_rec_width)),
                         std_logic_vector(to_unsigned(v_inj_pos, c_rec_width)));
      -- Push expected bus stream: (2)=start_tdc, (1)=use_data_rate, (0)=polarity
      for i in 0 to v_stream.len - 1 loop
        v_entry(0) := v_stream.bits(i);
        if (v_dp_start >= 0 and i >= v_dp_start and i <= v_dp_end) then
          v_entry(1) := '1';
        else
          v_entry(1) := '0';
        end if;
        if (v_fdf >= 0 and i = v_fdf) then
          v_entry(2) := '1';
        else
          v_entry(2) := '0';
        end if;
        Push(pcs_rec.BurstFifo, v_entry);
      end loop;
      -- Drive frame bytes through LLC VC
      for i in 0 to v_last_byte loop
        if (i = 0) then
          Send(llc_rec, v_frame(i), "10");
        else
          Send(llc_rec, v_frame(i), "00");
        end if;
      end loop;
      -- Verify: bus stream, transfer status, FCE events
      CheckBurst(pcs_rec, GetFifoCount(pcs_rec.BurstFifo));
      Check(llc_rec, v_exp_status);
      Check(fce_rec, std_logic_vector(resize(unsigned(v_exp_fce), c_rec_width)));
    end procedure submit_and_verify;

    --------------------------------------------------------------------------
    -- Helper: generate frame and set FCE error state
    --------------------------------------------------------------------------
    procedure next_frame is
    begin
      v_frame_count := v_frame_count + 1;
      gen_frame(v_frame, v_metadata, v_last_byte, v_stream, v_error_state);
      if (v_error_state = c_fce_passive) then
        Send(fce_rec, "01");
      else
        Send(fce_rec, "10");
      end if;
    end procedure next_frame;

    --------------------------------------------------------------------------
    -- Test 3: Normal transmission - cover all frame format combinations
    --------------------------------------------------------------------------
    procedure test_normal is
    begin
      Print("--------------------------------------------------------------------------");
      Print("Test 3: Normal Usage (ACK'ed transmissions)");
      Print("--------------------------------------------------------------------------");
      while not (IsCovered(ide_cov) and IsCovered(fdf_cov) and IsCovered(esi_cov) and IsCovered(brs_cov) and IsCovered(ftyp_cov) and IsCovered(dlc_cov) and IsCovered(fce_cov)) loop
        next_frame;
        v_exp_fce := (others => '0');
        -- FD frames randomly use ACK-delimiter slot (ISO 6.6.11.6)
        if (v_metadata.fdf = '1' and RV.DistBool((false => 50, true => 50))) then
          prepare_ack_delim;
        else
          prepare_ack;
        end if;
        submit_and_verify;
        ICover(ide_cov, to_integer(v_metadata.ide));
        ICover(fdf_cov, to_integer(v_metadata.fdf));
        ICover(brs_cov, to_integer(v_metadata.brs));
        ICover(esi_cov, to_integer(v_metadata.esi));
        ICover(ftyp_cov, to_integer(v_metadata.ftyp));
        ICover(dlc_cov, to_integer(unsigned(v_metadata.dlc)));
        ICover(inj_cov, v_inj_type);
        ICover(fce_cov, v_error_state);
      end loop;
    end procedure test_normal;

    --------------------------------------------------------------------------
    -- Test 4: Error injection - cover all fault scenarios and positions
    --------------------------------------------------------------------------
    procedure test_error_injection is
    begin
      Print("--------------------------------------------------------------------------");
      Print("Test 4: Error injection scenarios");
      Print("--------------------------------------------------------------------------");
      while not (IsCovered(inj_cov) and IsCovered(pos_cov)) loop
        next_frame;
        -- Focus position coverage once injection types are covered
        if (IsCovered(inj_cov) and not IsCovered(pos_cov)) then
          v_inj_type := c_inj_error;
        else
          v_inj_type := GetRandPoint(inj_cov);
        end if;
        -- ACK-delimiter acceptance is FD-only (ISO 6.6.11.6)
        if (v_inj_type = c_inj_ack_delim and v_metadata.fdf = '0') then
          v_inj_type := c_inj_ack;
        end if;
        v_exp_fce := (others => '0');
        case v_inj_type is
          when c_inj_ack                  => prepare_ack;
          when c_inj_ack_delim            => prepare_ack_delim;
          when c_inj_ack_error            => prepare_ack_error;
          when c_inj_error                => prepare_bit_error;
          when c_inj_lost_arb             => prepare_lost_arb;
          when c_inj_reactive_overload    => prepare_reactive_overload;
          when c_inj_error_delim_too_late => prepare_error_delim_too_late;
          when others                     => null;
        end case;
        submit_and_verify;
        ICover(inj_cov, v_inj_type);
        ICover(fce_cov, v_error_state);
        if (v_inj_type = c_inj_error) then
          ICover(pos_cov, v_inj_pos);
        end if;

      end loop;
    end procedure test_error_injection;

    --------------------------------------------------------------------------
    procedure report_results is
      variable v_errors : integer;
    begin
      AlertIfNotCovered;
      v_errors := EndOfTestReports(ReportAll => true);
      if (v_errors = 0) then
        Print("--------------------------------------------------------------------------");
        Print("Test Pass!");
        Print("--------------------------------------------------------------------------");
      else
        Print("--------------------------------------------------------------------------");
        Print("Test Fail!");
        Print("--------------------------------------------------------------------------");
      end if;
    end procedure report_results;

  begin
    WaitForBarrier(init_barrier);
    wait until reset = '0';
    WaitForClock(clk, 5);

    test_reset;
    test_bus_reintegration;
    test_normal;
    test_error_injection;

    report_results;
    std.env.finish;
    wait;
  end process p_test_ctrl;

end architecture tb;
