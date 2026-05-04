--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:   Test bench for the can_pcs module. Instantiates two can_pcs
--                units (TX and RX) with independent out-of-sync clocks to
--                exercise resynchronization. A physical bus model with separate
--                transceiver TX/RX delays and wire propagation delay is used to
--                exercise TDC. Three test sequences are run:
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-04-16  TMYAES:   [TRIT-4336] [FPGA] CAN FD extensions of TRIT-3880
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
  generic(
    gc_TbClkPeriod : time := 10 ns;
    gc_TbTimeOut   : time := 500 ms
  );
end entity can_pcs_tb;

architecture tb of can_pcs_tb is

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  -- Bit timing --------------------------------------------------------------
  constant c_nom_prop_seg     : natural := 40;
  constant c_nom_phase_seg1   : natural := 39;
  constant c_nom_phase_seg2   : natural := 20;
  constant c_sjw              : natural := 4;
  constant c_nom_bit_time_tq  : natural := 1 + c_nom_prop_seg + c_nom_phase_seg1 + c_nom_phase_seg2; -- Nominal bit time in TQs
  constant c_clock_tolerance  : real    := real(c_sjw) / (20.0 * real(c_nom_bit_time_tq)); -- ISO 7.3.6 eq. 3
  constant c_nom_half_period  : time    := gc_TbClkPeriod / 2;
  constant c_slow_half_period : time    := (gc_TbClkPeriod / 2) * (1.0 + 2.0 * c_clock_tolerance);

  -- Bus/transceiver delays --------------------------------------------------
  constant c_bus_delay_max        : time := 150 ns;
  constant c_transceiver_tx_delay : time := 300 ns;
  constant c_transceiver_rx_delay : time := 300 ns;

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal res_bit_index       : natural   := 50;
  signal frames_to_send      : natural   := 100;
  signal crc_delimiter_index : natural   := res_bit_index + 1 + (64 * 8);       -- Max data length
  signal tx_clock_is_leading : std_logic := '1';

  signal clk_tx : std_logic := '0';
  signal clk_rx : std_logic := '0';
  signal reset  : std_logic;

  -- DUT bus interfaces ------------------------------------------------------
  signal tx_from_tx_dut : std_logic;                                            -- TX PCX tx to bus
  signal tx_from_rx_dut : std_logic;                                            -- RX PCS tx to bus
  signal rx_at_rx_dut   : std_logic := c_recessive;                             -- bus seen by RX (delayed)
  signal rx_at_tx_dut   : std_logic := c_recessive;                             -- bus seen by TX (delayed)

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
  shared variable RV               : RandomPType;
  signal          test_id          : AlertLogIDType;
  signal          check_id         : AlertLogIDType;
  signal          init_barrier     : std_logic                        := '0';
  signal          polarity_history : std_logic_vector(8 - 1 downto 0) := (others => c_recessive); -- Holds the bits transmitted by the TX PCS

  -- Bus signals ------------------------------------------------------------
  signal tx_on_bus_at_tx : std_logic := c_recessive;
  signal tx_on_bus_at_rx : std_logic := c_recessive;
  signal rx_on_bus_at_rx : std_logic := c_recessive;
  signal rx_on_bus_at_tx : std_logic := c_recessive;
  signal bus_at_tx       : std_logic := c_recessive;
  signal bus_at_rx       : std_logic := c_recessive;
  signal bus_level       : std_logic;

  -- Transaction records -----------------------------------------------------
  signal tx_mac_rec : StreamRecType(DataToModel(4 downto 0), ParamToModel(0 downto 0), DataFromModel(0 downto 0), ParamFromModel(0 downto 0));
  signal rx_mac_rec : StreamRecType(DataToModel(4 downto 0), ParamToModel(0 downto 0), DataFromModel(0 downto 0), ParamFromModel(0 downto 0));
begin
  ----------------------------------------------------------------------------
  -- Infrastructure
  ----------------------------------------------------------------------------
  -- Clock and reset
  clk_tx <= not clk_tx after c_nom_half_period when tx_clock_is_leading else not clk_tx after c_slow_half_period;
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
    SetAlertStopCount(ERROR, 5);
    v_test_id            := NewID("can_pcs");
    v_check_id           := NewID("Bit check", v_test_id);
    RV.InitSeed(RV'instance_name & to_string(now));
    rx_mac_rec.BurstFifo <= NewID("rx fifo");
    tx_mac_rec.BurstFifo <= NewID("tx fifo");
    test_id              <= v_test_id;
    check_id             <= v_check_id;
    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  ----------------------------------------------------------------------------
  -- DUT: TX PCS 
  ----------------------------------------------------------------------------
  u_pcs_tx : entity work.can_pcs
    port map(
      clk_i => clk_tx,
      rst_i => reset,
      mac_i => tx_mac_i,
      mac_o => tx_mac_o,
      fce_i => tx_fce_i,
      fce_o => tx_fce_o,
      tx_o  => tx_from_tx_dut,
      rx_i  => rx_at_tx_dut
    );
  ----------------------------------------------------------------------------
  -- DUT: RX PCS
  ----------------------------------------------------------------------------
  u_pcs_rx : entity work.can_pcs
    port map(
      clk_i => clk_rx,
      rst_i => reset,
      mac_i => rx_mac_i,
      mac_o => rx_mac_o,
      fce_i => rx_fce_i,
      fce_o => rx_fce_o,
      tx_o  => tx_from_rx_dut,
      rx_i  => rx_at_rx_dut
    );

  ----------------------------------------------------------------------------
  -- Bus model 
  ----------------------------------------------------------------------------
  -- Bus at TX DUT -----------------------------------------------------------
  bus_at_tx <= tx_on_bus_at_tx and rx_on_bus_at_tx;                             -- Bus value at TX-DUT

  p_tx_onto_bus : process is                                                    -- TX -> bus (at the TX-DUT end of the bus)
  begin
    wait on tx_from_tx_dut;
    tx_on_bus_at_tx <= transport tx_from_tx_dut after c_transceiver_tx_delay;
  end process;

  p_tx_loopback : process is                                                    -- bus -> RX (at TX-DUT end of the bus)
  begin
    wait on bus_at_tx;
    rx_at_tx_dut <= transport bus_at_tx after c_transceiver_rx_delay;
  end process;
  ----------------------------------------------------------------------------
  -- Bus at RX DUT -----------------------------------------------------------
  bus_at_rx <= tx_on_bus_at_rx and rx_on_bus_at_rx;

  p_rx_onto_wire : process is                                                   -- TX -> bus (at the RX-DUT end of the bus)
  begin
    wait on tx_from_rx_dut;
    rx_on_bus_at_rx <= transport tx_from_rx_dut after c_transceiver_tx_delay;
  end process;

  p_rx_sees_bus : process is                                                    -- bus -> RX (at RX-DUT end of the bus)
  begin
    wait on bus_at_rx;
    rx_at_rx_dut <= transport bus_at_rx after c_transceiver_rx_delay;
  end process;
  ----------------------------------------------------------------------------
  -- Bus propagation delay ---------------------------------------------------
  p_tx_propagate : process is                                                   -- TX-DUT -> RX-DUT propagation
  begin
    wait on tx_on_bus_at_tx;
    tx_on_bus_at_rx <= transport tx_on_bus_at_tx after c_bus_delay_max;
  end process;

  p_rx_propagate : process is                                                   -- RX-DUT -> TX-DUT propagation
  begin
    wait on rx_on_bus_at_rx;
    rx_on_bus_at_tx <= transport rx_on_bus_at_rx after c_bus_delay_max;
  end process;
  ----------------------------------------------------------------------------

  ----------------------------------------------------------------------------
  -- Track transmitted bits for Transmitter Delay Compensation (TDC) verification (IOS : 7.3.4)
  ----------------------------------------------------------------------------
  p_polarity_history : process is
  begin
    WaitForBarrier(init_barrier);
    wait until reset = '0';

    polarity_history_loop : loop
      wait until rising_edge(tx_mac_o.sample_point);
      polarity_history <= polarity_history(polarity_history'high - 1 downto 0) & tx_mac_i.tx_data;
    end loop polarity_history_loop;
  end process p_polarity_history;

  ----------------------------------------------------------------------------
  -- Process checking the tdc_delay.
  ----------------------------------------------------------------------------
  p_check_tdc_delay : process is
    variable v_index : natural := 0;
  begin
    WaitForBarrier(init_barrier);
    wait until reset = '0';

    tdc_delay_check_loop : loop
      wait until rising_edge(tx_mac_o.secondary_sample_point);
      v_index := to_integer(unsigned(tx_mac_o.tdc_delay));
      AffirmIf(check_id, polarity_history(v_index) = tx_mac_o.rx_data, "index: " & to_string(v_index) & " pol_hist: " & to_string(polarity_history(v_index)) & " rx_data: " & to_string(tx_mac_o.rx_data));
    end loop tdc_delay_check_loop;
  end process p_check_tdc_delay;

  ----------------------------------------------------------------------------
  -- RX MAC VC
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

      -- Start collecting bit stream from RX after the SOF bit has been detected 
      if v_sof_detected then
        v_bit_index := v_bit_index + 1;
        -- rx_bit_index <= v_wire_idx;
        Push(rx_mac_rec.BurstFifo, "" & rx_mac_o.rx_data);
      end if;

      -- SOF detection: first dominant SP while do_hard_sync = '1' ---------------
      if (not v_sof_detected) and (rx_mac_i.do_hard_sync = '1') and (rx_mac_o.rx_data = c_dominant) then
        v_sof_detected        := true;
        -- Lower do_hard_sync after SOF detection
        rx_mac_i.do_hard_sync <= '0' after 2 * gc_TbClkPeriod;
        -- Push the SOF bit the received bits FIFO
        v_bit_index           := 0;
        Push(rx_mac_rec.BurstFifo, "" & rx_mac_o.rx_data);
      end if;

      -- Simple RX MAC model -----------------------------------------------------
      if v_bit_index = res_bit_index - 1 then                                   -- FDF SP: arm hard sync for res edge
        rx_mac_i.do_hard_sync <= '1' after 2 * gc_TbClkPeriod;
      elsif v_bit_index = res_bit_index then                                    -- res SP: drop hard sync, switch to data rate at BRS SP
        rx_mac_i.do_hard_sync       <= '0' after 2 * gc_TbClkPeriod;
        rx_mac_i.next_bit_is_brs <= '1' after 2 * gc_TbClkPeriod;
      elsif v_bit_index = res_bit_index + 1 then                                -- res SP: drop hard sync, switch to data rate at BRS SP
        rx_mac_i.next_bit_is_brs <= '0' after 2 * gc_TbClkPeriod;
      elsif v_bit_index = crc_delimiter_index - 1 then                          -- last-data sp: switch back to nominal at crc-delim sp
        rx_mac_i.data_phase_stop <= '1' after 2 * gc_tbclkperiod;
      elsif v_bit_index = crc_delimiter_index then                              -- last-data sp: switch back to nominal at crc-delim sp
        rx_mac_i.data_phase_stop <= '0' after 2 * gc_tbclkperiod;
      end if;
      ----------------------------------------------------------------------------

      -- Transaction dispatcher --------------------------------------------------
      if TransactionPending(rx_mac_rec.Rdy, rx_mac_rec.Ack) then
        case rx_mac_rec.Operation is
          when CHECK =>
            FinishTransaction(rx_mac_rec.Ack);
            v_bit_index           := 0;
            -- Do the check
            while not Empty(tx_mac_rec.BurstFifo) and not Empty(rx_mac_rec.BurstFifo) loop
              v_rx_bit    := Pop(rx_mac_rec.BurstFifo)(0);
              v_tx_bit    := Pop(tx_mac_rec.BurstFifo)(0);
              AffirmIf(check_id, v_rx_bit = v_tx_bit, "bit " & to_string(v_bit_index) & " RX: " & to_string(v_rx_bit) & " TX: " & to_string(v_tx_bit));
              v_bit_index := v_bit_index + 1;
            end loop;
            -- Flush any remaining bits in either fifo
            while not Empty(rx_mac_rec.BurstFifo) loop
              v_rx_bit := Pop(rx_mac_rec.BurstFifo)(0);
            end loop;
            while not Empty(tx_mac_rec.BurstFifo) loop
              v_tx_bit := Pop(tx_mac_rec.BurstFifo)(0);
            end loop;
            -- Reset frame state and re-arm SOF detection for next frame
            v_sof_detected        := false;
            v_bit_index           := -1;
            rx_mac_i.do_hard_sync <= '1' after 2 * gc_TbClkPeriod;
          when others => null;
        end case;
      end if;
      ----------------------------------------------------------------------------
    end loop rx_mac_loop;
  end process p_rx_mac_vc;

  ----------------------------------------------------------------------------
  -- p_test_ctrl
  ----------------------------------------------------------------------------
  p_test_ctrl : process is
    procedure test_reset is
    begin
      Print("--------------------------------------------------------------------------");
      Print("Test 1: Reset defaults");
      Print("--------------------------------------------------------------------------");

      AffirmIf(check_id, tx_from_tx_dut = c_recessive, "TX PCS -> MAC");
      AffirmIf(check_id, rx_mac_o = c_pcs_to_mac_if_reset, "RX PCS -> MAC");
    end procedure test_reset;

    procedure drive_random_frames is
      variable v_pol : std_logic;
    begin
      Print("--------------------------------------------------------------------------");
      Print("Test 2: Drive random frames (CC and FD)");
      Print("--------------------------------------------------------------------------");
      tx_mac_i.transmitting <= '1';
      rx_mac_i.transmitting <= '0';

      for frame_iter in 1 to frames_to_send loop
        -- Alternate which clock leads
        tx_clock_is_leading         <= not tx_clock_is_leading;
        tx_mac_i.next_bit_is_res <= '0';
        tx_mac_i.next_bit_is_brs <= '0';

        for i in 0 to crc_delimiter_index + 1 loop
          wait until rising_edge(tx_mac_o.sample_point);
          if i = 0 then
            Push(tx_mac_rec.BurstFifo, "" & c_dominant);                        -- Drive SOF bit
            tx_mac_i.tx_data <= c_dominant after 2 * gc_TbClkPeriod;
          elsif i = res_bit_index - 1 then                                      -- Drive recessive FDF bit
            Push(tx_mac_rec.BurstFifo, "" & c_recessive);
            tx_mac_i.tx_data <= c_recessive after 2 * gc_TbClkPeriod;
          elsif i = res_bit_index then                                          -- Drive dominant res bit
            Push(tx_mac_rec.BurstFifo, "" & c_dominant);
            tx_mac_i.tx_data            <= c_dominant after 2 * gc_TbClkPeriod;
            tx_mac_i.next_bit_is_res <= '1' after 2 * gc_TbClkPeriod;
          elsif i = res_bit_index + 1 then                                      -- Drive BRS bit
            v_pol                       := RV.RandSlv(1)(1);
            Push(tx_mac_rec.BurstFifo, "" & v_pol);
            tx_mac_i.tx_data            <= v_pol after 2 * gc_TbClkPeriod;
            tx_mac_i.next_bit_is_res <= '0' after 2 * gc_TbClkPeriod;
            tx_mac_i.next_bit_is_brs <= '1' after 2 * gc_TbClkPeriod;
          elsif i = crc_delimiter_index then                                    -- Drive data phase stop bit
            Push(tx_mac_rec.BurstFifo, "" & c_recessive);
            tx_mac_i.tx_data         <= c_recessive after 2 * gc_TbClkPeriod;
            tx_mac_i.data_phase_stop <= '1' after 2 * gc_TbClkPeriod;
          else                                                                  --other bits
            v_pol                       := RV.RandSlv(1)(1);
            Push(tx_mac_rec.BurstFifo, "" & v_pol);
            tx_mac_i.tx_data            <= v_pol after 2 * gc_TbClkPeriod;
            tx_mac_i.next_bit_is_brs <= '0' after 2 * gc_TbClkPeriod;
            tx_mac_i.data_phase_stop    <= '0' after 2 * gc_TbClkPeriod;
          end if;
        end loop;

        -- Drive a final bit and wait for it to land at RX before checking
        wait until rising_edge(tx_mac_o.sample_point);
        Push(tx_mac_rec.BurstFifo, "" & c_recessive);
        tx_mac_i.tx_data <= c_recessive after 2 * gc_TbClkPeriod;
        wait until rising_edge(rx_mac_o.sample_point);
        Check(rx_mac_rec, "");

        -- Drive inter-frame space (a few recessive bits)
        for i in 1 to 5 loop
          wait until rising_edge(tx_mac_o.sample_point);
        end loop;
      end loop;
    end procedure drive_random_frames;

    procedure test_bus_off is
      variable v_tx_idle : natural := 0;
      variable v_rx_idle : natural := 0;
      variable v_bus_dom : boolean := false;
    begin
      Print("--------------------------------------------------------------------------");
      Print("Test 3: Bus-off idle condition (TX + RX PCS)");
      Print("--------------------------------------------------------------------------");

      tx_fce_i.bus_off <= '1';
      rx_fce_i.bus_off <= '1';

      -- Sample some pulses after bus_off is set
      for i in 1 to c_nom_bit_time_tq * 2 * 11 * 3 loop
        wait until rising_edge(clk_tx);
        v_rx_idle := v_rx_idle + 1 when rx_fce_o.idle_condition = '1' else v_rx_idle;
        v_tx_idle := v_tx_idle + 1 when tx_fce_o.idle_condition = '1' else v_tx_idle;
        v_bus_dom := true when bus_level = c_dominant else v_bus_dom;
      end loop;

      AffirmIf(check_id, not v_bus_dom, "Bus must stay recessive when PCS's in bus_off");
      AffirmIf(check_id, v_tx_idle >= 1, "TX PCS idle_condition must pulse");
      AffirmIf(check_id, v_rx_idle >= 1, "RX PCS idle_condition must pulse ");
    end procedure test_bus_off;

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
    drive_random_frames;
    test_bus_off;

    report_results;
    std.env.finish;
    wait;
  end process p_test_ctrl;
end architecture tb;
