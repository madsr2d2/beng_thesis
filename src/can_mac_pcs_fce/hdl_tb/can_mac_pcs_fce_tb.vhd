--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for can_mac_pcs_fce.
--                  p_tx_llc_vc       - Avalon-ST source VC driving LLC TX frame bytes to DUT 1.
--                  p_tx_llc_vc_dut_2 - Avalon-ST source VC driving LLC TX frame bytes to DUT 2.
--                  p_status_latch       - Continuous monitor latching DUT 1 transfer status.
--                  p_status_latch_dut_2 - Continuous monitor latching DUT 2 transfer status.
--                  p_test_ctrl       - Coverage-driven test sequencer (IDE, FDF, DLC bins).
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
use work.pk_can_tb.all;

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

  constant c_bin_at_least : natural := 5;
  constant c_rec_width    : natural := 16;

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

  -- Bus signals ------------------------------------------------------------
  signal tx_on_bus_at_tx : std_logic := c_recessive;
  signal tx_on_bus_at_rx : std_logic := c_recessive;
  signal rx_on_bus_at_rx : std_logic := c_recessive;
  signal rx_on_bus_at_tx : std_logic := c_recessive;
  signal bus_at_tx       : std_logic := c_recessive;
  signal bus_at_rx       : std_logic := c_recessive;

  -- DUT bus interfaces -----------------------------------------------------
  signal tx_from_tx_dut       : std_logic;
  signal tx_from_rx_dut       : std_logic;
  signal rx_at_rx_dut         : std_logic := c_recessive;
  signal rx_at_tx_dut         : std_logic := c_recessive;
  signal bus_at_tx_observed   : std_logic;

  -- s_dut_1_rx_recessive forces DUT 1's loopback recessive so every dominant
  -- it drives becomes a bit error (TEC += 8, bypasses error-passive exemption).
  signal s_dut_1_rx_recessive : boolean   := false;
  signal s_dut_2_reset        : std_logic := '0';

  -- Sticky bus_off latch (DUT 1): captures the pulse since FCE may recover
  -- before the sequencer samples the live signal.
  signal s_bus_off_seen  : boolean := false;
  signal s_bus_off_clear : boolean := false;

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
  signal status_latch             : std_logic_vector(2 downto 0) := c_ongoing;
  signal clear_status             : boolean                      := false;
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
  signal llc_rec    : StreamRecType(
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
  begin
    SetAlertStopCount(ERROR, 1);
    SetLogEnable(DEBUG, false);
    v_test_id            := NewID("can_mac_pcs_fce");
    v_check_id           := NewID("Frame check", v_test_id);
    v_ide_cov            := NewID("IDE Coverage", v_test_id, ReportMode => ENABLED);
    v_fdf_cov            := NewID("FDF Coverage", v_test_id, ReportMode => ENABLED);
    v_dlc_cov            := NewID("DLC Coverage", v_test_id, ReportMode => ENABLED);
    RV.InitSeed(RV'instance_name & to_string(now));
    AddBins(v_ide_cov, c_bin_at_least, GenBin(0, 1));
    AddBins(v_fdf_cov, c_bin_at_least, GenBin(0, 1));
    AddBins(v_dlc_cov, c_bin_at_least, GenBin(0, c_dlc_max));
    tx_llc_rec_dut_1.BurstFifo <= NewID("TX LLC Burst fifo");
    llc_rec.BurstFifo    <= NewID("RX LLC Burst fifo");
    test_id              <= v_test_id;
    check_id             <= v_check_id;
    ide_cov              <= v_ide_cov;
    fdf_cov              <= v_fdf_cov;
    dlc_cov              <= v_dlc_cov;
    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  -- DUT 1: RX LLC sink always ready (prevents backpressure stall)
  mac_to_llc_tx_d2s_dut_1.avalon_st_sink.ready <= '1';
  -- DUT 2: RX LLC sink always ready
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
      tx_o      => tx_from_tx_dut,
      rx_i      => rx_at_tx_dut
    );

  ----------------------------------------------------------------------------
  -- DUT 2 (Receiver)
  ----------------------------------------------------------------------------
  u_dut_2 : entity work.can_mac_pcs_fce
    port map(
      clk      => clk,
      rst      => reset or s_dut_2_reset,
      tx_llc_i  => llc_to_mac_tx_s2d_dut_2,
      tx_llc_o  => llc_to_mac_tx_d2s_dut_2,
      rx_llc_i  => mac_to_llc_tx_d2s_dut_2,
      rx_llc_o  => mac_to_llc_tx_s2d_dut_2,
      llc_fce_i => llc_fce_i_dut_2,
      llc_fce_o => llc_fce_o_dut_2,
      tx_o      => tx_from_rx_dut,
      rx_i      => rx_at_rx_dut
    );

  ----------------------------------------------------------------------------
  -- Bus model: dominant-wins wired-AND
  ----------------------------------------------------------------------------
  bus_at_tx          <= tx_on_bus_at_tx and rx_on_bus_at_tx;
  bus_at_tx_observed <= c_recessive when s_dut_1_rx_recessive else bus_at_tx;
  bus_at_rx          <= tx_on_bus_at_rx and rx_on_bus_at_rx;

  p_tx_onto_bus : process is
  begin
    wait on tx_from_tx_dut;
    tx_on_bus_at_tx <= transport tx_from_tx_dut after s_transceiver_tx_d;
  end process;

  p_tx_loopback : process is
  begin
    wait on bus_at_tx_observed;
    rx_at_tx_dut <= transport bus_at_tx_observed after s_transceiver_rx_d;
  end process;

  p_rx_onto_wire : process is
  begin
    wait on tx_from_rx_dut;
    rx_on_bus_at_rx <= transport tx_from_rx_dut after s_transceiver_tx_d;
  end process;

  p_rx_sees_bus : process is
  begin
    wait on bus_at_rx;
    rx_at_rx_dut <= transport bus_at_rx after s_transceiver_rx_d;
  end process;

  -- Cross-propagation between the two DUT ends
  p_tx_propagate : process is
  begin
    wait on tx_on_bus_at_tx;
    tx_on_bus_at_rx <= transport tx_on_bus_at_tx after s_bus_delay;
  end process;

  p_rx_propagate : process is
  begin
    wait on rx_on_bus_at_rx;
    rx_on_bus_at_tx <= transport rx_on_bus_at_rx after s_bus_delay;
  end process;

  ----------------------------------------------------------------------------
  -- Bus-off sticky latch (DUT 1)
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
  p_status_latch : process(clk) is
  begin
    if rising_edge(clk) then
      if reset = '1' or clear_status or s_status_latch_rst_dut_1 then
        status_latch <= c_ongoing;
      else
        if llc_to_mac_tx_d2s_dut_1.transfer_status /= c_ongoing
           and llc_to_mac_tx_d2s_dut_1.transfer_status /= status_latch then
          status_latch <= llc_to_mac_tx_d2s_dut_1.transfer_status;
        end if;
      end if;
    end if;
  end process p_status_latch;

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
          if status_latch = c_ongoing then
            wait until status_latch /= c_ongoing;
          end if;
          AffirmIfEqual(check_id, status_latch, std_logic_vector(tx_llc_rec_dut_1.DataToModel(2 downto 0)), "Transfer status");
          clear_status <= true;
          wait until rising_edge(clk);
          clear_status <= false;
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
    llc_rec.Ack <= llc_rec.Ack + 1;
    wait for 0 ns;

    rx_sink_loop : loop
      wait until rising_edge(clk);

      if (not v_got_frame and mac_to_llc_tx_s2d_dut_2.avalon_st_source.valid = '1') then
        v_frame(v_byte_idx) := mac_to_llc_tx_s2d_dut_2.avalon_st_source.data;
        if (mac_to_llc_tx_s2d_dut_2.avalon_st_source.endofpacket = '1') then
          v_frame_len := v_byte_idx + 1;
          v_got_frame := true;
        else
          v_byte_idx := v_byte_idx + 1;
        end if;
      end if;

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
    end loop rx_sink_loop;
  end process p_rx_llc_sink_vc;

  ----------------------------------------------------------------------------
  -- p_test_ctrl
  ----------------------------------------------------------------------------
  p_test_ctrl : process is

    --------------------------------------------------------------------------
    -- gen_frame: LLC data frame (FTYP=0).
    -- v_id >= 0: fixed CC base frame with the given 11-bit ID and DLC=v_dlc.
    -- v_id  < 0: samples IDE/FDF/DLC from coverage bins, randomises ID/data.
    --------------------------------------------------------------------------
    procedure gen_frame(tx_frame  : out t_llc_frame;
                        metadata  : out t_llc_metadata;
                        last_byte : out natural;
                        v_id      : integer := -1;
                        v_dlc     : integer := -1) is
      variable v_data_len : natural;
      variable v_id_slv   : std_logic_vector(c_base_id_width - 1 downto 0);
    begin
      for i in tx_frame'range loop
        tx_frame(i) := (others => '0');
      end loop;
      if v_id >= 0 then
        tx_frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end) :=
          std_logic_vector(to_unsigned(v_dlc, c_dlc_field_width));
        v_id_slv                := std_logic_vector(to_unsigned(v_id, c_base_id_width));
        tx_frame(2)             := v_id_slv(c_base_id_width - 1 downto c_base_id_width - 8);
        tx_frame(3)(7 downto 5) := v_id_slv(2 downto 0);
      else
        tx_frame(0)(c_llc_frame_ide) := std_logic(to_unsigned(GetRandPoint(ide_cov), 1)(0));
        tx_frame(0)(c_llc_frame_fdf) := std_logic(to_unsigned(GetRandPoint(fdf_cov), 1)(0));
        tx_frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end) :=
          std_logic_vector(to_unsigned(GetRandPoint(dlc_cov), 4));
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
        if tx_frame(0)(c_llc_frame_fdf) = '1' then
          tx_frame(0)(c_llc_frame_brs) := RV.RandSlv(1)(1);
          tx_frame(0)(c_llc_frame_esi) := RV.RandSlv(1)(1);
        end if;
      end if;
      metadata   := extract_metadata(tx_frame(0), tx_frame(1));
      v_data_len := dlc_to_data_length(to_integer(unsigned(metadata.dlc)), metadata.fdf);
      last_byte  := c_llc_frame_data_byte + v_data_len - 1;
      for i in 0 to v_data_len - 1 loop
        tx_frame(c_data_offset + i) := RV.RandSlv(8);
      end loop;
    end procedure gen_frame;

    --------------------------------------------------------------------------
    -- submit_and_verify: send frame via DUT 1, verify TX status and RX bytes
    --------------------------------------------------------------------------
    procedure submit_and_verify(v_tx_frame : in t_llc_frame; v_last_byte : in natural; v_metadata : in t_llc_metadata; v_frame_count : in natural) is
      variable v_exp_len : natural;
    begin
      v_exp_len := c_data_offset + dlc_to_data_length(to_integer(unsigned(v_metadata.dlc)), v_metadata.fdf);

      for i in 0 to v_exp_len - 1 loop
        Push(llc_rec.BurstFifo, std_logic_vector(resize(unsigned(v_tx_frame(i)), c_rec_width)));
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

      Print("    [sv] waiting for c_transmitted");
      Check(tx_llc_rec_dut_1, std_logic_vector(resize(unsigned(c_transmitted), c_rec_width)));
      Print("    [sv] c_transmitted received; waiting for RX frame");
      Check(llc_rec,
        std_logic_vector(to_unsigned(v_exp_len, c_rec_width)), std_logic_vector(to_unsigned(v_frame_count, c_rec_width)));
      Print("    [sv] RX frame verified");
    end procedure submit_and_verify;

    --------------------------------------------------------------------------
    -- Test 1: Normal usage -- cover all IDE x FDF x DLC bins
    --------------------------------------------------------------------------
    procedure test_normal is
      variable v_frame       : t_llc_frame;
      variable v_metadata    : t_llc_metadata;
      variable v_last_byte   : natural;
      variable v_frame_count : natural := 0;
    begin
      test_num <= 1;
      Print("--------------------------------------------------------------------------");
      Print("Test 1: Normal Usage (DUT 1 TX -> DUT 2 RX)");
      Print("--------------------------------------------------------------------------");
      while not (IsCovered(ide_cov) and IsCovered(fdf_cov) and IsCovered(dlc_cov)) loop
        v_frame_count := v_frame_count + 1;

        gen_frame(v_frame, v_metadata, v_last_byte);
        submit_and_verify(v_frame, v_last_byte, v_metadata, v_frame_count);

        ICover(ide_cov, to_integer(unsigned'("" & v_metadata.ide)));
        ICover(fdf_cov, to_integer(unsigned'("" & v_metadata.fdf)));
        ICover(dlc_cov, to_integer(unsigned(v_metadata.dlc)));
      end loop;
    end procedure test_normal;

    --------------------------------------------------------------------------
    -- Test 2: Delay sweep -- batch of frames at each c_delay_sweep operating point
    --------------------------------------------------------------------------
    procedure test_delay_sweep(num_frames_per_cfg : natural := 20) is
      variable v_frame       : t_llc_frame;
      variable v_metadata    : t_llc_metadata;
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

        Print("--- Delay config " & to_string(i)
              & ": tx="  & to_string(c_delay_sweep(i).tx_d)
              & " rx="   & to_string(c_delay_sweep(i).rx_d)
              & " bus="  & to_string(c_delay_sweep(i).bus_d));

        for j in 1 to num_frames_per_cfg loop
          v_frame_count := v_frame_count + 1;
          gen_frame(v_frame, v_metadata, v_last_byte);
          submit_and_verify(v_frame, v_last_byte, v_metadata, v_frame_count);
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
      constant c_dlc        : natural := 1;
      variable v_id_1       : natural;
      variable v_id_2       : natural;
      variable v_frame_1    : t_llc_frame;
      variable v_frame_2    : t_llc_frame;
      variable v_meta_1     : t_llc_metadata;
      variable v_meta_2     : t_llc_metadata;
      variable v_last       : natural;
      variable v_exp_len    : natural;
    begin
      test_num <= 3;
      Print("--------------------------------------------------------------------------");
      Print("Test 3: Lost Arbitration (random IDs, " & integer'image(c_iterations) & " iterations)");
      Print("--------------------------------------------------------------------------");
      s_transceiver_tx_d <= 300 ns;
      s_transceiver_rx_d <= 300 ns;
      s_bus_delay        <= 150 ns;
      v_exp_len := c_data_offset + dlc_to_data_length(c_dlc, '0');

      for iter in 1 to c_iterations loop
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
        WaitForClock(clk, 30 * c_bit_time);

        loop
          v_id_1 := RV.RandInt(0, 2 ** c_base_id_width - 1);
          v_id_2 := RV.RandInt(0, 2 ** c_base_id_width - 1);
          exit when v_id_1 /= v_id_2;
        end loop;
        gen_frame(v_frame_1, v_meta_1, v_last, v_id_1, c_dlc);
        gen_frame(v_frame_2, v_meta_2, v_last, v_id_2, c_dlc);

        -- llc_rec monitors DUT 2's LLC RX.  The MAC only asserts llc_stream_start when
        -- not is_transmitter, so the VC only gets a frame when DUT 2 is the receiver
        -- (i.e. DUT 1 wins).  Pre-load the BurstFifo now so the VC can match bytes as
        -- they arrive after EOF.
        if v_id_1 < v_id_2 then
          for i in 0 to v_exp_len - 1 loop
            Push(llc_rec.BurstFifo, std_logic_vector(resize(unsigned(v_frame_1(i)), c_rec_width)));
          end loop;
        end if;

        WaitForClock(clk, 3 * c_bit_time);

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

        if status_latch = c_ongoing then
          wait until status_latch /= c_ongoing for 5 ms;
        end if;
        if status_latch_dut_2 = c_ongoing then
          wait until status_latch_dut_2 /= c_ongoing for 5 ms;
        end if;

        -- Post-hoc: verify loser had the higher ID; check DUT 2's received frame when DUT 1 won.
        if status_latch = c_lost_arb then
          Print("iter " & to_string(iter) & ": DUT2 wins (0x" & to_hstring(to_unsigned(v_id_2, c_base_id_width))
            & " < 0x" & to_hstring(to_unsigned(v_id_1, c_base_id_width)) & ")");
          AffirmIfEqual(check_id, status_latch_dut_2, c_transmitted, "DUT 2 transmitted (iter " & to_string(iter) & ")");
          AffirmIf(check_id, v_id_1 > v_id_2, "DUT 1 lost arb: higher ID (iter " & to_string(iter) & ")");
        else
          Print("iter " & to_string(iter) & ": DUT1 wins (0x" & to_hstring(to_unsigned(v_id_1, c_base_id_width))
            & " < 0x" & to_hstring(to_unsigned(v_id_2, c_base_id_width)) & ")");
          AffirmIfEqual(check_id, status_latch,       c_transmitted, "DUT 1 transmitted (iter " & to_string(iter) & ")");
          AffirmIfEqual(check_id, status_latch_dut_2, c_lost_arb,   "DUT 2 lost arb (iter "    & to_string(iter) & ")");
          AffirmIf(check_id, v_id_2 > v_id_1, "DUT 2 lost arb: higher ID (iter " & to_string(iter) & ")");
          Check(llc_rec,
            std_logic_vector(to_unsigned(v_exp_len, c_rec_width)),
            std_logic_vector(to_unsigned(iter,      c_rec_width)));
        end if;
      end loop;

      s_status_latch_rst_dut_1 <= true;
      s_status_latch_rst_dut_2 <= true;
      WaitForClock(clk, 2);
      s_status_latch_rst_dut_1 <= false;
      s_status_latch_rst_dut_2 <= false;
    end procedure test_lost_arb;

    --------------------------------------------------------------------------
    -- Test 4: Bus-off entry and recovery.
    -- Phase 1-2: s_dut_1_rx_recessive forces bit errors on every dominant drive forcing DUT 1 dominant.
    -- Phase 3: lift injection; FCE counts 128 x 11 recessive bits and recovers.
    -- Phase 4: confirm normal TX/RX resumes.
    --------------------------------------------------------------------------
    procedure test_bus_off is
      variable v_frame      : t_llc_frame;
      variable v_metadata   : t_llc_metadata;
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
      gen_frame(v_frame, v_metadata, v_last_byte);
      while not s_bus_off_seen loop
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
        v_send_count := v_send_count + 1;
      end loop;
      AffirmIf(test_id, s_bus_off_seen, "Bus-off after " & to_string(v_send_count) & " sends");
      Print("--- Phase 2 done: bus_off seen after " & to_string(v_send_count) & " sends");

      -- Phase 3: lift injection; wait for FCE bus-off recovery (~1.41 ms).
      s_dut_1_rx_recessive <= false;
      Print("--- Phase 3: waiting for bus_off deassert");
      if llc_fce_o_dut_1.bus_off /= '0' then
        wait until llc_fce_o_dut_1.bus_off = '0';
      end if;
      AffirmIf(test_id, llc_fce_o_dut_1.bus_off = '0', "Bus-off recovered");
      Print("--- Phase 3 done: bus_off deasserted");

      -- Phase 4: DUT 1 completed bus_reintegration; allow intermission to
      -- finish, clear stale status latches, then send the confirmation frame.
      Print("--- Phase 4: WaitForClock");
      WaitForClock(clk, (c_bus_idle_condition_width + 2) * (c_bit_time + 1));
      Print("--- Phase 4: resetting status latch");
      s_status_latch_rst_dut_1 <= true;
      WaitForClock(clk, 2);
      s_status_latch_rst_dut_1 <= false;
      Print("--- Phase 4: submit_and_verify");
      gen_frame(v_frame, v_metadata, v_last_byte);
      submit_and_verify(v_frame, v_last_byte, v_metadata, 0);
      Print("--- Phase 4 done");
    end procedure test_bus_off;

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

    -- Allow both DUTs to complete bus reintegration.
    WaitForClock(clk, (c_bus_idle_condition_width + 2) * (c_bit_time + 1));

    test_normal;
    test_delay_sweep(5);
    test_lost_arb;
    test_bus_off;

    report_results;
    std.env.finish;
    wait;
  end process p_test_ctrl;

end architecture tb;
