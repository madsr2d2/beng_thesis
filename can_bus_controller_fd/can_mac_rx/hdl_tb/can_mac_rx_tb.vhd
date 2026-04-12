--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_mac_rx (fsm_rx + bs + crc).
--                  p_pcs_vc       - PCS bus source VC (drives bitstream with SP pulses).
--                  p_llc_sink_vc  - LLC Avalon-ST sink VC (collects and verifies received frame bytes).
--                  p_test_ctrl    - Test sequencer: reset, normal usage.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-04-05  MRDSA     Initial happy-path testbench
--                2026-04-12  MRDSA     Restructured to company TB standard
--                                      with OSVVM transaction interfaces
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
  constant c_rec_width    : natural := 16;

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
  signal test_id      : AlertLogIDType;
  signal check_id     : AlertLogIDType;
  signal ide_cov      : CoverageIDType;
  signal fdf_cov      : CoverageIDType;
  signal dlc_cov      : CoverageIDType;
  signal init_barrier : integer_barrier := 1;

  -- Transaction interfaces
  signal pcs_rec : StreamRecType(
    DataToModel    (c_rec_width - 1 downto 0),
    ParamToModel   (c_rec_width - 1 downto 0),
    DataFromModel  (c_rec_width - 1 downto 0),
    ParamFromModel (c_rec_width - 1 downto 0)
  );
  signal llc_rec : StreamRecType(
    DataToModel    (c_rec_width - 1 downto 0),
    ParamToModel   (c_rec_width - 1 downto 0),
    DataFromModel  (c_rec_width - 1 downto 0),
    ParamFromModel (c_rec_width - 1 downto 0)
  );

  -- Bus reintegration sync
  signal pcs_ready : boolean := false;

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
    RV.InitSeed(random_seed);
    SetAlertStopCount(ERROR, 1);
    v_test_id  := NewID("can_mac_rx");
    v_check_id := NewID("Frame check", v_test_id);
    v_ide_cov  := NewID("IDE Coverage", v_test_id, ReportMode => ENABLED);
    v_fdf_cov  := NewID("FDF Coverage", v_test_id, ReportMode => ENABLED);
    v_dlc_cov  := NewID("DLC Coverage", v_test_id, ReportMode => ENABLED);
    RV.InitSeed(RV'instance_name & to_string(now));
    AddBins(v_ide_cov, c_bin_at_least, GenBin(0, 1));
    AddBins(v_fdf_cov, c_bin_at_least, GenBin(0, 1));
    AddBins(v_dlc_cov, c_bin_at_least, GenBin(0, c_dlc_max));
    pcs_rec.BurstFifo <= NewID("PCS Source Burst fifo");
    llc_rec.BurstFifo <= NewID("LLC Sink Burst fifo");
    test_id  <= v_test_id;
    check_id <= v_check_id;
    ide_cov  <= v_ide_cov;
    fdf_cov  <= v_fdf_cov;
    dlc_cov  <= v_dlc_cov;
    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  fce_i.error_passive_request <= '0';
  fce_i.error_active_request  <= '1';
  llc_i.avalon_st_sink.ready  <= '1';

  ----------------------------------------------------------------------------
  -- DUT
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
  -- PCS VC
  ----------------------------------------------------------------------------
  p_pcs_vc : process is
    variable v_bus_val  : std_logic;
    variable v_bit      : std_logic_vector(c_rec_width - 1 downto 0);

    -- Drive one bit: set bus_polarity, wait, pulse SP, deassert SP
    procedure drive_bit (constant pol : in std_logic) is
    begin
      WaitForClock(clk, c_sp_interval - 1);
      pcs_i.bus_polarity <= pol;
      pcs_i.sample_point <= '1';
      WaitForClock(clk);
      pcs_i.sample_point <= '0';
    end procedure drive_bit;

  begin
    pcs_i <= c_pcs_to_mac_if_reset;
    WaitForBarrier(init_barrier);
    wait until reset = '0';
    WaitForClock(clk, 5);

    -- Bus reintegration: feed 11 recessive bits so DUT reaches s_idle
    for i in 0 to c_bus_idle_condition_width - 1 loop
      drive_bit(c_recessive);
    end loop;
    pcs_ready <= true;

    pcs_vc_loop : loop
      -- Wait for SEND_BURST transaction
      wait until rising_edge(clk);

      if TransactionPending(pcs_rec.Rdy, pcs_rec.Ack) then
        case pcs_rec.Operation is
          when SEND_BURST =>
            -- Feed all bits from BurstFifo
            while not Empty(pcs_rec.BurstFifo) loop
              v_bit    := Pop(pcs_rec.BurstFifo);
              v_bus_val := v_bit(0);
              drive_bit(v_bus_val);
            end loop;
            FinishTransaction(pcs_rec.Ack); -- Ack the transaction
          when others =>
            FinishTransaction(pcs_rec.Ack);
        end case;
      end if;
    end loop pcs_vc_loop;
  end process p_pcs_vc;

  ----------------------------------------------------------------------------
  -- LLC Sink VC
  ----------------------------------------------------------------------------
  p_llc_sink_vc : process is
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

    llc_sink_loop : loop
      wait until rising_edge(clk);

      -- Collect bytes
      if (not v_got_frame and llc_o.avalon_st_source.valid = '1') then
        v_frame(v_byte_idx) := llc_o.avalon_st_source.data;
        if (llc_o.avalon_st_source.endofpacket = '1') then
          v_frame_len := v_byte_idx + 1;
          v_got_frame := true;
        else
          v_byte_idx := v_byte_idx + 1;
        end if;
      end if;

      -- Check received frame
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
    end loop llc_sink_loop;
  end process p_llc_sink_vc;

  ----------------------------------------------------------------------------
  -- p_test_ctrl
  ----------------------------------------------------------------------------
  p_test_ctrl : process is

    --------------------------------------------------------------------------
    -- gen_frame: random LLC frame + expected bus stream
    --------------------------------------------------------------------------
    procedure gen_frame (
      variable frame    : out t_llc_frame;
      variable metadata : out t_llc_metadata;
      variable stream   : out t_bus_stream
    ) is
      variable v_data_len : natural;
    begin
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
      frame(0)(5)          := '0';
      frame(0)(1 downto 0) := "00";
      frame(1)(3 downto 0) := "0000";
      if (metadata.fdf = '0') then
        frame(0)(c_llc_frame_esi) := '0';
        frame(0)(c_llc_frame_brs) := '0';
      else
        frame(0)(c_llc_frame_ftyp) := '0';
      end if;

      -- Zero ID bits beyond the transmitted width
      if (metadata.ide = '1') then
        frame(5)(2 downto 0) := "000";
      else
        frame(3)(4 downto 0) := "00000";
        frame(4)             := (others => '0');
        frame(5)             := (others => '0');
      end if;

      -- Zero data bytes beyond the transmitted length
      v_data_len := dlc_to_data_length(to_integer(unsigned(metadata.dlc)), metadata.fdf);
      for i in v_data_len to c_max_data_bytes - 1 loop
        frame(c_data_offset + i) := (others => '0');
      end loop;
    end procedure gen_frame;

    --------------------------------------------------------------------------
    -- Submit stream to PCS VC and verify LLC output
    --------------------------------------------------------------------------
    procedure submit_and_verify (
      variable v_frame       : in t_llc_frame;
      variable v_stream      : in t_bus_stream;
      variable v_exp_len     : in natural;
      variable v_frame_count : in natural
    ) is
    begin
      -- Push bus stream bits into PCS BurstFifo
      for i in 0 to v_stream.len - 1 loop
        Push(pcs_rec.BurstFifo, std_logic_vector(to_unsigned(
          std_logic'pos(v_stream.bits(i)), c_rec_width)));
      end loop;

      -- Push expected LLC bytes into LLC BurstFifo
      for i in 0 to v_exp_len - 1 loop
        Push(llc_rec.BurstFifo, std_logic_vector(resize(unsigned(v_frame(i)), c_rec_width)));
      end loop;

      -- Play bus stream (blocks until done)
      SendBurst(pcs_rec, v_stream.len);

      -- Verify LLC collected frame
      Check(llc_rec,
        std_logic_vector(to_unsigned(v_exp_len, c_rec_width)),
        std_logic_vector(to_unsigned(v_frame_count, c_rec_width)));
    end procedure submit_and_verify;

    --------------------------------------------------------------------------
    -- Test 1: Reset
    --------------------------------------------------------------------------
    procedure test_reset is
    begin
      Print("--------------------------------------------------------------------------");
      Print("Test 1: Reset");
      Print("--------------------------------------------------------------------------");
      AffirmIf(check_id, pcs_o = c_mac_to_pcs_if_reset, "pcs_o not reset correctly");
      AffirmIf(check_id, fce_o = c_mac_to_fce_if_reset, "fce_o not reset correctly");
      AffirmIf(check_id, llc_o = c_mac_rx_to_llc_if_reset, "llc_o not reset correctly");
    end procedure test_reset;

    --------------------------------------------------------------------------
    -- Test 2: Normal usage - cover all frame format combinations
    --------------------------------------------------------------------------
    procedure test_normal is
      variable v_frame       : t_llc_frame;
      variable v_metadata    : t_llc_metadata;
      variable v_stream      : t_bus_stream;
      variable v_exp_len     : natural;
      variable v_frame_count : natural := 0;
    begin
      Print("--------------------------------------------------------------------------");
      Print("Test 2: Normal Usage");
      Print("--------------------------------------------------------------------------");

      wait until pcs_ready;
      WaitForClock(clk, 5);

      while not (IsCovered(ide_cov) and IsCovered(fdf_cov) and IsCovered(dlc_cov)) loop
        v_frame_count := v_frame_count + 1;

        gen_frame(v_frame, v_metadata, v_stream);
        v_exp_len := c_data_offset + dlc_to_data_length(
          to_integer(unsigned(v_metadata.dlc)), v_metadata.fdf
        );

        submit_and_verify(v_frame, v_stream, v_exp_len, v_frame_count);

        ICover(ide_cov, to_integer(unsigned'("" & v_metadata.ide)));
        ICover(fdf_cov, to_integer(unsigned'("" & v_metadata.fdf)));
        ICover(dlc_cov, to_integer(unsigned(v_metadata.dlc)));

        Log(test_id,
          "Frame " & to_string(v_frame_count) &
          " ide=" & to_string(v_metadata.ide) &
          " fdf=" & to_string(v_metadata.fdf) &
          " dlc=" & to_hstring(v_metadata.dlc) &
          " len=" & to_string(v_stream.len), DEBUG);
      end loop;
    end procedure test_normal;

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
    WaitForClock(clk, 5);

    test_reset;
    test_normal;

    report_results;
    std.env.finish;
    wait;
  end process p_test_ctrl;

end architecture tb;
