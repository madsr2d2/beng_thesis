--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_llc_mac_pcs_fce. Two DUT instances share a bus model with
--                configurable transceiver and propagation delays sized using ISO 11898-1
--                sec. 7.3.2 / 7.3.4 constraints. DUT 1 transmits, DUT 2 receives and ACKs.
--                The user TX interface drives 71-byte legacy frames directly; the LLC
--                converts them internally and handles retransmission on lost arbitration.
--
--                  p_tx_vc_dut_1        - Avalon-ST source VC: drives TX legacy bytes to DUT 1.
--                  p_tx_vc_dut_2        - Avalon-ST source VC: drives TX legacy bytes to DUT 2.
--                  p_rx_llc_vc_dut_2    - Avalon-ST sink VC: collects DUT 2 RX bytes (internal
--                                         format from MAC) and compares byte-for-byte.
--                  p_status_latch_dut_1 - Monitor: captures first non-ongoing TX status for DUT 1.
--                  p_status_latch_dut_2 - Monitor: captures first non-ongoing TX status for DUT 2.
--                  p_bus_off_latch      - Monitor: sticky latch for DUT 1 bus-off event.
--                  p_test_ctrl          - Coverage-driven sequencer: runs five tests (reset,
--                                         normal TX/RX, delay sweep, lost arbitration, bus-off
--                                         recovery) until IDE, FDF, BRS, ESI, DLC, and FTYP bins
--                                         are all covered.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-05-06  MRDSA     Initial version based on can_mac_pcs_fce_tb.
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

entity can_llc_mac_pcs_fce_tb is
  generic(
    gc_TbTimeOut   : time := 1 sec;
    gc_TbClkPeriod : time := 10 ns
  );
end entity can_llc_mac_pcs_fce_tb;

architecture tb of can_llc_mac_pcs_fce_tb is

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  constant c_bin_at_least    : natural := 10;
  constant c_rec_width       : natural := 16;
  constant c_frame_count     : natural := 100;
  constant c_avalon_sop_byte : std_logic_vector := "10";
  constant c_avalon_eop_byte : std_logic_vector := "01";
  constant c_avalon_byte     : std_logic_vector := "00";

  -- Delay configuration (same budget as can_mac_pcs_fce_tb) ------------------
  constant c_nom_prop_seg_time : time := 800 ns;
  constant c_transceiver_d     : time := 50 ns;
  constant c_bus_delay_max     : time := (c_nom_prop_seg_time - 4 * c_transceiver_d) / 2;
  type t_delay_cfg is record
    transceiver_d : time;
    bus_d         : time;
  end record;
  type t_delay_cfg_arr is array (natural range <>) of t_delay_cfg;
  constant c_delay_sweep : t_delay_cfg_arr := (
    (transceiver_d => 50 ns, bus_d => 300 ns),
    (transceiver_d => 40 ns, bus_d => 240 ns),
    (transceiver_d => 30 ns, bus_d => 180 ns),
    (transceiver_d => 20 ns, bus_d => 120 ns),
    (transceiver_d => 10 ns, bus_d =>  60 ns)
  );
  ----------------------------------------------------------------------------

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal clk      : std_logic;
  signal reset    : std_logic := '1';
  signal test_rst : std_logic := '0';
  signal bus_delay     : time := c_bus_delay_max;
  signal transceiver_d : time := c_transceiver_d;
  -- DUT port connections
  signal dut1_tx : std_logic;
  signal dut2_tx : std_logic;
  signal dut1_rx : std_logic := c_recessive;
  signal dut2_rx : std_logic := c_recessive;
  -- Wire signals with transceiver delay
  signal dut1_wire     : std_logic := c_recessive;
  signal dut2_wire     : std_logic := c_recessive;
  signal dut1_wire_far : std_logic := c_recessive;
  signal dut2_wire_far : std_logic := c_recessive;
  -- Wired-AND bus
  signal bus_dut1 : std_logic := c_recessive;
  signal bus_dut2 : std_logic := c_recessive;
  signal dut_1_rx_recessive : boolean := false;
  -- Bus-off latch (DUT 1)
  signal bus_off_seen  : boolean := false;
  signal bus_off_clear : boolean := false;
  -- DUT 1 user TX interface
  signal user_tx_s2d_dut_1 : t_can_user_llc_tx_if_s2d := ( avalon_st_source => (data => (others => '0'), valid => '0', startofpacket => '0', endofpacket => '0'), abort_request    => '0'
  );
  signal user_tx_d2s_dut_1 : t_can_user_llc_tx_if_d2s;
  -- DUT 2 user TX interface
  signal user_tx_s2d_dut_2 : t_can_user_llc_tx_if_s2d := ( avalon_st_source => (data => (others => '0'), valid => '0', startofpacket => '0', endofpacket => '0'), abort_request    => '0'
  );
  signal user_tx_d2s_dut_2 : t_can_user_llc_tx_if_d2s;
  -- DUT 1 RX LLC interface (internal format from MAC)
  signal rx_llc_s2d_dut_1 : t_can_llc_mac_rx_if_s2d;
  signal rx_llc_d2s_dut_1 : t_can_llc_mac_rx_if_d2s := c_llc_to_mac_rx_if_reset;
  -- DUT 2 RX LLC interface
  signal rx_llc_s2d_dut_2 : t_can_llc_mac_rx_if_s2d;
  signal rx_llc_d2s_dut_2 : t_can_llc_mac_rx_if_d2s := c_llc_to_mac_rx_if_reset;
  -- Debug bus_off outputs
  signal debug_bus_off_dut_1 : std_logic;
  signal debug_bus_off_dut_2 : std_logic;
  -- Transfer status latches
  signal status_latch_dut_1  : std_logic_vector(2 downto 0) := c_ongoing;
  signal clear_status_dut_1  : boolean := false;
  signal status_latch_dut_2  : std_logic_vector(2 downto 0) := c_ongoing;
  signal clear_status_dut_2  : boolean := false;
  -- OSVVM
  shared variable RV       : RandomPType;
  signal test_id            : AlertLogIDType;
  signal check_id           : AlertLogIDType;
  signal ide_cov            : CoverageIDType;
  signal fdf_cov            : CoverageIDType;
  signal dlc_cov            : CoverageIDType;
  signal ftyp_cov           : CoverageIDType;
  signal brs_cov            : CoverageIDType;
  signal esi_cov            : CoverageIDType;
  signal init_barrier       : integer_barrier := 1;
  signal test_num           : natural;
  -- Transaction interfaces
  signal tx_rec_dut_1 : StreamRecType(
    DataToModel(c_rec_width - 1 downto 0),
    ParamToModel(c_rec_width - 1 downto 0),
    DataFromModel(c_rec_width - 1 downto 0),
    ParamFromModel(c_rec_width - 1 downto 0)
  );
  signal tx_rec_dut_2 : StreamRecType(
    DataToModel(c_rec_width - 1 downto 0),
    ParamToModel(c_rec_width - 1 downto 0),
    DataFromModel(c_rec_width - 1 downto 0),
    ParamFromModel(c_rec_width - 1 downto 0)
  );
  signal rx_rec_dut_2 : StreamRecType(
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
    std.env.stop(5);
  end process p_timeout;

  p_init : process is
    variable v_test_id  : AlertLogIDType;
    variable v_check_id : AlertLogIDType;
    variable v_ide_cov  : CoverageIDType;
    variable v_fdf_cov  : CoverageIDType;
    variable v_dlc_cov  : CoverageIDType;
    variable v_ftyp_cov : CoverageIDType;
    variable v_brs_cov  : CoverageIDType;
    variable v_esi_cov  : CoverageIDType;
  begin
    SetAlertStopCount(ERROR, 20);
    SetLogEnable(DEBUG, false);
    v_test_id  := NewID("can_llc_mac_pcs_fce");
    v_check_id := NewID("Frame check", v_test_id);
    v_ide_cov  := NewID("IDE Coverage",  v_test_id, ReportMode => ENABLED);
    v_fdf_cov  := NewID("FDF Coverage",  v_test_id, ReportMode => ENABLED);
    v_dlc_cov  := NewID("DLC Coverage",  v_test_id, ReportMode => ENABLED);
    v_ftyp_cov := NewID("FTYP Coverage", v_test_id, ReportMode => ENABLED);
    v_brs_cov  := NewID("BRS Coverage",  v_test_id, ReportMode => ENABLED);
    v_esi_cov  := NewID("ESI Coverage",  v_test_id, ReportMode => ENABLED);
    RV.InitSeed(RV'instance_name & to_string(now));
    AddBins(v_ide_cov,  c_bin_at_least, GenBin(0, 1));
    AddBins(v_fdf_cov,  c_bin_at_least, GenBin(0, 1));
    AddBins(v_dlc_cov,  c_bin_at_least, GenBin(0, c_dlc_max));
    AddBins(v_ftyp_cov, c_bin_at_least, GenBin(0, 1));
    AddBins(v_brs_cov,  c_bin_at_least, GenBin(0, 1));
    AddBins(v_esi_cov,  c_bin_at_least, GenBin(0, 1));
    tx_rec_dut_1.BurstFifo <= NewID("TX Burst fifo DUT 1");
    rx_rec_dut_2.BurstFifo <= NewID("RX Burst fifo DUT 2");
    -- RX sinks always ready
    rx_llc_d2s_dut_1.avalon_st_sink.ready <= '1';
    rx_llc_d2s_dut_2.avalon_st_sink.ready <= '1';
    test_id   <= v_test_id;
    check_id  <= v_check_id;
    ide_cov   <= v_ide_cov;
    fdf_cov   <= v_fdf_cov;
    dlc_cov   <= v_dlc_cov;
    ftyp_cov  <= v_ftyp_cov;
    brs_cov   <= v_brs_cov;
    esi_cov   <= v_esi_cov;
    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  ----------------------------------------------------------------------------
  -- DUT 1
  ----------------------------------------------------------------------------
  u_dut_1 : entity work.can_llc_mac_pcs_fce
    port map(
      clk_i           => clk,
      reset_i         => reset or test_rst,
      user_tx_i       => user_tx_s2d_dut_1,
      user_tx_o       => user_tx_d2s_dut_1,
      rx_llc_i        => rx_llc_d2s_dut_1,
      rx_llc_o        => rx_llc_s2d_dut_1,
      tx_o            => dut1_tx,
      rx_i            => dut1_rx,
      debug_bus_off_o => debug_bus_off_dut_1
    );

  ----------------------------------------------------------------------------
  -- DUT 2
  ----------------------------------------------------------------------------
  u_dut_2 : entity work.can_llc_mac_pcs_fce
    port map(
      clk_i           => clk,
      reset_i         => reset or test_rst,
      user_tx_i       => user_tx_s2d_dut_2,
      user_tx_o       => user_tx_d2s_dut_2,
      rx_llc_i        => rx_llc_d2s_dut_2,
      rx_llc_o        => rx_llc_s2d_dut_2,
      tx_o            => dut2_tx,
      rx_i            => dut2_rx,
      debug_bus_off_o => debug_bus_off_dut_2
    );

  ----------------------------------------------------------------------------
  -- Bus model (identical to can_mac_pcs_fce_tb)
  ----------------------------------------------------------------------------
  bus_dut1 <= c_recessive when (dut_1_rx_recessive and not bus_off_seen) else dut1_wire and dut2_wire_far;
  bus_dut2 <= dut2_wire   when (dut_1_rx_recessive and not bus_off_seen) else dut1_wire_far and dut2_wire;

  p_dut1_tx_to_wire : process is
  begin
    wait on dut1_tx;
    dut1_wire <= transport dut1_tx after transceiver_d;
  end process;

  p_dut1_rx_from_bus : process is
  begin
    wait on bus_dut1;
    dut1_rx <= transport bus_dut1 after transceiver_d;
  end process;

  p_dut2_tx_to_wire : process is
  begin
    wait on dut2_tx;
    dut2_wire <= transport dut2_tx after transceiver_d;
  end process;

  p_dut2_rx_from_bus : process is
  begin
    wait on bus_dut2;
    dut2_rx <= transport bus_dut2 after transceiver_d;
  end process;

  p_propagate_dut1_to_dut2 : process is
  begin
    wait on dut1_wire;
    dut1_wire_far <= transport dut1_wire after bus_delay;
  end process;

  p_propagate_dut2_to_dut1 : process is
  begin
    wait on dut2_wire;
    dut2_wire_far <= transport dut2_wire after bus_delay;
  end process;

  ----------------------------------------------------------------------------
  -- Bus-off latch (DUT 1)
  ----------------------------------------------------------------------------
  p_bus_off_latch : process(clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' or bus_off_clear then
        bus_off_seen <= false;
      elsif debug_bus_off_dut_1 = '1' then
        bus_off_seen <= true;
      end if;
    end if;
  end process p_bus_off_latch;

  ----------------------------------------------------------------------------
  -- Transfer status latch (DUT 1)
  ----------------------------------------------------------------------------
  p_status_latch_dut_1 : process(clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' or clear_status_dut_1 then
        status_latch_dut_1 <= c_ongoing;
      elsif user_tx_d2s_dut_1.transfer_status /= c_ongoing and
            user_tx_d2s_dut_1.transfer_status /= status_latch_dut_1 then
        status_latch_dut_1 <= user_tx_d2s_dut_1.transfer_status;
      end if;
    end if;
  end process p_status_latch_dut_1;

  ----------------------------------------------------------------------------
  -- Transfer status latch (DUT 2)
  ----------------------------------------------------------------------------
  p_status_latch_dut_2 : process(clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' or clear_status_dut_2 then
        status_latch_dut_2 <= c_ongoing;
      elsif user_tx_d2s_dut_2.transfer_status /= c_ongoing and
            user_tx_d2s_dut_2.transfer_status /= status_latch_dut_2 then
        status_latch_dut_2 <= user_tx_d2s_dut_2.transfer_status;
      end if;
    end if;
  end process p_status_latch_dut_2;

  ----------------------------------------------------------------------------
  -- TX user source VC (DUT 1) -- drives 71-byte legacy frames
  ----------------------------------------------------------------------------
  p_tx_vc_dut_1 : process is
  begin
    WaitForBarrier(init_barrier);
    tx_vc_dut_1_loop : loop
      WaitForTransaction(tx_rec_dut_1.Rdy, tx_rec_dut_1.Ack);
      case tx_rec_dut_1.Operation is
        when SEND =>
          user_tx_s2d_dut_1.avalon_st_source.valid         <= '1';
          user_tx_s2d_dut_1.avalon_st_source.data          <= SafeResize(std_logic_vector(tx_rec_dut_1.DataToModel), c_byte_width);
          user_tx_s2d_dut_1.avalon_st_source.startofpacket <= tx_rec_dut_1.ParamToModel(1);
          user_tx_s2d_dut_1.avalon_st_source.endofpacket   <= tx_rec_dut_1.ParamToModel(0);
          wait until rising_edge(clk) and user_tx_d2s_dut_1.avalon_st_sink.ready = '1';
          user_tx_s2d_dut_1.avalon_st_source.valid         <= '0';
        when CHECK =>
          if status_latch_dut_1 = c_ongoing then
            wait until status_latch_dut_1 /= c_ongoing;
          end if;
          AffirmIfEqual(check_id, status_latch_dut_1, std_logic_vector(tx_rec_dut_1.DataToModel(2 downto 0)), "Transfer status");
        when others => null;
      end case;
    end loop tx_vc_dut_1_loop;
  end process p_tx_vc_dut_1;

  ----------------------------------------------------------------------------
  -- TX user source VC (DUT 2)
  ----------------------------------------------------------------------------
  p_tx_vc_dut_2 : process is
  begin
    WaitForBarrier(init_barrier);
    tx_vc_dut_2_loop : loop
      WaitForTransaction(tx_rec_dut_2.Rdy, tx_rec_dut_2.Ack);
      case tx_rec_dut_2.Operation is
        when SEND =>
          user_tx_s2d_dut_2.avalon_st_source.valid         <= '1';
          user_tx_s2d_dut_2.avalon_st_source.data          <= SafeResize(std_logic_vector(tx_rec_dut_2.DataToModel), c_byte_width);
          user_tx_s2d_dut_2.avalon_st_source.startofpacket <= tx_rec_dut_2.ParamToModel(1);
          user_tx_s2d_dut_2.avalon_st_source.endofpacket   <= tx_rec_dut_2.ParamToModel(0);
          wait until rising_edge(clk) and user_tx_d2s_dut_2.avalon_st_sink.ready = '1';
          user_tx_s2d_dut_2.avalon_st_source.valid         <= '0';
        when CHECK =>
          if status_latch_dut_2 = c_ongoing then
            wait until status_latch_dut_2 /= c_ongoing;
          end if;
          AffirmIfEqual(check_id, status_latch_dut_2, std_logic_vector(tx_rec_dut_2.DataToModel(2 downto 0)), "DUT 2 transfer status");
        when others => null;
      end case;
    end loop tx_vc_dut_2_loop;
  end process p_tx_vc_dut_2;

  ----------------------------------------------------------------------------
  -- RX LLC sink VC (DUT 2) -- collects internal-format bytes from MAC
  ----------------------------------------------------------------------------
  p_rx_llc_vc_dut_2 : process is
  begin
    WaitForBarrier(init_barrier);
    loop
      WaitForTransaction(clk, rx_rec_dut_2.Rdy, rx_rec_dut_2.Ack);
      case rx_rec_dut_2.Operation is
        when CHECK =>
          collect_loop : loop
            wait until rising_edge(clk);
            if rx_llc_s2d_dut_2.avalon_st_source.valid = '1' then
              report "DBG RX sop=" & to_string(rx_llc_s2d_dut_2.avalon_st_source.startofpacket)
                   & " eop=" & to_string(rx_llc_s2d_dut_2.avalon_st_source.endofpacket)
                   & " data=0x" & to_hstring(rx_llc_s2d_dut_2.avalon_st_source.data) severity note;
              Push(tx_rec_dut_1.BurstFifo, SafeResize(rx_llc_s2d_dut_2.avalon_st_source.data, c_rec_width));
              exit collect_loop when rx_llc_s2d_dut_2.avalon_st_source.endofpacket = '1';
            end if;
          end loop collect_loop;
          while not IsEmpty(tx_rec_dut_1.BurstFifo) loop
            AffirmIfEqual(check_id, Pop(tx_rec_dut_1.BurstFifo)(7 downto 0), Pop(rx_rec_dut_2.BurstFifo)(7 downto 0), "RX byte");
          end loop;
          AffirmIf(check_id, IsEmpty(rx_rec_dut_2.BurstFifo), "RX frame length matches expected");
        when others => null;
      end case;
    end loop;
  end process p_rx_llc_vc_dut_2;

  ----------------------------------------------------------------------------
  -- p_test_ctrl
  ----------------------------------------------------------------------------
  p_test_ctrl : process is

    --------------------------------------------------------------------------
    -- to_legacy_frame: convert internal t_llc_frame to 71-byte legacy format.
    -- Reverses the conversion performed by can_llc on frame capture.
    --------------------------------------------------------------------------
    function to_legacy_frame(internal : t_llc_frame) return t_legacy_frame is
      variable legacy   : t_legacy_frame := (others => (others => '0'));
      variable raw_id   : std_logic_vector(31 downto 0);
      variable ide      : std_logic;
      variable fdf      : std_logic;
      variable dlc      : natural;
      variable data_len : natural;
    begin
      ide  := internal(0)(c_llc_frame_ide);
      fdf  := internal(0)(c_llc_frame_fdf);
      dlc  := to_integer(unsigned(internal(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end)));
      data_len := dlc_to_data_length(dlc, fdf);

      raw_id := internal(2) & internal(3) & internal(4) & internal(5);

      if ide = '1' then
        -- Extended 29-bit: raw_id[31:3] packed from legacy bytes 0..3
        legacy(0)(4 downto 0) := raw_id(31 downto 27);
        legacy(1)              := raw_id(26 downto 19);
        legacy(2)              := raw_id(18 downto 11);
        legacy(3)              := raw_id(10 downto 3);
      else
        -- Base 11-bit: raw_id[31:21] packed from legacy bytes 2..3
        legacy(2)(2 downto 0) := raw_id(31 downto 29);
        legacy(3)              := raw_id(28 downto 21);
      end if;

      legacy(4)(6)          := ide;
      legacy(4)(5)          := fdf;
      legacy(4)(4)          := '0';
      legacy(4)(3 downto 0) := internal(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end);

      for i in 0 to data_len - 1 loop
        legacy(c_legacy_data_offset + i) := internal(c_data_offset + i);
      end loop;

      legacy(69)(0) := ide;
      legacy(70)(2) := internal(0)(c_llc_frame_brs);
      legacy(70)(1) := internal(0)(c_llc_frame_esi);
      legacy(70)(0) := internal(0)(c_llc_frame_ftyp);

      return legacy;
    end function to_legacy_frame;

    --------------------------------------------------------------------------
    -- clear_latches
    --------------------------------------------------------------------------
    procedure clear_latches is
    begin
      clear_status_dut_1 <= true;
      clear_status_dut_2 <= true;
      WaitForClock(clk, 1);
      clear_status_dut_1 <= false;
      clear_status_dut_2 <= false;
    end procedure clear_latches;

    --------------------------------------------------------------------------
    -- wait_idle_and_clear: block until both LLC user interfaces are ready
    -- (LLC in c_st_idle), then clear status latches.
    --------------------------------------------------------------------------
    procedure wait_idle_and_clear is
    begin
      if user_tx_d2s_dut_1.avalon_st_sink.ready /= '1' then
        wait until user_tx_d2s_dut_1.avalon_st_sink.ready = '1' for 5 ms;
      end if;
      if user_tx_d2s_dut_2.avalon_st_sink.ready /= '1' then
        wait until user_tx_d2s_dut_2.avalon_st_sink.ready = '1' for 5 ms;
      end if;
      clear_latches;
    end procedure wait_idle_and_clear;

    --------------------------------------------------------------------------
    -- gen_frame: builds an internal-format t_llc_frame and returns the
    -- corresponding last_byte index (for RX FIFO depth).
    --   Overload 1: fixed 11-bit base CC frame with given ID, DLC=1.
    --   Overload 2: random frame drawn from coverage bins.
    --------------------------------------------------------------------------
    procedure gen_frame(
      tx_frame : out t_llc_frame;
      last_byte : out natural;
      v_id      : in  std_logic_vector(c_base_id_width - 1 downto 0)
    ) is
      variable v_data_len : natural;
    begin
      for i in tx_frame'range loop
        tx_frame(i) := (others => '0');
      end loop;
      tx_frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end) :=
        std_logic_vector(to_unsigned(1, c_dlc_field_width));
      tx_frame(2)             := v_id(c_base_id_width - 1 downto c_base_id_width - 8);
      tx_frame(3)(7 downto 5) := v_id(2 downto 0);
      v_data_len := 1;
      last_byte  := c_data_offset - 1 + v_data_len;
      tx_frame(c_data_offset) := RV.RandSlv(8);
    end procedure gen_frame;

    procedure gen_frame(tx_frame : out t_llc_frame; last_byte : out natural) is
      variable v_data_len : natural;
    begin
      for i in tx_frame'range loop
        tx_frame(i) := (others => '0');
      end loop;
      tx_frame(0)(c_llc_frame_ide)  := std_logic(to_unsigned(GetRandPoint(ide_cov), 1)(0));
      tx_frame(0)(c_llc_frame_fdf)  := std_logic(to_unsigned(GetRandPoint(fdf_cov), 1)(0));
      tx_frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end) :=
        std_logic_vector(to_unsigned(GetRandPoint(dlc_cov), 4));
      if tx_frame(0)(c_llc_frame_fdf) = '1' then
        tx_frame(0)(c_llc_frame_brs) := RV.RandSlv(1)(1);
        tx_frame(0)(c_llc_frame_esi) := RV.RandSlv(1)(1);
      else
        tx_frame(0)(c_llc_frame_ftyp) := std_logic(to_unsigned(GetRandPoint(ftyp_cov), 1)(0));
      end if;
      for i in 2 to 5 loop
        tx_frame(i) := RV.RandSlv(8);
      end loop;
      if tx_frame(0)(c_llc_frame_ide) = '1' then
        tx_frame(5)(2 downto 0) := "000";
      else
        tx_frame(3)(4 downto 0) := "00000";
        tx_frame(4)             := (others => '0');
        tx_frame(5)             := (others => '0');
      end if;
      if tx_frame(0)(c_llc_frame_ftyp) = '1' then
        last_byte := c_data_offset - 1;
      else
        v_data_len := dlc_to_data_length(
          to_integer(unsigned(tx_frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end))),
          tx_frame(0)(c_llc_frame_fdf));
        last_byte := c_data_offset - 1 + v_data_len;
        for i in 0 to v_data_len - 1 loop
          tx_frame(c_data_offset + i) := RV.RandSlv(8);
        end loop;
      end if;
    end procedure gen_frame;

    --------------------------------------------------------------------------
    -- submit_and_verify: send via DUT 1 (legacy format), verify DUT 1 TX
    -- status and received internal-format bytes at DUT 2.
    --------------------------------------------------------------------------
    procedure submit_and_verify(v_tx_frame : in t_llc_frame; v_last_byte : in natural) is
      variable v_legacy : t_legacy_frame;
    begin
      v_legacy := to_legacy_frame(v_tx_frame);
      -- Push expected internal-format bytes to DUT 2 RX FIFO
      for i in 0 to v_last_byte loop
        Push(rx_rec_dut_2.BurstFifo, SafeResize(v_tx_frame(i), c_rec_width));
      end loop;
      report "DBG EXP cfg0=0x" & to_hstring(v_tx_frame(0))
           & " cfg1=0x" & to_hstring(v_tx_frame(1))
           & " id0=0x"  & to_hstring(v_tx_frame(2))
           & " id1=0x"  & to_hstring(v_tx_frame(3))
           & " id2=0x"  & to_hstring(v_tx_frame(4))
           & " id3=0x"  & to_hstring(v_tx_frame(5))
           & " last_byte=" & to_string(v_last_byte) severity note;
      -- Drive all 71 legacy bytes to DUT 1
      for i in 0 to c_legacy_frame_len - 1 loop
        if i = 0 then
          Send(tx_rec_dut_1, v_legacy(i), c_avalon_sop_byte);
        elsif i < c_legacy_frame_len - 1 then
          Send(tx_rec_dut_1, v_legacy(i), c_avalon_byte);
        else
          Send(tx_rec_dut_1, v_legacy(i), c_avalon_eop_byte);
        end if;
      end loop;
      -- Check received internal-format bytes at DUT 2
      Check(rx_rec_dut_2, std_logic_vector(to_unsigned(v_last_byte + 1, c_rec_width)));
      -- Check transfer status at DUT 1
      Check(tx_rec_dut_1, std_logic_vector(resize(unsigned(c_transmitted), c_rec_width)));
      clear_latches;
    end procedure submit_and_verify;

    --------------------------------------------------------------------------
    -- Test 1: Reset mid-frame, verify clean recovery.
    --------------------------------------------------------------------------
    procedure test_reset is
      variable v_frame     : t_llc_frame;
      variable v_last_byte : natural;
      variable v_legacy    : t_legacy_frame;
    begin
      test_num <= 1;
      Print("--------------------------------------------------------------------------");
      Print("Test 1: Reset");
      Print("--------------------------------------------------------------------------");
      gen_frame(v_frame, v_last_byte);
      v_legacy := to_legacy_frame(v_frame);
      Send(tx_rec_dut_1, v_legacy(0), c_avalon_sop_byte);
      WaitForClock(clk, 5);
      test_rst <= '1';
      WaitForClock(clk, 10);
      test_rst <= '0';
      wait_idle_and_clear;
      gen_frame(v_frame, v_last_byte);
      submit_and_verify(v_frame, v_last_byte);
    end procedure test_reset;

    --------------------------------------------------------------------------
    -- Test 2: Normal usage, coverage-driven random frames.
    --------------------------------------------------------------------------
    procedure test_normal is
      variable v_frame     : t_llc_frame;
      variable v_last_byte : natural;
    begin
      test_num <= 2;
      Print("--------------------------------------------------------------------------");
      Print("Test 2: Normal Usage (DUT 1 TX -> DUT 2 RX)");
      Print("--------------------------------------------------------------------------");
      while not (IsCovered(ide_cov)  and IsCovered(fdf_cov) and
                 IsCovered(dlc_cov)  and IsCovered(ftyp_cov) and
                 IsCovered(brs_cov)  and IsCovered(esi_cov)) loop
        gen_frame(v_frame, v_last_byte);
        submit_and_verify(v_frame, v_last_byte);
        ICover(ide_cov,  to_integer(unsigned'("" & v_frame(0)(c_llc_frame_ide))));
        ICover(fdf_cov,  to_integer(unsigned'("" & v_frame(0)(c_llc_frame_fdf))));
        ICover(dlc_cov,  to_integer(unsigned(v_frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end))));
        if v_frame(0)(c_llc_frame_fdf) = '1' then
          ICover(brs_cov,  to_integer(unsigned'("" & v_frame(0)(c_llc_frame_brs))));
          ICover(esi_cov,  to_integer(unsigned'("" & v_frame(0)(c_llc_frame_esi))));
        else
          ICover(ftyp_cov, to_integer(unsigned'("" & v_frame(0)(c_llc_frame_ftyp))));
        end if;
      end loop;
    end procedure test_normal;

    --------------------------------------------------------------------------
    -- Test 3: Delay sweep.
    --------------------------------------------------------------------------
    procedure test_delay_sweep is
      variable v_frame     : t_llc_frame;
      variable v_last_byte : natural;
    begin
      test_num <= 3;
      Print("--------------------------------------------------------------------------");
      Print("Test 3: Delay Sweep");
      Print("--------------------------------------------------------------------------");
      for i in c_delay_sweep'range loop
        transceiver_d <= c_delay_sweep(i).transceiver_d;
        bus_delay     <= c_delay_sweep(i).bus_d;
        for j in 1 to c_frame_count loop
          gen_frame(v_frame, v_last_byte);
          submit_and_verify(v_frame, v_last_byte);
        end loop;
      end loop;
    end procedure test_delay_sweep;

    --------------------------------------------------------------------------
    -- Test 4: Lost arbitration.
    -- Both DUTs transmit CC base frames with distinct IDs simultaneously.
    -- The LLC retransmits lost_arb automatically; both DUTs eventually report
    -- c_transmitted. This exercises the full arbitration + LLC retransmission path.
    --------------------------------------------------------------------------
    procedure test_lost_arb is
      variable v_id_1    : std_logic_vector(c_base_id_width - 1 downto 0);
      variable v_id_2    : std_logic_vector(c_base_id_width - 1 downto 0);
      variable v_frame_1 : t_llc_frame;
      variable v_frame_2 : t_llc_frame;
      variable v_legacy_1 : t_legacy_frame;
      variable v_legacy_2 : t_legacy_frame;
      variable v_last    : natural;
    begin
      test_num <= 4;
      Print("--------------------------------------------------------------------------");
      Print("Test 4: Lost Arbitration");
      Print("--------------------------------------------------------------------------");
      transceiver_d <= c_transceiver_d;
      bus_delay     <= c_bus_delay_max;
      for iter in 1 to c_frame_count loop
        wait_idle_and_clear;
        loop
          v_id_1 := RV.RandSlv(c_base_id_width);
          v_id_2 := RV.RandSlv(c_base_id_width);
          exit when v_id_1 /= v_id_2;
        end loop;
        gen_frame(v_frame_1, v_last, v_id_1);
        gen_frame(v_frame_2, v_last, v_id_2);
        v_legacy_1 := to_legacy_frame(v_frame_1);
        v_legacy_2 := to_legacy_frame(v_frame_2);

        -- Transmit from both DUTs simultaneously
        for i in 0 to c_legacy_frame_len - 1 loop
          if i = 0 then
            Send(tx_rec_dut_1, v_legacy_1(i), c_avalon_sop_byte);
            Send(tx_rec_dut_2, v_legacy_2(i), c_avalon_sop_byte);
          elsif i < c_legacy_frame_len - 1 then
            Send(tx_rec_dut_1, v_legacy_1(i), c_avalon_byte);
            Send(tx_rec_dut_2, v_legacy_2(i), c_avalon_byte);
          else
            Send(tx_rec_dut_1, v_legacy_1(i), c_avalon_eop_byte);
            Send(tx_rec_dut_2, v_legacy_2(i), c_avalon_eop_byte);
          end if;
        end loop;

        -- LLC absorbs c_lost_arb and retransmits; wait for both to eventually complete
        if status_latch_dut_1 = c_ongoing then
          wait until status_latch_dut_1 /= c_ongoing for 10 ms;
        end if;
        if status_latch_dut_2 = c_ongoing then
          wait until status_latch_dut_2 /= c_ongoing for 10 ms;
        end if;
        AffirmIfEqual(check_id, status_latch_dut_1, c_transmitted, "DUT 1 eventually transmitted");
        AffirmIfEqual(check_id, status_latch_dut_2, c_transmitted, "DUT 2 eventually transmitted");
      end loop;
    end procedure test_lost_arb;

    --------------------------------------------------------------------------
    -- Test 5: Bus-off entry and LLC hold-and-resume.
    --------------------------------------------------------------------------
    procedure test_bus_off is
      variable v_frame      : t_llc_frame;
      variable v_last_byte  : natural;
      variable v_legacy     : t_legacy_frame;
      variable v_send_count : natural := 0;
    begin
      test_num <= 5;
      Print("--------------------------------------------------------------------------");
      Print("Test 5: Bus-off Recovery");
      Print("--------------------------------------------------------------------------");

      -- Phase 1: engage bit-error injection on DUT 1's loopback.
      dut_1_rx_recessive <= true;
      wait_idle_and_clear;

      -- Phase 2: drive DUT 1 to bus-off.
      gen_frame(v_frame, v_last_byte);
      v_legacy := to_legacy_frame(v_frame);
      while not bus_off_seen loop
        v_send_count := v_send_count + 1;
        for i in 0 to c_legacy_frame_len - 1 loop
          exit when bus_off_seen;
          if i = 0 then
            Send(tx_rec_dut_1, v_legacy(i), c_avalon_sop_byte);
          elsif i < c_legacy_frame_len - 1 then
            Send(tx_rec_dut_1, v_legacy(i), c_avalon_byte);
          else
            Send(tx_rec_dut_1, v_legacy(i), c_avalon_eop_byte);
          end if;
        end loop;
      end loop;
      dut_1_rx_recessive <= false;
      AffirmIf(test_id, bus_off_seen, "Bus-off after " & to_string(v_send_count) & " sends");

      -- Phase 3: wait for FCE bus-off recovery (128 x 11 recessive bits).
      if debug_bus_off_dut_1 /= '0' then
        wait until debug_bus_off_dut_1 = '0' for 5 ms;
      end if;
      AffirmIf(test_id, debug_bus_off_dut_1 = '0', "Bus-off recovered");

      -- Phase 4: LLC auto-retransmits the buffered frame after recovery.
      clear_latches;
      wait until status_latch_dut_1 /= c_ongoing for 5 ms;
      AffirmIfEqual(check_id, status_latch_dut_1, c_transmitted, "DUT 1 retransmission after bus-off");

      -- Phase 5: confirm normal TX/RX resumes.
      wait_idle_and_clear;
      for i in 1 to c_frame_count loop
        gen_frame(v_frame, v_last_byte);
        submit_and_verify(v_frame, v_last_byte);
      end loop;
    end procedure test_bus_off;

    --------------------------------------------------------------------------
    procedure report_results is
    begin
      AffirmIf(test_id, IsCovered(ide_cov),  "IDE covered");
      AffirmIf(test_id, IsCovered(fdf_cov),  "FDF covered");
      AffirmIf(test_id, IsCovered(dlc_cov),  "DLC covered");
      AffirmIf(test_id, IsCovered(ftyp_cov), "FTYP covered");
      AffirmIf(test_id, IsCovered(brs_cov),  "BRS covered");
      AffirmIf(test_id, IsCovered(esi_cov),  "ESI covered");
      WriteBin(ide_cov);
      WriteBin(fdf_cov);
      WriteBin(dlc_cov);
      WriteBin(ftyp_cov);
      WriteBin(brs_cov);
      WriteBin(esi_cov);
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
    wait_idle_and_clear;
    test_reset;
    test_normal;
    test_delay_sweep;
    test_lost_arb;
    test_bus_off;
    report_results;
    std.env.finish;
  end process p_test_ctrl;

end architecture tb;
