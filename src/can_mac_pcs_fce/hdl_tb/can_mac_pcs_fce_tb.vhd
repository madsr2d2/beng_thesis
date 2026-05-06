--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_mac_pcs_fce (MAC + PCS + FCE integrated system).
--                  p_tx_llc_vc          - Avalon-ST source VC: drives LLC TX bytes to DUT 1.
--                  p_tx_llc_vc_dut_2    - Avalon-ST source VC: drives LLC TX bytes to DUT 2.
--                  p_rx_llc_sink_vc     - Avalon-ST sink VC: collects and checks DUT 2 RX frames.
--                  p_status_latch_dut_1      - Continuous monitor: latches DUT 1 transfer status.
--                  p_status_latch_dut_2 - Continuous monitor: latches DUT 2 transfer status.
--                  p_bus_off_latch      - Continuous monitor: sticky latch for DUT 1 bus-off.
--                  p_test_ctrl          - Coverage-driven test sequencer (IDE, FDF, DLC bins).
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

entity can_mac_pcs_fce_tb is
  generic(
    gc_TbTimeOut   : time := 1 sec;
    gc_TbClkPeriod : time := 10 ns
  );
end entity can_mac_pcs_fce_tb;

architecture tb of can_mac_pcs_fce_tb is

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  -- Same values as the PCS generics
  constant c_pcs_prescaler      : natural := 2;
  constant c_pcs_nom_prop_seg   : natural := 40;
  constant c_pcs_nom_phase_seg1 : natural := 39;
  constant c_pcs_nom_phase_seg2 : natural := 20;
  constant c_bit_time : natural := (1 + c_pcs_nom_prop_seg + c_pcs_nom_phase_seg1 + c_pcs_nom_phase_seg2) * c_pcs_prescaler;
  -- TB Infrastructure
  constant c_bin_at_least          : natural := 5;
  constant c_rec_width             : natural := 16;
  constant c_delay_frames_per_cfg  : natural := 5;
  constant c_avalon_sop_byte : std_logic_vector := "10";
  constant c_avalon_eop_byte : std_logic_vector := "01";
  constant c_avalon_byte     : std_logic_vector := "00";

  -- Delay configuration -----------------------------------------------------
  -- Two ISO constraints jointly bound the delays in the test bench.
  --
  -- (1) Arbitration condition, ISO sec. 7.3.2 Formula (2):
  --        t_prop_seg >= t_node_A + t_node_B + 2 x t_busline
  --                   >= 4 x transceiver_d + 2 x bus_d
  --     DUT prop_seg = c_pcs_nom_prop_seg x c_pcs_prescaler x gc_TbClkPeriod = 40 x 2 x 10 ns = 800 ns.
  --     Budget fully consumed: 4 x 50 ns + 2 x 300 ns = 800 ns.
  --
  -- (2) TDC compensation range, ISO sec. 7.3.4:
  --        transmitter_delay = 2 x transceiver_d <= 95 x t_q.min
  --     With t_q.min = gc_TbClkPeriod = 10 ns: limit = 95 x 10 ns = 950 ns -> (1) is the binding constraint
  constant c_nom_prop_seg_time : time := 800 ns;
  constant c_transceiver_d     : time := 50 ns;   -- 100 ns round-trip matches then TCAN1042 CAN transceiver (~110 ns TXD-to-RXD)
  constant c_bus_delay_max     : time := (c_nom_prop_seg_time - 4 * c_transceiver_d) / 2;
  type t_delay_cfg is record
    transceiver_d : time;
    bus_d         : time;
  end record;
  type t_delay_cfg_arr is array (natural range <>) of t_delay_cfg;
  -- Sweep from 100 % down to 20 % of the ISO propagation budget.
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
  signal clk   : std_logic;
  signal reset : std_logic := '1';
  -- Bus model and delay signals
  signal bus_delay      : time := c_bus_delay_max;
  signal transceiver_d  : time := c_transceiver_d;
  -- DUT port connections
  signal dut1_tx      : std_logic;
  signal dut2_tx      : std_logic;
  signal dut1_rx      : std_logic := c_recessive;
  signal dut2_rx      : std_logic := c_recessive;
  -- Wire signals: DUT's TX after transceiver TX delay
  signal dut1_wire    : std_logic := c_recessive;
  signal dut2_wire    : std_logic := c_recessive;
  -- Propagated to the far end after bus delay
  signal dut1_wire_far : std_logic := c_recessive;
  signal dut2_wire_far : std_logic := c_recessive;
  -- Wired-AND bus as seen at each node's end (forced recessive on DUT 1 when injection active)
  signal bus_dut1     : std_logic := c_recessive;
  signal bus_dut2     : std_logic := c_recessive;
  -- s_dut_1_rx_recessive forces DUT 1's loopback recessive
  signal dut_1_rx_recessive : boolean   := false;
  -- bus_off latch (DUT 1)
  signal bus_off_seen  : boolean := false;
  signal bus_off_clear : boolean := false;
  -- DUT 1 interfaces
  signal llc_to_mac_tx_s2d_dut_1 : t_can_llc_mac_tx_if_s2d := c_llc_to_mac_tx_if_reset;
  signal llc_to_mac_tx_d2s_dut_1 : t_can_llc_mac_tx_if_d2s;
  signal mac_to_llc_tx_s2d_dut_1 : t_can_llc_mac_rx_if_s2d;
  signal mac_to_llc_tx_d2s_dut_1 : t_can_llc_mac_rx_if_d2s := c_llc_to_mac_rx_if_reset;
  -- DUT 2 interfaces
  signal llc_to_mac_tx_s2d_dut_2 : t_can_llc_mac_tx_if_s2d := c_llc_to_mac_tx_if_reset;
  signal llc_to_mac_tx_d2s_dut_2 : t_can_llc_mac_tx_if_d2s;
  signal mac_to_llc_tx_s2d_dut_2 : t_can_llc_mac_rx_if_s2d;
  signal mac_to_llc_tx_d2s_dut_2 : t_can_llc_mac_rx_if_d2s := c_llc_to_mac_rx_if_reset;
  -- LLC-FCE interfaces
  signal llc_fce_i_dut_1 : t_can_llc_fce_if_m2s := (normal_mode => '1');
  signal llc_fce_o_dut_1 : t_can_fce_llc_if_s2m;
  signal llc_fce_i_dut_2 : t_can_llc_fce_if_m2s := (normal_mode => '1');
  signal llc_fce_o_dut_2 : t_can_fce_llc_if_s2m;
  -- Transfer status latches
  signal status_latch_dut_1            : std_logic_vector(2 downto 0) := c_ongoing;
  signal clear_status_dut_1 : boolean                      := false;
  signal status_latch_dut_2 : std_logic_vector(2 downto 0) := c_ongoing;
  signal clear_status_dut_2 : boolean                      := false;
  -- OSVVM stuff
  shared variable RV           : RandomPType;
  signal          test_id      : AlertLogIDType;
  signal          check_id     : AlertLogIDType;
  signal          ide_cov      : CoverageIDType;
  signal          fdf_cov      : CoverageIDType;
  signal          dlc_cov      : CoverageIDType;
  signal          ftyp_cov     : CoverageIDType;
  signal          init_barrier : integer_barrier := 1;
  signal          test_num     : natural;
  -- Transaction interfaces
  signal tx_llc_rec_dut_1 : StreamRecType(
    DataToModel(c_rec_width - 1 downto 0),
    ParamToModel(c_rec_width - 1 downto 0),
    DataFromModel(c_rec_width - 1 downto 0),
    ParamFromModel(c_rec_width - 1 downto 0)
  );
  signal tx_llc_rec_dut_2 : StreamRecType(
    DataToModel(c_rec_width - 1 downto 0),
    ParamToModel(c_rec_width - 1 downto 0),
    DataFromModel(c_rec_width - 1 downto 0),
    ParamFromModel(c_rec_width - 1 downto 0)
  );
  signal rx_llc_rec_dut_2 : StreamRecType(
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
    variable v_test_id   : AlertLogIDType;
    variable v_check_id  : AlertLogIDType;
    variable v_ide_cov   : CoverageIDType;
    variable v_fdf_cov   : CoverageIDType;
    variable v_dlc_cov   : CoverageIDType;
    variable v_ftyp_cov  : CoverageIDType;
  begin
    SetAlertStopCount(ERROR, 1);
    SetLogEnable(DEBUG, false);
    v_test_id            := NewID("can_mac_pcs_fce");
    v_check_id           := NewID("Frame check", v_test_id);
    v_ide_cov            := NewID("IDE Coverage",  v_test_id, ReportMode => ENABLED);
    v_fdf_cov            := NewID("FDF Coverage",  v_test_id, ReportMode => ENABLED);
    v_dlc_cov            := NewID("DLC Coverage",  v_test_id, ReportMode => ENABLED);
    v_ftyp_cov           := NewID("FTYP Coverage", v_test_id, ReportMode => ENABLED);
    RV.InitSeed(RV'instance_name & to_string(now));
    AddBins(v_ide_cov,  c_bin_at_least, GenBin(0, 1));
    AddBins(v_fdf_cov,  c_bin_at_least, GenBin(0, 1));
    AddBins(v_dlc_cov,  c_bin_at_least, GenBin(0, c_dlc_max));
    AddBins(v_ftyp_cov, c_bin_at_least, GenBin(0, 1));
    tx_llc_rec_dut_1.BurstFifo <= NewID("TX LLC Burst fifo DUT 1");
    rx_llc_rec_dut_2.BurstFifo <= NewID("RX LLC Burst fifo DUT 2");
    test_id              <= v_test_id;
    check_id             <= v_check_id;
    ide_cov              <= v_ide_cov;
    fdf_cov              <= v_fdf_cov;
    dlc_cov              <= v_dlc_cov;
    ftyp_cov             <= v_ftyp_cov;
    -- DUT RX LLC sink always ready
    mac_to_llc_tx_d2s_dut_1.avalon_st_sink.ready <= '1';
    mac_to_llc_tx_d2s_dut_2.avalon_st_sink.ready <= '1';
    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  ----------------------------------------------------------------------------
  -- DUT 1
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
      tx_o      => dut1_tx,
      rx_i      => dut1_rx
    );

  ----------------------------------------------------------------------------
  -- DUT 2
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
      tx_o      => dut2_tx,
      rx_i      => dut2_rx
    );

  ----------------------------------------------------------------------------
  -- Bus model: dominant-wins with transceiver and propagation delays.
  --
  --  s_dut1_tx -[transceiver_d]-> s_dut1_wire -[bus_d]-> s_dut1_wire_far
  --  s_dut2_tx -[transceiver_d]-> s_dut2_wire -[bus_d]-> s_dut2_wire_far
  --
  --  s_bus_dut1 = s_dut1_wire AND s_dut2_wire_far  (forced recessive when injection active)
  --  s_bus_dut2 = s_dut1_wire_far AND s_dut2_wire  (forced to s_dut2_wire when injection active)
  --
  --  s_dut1_rx <-[transceiver_d]- s_bus_dut1
  --  s_dut2_rx <-[transceiver_d]- s_bus_dut2
  --
  --  s_dut_1_rx_recessive simulates DUT 1's transceiver being open-circuit:
  --  DUT 1's wire is removed from the bus at both ends so DUT 2 also sees only
  --  its own (recessive) signal and does not start receiving a phantom frame.
  ----------------------------------------------------------------------------
  -- bus_off_seen drops the recessive override when bus enters bus-off state.
  -- This is helpful in the bus-off test (the retransmission of the frame that got "bus-off'ed" is not corrupted again)
  bus_dut1 <= c_recessive when (dut_1_rx_recessive and not bus_off_seen) else dut1_wire and dut2_wire_far;
  bus_dut2 <= dut2_wire when (dut_1_rx_recessive and not bus_off_seen) else dut1_wire_far and dut2_wire;

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
      elsif llc_fce_o_dut_1.bus_off = '1' then
        bus_off_seen <= true;
      end if;
    end if;
  end process p_bus_off_latch;

  ----------------------------------------------------------------------------
  -- Transfer status latch (DUT 1 TX)
  ----------------------------------------------------------------------------
  p_status_latch_dut_1: process(clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' or clear_status_dut_1 then
        status_latch_dut_1 <= c_ongoing;
      else
        if llc_to_mac_tx_d2s_dut_1.transfer_status /= c_ongoing and llc_to_mac_tx_d2s_dut_1.transfer_status /= status_latch_dut_1 then
          status_latch_dut_1 <= llc_to_mac_tx_d2s_dut_1.transfer_status;
        end if;
      end if;
    end if;
  end process p_status_latch_dut_1;

  ----------------------------------------------------------------------------
  -- Transfer status latch (DUT 2 TX)
  ----------------------------------------------------------------------------
  p_status_latch_dut_2 : process(clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' or clear_status_dut_2 then
        status_latch_dut_2 <= c_ongoing;
      else
        if llc_to_mac_tx_d2s_dut_2.transfer_status /= c_ongoing and llc_to_mac_tx_d2s_dut_2.transfer_status /= status_latch_dut_2 then
          status_latch_dut_2 <= llc_to_mac_tx_d2s_dut_2.transfer_status;
        end if;
      end if;
    end if;
  end process p_status_latch_dut_2;

  ----------------------------------------------------------------------------
  -- TX LLC source VC (DUT 1)
  ----------------------------------------------------------------------------
  p_tx_llc_vc : process is
  begin
    WaitForBarrier(init_barrier);
    tx_llc_vc_loop : loop
      WaitForTransaction(tx_llc_rec_dut_1.Rdy, tx_llc_rec_dut_1.Ack);
      case tx_llc_rec_dut_1.Operation is
        when SEND =>
          llc_to_mac_tx_s2d_dut_1.avalon_st_source.valid         <= '1';
          llc_to_mac_tx_s2d_dut_1.avalon_st_source.data          <= SafeResize(std_logic_vector(tx_llc_rec_dut_1.DataToModel), c_byte_width);
          llc_to_mac_tx_s2d_dut_1.avalon_st_source.startofpacket <= tx_llc_rec_dut_1.ParamToModel(1);
          llc_to_mac_tx_s2d_dut_1.avalon_st_source.endofpacket   <= tx_llc_rec_dut_1.ParamToModel(0);
          wait until rising_edge(clk) and llc_to_mac_tx_d2s_dut_1.avalon_st_sink.ready = '1';
          llc_to_mac_tx_s2d_dut_1.avalon_st_source.valid         <= '0';
        when CHECK =>
          if status_latch_dut_1 = c_ongoing then
            wait until status_latch_dut_1 /= c_ongoing;
          end if;
          AffirmIfEqual(check_id, status_latch_dut_1, std_logic_vector(tx_llc_rec_dut_1.DataToModel(2 downto 0)), "Transfer status");
        when others => null;
      end case;
    end loop tx_llc_vc_loop;
  end process p_tx_llc_vc;

  ----------------------------------------------------------------------------
  -- TX LLC source VC (DUT 2)
  ----------------------------------------------------------------------------
  p_tx_llc_vc_dut_2 : process is
  begin
    WaitForBarrier(init_barrier);
    tx_llc_vc_dut_2_loop : loop
      WaitForTransaction(tx_llc_rec_dut_2.Rdy, tx_llc_rec_dut_2.Ack);
      case tx_llc_rec_dut_2.Operation is
        when SEND =>
          llc_to_mac_tx_s2d_dut_2.avalon_st_source.valid         <= '1';
          llc_to_mac_tx_s2d_dut_2.avalon_st_source.data          <= SafeResize(std_logic_vector(tx_llc_rec_dut_2.DataToModel), c_byte_width);
          llc_to_mac_tx_s2d_dut_2.avalon_st_source.startofpacket <= tx_llc_rec_dut_2.ParamToModel(1);
          llc_to_mac_tx_s2d_dut_2.avalon_st_source.endofpacket   <= tx_llc_rec_dut_2.ParamToModel(0);
          wait until rising_edge(clk) and llc_to_mac_tx_d2s_dut_2.avalon_st_sink.ready = '1';
          llc_to_mac_tx_s2d_dut_2.avalon_st_source.valid         <= '0';
        when CHECK =>
          if status_latch_dut_2 = c_ongoing then
            wait until status_latch_dut_2 /= c_ongoing;
          end if;
          AffirmIfEqual(check_id, status_latch_dut_2, std_logic_vector(tx_llc_rec_dut_2.DataToModel(2 downto 0)), "DUT 2 transfer status");
        when others => null;
      end case;
    end loop tx_llc_vc_dut_2_loop;
  end process p_tx_llc_vc_dut_2;

  ----------------------------------------------------------------------------
  -- RX LLC sink VC (DUT 2)
  ----------------------------------------------------------------------------
  p_rx_llc_sink_vc : process is
  begin
    WaitForBarrier(init_barrier);
    loop
      WaitForTransaction(clk, rx_llc_rec_dut_2.Rdy, rx_llc_rec_dut_2.Ack);
      case rx_llc_rec_dut_2.Operation is
        when CHECK =>
          -- Collect received bytes into the FIFO until EOP.
          collect_loop : loop
            wait until rising_edge(clk);
            if mac_to_llc_tx_s2d_dut_2.avalon_st_source.valid = '1' then
              Push(tx_llc_rec_dut_1.BurstFifo, SafeResize(mac_to_llc_tx_s2d_dut_2.avalon_st_source.data, c_rec_width));
              exit collect_loop when mac_to_llc_tx_s2d_dut_2.avalon_st_source.endofpacket = '1';
            end if;
          end loop collect_loop;
          -- Drain FIFOs and check bytes match.
          while not IsEmpty(tx_llc_rec_dut_1.BurstFifo) loop
            AffirmIfEqual(check_id, Pop(tx_llc_rec_dut_1.BurstFifo)(7 downto 0), Pop(rx_llc_rec_dut_2.BurstFifo)(7 downto 0), "RX byte");
          end loop;
          AffirmIf(check_id, IsEmpty(rx_llc_rec_dut_2.BurstFifo), "RX frame length matches expected");
        when others => null;
      end case;
    end loop;
  end process p_rx_llc_sink_vc;

  ----------------------------------------------------------------------------
  -- p_test_ctrl
  ----------------------------------------------------------------------------
  p_test_ctrl : process is

    --------------------------------------------------------------------------
    -- clear_latches: pulse both transfer-status latches back to c_ongoing.
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
    -- wait_idle_and_clear: block until both DUT TX paths return to c_ongoing,
    -- then pulse the latches clear.
    --------------------------------------------------------------------------
    procedure wait_idle_and_clear is
    begin
      if llc_to_mac_tx_d2s_dut_1.transfer_status /= c_ongoing then
        wait until llc_to_mac_tx_d2s_dut_1.transfer_status = c_ongoing for 5 ms;
      end if;
      if llc_to_mac_tx_d2s_dut_2.transfer_status /= c_ongoing then
        wait until llc_to_mac_tx_d2s_dut_2.transfer_status = c_ongoing for 5 ms;
      end if;
      clear_latches;
    end procedure wait_idle_and_clear;

    --------------------------------------------------------------------------
    -- gen_frame: builds an LLC frame.
    --------------------------------------------------------------------------
    procedure gen_frame(tx_frame : out t_llc_frame; last_byte : out natural; v_id : integer := -1) is
      variable v_data_len : natural;
      variable v_id_slv   : std_logic_vector(c_base_id_width - 1 downto 0);
    begin
      for i in tx_frame'range loop
        tx_frame(i) := (others => '0');
      end loop;
      -- Format: random from coverage bins, or fixed CC base data with DLC=1.
      if v_id < 0 then
        tx_frame(0)(c_llc_frame_ide) := std_logic(to_unsigned(GetRandPoint(ide_cov), 1)(0));
        tx_frame(0)(c_llc_frame_fdf) := std_logic(to_unsigned(GetRandPoint(fdf_cov), 1)(0));
        tx_frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end) :=
          std_logic_vector(to_unsigned(GetRandPoint(dlc_cov), 4));
        if tx_frame(0)(c_llc_frame_fdf) = '1' then
          tx_frame(0)(c_llc_frame_brs) := RV.RandSlv(1)(1);
          tx_frame(0)(c_llc_frame_esi) := RV.RandSlv(1)(1);
        else
          -- RTR only applies to CC frames (ISO 7.3.1.1); sample FTYP from coverage.
          tx_frame(0)(c_llc_frame_ftyp) := std_logic(to_unsigned(GetRandPoint(ftyp_cov), 1)(0));
        end if;
      else
        tx_frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end) :=
          std_logic_vector(to_unsigned(1, c_dlc_field_width));
      end if;
      -- ID: fixed if v_id >= 0, else random random.
      if v_id >= 0 then
        v_id_slv                := std_logic_vector(to_unsigned(v_id, c_base_id_width));
        tx_frame(2)             := v_id_slv(c_base_id_width - 1 downto c_base_id_width - 8);
        tx_frame(3)(7 downto 5) := v_id_slv(2 downto 0);
      else
        for i in 2 to 5 loop
          tx_frame(i) := RV.RandSlv(8);
        end loop;
        -- Zero unused ID bits: extended uses bytes 2..5 (29-bit), base uses bytes 2..3 (11-bit).
        if tx_frame(0)(c_llc_frame_ide) = '1' then
          tx_frame(5)(2 downto 0) := "000";
        else
          tx_frame(3)(4 downto 0) := "00000";
          tx_frame(4)             := (others => '0');
          tx_frame(5)             := (others => '0');
        end if;
      end if;
      -- Data bytes: RTR carries none; all others fill v_data_len bytes.
      if tx_frame(0)(c_llc_frame_ftyp) = '1' then
        last_byte := c_data_offset - 1;
      else
        v_data_len := dlc_to_data_length( to_integer(unsigned(tx_frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end))), tx_frame(0)(c_llc_frame_fdf));
        last_byte := c_data_offset - 1 + v_data_len;
        for i in 0 to v_data_len - 1 loop
          tx_frame(c_data_offset + i) := RV.RandSlv(8);
        end loop;
      end if;
    end procedure gen_frame;

    --------------------------------------------------------------------------
    -- submit_and_verify: send frame via DUT 1, verify TX status and RX bytes
    --------------------------------------------------------------------------
    procedure submit_and_verify(v_tx_frame : in t_llc_frame; v_last_byte : in natural) is
    begin
      -- Pre-load expected bytes before sending: p_rx_llc_sink_vc processes them when the frame arrives.
      for i in 0 to v_last_byte loop
        Push(rx_llc_rec_dut_2.BurstFifo, SafeResize(v_tx_frame(i), c_rec_width));
      end loop;

      for i in 0 to v_last_byte loop
        if (i = 0) then
          Send(tx_llc_rec_dut_1, v_tx_frame(i), c_avalon_sop_byte);
        elsif (i < v_last_byte) then
          Send(tx_llc_rec_dut_1, v_tx_frame(i), c_avalon_byte);
        else
          Send(tx_llc_rec_dut_1, v_tx_frame(i), c_avalon_eop_byte);
        end if;
      end loop;

      -- Issue the RX check while the frame is still in transit: the VC collects
      -- bytes from DUT 2 as they arrive, concurrently with p_tx_llc_vc driving DUT 1.
      Check(rx_llc_rec_dut_2, std_logic_vector(to_unsigned(v_last_byte + 1, c_rec_width)));
      -- RX verification is now complete; confirm TX outcome and reset the latches.
      Check(tx_llc_rec_dut_1, std_logic_vector(resize(unsigned(c_transmitted), c_rec_width)));
      clear_latches;
    end procedure submit_and_verify;

    --------------------------------------------------------------------------
    -- Test 1: Normal usage
    --------------------------------------------------------------------------
    procedure test_normal is
      variable v_frame     : t_llc_frame;
      variable v_last_byte : natural;
    begin
      test_num <= 1;
      Print("--------------------------------------------------------------------------");
      Print("Test 1: Normal Usage (DUT 1 TX -> DUT 2 RX)");
      Print("--------------------------------------------------------------------------");
      while not (IsCovered(ide_cov) and IsCovered(fdf_cov) and IsCovered(dlc_cov) and IsCovered(ftyp_cov)) loop
        gen_frame(v_frame, v_last_byte);
        submit_and_verify(v_frame, v_last_byte);

        ICover(ide_cov,  to_integer(unsigned'("" & v_frame(0)(c_llc_frame_ide))));
        ICover(fdf_cov,  to_integer(unsigned'("" & v_frame(0)(c_llc_frame_fdf))));
        ICover(dlc_cov,  to_integer(unsigned(v_frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end))));
        -- FTYP is only meaningful for CC frames; RTR is illegal in FD (ISO 7.3.1.1).
        if v_frame(0)(c_llc_frame_fdf) = '0' then
          ICover(ftyp_cov, to_integer(unsigned'("" & v_frame(0)(c_llc_frame_ftyp))));
        end if;
      end loop;
    end procedure test_normal;

    --------------------------------------------------------------------------
    -- Test 2: Delay sweep -- batch of frames at each c_delay_sweep operating point
    --------------------------------------------------------------------------
    procedure test_delay_sweep is
      variable v_frame     : t_llc_frame;
      variable v_last_byte : natural;
    begin
      test_num <= 2;
      Print("--------------------------------------------------------------------------");
      Print("Test 2: Delay Sweep");
      Print("--------------------------------------------------------------------------");
      for i in c_delay_sweep'range loop
        transceiver_d <= c_delay_sweep(i).transceiver_d;
        bus_delay     <= c_delay_sweep(i).bus_d;

        for i in 1 to c_delay_frames_per_cfg loop
          gen_frame(v_frame, v_last_byte);
          submit_and_verify(v_frame, v_last_byte);
        end loop;
      end loop;
    end procedure test_delay_sweep;

    --------------------------------------------------------------------------
    -- Test 3: Lost arbitration -- both DUTs transmit CC base frames with
    -- random distinct IDs. Winner (lower ID) reports c_transmitted; loser
    -- reports c_lost_arb (ISO 11898-1 6.5.2).
    --------------------------------------------------------------------------
    procedure test_lost_arb is
      constant c_iterations : natural := 10;
      variable v_id_1       : natural;
      variable v_id_2       : natural;
      variable v_frame_1    : t_llc_frame;
      variable v_frame_2    : t_llc_frame;
      variable v_last       : natural;
      variable v_dut1_wins  : boolean;
    begin
      test_num <= 3;
      Print("--------------------------------------------------------------------------");
      Print("Test 3: Lost Arbitration (random IDs, " & integer'image(c_iterations) & " iterations)");
      Print("--------------------------------------------------------------------------");
      transceiver_d <= c_transceiver_d;
      bus_delay     <= c_bus_delay_max;
      for iter in 1 to c_iterations loop
        -- Latch captures only the first non-ongoing status; wait for idle so
        -- a tail retransmission from the previous iteration does not pollute it.
        wait_idle_and_clear;

        loop  -- Generate distinct IDs
          v_id_1 := RV.RandInt(0, 2 ** c_base_id_width - 1);
          v_id_2 := RV.RandInt(0, 2 ** c_base_id_width - 1);
          exit when v_id_1 /= v_id_2;
        end loop;
        gen_frame(v_frame_1, v_last, v_id_1);
        gen_frame(v_frame_2, v_last, v_id_2);
        v_dut1_wins := v_id_1 < v_id_2;

        -- Transmit from both DUT's at the same time to ensure arbitration is triggered 
        for i in 0 to v_last loop
          if i = 0 then
            Send(tx_llc_rec_dut_1, v_frame_1(i), c_avalon_sop_byte);
            Send(tx_llc_rec_dut_2, v_frame_2(i), c_avalon_sop_byte);
          elsif i < v_last then
            Send(tx_llc_rec_dut_1, v_frame_1(i), c_avalon_byte);
            Send(tx_llc_rec_dut_2, v_frame_2(i), c_avalon_byte);
          else
            Send(tx_llc_rec_dut_1, v_frame_1(i), c_avalon_eop_byte);
            Send(tx_llc_rec_dut_2, v_frame_2(i), c_avalon_eop_byte);
          end if;
        end loop;

        -- Wait for DUT's to either lose arbitration or transmit successfully
        if status_latch_dut_1 = c_ongoing then
          wait until status_latch_dut_1 /= c_ongoing for 5 ms;
        end if;
        if status_latch_dut_2 = c_ongoing then
          wait until status_latch_dut_2 /= c_ongoing for 5 ms;
        end if;

        if v_dut1_wins then
          AffirmIfEqual(check_id, status_latch_dut_1, c_transmitted, "DUT 1 transmitted");
          AffirmIfEqual(check_id, status_latch_dut_2, c_lost_arb,   "DUT 2 lost arb");
          AffirmIf(check_id, v_id_1 < v_id_2, "DUT 1 won: lower ID");
        else
          AffirmIfEqual(check_id, status_latch_dut_1, c_lost_arb,   "DUT 1 lost arb");
          AffirmIfEqual(check_id, status_latch_dut_2, c_transmitted, "DUT 2 transmitted");
          AffirmIf(check_id, v_id_2 < v_id_1, "DUT 2 won: lower ID");
        end if;
      end loop;

      -- Let the last iteration's loser retransmit and settle before clearing.
      WaitForClock(clk, 100 * c_bit_time);
      clear_latches;
    end procedure test_lost_arb;

    --------------------------------------------------------------------------
    -- Test 4: Bus-off entry and recovery.
    -- Phase 1-2: s_dut_1_rx_recessive forces bit errors on every dominant drive at DUT 1.
    -- Phase 3: lift injection, FCE counts 128 x 11 recessive bits and recovers.
    -- Phase 4: confirm normal TX/RX resumes by sending.
    --------------------------------------------------------------------------
    procedure test_bus_off is
      variable v_frame      : t_llc_frame;
      variable v_last_byte  : natural;
      variable v_send_count : natural := 0;
    begin
      test_num <= 4;
      Print("--------------------------------------------------------------------------");
      Print("Test 4: Bus-off Recovery");
      Print("--------------------------------------------------------------------------");
      bus_off_clear <= true;
      WaitForClock(clk, 2);
      bus_off_clear <= false;

      -- Phase 1: engage bit-error injection.
      dut_1_rx_recessive <= true;
      WaitForClock(clk, 10);

      -- Phase 2: drive DUT 1 to bus-off.
      gen_frame(v_frame, v_last_byte);
      while not bus_off_seen loop
        v_send_count := v_send_count + 1;
        for i in 0 to v_last_byte loop
          exit when bus_off_seen;
          if i = 0 then
            Send(tx_llc_rec_dut_1, v_frame(i), c_avalon_sop_byte);
          elsif i < v_last_byte then
            Send(tx_llc_rec_dut_1, v_frame(i), c_avalon_byte);
          else
            Send(tx_llc_rec_dut_1, v_frame(i), c_avalon_eop_byte);
          end if;
        end loop;
      end loop;
      dut_1_rx_recessive <= false;
      AffirmIf(test_id, bus_off_seen, "Bus-off after " & to_string(v_send_count) & " sends");

      -- Phase 3: wait for FCE bus-off recovery (128 x 11 bit times).
      if llc_fce_o_dut_1.bus_off /= '0' then
        wait until llc_fce_o_dut_1.bus_off = '0' for 5 ms;
      end if;
      AffirmIf(test_id, llc_fce_o_dut_1.bus_off = '0', "Bus-off recovered");

      -- Phase 4: confirm normal TX/RX resumes after recovery.
      clear_latches;
      wait until status_latch_dut_1 /= c_ongoing for 5 ms;
      -- Settle: ensure the Phase-2 frame's bytes have fully streamed through
      -- DUT 2's MAC-to-LLC interface before the verification frame arrives.
      -- WaitForClock(clk, (c_bus_idle_condition_width + 3) * c_bit_time);
      clear_latches;
      for i in 1 to 10 loop
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
      WriteBin(ide_cov);
      WriteBin(fdf_cov);
      WriteBin(dlc_cov);
      WriteBin(ftyp_cov);
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

    -- Allow both DUTs to complete bus reintegration.
    WaitForClock(clk, (c_bus_idle_condition_width + 2) * (c_bit_time + 1));

    test_normal;
    test_delay_sweep;
    test_lost_arb;
    test_bus_off;

    report_results;
    std.env.finish;
    wait;
  end process p_test_ctrl;

end architecture tb;
