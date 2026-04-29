--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_mac_pcs_fce.
--                  p_tx_llc_vc   - Avalon-ST source VC driving LLC TX frame bytes to DUT 1.
--                  p_status_latch - Continuous monitor latching DUT 1 transfer status.
--                  p_test_ctrl   - Coverage-driven test sequencer (IDE, FDF, DLC bins).
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-04-27  MRDSA:    Local port of company can_mac_pcs_fce_tb.
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.OsvvmContext;
  use osvvm.ScoreboardPkg_slv.all;
library osvvm_common;
  context osvvm_common.OsvvmCommonContext;

use work.pk_can_types.all;
use work.pk_can_tb.all;

entity can_mac_pcs_fce_tb is
  generic(
    gc_TbTimeOut   : time := 500 ms;
    gc_TbClkPeriod : time := 10 ns
  );
end entity can_mac_pcs_fce_tb;

architecture tb of can_mac_pcs_fce_tb is

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  -- Nominal bit timing (ISO 7.3.2, midpoint of subtype ranges in pk_can_types)
  constant c_sp       : natural := 80;
  constant c_bit_time : natural := 100;

  -- Data phase bit timing
  constant c_data_sp       : natural := 8;
  constant c_data_ssp      : natural := 7;
  constant c_data_bit_time : natural := 10;

  constant c_bin_at_least : natural := 50;
  constant c_rec_width    : natural := 16;

  -- Avalon-ST byte encoding [1] = startofpacket, [0] = endofpacket
  constant c_avalon_sop_byte : std_logic_vector := "10";
  constant c_avalon_eop_byte : std_logic_vector := "01";
  constant c_avalon_byte     : std_logic_vector := "00";

  -- Bus/transceiver delays. Driven from signals so the test sequencer can
  -- sweep across delay configurations and confirm the design is robust to a
  -- range of physical timings (not tuned to one specific value).
  signal s_bus_delay        : time := 150 ns;
  signal s_transceiver_tx_d : time := 300 ns;
  signal s_transceiver_rx_d : time := 300 ns;

  -- Delay-sweep configuration table. Each entry is (transceiver_tx,
  -- transceiver_rx, bus). Round-trip propagation = 2*(tx + rx) + 2*bus.
  type t_delay_cfg is record
    tx_d  : time;
    rx_d  : time;
    bus_d : time;
  end record;
  type t_delay_cfg_arr is array (natural range <>) of t_delay_cfg;
  -- The sweep starts with the nominal (ISO-derived) configuration which is
  -- known to pass, then increments toward higher delays first and lower
  -- delays after. Currently only the nominal config passes -- see TODO in
  -- can_mac_fsm.vhd / can_mac_bs.vhd for the design-tuning issue this
  -- exposes. The sweep is included so any future timing-tolerance fixes
  -- can be validated against multiple operating points.
  constant c_delay_sweep : t_delay_cfg_arr := (
    (tx_d => 300 ns, rx_d => 300 ns, bus_d => 150 ns),  -- nominal (passes today)
    (tx_d => 400 ns, rx_d => 400 ns, bus_d => 200 ns),
    (tx_d => 250 ns, rx_d => 250 ns, bus_d => 125 ns),
    (tx_d => 200 ns, rx_d => 200 ns, bus_d => 100 ns),
    (tx_d => 100 ns, rx_d => 100 ns, bus_d =>  50 ns),
    (tx_d =>  50 ns, rx_d =>  50 ns, bus_d =>  25 ns)
  );
  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal clk   : std_logic;
  signal reset : std_logic := '1';

  -- Bus signals ------------------------------------------------------------
  signal tx_on_bus_at_tx : std_logic := c_recessive;
  signal tx_on_bus_at_rx : std_logic := c_recessive;
  signal rx_on_bus_at_rx : std_logic := c_recessive;
  signal rx_on_bus_at_tx : std_logic := c_recessive;
  signal bus_at_tx       : std_logic := c_recessive;
  signal bus_at_rx       : std_logic := c_recessive;

  -- DUT bus interfaces -----------------------------------------------------
  signal tx_from_tx_dut : std_logic;
  signal tx_from_rx_dut : std_logic;
  signal rx_at_rx_dut   : std_logic := c_recessive;
  signal rx_at_tx_dut   : std_logic := c_recessive;

  -- DUT 1 interfaces
  signal llc_to_mac_tx_s2d_dut_1 : t_can_llc_mac_tx_if_s2d;
  signal llc_to_mac_tx_d2s_dut_1 : t_can_llc_mac_tx_if_d2s;
  signal mac_to_llc_tx_s2d_dut_1 : t_can_llc_mac_rx_if_s2d;
  signal mac_to_llc_tx_d2s_dut_1 : t_can_llc_mac_rx_if_d2s;

  -- DUT 2 interfaces
  signal llc_to_mac_tx_s2d_dut_2 : t_can_llc_mac_tx_if_s2d;
  signal llc_to_mac_tx_d2s_dut_2 : t_can_llc_mac_tx_if_d2s;
  signal mac_to_llc_tx_s2d_dut_2 : t_can_llc_mac_rx_if_s2d;
  signal mac_to_llc_tx_d2s_dut_2 : t_can_llc_mac_rx_if_d2s;

  -- LLC-FCE interfaces (both DUTs always in normal mode for simulation)
  signal llc_fce_i_dut_1 : t_can_llc_fce_if_m2s := (normal_mode => '1');
  signal llc_fce_o_dut_1 : t_can_fce_llc_if_s2m;
  signal llc_fce_i_dut_2 : t_can_llc_fce_if_m2s := (normal_mode => '1');
  signal llc_fce_o_dut_2 : t_can_fce_llc_if_s2m;

  -- Transfer status latch (TX DUT 1)
  signal status_latch : std_logic_vector(2 downto 0) := c_ongoing;
  signal clear_status : boolean                      := false;

  -- OSVVM signals
  shared variable RV           : RandomPType;
  signal          test_id      : AlertLogIDType;
  signal          check_id     : AlertLogIDType;
  signal          ide_cov      : CoverageIDType;
  signal          fdf_cov      : CoverageIDType;
  signal          dlc_cov      : CoverageIDType;
  signal          init_barrier : integer_barrier := 1;
  signal          test_num     : natural;

  -- Transaction interfaces
  signal tx_llc_rec : StreamRecType(
    DataToModel(c_rec_width - 1 downto 0),
    ParamToModel(c_rec_width - 1 downto 0),
    DataFromModel(c_rec_width - 1 downto 0),
    ParamFromModel(c_rec_width - 1 downto 0)
  );
  signal llc_rec    : StreamRecType(
    DataToModel(c_rec_width - 1 downto 0),
    ParamToModel(c_rec_width - 1 downto 0),
    DataFromModel(c_rec_width - 1 downto 0),
    ParamFromModel(c_rec_width - 1 downto 0)
  );

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
    variable v_test_id  : AlertLogIDType;
    variable v_check_id : AlertLogIDType;
    variable v_ide_cov  : CoverageIDType;
    variable v_fdf_cov  : CoverageIDType;
    variable v_dlc_cov  : CoverageIDType;
  begin
    SetAlertStopCount(ERROR, 1);
    v_test_id            := NewID("can_mac_pcs_fce");
    v_check_id           := NewID("Frame check", v_test_id);
    v_ide_cov            := NewID("IDE Coverage", v_test_id, ReportMode => ENABLED);
    v_fdf_cov            := NewID("FDF Coverage", v_test_id, ReportMode => ENABLED);
    v_dlc_cov            := NewID("DLC Coverage", v_test_id, ReportMode => ENABLED);
    RV.InitSeed(RV'instance_name & to_string(now));
    AddBins(v_ide_cov, c_bin_at_least, GenBin(0, 1));
    AddBins(v_fdf_cov, c_bin_at_least, GenBin(0, 1));
    AddBins(v_dlc_cov, c_bin_at_least, GenBin(0, c_dlc_max));
    tx_llc_rec.BurstFifo <= NewID("TX LLC Burst fifo");
    llc_rec.BurstFifo    <= NewID("RX LLC Burst fifo");
    test_id              <= v_test_id;
    check_id             <= v_check_id;
    ide_cov              <= v_ide_cov;
    fdf_cov              <= v_fdf_cov;
    dlc_cov              <= v_dlc_cov;
    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  -- DUT 1: RX LLC sink always ready (prevents backpressure stall)
  mac_to_llc_tx_d2s_dut_1.avalon_st_sink.ready <= '1';
  -- DUT 2: TX LLC idle, RX LLC sink always ready
  llc_to_mac_tx_s2d_dut_2.avalon_st_source.valid         <= '0';
  llc_to_mac_tx_s2d_dut_2.avalon_st_source.data          <= (others => '0');
  llc_to_mac_tx_s2d_dut_2.avalon_st_source.startofpacket <= '0';
  llc_to_mac_tx_s2d_dut_2.avalon_st_source.endofpacket   <= '0';
  mac_to_llc_tx_d2s_dut_2.avalon_st_sink.ready           <= '1';

  ----------------------------------------------------------------------------
  -- DUT 1 (Transmitter)
  ----------------------------------------------------------------------------
  u_dut_1 : entity work.can_mac_pcs_fce
    port map(
      clk      => clk,
      rst      => reset,
      tx_llc_i  => llc_to_mac_tx_s2d_dut_1,
      tx_llc_o  => llc_to_mac_tx_d2s_dut_1,
      rx_llc_i  => mac_to_llc_tx_d2s_dut_1,
      rx_llc_o  => mac_to_llc_tx_s2d_dut_1,
      llc_fce_i => llc_fce_i_dut_1,
      llc_fce_o => llc_fce_o_dut_1,
      tx_o      => tx_from_tx_dut,
      rx_i      => rx_at_tx_dut
    );

  ----------------------------------------------------------------------------
  -- DUT 2 (Receiver)
  ----------------------------------------------------------------------------
  u_dut_2 : entity work.can_mac_pcs_fce
    port map(
      clk      => clk,
      rst      => reset,
      tx_llc_i  => llc_to_mac_tx_s2d_dut_2,
      tx_llc_o  => llc_to_mac_tx_d2s_dut_2,
      rx_llc_i  => mac_to_llc_tx_d2s_dut_2,
      rx_llc_o  => mac_to_llc_tx_s2d_dut_2,
      llc_fce_i => llc_fce_i_dut_2,
      llc_fce_o => llc_fce_o_dut_2,
      tx_o      => tx_from_rx_dut,
      rx_i      => rx_at_rx_dut
    );

  ----------------------------------------------------------------------------
  -- Bus model: dominant-wins wired-AND
  ----------------------------------------------------------------------------
  -- Bus at TX DUT
  bus_at_tx <= tx_on_bus_at_tx and rx_on_bus_at_tx;

  p_tx_onto_bus : process is
  begin
    wait on tx_from_tx_dut;
    tx_on_bus_at_tx <= transport tx_from_tx_dut after s_transceiver_tx_d;
  end process;

  p_tx_loopback : process is
  begin
    wait on bus_at_tx;
    rx_at_tx_dut <= transport bus_at_tx after s_transceiver_rx_d;
  end process;

  -- Bus at RX DUT
  bus_at_rx <= tx_on_bus_at_rx and rx_on_bus_at_rx;

  p_rx_onto_wire : process is
  begin
    wait on tx_from_rx_dut;
    rx_on_bus_at_rx <= transport tx_from_rx_dut after s_transceiver_tx_d;
  end process;

  p_rx_sees_bus : process is
  begin
    wait on bus_at_rx;
    rx_at_rx_dut <= transport bus_at_rx after s_transceiver_rx_d;
  end process;

  -- Cross-propagation between the two DUT ends
  p_tx_propagate : process is
  begin
    wait on tx_on_bus_at_tx;
    tx_on_bus_at_rx <= transport tx_on_bus_at_tx after s_bus_delay;
  end process;

  p_rx_propagate : process is
  begin
    wait on rx_on_bus_at_rx;
    rx_on_bus_at_tx <= transport rx_on_bus_at_rx after s_bus_delay;
  end process;

  ----------------------------------------------------------------------------
  -- Transfer status latch (DUT 1 TX)
  ----------------------------------------------------------------------------
  p_status_latch : process(clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' or clear_status then
        status_latch <= c_ongoing;
      else
        if llc_to_mac_tx_d2s_dut_1.transfer_status /= c_ongoing
           and llc_to_mac_tx_d2s_dut_1.transfer_status /= status_latch then
          status_latch <= llc_to_mac_tx_d2s_dut_1.transfer_status;
        end if;
      end if;
    end if;
  end process p_status_latch;

  ----------------------------------------------------------------------------
  -- TX LLC source VC
  ----------------------------------------------------------------------------
  p_tx_llc_vc : process is
  begin
    WaitForBarrier(init_barrier);
    tx_llc_vc_loop : loop
      WaitForTransaction(tx_llc_rec.Rdy, tx_llc_rec.Ack);
      case tx_llc_rec.Operation is
        when SEND =>
          llc_to_mac_tx_s2d_dut_1.avalon_st_source.valid         <= '1';
          llc_to_mac_tx_s2d_dut_1.avalon_st_source.data          <= SafeResize(std_logic_vector(tx_llc_rec.DataToModel), c_byte_width);
          llc_to_mac_tx_s2d_dut_1.avalon_st_source.startofpacket <= tx_llc_rec.ParamToModel(1);
          llc_to_mac_tx_s2d_dut_1.avalon_st_source.endofpacket   <= tx_llc_rec.ParamToModel(0);
          wait until rising_edge(clk) and llc_to_mac_tx_d2s_dut_1.avalon_st_sink.ready = '1';
          llc_to_mac_tx_s2d_dut_1.avalon_st_source.valid         <= '0';
        when CHECK =>
          if status_latch = c_ongoing then
            wait until status_latch /= c_ongoing;
          end if;
          AffirmIfEqual(check_id, status_latch, std_logic_vector(tx_llc_rec.DataToModel(2 downto 0)), "Transfer status");
          clear_status <= true;
          wait until rising_edge(clk);
          clear_status <= false;
        when others => null;
      end case;
    end loop tx_llc_vc_loop;
  end process p_tx_llc_vc;

  ----------------------------------------------------------------------------
  -- RX LLC sink VC: collects bytes from DUT 2 RX output and services Check
  -- transactions on llc_rec.
  ----------------------------------------------------------------------------
  p_rx_llc_sink_vc : process is
    variable v_byte_idx  : natural := 0;
    variable v_frame     : t_llc_frame;
    variable v_frame_len : natural := 0;
    variable v_got_frame : boolean := false;
    variable v_exp_len   : natural;
    variable v_exp_byte  : std_logic_vector(c_rec_width - 1 downto 0);
    variable v_count     : natural;
  begin
    WaitForBarrier(init_barrier);
    wait until reset = '0';
    llc_rec.Ack <= llc_rec.Ack + 1;
    wait for 0 ns;

    rx_sink_loop : loop
      wait until rising_edge(clk);

      if (not v_got_frame and mac_to_llc_tx_s2d_dut_2.avalon_st_source.valid = '1') then
        v_frame(v_byte_idx) := mac_to_llc_tx_s2d_dut_2.avalon_st_source.data;
        if (mac_to_llc_tx_s2d_dut_2.avalon_st_source.endofpacket = '1') then
          v_frame_len := v_byte_idx + 1;
          v_got_frame := true;
        else
          v_byte_idx := v_byte_idx + 1;
        end if;
      end if;

      if v_got_frame and TransactionPending(llc_rec.Rdy, llc_rec.Ack) then
        case llc_rec.Operation is
          when CHECK =>
            v_exp_len := to_integer(unsigned(llc_rec.DataToModel(7 downto 0)));
            v_count   := to_integer(unsigned(llc_rec.ParamToModel(15 downto 0)));
            AffirmIfEqual(check_id, v_frame_len, v_exp_len, "Frame " & to_string(v_count) & " length");
            for i in 0 to v_exp_len - 1 loop
              v_exp_byte := Pop(llc_rec.BurstFifo);
              AffirmIfEqual(check_id, v_frame(i), v_exp_byte(7 downto 0), "Frame " & to_string(v_count) & " byte " & to_string(i));
            end loop;
            v_byte_idx  := 0;
            v_got_frame := false;
          when others => null;
        end case;
        FinishTransaction(llc_rec.Ack);
      end if;
    end loop rx_sink_loop;
  end process p_rx_llc_sink_vc;

  ----------------------------------------------------------------------------
  -- p_test_ctrl
  ----------------------------------------------------------------------------
  p_test_ctrl : process is

    --------------------------------------------------------------------------
    -- gen_frame: random LLC frame
    --------------------------------------------------------------------------
    procedure gen_frame(tx_frame : out t_llc_frame; metadata : out t_llc_metadata; last_byte : out natural) is
      variable v_data_len : natural;
    begin
      for i in tx_frame'range loop
        tx_frame(i) := RV.RandSlv(8);
      end loop;
      tx_frame(0)(c_llc_frame_ide)                                  := std_logic(to_unsigned(GetRandPoint(ide_cov), 1)(0));
      tx_frame(0)(c_llc_frame_fdf)                                  := std_logic(to_unsigned(GetRandPoint(fdf_cov), 1)(0));
      tx_frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end) := std_logic_vector(to_unsigned(GetRandPoint(dlc_cov), 4));
      metadata                                                      := extract_metadata(tx_frame(0), tx_frame(1));
      v_data_len                                                    := dlc_to_data_length(to_integer(unsigned(metadata.dlc)), metadata.fdf);
      last_byte                                                     := c_llc_frame_data_byte + v_data_len - 1;

      -- Zero unused / non-transmitted bits so the expected frame matches what
      -- the RX can actually reconstruct. Always force FTYP=0 (data frame) so
      -- the test only generates data frames; RTR coverage is not in scope here.
      tx_frame(0)(c_llc_frame_ftyp) := '0';
      tx_frame(0)(2 downto 0)       := "000";
      tx_frame(1)(3 downto 0)       := "0000";
      if (metadata.fdf = '0') then
        tx_frame(0)(c_llc_frame_esi) := '0';
        tx_frame(0)(c_llc_frame_brs) := '0';
      end if;
      if (metadata.ide = '1') then
        tx_frame(5)(2 downto 0) := "000";
      else
        tx_frame(3)(4 downto 0) := "00000";
        tx_frame(4)             := (others => '0');
        tx_frame(5)             := (others => '0');
      end if;
      for i in v_data_len to c_max_data_bytes - 1 loop
        tx_frame(c_data_offset + i) := (others => '0');
      end loop;
    end procedure gen_frame;

    --------------------------------------------------------------------------
    -- submit_and_verify: send frame via TX, verify at RX
    --------------------------------------------------------------------------
    procedure submit_and_verify(v_tx_frame : in t_llc_frame; v_last_byte : in natural; v_metadata : in t_llc_metadata; v_frame_count : in natural) is
      variable v_exp_len : natural;
    begin
      v_exp_len := c_data_offset + dlc_to_data_length(to_integer(unsigned(v_metadata.dlc)), v_metadata.fdf);

      -- Push expected RX bytes into LLC sink BurstFifo
      for i in 0 to v_exp_len - 1 loop
        Push(llc_rec.BurstFifo, std_logic_vector(resize(unsigned(v_tx_frame(i)), c_rec_width)));
      end loop;

      -- Drive TX frame bytes through DUT 1
      for i in 0 to v_last_byte loop
        if (i = 0) then
          Send(tx_llc_rec, v_tx_frame(i), c_avalon_sop_byte);
        elsif (i < v_last_byte) then
          Send(tx_llc_rec, v_tx_frame(i), c_avalon_byte);
        else
          Send(tx_llc_rec, v_tx_frame(i), c_avalon_eop_byte);
        end if;
      end loop;

      -- Wait for TX to complete
      Check(tx_llc_rec, std_logic_vector(resize(unsigned(c_transmitted), c_rec_width)));

      -- Verify DUT 2 RX received the correct frame
      Check(llc_rec,
        std_logic_vector(to_unsigned(v_exp_len, c_rec_width)),
        std_logic_vector(to_unsigned(v_frame_count, c_rec_width)));
    end procedure submit_and_verify;

    --------------------------------------------------------------------------
    -- Test 1: Normal usage - cover all frame format combinations
    --------------------------------------------------------------------------
    procedure test_normal is
      variable v_frame       : t_llc_frame;
      variable v_metadata    : t_llc_metadata;
      variable v_last_byte   : natural;
      variable v_frame_count : natural := 0;
    begin
      test_num <= 1;
      Print("--------------------------------------------------------------------------");
      Print("Test 1: Normal Usage (DUT 1 TX -> DUT 2 RX)");
      Print("--------------------------------------------------------------------------");

      while not (IsCovered(ide_cov) and IsCovered(fdf_cov) and IsCovered(dlc_cov)) loop
        v_frame_count := v_frame_count + 1;

        gen_frame(v_frame, v_metadata, v_last_byte);
        submit_and_verify(v_frame, v_last_byte, v_metadata, v_frame_count);

        ICover(ide_cov, to_integer(unsigned'("" & v_metadata.ide)));
        ICover(fdf_cov, to_integer(unsigned'("" & v_metadata.fdf)));
        ICover(dlc_cov, to_integer(unsigned(v_metadata.dlc)));
      end loop;
    end procedure test_normal;

    --------------------------------------------------------------------------
    -- Test 2: Delay sweep -- exercise the DUTs across a range of bus and
    -- transceiver propagation delays. For each entry in c_delay_sweep we
    -- update the bus model delay signals and submit a small batch of
    -- random frames; any c_disturbed status or RX byte mismatch increments
    -- the alert count for that delay configuration.
    --------------------------------------------------------------------------
    procedure test_delay_sweep(num_frames_per_cfg : natural := 20) is
      variable v_frame       : t_llc_frame;
      variable v_metadata    : t_llc_metadata;
      variable v_last_byte   : natural;
      variable v_frame_count : natural := 0;
    begin
      test_num <= 2;
      Print("--------------------------------------------------------------------------");
      Print("Test 2: Delay Sweep");
      Print("--------------------------------------------------------------------------");

      for i in c_delay_sweep'range loop
        s_transceiver_tx_d <= c_delay_sweep(i).tx_d;
        s_transceiver_rx_d <= c_delay_sweep(i).rx_d;
        s_bus_delay        <= c_delay_sweep(i).bus_d;

        -- Wait several bit times for any in-flight propagation events to
        -- drain through the new delay values before launching the next
        -- batch of frames.
        WaitForClock(clk, 10 * c_bit_time);

        Print("--- Delay config " & to_string(i)
              & ": tx="    & to_string(c_delay_sweep(i).tx_d)
              & " rx="     & to_string(c_delay_sweep(i).rx_d)
              & " bus="    & to_string(c_delay_sweep(i).bus_d)
              & " (rt="    & to_string(2 * (c_delay_sweep(i).tx_d
                                          + c_delay_sweep(i).rx_d
                                          + c_delay_sweep(i).bus_d)) & ")");

        for j in 1 to num_frames_per_cfg loop
          v_frame_count := v_frame_count + 1;
          gen_frame(v_frame, v_metadata, v_last_byte);
          submit_and_verify(v_frame, v_last_byte, v_metadata, v_frame_count);
        end loop;
      end loop;
    end procedure test_delay_sweep;

    --------------------------------------------------------------------------
    procedure report_results is
    begin
      AffirmIf(test_id, IsCovered(ide_cov), "IDE covered");
      AffirmIf(test_id, IsCovered(fdf_cov), "FDF covered");
      AffirmIf(test_id, IsCovered(dlc_cov), "DLC covered");
      WriteBin(ide_cov);
      WriteBin(fdf_cov);
      WriteBin(dlc_cov);
      if (EndOfTestReports(ReportAll => true) = 0) then
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

    -- Wait for both DUTs to complete bus reintegration (11+ bit times)
    WaitForClock(clk, (c_bus_idle_condition_width + 2) * (c_bit_time + 1));

    test_normal;
    test_delay_sweep(5);

    report_results;
    std.env.finish;
    wait;
  end process p_test_ctrl;

end architecture tb;
