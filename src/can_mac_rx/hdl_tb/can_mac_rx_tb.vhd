--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_mac_rx (fsm_rx + bs + crc).
--                  p_pcs_vc       - PCS bus source VC (drives bitstream with SP pulses).
--                  p_llc_sink_vc  - LLC Avalon-ST sink VC (collects received frame bytes).
--                  p_test_ctrl    - Coverage-driven test sequencer.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-04-05  MRDSA     Initial happy-path testbench
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;
  use work.pk_can_tb.all;

library osvvm;
  context osvvm.OsvvmContext;

entity can_mac_rx_tb is
  generic (
    gc_TbTimeOut   : time := 50 ms;
    gc_TbClkPeriod : time := 10 ns
  );
end entity can_mac_rx_tb;

architecture tb of can_mac_rx_tb is

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  constant c_sp_interval  : natural := 10;

  constant c_bin_at_least : natural := 50;
  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal clk   : std_logic;
  signal reset : std_logic := '1';

  -- DUT interface
  signal llc_i : t_can_llc_mac_rx_if_d2s;
  signal llc_o : t_can_llc_mac_rx_if_s2d;
  signal pcs_i : t_can_mac_pcs_if_s2m := c_pcs_to_mac_if_reset;
  signal pcs_o : t_can_mac_pcs_if_m2s;
  signal fce_i : t_can_mac_fce_if_s2m := c_fce_to_mac_if_reset;
  signal fce_o : t_can_mac_fce_if_m2s;

  -- OSVVM signals
  shared variable RV : RandomPType;
  signal test_id     : AlertLogIDType;
  signal check_id    : AlertLogIDType;
  signal ide_cov     : CoverageIDType;
  signal fdf_cov     : CoverageIDType;
  signal dlc_cov     : CoverageIDType;
  signal init_barrier : std_logic := '0';

  -- Inter-process communication
  signal pcs_stream    : t_bus_stream;
  signal pcs_start     : boolean := false;
  signal pcs_done      : boolean := false;
  signal pcs_ready     : boolean := false;
  signal llc_frame_rx  : t_llc_frame;
  signal llc_frame_len : natural := 0;
  signal llc_rx_done   : boolean := false;

  ----------------------------------------------------------------------------
  -- gen_frame: random LLC frame + expected bus stream via shared ref model
  ----------------------------------------------------------------------------
  procedure gen_frame (
    variable frame    : out t_llc_frame;
    variable metadata : out t_llc_metadata;
    variable stream   : out t_bus_stream
  ) is
    variable v_id_bits  : natural;
    variable v_data_len : natural;
  begin
    -- Randomize everything (same approach as TX TB)
    for i in frame'range loop
      frame(i) := RV.RandSlv(8);
    end loop;
    frame(0)(c_llc_frame_ide) := std_logic(to_unsigned(GetRandPoint(ide_cov), 1)(0));
    frame(0)(c_llc_frame_fdf) := std_logic(to_unsigned(GetRandPoint(fdf_cov), 1)(0));
    frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end) :=
      std_logic_vector(to_unsigned(GetRandPoint(dlc_cov), 4));
    metadata := extract_metadata(frame(0), frame(1));
    stream   := build_bus_stream(frame, metadata, false);

    -- Sanitize: zero fields the RX FSM cannot reconstruct from the bus.
    -- The FSM resets llc_frame to all-zero on SOF, then only writes
    -- fields present in the received frame format.
    frame(0)(5)          := '0';
    frame(0)(1 downto 0) := "00";
    frame(1)(3 downto 0) := "0000";
    if (metadata.fdf = '0') then
      frame(0)(c_llc_frame_esi) := '0';
      frame(0)(c_llc_frame_brs) := '0';
    else
      -- FD: RRS is always dominant on the bus (ISO 11898-1 Sec. 8.4)
      frame(0)(c_llc_frame_ftyp) := '0';
    end if;

    -- Zero ID bits beyond the transmitted width
    if (metadata.ide = '1') then
      v_id_bits := c_base_id_width + c_extended_id_width;
    else
      v_id_bits := c_base_id_width;
    end if;
    for i in v_id_bits to 31 loop
      frame(c_id_offset + i / 8)(7 - (i mod 8)) := '0';
    end loop;

    -- Zero data bytes beyond the transmitted length
    v_data_len := dlc_to_data_length(to_integer(unsigned(metadata.dlc)), metadata.fdf);
    for i in v_data_len to c_max_data_bytes - 1 loop
      frame(c_data_offset + i) := (others => '0');
    end loop;
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
    Alert(test_id, "Testbench timeout", FAILURE);
    std.env.finish;
    wait;
  end process p_timeout;

  p_init : process is
  begin
    test_id <= NewID("can_mac_rx");
    wait for 0 ns;
    check_id <= NewID("Frame check", test_id);
    ide_cov  <= NewID("IDE Coverage", test_id, ReportMode => ENABLED);
    fdf_cov  <= NewID("FDF Coverage", test_id, ReportMode => ENABLED);
    dlc_cov  <= NewID("DLC Coverage", test_id, ReportMode => ENABLED);
    wait for 0 ns;
    SetAlertStopCount(FAILURE, 1);
    RV.InitSeed(RV'instance_name & to_string(now));
    AddBins(ide_cov, c_bin_at_least, GenBin(0, 1));
    AddBins(fdf_cov, c_bin_at_least, GenBin(0, 1));
    AddBins(dlc_cov, c_bin_at_least, GenBin(0, c_dlc_max));
    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  fce_i.error_passive_request <= '0';
  fce_i.error_active_request  <= '1';
  llc_i.avalon_st_sink.ready  <= '1';

  ----------------------------------------------------------------------------
  -- DUT instantiation
  ----------------------------------------------------------------------------
  u_dut : entity work.can_mac_rx
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
  -- PCS Bus Source VC: feeds bus stream bit-by-bit with SP pulses.
  -- Implements wired-AND: if DUT drives dominant via pcs_o, bus is dominant.
  ----------------------------------------------------------------------------
  p_pcs_vc : process is
    variable v_sp_count : natural := 0;
    variable v_bit_idx  : natural := 0;
    variable v_bus_val  : std_logic;
  begin
    pcs_i <= c_pcs_to_mac_if_reset;
    WaitForBarrier(init_barrier);
    wait until reset = '0';
    WaitForClock(clk, 5);

    -- Bus reintegration: feed 11 recessive bits so DUT reaches s_idle
    for i in 0 to c_bus_idle_condition_width - 1 loop
      pcs_i.bus_polarity <= c_recessive;
      pcs_i.sample_point           <= '0';
      WaitForClock(clk, c_sp_interval - 1);
      pcs_i.sample_point <= '1';
      WaitForClock(clk);
    end loop;
    pcs_i.sample_point  <= '0';
    pcs_ready <= true;
    WaitForClock(clk, 5);

    pcs_vc_loop : loop
      wait until pcs_start;
      pcs_done   <= false;
      v_bit_idx  := 0;
      v_sp_count := 0;

      bit_loop : while v_bit_idx < pcs_stream.len loop
        WaitForClock(clk);

        v_bus_val := pcs_stream.bits(v_bit_idx);
        if (pcs_o.valid = '1' and pcs_o.polarity = c_dominant) then
          v_bus_val := c_dominant;
        end if;

        pcs_i.bus_polarity <= v_bus_val;
        pcs_i.sample_point           <= '0';

        if (v_sp_count = c_sp_interval - 1) then
          pcs_i.sample_point   <= '1';
          v_sp_count := 0;
          v_bit_idx  := v_bit_idx + 1;
        else
          v_sp_count := v_sp_count + 1;
        end if;
      end loop bit_loop;

      WaitForClock(clk, 2);
      pcs_i.sample_point           <= '0';
      pcs_i.bus_polarity <= c_recessive;
      pcs_done           <= true;
    end loop pcs_vc_loop;
  end process p_pcs_vc;

  ----------------------------------------------------------------------------
  -- LLC Sink VC: collects bytes from Avalon-ST output until EOP.
  ----------------------------------------------------------------------------
  p_llc_sink_vc : process is
    variable v_byte_idx : natural := 0;
  begin
    WaitForBarrier(init_barrier);
    wait until reset = '0';

    llc_sink_loop : loop
      llc_rx_done <= false;
      v_byte_idx  := 0;

      sop_wait : loop
        WaitForClock(clk);
        exit sop_wait when llc_o.avalon_st_source.valid = '1'
                       and llc_o.avalon_st_source.startofpacket = '1';
      end loop sop_wait;

      llc_frame_rx(v_byte_idx) <= llc_o.avalon_st_source.data;

      if (llc_o.avalon_st_source.endofpacket = '1') then
        llc_frame_len <= 1;
        llc_rx_done   <= true;
        WaitForClock(clk, 2);
        next llc_sink_loop;
      end if;
      v_byte_idx := v_byte_idx + 1;

      collect_loop : loop
        WaitForClock(clk);
        if (llc_o.avalon_st_source.valid = '1') then
          llc_frame_rx(v_byte_idx) <= llc_o.avalon_st_source.data;
          if (llc_o.avalon_st_source.endofpacket = '1') then
            llc_frame_len <= v_byte_idx + 1;
            llc_rx_done   <= true;
            WaitForClock(clk, 2);
            exit collect_loop;
          end if;
          v_byte_idx := v_byte_idx + 1;
        end if;
      end loop collect_loop;

    end loop llc_sink_loop;
  end process p_llc_sink_vc;

  ----------------------------------------------------------------------------
  -- Test sequencer: coverage-driven happy-path frames.
  ----------------------------------------------------------------------------
  p_test_ctrl : process is
    variable v_frame       : t_llc_frame;
    variable v_metadata    : t_llc_metadata;
    variable v_stream      : t_bus_stream;
    variable v_exp_len     : natural;
    variable v_frame_count : natural := 0;
  begin
    WaitForBarrier(init_barrier);
    wait until reset = '0';
    WaitForClock(clk, 10);

    -- Test 1: Reset check
    AffirmIf(check_id, pcs_o = c_mac_to_pcs_if_reset, "pcs_o reset");
    AffirmIf(check_id, fce_o = c_mac_to_fce_if_reset, "fce_o reset");
    AffirmIf(check_id, llc_o = c_mac_rx_to_llc_if_reset, "llc_o reset");

    -- Wait for PCS VC to complete bus reintegration
    wait until pcs_ready;
    WaitForClock(clk, 5);

    -- Test 2: Coverage-driven happy path
    frame_loop : while not (IsCovered(ide_cov) and IsCovered(fdf_cov) and IsCovered(dlc_cov)) loop
      v_frame_count := v_frame_count + 1;

      gen_frame(v_frame, v_metadata, v_stream);
      v_exp_len := c_data_offset + dlc_to_data_length(
        to_integer(unsigned(v_metadata.dlc)), v_metadata.fdf
      );

      -- Load stream and trigger PCS VC
      pcs_stream <= v_stream;
      WaitForClock(clk);
      pcs_start  <= true;
      WaitForClock(clk);
      pcs_start  <= false;

      -- Wait for LLC sink to collect the frame
      wait until llc_rx_done for v_stream.len * c_sp_interval * gc_TbClkPeriod * 2;
      if not llc_rx_done then
        Alert(test_id, "Frame " & to_string(v_frame_count) &
          " LLC timeout (ide=" & to_string(v_metadata.ide) &
          " fdf=" & to_string(v_metadata.fdf) &
          " dlc=" & to_hstring(v_metadata.dlc) &
          " len=" & to_string(v_stream.len) & ")", ERROR);
        if (not pcs_done) then
          wait until pcs_done;
        end if;
        WaitForClock(clk, 20);
        next frame_loop;
      end if;
      WaitForClock(clk);

      -- Verify received frame
      AffirmIfEqual(check_id, llc_frame_len, v_exp_len,
        "Frame " & to_string(v_frame_count) & " length");

      for i in 0 to v_exp_len - 1 loop
        AffirmIfEqual(check_id, llc_frame_rx(i), v_frame(i),
          "Frame " & to_string(v_frame_count) & " byte " & to_string(i));
      end loop;

      ICover(ide_cov, to_integer(unsigned'("" & v_metadata.ide)));
      ICover(fdf_cov, to_integer(unsigned'("" & v_metadata.fdf)));
      ICover(dlc_cov, to_integer(unsigned(v_metadata.dlc)));

      if (not pcs_done) then
        wait until pcs_done;
      end if;
      WaitForClock(clk, 5);

      Log(test_id,
        "Frame " & to_string(v_frame_count) &
        " ide=" & to_string(v_metadata.ide) &
        " fdf=" & to_string(v_metadata.fdf) &
        " dlc=" & to_hstring(v_metadata.dlc) &
        " len=" & to_string(v_stream.len), DEBUG);
    end loop frame_loop;

    AffirmIf(GetAlertLogID(ide_cov), IsCovered(ide_cov), "IDE covered");
    AffirmIf(GetAlertLogID(fdf_cov), IsCovered(fdf_cov), "FDF covered");
    AffirmIf(GetAlertLogID(dlc_cov), IsCovered(dlc_cov), "DLC covered");
    WriteBin(ide_cov);
    WriteBin(fdf_cov);
    WriteBin(dlc_cov);
    EndOfTestReports(ReportAll => true);
    std.env.finish;
    wait;
  end process p_test_ctrl;

end architecture tb;
