--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   PCS sub-layer testbench (can_pcs_tx + can_pcs_rx with
--                shared bus model and configurable propagation delay).
--                  p_tx_mac_vc       - TX PCS MAC source VC (drives polarity and rate).
--                  p_rx_ctrl_vc      - RX PCS MAC control VC (sets use_data_rate, hard_sync_en).
--                  p_rx_collector_vc - RX PCS bit sink VC (collects SP samples, verifies).
--                  p_test_ctrl       - Coverage-driven test sequencer (CC + FD).
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-04-16  MRDSA     Initial PCS TX+RX integration testbench
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

entity can_pcs_tb is
  generic (
    gc_TbTimeOut      : time := 500 ms;
    gc_TbClkPeriod_tx : time := 10 ns;
    gc_TbClkPeriod_rx : time := 10.012 ns  -- RX oscillator 0.09% slow (within ISO 7.3.6 tolerance of 0.096%)
  );
end entity can_pcs_tb;

architecture tb of can_pcs_tb is

  ----------------------------------------------------------------------------
  -- Bit timing generics (shared by TX and RX)
  -- Using prescaler=2 for fast simulation with TDC capability
  ----------------------------------------------------------------------------
  constant c_prescaler       : t_prescaler          := 2;
  constant c_nom_sync_seg    : natural              := c_sync_seg;
  constant c_nom_prop_seg    : t_nominal_prop_seg   := 48;
  constant c_nom_phase_seg1  : t_nominal_phase_seg1 := 16;
  constant c_nom_phase_seg2  : t_nominal_phase_seg2 := 16;
  constant c_data_sync_seg   : natural              := c_sync_seg;
  constant c_data_prop_seg   : t_data_prop_seg      := 4;
  constant c_data_phase_seg1 : t_data_phase_seg1    := 4;
  constant c_data_phase_seg2 : t_data_phase_seg2    := 4;
  constant c_sjw_val         : t_sjw                := 2;

  -- Derived timing in clock cycles
  constant c_nom_bit_time_tq   : natural := c_nom_sync_seg + c_nom_prop_seg + c_nom_phase_seg1 + c_nom_phase_seg2;
  constant c_data_bit_time_tq  : natural := c_data_sync_seg + c_data_prop_seg + c_data_phase_seg1 + c_data_phase_seg2;
  constant c_nom_bit_time_clk  : natural := c_nom_bit_time_tq * c_prescaler;
  constant c_data_bit_time_clk : natural := c_data_bit_time_tq * c_prescaler;

  -- Bus propagation delay (absolute time, independent of node clocks)
  constant c_bus_delay : time := 200 ns;

  -- TX transceiver loopback delay (ISO 7.3.4: round-trip through transceiver).
  -- TDC measures from TX dominant edge to RX dominant edge on this path.
  constant c_tx_loopback_delay : time := 400 ns;

  -- Test parameters
  constant c_cc_stream_len : natural := 50;
  constant c_fd_nom_len    : natural := 20;
  constant c_fd_data_len   : natural := 40;
  constant c_fd_tail_len   : natural := 15;
  constant c_bin_at_least  : natural := 3;
  constant c_rec_width     : natural := 16;

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal clk_tx : std_logic;   -- TX node oscillator
  signal clk_rx : std_logic;   -- RX node oscillator (independent, slightly different frequency)
  signal reset  : std_logic := '1';

  -- Shared bus
  signal tx_bus_wire    : std_logic;
  signal rx_bus_wire    : std_logic := c_recessive;
  signal rx_tx_bus      : std_logic;
  signal bus_level      : std_logic;
  signal tx_loopback    : std_logic := c_recessive; -- TX PCS rx_bus_i with transceiver delay

  -- TX PCS interface (driven exclusively by p_tx_mac_vc)
  signal tx_mac_i : t_can_mac_pcs_if_m2s := c_mac_to_pcs_if_reset;
  signal tx_mac_o : t_can_mac_pcs_if_s2m;
  signal tx_fce_i : t_can_fce_pcs_if_m2s := c_fce_to_pcs_if_reset;
  signal tx_fce_o : t_can_pcs_fce_if_s2m;

  -- RX PCS interface (driven exclusively by p_rx_ctrl_vc)
  signal rx_mac_i : t_can_mac_pcs_rx_if_m2s := c_mac_to_pcs_rx_if_reset;
  signal rx_mac_o : t_can_mac_pcs_rx_if_s2m;
  signal rx_fce_i : t_can_fce_pcs_if_m2s := c_fce_to_pcs_if_reset;
  signal rx_fce_o : t_can_pcs_fce_if_s2m;

  -- RX PCS debug ports
  signal rx_phase1_ext      : natural;
  signal rx_phase2_short    : natural;
  signal rx_prescaler_reset : boolean;

  -- OSVVM signals
  shared variable RV : RandomPType;
  signal test_id      : AlertLogIDType;
  signal check_id     : AlertLogIDType;
  signal pol_cov      : CoverageIDType;
  signal init_barrier : std_logic := '0';
  signal test_num     : natural := 0;

  -- Transaction records
  -- TX MAC VC: DataToModel [0]=polarity, [1]=use_data_rate, [2]=start_tdc
  --            ParamToModel = bit_time_clk as unsigned
  signal tx_mac_rec : StreamRecType(
    DataToModel    (c_rec_width - 1 downto 0),
    ParamToModel   (c_rec_width - 1 downto 0),
    DataFromModel  (c_rec_width - 1 downto 0),
    ParamFromModel (c_rec_width - 1 downto 0)
  );

  -- RX ctrl VC: DataToModel [0]=use_data_rate, [1]=hard_sync_en
  signal rx_ctrl_rec : StreamRecType(
    DataToModel    (c_rec_width - 1 downto 0),
    ParamToModel   (c_rec_width - 1 downto 0),
    DataFromModel  (c_rec_width - 1 downto 0),
    ParamFromModel (c_rec_width - 1 downto 0)
  );

  -- RX collector VC: CHECK with expected count in DataToModel, expected bits in BurstFifo
  signal rx_coll_rec : StreamRecType(
    DataToModel    (c_rec_width - 1 downto 0),
    ParamToModel   (c_rec_width - 1 downto 0),
    DataFromModel  (c_rec_width - 1 downto 0),
    ParamFromModel (c_rec_width - 1 downto 0)
  );

begin

  ----------------------------------------------------------------------------
  -- Infrastructure
  ----------------------------------------------------------------------------
  CreateClock(clk_tx, gc_TbClkPeriod_tx);
  CreateClock(clk_rx, gc_TbClkPeriod_rx);
  CreateReset(reset, '1', clk_tx, gc_TbClkPeriod_tx * 10);

  p_timeout : process is
  begin
    wait for gc_TbTimeOut;
    assert false report "ERROR TEST FAILED, due to time out" severity error;
    std.env.stop(1);
  end process p_timeout;

  p_init : process is
    variable v_test_id  : AlertLogIDType;
    variable v_check_id : AlertLogIDType;
    variable v_pol_cov  : CoverageIDType;
  begin
    SetAlertStopCount(ERROR, 1);
    v_test_id  := NewID("can_pcs");
    v_check_id := NewID("Bit check", v_test_id);
    v_pol_cov  := NewID("Polarity Coverage", v_test_id, ReportMode => ENABLED);
    RV.InitSeed(RV'instance_name & to_string(now));
    AddBins(v_pol_cov, c_bin_at_least, GenBin(0, 1));
    rx_coll_rec.BurstFifo <= NewID("RX Coll Burst fifo");
    test_id  <= v_test_id;
    check_id <= v_check_id;
    pol_cov  <= v_pol_cov;
    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  ----------------------------------------------------------------------------
  -- Bus model: dominant-wins (AND) with transport delays
  -- TX PCS drives tx_bus_wire directly onto the bus.
  -- RX PCS tx_bus_o (rx_tx_bus) carries ACK/error flags onto the bus.
  -- TX PCS sees bus with transceiver loopback delay (for TDC measurement).
  -- RX PCS sees bus delayed by c_bus_delay (propagation model).
  ----------------------------------------------------------------------------
  bus_level <= tx_bus_wire and rx_tx_bus;

  p_tx_loopback_delay : process is
  begin
    wait on bus_level;
    tx_loopback <= transport bus_level after c_tx_loopback_delay;
  end process p_tx_loopback_delay;

  p_rx_delay : process is
  begin
    wait on bus_level;
    rx_bus_wire <= transport bus_level after c_bus_delay;
  end process p_rx_delay;

  ----------------------------------------------------------------------------
  -- DUT: TX PCS
  ----------------------------------------------------------------------------
  u_pcs_tx : entity work.can_pcs_tx
    generic map (
      gc_prescaler       => c_prescaler,
      gc_nom_sync_seg    => c_nom_sync_seg,
      gc_nom_prop_seg    => c_nom_prop_seg,
      gc_nom_phase_seg1  => c_nom_phase_seg1,
      gc_nom_phase_seg2  => c_nom_phase_seg2,
      gc_data_sync_seg   => c_data_sync_seg,
      gc_data_prop_seg   => c_data_prop_seg,
      gc_data_phase_seg1 => c_data_phase_seg1,
      gc_data_phase_seg2 => c_data_phase_seg2,
      gc_tdc_enable      => '1'
    )
    port map (
      clk_i    => clk_tx,
      rst_i    => reset,
      mac_i    => tx_mac_i,
      mac_o    => tx_mac_o,
      fce_i    => tx_fce_i,
      fce_o    => tx_fce_o,
      tx_bus_o => tx_bus_wire,
      rx_bus_i => tx_loopback
    );

  ----------------------------------------------------------------------------
  -- DUT: RX PCS
  ----------------------------------------------------------------------------
  u_pcs_rx : entity work.can_pcs_rx
    generic map (
      gc_prescaler       => c_prescaler,
      gc_nom_prop_seg    => c_nom_prop_seg,
      gc_nom_phase_seg1  => c_nom_phase_seg1,
      gc_nom_phase_seg2  => c_nom_phase_seg2,
      gc_data_prop_seg   => c_data_prop_seg,
      gc_data_phase_seg1 => c_data_phase_seg1,
      gc_data_phase_seg2 => c_data_phase_seg2,
      gc_sjw             => c_sjw_val
    )
    port map (
      clk_i    => clk_rx,
      rst_i    => reset,
      mac_i    => rx_mac_i,
      mac_o    => rx_mac_o,
      fce_i    => rx_fce_i,
      fce_o    => rx_fce_o,
      tx_bus_o => rx_tx_bus,
      rx_bus_i => rx_bus_wire,
      debug_phase1_extension_o  => rx_phase1_ext,
      debug_phase2_shortening_o => rx_phase2_short,
      debug_prescaler_restart_o => rx_prescaler_reset
    );

  ----------------------------------------------------------------------------
  -- TX MAC source VC
  -- Drives polarity and use_data_rate onto tx_mac_i.
  -- SEND: DataToModel [0]=polarity, [1]=use_data_rate, [2]=start_tdc
  --       ParamToModel = bit hold time in clock cycles (unsigned)
  ----------------------------------------------------------------------------
  p_tx_mac_vc : process is
    variable v_hold_clks : natural;
  begin
    WaitForBarrier(init_barrier);
    tx_mac_i <= c_mac_to_pcs_if_reset;

    tx_mac_vc_loop : loop
      WaitForTransaction(tx_mac_rec.Rdy, tx_mac_rec.Ack);
      case tx_mac_rec.Operation is
        when SEND =>
          tx_mac_i.polarity      <= tx_mac_rec.DataToModel(0);
          tx_mac_i.use_data_rate <= tx_mac_rec.DataToModel(1);
          tx_mac_i.start_tdc     <= tx_mac_rec.DataToModel(2);
          v_hold_clks := to_integer(unsigned(tx_mac_rec.ParamToModel));
          WaitForClock(clk_tx, v_hold_clks);
        when SEND_BURST =>
          -- Reset TX MAC interface to idle
          tx_mac_i <= c_mac_to_pcs_if_reset;
        when others => null;
      end case;
    end loop tx_mac_vc_loop;
  end process p_tx_mac_vc;

  ----------------------------------------------------------------------------
  -- RX control VC
  -- Drives use_data_rate and hard_sync_en onto rx_mac_i.
  -- SEND: DataToModel [0]=use_data_rate, [1]=hard_sync_en
  ----------------------------------------------------------------------------
  p_rx_ctrl_vc : process is
  begin
    WaitForBarrier(init_barrier);
    rx_mac_i <= c_mac_to_pcs_rx_if_reset;

    rx_ctrl_vc_loop : loop
      WaitForTransaction(rx_ctrl_rec.Rdy, rx_ctrl_rec.Ack);
      case rx_ctrl_rec.Operation is
        when SEND =>
          rx_mac_i.use_data_rate <= rx_ctrl_rec.DataToModel(0);
          rx_mac_i.hard_sync_en  <= rx_ctrl_rec.DataToModel(1);
        when others => null;
      end case;
    end loop rx_ctrl_vc_loop;
  end process p_rx_ctrl_vc;

  ----------------------------------------------------------------------------
  -- RX bit collector VC
  -- Continuously collects bus_polarity on each rx_mac_o.sample_point strobe.
  -- SEND: clears the collected buffer (call before starting a new TX stream).
  -- CHECK: verifies collected bits against expected bits from BurstFifo.
  --        DataToModel(7:0) = expected bit count,
  --        ParamToModel(15:0) = test number (for log messages).
  ----------------------------------------------------------------------------
  p_rx_collector_vc : process is
    constant c_max_bits    : natural := 256;
    variable v_rx_bits     : std_logic_vector(0 to c_max_bits - 1);
    variable v_rx_len      : natural := 0;
    variable v_collecting  : boolean := false;
    variable v_exp_count   : natural;
    variable v_test_num    : natural;
    variable v_exp_bit     : std_logic_vector(c_rec_width - 1 downto 0);
    variable v_mismatches  : natural;
    variable v_compare_len : natural;
    variable v_offset      : natural;
  begin
    WaitForBarrier(init_barrier);
    wait until reset = '0';

    rx_collector_loop : loop
      wait until rising_edge(clk_rx);

      -- Collect sampled bit on every SP strobe while collecting is enabled
      if (v_collecting and rx_mac_o.sample_point = '1' and v_rx_len < c_max_bits) then
        v_rx_bits(v_rx_len) := rx_mac_o.bus_polarity;
        v_rx_len            := v_rx_len + 1;
      end if;

      -- Handle transactions
      if TransactionPending(rx_coll_rec.Rdy, rx_coll_rec.Ack) then
        case rx_coll_rec.Operation is
          when SEND =>
            -- Clear buffer and start collecting
            v_rx_len     := 0;
            v_collecting := true;

          when CHECK =>
            v_collecting := false;
            v_exp_count  := to_integer(unsigned(rx_coll_rec.DataToModel(7 downto 0)));
            v_test_num   := to_integer(unsigned(rx_coll_rec.ParamToModel(15 downto 0)));

            Print("  Test " & to_string(v_test_num) & ": TX sent " &
              to_string(v_exp_count) & " bits, RX received " & to_string(v_rx_len) & " bits");

            AffirmIf(check_id, v_rx_len > 0,
              "Test " & to_string(v_test_num) & ": RX must receive at least one bit");

            -- The RX stream starts with idle recessive samples collected
            -- before the SOF arrives (bus delay). Find the first dominant bit
            -- (SOF) to align the comparison.
            v_offset := 0;
            for i in 0 to v_rx_len - 1 loop
              if v_rx_bits(i) = c_dominant then
                v_offset := i;
                exit;
              end if;
            end loop;

            -- Compare from aligned position
            v_mismatches  := 0;
            v_compare_len := 0;
            for i in 0 to v_exp_count - 1 loop
              exit when v_offset + i >= v_rx_len;
              v_exp_bit     := Pop(rx_coll_rec.BurstFifo);
              v_compare_len := v_compare_len + 1;
              if (v_rx_bits(v_offset + i) /= v_exp_bit(0)) then
                v_mismatches := v_mismatches + 1;
                Print("    Mismatch at TX bit " & to_string(i) & " (RX idx " &
                  to_string(v_offset + i) & "): expected " &
                  std_logic'image(v_exp_bit(0)) & " got " &
                  std_logic'image(v_rx_bits(v_offset + i)));
              end if;
            end loop;

            -- Flush remaining expected bits from the fifo
            for i in v_compare_len to v_exp_count - 1 loop
              v_exp_bit := Pop(rx_coll_rec.BurstFifo);
            end loop;

            AffirmIf(check_id, v_compare_len > 0,
              "Test " & to_string(v_test_num) & ": at least one bit compared");
            AffirmIf(check_id, v_mismatches = 0,
              "Test " & to_string(v_test_num) & ": bit comparison " &
              to_string(v_mismatches) & " mismatches out of " & to_string(v_compare_len));

            v_rx_len := 0;
          when others => null;
        end case;
        FinishTransaction(rx_coll_rec.Ack);
      end if;
    end loop rx_collector_loop;
  end process p_rx_collector_vc;

  ----------------------------------------------------------------------------
  -- Resync monitor: prints when Phase_Seg adjustments change (Test 6 only)
  ----------------------------------------------------------------------------
  p_resync_monitor : process is
    variable v_prev_p1      : natural := 0;
    variable v_prev_p2      : natural := 0;
    variable v_prev_restart : boolean := false;
  begin
    wait until reset = '0';

    resync_mon_loop : loop
      wait until rising_edge(clk_rx);

      if test_num = 6 then
        if rx_phase1_ext /= v_prev_p1 then
          report "  [RESYNC] phase1_extension: " & to_string(v_prev_p1) &
            " -> " & to_string(rx_phase1_ext) & " at " & time'image(now)
            severity note;
          v_prev_p1 := rx_phase1_ext;
        end if;

        if rx_phase2_short /= v_prev_p2 then
          report "  [RESYNC] phase2_shortening: " & to_string(v_prev_p2) &
            " -> " & to_string(rx_phase2_short) & " at " & time'image(now)
            severity note;
          v_prev_p2 := rx_phase2_short;
        end if;

        if rx_prescaler_reset and not v_prev_restart then
          report "  [RESYNC] prescaler_restart (edge in/near Sync_Seg) at " &
            time'image(now) severity note;
        end if;
        v_prev_restart := rx_prescaler_reset;
      end if;
    end loop resync_mon_loop;
  end process p_resync_monitor;

  ----------------------------------------------------------------------------
  -- p_test_ctrl
  ----------------------------------------------------------------------------
  p_test_ctrl : process is

    --------------------------------------------------------------------------
    -- send_tx_bit: SEND one bit via TX MAC VC transaction
    --------------------------------------------------------------------------
    procedure send_tx_bit (
      pol           : std_logic;
      use_data_rate : std_logic;
      start_tdc     : std_logic;
      bit_time_clk  : natural
    ) is
      variable v_data  : std_logic_vector(c_rec_width - 1 downto 0) := (others => '0');
      variable v_param : std_logic_vector(c_rec_width - 1 downto 0);
    begin
      v_data(0) := pol;
      v_data(1) := use_data_rate;
      v_data(2) := start_tdc;
      v_param   := std_logic_vector(to_unsigned(bit_time_clk, c_rec_width));
      Send(tx_mac_rec, v_data, v_param);
    end procedure send_tx_bit;

    --------------------------------------------------------------------------
    -- set_rx_ctrl: SEND control signals to RX PCS MAC interface
    --------------------------------------------------------------------------
    procedure set_rx_ctrl (
      use_data_rate : std_logic;
      hard_sync_en  : std_logic
    ) is
      variable v_data : std_logic_vector(c_rec_width - 1 downto 0) := (others => '0');
    begin
      v_data(0) := use_data_rate;
      v_data(1) := hard_sync_en;
      Send(rx_ctrl_rec, v_data);
    end procedure set_rx_ctrl;

    --------------------------------------------------------------------------
    -- Test 1: Reset defaults
    --------------------------------------------------------------------------
    procedure test_reset is
    begin
      test_num <= 1;
      Print("--------------------------------------------------------------------------");
      Print("Test 1: Reset defaults");
      Print("--------------------------------------------------------------------------");

      AffirmIf(check_id, tx_bus_wire = c_recessive, "TX bus recessive after reset");
      AffirmIf(check_id, tx_mac_o.sample_point = '0', "TX SP deasserted after reset");
      AffirmIf(check_id, rx_mac_o.sample_point = '0', "RX SP deasserted after reset");
      AffirmIf(check_id, rx_mac_o.bus_polarity = c_recessive, "RX bus_polarity recessive after reset");
    end procedure test_reset;

    --------------------------------------------------------------------------
    -- Test 2: CC (nominal-rate only) bitstream transfer
    --------------------------------------------------------------------------
    procedure test_cc_transfer is
      variable v_pol : std_logic;
    begin
      test_num <= 2;
      Print("--------------------------------------------------------------------------");
      Print("Test 2: CC bitstream transfer (nominal rate)");
      Print("--------------------------------------------------------------------------");

      -- Wait for bus idle
      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);

      -- Start collecting at RX
      Send(rx_coll_rec, std_logic_vector(to_unsigned(0, c_rec_width)));

      -- First bit is SOF (dominant) to trigger hard sync at RX
      v_pol := c_dominant;
      Push(rx_coll_rec.BurstFifo, std_logic_vector(to_unsigned(0, c_rec_width - 1)) & v_pol);
      send_tx_bit(v_pol, '0', '0', c_nom_bit_time_clk);

      for i in 1 to c_cc_stream_len - 1 loop
        v_pol := RV.RandSlv(1)(1);
        Push(rx_coll_rec.BurstFifo, std_logic_vector(to_unsigned(0, c_rec_width - 1)) & v_pol);
        send_tx_bit(v_pol, '0', '0', c_nom_bit_time_clk);
        ICover(pol_cov, to_integer(unsigned'("" & v_pol)));
      end loop;

      -- Wait for RX PCS to sample remaining bits (propagation + one more bit time)
      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);

      -- Verify received bits
      Check(rx_coll_rec,
        std_logic_vector(to_unsigned(c_cc_stream_len, c_rec_width)),
        std_logic_vector(to_unsigned(2, c_rec_width)));
    end procedure test_cc_transfer;

    --------------------------------------------------------------------------
    -- Test 3: FD (nominal + data rate) bitstream transfer
    --
    -- TX PCS FSM: nominal -> measuring -> data (3 nominal bit boundaries).
    -- RX PCS FSM: nominal -> data (1 bit boundary).
    --
    -- ISO 11898-1:2015 Section 7.3 transition sequence:
    --   Phase 1: Nominal-rate bits (SOF + arb field)          -- verified
    --   Phase 2: FDF bit with start_tdc=1 (TX: nominal->measuring)
    --            res bit (TDC measurement, still measuring)
    --            BRS bit with use_data_rate=1 (TX: measuring->data)
    --            These 3 transition bits are excluded from comparison.
    --   Phase 3: RX switches to data rate (manual coordination)
    --   Phase 4: Data-rate bits (ESI onwards)                 -- verified
    --   Phase 5: Switch back to nominal rate
    --   Phase 6: Nominal-rate tail bits                       -- verified
    --------------------------------------------------------------------------
    procedure test_fd_transfer is
      variable v_pol           : std_logic;
      variable v_data_bits_len : natural := 0;
    begin
      test_num <= 3;
      Print("--------------------------------------------------------------------------");
      Print("Test 3: FD bitstream transfer (nominal + data rate)");
      Print("--------------------------------------------------------------------------");

      -- Wait for bus idle
      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);

      -- Start collecting at RX
      Send(rx_coll_rec, std_logic_vector(to_unsigned(0, c_rec_width)));

      -- Phase 1: Nominal-rate bits (SOF + arbitration)
      -- SOF dominant
      v_pol := c_dominant;
      Push(rx_coll_rec.BurstFifo, std_logic_vector(to_unsigned(0, c_rec_width - 1)) & v_pol);
      send_tx_bit(v_pol, '0', '0', c_nom_bit_time_clk);

      -- Remaining nominal bits before rate switch
      for i in 1 to c_fd_nom_len - 1 loop
        v_pol := RV.RandSlv(1)(1);
        Push(rx_coll_rec.BurstFifo, std_logic_vector(to_unsigned(0, c_rec_width - 1)) & v_pol);
        send_tx_bit(v_pol, '0', '0', c_nom_bit_time_clk);
      end loop;

      -- Phase 2: TX transition (nominal -> measuring -> data).
      -- ISO 7.3: FDF dominant edge triggers TDC measurement, BRS is last
      -- nominal bit, ESI is first data-rate bit.
      --
      -- FDF bit: start_tdc=1 (TX PCS: nominal -> measuring at bit boundary)
      send_tx_bit(c_dominant, '0', '1', c_nom_bit_time_clk);
      -- res bit: TDC measurement in progress, still s_measuring
      send_tx_bit(c_recessive, '0', '0', c_nom_bit_time_clk);

      -- BRS bit: Both TX and RX switch to data rate at the same bit boundary.
      -- In real hardware both MAC FSMs observe BRS on the bus and assert
      -- use_data_rate simultaneously. Here we set RX before the BRS bit so
      -- use_data_rate is already latched when both PCS modules hit their
      -- next bit boundary.
      set_rx_ctrl(use_data_rate => '1', hard_sync_en => '0');
      send_tx_bit(c_recessive, '1', '0', c_nom_bit_time_clk);

      -- These 3 transition bits are not pushed to the expected fifo since they
      -- have complex timing. Instead, stop collecting, verify Phase 1, then
      -- restart collection for Phase 4.

      -- Verify Phase 1 nominal bits (before transition)
      WaitForClock(clk_tx, c_nom_bit_time_clk * 2);
      Check(rx_coll_rec,
        std_logic_vector(to_unsigned(c_fd_nom_len, c_rec_width)),
        std_logic_vector(to_unsigned(3, c_rec_width)));

      -- Phase 4: Data-rate bits (both sides in data mode)
      -- Start fresh collection
      Send(rx_coll_rec, std_logic_vector(to_unsigned(0, c_rec_width)));

      -- First data-rate bit forced dominant for RX collector SOF-alignment
      v_pol := c_dominant;
      Push(rx_coll_rec.BurstFifo, std_logic_vector(to_unsigned(0, c_rec_width - 1)) & v_pol);
      send_tx_bit(v_pol, '1', '0', c_data_bit_time_clk);
      v_data_bits_len := v_data_bits_len + 1;

      for i in 1 to c_fd_data_len - 1 loop
        v_pol := RV.RandSlv(1)(1);
        Push(rx_coll_rec.BurstFifo, std_logic_vector(to_unsigned(0, c_rec_width - 1)) & v_pol);
        send_tx_bit(v_pol, '1', '0', c_data_bit_time_clk);
        v_data_bits_len := v_data_bits_len + 1;
        ICover(pol_cov, to_integer(unsigned'("" & v_pol)));
      end loop;

      -- Wait for last data-rate bits to propagate to RX
      WaitForClock(clk_tx, c_data_bit_time_clk * 3);

      -- Verify data-rate bits
      Check(rx_coll_rec,
        std_logic_vector(to_unsigned(v_data_bits_len, c_rec_width)),
        std_logic_vector(to_unsigned(3, c_rec_width)));

      -- Phase 5: Switch both sides back to nominal rate simultaneously.
      -- Re-enable hard sync (ISO 7.3.5.1 rule c: hard sync during EOF/IFS).
      -- Set RX before the TX transition bit so both see use_data_rate='0'
      -- at their next bit boundary.
      set_rx_ctrl(use_data_rate => '0', hard_sync_en => '1');
      send_tx_bit(c_recessive, '0', '0', c_data_bit_time_clk);

      -- Wait for both PCS modules to settle back to nominal
      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);

      -- Phase 6: Nominal-rate tail bits
      Send(rx_coll_rec, std_logic_vector(to_unsigned(0, c_rec_width)));

      -- First tail bit forced dominant for RX collector SOF-alignment
      v_pol := c_dominant;
      Push(rx_coll_rec.BurstFifo, std_logic_vector(to_unsigned(0, c_rec_width - 1)) & v_pol);
      send_tx_bit(v_pol, '0', '0', c_nom_bit_time_clk);

      for i in 1 to c_fd_tail_len - 1 loop
        v_pol := RV.RandSlv(1)(1);
        Push(rx_coll_rec.BurstFifo, std_logic_vector(to_unsigned(0, c_rec_width - 1)) & v_pol);
        send_tx_bit(v_pol, '0', '0', c_nom_bit_time_clk);
      end loop;

      -- Wait for RX to sample remaining bits
      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);

      -- Verify tail bits
      Check(rx_coll_rec,
        std_logic_vector(to_unsigned(c_fd_tail_len, c_rec_width)),
        std_logic_vector(to_unsigned(3, c_rec_width)));

      -- Reset both sides to defaults
      set_rx_ctrl(use_data_rate => '0', hard_sync_en => '1');
      -- Send a few idle recessive bits to ensure TX PCS is fully in nominal
      send_tx_bit(c_recessive, '0', '0', c_nom_bit_time_clk);
      send_tx_bit(c_recessive, '0', '0', c_nom_bit_time_clk);
      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);
    end procedure test_fd_transfer;

    --------------------------------------------------------------------------
    -- Test 4: SP cadence verification (nominal rate, TX PCS)
    --------------------------------------------------------------------------
    procedure test_sp_cadence is
      variable v_sp_count    : natural := 0;
      variable v_clk_count   : natural := 0;
      variable v_first_seen  : boolean := false;
      variable v_period      : natural := 0;
      variable v_periods_ok  : natural := 0;
    begin
      test_num <= 4;
      Print("--------------------------------------------------------------------------");
      Print("Test 4: SP cadence verification (nominal rate)");
      Print("--------------------------------------------------------------------------");

      -- Observe SP strobes on TX PCS during idle bus (recessive)
      v_sp_count   := 0;
      v_first_seen := false;
      v_periods_ok := 0;

      for i in 1 to c_nom_bit_time_clk * 10 loop
        wait until rising_edge(clk_tx);
        if tx_mac_o.sample_point = '1' then
          if v_first_seen then
            v_period := v_clk_count + 1; -- +1: include this SP clock cycle
            if v_period = c_nom_bit_time_clk then
              v_periods_ok := v_periods_ok + 1;
            end if;
          end if;
          v_first_seen := true;
          v_clk_count  := 0;
          v_sp_count   := v_sp_count + 1;
        else
          v_clk_count := v_clk_count + 1;
        end if;
      end loop;

      AffirmIf(check_id, v_sp_count >= 8,
        "Expected >= 8 TX SP strobes, got " & to_string(v_sp_count));
      AffirmIf(check_id, v_periods_ok >= 6,
        "TX SP period = " & to_string(c_nom_bit_time_clk) & " clk verified " &
        to_string(v_periods_ok) & " times");
    end procedure test_sp_cadence;

    --------------------------------------------------------------------------
    -- Test 5: TDC measurement with long bus delay
    --
    -- The TX transceiver loopback delay (c_tx_loopback_delay) models the
    -- real round-trip through the CAN transceiver. TDC measures from the
    -- TX dominant edge to the RX dominant edge on this delayed path.
    --
    -- With 40 clk delay, prescaler=2, data_bit_time=13 TQ:
    --   delay_count_clk = ~40
    --   v_delay_tq      = ceil(40/2) = 20
    --   tdc_delay        = ceil(20/13) = 2
    --   ssp_position     = (20 + 8) mod 13 = 2
    --
    -- Verifies:
    --   1. tdc_delay output is non-zero after measuring phase
    --   2. secondary_sample_point fires during data phase
    --------------------------------------------------------------------------
    procedure test_tdc_long_delay is
      variable v_pol           : std_logic;
      variable v_ssp_count    : natural := 0;
      variable v_tdc_val      : natural := 0;
      variable v_ssp_standoff : natural := 0;
      variable v_standoff_done : boolean := false;
    begin
      test_num <= 5;
      Print("--------------------------------------------------------------------------");
      Print("Test 5: TDC measurement with long bus delay");
      Print("--------------------------------------------------------------------------");

      -- Wait for bus idle
      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);

      -- Phase 1: A few nominal bits (SOF + arb) to establish bus activity
      send_tx_bit(c_dominant, '0', '0', c_nom_bit_time_clk); -- SOF
      for i in 1 to 5 loop
        send_tx_bit(c_recessive, '0', '0', c_nom_bit_time_clk);
      end loop;

      -- Phase 2: FDF bit with start_tdc (TX PCS: nominal -> measuring)
      -- The FDF-to-res dominant edge triggers TDC counting.
      send_tx_bit(c_dominant, '0', '1', c_nom_bit_time_clk);

      -- res bit: recessive, TDC counts until RX dominant edge arrives
      -- (delayed by c_tx_loopback_delay through the bus model)
      send_tx_bit(c_recessive, '0', '0', c_nom_bit_time_clk);

      -- BRS bit: set use_data_rate=1 with minimal hold (2 clk).
      -- The interface retains these values after the VC returns.
      -- We start observing immediately so we can catch the standoff.
      send_tx_bit(c_recessive, '1', '0', 2);

      -- Phase 3: Observe SSP clock-by-clock from here.
      -- The PCS is still finishing the current nominal bit and will
      -- transition measuring->data at the next bit boundary. We watch
      -- through the transition and the full data phase to verify:
      --   (a) tdc_delay is non-zero
      --   (b) SSP does NOT fire during the standoff period
      --   (c) SSP DOES fire after the standoff
      v_ssp_count     := 0;
      v_ssp_standoff  := 0;
      v_standoff_done := false;
      v_tdc_val       := 0;

      -- Observe for up to 2 nominal + 10 data bit times (covers transition + data phase)
      for i in 1 to c_nom_bit_time_clk * 2 + c_data_bit_time_clk * 10 loop
        wait until rising_edge(clk_tx);

        -- Latch tdc_delay once it becomes non-zero
        if (v_tdc_val = 0 and unsigned(tx_mac_o.tdc_delay) > 0) then
          v_tdc_val := to_integer(unsigned(tx_mac_o.tdc_delay));
        end if;

        if tx_mac_o.secondary_sample_point = '1' then
          v_ssp_count := v_ssp_count + 1;
          if not v_standoff_done then
            v_standoff_done := true;
            v_ssp_standoff  := i; -- clock cycle of first SSP (from start of observation)
          end if;
        end if;
      end loop;

      Print("  TDC delay value: " & to_string(v_tdc_val));
      Print("  SSP first fired at observation clock: " & to_string(v_ssp_standoff));
      Print("  SSP pulses observed: " & to_string(v_ssp_count));

      AffirmIf(check_id, v_tdc_val > 0,
        "TDC delay must be > 0 with " & time'image(c_tx_loopback_delay) &
        " loopback delay, got " & to_string(v_tdc_val));

      -- SSP must not fire during the first tdc_delay data bit times.
      -- The observation starts ~1 nominal bit before s_data, so the standoff
      -- window relative to observation start is approximately:
      --   nom_bit_time + tdc_delay * data_bit_time
      -- We check that the first SSP fires after at least tdc_delay data bit
      -- times from the start of the observation (conservative lower bound).
      AffirmIf(check_id, v_ssp_standoff > v_tdc_val * c_data_bit_time_clk,
        "SSP must respect standoff of " & to_string(v_tdc_val) & " data bit times (" &
        to_string(v_tdc_val * c_data_bit_time_clk) & " clks), first SSP at obs clk " &
        to_string(v_ssp_standoff));

      AffirmIf(check_id, v_ssp_count > 0,
        "SSP must fire at least once after standoff, got " &
        to_string(v_ssp_count) & " pulses");

      -- Phase 4: Switch back to nominal
      send_tx_bit(c_recessive, '0', '0', c_data_bit_time_clk);
      send_tx_bit(c_recessive, '0', '0', c_nom_bit_time_clk);
      send_tx_bit(c_recessive, '0', '0', c_nom_bit_time_clk);
      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);
    end procedure test_tdc_long_delay;

    --------------------------------------------------------------------------
    -- Test 6: Resynchronization under oscillator drift (ISO 7.3.5.4)
    --
    -- Models two CAN nodes with different oscillator frequencies:
    --   TX node: gc_TbClkPeriod_tx (10.00 ns)
    --   RX node: gc_TbClkPeriod_rx (10.009 ns, 0.09% slow)
    --
    -- Per-bit drift: 0.0009 * 81 TQ = ~0.073 TQ/bit.
    --
    -- Bit pattern: groups of 5 dominant + 1 recessive (bit stuffing worst
    -- case per ISO 8.5). The rec-to-dom edge after the recessive bit
    -- triggers resync. Between edges (6 bits), drift accumulates:
    --   6 * 0.073 = 0.44 TQ < SJW(2)
    -- Within ISO 7.3.6 tolerance (0.096%), so the |e| <= SJW restart
    -- path fires on each edge, returning it to Sync_Seg every time.
    --
    -- Procedure:
    --   1. SOF with hard_sync_en='1' (hard sync to align RX, ISO 7.3.5.3)
    --   2. Switch to hard_sync_en='0' (resync mode, ISO 7.3.5.1 rule d)
    --   3. Send groups of 5 dominant + 1 recessive to stress resync
    --   4. Verify all bits sampled correctly
    --------------------------------------------------------------------------
    procedure test_resync_drift is
      constant c_group_len   : natural := 5;  -- Same-polarity bits per group (bit stuffing limit)
      constant c_num_groups  : natural := 25; -- Number of groups
      variable v_bit_count   : natural := 0;
    begin
      test_num <= 6;
      Print("--------------------------------------------------------------------------");
      Print("Test 6: Resynchronization under oscillator drift (ISO 7.3.5.4)");
      Print("  TX clk period: " & time'image(gc_TbClkPeriod_tx));
      Print("  RX clk period: " & time'image(gc_TbClkPeriod_rx));
      Print("  Drift per bit: ~0.073 TQ, SJW=" & to_string(c_sjw_val));
      Print("  Pattern: " & to_string(c_group_len) & " dominant + 1 recessive x " &
        to_string(c_num_groups) & " groups");
      Print("--------------------------------------------------------------------------");

      -- Wait for bus idle
      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);

      -- Start collecting at RX
      Send(rx_coll_rec, std_logic_vector(to_unsigned(0, c_rec_width)));

      -- SOF dominant with hard_sync_en='1' (hard sync aligns RX to TX)
      Push(rx_coll_rec.BurstFifo, std_logic_vector(to_unsigned(0, c_rec_width - 1)) & c_dominant);
      send_tx_bit(c_dominant, '0', '0', c_nom_bit_time_clk);
      v_bit_count := 1;

      -- Switch to resync mode (ISO 7.3.5.1 rule d: resync during frame)
      set_rx_ctrl(use_data_rate => '0', hard_sync_en => '0');

      -- Send groups: 5 dominant (drift accumulates past SJW) + 1 recessive
      for g in 0 to c_num_groups - 1 loop
        -- Dominant group: no rec-to-dom edges, drift accumulates
        for i in 0 to c_group_len - 1 loop
          Push(rx_coll_rec.BurstFifo, std_logic_vector(to_unsigned(0, c_rec_width - 1)) & c_dominant);
          send_tx_bit(c_dominant, '0', '0', c_nom_bit_time_clk);
          v_bit_count := v_bit_count + 1;
        end loop;

        -- Recessive bit: sampled at SP, then next group's dominant creates
        -- the rec-to-dom edge that triggers resync (ISO 7.3.5.1 rule b)
        Push(rx_coll_rec.BurstFifo, std_logic_vector(to_unsigned(0, c_rec_width - 1)) & c_recessive);
        send_tx_bit(c_recessive, '0', '0', c_nom_bit_time_clk);
        v_bit_count := v_bit_count + 1;
      end loop;

      -- Wait for RX to sample remaining bits
      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);

      -- Verify all bits sampled correctly despite drift
      Check(rx_coll_rec,
        std_logic_vector(to_unsigned(v_bit_count, c_rec_width)),
        std_logic_vector(to_unsigned(6, c_rec_width)));

      -- Reset RX to default (hard_sync_en='1' for bus integration)
      set_rx_ctrl(use_data_rate => '0', hard_sync_en => '1');
    end procedure test_resync_drift;

    --------------------------------------------------------------------------
    procedure report_results is
    begin
      AffirmIf(test_id, IsCovered(pol_cov), "Polarity covered");
      WriteBin(pol_cov);
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

    -- Wait for PCS to stabilize after reset
    WaitForClock(clk_tx, c_nom_bit_time_clk * 5);

    test_reset;
    test_cc_transfer;
    test_fd_transfer;
    test_sp_cadence;
    test_tdc_long_delay;
    test_resync_drift;

    report_results;
    std.env.finish;
    wait;
  end process p_test_ctrl;

end architecture tb;
