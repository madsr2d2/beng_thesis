--------------------------------------------------------------------------------
-- Title      : MAC Serializer TX Testbench with OSVVM Streaming VCs
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_mac_ser_tx_tb_with_fsm_model.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Testbench for can_mac_ser_tx using OSVVM streaming VCs.
--              Operates byte-by-byte: the sequencer sends each LLC byte
--              individually, then checks the resulting bit stream before
--              advancing to the next byte.
--
--              LLC VC (p_llc_vc) - Single-byte Avalon-ST sender.
--                Accepts SEND with Data (byte) and Param (SOP & EOP).
--
--              MAC FSM VC (p_mac_fsm_vc) - Single process controlling
--                ready and transfer_status.
--                  SEND: set transfer_status.
--                  CHECK_BURST: drive random ready (50/50), pop expected
--                    bits from BurstFifo and compare on each handshake.
--                    Returns when BurstFifo is empty.
--
--              Test sequencer (p_test_ctrl) - Per-frame loop:
--                1. Send(rx_mac_fsm_rec, c_ongoing)
--                2. Send config bytes 0-1 via LLC (metadata only)
--                3. For each ID/data byte:
--                   a. Send byte via LLC
--                   b. Push expected real bits, CheckBurst
--                4. Send(rx_mac_fsm_rec, c_transmitted)
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

library osvvm;
  context osvvm.OsvvmContext;
  use osvvm.ScoreboardPkg_slv.all;
library osvvm_common;
  context osvvm_common.OsvvmCommonContext;

entity can_mac_ser_tx_tb_with_fsm_model is
  generic (
    gc_TbTimeOut   : time := 500 ms;
    gc_TbClkPeriod : time := 10 ns
  );
end entity can_mac_ser_tx_tb_with_fsm_model;

architecture tb of can_mac_ser_tx_tb_with_fsm_model is

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  constant c_config_bytes    : integer  := 2;
  constant c_first_data_byte : integer  := c_config_bytes + c_llc_id_byte_count;
  constant c_cb_cov_bin      : integer := to_integer(unsigned(c_llc_fmt_cb));
  constant c_ce_cov_bin      : integer := to_integer(unsigned(c_llc_fmt_ce));
  constant c_fb_cov_bin      : integer := to_integer(unsigned(c_llc_fmt_fb));
  constant c_bin_num         : integer := 100;
  constant c_fe_cov_bin      : integer := to_integer(unsigned(c_llc_fmt_fe));
  constant c_metadata_check    : std_logic_vector_max_c := "01";
  constant c_bit_stream_check  : std_logic_vector_max_c := "10";


  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal clk   : std_logic;
  signal reset : std_logic;

  -- DUT interface
  signal llc_i        : t_can_llc_mac_tx_if_s2d;
  signal llc_o        : t_can_llc_mac_tx_if_d2s;
  signal tx_mac_fsm_i : t_can_mac_ser_fsm_tx_if_m2s;
  signal tx_mac_fsm_o : t_can_mac_ser_fsm_tx_if_s2m;

  -- OSVVM signals
  shared variable RV  : RandomPType;
  signal test_id      : AlertLogIDType;
  signal fmt_cov      : CoverageIDType;
  signal dlc_cov      : CoverageIDType;
  signal init_barrier : std_logic := '0';
  signal llc_rec : StreamRecType(
    DataToModel    (t_byte'high downto 0),
    ParamToModel   (1 downto 0),
    DataFromModel  (0 downto 0),
    ParamFromModel (0 downto 0)
  );
  signal mac_fsm_rec : StreamRecType(
    DataToModel    (2 downto 0),
    ParamToModel   (1 downto 0),
    DataFromModel  (0 downto 0),
    ParamFromModel (0 downto 0)
  );

  ----------------------------------------------------------------------------
  -- Functions and procedures 
  ----------------------------------------------------------------------------
  function to_slv (b : std_logic) return std_logic_vector is
  begin
    return (0 downto 0 => b);
  end function to_slv;

  procedure avalon_st_send (
    signal   sink   : in    t_eth_st_d2s;
    signal   source : out   t_eth_st_s2d;
    constant data   : in    std_logic_vector(c_byte_width - 1 downto 0);
    constant sop    : in    std_logic;
    constant eop    : in    std_logic
  ) is
  begin
    source.valid         <= '1';
    source.data          <= data;
    source.startofpacket <= sop;
    source.endofpacket   <= eop;

    -- Wait for ready+valid handshake on clock edge
    loop
      WaitForClock(clk);
      exit when sink.ready = '1';
    end loop;
    wait for 0 ns;
    source.valid <= '0';
  end procedure avalon_st_send;

  function extract_metadata (
    config_byte_0 : t_byte;
    config_byte_1 : t_byte
  ) return t_llc_metadata is
    variable result : t_llc_metadata;
  begin
    result.format := config_byte_0(c_llc_frame_config_byte_0_format_start downto c_llc_frame_config_byte_0_format_end);
    result.ftyp   := config_byte_0(c_llc_frame_config_byte_0_ftyp);
    result.esi    := config_byte_0(c_llc_frame_config_byte_0_esi);
    result.brs    := config_byte_0(c_llc_frame_config_byte_0_brs);
    result.dlc    := config_byte_1(c_llc_frame_config_byte_1_dlc_start downto c_llc_frame_config_byte_1_dlc_end);
    return result;
  end function extract_metadata;

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
    variable v_test_id : AlertLogIDType;
    variable v_fmt_cov : CoverageIDType;
    variable v_dlc_cov : CoverageIDType;
  begin
    SetAlertStopCount(ERROR, 10);
    SetLogEnable(INFO, TRUE);
    v_test_id := NewId("can_mac_ser_tx");
    v_fmt_cov := NewID("Format Coverage", v_test_id);
    v_dlc_cov := NewID("DLC Coverage", v_test_id);
    mac_fsm_rec.BurstFifo <= NewID("MacFsmBurstFifo", v_test_id);

    -- Add coverage bins
    AddBins(v_fmt_cov, GenBin(c_bin_num, (c_cb_cov_bin, c_ce_cov_bin, c_fb_cov_bin, c_fe_cov_bin)));
    AddBins(v_dlc_cov, GenBin(c_bin_num, 0, c_dlc_max, c_dlc_max + 1));

    test_id <= v_test_id;
    fmt_cov <= v_fmt_cov;
    dlc_cov <= v_dlc_cov;

    WaitForBarrier(init_barrier);
    wait;
  end process p_init;

  ----------------------------------------------------------------------------
  -- DUT
  ----------------------------------------------------------------------------
  u_dut : entity work.can_mac_ser_tx
    port map (
      clk_i        => clk,
      rst_i        => reset,
      llc_i        => llc_i,
      llc_o        => llc_o,
      tx_mac_fsm_i => tx_mac_fsm_i,
      tx_mac_fsm_o => tx_mac_fsm_o
    );

  ----------------------------------------------------------------------------
  -- LLC Verification Component
  ----------------------------------------------------------------------------
  p_llc_vc : process is
  begin
    -- TODO: Use the proper reset constant here
    llc_i.avalon_st_source.valid         <= '0';
    llc_i.avalon_st_source.startofpacket <= '0';
    llc_i.avalon_st_source.endofpacket   <= '0';
    llc_i.avalon_st_source.data          <= (others => '0');
    WaitForBarrier(init_barrier);

    llv_vs_loop : loop
      WaitForTransaction(clk, llc_rec.Rdy, llc_rec.Ack);

      case llc_rec.Operation is
        when SEND =>
          avalon_st_send(llc_o.avalon_st_sink, llc_i.avalon_st_source,
                        std_logic_vector(llc_rec.DataToModel),
                        llc_rec.ParamToModel(1), llc_rec.ParamToModel(0));

        when others => Null;
      end case;
    end loop;
  end process p_llc_vc;

  ----------------------------------------------------------------------------
  -- MAC FSM Verification Component
  ----------------------------------------------------------------------------
  p_mac_fsm_vc : process is
  begin
    tx_mac_fsm_i <= c_tx_mac_fsm_to_ser_if_reset;
    WaitForBarrier(init_barrier);

    mac_fsm_vs_loop : loop
      WaitForTransaction(clk, mac_fsm_rec.Rdy, mac_fsm_rec.Ack);

      case mac_fsm_rec.Operation is
        when SEND =>
          tx_mac_fsm_i.transfer_status <= std_logic_vector(mac_fsm_rec.DataToModel);

        when CHECK_BURST =>
          -- Metadata check
          if mac_fsm_rec.ParamToModel = c_metadata_check then
            AffirmIfEqual(test_id, tx_mac_fsm_o.llc_metadata.format, Pop(mac_fsm_rec.BurstFifo), "FORMAT");
            AffirmIfEqual(test_id, tx_mac_fsm_o.llc_metadata.dlc, Pop(mac_fsm_rec.BurstFifo), "DLC");
            AffirmIfEqual(test_id, to_slv(tx_mac_fsm_o.llc_metadata.ftyp), Pop(mac_fsm_rec.BurstFifo), "FTYP");
            AffirmIfEqual(test_id, to_slv(tx_mac_fsm_o.llc_metadata.brs), Pop(mac_fsm_rec.BurstFifo), "BRS");
            AffirmIfEqual(test_id, to_slv(tx_mac_fsm_o.llc_metadata.esi), Pop(mac_fsm_rec.BurstFifo), "ESI");
          end if;

          -- Bit stream check
          if mac_fsm_rec.ParamToModel = c_bit_stream_check then
            while GetFifoCount(mac_fsm_rec.BurstFifo) > 0 loop
              -- Random back pressure
              tx_mac_fsm_i.ready <= '1' when RV.RandBool else '0';
              WaitForClock(clk);
              if (tx_mac_fsm_i.ready = '1') and (tx_mac_fsm_o.valid = '1') then
                AffirmIfEqual(test_id, to_slv(tx_mac_fsm_o.data), Pop(mac_fsm_rec.BurstFifo), "Bit check");
              end if;
            end loop;
          end if;

        when others => Null;
      end case;
    end loop;
  end process p_mac_fsm_vc;

  ----------------------------------------------------------------------------
  -- Transfer status checker
  ----------------------------------------------------------------------------
  p_transfer_status_checker : process is
    variable v_prev_input : std_logic_vector(2 downto 0) := c_ongoing;
  begin
    WaitForBarrier(init_barrier);
    wait until reset = '1';

    loop
      wait until rising_edge(clk);
      if reset = '1' then
        AffirmIfEqual(test_id, llc_o.transfer_status, c_ongoing, "Transfer status reset value");
      else
        AffirmIfEqual(test_id, llc_o.transfer_status, v_prev_input, "Transfer status forwarding");
        v_prev_input := tx_mac_fsm_i.transfer_status;
      end if;
    end loop;
  end process p_transfer_status_checker;

  ----------------------------------------------------------------------------
  -- Test sequencer
  ----------------------------------------------------------------------------
  p_test_ctrl : process is
    variable v_frame         : t_llc_frame;
    variable v_metadata      : t_llc_metadata;
    variable v_last_byte     : integer;
    variable v_id_remaining  : integer;
    variable v_pad_remaining : integer;
    variable v_frame_count   : integer := 0;
  begin
    WaitForBarrier(init_barrier);
    wait until reset = '0';
    WaitForClock(clk, 5);

    -- Loop until full coverage (each loop transmits a new frame)
    frame_loop : while not (IsCovered(fmt_cov) and IsCovered(dlc_cov)) loop
      v_frame_count := v_frame_count + 1;

      -- Set transfer_status to ongoing
      Send(mac_fsm_rec, Data => c_ongoing);

      -- Generate random frame
      for i in v_frame'range loop
        v_frame(i) := RV.RandSlv(8);
      end loop;

      -- Coverage-driven format and DLC
      v_frame(0)(c_llc_frame_config_byte_0_format_start downto c_llc_frame_config_byte_0_format_end) := std_logic_vector(to_unsigned(GetRandPoint(fmt_cov), 3));
      v_frame(1)(c_llc_frame_config_byte_1_dlc_start downto c_llc_frame_config_byte_1_dlc_end) := std_logic_vector(to_unsigned(GetRandPoint(dlc_cov), 4));

      -- Extract metadata and compute frame length
      v_metadata  := extract_metadata(v_frame(0), v_frame(1));
      v_last_byte := c_first_data_byte + dlc_to_data_length( t_dlc(to_integer(unsigned(v_metadata.dlc))), v_metadata.format) - 1;

      -- Initialize ID/padding counters (like in DUT)
      if (v_metadata.format(2) = '1') then
        v_id_remaining  := c_base_id_width + c_extended_id_width;
        v_pad_remaining := c_llc_id_stream_width - (c_base_id_width + c_extended_id_width);
      else
        v_id_remaining  := c_base_id_width;
        v_pad_remaining := c_llc_id_stream_width - c_base_id_width;
      end if;

      -- Send config bytes (DUT does not generate bit stream for the config bytes)
      Send(llc_rec, v_frame(0), "10");
      Send(llc_rec, v_frame(1), "00");

      -- Verify LLC metadata (Param="1" flags metadata check)
      Push(mac_fsm_rec.BurstFifo, v_metadata.format);
      Push(mac_fsm_rec.BurstFifo, v_metadata.dlc);
      Push(mac_fsm_rec.BurstFifo, to_slv(v_metadata.ftyp));
      Push(mac_fsm_rec.BurstFifo, to_slv(v_metadata.brs));
      Push(mac_fsm_rec.BurstFifo, to_slv(v_metadata.esi));
      CheckBurst(mac_fsm_rec, GetFifoCount(mac_fsm_rec.BurstFifo), std_logic_vector(c_metadata_check));

      -- ID + data bytes: send each byte, then check its bit stream
      for i in c_config_bytes to v_last_byte loop

        -- Send byte to LLC
        Send(llc_rec, v_frame(i), "00");

        -- Push expected real bits for this byte (skip padding)
        for bit_pos in c_byte_width - 1 downto 0 loop
          if (v_pad_remaining > 0) and (v_id_remaining = 0) then
            v_pad_remaining := v_pad_remaining - 1;
          else
            Push(mac_fsm_rec.BurstFifo, to_slv(v_frame(i)(bit_pos)));
            if (v_id_remaining > 0) then
              v_id_remaining := v_id_remaining - 1;
            end if;
          end if;
        end loop;

        -- Check bits for this byte (skip pure-padding bytes)
        if GetFifoCount(mac_fsm_rec.BurstFifo) > 0 then
          CheckBurst(mac_fsm_rec, GetFifoCount(mac_fsm_rec.BurstFifo), std_logic_vector(c_bit_stream_check));
        end if;

        -- Random abort after check (~2% probability, BurstFifo is empty here)
        if RV.DistBool((false => 98, true => 2)) then
          Send(mac_fsm_rec, Data => c_disturbed);
          WaitForClock(clk, 3);
          next frame_loop;
        end if;
      end loop;

      -- End transfer and sample coverage
      Send(mac_fsm_rec, Data => c_transmitted);
      ICover(fmt_cov, to_integer(unsigned(v_metadata.format)));
      ICover(dlc_cov, to_integer(unsigned(v_metadata.dlc)));
      WaitForClock(clk, 2);
    end loop frame_loop;

    WriteBin(fmt_cov);
    WriteBin(dlc_cov);
    EndOfTestReports(ReportAll => true);
    std.env.finish;
    wait;
  end process p_test_ctrl;

end architecture tb;

-- eof
