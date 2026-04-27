--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   MAC sub-layer testbench (can_mac_tx + can_mac_rx with shared PCS model).
--                  p_pcs_model      - Shared PCS model (SP generation, bus routing).
--                  p_tx_llc_vc      - TX LLC Avalon-ST source VC (drives frame bytes to can_mac_tx).
--                  p_llc_sink_vc    - RX LLC Avalon-ST sink VC (collects and verifies received frame bytes).
--                  p_gating_monitor - Latches unexpected RX activity while transmitting_i asserted.
--                  p_test_ctrl      - Coverage-driven test sequencer.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-04-14  TMYAES:   [TRIT-4355] [FPGA] Controlling FSM form MAC layer in CAN-FD module
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
use work.pk_can_tb.all;

entity can_mac_tb is
  generic (
    gc_TbTimeOut   : time := 500 ms;
    gc_TbClkPeriod : time := 10 ns
  );
end entity can_mac_tb;

architecture tb of can_mac_tb is

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

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal clk   : std_logic;
  signal reset : std_logic := '1';

  -- Shared bus (dominant-wins / wired-AND)
  signal bus_level : std_logic;

  -- TX module interface (can_mac_tx)
  signal tx_llc_i : t_can_llc_mac_tx_if_s2d;
  signal tx_llc_o : t_can_llc_mac_tx_if_d2s;
  signal tx_pcs_i : t_can_mac_pcs_if_s2m := c_pcs_to_mac_if_reset;
  signal tx_pcs_o : t_can_mac_pcs_if_m2s;
  signal tx_fce_i : t_can_mac_fce_if_s2m := c_fce_to_mac_if_reset;
  signal tx_fce_o : t_can_mac_fce_if_m2s;

  -- Transfer status latch (TX)
  signal status_latch : std_logic_vector(2 downto 0) := c_ongoing;
  signal clear_status : boolean := false;

  -- RX DUT interface (can_mac_rx)
  signal rx_llc_i : t_can_llc_mac_rx_if_d2s;
  signal rx_llc_o : t_can_llc_mac_rx_if_s2d;
  signal rx_pcs_i : t_can_mac_pcs_if_s2m := c_pcs_to_mac_if_reset;
  signal rx_pcs_o : t_can_mac_pcs_if_m2s;
  signal rx_fce_i : t_can_mac_fce_if_s2m := c_fce_to_mac_if_reset;
  signal rx_fce_o : t_can_mac_fce_if_m2s;

  -- OSVVM signals
  shared variable RV : RandomPType;
  signal test_id      : AlertLogIDType;
  signal check_id     : AlertLogIDType;
  signal ide_cov      : CoverageIDType;
  signal fdf_cov      : CoverageIDType;
  signal dlc_cov      : CoverageIDType;
  signal init_barrier : integer_barrier := 1;
  signal test_num     : natural;

  -- Transaction interfaces
  signal tx_llc_rec : StreamRecType(
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

  -- TX gating for RX
  signal transmitting : std_logic := '0';

  -- Gating test latches (driven only by p_gating_monitor)
  signal pcs_valid_seen  : boolean := false;
  signal llc_valid_seen  : boolean := false;
  signal fce_active_seen : boolean := false;
  signal clear_latches   : boolean := false;

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
    v_test_id  := NewID("can_mac");
    v_check_id := NewID("Frame check", v_test_id);
    v_ide_cov  := NewID("IDE Coverage", v_test_id, ReportMode => ENABLED);
    v_fdf_cov  := NewID("FDF Coverage", v_test_id, ReportMode => ENABLED);
    v_dlc_cov  := NewID("DLC Coverage", v_test_id, ReportMode => ENABLED);
    RV.InitSeed(RV'instance_name & to_string(now));
    AddBins(v_ide_cov, c_bin_at_least, GenBin(0, 1));
    AddBins(v_fdf_cov, c_bin_at_least, GenBin(0, 1));
    AddBins(v_dlc_cov, c_bin_at_least, GenBin(0, c_dlc_max));
    tx_llc_rec.BurstFifo <= NewID("TX LLC Burst fifo");
    llc_rec.BurstFifo    <= NewID("RX LLC Burst fifo");
    test_id  <= v_test_id;
    check_id <= v_check_id;
    ide_cov  <= v_ide_cov;
    fdf_cov  <= v_fdf_cov;
    dlc_cov  <= v_dlc_cov;
    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  -- FCE: error-active for both TX and RX
  tx_fce_i.error_active <= '1';
  rx_fce_i.error_active <= '1';

  -- RX LLC sink always ready
  rx_llc_i.avalon_st_sink.ready <= '1';

  ----------------------------------------------------------------------------
  -- Shared bus: dominant-wins
  ---------------------------------------------------------------------------- 
  bus_level <= tx_pcs_o.tx_data and rx_pcs_o.tx_data;

  ----------------------------------------------------------------------------
  -- TX module: can_mac_tx (bit-stream source)
  ----------------------------------------------------------------------------
  u_mac_tx : entity work.can_mac_tx
    port map (
      clk   => clk,
      rst   => reset,
      llc_i => tx_llc_i,
      llc_o => tx_llc_o,
      pcs_i => tx_pcs_i,
      pcs_o => tx_pcs_o,
      fce_i => tx_fce_i,
      fce_o => tx_fce_o
    );

  ----------------------------------------------------------------------------
  -- RX DUT: can_mac_rx
  ----------------------------------------------------------------------------
  u_mac_rx : entity work.can_mac_rx
    port map (
      clk            => clk,
      rst            => reset,
      llc_i          => rx_llc_i,
      llc_o          => rx_llc_o,
      pcs_i          => rx_pcs_i,
      pcs_o          => rx_pcs_o,
      fce_i          => rx_fce_i,
      fce_o          => rx_fce_o,
      transmitting_i => transmitting
    );

  ----------------------------------------------------------------------------
  -- Transfer status latch (TX)
  ----------------------------------------------------------------------------
  p_status_latch : process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' or clear_status then
        status_latch <= c_ongoing;
      else
        status_latch <= tx_llc_o.transfer_status when tx_llc_o.transfer_status /= c_ongoing;
      end if;
    end if;
  end process p_status_latch;

  ----------------------------------------------------------------------------
  -- Shared PCS model: generates SP strobes for both TX and RX paths.
  ----------------------------------------------------------------------------
  p_pcs_model : process is
    variable v_tq_count        : natural range 0 to c_bit_time := 0;
    variable v_active_bit_time : natural := c_bit_time;
    variable v_active_sp       : natural := c_sp;
    variable v_ssp_strobe      : std_logic;
  begin
    WaitForBarrier(init_barrier);

    pcs_loop : loop
      wait until rising_edge(clk);
      v_tq_count := 0 when v_tq_count = v_active_bit_time else v_tq_count + 1;
      if v_tq_count = 0 then
        v_active_bit_time := c_data_bit_time when tx_pcs_o.next_bit_is_brs = '1' else c_bit_time;
        v_active_sp       := c_data_sp       when tx_pcs_o.next_bit_is_brs = '1' else c_sp;
      end if;
      tx_pcs_i.sample_point <= '1' when v_tq_count = v_active_sp else '0';
      rx_pcs_i.sample_point <= '1' when v_tq_count = v_active_sp + 2 else '0'; -- The 2 is from 1 clk internal can_mac_tx delay + 1 clk TB delay = 2
      v_ssp_strobe := '1' when v_tq_count = c_data_ssp and tx_pcs_o.next_bit_is_brs = '1' else '0';
      
      -- TX PCS input
      tx_pcs_i.secondary_sample_point <= v_ssp_strobe;
      tx_pcs_i.tdc_delay              <= (others => '0'); -- Zero delay bus model
      tx_pcs_i.rx_data           <= bus_level;

      -- RX PCS input
      rx_pcs_i.secondary_sample_point <= v_ssp_strobe;
      rx_pcs_i.tdc_delay              <= (others => '0'); -- Zero delay bus model
      rx_pcs_i.rx_data           <= bus_level;
    end loop pcs_loop;
  end process p_pcs_model;

  ----------------------------------------------------------------------------
  -- TX LLC source VC (drives frame bytes to can_mac_tx)
  ----------------------------------------------------------------------------
  p_tx_llc_vc : process is
  begin
    WaitForBarrier(init_barrier);
    tx_llc_vc_loop : loop
      WaitForTransaction(tx_llc_rec.Rdy, tx_llc_rec.Ack);
      case tx_llc_rec.Operation is
        when SEND =>
          tx_llc_i.avalon_st_source.valid         <= '1';
          tx_llc_i.avalon_st_source.data          <= SafeResize(std_logic_vector(tx_llc_rec.DataToModel), c_byte_width);
          tx_llc_i.avalon_st_source.startofpacket <= tx_llc_rec.ParamToModel(1);
          tx_llc_i.avalon_st_source.endofpacket   <= tx_llc_rec.ParamToModel(0);
          wait until rising_edge(clk) and tx_llc_o.avalon_st_sink.ready = '1';
          tx_llc_i.avalon_st_source.valid <= '0';
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
  -- RX LLC Sink VC (collects and verifies received frame bytes)
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
      if (not v_got_frame and rx_llc_o.avalon_st_source.valid = '1') then
        v_frame(v_byte_idx) := rx_llc_o.avalon_st_source.data;
        if (rx_llc_o.avalon_st_source.endofpacket = '1') then
          v_frame_len := v_byte_idx + 1;
          v_got_frame := true;
        else
          v_byte_idx := v_byte_idx + 1;
        end if;
      end if;

      -- Check received frame against expected
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
  -- Gating monitor: latch if pcs_o.valid or llc_o.valid pulses while TX active
  ----------------------------------------------------------------------------
  p_gating_monitor : process (clk) is
  begin
    if rising_edge(clk) then
      if clear_latches then
        pcs_valid_seen  <= false;
        llc_valid_seen  <= false;
        fce_active_seen <= false;
      elsif transmitting = '1' then
        if rx_pcs_o.tx_data = c_dominant then
          pcs_valid_seen <= true;
        end if;
        if rx_llc_o.avalon_st_source.valid = '1' then
          llc_valid_seen <= true;
        end if;
        if rx_fce_o /= c_mac_to_fce_if_reset then
          fce_active_seen <= true;
        end if;
      end if;
    end if;
  end process p_gating_monitor;

  ----------------------------------------------------------------------------
  -- p_test_ctrl
  ----------------------------------------------------------------------------
  p_test_ctrl : process is

    --------------------------------------------------------------------------
    -- gen_frame: random LLC frame
    --------------------------------------------------------------------------
    procedure gen_frame (tx_frame : out t_llc_frame; metadata : out t_llc_metadata; last_byte : out natural) is
      variable v_data_len : natural;
    begin
      for i in tx_frame'range loop
        tx_frame(i) := RV.RandSlv(8);
      end loop;
      tx_frame(0)(c_llc_frame_ide) := std_logic(to_unsigned(GetRandPoint(ide_cov), 1)(0));
      tx_frame(0)(c_llc_frame_fdf) := std_logic(to_unsigned(GetRandPoint(fdf_cov), 1)(0));
      tx_frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end) := std_logic_vector(to_unsigned(GetRandPoint(dlc_cov), 4));
      metadata   := extract_metadata(tx_frame(0), tx_frame(1));
      v_data_len := dlc_to_data_length(to_integer(unsigned(metadata.dlc)), metadata.fdf);
      last_byte  := c_llc_frame_data_byte + v_data_len - 1;

      -- Zero the unused fields
      tx_frame(0)(5)          := '0';
      tx_frame(0)(1 downto 0) := "00";
      tx_frame(1)(3 downto 0) := "0000";
      if (metadata.fdf = '0') then
        tx_frame(0)(c_llc_frame_esi) := '0';
        tx_frame(0)(c_llc_frame_brs) := '0';
      else
        tx_frame(0)(c_llc_frame_ftyp) := '0';
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
    procedure submit_and_verify (v_tx_frame : in t_llc_frame; v_last_byte : in natural;  v_metadata : in t_llc_metadata; v_frame_count : in natural) is
      variable v_exp_len : natural;
    begin
      v_exp_len := c_data_offset + dlc_to_data_length( to_integer(unsigned(v_metadata.dlc)), v_metadata.fdf);

      -- Push expected RX bytes into LLC sink BurstFifo
      for i in 0 to v_exp_len - 1 loop
        Push(llc_rec.BurstFifo, std_logic_vector(resize(unsigned(v_tx_frame(i)), c_rec_width)));
      end loop;

      -- Drive TX frame bytes through can_mac_tx
      for i in 0 to v_last_byte loop
        if (i = 0) then
          Send(tx_llc_rec, v_tx_frame(i), c_avalon_sop_byte);
        elsif (i < v_last_byte) then
          Send(tx_llc_rec, v_tx_frame(i), c_avalon_byte);
        else
          Send(tx_llc_rec, v_tx_frame(i), c_avalon_eop_byte);
        end if;
      end loop;

      -- Wait for TX to complete with c_transmitted
      Check(tx_llc_rec, std_logic_vector(resize(unsigned(c_transmitted), c_rec_width)));

      -- Verify RX collected the frame
      Check(llc_rec, std_logic_vector(to_unsigned(v_exp_len, c_rec_width)), std_logic_vector(to_unsigned(v_frame_count, c_rec_width)));
    end procedure submit_and_verify;

    --------------------------------------------------------------------------
    -- Test 1: Reset
    --------------------------------------------------------------------------
    procedure test_reset is
    begin
      test_num <= 1;
      Print("--------------------------------------------------------------------------");
      Print("Test 1: Reset");
      Print("--------------------------------------------------------------------------");
      AffirmIf(check_id, rx_pcs_o = c_mac_to_pcs_if_reset, "pcs_o not reset correctly");
      AffirmIf(check_id, rx_fce_o = c_mac_to_fce_if_reset, "fce_o not reset correctly");
      AffirmIf(check_id, rx_llc_o = c_mac_rx_to_llc_if_reset, "llc_o not reset correctly");
    end procedure test_reset;

    --------------------------------------------------------------------------
    -- Test 2: Normal usage - cover all frame format combinations
    --------------------------------------------------------------------------
    procedure test_normal is
      variable v_frame    : t_llc_frame;
      variable v_metadata    : t_llc_metadata;
      variable v_last_byte   : natural;
      variable v_frame_count : natural := 0;
    begin
      test_num <= 2;
      Print("--------------------------------------------------------------------------");
      Print("Test 2: Normal Usage (MAC TX -> MAC RX)");
      Print("--------------------------------------------------------------------------");

      while not (IsCovered(ide_cov) and IsCovered(fdf_cov) and IsCovered(dlc_cov)) loop
        v_frame_count := v_frame_count + 1;

        gen_frame(v_frame, v_metadata, v_last_byte);
        submit_and_verify(v_frame,  v_last_byte, v_metadata, v_frame_count);

        ICover(ide_cov, to_integer(unsigned'("" & v_metadata.ide)));
        ICover(fdf_cov, to_integer(unsigned'("" & v_metadata.fdf)));
        ICover(dlc_cov, to_integer(unsigned(v_metadata.dlc)));
      end loop;
    end procedure test_normal;

    --------------------------------------------------------------------------
    -- Test 3: Gating RX during transmission
    --------------------------------------------------------------------------
    procedure test_transmitting is
      variable v_frame     : t_llc_frame;
      variable v_metadata  : t_llc_metadata;
      variable v_last_byte : natural;
    begin
      test_num <= 3;
      Print("--------------------------------------------------------------------------");
      Print("Test 3: Gating RX during transmission (RX should remain passive when transmitting_i is high)  ");
      Print("--------------------------------------------------------------------------");

      -- Clear latches and assert transmitting
      clear_latches <= true;
      WaitForClock(clk);
      clear_latches <= false;
      transmitting  <= '1';
      WaitForClock(clk, 5);

      -- Generate a frame and send via TX module
      gen_frame(v_frame, v_metadata, v_last_byte);

      -- Drive TX frame bytes (TX will complete but RX should ignore)
      for i in 0 to v_last_byte loop
        if (i = 0) then
          Send(tx_llc_rec, v_frame(i), c_avalon_sop_byte);
        elsif (i < v_last_byte) then
          Send(tx_llc_rec, v_frame(i), c_avalon_byte);
        else
          Send(tx_llc_rec, v_frame(i), c_avalon_eop_byte);
        end if;
      end loop;

      -- Wait for TX to finish (RX won't ACK so TX gets disturbed)
      wait until status_latch /= c_ongoing;

      -- Verify that RX did not activate during the frame
      AffirmIf(check_id, not pcs_valid_seen, "pcs_o.polarity went dominant during transmission");
      AffirmIf(check_id, not llc_valid_seen, "llc_o.valid pulsed during transmission");
      AffirmIf(check_id, not fce_active_seen, "fce_o signaled during transmission");
      AffirmIf(check_id, status_latch = c_disturbed, "TX transfer status should be c_disturbed since RX did not ACK");

      transmitting <= '0';
      WaitForClock(clk, 10);
    end procedure test_transmitting;

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

    -- Wait for both TX and RX to complete bus reintegration (11+ bit times)
    WaitForClock(clk, (c_bus_idle_condition_width + 2) * (c_bit_time + 1));

    test_reset;
    test_normal;
    test_transmitting;

    report_results;
    std.env.finish;
    wait;
  end process p_test_ctrl;

end architecture tb;
