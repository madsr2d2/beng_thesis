--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   PCS sub-layer testbench (can_pcs_tx + can_pcs_rx with a
--                dominant-wins bus model, transceiver loopback, and RX
--                propagation delay). Two independent clocks model oscillator
--                drift within ISO 7.3.6 tolerance.
--                  p_tx_mac_vc   - TX MAC source VC (polarity + control bits).
--                  p_rx_mac_vc   - RX MAC VC: owns rx_mac_i, collects SP samples,
--                                  models MAC hard-sync arming, verifies bits.
--                  p_test_ctrl   - Test sequencer.
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
    gc_TbClkPeriod : time := 10 ns;
    gc_TbTimeOut      : time := 500 ms
  );
end entity can_pcs_tb;

architecture tb of can_pcs_tb is

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  -- Bit timing
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
  constant c_nom_bit_time_tq   : natural := c_nom_sync_seg + c_nom_prop_seg + c_nom_phase_seg1 + c_nom_phase_seg2;
  constant c_data_bit_time_tq  : natural := c_data_sync_seg + c_data_prop_seg + c_data_phase_seg1 + c_data_phase_seg2;
  constant c_nom_bit_time_clk  : natural := c_nom_bit_time_tq * c_prescaler;
  constant c_data_bit_time_clk : natural := c_data_bit_time_tq * c_prescaler;
  constant c_clock_tolerance : real :=  real(c_sjw_val) / (20.0 * real(c_nom_bit_time_tq)); -- ISO : 7.3.6, eq. 3

  -- Bus/transceiver delays
  constant c_bus_delay         : time := 200 ns; -- This is the wire propagation delay
  constant c_tx_loopback_delay : time := 400 ns; -- This is the transceiver round-trip delay that TDC must compensate for (ISO : 7.3.4)

  ----------------------------------------------------------------------------
  -- Test parameters
  ----------------------------------------------------------------------------
  constant c_stream_len : natural := 500;
  constant c_fd_nom_len    : natural := 20;
  constant c_fd_data_len   : natural := 40;
  constant c_fd_switchback_len : natural := 15; -- nominal bits after data-phase, verifies data->nominal rate switchback
  constant c_rec_width     : natural := 16;
  constant c_rx_buffer_max : natural := 5000;
  constant c_start_collection_rx_stream : natural := 0;
  constant c_nominel_bit_rate  : std_logic_vector(1 downto 0) := "00"; -- nominal TDC idle
  constant c_tx_start_tdc  : std_logic_vector(1 downto 0) := "01"; -- start TDC
  constant c_tx_data_bit_rate : std_logic_vector(1 downto 0) := "10"; -- data rate
  constant c_rx_data_bit_rate  : std_logic_vector(1 downto 0) := "01"; -- data rate
  constant c_rx_hard_sync : std_logic_vector(1 downto 0) := "10"; -- arm hard_sync

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal clk_tx : std_logic;
  signal clk_rx : std_logic;
  signal reset  : std_logic;

  signal tx_tx_bus : std_logic;                   -- TX PCX tx to bus
  signal rx_tx_bus   : std_logic;                   -- RX PCS tx to bus
  signal bus_level   : std_logic;                   -- wired-AND of both drivers
  signal rx_bus_wire : std_logic := c_recessive;    -- bus seen by RX (delayed)
  signal tx_loopback : std_logic := c_recessive;    -- bus seen by TX (delayed)

  signal tx_mac_i : t_can_mac_pcs_if_m2s := c_mac_to_pcs_if_reset;
  signal tx_mac_o : t_can_mac_pcs_if_s2m;
  signal tx_fce_i : t_can_fce_pcs_if_m2s := c_fce_to_pcs_if_reset;
  signal tx_fce_o : t_can_pcs_fce_if_s2m;

  signal rx_mac_i : t_can_mac_pcs_rx_if_m2s := c_mac_to_pcs_rx_if_reset;
  signal rx_mac_o : t_can_mac_pcs_rx_if_s2m;
  signal rx_fce_i : t_can_fce_pcs_if_m2s := c_fce_to_pcs_if_reset;
  signal rx_fce_o : t_can_pcs_fce_if_s2m;

  shared variable RV : RandomPType;
  signal test_id      : AlertLogIDType;
  signal check_id     : AlertLogIDType;
  signal init_barrier : std_logic := '0';
  signal test_num     : natural := 0;


  ----------------------------------------------------------------------------
  -- Transaction records
  ----------------------------------------------------------------------------
  signal tx_mac_rec : StreamRecType(
    DataToModel    (2 downto 0),
    ParamToModel   (c_rec_width - 1 downto 0),
    DataFromModel  (c_rec_width - 1 downto 0),
    ParamFromModel (c_rec_width - 1 downto 0)
  );

  signal rx_mac_rec : StreamRecType(
    DataToModel    (1 downto 0),
    ParamToModel   (c_rec_width - 1 downto 0),
    DataFromModel  (c_rec_width - 1 downto 0),
    ParamFromModel (c_rec_width - 1 downto 0)
  );

begin

  ----------------------------------------------------------------------------
  -- Infrastructure
  ----------------------------------------------------------------------------
  CreateClock(clk_tx, gc_TbClkPeriod);
  CreateClock(clk_rx, gc_TbClkPeriod*(1.0 + c_clock_tolerance));
  CreateReset(reset, '1', clk_tx, gc_TbClkPeriod * 10);

  p_timeout : process is
  begin
    wait for gc_TbTimeOut;
    assert false report "ERROR TEST FAILED, due to time out" severity error;
    std.env.stop(1);
  end process p_timeout;

  p_init : process is
    variable v_test_id  : AlertLogIDType;
    variable v_check_id : AlertLogIDType;
  begin
    SetAlertStopCount(ERROR, 1);
    v_test_id  := NewID("can_pcs");
    v_check_id := NewID("Bit check", v_test_id);
    RV.InitSeed(RV'instance_name & to_string(now));
    rx_mac_rec.BurstFifo <= NewID("RX Coll Burst fifo");
    test_id  <= v_test_id;
    check_id <= v_check_id;
    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  ----------------------------------------------------------------------------
  -- Bus model
  ----------------------------------------------------------------------------
  bus_level <= tx_tx_bus and rx_tx_bus;
  p_rx_delay : process is
  begin
    wait on bus_level;
    rx_bus_wire <= transport bus_level after c_bus_delay;
  end process p_rx_delay;
  ----------------------------------------------------------------------------

  ----------------------------------------------------------------------------
  -- Transceiver model
  ----------------------------------------------------------------------------
  p_tx_loopback_delay : process is
  begin
    wait on bus_level;
    tx_loopback <= transport bus_level after c_tx_loopback_delay;
  end process p_tx_loopback_delay;

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
      tx_bus_o => tx_tx_bus,
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
      rx_bus_i => rx_bus_wire
    );

  ----------------------------------------------------------------------------
  -- TX MAC VC.
  ----------------------------------------------------------------------------
  p_tx_mac_vc : process is
  begin
    WaitForBarrier(init_barrier);
    tx_mac_i <= c_mac_to_pcs_if_reset;

    tx_mac_vc_loop : loop
      WaitForTransaction(tx_mac_rec.Rdy, tx_mac_rec.Ack);
      case tx_mac_rec.Operation is
        when SEND =>
          wait until tx_mac_o.sample_point = '1';
          tx_mac_i.polarity      <= tx_mac_rec.DataToModel(2);
          tx_mac_i.use_data_rate <= tx_mac_rec.DataToModel(1);
          tx_mac_i.start_tdc     <= tx_mac_rec.DataToModel(0);
        when others => null;
      end case;
    end loop tx_mac_vc_loop;
  end process p_tx_mac_vc;

  ----------------------------------------------------------------------------
  -- RX MAC VC.
  ----------------------------------------------------------------------------
  p_rx_mac_vc : process is
    variable v_rx_bits         : std_logic_vector(0 to c_stream_len);
    variable v_rx_len          : natural := 0;
    variable v_collecting      : boolean := false;
    variable v_sof_seen  : boolean := false;
    variable v_hard_sync_armed : boolean := false;
    variable v_expected        : std_logic_vector(0 downto 0);
  begin
    WaitForBarrier(init_barrier);
    rx_mac_i <= c_mac_to_pcs_rx_if_reset;
    wait until reset = '0';

    rx_mac_loop : loop
      wait until rising_edge(clk_rx);

      ----------------------------------------------------------------------------
      -- Collect bit string received at RC MAC
      ----------------------------------------------------------------------------
      if (v_collecting and rx_mac_o.sample_point = '1') then
        if (not v_sof_seen and rx_mac_o.bus_polarity = c_dominant) then -- Skip until SOF bit is observed
          v_sof_seen := true;
        end if;
        if v_sof_seen then
          v_rx_bits(v_rx_len) := rx_mac_o.bus_polarity;
          v_rx_len            := v_rx_len + 1;
        end if;
      end if;

      -- Lower hard_sync_en at the first dominant sample after arming.
      if (v_hard_sync_armed and rx_mac_o.sample_point = '1' and rx_mac_o.bus_polarity = c_dominant) then
        rx_mac_i.hard_sync_en <= '0';
        v_hard_sync_armed     := false;
      end if;
      ----------------------------------------------------------------------------

      if TransactionPending(rx_mac_rec.Rdy, rx_mac_rec.Ack) then
        case rx_mac_rec.Operation is
          when SET_MODEL_OPTIONS =>
            if rx_mac_rec.Options = c_start_collection_rx_stream then
              v_rx_len         := 0;
              v_sof_seen := false;
              v_collecting     := true;
            end if;

          when SEND =>
            wait until rx_mac_o.sample_point = '1';
            rx_mac_i.hard_sync_en  <= rx_mac_rec.DataToModel(1);
            rx_mac_i.use_data_rate <= rx_mac_rec.DataToModel(0);
            v_hard_sync_armed      := (rx_mac_rec.DataToModel(1) = '1');

          when CHECK_BURST =>
            v_collecting := false;
            for i in 0 to rx_mac_rec.IntToModel - 1 loop
              v_expected(0) := v_rx_bits(i);
              Check(rx_mac_rec.BurstFifo, v_expected);
            end loop;

          when others => null;
        end case;
        FinishTransaction(rx_mac_rec.Ack);
      end if;
    end loop rx_mac_loop;
  end process p_rx_mac_vc;


  ----------------------------------------------------------------------------
  -- p_test_ctrl
  ----------------------------------------------------------------------------
  p_test_ctrl : process is

    --------------------------------------------------------------------------
    -- Test 1: Reset
    --------------------------------------------------------------------------
    procedure test_reset is
    begin
      test_num <= 1;
      Print("--------------------------------------------------------------------------");
      Print("Test 1: Reset defaults");
      Print("--------------------------------------------------------------------------");

      AffirmIf(check_id, tx_tx_bus = c_recessive, "TX PCS -> MAC");
      AffirmIf(check_id, rx_mac_o = c_pcs_to_mac_rx_if_reset, "RX PCS -> MAC");
    end procedure test_reset;

    --------------------------------------------------------------------------
    -- Test 2: CC bitstream transfer.
    --------------------------------------------------------------------------
    procedure test_cc_transfer is
      variable v_pol : std_logic;
    begin
      test_num <= 2;
      Print("--------------------------------------------------------------------------");
      Print("Test 2: CC bitstream transfer");
      Print("--------------------------------------------------------------------------");

      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);

      Send(rx_mac_rec, c_rx_hard_sync);
      SetModelOptions(rx_mac_rec, c_start_collection_rx_stream);

      -- Send SOF bit
      Push(rx_mac_rec.BurstFifo, "" & c_dominant);
      Send(tx_mac_rec, c_dominant & c_nominel_bit_rate);

      for i in 1 to c_stream_len - 1 loop
        v_pol := RV.RandSlv(1)(1);
        Push(rx_mac_rec.BurstFifo, "" & v_pol);
        Send(tx_mac_rec, v_pol & c_nominel_bit_rate);
      end loop;

      WaitForClock(clk_tx, c_nom_bit_time_clk * 2);
      wait for c_bus_delay;
      CheckBurst(rx_mac_rec, GetFifoCount(rx_mac_rec.BurstFifo));

      -- Drive bus recessive before returning so the next test's collector starts from idle
      Send(tx_mac_rec, c_recessive & c_nominel_bit_rate);
      Send(tx_mac_rec, c_recessive & c_nominel_bit_rate);
      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);
    end procedure test_cc_transfer;

    --------------------------------------------------------------------------
    -- Test 3: FD bitstream transfer (nominal + data rate)
    --------------------------------------------------------------------------
    procedure test_fd_transfer is
      variable v_pol : std_logic;
    begin
      test_num <= 3;
      Print("--------------------------------------------------------------------------");
      Print("Test 3: FD bitstream transfer (nominal + data rate)");
      Print("--------------------------------------------------------------------------");

      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);

      -- Sent SOF bit
      Send(rx_mac_rec, c_rx_hard_sync);
      SetModelOptions(rx_mac_rec, c_start_collection_rx_stream);
      Push(rx_mac_rec.BurstFifo, "" & c_dominant);
      Send(tx_mac_rec, c_dominant & c_nominel_bit_rate);

      -- Send nominal bit stream preceding the data field
      for i in 1 to c_fd_nom_len - 1 loop
        v_pol := RV.RandSlv(1)(1);
        Push(rx_mac_rec.BurstFifo, "" & v_pol);
        Send(tx_mac_rec, v_pol & c_nominel_bit_rate);
      end loop;

      -- FDF/res/BRS transition (This starts the data phase ISO : Figure 2)
      Send(rx_mac_rec, c_rx_hard_sync); -- RX PCS should hard sync on FDF -> res bit dominant edge (ISO : 7.3.5.1,c)
      Push(rx_mac_rec.BurstFifo, "" & c_recessive);
      Send(tx_mac_rec, c_recessive & c_tx_start_tdc);      -- FDF bit, start_tdc
      Push(rx_mac_rec.BurstFifo, "" & c_dominant);
      Send(tx_mac_rec, c_dominant  & c_nominel_bit_rate);  -- res bit
      Push(rx_mac_rec.BurstFifo, "" & c_recessive);
      Send(tx_mac_rec, c_recessive & c_nominel_bit_rate);  -- BRS bit

      -- Send Data-rate bits.
      for i in 1 to c_fd_data_len loop
        v_pol := RV.RandSlv(1)(1);
        Push(rx_mac_rec.BurstFifo, "" & v_pol);
        Send(tx_mac_rec, v_pol & c_tx_data_bit_rate);
        if i = 1 then
          Send(rx_mac_rec, c_rx_data_bit_rate);
        end if;
      end loop;

      -- Switch both sides back to nominal. ISO 7.3.5.1: the first rec->dom edge
      -- after the CRC delimiter SP (with TDC in use) shall cause hard sync, so
      -- the RX arms hard_sync here (VC auto-lowers at the next dominant SP).
      -- Collection continues unbroken - this is the bitstream the RX MAC FSM sees.
      Push(rx_mac_rec.BurstFifo, "" & c_recessive);
      Send(tx_mac_rec, c_recessive & c_nominel_bit_rate);
      Send(rx_mac_rec, c_rx_hard_sync);

      for i in 1 to c_fd_switchback_len - 1 loop
        v_pol := RV.RandSlv(1)(1);
        Push(rx_mac_rec.BurstFifo, "" & v_pol);
        Send(tx_mac_rec, v_pol & c_nominel_bit_rate);
      end loop;

      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);
      CheckBurst(rx_mac_rec, GetFifoCount(rx_mac_rec.BurstFifo));

      -- Return to idle and re-arm hard_sync for the next frame's SOF.
      Send(tx_mac_rec, c_recessive & c_nominel_bit_rate);
      Send(tx_mac_rec, c_recessive & c_nominel_bit_rate);
      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);
      Send(rx_mac_rec, c_rx_hard_sync);
    end procedure test_fd_transfer;


    --------------------------------------------------------------------------
    -- Test 4: TDC measurement with long transceiver loopback delay.
    --
    -- Drives SOF -> arb -> FDF/res/BRS and then observes the data phase.
    -- Verifies (a) tdc_delay is non-zero after measuring, (b) SSP respects
    -- the standoff window, (c) SSP fires during data. TDC counts from the
    -- rec->dom edge at the FDF/res boundary (start_tdc='1' on FDF).
    --------------------------------------------------------------------------
    procedure test_tdc_long_delay is
      variable v_ssp_count     : natural := 0;
      variable v_tdc_val       : natural := 0;
      variable v_ssp_standoff  : natural := 0;
      variable v_standoff_done : boolean := false;
    begin
      test_num <= 4;
      Print("--------------------------------------------------------------------------");
      Print("Test 4: TDC measurement with long bus delay");
      Print("--------------------------------------------------------------------------");

      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);

      -- SOF + arb nominal bits to establish bus activity.
      Send(rx_mac_rec, c_rx_hard_sync);
      Send(tx_mac_rec, c_dominant & c_nominel_bit_rate); -- SOF
      for i in 1 to 5 loop
        Send(tx_mac_rec, c_recessive & c_nominel_bit_rate);
      end loop;

      -- FDF/res/BRS transition. The start_tdc='1' Send drives res=dominant;
      -- the rec->dom edge at the FDF/res boundary seeds TDC counting.
      Send(rx_mac_rec, c_rx_hard_sync);
      Send(tx_mac_rec, c_dominant  & c_tx_start_tdc);   -- FDF, start_tdc
      Send(tx_mac_rec, c_recessive & c_nominel_bit_rate);   -- res
      Send(tx_mac_rec, c_dominant  & c_tx_data_bit_rate);  -- BRS, switch to data rate

      -- Observe through transition + data phase (2 nom + 10 data bit times).
      for i in 1 to c_nom_bit_time_clk * 2 + c_data_bit_time_clk * 10 loop
        wait until rising_edge(clk_tx);

        if (v_tdc_val = 0 and unsigned(tx_mac_o.tdc_delay) > 0) then
          v_tdc_val := to_integer(unsigned(tx_mac_o.tdc_delay));
        end if;

        if tx_mac_o.secondary_sample_point = '1' then
          v_ssp_count := v_ssp_count + 1;
          if not v_standoff_done then
            v_standoff_done := true;
            v_ssp_standoff  := i;
          end if;
        end if;
      end loop;

      Print("  TDC delay value: " & to_string(v_tdc_val));
      Print("  SSP first fired at observation clock: " & to_string(v_ssp_standoff));
      Print("  SSP pulses observed: " & to_string(v_ssp_count));

      AffirmIf(check_id, v_tdc_val > 0,
        "TDC delay must be > 0 with " & time'image(c_tx_loopback_delay) &
        " loopback delay, got " & to_string(v_tdc_val));

      -- Standoff lower bound: observation starts ~1 nominal bit before s_data,
      -- so the first SSP must follow tdc_delay data bit times at minimum.
      AffirmIf(check_id, v_ssp_standoff > v_tdc_val * c_data_bit_time_clk,
        "SSP must respect standoff of " & to_string(v_tdc_val) & " data bit times (" &
        to_string(v_tdc_val * c_data_bit_time_clk) & " clks), first SSP at obs clk " &
        to_string(v_ssp_standoff));

      AffirmIf(check_id, v_ssp_count > 0,
        "SSP must fire at least once after standoff, got " &
        to_string(v_ssp_count) & " pulses");

      -- Return to idle at nominal rate.
      Send(tx_mac_rec, c_recessive & c_nominel_bit_rate);
      Send(tx_mac_rec, c_recessive & c_nominel_bit_rate);
      Send(tx_mac_rec, c_recessive & c_nominel_bit_rate);
      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);
    end procedure test_tdc_long_delay;

    --------------------------------------------------------------------------
    -- Test 5: Resynchronization under oscillator drift (ISO 7.3.5.4).
    --
    -- TX and RX run on slightly different clocks (~0.09% drift, within the
    -- ISO 7.3.6 tolerance). The pattern stresses resync with groups of 5
    -- dominant + 1 recessive bits so a rec->dom edge appears every 6 bits.
    --------------------------------------------------------------------------
    procedure test_resync_drift is
      constant c_group_len  : natural := 5;
      constant c_num_groups : natural := 25;
    begin
      test_num <= 5;
      Print("--------------------------------------------------------------------------");
      Print("Test 5: Resynchronization under oscillator drift (ISO 7.3.5.4)");
      Print("--------------------------------------------------------------------------");

      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);

      -- Arm hard_sync for SOF; VC auto-lowers at SP so the rest of the frame
      -- runs in resync mode (ISO 7.3.5.1 rule d).
      Send(rx_mac_rec, c_rx_hard_sync);
      SetModelOptions(rx_mac_rec, c_start_collection_rx_stream);

      -- SOF.
      Push(rx_mac_rec.BurstFifo, "" & c_dominant);
      Send(tx_mac_rec, c_dominant & c_nominel_bit_rate);

      -- 5 dominant (drift accumulates) + 1 recessive (edge triggers resync).
      for g in 0 to c_num_groups - 1 loop
        for i in 0 to c_group_len - 1 loop
          Push(rx_mac_rec.BurstFifo, "" & c_dominant);
          Send(tx_mac_rec, c_dominant & c_nominel_bit_rate);
        end loop;
        Push(rx_mac_rec.BurstFifo, "" & c_recessive);
        Send(tx_mac_rec, c_recessive & c_nominel_bit_rate);
      end loop;

      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);
      CheckBurst(rx_mac_rec, GetFifoCount(rx_mac_rec.BurstFifo));

      Send(rx_mac_rec, c_rx_hard_sync);
    end procedure test_resync_drift;

    --------------------------------------------------------------------------
    -- Test 6: Bus-off. Both MAC polarities held dominant. Bus should stay
    -- recessive. Pulse idle_condition on 11 recessive SP samples (ISO 6.6.7.5).
    --------------------------------------------------------------------------
    procedure test_bus_off is
      variable v_tx_idle : natural := 0;
      variable v_rx_idle : natural := 0;
      variable v_bus_dom : boolean := false;
    begin
      test_num <= 6;
      Print("--------------------------------------------------------------------------");
      Print("Test 6: Bus-off idle condition (TX + RX PCS)");
      Print("--------------------------------------------------------------------------");

      Send(tx_mac_rec, c_dominant & c_nominel_bit_rate);
      rx_mac_i.polarity <= c_dominant;
      tx_fce_i.bus_off  <= '1';
      rx_fce_i.bus_off  <= '1';
      WaitForClock(clk_tx, c_nom_bit_time_clk * 2);

      for i in 1 to c_nom_bit_time_clk * 15 loop
        wait until rising_edge(clk_tx);
        if tx_fce_o.idle_condition = '1' then v_tx_idle := v_tx_idle + 1; end if;
        if rx_fce_o.idle_condition = '1' then v_rx_idle := v_rx_idle + 1; end if;
        if bus_level = c_dominant then v_bus_dom := true; end if;
      end loop;

      AffirmIf(check_id, not v_bus_dom, "Bus must stay recessive with both PCS in bus_off");
      AffirmIf(check_id, v_tx_idle >= 1, "TX PCS idle_condition must pulse, got " & to_string(v_tx_idle));
      AffirmIf(check_id, v_rx_idle >= 1, "RX PCS idle_condition must pulse, got " & to_string(v_rx_idle));

      tx_fce_i.bus_off  <= '0';
      rx_fce_i.bus_off  <= '0';
      rx_mac_i.polarity <= c_recessive;
      WaitForClock(clk_tx, c_nom_bit_time_clk * 3);
    end procedure test_bus_off;

    --------------------------------------------------------------------------
    procedure report_results is
    begin
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
    test_tdc_long_delay;
    test_resync_drift;
    test_bus_off;

    report_results;
    std.env.finish;
    wait;
  end process p_test_ctrl;

end architecture tb;
