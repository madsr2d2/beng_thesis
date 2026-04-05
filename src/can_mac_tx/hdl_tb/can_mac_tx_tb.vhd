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
  -- Constants
  ----------------------------------------------------------------------------
  constant c_sp_interval  : natural := 10;
  constant c_bin_at_least : natural := 5;
  constant c_rec_width    : natural := 16;

  -- Error injection position coverage range.
  -- Min: smallest reachable position (CB arb_end with no stuff bits) = 13.
  -- Max: safe ack_pos - 2 for FE DLC=15 with any data pattern ~ 580.
  constant c_min_err_pos      : natural := 13;
  constant c_max_err_pos      : natural := 580;
  constant c_pos_bin_num      : natural := 50;

  -- PCS VC subtypes / injection coverage bins (unified natural encoding).
  -- 0 = activate SP strobe (not an injection type).
  constant c_pcs_active               : natural := 0;
  constant c_inj_ack                  : natural := 1;
  constant c_inj_ack_error            : natural := 2;
  constant c_inj_error                : natural := 3;
  constant c_inj_lost_arb             : natural := 4;
  constant c_inj_reactive_overload    : natural := 5;
  constant c_inj_error_delim_too_late : natural := 6;
  
  type injection_type is (ack, ack_error, error, lost_arb, overload, reactive_overload, error_delimiter_too_late);
  signal inj_type : injection_type;

  -- FCE state coverage bins (integer encoding)
  constant c_fce_active  : natural := 0;
  constant c_fce_passive : natural := 1;

  -- FCE latch bit positions (pulse events from fce_o)
  constant c_fce_successful_transfer   : natural := 0;
  constant c_fce_error                 : natural := 1;
  constant c_fce_primary_error         : natural := 2;
  constant c_fce_counters_unchanged    : natural := 3;
  constant c_fce_error_delim_too_late  : natural := 4;
  constant c_fce_latch_width           : natural := 5;

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

  -- Data-phase info for PCS VC (set by test sequencer before each frame)
  signal pcs_fdf_pos          : integer := -1;
  signal pcs_data_phase_start : integer := -1;
  signal pcs_data_phase_end   : integer := -1;
  
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

  -- =========================================================================
  -- Reference model (build_bus_stream) now in pk_can_types.
  -- =========================================================================

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

  procedure truncate_error (stream : inout t_bus_stream; inject_pos : in natural; is_passive : in boolean := false) is
    variable idx      : natural   := inject_pos;
    variable flag_pol : std_logic := c_dominant;
  begin
    if (is_passive) then 
      flag_pol := c_recessive;
    end if;
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
    SetAlertStopCount(ERROR, 10);
    SetLogEnable(INFO, false);
    SetLogEnable(DEBUG, false);
    v_test_id := NewID("can_mac_tx");
    v_reset_id   := NewID("Reset check", v_test_id);
    v_status_id  := NewID("Transfer Status check", v_test_id);
    v_stream_id  := NewID("Bus stream check", v_test_id);
    v_fce_chk_id := NewID("FCE event check", v_test_id);

    v_ide_cov := NewID("IDE Coverage", v_test_id);
    v_fdf_cov := NewID("FDF Coverage", v_test_id);
    v_ftyp_cov := NewID("FTYP Coverage", v_test_id);
    v_esi_cov  := NewID("ESI Coverage", v_test_id);
    v_brs_cov  := NewID("BRS Coverage", v_test_id);
    v_dlc_cov := NewID("DLC Coverage", v_test_id);
    v_inj_cov := NewID("Error Injection Coverage", v_test_id);
    v_pos_cov := NewID("Error Injection Position Coverage", v_test_id);
    v_fce_cov := NewID("FCE State Coverage", v_test_id);
    pcs_rec.BurstFifo <= NewID("PCS VC Burst fifo");

    AddBins(v_ide_cov, GenBin(c_bin_at_least, (0, 1)));
    AddBins(v_fdf_cov, GenBin(c_bin_at_least, (0, 1)));
    AddBins(v_ftyp_cov, GenBin(c_bin_at_least, (0, 1)));
    AddBins(v_esi_cov, GenBin(c_bin_at_least, (0, 1)));
    AddBins(v_brs_cov, GenBin(c_bin_at_least, (0, 1)));
    AddBins(v_dlc_cov, GenBin(c_bin_at_least, 0, c_dlc_max, c_dlc_max + 1));
    AddBins(v_inj_cov, GenBin(c_bin_at_least, (c_inj_ack, c_inj_ack_error, c_inj_error, c_inj_lost_arb, c_inj_reactive_overload, c_inj_error_delim_too_late)));
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
      if (reset = '1') then
        status_latch <= c_ongoing;
      elsif (llc_i.avalon_st_source.startofpacket = '1' and llc_o.avalon_st_sink.ready = '1') then
        status_latch <= llc_o.transfer_status;
      elsif (llc_o.transfer_status /= c_ongoing) then
        status_latch <= llc_o.transfer_status;
      end if;
    end if;
  end process p_status_latch;

  ----------------------------------------------------------------------------
  -- FCE event latch (Used for checks in FCE VC)
  ----------------------------------------------------------------------------
  p_fce_latch : process (clk) is
  begin
    if rising_edge(clk) then
      if (reset = '1') then
        fce_latch <= (others => '0');
      elsif (llc_i.avalon_st_source.startofpacket = '1' and llc_o.avalon_st_sink.ready = '1') then
        fce_latch <= (others => '0');
      else
        if (fce_o.successful_transfer = '1') then
          fce_latch(c_fce_successful_transfer) <= '1';
        end if;
        if (fce_o.error = '1') then
          fce_latch(c_fce_error) <= '1';
        end if;
        if (fce_o.primary_error = '1') then
          fce_latch(c_fce_primary_error) <= '1';
        end if;
        if (fce_o.counters_unchanged = '1') then
          fce_latch(c_fce_counters_unchanged) <= '1';
        end if;
        if (fce_o.error_delimiter_too_late = '1') then
          fce_latch(c_fce_error_delim_too_late) <= '1';
        end if;
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
          wait until rising_edge(clk) and status_latch /= c_ongoing;
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
          wait until rising_edge(clk) and status_latch /= c_ongoing;
          AffirmIfEqual(status_check_id, status_latch, std_logic_vector(llc_rec.DataToModel(2 downto 0)), "Transfer status");
        when others => null;
      end case;
    end loop;
  end process p_llc_vc;

  ----------------------------------------------------------------------------
  -- PCS Verification Component
  ----------------------------------------------------------------------------
  p_pcs_vc : process is
    variable v_expected_bit : std_logic;
    variable v_bus_idx      : natural;
    variable v_inject_pos   : natural;
    variable v_inject_pos_2 : natural;
    variable v_inject_end_2 : natural;
    variable v_subtype      : natural;
    variable v_sp_active           : boolean := false;
    variable v_checking            : boolean := false;
    variable v_burst_check_pending : boolean := false;
    variable v_sp_count            : natural range 0 to c_sp_interval - 1 := 0;

    -- Data-phase info (latched from signals at SEND_ASYNC)
    variable v_fdf_pos          : integer := -1;
    variable v_data_phase_start : integer := -1;
    variable v_data_phase_end   : integer := -1;

    --------------------------------------------------------------------------
    -- Arm/disarm bus override at programmed position(s)
    --------------------------------------------------------------------------
    procedure arm_bus_injection is
    begin
      -- Primary injection position
      if (v_bus_idx = v_inject_pos) then
        if (v_subtype = c_inj_ack or v_subtype = c_inj_lost_arb) then
          bus_override <= c_dominant;
        end if;
        if (v_subtype /= c_inj_ack_error) then
          bus_override_en <= true;
        end if;
      elsif (v_bus_idx = v_inject_pos + 1) then
        bus_override_en <= false;
      end if;
      -- Secondary injection point
      if (v_inject_pos_2 > 0) then
        if (v_bus_idx = v_inject_pos_2) then
          bus_override    <= c_dominant;
          bus_override_en <= true;
        elsif (v_bus_idx = v_inject_end_2 + 1) then
          bus_override_en <= false;
        end if;
      end if;
    end procedure arm_bus_injection;

  begin
    pcs_i.sp           <= '0';
    pcs_i.ssp          <= '0';
    pcs_i.tdc_delay    <= (others => '0');
    pcs_i.bus_polarity <= c_recessive;
    bus_override_en    <= false;
    WaitForBarrier(init_barrier);
    FinishTransaction(pcs_rec.Ack);

    pcs_vc_loop : loop
      wait until rising_edge(clk);

      --------------------------------------------------------------------------
      -- Continuous: SP strobe generation with bus loopback/override
      --------------------------------------------------------------------------
      pcs_i.sp <= '0';
      if (v_sp_active) then
        if (v_sp_count = c_sp_interval - 1) then
          -- Inject types that inject errors by flipping polarity at SP
          if (bus_override_en and (v_subtype  = c_inj_error or v_subtype = c_inj_reactive_overload or v_subtype = c_inj_error_delim_too_late)) then
            pcs_i.bus_polarity <= not pcs_o.polarity;
          elsif (bus_override_en) then
            -- Else pass the override polarity
            pcs_i.bus_polarity <= bus_override;
          else
            -- Else loop back the bit polarity from the MAC fsm
            pcs_i.bus_polarity <= pcs_o.polarity;
          end if;
          pcs_i.sp <= '1';
          v_sp_count := 0;
        else
          v_sp_count := v_sp_count + 1;
        end if;
      end if;

      --NOTE: SSP is not modelled, just held low...
      pcs_i.ssp <= '0';

      --------------------------------------------------------------------------
      -- Bit checking: pop-and-compare on each SP (incl. IFS)
      --------------------------------------------------------------------------
      if (v_checking) then
        if (pcs_i.sp = '1' and (pcs_o.valid = '1' or v_bus_idx > 0)) then
          v_expected_bit := Pop(pcs_rec.BurstFifo)(0); -- Pop expected bit from fifo
          -- Check bit polarity from MAC fsm
          AffirmIfEqual(stream_check_id, pcs_o.polarity, v_expected_bit, "Bit: Got/Expected = " & to_string(pcs_o.polarity) & "/" & to_string(v_expected_bit));
          -- Check use_data_rate
          if (v_data_phase_start >= 0 and v_bus_idx >= v_data_phase_start and v_bus_idx <= v_data_phase_end) then
            AffirmIfEqual(stream_check_id, pcs_o.use_data_rate, '1', "pcs_o.use_data_rate: Got/Expected = " & to_string(pcs_o.use_data_rate) & "/" & '1');
          else
            AffirmIfEqual(stream_check_id, pcs_o.use_data_rate, '0', "pcs_o.use_data_rate: Got/Expected = " & to_string(pcs_o.use_data_rate) & "/" & '0');
          end if;
          -- Check start_tdc (single pulse at FDF bit)
          if (v_fdf_pos >= 0 and v_bus_idx = v_fdf_pos) then
            AffirmIfEqual(stream_check_id, pcs_o.start_tdc, '1', "pcs_o.start_tdc: Got/Expected = " & to_string(pcs_o.start_tdc) & "/" & '1');
          else
            AffirmIfEqual(stream_check_id, pcs_o.start_tdc, '0', "pcs_o.start_tdc: Got/Expected = " & to_string(pcs_o.start_tdc) & "/" & '0');
          end if;
          v_bus_idx := v_bus_idx + 1;
          arm_bus_injection;
        end if;
        -- Finish transaction when scoreboard is empty
        if (v_bus_idx > 0 and Empty(pcs_rec.BurstFifo)) then
          bus_override_en <= false;
          v_checking      := false;
          if v_burst_check_pending then
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
              v_sp_count  := 0;
              v_bus_idx   := 0;
            else
              v_inject_pos   := to_integer(unsigned(pcs_rec.ParamToModel));
              v_inject_pos_2 := 0;
              v_inject_end_2 := 0;
              -- Latch data-phase info from signals
              v_fdf_pos          := pcs_fdf_pos;
              v_data_phase_start := pcs_data_phase_start;
              v_data_phase_end   := pcs_data_phase_end;
              -- Compute secondary injection positions per subtype
              if (v_subtype = c_inj_reactive_overload) then
                v_inject_pos_2 := v_inject_pos + c_error_sequence_width;
                v_inject_end_2 := v_inject_pos_2;
              elsif (v_subtype = c_inj_error_delim_too_late) then
                v_inject_pos_2 := v_inject_pos + 1 + c_error_flag_width;
                v_inject_end_2 := v_inject_pos_2 + c_error_delimiter_width - 1;
              end if;
              v_checking := true;
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
    variable v_frame_count : natural := 0;
    variable v_stream      : t_bus_stream;
    variable v_inj_type    : natural;
    variable v_inj_pos     : natural;
    variable v_candidate   : natural;
    variable v_exp_status  : std_logic_vector(2 downto 0);
    variable v_exp_fce     : std_logic_vector(c_fce_latch_width - 1 downto 0);
    variable v_error_state   : natural;
    variable v_cov_done : boolean := false;
  begin
    WaitForBarrier(init_barrier);
    wait until reset = '0';
    WaitForClock(clk, 5);

    Print("----------------------------------------------------------------------------");
    Print("Test 1: Reset");
    Print("----------------------------------------------------------------------------");
    AffirmIf(reset_check_id, pcs_o=c_mac_to_pcs_if_reset, "pcs_o not reset correctly");
    AffirmIf(reset_check_id, fce_o=c_mac_to_fce_if_reset, "fce_o not reset correctly");
    AffirmIf(reset_check_id, llc_o=c_mac_to_llc_if_reset, "llc_o not reset correctly");

    Print("--------------------------------------------------------------------------");
    Print("Test 2: Bus reintegration");
    Print("--------------------------------------------------------------------------");
    -- Activate SP strobes; FSM should remain in s_bus_reintegration for 11 SPs
    SendAsync(pcs_rec, std_logic_vector(to_unsigned(c_pcs_active, c_rec_width)));
    for sp_idx in 0 to c_bus_idle_condition_width - 2 loop
      wait until rising_edge(clk) and pcs_i.sp = '1';
      AffirmIf(reset_check_id, pcs_o.valid = '0', "Reintegration: valid=0 at SP " & to_string(sp_idx));
    end loop;
    -- After the 11th SP the FSM transitions to s_bus_idle (still valid='0')
    wait until rising_edge(clk) and pcs_i.sp = '1';
    AffirmIf(reset_check_id, pcs_o.valid = '0', "Bus idle: valid=0 (no pending frame)");

    Print("--------------------------------------------------------------------------");
    Print("Test 3: Coverage-driven random frames");
    Print("--------------------------------------------------------------------------");
    frame_loop : while not (v_cov_done) loop -- Loop until coverage is met
      v_frame_count := v_frame_count + 1;

      gen_frame(v_frame, v_metadata, v_last_byte, v_stream, v_error_state);

      if (v_error_state = c_fce_passive) then
        Send(fce_rec, "01");  -- error_passive=1, error_active=0, bus_off=0
      else
        Send(fce_rec, "10");  -- error_passive=0, error_active=1, bus_off=0
      end if;

      -- Once inj_cov met, focus on position coverage
      if (IsCovered(inj_cov) and not IsCovered(pos_cov)) then
        v_inj_type := c_inj_error;
      else
        v_inj_type := GetRandPoint(inj_cov);
      end if;

      v_exp_fce := (others => '0');

      case v_inj_type is
        when c_inj_ack =>
          v_inj_pos     := v_stream.ack_pos;
          v_exp_status  := c_transmitted;
          v_exp_fce(c_fce_successful_transfer) := '1';
          inj_type <= ack;

        when c_inj_ack_error =>
          v_inj_pos     := v_stream.ack_pos;
          v_exp_status  := c_disturbed;
          v_exp_fce(c_fce_error) := '1';
          inj_type <= ack_error;
          if (v_error_state = c_fce_passive) then
            -- ISO 8.1.4.2 rule c) Exception 1: passive TX ACK error,
            -- no dominant seen during passive EF -> counters_unchanged
            v_exp_fce(c_fce_counters_unchanged) := '1';
          else
            -- Active error flag transmits dominant -> primary_error fires
            v_exp_fce(c_fce_primary_error) := '1';
          end if;
          -- ACK error detected at ACK delimiter (ack_pos + 1), error flag
          -- starts at bit after that: ack_pos + 2
          truncate_error(v_stream, v_stream.ack_pos + 2, v_error_state = c_fce_passive);


        when c_inj_error =>
          -- Coverage-driven position: try uncovered bins that fit within
          -- this frame's valid range [arb_end, ack_pos-2].
          -- Arb field excluded (ISO 6.6.21.2.a Exception 1).
          v_inj_pos := RV.RandInt(v_stream.arb_end, v_stream.ack_pos - 2);
          inj_type <= error;
          for attempt in 0 to 9 loop
            v_candidate := GetRandPoint(pos_cov);
            if (v_candidate >= v_stream.arb_end and v_candidate <= v_stream.ack_pos - 2) then
              v_inj_pos := v_candidate;
              exit;
            end if;
          end loop;
          v_exp_status  := c_disturbed;
          v_exp_fce(c_fce_error) := '1';
          if not (v_error_state = c_fce_passive) then
            v_exp_fce(c_fce_primary_error) := '1';
          end if;
          truncate_error(v_stream, v_inj_pos + 1, v_error_state = c_fce_passive);

        when c_inj_lost_arb =>
          v_exp_status  := c_lost_arb;
          v_frame(2)(c_byte_width - 1) := c_recessive;
          v_metadata := extract_metadata(v_frame(0), v_frame(1));
          v_stream   := build_bus_stream(v_frame, v_metadata, v_error_state = c_fce_passive);
          v_inj_pos    := 1;
          v_stream.len := v_inj_pos + 1;
          inj_type <= lost_arb;

        when c_inj_reactive_overload =>
          -- Bit error + dominant at last error delimiter bit -> reactive OF
          v_inj_pos     := RV.RandInt(v_stream.arb_end, v_stream.ack_pos - 2);
          v_exp_status  := c_disturbed;
          v_exp_fce(c_fce_error) := '1';
          inj_type <= reactive_overload;
          if not (v_error_state = c_fce_passive) then
            v_exp_fce(c_fce_primary_error) := '1';
          end if;
          truncate_reactive_overload(v_stream, v_inj_pos, v_error_state = c_fce_passive);

        when c_inj_error_delim_too_late =>
          -- Bit error + 8 dominant during error delimiter
          v_inj_pos     := RV.RandInt(v_stream.arb_end, v_stream.ack_pos - 2);
          v_exp_status  := c_disturbed;
          v_exp_fce(c_fce_error) := '1';
          v_exp_fce(c_fce_error_delim_too_late) := '1';
          inj_type <= error_delimiter_too_late;
          if not (v_error_state = c_fce_passive) then
            v_exp_fce(c_fce_primary_error) := '1';
          end if;
          -- Same TX output as reactive overload (overload triggered by
          -- dominant at last delimiter bit)
          truncate_reactive_overload(v_stream, v_inj_pos, v_error_state = c_fce_passive);

        when others =>
          null;
      end case;

      -- Adjust data-phase bounds for error truncation
      pcs_fdf_pos          <= v_stream.fdf_pos;
      pcs_data_phase_start <= v_stream.data_phase_start;
      pcs_data_phase_end   <= v_stream.data_phase_end;
      case v_inj_type is
        when c_inj_lost_arb =>
          pcs_fdf_pos          <= -1;
          pcs_data_phase_start <= -1;
          pcs_data_phase_end   <= -1;
        when c_inj_error | c_inj_reactive_overload | c_inj_error_delim_too_late =>
          if (v_stream.fdf_pos >= 0 and v_inj_pos < v_stream.fdf_pos) then
            pcs_fdf_pos <= -1;
          end if;
          if (v_stream.data_phase_start >= 0 and v_inj_pos < v_stream.data_phase_start) then
            pcs_data_phase_start <= -1;
            pcs_data_phase_end   <= -1;
          elsif (v_stream.data_phase_start >= 0 and v_inj_pos <= v_stream.data_phase_end) then
            pcs_data_phase_end <= v_inj_pos;
          end if;
        when c_inj_ack_error =>
          -- Error after ACK delimiter; full data phase already complete
          null;
        when others =>
          null;
      end case;

      -- Configure PCS VC 
      SendAsync(pcs_rec, std_logic_vector(to_unsigned(c_pcs_active, c_rec_width)));
      SendAsync(pcs_rec, std_logic_vector(to_unsigned(v_inj_type, c_rec_width)), std_logic_vector(to_unsigned(v_inj_pos, c_rec_width)));

      -- Push expected bus stream before driving bytes
      for i in 0 to v_stream.len - 1 loop
        Push(pcs_rec.BurstFifo, (0 downto 0 => v_stream.bits(i)));
      end loop;

      -- Drive frame through DUT (PCS VC checks concurrently)
      for i in 0 to v_last_byte loop
        if i = 0 then
          Send(llc_rec, v_frame(i), "10"); -- Set SOP for first byte
        else
          Send(llc_rec, v_frame(i), "00");
        end if;
      end loop;

      -- Do the checks
      CheckBurst(pcs_rec, GetFifoCount(pcs_rec.BurstFifo)); -- Check bit stream sent to PCS
      Check(llc_rec, v_exp_status); -- Check transfer status send to LLC
      Check(fce_rec, std_logic_vector(resize(unsigned(v_exp_fce), c_rec_width))); -- Check output to FCE

      -- Only sample coverage on successful transmission
      if (v_inj_type = c_inj_ack) then
        ICover(ide_cov, to_integer(v_metadata.ide));
        ICover(fdf_cov, to_integer(v_metadata.fdf));
        ICover(brs_cov, to_integer(v_metadata.brs));
        ICover(esi_cov, to_integer(v_metadata.esi));
        ICover(ftyp_cov, to_integer(v_metadata.ftyp));
        ICover(dlc_cov, to_integer(unsigned(v_metadata.dlc)));
      end if;

      -- Sample injection type coverage, error injection position coverage and frame type coverage
      ICover(inj_cov, v_inj_type);
      ICover(fce_cov, v_error_state);
      if (v_inj_type = c_inj_error) then
        ICover(pos_cov, v_inj_pos);
      end if;

      -- Update loop guard
      v_cov_done := IsCovered(ide_cov) and 
                    IsCovered(fdf_cov) and 
                    IsCovered(esi_cov) and 
                    IsCovered(brs_cov) and 
                    IsCovered(ftyp_cov) and 
                    IsCovered(dlc_cov) and 
                    IsCovered(inj_cov) and 
                    IsCovered(pos_cov) and 
                    IsCovered(fce_cov);

      -- Debug printing
      Log(test_id, "Frame " & to_string(v_frame_count) &
          " ide=" & std_logic'image(v_metadata.ide) & " fdf=" & std_logic'image(v_metadata.fdf) &
          " dlc=" & to_hstring(v_metadata.dlc) &
          " inj=" & to_string(v_inj_type) &
          " pos=" & to_string(v_inj_pos) &
          " fce=" & to_string(v_error_state) &
          " len=" & to_string(v_stream.len) &
          " fdf=" & to_string(v_stream.fdf_pos) &
          " dp_start=" & to_string(v_stream.data_phase_start) &
          " dp_end=" & to_string(v_stream.data_phase_end) &
          " ack=" & to_string(v_stream.ack_pos) &
          " arb_end=" & to_string(v_stream.arb_end), DEBUG);
    end loop frame_loop;

    AffirmIf(GetAlertLogID(ide_cov), IsCovered(ide_cov),"");
    AffirmIf(GetAlertLogID(fdf_cov), IsCovered(fdf_cov),"");
    AffirmIf(GetAlertLogID(ftyp_cov), IsCovered(ftyp_cov),"");
    AffirmIf(GetAlertLogID(esi_cov), IsCovered(esi_cov),"");
    AffirmIf(GetAlertLogID(brs_cov), IsCovered(brs_cov),"");
    AffirmIf(GetAlertLogID(dlc_cov), IsCovered(dlc_cov),"");
    AffirmIf(GetAlertLogID(inj_cov), IsCovered(inj_cov),"");
    AffirmIf(GetAlertLogID(pos_cov), IsCovered(pos_cov),"");
    AffirmIf(GetAlertLogID(fce_cov), IsCovered(fce_cov),"");

    Print("----------------------------------------------------------------------------");
    Print("Test done!");
    Print("----------------------------------------------------------------------------");
    WriteBin(ide_cov);
    WriteBin(fdf_cov);
    WriteBin(esi_cov);
    WriteBin(brs_cov);
    WriteBin(ftyp_cov);
    WriteBin(dlc_cov);
    WriteBin(inj_cov);
    WriteBin(pos_cov);
    WriteBin(fce_cov);
    EndOfTestReports(ReportAll => true);
    std.env.finish;
    wait;

  end process p_test_ctrl;

end architecture tb;
