--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_mac_tx (ser + fsm + bs + crc) - Version 1: Happy path.
--                  p_llc_vc           - LLC Avalon-ST source VC (byte driver).
--                  p_pcs_vc           - PCS sink VC (bit-level self-checking, ACK injection).
--                  p_test_ctrl        - Coverage-driven test sequencer with reference model.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-28  MRDSA     [TRIT-4355] Initial implementation
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

entity can_mac_tx_tb_v1 is
  generic (
    gc_TbTimeOut   : time := 500 ms;
    gc_TbClkPeriod : time := 10 ns
  );
end entity can_mac_tx_tb_v1;

architecture tb of can_mac_tx_tb_v1 is

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  constant c_sp_interval   : natural := 10;
  constant c_bin_num       : natural := 5;
  constant c_max_bus_bits  : natural := 1024;
  constant c_rec_width     : natural := 16;

  -- PCS VC subtypes (unified natural encoding)
  constant c_pcs_active : natural := 0;
  constant c_inj_ack    : natural := 1;

  ----------------------------------------------------------------------------
  -- Types
  ----------------------------------------------------------------------------
  type t_bus_stream is record
    bits             : std_logic_vector(0 to c_max_bus_bits - 1);
    len              : natural;
    ack_pos          : natural;
    fdf_pos          : natural;  -- stuffed index of FDF bit (-1 for CC)
    data_phase_start : natural;  -- stuffed index of ESI bit (-1 if no data phase)
    data_phase_end   : natural;  -- last stuffed index in data phase (-1 if no data phase)
  end record t_bus_stream;

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

  -- Data-phase info for PCS VC (set by test sequencer before each frame)
  signal pcs_fdf_pos          : natural := -1;
  signal pcs_data_phase_start : natural := -1;
  signal pcs_data_phase_end   : natural := -1;

  -- OSVVM signals
  shared variable RV  : RandomPType;
  signal test_id         : AlertLogIDType;
  signal reset_check_id  : AlertLogIDType;
  signal status_check_id : AlertLogIDType;
  signal stream_check_id : AlertLogIDType;
  signal ide_cov      : CoverageIDType;
  signal fdf_cov      : CoverageIDType;
  signal dlc_cov      : CoverageIDType;
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

  ----------------------------------------------------------------------------
  -- Utility functions
  ----------------------------------------------------------------------------
  function to_slv (b : std_logic) return std_logic_vector is
  begin
    return (0 downto 0 => b);
  end function to_slv;

  ----------------------------------------------------------------------------
  -- Reference model: build expected bus stream (single-pass)
  --   Phase 1: SOF..data  (get_mac_frame_bit -> dynamic stuffer -> CRC)
  --   Phase 2: SBC (FD) + CRC computation
  --   Phase 3: CRC region (CC: stuffed CRC-15; FD: FSB-interleaved)
  --   Phase 4: Recessive tail (delimiter, ACK, EOF, IFS)
  ----------------------------------------------------------------------------
  function build_bus_stream (
    frame    : t_llc_frame;
    metadata : t_llc_metadata
  ) return t_bus_stream is
    variable result : t_bus_stream;
    variable fp     : t_frame_params;
    variable is_fd  : boolean;

    -- Serializer data: ID stream and data bytes
    variable id_stream   : std_logic_vector(c_llc_id_field_width - 1 downto 0);
    variable ser_data    : std_logic;
    variable fb          : t_mac_frame_bit;
    variable data_bit_no : natural;

    -- Dynamic stuffer state
    variable consec   : natural range 0 to c_stuff_width := 0;
    variable last_pol : std_logic := c_recessive;
    variable ds_count : std_logic_vector(2 downto 0) := (others => '0');

    -- CRC accumulator and result
    variable crc_in     : std_logic_vector(0 to c_max_bus_bits - 1);
    variable crc_in_len : natural := 0;
    variable crc        : std_logic_vector(c_crc_21_length - 1 downto 0);

    -- FD CRC region
    variable sbc  : std_logic_vector(c_sbc_field_width - 1 downto 0);
    variable gray : std_logic_vector(2 downto 0);

    variable tail_len : natural;

    -- Feed one bit through the dynamic stuffer.
    -- FD: stuff bits feed CRC input. CC: they do not.
    procedure ds_feed (pol : std_logic) is
    begin
      result.bits(result.len) := pol;
      result.len              := result.len + 1;
      if (is_fd) then
        crc_in(crc_in_len) := pol;
        crc_in_len         := crc_in_len + 1;
      end if;

      if (pol = last_pol) then
        consec := consec + 1;
        if (consec = c_stuff_width) then
          result.bits(result.len) := not pol;
          result.len              := result.len + 1;
          if (is_fd) then
            crc_in(crc_in_len) := not pol;
            crc_in_len         := crc_in_len + 1;
          end if;
          consec   := 1;
          last_pol := not pol;
          ds_count := ds_count + 1;
        end if;
      else
        consec   := 1;
        last_pol := pol;
      end if;
    end procedure ds_feed;

  begin
    result.len              := 0;
    result.fdf_pos          := -1;
    result.data_phase_start := -1;
    result.data_phase_end   := -1;
    fp                      := get_frame_params(metadata);
    is_fd                   := metadata.fdf = '1';

    -- Flatten ID bytes (2..5) into a 32-bit vector, MSB first
    id_stream := frame(2) & frame(3) & frame(4) & frame(5);

    --------------------------------------------------------------------------
    -- Phase 1: SOF through last data bit
    --------------------------------------------------------------------------
    for pos in 0 to fp.data_stop - 1 loop
      -- Resolve ser_data for ID and data field positions
      if (pos >= c_cb_base_id_start and pos <= c_cb_base_id_stop) then
        ser_data := id_stream(c_llc_id_field_width - 1 - (pos - c_cb_base_id_start));
      elsif (metadata.ide = '1' and
             pos >= c_ce_extended_id_start and pos <= c_ce_extended_id_stop) then
        ser_data := id_stream(c_llc_id_field_width - 1 - c_base_id_width
                              - (pos - c_ce_extended_id_start));
      elsif (pos >= fp.dlc_start + c_dlc_field_width and pos < fp.data_stop) then
        data_bit_no := pos - (fp.dlc_start + c_dlc_field_width);
        ser_data := frame(6 + data_bit_no / c_byte_width)
                         (c_byte_width - 1 - (data_bit_no mod c_byte_width));
      else
        ser_data := '0';
      end if;

      fb := get_mac_frame_bit(pos, ser_data, metadata, fp,
                              c_recessive, "0000", (others => '0'));

      -- CC: raw bits feed CRC (stuff bits do not)
      if (not is_fd) then
        crc_in(crc_in_len) := fb.polarity;
        crc_in_len         := crc_in_len + 1;
      end if;
      ds_feed(fb.polarity);

      -- Track stuffed positions using the bit_name from pkg
      case fb.bit_name is
        when fdf_bit =>
          result.fdf_pos := result.len - 1;
        when esi_bit =>
          if (metadata.brs = '1') then
            result.data_phase_start := result.len - 1;
          end if;
        when others =>
          null;
      end case;
    end loop;

    --------------------------------------------------------------------------
    -- Phase 2: SBC (FD only) + CRC computation
    --------------------------------------------------------------------------
    if (is_fd) then
      gray := f_to_gray(std_logic_vector(ds_count));
      sbc  := gray & f_calc_parity(gray);

      for i in c_sbc_field_width - 1 downto 0 loop
        crc_in(crc_in_len) := sbc(i);
        crc_in_len         := crc_in_len + 1;
      end loop;
    end if;

    crc := (others => '0');
    case fp.crc_poly_select is
      when "01" =>
        crc(c_crc_21_length - 1 downto c_crc_21_length - c_crc_17_length) :=
          f_calc_can_crc(crc_in(0 to crc_in_len - 1), c_crc_init_17_vec, c_crc_poly_17_vec);
      when "10" =>
        crc := f_calc_can_crc(crc_in(0 to crc_in_len - 1), c_crc_init_21_vec, c_crc_poly_21_vec);
      when others =>
        crc(c_crc_21_length - 1 downto c_crc_21_length - c_crc_15_length) :=
          f_calc_can_crc(crc_in(0 to crc_in_len - 1), c_crc_init_15_vec, c_crc_poly_15_vec);
    end case;

    --------------------------------------------------------------------------
    -- Phase 3: CRC region (FD: FSB-interleaved via pkg; CC: stuffed CRC-15)
    --------------------------------------------------------------------------
    for pos in fp.data_stop to fp.crc_delimiter - 1 loop
      fb := get_mac_frame_bit(pos, '0', metadata, fp,
                              result.bits(result.len - 1), sbc, crc);
      if (is_fd) then
        result.bits(result.len) := fb.polarity;
        result.len              := result.len + 1;
      else
        ds_feed(fb.polarity);
      end if;
    end loop;

    -- Data phase ends at last CRC region bit (just before CRC delimiter)
    if (result.data_phase_start >= 0) then
      result.data_phase_end := result.len - 1;
    end if;

    --------------------------------------------------------------------------
    -- Phase 4: Recessive tail (CRC delim, ACK, EOF, IFS)
    --------------------------------------------------------------------------
    result.ack_pos := result.len + c_ack_slot_offset;
    tail_len := c_eof_start_offset + c_eof_field_width + c_intermission_width;
    for i in 0 to tail_len - 1 loop
      result.bits(result.len) := c_recessive;
      result.len              := result.len + 1;
    end loop;

    return result;
  end function build_bus_stream;

  ----------------------------------------------------------------------------
  -- Random frame and expected bus stream generator
  ----------------------------------------------------------------------------
  procedure gen_frame (
    variable frame     : out t_llc_frame;
    variable metadata  : out t_llc_metadata;
    variable last_byte : out natural;
    variable stream    : out t_bus_stream
  ) is
  begin
    for i in frame'range loop
      frame(i) := RV.RandSlv(8);
    end loop;

    -- Coverage-driven IDE, FDF, and DLC
    frame(0)(c_llc_frame_ide) := std_logic(to_unsigned(GetRandPoint(ide_cov), 1)(0));
    frame(0)(c_llc_frame_fdf) := std_logic(to_unsigned(GetRandPoint(fdf_cov), 1)(0));
    frame(0)(5)               := '0'; -- reserved
    frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end) :=
      std_logic_vector(to_unsigned(GetRandPoint(dlc_cov), 4));

    -- Keep ftyp consistent with DLC (FD ignores ftyp)
    if (frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end) = "0000") then
      frame(0)(c_llc_frame_ftyp) := '1';
    else
      frame(0)(c_llc_frame_ftyp) := '0';
    end if;

    metadata  := extract_metadata(frame(0), frame(1));
    last_byte := 6 + dlc_to_data_length(
                   natural range 0 to c_dlc_max(to_integer(unsigned(metadata.dlc))), metadata.fdf) - 1;
    stream    := build_bus_stream(frame, metadata);
  end procedure gen_frame;

begin

  ----------------------------------------------------------------------------
  -- Infrastructure
  ----------------------------------------------------------------------------
  CreateClock(clk, gc_TbClkPeriod);
  CreateReset(reset, '1', clk, gc_TbClkPeriod * 10);

  p_timeout : process is
  begin
    wait for gc_TbTimeOut;
    assert false report "ERROR TEST FAILED, due to time out" severity error;
    std.env.stop(1);
  end process p_timeout;

  p_init : process is
    variable v_test_id   : AlertLogIDType;
    variable v_reset_id  : AlertLogIDType;
    variable v_status_id : AlertLogIDType;
    variable v_stream_id : AlertLogIDType;
    variable v_ide_cov   : CoverageIDType;
    variable v_fdf_cov   : CoverageIDType;
    variable v_dlc_cov   : CoverageIDType;
  begin
    SetAlertStopCount(ERROR, 10);
    SetLogEnable(INFO, false);
    SetLogEnable(DEBUG, false);
    v_test_id   := NewID("can_mac_tx");
    v_reset_id  := NewID("Reset check", v_test_id);
    v_status_id := NewID("Transfer Status check", v_test_id);
    v_stream_id := NewID("Bus stream check", v_test_id);

    v_ide_cov := NewID("IDE Coverage", v_test_id);
    v_fdf_cov := NewID("FDF Coverage", v_test_id);
    v_dlc_cov := NewID("DLC Coverage", v_test_id);
    pcs_rec.BurstFifo <= NewID("PCS VC Burst fifo");

    AddBins(v_ide_cov, GenBin(c_bin_num, (0, 1)));
    AddBins(v_fdf_cov, GenBin(c_bin_num, (0, 1)));
    AddBins(v_dlc_cov, GenBin(c_bin_num, 0, c_dlc_max, c_dlc_max + 1));

    test_id         <= v_test_id;
    reset_check_id  <= v_reset_id;
    status_check_id <= v_status_id;
    stream_check_id <= v_stream_id;
    ide_cov <= v_ide_cov;
    fdf_cov <= v_fdf_cov;
    dlc_cov <= v_dlc_cov;

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
  -- Transfer status latch (clears on SOP handshake)
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
  -- LLC Verification Component
  ----------------------------------------------------------------------------
  p_llc_vc : process is
  begin
    WaitForBarrier(init_barrier);

    llc_vc_loop : loop
      WaitForTransaction(llc_rec.Rdy, llc_rec.Ack);
      case llc_rec.Operation is
        when SEND =>
          llc_i.avalon_st_source.valid         <= '1';
          llc_i.avalon_st_source.data          <= std_logic_vector(llc_rec.DataToModel(t_byte'range));
          llc_i.avalon_st_source.startofpacket <= llc_rec.ParamToModel(1);
          llc_i.avalon_st_source.endofpacket   <= llc_rec.ParamToModel(0);
          wait until rising_edge(clk) and llc_o.avalon_st_sink.ready = '1';
          llc_i.avalon_st_source.valid <= '0';

        when CHECK =>
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
    variable v_bus_idx      : natural;
    variable v_inject_pos   : natural;
    variable v_subtype      : natural;
    variable v_sp_active           : boolean := false;
    variable v_checking            : boolean := false;
    variable v_burst_check_pending : boolean := false;
    variable v_sp_count            : natural range 0 to c_sp_interval - 1 := 0;

    -- Data-phase info (latched from signals at SEND_ASYNC)
    variable v_fdf_pos          : natural := -1;
    variable v_data_phase_start : natural := -1;
    variable v_data_phase_end   : natural := -1;

    --------------------------------------------------------------------------
    -- Inject: arm/disarm bus override at programmed position
    --------------------------------------------------------------------------
    procedure inject is
    begin
      if (v_bus_idx = v_inject_pos) then
        bus_override    <= c_dominant;
        bus_override_en <= true;
      elsif (v_bus_idx = v_inject_pos + 1) then
        bus_override_en <= false;
      end if;
    end procedure inject;

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
      -- Continuous: SP strobe generation with bus loopback
      --------------------------------------------------------------------------
      pcs_i.sp <= '0';
      if (v_sp_active) then
        if (v_sp_count = c_sp_interval - 1) then
          if (bus_override_en) then
            pcs_i.bus_polarity <= bus_override;
          else
            pcs_i.bus_polarity <= pcs_o.polarity;
          end if;
          pcs_i.sp <= '1';
          v_sp_count := 0;
        else
          v_sp_count := v_sp_count + 1;
        end if;
      end if;

      -- SSP not modelled here; tested at can_tx_tb with full PCS
      pcs_i.ssp <= '0';

      --------------------------------------------------------------------------
      -- Bit checking: pop-and-compare on each SP (incl. IFS)
      --------------------------------------------------------------------------
      if (v_checking) then
        if (pcs_i.sp = '1' and (pcs_o.valid = '1' or v_bus_idx > 0)) then
          AffirmIfEqual(stream_check_id, to_slv(pcs_o.polarity), Pop(pcs_rec.BurstFifo),
                        "PCS bit " & to_string(v_bus_idx));

          -- Check use_data_rate
          if (v_data_phase_start >= 0 and v_bus_idx >= v_data_phase_start
              and v_bus_idx <= v_data_phase_end) then
            AffirmIfEqual(stream_check_id, pcs_o.use_data_rate, '1',
                          "use_data_rate=1 at bit " & to_string(v_bus_idx));
          else
            AffirmIfEqual(stream_check_id, pcs_o.use_data_rate, '0',
                          "use_data_rate=0 at bit " & to_string(v_bus_idx));
          end if;

          -- Check start_tdc (single pulse at FDF bit)
          if (v_fdf_pos >= 0 and v_bus_idx = v_fdf_pos) then
            AffirmIfEqual(stream_check_id, pcs_o.start_tdc, '1',
                          "start_tdc=1 at FDF bit " & to_string(v_bus_idx));
          else
            AffirmIfEqual(stream_check_id, pcs_o.start_tdc, '0',
                          "start_tdc=0 at bit " & to_string(v_bus_idx));
          end if;

          v_bus_idx := v_bus_idx + 1;
          inject;
        end if;

        if (v_bus_idx > 0 and GetFifoCount(pcs_rec.BurstFifo) = 0) then
          bus_override_en <= false;
          v_checking      := false;
          if (v_burst_check_pending) then
            v_burst_check_pending := false;
            FinishTransaction(pcs_rec.Ack);
          end if;
        end if;
      end if;

      --------------------------------------------------------------------------
      -- Transaction dispatch
      --------------------------------------------------------------------------
      if (TransactionPending(pcs_rec.Rdy, pcs_rec.Ack)) then
        case pcs_rec.Operation is
          when SEND_ASYNC =>
            v_subtype := to_integer(unsigned(pcs_rec.DataToModel));

            if (v_subtype = c_pcs_active) then
              v_sp_active := true;
              v_sp_count  := 0;
              v_bus_idx   := 0;

            else
              v_inject_pos := to_integer(unsigned(pcs_rec.ParamToModel));

              -- Latch data-phase info from signals
              v_fdf_pos          := pcs_fdf_pos;
              v_data_phase_start := pcs_data_phase_start;
              v_data_phase_end   := pcs_data_phase_end;

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
  begin
    WaitForBarrier(init_barrier);
    wait until reset = '0';
    WaitForClock(clk, 5);

    Print("----------------------------------------------------------------------------");
    Print("Test 1: Reset");
    Print("----------------------------------------------------------------------------");
    AffirmIfEqual(reset_check_id, llc_o.transfer_status, c_ongoing, "LLC transfer_status");
    AffirmIfEqual(reset_check_id, llc_o.avalon_st_sink.ready, '1', "LLC ready");
    AffirmIfEqual(reset_check_id, pcs_o.polarity, c_recessive, "PCS polarity");
    AffirmIfEqual(reset_check_id, pcs_o.valid, '0', "PCS valid");
    AffirmIfEqual(reset_check_id, pcs_o.use_data_rate, '0', "PCS use_data_rate");
    AffirmIfEqual(reset_check_id, pcs_o.start_tdc, '0', "PCS start_tdc");

    Print("--------------------------------------------------------------------------");
    Print("Test 2: Bus reintegration");
    Print("--------------------------------------------------------------------------");
    SendAsync(pcs_rec, std_logic_vector(to_unsigned(c_pcs_active, c_rec_width)));
    for sp_idx in 0 to c_bus_idle_condition_width - 2 loop
      wait until rising_edge(clk) and pcs_i.sp = '1';
      AffirmIfEqual(reset_check_id, pcs_o.valid, '0',
                    "Reintegration: valid=0 at SP " & to_string(sp_idx));
    end loop;
    wait until rising_edge(clk) and pcs_i.sp = '1';
    AffirmIfEqual(reset_check_id, pcs_o.valid, '0',
                  "Bus idle: valid=0 (no pending frame)");

    Print("--------------------------------------------------------------------------");
    Print("Test 3: Coverage-driven random frames (happy path)");
    Print("--------------------------------------------------------------------------");
    frame_loop : while not (IsCovered(ide_cov) and IsCovered(fdf_cov) and IsCovered(dlc_cov)) loop
      v_frame_count := v_frame_count + 1;

      gen_frame(v_frame, v_metadata, v_last_byte, v_stream);

      Log(test_id, "Frame " & to_string(v_frame_count) &
          " ide=" & std_logic'image(v_metadata.ide) & " fdf=" & std_logic'image(v_metadata.fdf) &
          " dlc=" & to_hstring(v_metadata.dlc) &
          " len=" & to_string(v_stream.len) &
          " ack=" & to_string(v_stream.ack_pos), DEBUG);

      -- Pass data-phase info to PCS VC
      pcs_fdf_pos          <= v_stream.fdf_pos;
      pcs_data_phase_start <= v_stream.data_phase_start;
      pcs_data_phase_end   <= v_stream.data_phase_end;

      -- Configure PCS VC: activate SP + ACK injection at ack_pos
      SendAsync(pcs_rec, std_logic_vector(to_unsigned(c_pcs_active, c_rec_width)));
      SendAsync(pcs_rec, std_logic_vector(to_unsigned(c_inj_ack, c_rec_width)),
                         std_logic_vector(to_unsigned(v_stream.ack_pos, c_rec_width)));

      -- Push expected bus stream before driving bytes (PCS VC pops on SP)
      for i in 0 to v_stream.len - 1 loop
        Push(pcs_rec.BurstFifo, to_slv(v_stream.bits(i)));
      end loop;

      -- Drive frame through DUT (PCS VC checks concurrently)
      Send(llc_rec, v_frame(0), "10");
      Send(llc_rec, v_frame(1), "00");

      for i in 2 to v_last_byte loop
        Send(llc_rec, v_frame(i), "00");
      end loop;

      -- Check received bit stream
      CheckBurst(pcs_rec, GetFifoCount(pcs_rec.BurstFifo));

      -- Check transfer status
      Check(llc_rec, c_transmitted);

      ICover(ide_cov, to_integer(unsigned'(0 => v_metadata.ide)));
      ICover(fdf_cov, to_integer(unsigned'(0 => v_metadata.fdf)));
      ICover(dlc_cov, to_integer(unsigned(v_metadata.dlc)));

    end loop frame_loop;

    AffirmIf(GetAlertLogID(ide_cov), IsCovered(ide_cov), "IDE coverage met");
    AffirmIf(GetAlertLogID(fdf_cov), IsCovered(fdf_cov), "FDF coverage met");
    AffirmIf(GetAlertLogID(dlc_cov), IsCovered(dlc_cov), "DLC coverage met");

    Print("----------------------------------------------------------------------------");
    Print("Test done!");
    Print("----------------------------------------------------------------------------");
    WriteBin(ide_cov);
    WriteBin(fdf_cov);
    WriteBin(dlc_cov);
    EndOfTestReports(ReportAll => true);
    std.env.finish;
    wait;

  end process p_test_ctrl;

end architecture tb;
