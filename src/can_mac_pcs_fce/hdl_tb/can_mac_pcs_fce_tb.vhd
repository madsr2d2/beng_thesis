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
  -- Nominal bit timing (ISO 7.3.2, midpoint of subtype ranges in pk_can_types)
  constant c_bit_time : natural := 100;

  constant c_bin_at_least          : natural := 5;
  constant c_rec_width             : natural := 16;
  constant c_delay_frames_per_cfg  : natural := 5;

  -- Avalon-ST byte encoding [1] = startofpacket, [0] = endofpacket
  constant c_avalon_sop_byte : std_logic_vector := "10";
  constant c_avalon_eop_byte : std_logic_vector := "01";
  constant c_avalon_byte     : std_logic_vector := "00";

  -- Bus / transceiver delays (driven so test_delay_sweep can update them).
  signal s_bus_delay        : time := 150 ns;
  signal s_transceiver_tx_d : time := 300 ns;
  signal s_transceiver_rx_d : time := 300 ns;

  type t_delay_cfg is record
    tx_d  : time;
    rx_d  : time;
    bus_d : time;
  end record;
  type t_delay_cfg_arr is array (natural range <>) of t_delay_cfg;

  -- Operating points within prop_seg = 800 ns (ISO 11898-1 7.3.5.1).
  constant c_delay_sweep : t_delay_cfg_arr := (
    (tx_d => 300 ns, rx_d => 300 ns, bus_d => 150 ns),
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

  -- Bus model signals -------------------------------------------------------
  -- DUT port connections
  signal s_dut1_tx      : std_logic;
  signal s_dut2_tx      : std_logic;
  signal s_dut1_rx      : std_logic := c_recessive;
  signal s_dut2_rx      : std_logic := c_recessive;
  -- Wire signals: DUT's TX after transceiver TX delay, at each node's physical end
  signal s_dut1_wire    : std_logic := c_recessive;
  signal s_dut2_wire    : std_logic := c_recessive;
  -- Propagated to the far end after bus delay
  signal s_dut1_wire_far : std_logic := c_recessive;
  signal s_dut2_wire_far : std_logic := c_recessive;
  -- Wired-AND bus as seen at each node's end
  signal s_bus_dut1     : std_logic := c_recessive;
  signal s_bus_dut2     : std_logic := c_recessive;
  -- DUT 1 RX input with error-injection override (forces recessive for bus-off test)
  signal s_bus_dut1_obs : std_logic;

  -- s_dut_1_rx_recessive forces DUT 1's loopback recessive so every dominant
  -- it drives becomes a bit error (TEC += 8, bypasses error-passive exemption).
  signal s_dut_1_rx_recessive : boolean   := false;

  -- Sticky bus_off latch (DUT 1): captures the pulse since FCE may recover
  -- before the sequencer samples the live signal.
  signal s_bus_off_seen  : boolean := false;
  signal s_bus_off_clear : boolean := false;

  -- Flush p_rx_llc_sink_vc between tests: discards any frame buffered by DUT 2
  -- that was received during test_lost_arb iterations where DUT 1 won.
  signal s_rx_sink_flush : boolean := false;

  -- DUT 1 interfaces
  signal llc_to_mac_tx_s2d_dut_1 : t_can_llc_mac_tx_if_s2d;
  signal llc_to_mac_tx_d2s_dut_1 : t_can_llc_mac_tx_if_d2s;
  signal mac_to_llc_tx_s2d_dut_1 : t_can_llc_mac_rx_if_s2d;
  signal mac_to_llc_tx_d2s_dut_1 : t_can_llc_mac_rx_if_d2s;

  -- DUT 2 interfaces. LLC TX source is idle until p_tx_llc_vc_dut_2 drives it.
  signal llc_to_mac_tx_s2d_dut_2 : t_can_llc_mac_tx_if_s2d := (
    avalon_st_source => (
      data          => (others => '0'),
      valid         => '0',
      startofpacket => '0',
      endofpacket   => '0'
    )
  );
  signal llc_to_mac_tx_d2s_dut_2 : t_can_llc_mac_tx_if_d2s;
  signal mac_to_llc_tx_s2d_dut_2 : t_can_llc_mac_rx_if_s2d;
  signal mac_to_llc_tx_d2s_dut_2 : t_can_llc_mac_rx_if_d2s;

  -- LLC-FCE interfaces (both DUTs always in normal mode for simulation)
  signal llc_fce_i_dut_1 : t_can_llc_fce_if_m2s := (normal_mode => '1');
  signal llc_fce_o_dut_1 : t_can_fce_llc_if_s2m;
  signal llc_fce_i_dut_2 : t_can_llc_fce_if_m2s := (normal_mode => '1');
  signal llc_fce_o_dut_2 : t_can_fce_llc_if_s2m;

  -- Transfer status latches
  signal status_latch_dut_1            : std_logic_vector(2 downto 0) := c_ongoing;
  signal clear_status_dut_1            : boolean                      := false;
  signal s_status_latch_rst_dut_1       : boolean                      := false;
  signal status_latch_dut_2       : std_logic_vector(2 downto 0) := c_ongoing;
  signal clear_status_dut_2       : boolean                      := false;
  signal s_status_latch_rst_dut_2 : boolean                      := false;

  -- OSVVM signals
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
    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  -- DUT RX LLC sink always ready
  mac_to_llc_tx_d2s_dut_1.avalon_st_sink.ready <= '1';
  mac_to_llc_tx_d2s_dut_2.avalon_st_sink.ready <= '1';

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
      tx_o      => s_dut1_tx,
      rx_i      => s_dut1_rx
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
      tx_o      => s_dut2_tx,
      rx_i      => s_dut2_rx
    );

  ----------------------------------------------------------------------------
  -- Bus model: dominant-wins wired-AND with transceiver and propagation delays.
  --
  --  s_dut1_tx -[tx_d]-> s_dut1_wire -[bus_d]-> s_dut1_wire_far
  --  s_dut2_tx -[tx_d]-> s_dut2_wire -[bus_d]-> s_dut2_wire_far
  --
  --  s_bus_dut1 = s_dut1_wire AND s_dut2_wire_far  (bus as seen at DUT 1's end)
  --  s_bus_dut2 = s_dut1_wire_far AND s_dut2_wire  (bus as seen at DUT 2's end)
  --
  --  s_dut1_rx <-[rx_d]- s_bus_dut1_obs  (s_bus_dut1 forced recessive in bus-off test)
  --  s_dut2_rx <-[rx_d]- s_bus_dut2
  ----------------------------------------------------------------------------
  s_bus_dut1     <= s_dut1_wire     and s_dut2_wire_far;
  s_bus_dut1_obs <= c_recessive when s_dut_1_rx_recessive else s_bus_dut1;
  s_bus_dut2     <= s_dut1_wire_far and s_dut2_wire;

  p_dut1_tx_to_wire : process is
  begin
    wait on s_dut1_tx;
    s_dut1_wire <= transport s_dut1_tx after s_transceiver_tx_d;
  end process;

  p_dut1_rx_from_bus : process is
  begin
    wait on s_bus_dut1_obs;
    s_dut1_rx <= transport s_bus_dut1_obs after s_transceiver_rx_d;
  end process;

  p_dut2_tx_to_wire : process is
  begin
    wait on s_dut2_tx;
    s_dut2_wire <= transport s_dut2_tx after s_transceiver_tx_d;
  end process;

  p_dut2_rx_from_bus : process is
  begin
    wait on s_bus_dut2;
    s_dut2_rx <= transport s_bus_dut2 after s_transceiver_rx_d;
  end process;

  p_propagate_dut1_to_dut2 : process is
  begin
    wait on s_dut1_wire;
    s_dut1_wire_far <= transport s_dut1_wire after s_bus_delay;
  end process;

  p_propagate_dut2_to_dut1 : process is
  begin
    wait on s_dut2_wire;
    s_dut2_wire_far <= transport s_dut2_wire after s_bus_delay;
  end process;

  ----------------------------------------------------------------------------
  -- Bus-off latch (DUT 1)
  ----------------------------------------------------------------------------
  p_bus_off_latch : process(clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' or s_bus_off_clear then
        s_bus_off_seen <= false;
      elsif llc_fce_o_dut_1.bus_off = '1' then
        s_bus_off_seen <= true;
      end if;
    end if;
  end process p_bus_off_latch;

  ----------------------------------------------------------------------------
  -- Transfer status latch (DUT 1 TX)
  ----------------------------------------------------------------------------
  p_status_latch_dut_1: process(clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' or clear_status_dut_1 or s_status_latch_rst_dut_1 then
        status_latch_dut_1 <= c_ongoing;
      else
        if llc_to_mac_tx_d2s_dut_1.transfer_status /= c_ongoing
           and llc_to_mac_tx_d2s_dut_1.transfer_status /= status_latch_dut_1 then
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
      if reset = '1' or clear_status_dut_2 or s_status_latch_rst_dut_2 then
        status_latch_dut_2 <= c_ongoing;
      else
        if llc_to_mac_tx_d2s_dut_2.transfer_status /= c_ongoing
           and llc_to_mac_tx_d2s_dut_2.transfer_status /= status_latch_dut_2 then
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
          -- status_latch_dut_1holds the first non-ongoing status; wait for it then clear.
          if status_latch_dut_1 = c_ongoing then
            wait until status_latch_dut_1 /= c_ongoing;
          end if;
          AffirmIfEqual(check_id, status_latch_dut_1, std_logic_vector(tx_llc_rec_dut_1.DataToModel(2 downto 0)), "Transfer status");
          clear_status_dut_1 <= true;
          wait until rising_edge(clk);
          clear_status_dut_1 <= false;
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
          clear_status_dut_2 <= true;
          wait until rising_edge(clk);
          clear_status_dut_2 <= false;
        when others => null;
      end case;
    end loop tx_llc_vc_dut_2_loop;
  end process p_tx_llc_vc_dut_2;

  ----------------------------------------------------------------------------
  -- RX LLC sink VC (DUT 2)
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
    rx_llc_rec_dut_2.Ack <= rx_llc_rec_dut_2.Ack + 1;  -- initial handshake: mark VC ready
    wait for 0 ns;

    rx_sink_loop : loop
      wait until rising_edge(clk);

      if s_rx_sink_flush then
        v_got_frame := false;
        v_byte_idx  := 0;
      end if;

      if (not v_got_frame and mac_to_llc_tx_s2d_dut_2.avalon_st_source.valid = '1') then
        v_frame(v_byte_idx) := mac_to_llc_tx_s2d_dut_2.avalon_st_source.data;
        if (mac_to_llc_tx_s2d_dut_2.avalon_st_source.endofpacket = '1') then
          v_frame_len := v_byte_idx + 1;
          v_got_frame := true;
        else
          v_byte_idx := v_byte_idx + 1;
        end if;
      end if;

      if v_got_frame and TransactionPending(rx_llc_rec_dut_2.Rdy, rx_llc_rec_dut_2.Ack) then
        case rx_llc_rec_dut_2.Operation is
          when CHECK =>
            v_exp_len := to_integer(unsigned(rx_llc_rec_dut_2.DataToModel(7 downto 0)));
            v_count   := to_integer(unsigned(rx_llc_rec_dut_2.ParamToModel(15 downto 0)));
            AffirmIfEqual(check_id, v_frame_len, v_exp_len, "Frame " & to_string(v_count) & " length");
            for i in 0 to v_exp_len - 1 loop
              v_exp_byte := Pop(rx_llc_rec_dut_2.BurstFifo);
              AffirmIfEqual(check_id, v_frame(i), v_exp_byte(7 downto 0), "Frame " & to_string(v_count) & " byte " & to_string(i));
            end loop;
            v_byte_idx  := 0;
            v_got_frame := false;
          when others => null;
        end case;
        FinishTransaction(rx_llc_rec_dut_2.Ack);
      end if;
    end loop rx_sink_loop;
  end process p_rx_llc_sink_vc;

  ----------------------------------------------------------------------------
  -- p_test_ctrl
  ----------------------------------------------------------------------------
  p_test_ctrl : process is

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
    procedure submit_and_verify(v_tx_frame : in t_llc_frame; v_last_byte : in natural; v_frame_count : in natural) is
    begin
      -- Pre-load expected bytes before sending: p_rx_llc_sink_vc processes them when the frame arrives.
      for i in 0 to v_last_byte loop
        Push(rx_llc_rec_dut_2.BurstFifo, std_logic_vector(resize(unsigned(v_tx_frame(i)), c_rec_width)));
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

      Check(tx_llc_rec_dut_1, std_logic_vector(resize(unsigned(c_transmitted), c_rec_width)));
      Check(rx_llc_rec_dut_2, std_logic_vector(to_unsigned(v_last_byte + 1, c_rec_width)), std_logic_vector(to_unsigned(v_frame_count, c_rec_width)));
    end procedure submit_and_verify;

    --------------------------------------------------------------------------
    -- Test 1: Normal usage -- cover all IDE x FDF x DLC bins
    --------------------------------------------------------------------------
    procedure test_normal is
      variable v_frame       : t_llc_frame;
      variable v_last_byte   : natural;
      variable v_frame_count : natural := 0;
    begin
      test_num <= 1;
      Print("--------------------------------------------------------------------------");
      Print("Test 1: Normal Usage (DUT 1 TX -> DUT 2 RX)");
      Print("--------------------------------------------------------------------------");
      while not (IsCovered(ide_cov) and IsCovered(fdf_cov) and IsCovered(dlc_cov) and IsCovered(ftyp_cov)) loop
        v_frame_count := v_frame_count + 1;

        gen_frame(v_frame, v_last_byte);
        submit_and_verify(v_frame, v_last_byte, v_frame_count);

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
      variable v_frame       : t_llc_frame;
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

        -- Drain in-flight propagation events at the previous delays.
        WaitForClock(clk, 10 * c_bit_time);

        for j in 1 to c_delay_frames_per_cfg loop
          v_frame_count := v_frame_count + 1;
          gen_frame(v_frame, v_last_byte);
          submit_and_verify(v_frame, v_last_byte, v_frame_count);
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
      s_transceiver_tx_d <= 300 ns;
      s_transceiver_rx_d <= 300 ns;
      s_bus_delay        <= 150 ns;
      for iter in 1 to c_iterations loop
        -- Wait for both DUTs idle before clearing latches.
        if llc_to_mac_tx_d2s_dut_1.transfer_status /= c_ongoing then
          wait until llc_to_mac_tx_d2s_dut_1.transfer_status = c_ongoing for 5 ms;
        end if;
        if llc_to_mac_tx_d2s_dut_2.transfer_status /= c_ongoing then
          wait until llc_to_mac_tx_d2s_dut_2.transfer_status = c_ongoing for 5 ms;
        end if;
        s_status_latch_rst_dut_1 <= true;
        s_status_latch_rst_dut_2 <= true;
        WaitForClock(clk, 2);
        s_status_latch_rst_dut_1 <= false;
        s_status_latch_rst_dut_2 <= false;

        loop
          v_id_1 := RV.RandInt(0, 2 ** c_base_id_width - 1);
          v_id_2 := RV.RandInt(0, 2 ** c_base_id_width - 1);
          exit when v_id_1 /= v_id_2;
        end loop;
        gen_frame(v_frame_1, v_last, v_id_1);
        gen_frame(v_frame_2, v_last, v_id_2);
        v_dut1_wins := v_id_1 < v_id_2;

        -- Both DUTs start sending frames at the same time
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

        if status_latch_dut_1= c_ongoing then
          wait until status_latch_dut_1/= c_ongoing for 5 ms;
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

      -- Reset latches, then wait for the iter-10 loser's retransmission result
      -- before flushing (one latch captures c_transmitted, the other stays c_ongoing).
      s_status_latch_rst_dut_1 <= true;
      s_status_latch_rst_dut_2 <= true;
      WaitForClock(clk, 2);
      s_status_latch_rst_dut_1 <= false;
      s_status_latch_rst_dut_2 <= false;
      wait until status_latch_dut_1 /= c_ongoing or status_latch_dut_2 /= c_ongoing for 5 ms;
      s_rx_sink_flush <= true;
      WaitForClock(clk, 2);
      s_rx_sink_flush <= false;
    end procedure test_lost_arb;

    --------------------------------------------------------------------------
    -- Test 4: Bus-off entry and recovery.
    -- Phase 1-2: s_dut_1_rx_recessive forces bit errors on every dominant drive forcing DUT 1 dominant.
    -- Phase 3: lift injection; FCE counts 128 x 11 recessive bits and recovers.
    -- Phase 4: confirm normal TX/RX resumes.
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
      s_bus_off_clear <= true;
      WaitForClock(clk, 2);
      s_bus_off_clear <= false;

      -- Phase 1: engage bit-error injection.
      s_dut_1_rx_recessive <= true;
      WaitForClock(clk, 10);

      -- Phase 2: drive DUT 1 to bus-off.
      gen_frame(v_frame, v_last_byte);
      while not s_bus_off_seen loop
        v_send_count := v_send_count + 1;
        for i in 0 to v_last_byte loop
          exit when s_bus_off_seen;
          if i = 0 then
            Send(tx_llc_rec_dut_1, v_frame(i), c_avalon_sop_byte);
          elsif i < v_last_byte then
            Send(tx_llc_rec_dut_1, v_frame(i), c_avalon_byte);
          else
            Send(tx_llc_rec_dut_1, v_frame(i), c_avalon_eop_byte);
          end if;
        end loop;
        -- Yield for at least one bit time so s_bus_off_seen can propagate.
        WaitForClock(clk, c_bit_time);
      end loop;
      AffirmIf(test_id, s_bus_off_seen, "Bus-off after " & to_string(v_send_count) & " sends");

      -- Phase 3: lift injection; wait for FCE bus-off recovery (128 x 11 bit times).
      s_dut_1_rx_recessive <= false;
      if llc_fce_o_dut_1.bus_off /= '0' then
        for t4_slice in 1 to 40 loop
          wait until llc_fce_o_dut_1.bus_off = '0' for 100 us;
          exit when llc_fce_o_dut_1.bus_off = '0';
        end loop;
      end if;
      AffirmIf(test_id, llc_fce_o_dut_1.bus_off = '0', "Bus-off recovered");

      -- Phase 4: DUT 1 completed bus_reintegration; allow intermission to
      -- finish, clear stale status latches, then send the confirmation frame.
      WaitForClock(clk, (c_bus_idle_condition_width + 2) * (c_bit_time + 1));
      s_status_latch_rst_dut_1 <= true;
      WaitForClock(clk, 2);
      s_status_latch_rst_dut_1 <= false;
      gen_frame(v_frame, v_last_byte);
      submit_and_verify(v_frame, v_last_byte, 0);
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
