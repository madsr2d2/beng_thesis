--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_mac + can_fce node-to-node integration.
--                Two can_mac + can_fce pairs share a dominant-wins bus.
--                Node A transmits, Node B receives. A simplified PCS model
--                provides bit timing (SP strobes) for both nodes.
--                  p_tx_pcs_vc      - TX PCS model (bit timing, bus drive, loopback).
--                  p_rx_pcs_vc      - RX PCS model (bus sample, SP strobe).
--                  p_tx_llc_vc      - LLC Avalon-ST source VC (drives frame bytes to Node A TX).
--                  p_rx_llc_sink_vc - LLC Avalon-ST sink VC (collects and verifies at Node B RX).
--                  p_test_ctrl      - Test sequencer.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-04-13  MRDSA     Initial node-to-node wiring testbench
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;
  use work.pk_can_tb.all;

library osvvm;
  context osvvm.OsvvmContext;
  use osvvm.ScoreboardPkg_slv.all;
library osvvm_common;
  context osvvm_common.OsvvmCommonContext;

entity can_mac_n2n_tb is
  generic (
    gc_TbTimeOut   : time := 50 ms;
    gc_TbClkPeriod : time := 10 ns
  );
end entity can_mac_n2n_tb;

architecture tb of can_mac_n2n_tb is

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  -- Nominal bit timing (same as can_mac_tx_tb)
  constant c_sp       : natural := c_sync_seg + (t_nominal_prop_seg'high - t_nominal_prop_seg'low) / 2 + (t_nominal_phase_seg1'high - t_nominal_phase_seg1'low) / 2;
  constant c_bit_time : natural := c_sp + (t_nominal_phase_seg2'high - t_nominal_phase_seg2'low) / 2;

  -- Data phase bit timing
  constant c_data_sp       : natural := c_sync_seg + (t_data_prop_seg'high - t_data_prop_seg'low) / 2 + (t_data_phase_seg1'high - t_data_phase_seg1'low) / 2;
  constant c_data_ssp      : natural := c_data_sp / 2;
  constant c_data_bit_time : natural := c_data_sp + t_data_phase_seg2'high;

  constant c_rec_width    : natural := 16;
  constant c_bin_at_least : natural := 5;

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

  -- Node A (transmitter): MAC + FCE
  signal a_tx_llc_i : t_can_llc_mac_tx_if_s2d;
  signal a_tx_llc_o : t_can_llc_mac_tx_if_d2s;
  signal a_rx_llc_i : t_can_llc_mac_rx_if_d2s;
  signal a_rx_llc_o : t_can_llc_mac_rx_if_s2d;
  signal a_tx_pcs_i : t_can_mac_pcs_if_s2m := c_pcs_to_mac_if_reset;
  signal a_tx_pcs_o : t_can_mac_pcs_if_m2s;
  signal a_rx_pcs_i : t_can_mac_pcs_if_s2m := c_pcs_to_mac_if_reset;
  signal a_rx_pcs_o : t_can_mac_pcs_if_m2s;
  signal a_mac_fce_o : t_can_mac_fce_if_m2s;
  signal a_fce_mac_o : t_can_mac_fce_if_s2m;
  signal a_fce_llc_i : t_can_llc_fce_if_m2s := c_llc_to_fce_if_reset;
  signal a_fce_llc_o : t_can_fce_llc_if_s2m;
  signal a_fce_pcs_i : t_can_pcs_fce_if_s2m := c_pcs_to_fce_if_reset;
  signal a_fce_pcs_o : t_can_fce_pcs_if_m2s;
  signal a_debug_tec : natural range 0 to c_fce_tec_max;
  signal a_debug_rec : natural range 0 to c_fce_rec_max;

  -- Node B (receiver): MAC + FCE
  signal b_tx_llc_i : t_can_llc_mac_tx_if_s2d;
  signal b_tx_llc_o : t_can_llc_mac_tx_if_d2s;
  signal b_rx_llc_i : t_can_llc_mac_rx_if_d2s;
  signal b_rx_llc_o : t_can_llc_mac_rx_if_s2d;
  signal b_tx_pcs_i : t_can_mac_pcs_if_s2m := c_pcs_to_mac_if_reset;
  signal b_tx_pcs_o : t_can_mac_pcs_if_m2s;
  signal b_rx_pcs_i : t_can_mac_pcs_if_s2m := c_pcs_to_mac_if_reset;
  signal b_rx_pcs_o : t_can_mac_pcs_if_m2s;
  signal b_mac_fce_o : t_can_mac_fce_if_m2s;
  signal b_fce_mac_o : t_can_mac_fce_if_s2m;
  signal b_fce_llc_i : t_can_llc_fce_if_m2s := c_llc_to_fce_if_reset;
  signal b_fce_llc_o : t_can_fce_llc_if_s2m;
  signal b_fce_pcs_i : t_can_pcs_fce_if_s2m := c_pcs_to_fce_if_reset;
  signal b_fce_pcs_o : t_can_fce_pcs_if_m2s;
  signal b_debug_tec : natural range 0 to c_fce_tec_max;
  signal b_debug_rec : natural range 0 to c_fce_rec_max;

  -- Transfer status latch (Node A TX)
  signal status_latch : std_logic_vector(2 downto 0) := c_ongoing;
  signal clear_status : boolean := false;

  -- OSVVM signals
  shared variable RV : RandomPType;
  signal test_id      : AlertLogIDType;
  signal check_id     : AlertLogIDType;
  signal ide_cov      : CoverageIDType;
  signal fdf_cov      : CoverageIDType;
  signal dlc_cov      : CoverageIDType;
  signal init_barrier : std_logic := '0';

  -- Transaction interfaces
  signal tx_llc_rec : StreamRecType(
    DataToModel    (c_rec_width - 1 downto 0),
    ParamToModel   (c_rec_width - 1 downto 0),
    DataFromModel  (c_rec_width - 1 downto 0),
    ParamFromModel (c_rec_width - 1 downto 0)
  );
  signal rx_llc_rec : StreamRecType(
    DataToModel    (c_rec_width - 1 downto 0),
    ParamToModel   (c_rec_width - 1 downto 0),
    DataFromModel  (c_rec_width - 1 downto 0),
    ParamFromModel (c_rec_width - 1 downto 0)
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
    v_test_id  := NewID("can_mac_n2n_tb");
    v_check_id := NewID("Frame check", v_test_id);
    v_ide_cov  := NewID("IDE Coverage", v_test_id, ReportMode => ENABLED);
    v_fdf_cov  := NewID("FDF Coverage", v_test_id, ReportMode => ENABLED);
    v_dlc_cov  := NewID("DLC Coverage", v_test_id, ReportMode => ENABLED);
    RV.InitSeed(RV'instance_name & to_string(now));
    AddBins(v_ide_cov, c_bin_at_least, GenBin(0, 1));
    AddBins(v_fdf_cov, c_bin_at_least, GenBin(0, 1));
    AddBins(v_dlc_cov, c_bin_at_least, GenBin(0, c_dlc_max));
    tx_llc_rec.BurstFifo <= NewID("TX LLC Burst fifo");
    rx_llc_rec.BurstFifo <= NewID("RX LLC Burst fifo");
    test_id  <= v_test_id;
    check_id <= v_check_id;
    ide_cov  <= v_ide_cov;
    fdf_cov  <= v_fdf_cov;
    dlc_cov  <= v_dlc_cov;
    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  -- Node A: RX LLC sink always ready (unused, but prevents backpressure stall)
  a_rx_llc_i.avalon_st_sink.ready <= '1';
  -- Node B: TX LLC idle, RX LLC sink ready
  b_tx_llc_i.avalon_st_source.valid         <= '0';
  b_tx_llc_i.avalon_st_source.data          <= (others => '0');
  b_tx_llc_i.avalon_st_source.startofpacket <= '0';
  b_tx_llc_i.avalon_st_source.endofpacket   <= '0';
  b_rx_llc_i.avalon_st_sink.ready           <= '1';

  ----------------------------------------------------------------------------
  -- Shared bus: dominant-wins (AND logic, c_dominant = '0').
  -- Each MAC holds pcs_o.polarity recessive in quiet states, so plain AND
  -- of all four drivers gives correct wired-AND semantics.
  ----------------------------------------------------------------------------
  bus_level <= a_tx_pcs_o.polarity and a_rx_pcs_o.polarity and b_tx_pcs_o.polarity and b_rx_pcs_o.polarity;

  ----------------------------------------------------------------------------
  -- Node A: can_mac + can_fce (transmitter)
  ----------------------------------------------------------------------------
  u_mac_a : entity work.can_mac
    port map (
      clk      => clk,
      rst      => reset,
      tx_llc_i => a_tx_llc_i,
      tx_llc_o => a_tx_llc_o,
      rx_llc_i => a_rx_llc_i,
      rx_llc_o => a_rx_llc_o,
      tx_pcs_i => a_tx_pcs_i,
      tx_pcs_o => a_tx_pcs_o,
      rx_pcs_i => a_rx_pcs_i,
      rx_pcs_o => a_rx_pcs_o,
      fce_i    => a_fce_mac_o,
      fce_o    => a_mac_fce_o
    );

  u_fce_a : entity work.can_fce
    port map (
      clk_i       => clk,
      rst_i       => reset,
      llc_i       => a_fce_llc_i,
      llc_o       => a_fce_llc_o,
      mac_i       => a_mac_fce_o,
      mac_o       => a_fce_mac_o,
      pcs_i       => a_fce_pcs_i,
      pcs_o       => a_fce_pcs_o,
      debug_tec_o => a_debug_tec,
      debug_rec_o => a_debug_rec
    );

  ----------------------------------------------------------------------------
  -- Node B: can_mac + can_fce (receiver)
  ----------------------------------------------------------------------------
  u_mac_b : entity work.can_mac
    port map (
      clk      => clk,
      rst      => reset,
      tx_llc_i => b_tx_llc_i,
      tx_llc_o => b_tx_llc_o,
      rx_llc_i => b_rx_llc_i,
      rx_llc_o => b_rx_llc_o,
      tx_pcs_i => b_tx_pcs_i,
      tx_pcs_o => b_tx_pcs_o,
      rx_pcs_i => b_rx_pcs_i,
      rx_pcs_o => b_rx_pcs_o,
      fce_i    => b_fce_mac_o,
      fce_o    => b_mac_fce_o
    );

  u_fce_b : entity work.can_fce
    port map (
      clk_i       => clk,
      rst_i       => reset,
      llc_i       => b_fce_llc_i,
      llc_o       => b_fce_llc_o,
      mac_i       => b_mac_fce_o,
      mac_o       => b_fce_mac_o,
      pcs_i       => b_fce_pcs_i,
      pcs_o       => b_fce_pcs_o,
      debug_tec_o => b_debug_tec,
      debug_rec_o => b_debug_rec
    );

  ----------------------------------------------------------------------------
  -- Transfer status latch (Node A TX)
  ----------------------------------------------------------------------------
  p_status_latch : process (clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' or clear_status then
        status_latch <= c_ongoing;
      else
        status_latch <= a_tx_llc_o.transfer_status when a_tx_llc_o.transfer_status /= c_ongoing;
      end if;
    end if;
  end process p_status_latch;

  ----------------------------------------------------------------------------
  -- PCS model Node A: shared bit timing for TX and RX paths.
  -- The TX path's use_data_rate controls the bit rate switch since Node A
  -- is the transmitter; the RX path follows the same timing.
  ----------------------------------------------------------------------------
  p_pcs_a : process is
    variable v_tq_count        : natural range 0 to c_bit_time := 0;
    variable v_active_bit_time : natural := c_bit_time;
    variable v_active_sp       : natural := c_sp;
    variable v_tx_sp_strobe    : std_logic;
    variable v_rx_sp_strobe    : std_logic;
    variable v_ssp_strobe      : std_logic;
  begin
    WaitForBarrier(init_barrier);

    pcs_a_loop : loop
      wait until rising_edge(clk);
      v_tq_count := 0 when v_tq_count = v_active_bit_time else v_tq_count + 1;
      if v_tq_count = 0 then
        v_active_bit_time := c_data_bit_time when a_tx_pcs_o.use_data_rate = '1' else c_bit_time;
        v_active_sp       := c_data_sp       when a_tx_pcs_o.use_data_rate = '1' else c_sp;
      end if;
      v_tx_sp_strobe := '1' when v_tq_count = v_active_sp else '0';
      v_rx_sp_strobe := '1' when v_tq_count = v_active_sp + 2 else '0';
      v_ssp_strobe   := '1' when v_tq_count = c_data_ssp and a_tx_pcs_o.use_data_rate = '1' else '0';

      -- TX PCS input
      a_tx_pcs_i.sample_point           <= v_tx_sp_strobe;
      a_tx_pcs_i.secondary_sample_point <= v_ssp_strobe;
      a_tx_pcs_i.tdc_delay              <= (others => '0');
      a_tx_pcs_i.bus_polarity           <= bus_level;

      -- RX PCS input (SP offset by +2 TQ for bus propagation)
      a_rx_pcs_i.sample_point           <= v_rx_sp_strobe;
      a_rx_pcs_i.secondary_sample_point <= v_ssp_strobe;
      a_rx_pcs_i.tdc_delay              <= (others => '0');
      a_rx_pcs_i.bus_polarity           <= bus_level;
    end loop pcs_a_loop;
  end process p_pcs_a;

  ----------------------------------------------------------------------------
  -- PCS model Node B: shared bit timing for TX and RX paths.
  -- Node B is the receiver; its RX path's use_data_rate controls the
  -- bit rate switch after it decodes BRS.
  ----------------------------------------------------------------------------
  p_pcs_b : process is
    variable v_tq_count        : natural range 0 to c_bit_time := 0;
    variable v_active_bit_time : natural := c_bit_time;
    variable v_active_sp       : natural := c_sp;
    variable v_tx_sp_strobe    : std_logic;
    variable v_rx_sp_strobe    : std_logic;
    variable v_ssp_strobe      : std_logic;
  begin
    WaitForBarrier(init_barrier);

    pcs_b_loop : loop
      wait until rising_edge(clk);
      v_tq_count := 0 when v_tq_count = v_active_bit_time else v_tq_count + 1;
      if v_tq_count = 0 then
        v_active_bit_time := c_data_bit_time when b_rx_pcs_o.use_data_rate = '1' else c_bit_time;
        v_active_sp       := c_data_sp       when b_rx_pcs_o.use_data_rate = '1' else c_sp;
      end if;
      v_tx_sp_strobe := '1' when v_tq_count = v_active_sp else '0';
      v_rx_sp_strobe := '1' when v_tq_count = v_active_sp + 2 else '0';
      v_ssp_strobe   := '1' when v_tq_count = c_data_ssp and b_rx_pcs_o.use_data_rate = '1' else '0';

      -- TX PCS input
      b_tx_pcs_i.sample_point           <= v_tx_sp_strobe;
      b_tx_pcs_i.secondary_sample_point <= v_ssp_strobe;
      b_tx_pcs_i.tdc_delay              <= (others => '0');
      b_tx_pcs_i.bus_polarity           <= bus_level;

      -- RX PCS input (SP offset by +2 TQ for bus propagation)
      b_rx_pcs_i.sample_point           <= v_rx_sp_strobe;
      b_rx_pcs_i.secondary_sample_point <= v_ssp_strobe;
      b_rx_pcs_i.tdc_delay              <= (others => '0');
      b_rx_pcs_i.bus_polarity           <= bus_level;
    end loop pcs_b_loop;
  end process p_pcs_b;

  ----------------------------------------------------------------------------
  -- Node A: TX LLC source VC (drives frame bytes)
  ----------------------------------------------------------------------------
  p_tx_llc_vc : process is
  begin
    WaitForBarrier(init_barrier);
    tx_llc_loop : loop
      WaitForTransaction(tx_llc_rec.Rdy, tx_llc_rec.Ack);
      case tx_llc_rec.Operation is
        when SEND =>
          a_tx_llc_i.avalon_st_source.valid         <= '1';
          a_tx_llc_i.avalon_st_source.data          <= SafeResize(std_logic_vector(tx_llc_rec.DataToModel), c_byte_width);
          a_tx_llc_i.avalon_st_source.startofpacket <= tx_llc_rec.ParamToModel(1);
          a_tx_llc_i.avalon_st_source.endofpacket   <= tx_llc_rec.ParamToModel(0);
          wait until rising_edge(clk) and a_tx_llc_o.avalon_st_sink.ready = '1';
          a_tx_llc_i.avalon_st_source.valid <= '0';
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
    end loop tx_llc_loop;
  end process p_tx_llc_vc;

  ----------------------------------------------------------------------------
  -- Node B: RX LLC sink VC (collects and verifies received frame)
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

    -- Initialize Ack from default (-1) to 0 so FinishTransaction
    -- increments to the value RequestTransaction expects.
    rx_llc_rec.Ack <= rx_llc_rec.Ack + 1;
    wait for 0 ns;

    rx_llc_loop : loop
      wait until rising_edge(clk);

      -- Collect bytes from Node B RX LLC output
      if (not v_got_frame and b_rx_llc_o.avalon_st_source.valid = '1') then
        v_frame(v_byte_idx) := b_rx_llc_o.avalon_st_source.data;
        if (b_rx_llc_o.avalon_st_source.endofpacket = '1') then
          v_frame_len := v_byte_idx + 1;
          v_got_frame := true;
        else
          v_byte_idx := v_byte_idx + 1;
        end if;
      end if;

      -- Check received frame against expected
      if v_got_frame and TransactionPending(rx_llc_rec.Rdy, rx_llc_rec.Ack) then
        case rx_llc_rec.Operation is
          when CHECK =>
            v_exp_len := to_integer(unsigned(rx_llc_rec.DataToModel(7 downto 0)));
            v_count   := to_integer(unsigned(rx_llc_rec.ParamToModel(15 downto 0)));
            AffirmIfEqual(check_id, v_frame_len, v_exp_len, "Frame " & to_string(v_count) & " length");
            for i in 0 to v_exp_len - 1 loop
              v_exp_byte := Pop(rx_llc_rec.BurstFifo);
              AffirmIfEqual(check_id, v_frame(i), v_exp_byte(7 downto 0), "Frame " & to_string(v_count) & " byte " & to_string(i));
            end loop;
            v_byte_idx  := 0;
            v_got_frame := false;
          when others => null;
        end case;
        FinishTransaction(rx_llc_rec.Ack);
      end if;
    end loop rx_llc_loop;
  end process p_rx_llc_sink_vc;

  ----------------------------------------------------------------------------
  -- p_test_ctrl
  ----------------------------------------------------------------------------
  p_test_ctrl : process is

    --------------------------------------------------------------------------
    -- gen_frame: random LLC frame + expected RX frame (sanitized)
    --------------------------------------------------------------------------
    procedure gen_frame (
      variable tx_frame    : out t_llc_frame;
      variable rx_frame    : out t_llc_frame;
      variable metadata    : out t_llc_metadata;
      variable last_byte   : out natural
    ) is
      variable v_data_len : natural;
    begin
      for i in tx_frame'range loop
        tx_frame(i) := RV.RandSlv(8);
      end loop;
      tx_frame(0)(c_llc_frame_ide) := std_logic(to_unsigned(GetRandPoint(ide_cov), 1)(0));
      tx_frame(0)(c_llc_frame_fdf) := std_logic(to_unsigned(GetRandPoint(fdf_cov), 1)(0));
      tx_frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end) :=
        std_logic_vector(to_unsigned(GetRandPoint(dlc_cov), 4));
      metadata  := extract_metadata(tx_frame(0), tx_frame(1));
      v_data_len := dlc_to_data_length(to_integer(unsigned(metadata.dlc)), metadata.fdf);
      last_byte := c_llc_frame_data_byte + v_data_len - 1;

      -- Build expected RX frame (sanitize fields RX cannot reconstruct)
      rx_frame := tx_frame;
      rx_frame(0)(5)          := '0';
      rx_frame(0)(1 downto 0) := "00";
      rx_frame(1)(3 downto 0) := "0000";
      if (metadata.fdf = '0') then
        rx_frame(0)(c_llc_frame_esi) := '0';
        rx_frame(0)(c_llc_frame_brs) := '0';
      else
        rx_frame(0)(c_llc_frame_ftyp) := '0';
      end if;
      if (metadata.ide = '1') then
        rx_frame(5)(2 downto 0) := "000";
      else
        rx_frame(3)(4 downto 0) := "00000";
        rx_frame(4)             := (others => '0');
        rx_frame(5)             := (others => '0');
      end if;
      for i in v_data_len to c_max_data_bytes - 1 loop
        rx_frame(c_data_offset + i) := (others => '0');
      end loop;
    end procedure gen_frame;

    --------------------------------------------------------------------------
    -- Submit frame via Node A TX, verify at Node B RX
    --------------------------------------------------------------------------
    procedure submit_and_verify (
      variable v_tx_frame    : in t_llc_frame;
      variable v_rx_frame    : in t_llc_frame;
      variable v_last_byte   : in natural;
      variable v_metadata    : in t_llc_metadata;
      variable v_frame_count : in natural
    ) is
      variable v_exp_len : natural;
    begin
      v_exp_len := c_data_offset + dlc_to_data_length(
        to_integer(unsigned(v_metadata.dlc)), v_metadata.fdf);

      -- Push expected RX bytes into LLC sink BurstFifo
      for i in 0 to v_exp_len - 1 loop
        Push(rx_llc_rec.BurstFifo, std_logic_vector(resize(unsigned(v_rx_frame(i)), c_rec_width)));
      end loop;

      -- Drive TX frame bytes through Node A LLC
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

      -- Verify RX collected the frame
      Check(rx_llc_rec,
        std_logic_vector(to_unsigned(v_exp_len, c_rec_width)),
        std_logic_vector(to_unsigned(v_frame_count, c_rec_width)));
    end procedure submit_and_verify;

    variable v_tx_frame    : t_llc_frame;
    variable v_rx_frame    : t_llc_frame;
    variable v_metadata    : t_llc_metadata;
    variable v_last_byte   : natural;
    variable v_frame_count : natural := 0;

  begin
    WaitForBarrier(init_barrier);
    wait until reset = '0';

    -- Wait for both nodes to complete bus reintegration (11 bit times + margin)
    WaitForClock(clk, (c_bus_idle_condition_width + 2) * (c_bit_time + 1));

    Print("--------------------------------------------------------------------------");
    Print("can_mac_n2n_tb: Node-to-node frame transfer");
    Print("--------------------------------------------------------------------------");

    while not (IsCovered(ide_cov) and IsCovered(fdf_cov) and IsCovered(dlc_cov)) loop
      v_frame_count := v_frame_count + 1;

      gen_frame(v_tx_frame, v_rx_frame, v_metadata, v_last_byte);
      submit_and_verify(v_tx_frame, v_rx_frame, v_last_byte, v_metadata, v_frame_count);

      ICover(ide_cov, to_integer(unsigned'("" & v_metadata.ide)));
      ICover(fdf_cov, to_integer(unsigned'("" & v_metadata.fdf)));
      ICover(dlc_cov, to_integer(unsigned(v_metadata.dlc)));

      Log(test_id,
        "Frame " & to_string(v_frame_count) &
        " ide=" & to_string(v_metadata.ide) &
        " fdf=" & to_string(v_metadata.fdf) &
        " dlc=" & to_hstring(v_metadata.dlc), DEBUG);
    end loop;

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
    std.env.finish;
    wait;
  end process p_test_ctrl;

end architecture tb;
