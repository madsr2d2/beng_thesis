--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_pcs. Instantiates two can_pcs units (TX and RX) with
--                independent out-of-sync clocks to exercise resynchronization. A physical
--                bus model with separate transceiver TX/RX delays and wire propagation delay
--                using ISO 11898-1 sec. 7.3.2 constraints is used to exercise TDC.
--                Three test sequences are run.
--
--                  p_polarity_history  - TX shift register shadow: tracks bits committed to
--                                        the bus at drive_bit time for TDC checking.
--                  p_check_tdc_delay   - SSP monitor: at each Secondary Sample Point verifies
--                                        polarity_history(tdc_delay) = rx_data (ISO 7.3.4).
--                  p_rx_mac_vc         - Bit-level RX sink VC: detects SOF, collects bus bits
--                                        at each RX sample point, and compares against TX sequence.
--                  p_test_ctrl         - Test sequencer: reset check, random FD frame drive with
--                                        clock-rate alternation, and bus-off idle verification.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-04-16  TMYAES:   [TRIT-4336] [FPGA] CAN FD extensions of TRIT-3880
--                2026-04-27  MRDSA:    Local mirror of company can_pcs_tb.
--
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
    gc_TbTimeOut   : time := 500 ms
  );
end entity can_pcs_tb;

architecture tb of can_pcs_tb is

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  -- Bit timing --------------------------------------------------------------
  constant c_nom_prop_seg    : natural := 40;
  constant c_nom_phase_seg1  : natural := 39;
  constant c_nom_phase_seg2  : natural := 20;
  constant c_sjw             : natural := 4;
  constant c_nom_bit_time_tq : natural := 1 + c_nom_prop_seg + c_nom_phase_seg1 + c_nom_phase_seg2;
  constant c_clock_tolerance : real    := real(c_sjw) / (20.0 * real(c_nom_bit_time_tq)); -- ISO 7.3.6 eq. 3
  constant c_nom_half_period : time    := gc_TbClkPeriod / 2;
  constant c_slow_half_period : time   := (gc_TbClkPeriod / 2) * (1.0 + 2.0 * c_clock_tolerance);

  -- Bus/transceiver delays --------------------------------------------------
  -- ISO 7.3.2 arbitration constraint:
  --   t_prop_seg >= 4 x transceiver_d + 2 x bus_d
  -- c_nom_prop_seg x prescaler x gc_TbClkPeriod = 40 x 2 x 10 ns = 800 ns.
  -- Budget fully consumed: 4 x 50 ns + 2 x 300 ns = 800 ns.
  constant c_nom_prop_seg_time : time := 800 ns;
  constant c_transceiver_d     : time := 50 ns;
  constant c_bus_delay_max     : time := (c_nom_prop_seg_time - 4 * c_transceiver_d) / 2;

  -- Frame structure ---------------------------------------------------------
  constant c_frames_to_send      : natural := 100;
  constant c_res_bit_index       : natural := 50;
  constant c_crc_delimiter_index : natural := c_res_bit_index + 1 + (64 * 8);  -- max data length

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal tx_clock_is_leading : boolean   := true;

  signal clk_tx : std_logic := '0';
  signal clk_rx : std_logic := '0';
  signal reset  : std_logic;

  -- DUT bus interfaces ------------------------------------------------------
  signal tx_dut_tx : std_logic;                           -- TX PCS output to bus
  signal rx_dut_tx : std_logic;                           -- RX PCS output to bus
  signal tx_dut_rx : std_logic := c_recessive;            -- bus seen by TX DUT (after delays)
  signal rx_dut_rx : std_logic := c_recessive;            -- bus seen by RX DUT (after delays)

  -- DUT interfaces ----------------------------------------------------------
  signal tx_mac_i : t_can_mac_pcs_if_m2s := c_mac_to_pcs_if_reset;
  signal tx_mac_o : t_can_mac_pcs_if_s2m;
  signal tx_fce_i : t_can_fce_pcs_if_m2s := c_fce_to_pcs_if_reset;
  signal tx_fce_o : t_can_pcs_fce_if_s2m;
  signal rx_mac_i : t_can_mac_pcs_if_m2s := c_mac_to_pcs_if_reset;
  signal rx_mac_o : t_can_mac_pcs_if_s2m;
  signal rx_fce_i : t_can_fce_pcs_if_m2s := c_fce_to_pcs_if_reset;
  signal rx_fce_o : t_can_pcs_fce_if_s2m;

  -- TB infrastructure -------------------------------------------------------
  shared variable RV           : RandomPType;
  signal          test_id      : AlertLogIDType;
  signal          check_id     : AlertLogIDType;
  signal          init_barrier : integer_barrier := 1;
  signal          test_num     : natural;
  signal polarity_history : std_logic_vector(8 - 1 downto 0) := (others => c_recessive);

  -- Bus signals -------------------------------------------------------------
  signal tx_dut_wire     : std_logic := c_recessive;      -- TX DUT TX after transceiver delay
  signal rx_dut_wire     : std_logic := c_recessive;      -- RX DUT TX after transceiver delay
  signal tx_dut_wire_far : std_logic := c_recessive;      -- TX DUT wire propagated to RX end
  signal rx_dut_wire_far : std_logic := c_recessive;      -- RX DUT wire propagated to TX end
  signal bus_tx_dut      : std_logic := c_recessive;      -- wired-AND at TX DUT
  signal bus_rx_dut      : std_logic := c_recessive;      -- wired-AND at RX DUT
  signal bus_level       : std_logic;

  -- Transaction records -----------------------------------------------------
  signal tx_mac_rec : StreamRecType(DataToModel(4 downto 0), ParamToModel(0 downto 0), DataFromModel(0 downto 0), ParamFromModel(0 downto 0));
  signal rx_mac_rec : StreamRecType(DataToModel(4 downto 0), ParamToModel(0 downto 0), DataFromModel(0 downto 0), ParamFromModel(0 downto 0));

begin

  ----------------------------------------------------------------------------
  -- Infrastructure
  ----------------------------------------------------------------------------
  clk_tx <= not clk_tx after c_nom_half_period  when tx_clock_is_leading else not clk_tx after c_slow_half_period;
  clk_rx <= not clk_rx after c_slow_half_period when tx_clock_is_leading else not clk_rx after c_nom_half_period;
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
    SetLogEnable(DEBUG, false);
    v_test_id  := NewID("can_pcs");
    v_check_id := NewID("Bit check", v_test_id);
    RV.InitSeed(RV'instance_name & to_string(now));
    rx_mac_rec.BurstFifo <= NewID("rx fifo");
    tx_mac_rec.BurstFifo <= NewID("tx fifo");
    test_id  <= v_test_id;
    check_id <= v_check_id;
    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  ----------------------------------------------------------------------------
  -- DUT: TX PCS
  ----------------------------------------------------------------------------
  u_pcs_tx : entity work.can_pcs
    port map (
      clk_i => clk_tx,
      reset_i => reset,
      mac_i => tx_mac_i,
      mac_o => tx_mac_o,
      fce_i => tx_fce_i,
      fce_o => tx_fce_o,
      tx_o  => tx_dut_tx,
      rx_i  => tx_dut_rx
    );

  ----------------------------------------------------------------------------
  -- DUT: RX PCS
  ----------------------------------------------------------------------------
  u_pcs_rx : entity work.can_pcs
    port map (
      clk_i => clk_rx,
      reset_i => reset,
      mac_i => rx_mac_i,
      mac_o => rx_mac_o,
      fce_i => rx_fce_i,
      fce_o => rx_fce_o,
      tx_o  => rx_dut_tx,
      rx_i  => rx_dut_rx
    );

  ----------------------------------------------------------------------------
  -- Bus model: dominant-wins wired-AND with transceiver and propagation delays.
  --
  --  tx_dut_tx -[c_transceiver_d]-> tx_dut_wire -[c_bus_delay_max]-> tx_dut_wire_far
  --  rx_dut_tx -[c_transceiver_d]-> rx_dut_wire -[c_bus_delay_max]-> rx_dut_wire_far
  --
  --  bus_tx_dut = tx_dut_wire AND rx_dut_wire_far
  --  bus_rx_dut = tx_dut_wire_far AND rx_dut_wire
  --
  --  tx_dut_rx <-[c_transceiver_d]- bus_tx_dut
  --  rx_dut_rx <-[c_transceiver_d]- bus_rx_dut
  ----------------------------------------------------------------------------
  bus_tx_dut <= tx_dut_wire and rx_dut_wire_far;
  bus_rx_dut <= tx_dut_wire_far and rx_dut_wire;

  p_tx_dut_tx_to_wire : process is
  begin
    wait on tx_dut_tx;
    tx_dut_wire <= transport tx_dut_tx after c_transceiver_d;
  end process;

  p_tx_dut_rx_from_bus : process is
  begin
    wait on bus_tx_dut;
    tx_dut_rx <= transport bus_tx_dut after c_transceiver_d;
  end process;

  p_rx_dut_tx_to_wire : process is
  begin
    wait on rx_dut_tx;
    rx_dut_wire <= transport rx_dut_tx after c_transceiver_d;
  end process;

  p_rx_dut_rx_from_bus : process is
  begin
    wait on bus_rx_dut;
    rx_dut_rx <= transport bus_rx_dut after c_transceiver_d;
  end process;

  p_propagate_tx_to_rx : process is
  begin
    wait on tx_dut_wire;
    tx_dut_wire_far <= transport tx_dut_wire after c_bus_delay_max;
  end process;

  p_propagate_rx_to_tx : process is
  begin
    wait on rx_dut_wire;
    rx_dut_wire_far <= transport rx_dut_wire after c_bus_delay_max;
  end process;

  -- bus_level: physical bus level used by test_bus_off
  bus_level <= bus_tx_dut;

  ----------------------------------------------------------------------------
  -- Track transmitted bits for Transmitter Delay Compensation (TDC) verification (ISO 7.3.4).
  ----------------------------------------------------------------------------
  p_polarity_history : process is
    variable v_in_data_phase : boolean := false;
  begin
    WaitForBarrier(init_barrier);
    wait until reset = '0';

    polarity_history_loop : loop
      wait until rising_edge(tx_mac_o.sample_point);
      WaitForClock(clk_tx, 2);                          -- align with drive_bit (SP + 2 clk) from the MAC FSM
      if tx_mac_i.next_bit_is_brs = '1' then
        polarity_history <= (0 => tx_mac_i.tx_data, others => c_recessive);
        v_in_data_phase  := true;
      elsif v_in_data_phase then
        polarity_history <= polarity_history(polarity_history'high - 1 downto 0) & tx_mac_i.tx_data;
        if tx_mac_i.data_phase_stop = '1' then
          v_in_data_phase := false;
        end if;
      end if;
    end loop polarity_history_loop;
  end process p_polarity_history;

  ----------------------------------------------------------------------------
  -- Verify TDC delay: at each SSP polarity_history(tdc_delay) must equal rx_data.
  ----------------------------------------------------------------------------
  p_check_tdc_delay : process is
    variable v_index : natural := 0;
  begin
    WaitForBarrier(init_barrier);
    wait until reset = '0';

    tdc_delay_check_loop : loop
      wait until rising_edge(tx_mac_o.secondary_sample_point);
      v_index := to_integer(unsigned(tx_mac_o.tdc_delay));
      AffirmIf(check_id, polarity_history(v_index) = tx_mac_o.rx_data,"pol_hist: " & to_string(polarity_history(v_index)) & " rx_data: " & to_string(tx_mac_o.rx_data));
    end loop tdc_delay_check_loop;
  end process p_check_tdc_delay;

  ----------------------------------------------------------------------------
  -- RX MAC sink VC: detects SOF, collects bus bits at each RX sample point,
  -- and on a CHECK transaction compares the collected bit stream against the
  -- TX sequence pushed by the test controller.
  ----------------------------------------------------------------------------
  p_rx_mac_vc : process is
    variable v_rx_bit       : std_logic;
    variable v_tx_bit       : std_logic;
    variable v_bit_index    : integer;
    variable v_sof_detected : boolean := false;
  begin
    rx_mac_i.do_hard_sync <= '1';
    v_sof_detected        := false;
    WaitForBarrier(init_barrier);
    wait until reset = '0';

    rx_mac_loop : loop
      wait until rising_edge(rx_mac_o.sample_point);

      -- Collect bit stream after SOF detection
      if v_sof_detected then
        v_bit_index := v_bit_index + 1;
        Push(rx_mac_rec.BurstFifo, "" & rx_mac_o.rx_data);
      end if;

      -- SOF detection: first dominant SP while do_hard_sync = '1'
      if (not v_sof_detected) and (rx_mac_i.do_hard_sync = '1') and (rx_mac_o.rx_data = c_dominant) then
        v_sof_detected        := true;
        rx_mac_i.do_hard_sync <= '0' after 2 * gc_TbClkPeriod;
        v_bit_index           := 0;
        Push(rx_mac_rec.BurstFifo, "" & rx_mac_o.rx_data);
      end if;

      -- Minimal RX MAC model: arm hard sync at FDF, switch to data rate at BRS
      if v_bit_index = c_res_bit_index - 1 then
        rx_mac_i.do_hard_sync    <= '1' after 2 * gc_TbClkPeriod;
      elsif v_bit_index = c_res_bit_index then
        rx_mac_i.do_hard_sync    <= '0' after 2 * gc_TbClkPeriod;
        rx_mac_i.next_bit_is_brs <= '1' after 2 * gc_TbClkPeriod;
      elsif v_bit_index = c_res_bit_index + 1 then
        rx_mac_i.next_bit_is_brs <= '0' after 2 * gc_TbClkPeriod;
      elsif v_bit_index = c_crc_delimiter_index - 1 then
        rx_mac_i.data_phase_stop <= '1' after 2 * gc_TbClkPeriod;
      elsif v_bit_index = c_crc_delimiter_index then
        rx_mac_i.data_phase_stop <= '0' after 2 * gc_TbClkPeriod;
      end if;

      -- Transaction dispatcher
      if TransactionPending(rx_mac_rec.Rdy, rx_mac_rec.Ack) then
        case rx_mac_rec.Operation is
          when CHECK =>
            FinishTransaction(rx_mac_rec.Ack);
            v_bit_index := 0;
            while not Empty(tx_mac_rec.BurstFifo) and not Empty(rx_mac_rec.BurstFifo) loop
              v_rx_bit    := Pop(rx_mac_rec.BurstFifo)(0);
              v_tx_bit    := Pop(tx_mac_rec.BurstFifo)(0);
              AffirmIf(check_id, v_rx_bit = v_tx_bit, "bit " & to_string(v_bit_index) & " RX: " & to_string(v_rx_bit) & " TX: " & to_string(v_tx_bit));
              v_bit_index := v_bit_index + 1;
            end loop;
            while not Empty(rx_mac_rec.BurstFifo) loop
              v_rx_bit := Pop(rx_mac_rec.BurstFifo)(0);
            end loop;
            while not Empty(tx_mac_rec.BurstFifo) loop
              v_tx_bit := Pop(tx_mac_rec.BurstFifo)(0);
            end loop;
            v_sof_detected        := false;
            v_bit_index           := -1;
            rx_mac_i.do_hard_sync <= '1' after 2 * gc_TbClkPeriod;
          when others => null;
        end case;
      end if;

    end loop rx_mac_loop;
  end process p_rx_mac_vc;

  ----------------------------------------------------------------------------
  -- p_test_ctrl
  ----------------------------------------------------------------------------
  p_test_ctrl : process is

    --------------------------------------------------------------------------
    -- Test 1: Reset defaults.
    --------------------------------------------------------------------------
    procedure test_reset is
    begin
      test_num <= 1;
      Print("--------------------------------------------------------------------------");
      Print("Test 1: Reset defaults");
      Print("--------------------------------------------------------------------------");
      AffirmIf(check_id, tx_dut_tx = c_recessive, "TX PCS -> bus");
      AffirmIf(check_id, rx_mac_o = c_pcs_to_mac_if_reset, "RX PCS -> MAC");
    end procedure test_reset;

    --------------------------------------------------------------------------
    -- Test 2: Drive random FD frames. TX and RX clocks alternate which leads
    -- each frame iteration to stress resynchronization.
    --------------------------------------------------------------------------
    procedure test_normal is
      variable v_pol : std_logic;
    begin
      test_num <= 2;
      Print("--------------------------------------------------------------------------");
      Print("Test 2: Drive random frames (CC and FD)");
      Print("--------------------------------------------------------------------------");
      tx_mac_i.transmitting <= '1';
      rx_mac_i.transmitting <= '0';

      for frame_iter in 1 to c_frames_to_send loop
        tx_clock_is_leading      <= not tx_clock_is_leading;
        tx_mac_i.next_bit_is_res <= '0';
        tx_mac_i.next_bit_is_brs <= '0';

        for i in 0 to c_crc_delimiter_index + 1 loop
          wait until rising_edge(tx_mac_o.sample_point);
          if i = 0 then
            Push(tx_mac_rec.BurstFifo, "" & c_dominant);
            tx_mac_i.tx_data <= c_dominant after 2 * gc_TbClkPeriod;
          elsif i = c_res_bit_index - 1 then
            Push(tx_mac_rec.BurstFifo, "" & c_recessive);
            tx_mac_i.tx_data <= c_recessive after 2 * gc_TbClkPeriod;
          elsif i = c_res_bit_index then
            Push(tx_mac_rec.BurstFifo, "" & c_dominant);
            tx_mac_i.tx_data         <= c_dominant after 2 * gc_TbClkPeriod;
            tx_mac_i.next_bit_is_res <= '1' after 2 * gc_TbClkPeriod;
          elsif i = c_res_bit_index + 1 then
            v_pol                    := RV.RandSlv(1)(1);
            Push(tx_mac_rec.BurstFifo, "" & v_pol);
            tx_mac_i.tx_data         <= v_pol after 2 * gc_TbClkPeriod;
            tx_mac_i.next_bit_is_res <= '0' after 2 * gc_TbClkPeriod;
            tx_mac_i.next_bit_is_brs <= '1' after 2 * gc_TbClkPeriod;
          elsif i = c_crc_delimiter_index then
            Push(tx_mac_rec.BurstFifo, "" & c_recessive);
            tx_mac_i.tx_data         <= c_recessive after 2 * gc_TbClkPeriod;
            tx_mac_i.data_phase_stop <= '1' after 2 * gc_TbClkPeriod;
          else
            v_pol                    := RV.RandSlv(1)(1);
            Push(tx_mac_rec.BurstFifo, "" & v_pol);
            tx_mac_i.tx_data         <= v_pol after 2 * gc_TbClkPeriod;
            tx_mac_i.next_bit_is_brs <= '0' after 2 * gc_TbClkPeriod;
            tx_mac_i.data_phase_stop <= '0' after 2 * gc_TbClkPeriod;
          end if;
        end loop;

        -- Drive a final bit and wait for it to land at RX before checking
        wait until rising_edge(tx_mac_o.sample_point);
        Push(tx_mac_rec.BurstFifo, "" & c_recessive);
        tx_mac_i.tx_data <= c_recessive after 2 * gc_TbClkPeriod;
        wait until rising_edge(rx_mac_o.sample_point);
        Check(rx_mac_rec, "");

        -- Inter-frame space
        for i in 1 to 5 loop
          wait until rising_edge(tx_mac_o.sample_point);
        end loop;
      end loop;
    end procedure test_normal;

    --------------------------------------------------------------------------
    -- Test 3: Bus-off idle condition. Both PCS units are put into bus_off and
    -- the test verifies no dominant pulses appear and idle_condition strobes fire.
    --------------------------------------------------------------------------
    procedure test_bus_off is
      variable v_tx_idle : natural := 0;
      variable v_rx_idle : natural := 0;
      variable v_bus_dom : boolean := false;
    begin
      test_num <= 3;
      Print("--------------------------------------------------------------------------");
      Print("Test 3: Bus-off idle condition (TX + RX PCS)");
      Print("--------------------------------------------------------------------------");
      tx_fce_i.bus_off <= '1';
      rx_fce_i.bus_off <= '1';

      for i in 1 to c_nom_bit_time_tq * 2 * 11 * 3 loop
        wait until rising_edge(clk_tx);
        v_rx_idle := v_rx_idle + 1 when rx_fce_o.idle_condition = '1' else v_rx_idle;
        v_tx_idle := v_tx_idle + 1 when tx_fce_o.idle_condition = '1' else v_tx_idle;
        v_bus_dom := true when bus_level = c_dominant else v_bus_dom;
      end loop;

      AffirmIf(check_id, not v_bus_dom, "Bus must stay recessive when PCS in bus_off");
      AffirmIf(check_id, v_tx_idle >= 1, "TX PCS idle_condition must pulse");
      AffirmIf(check_id, v_rx_idle >= 1, "RX PCS idle_condition must pulse");
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

    test_reset;
    test_normal;
    test_bus_off;

    report_results;
    std.env.finish;
    wait;
  end process p_test_ctrl;

end architecture tb;
