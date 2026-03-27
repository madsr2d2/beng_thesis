--------------------------------------------------------------------------------
-- Title      : MAC Serializer TX Testbench with OSVVM Streaming VCs
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_mac_ser_tx_tb_with_fsm_model.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Testbench for can_mac_ser_tx using OSVVM streaming VCs with
--              burst transactions.
--
--              LLC VC (p_llc_vc) - Avalon-ST byte sender. On SEND_BURST,
--                pops bytes from BurstFifo and sends each via Avalon-ST
--                with SOP on the first byte. Random inter-byte gaps.
--
--              MAC FSM VC - Two processes, split signals to avoid multiple
--                drivers on the tx_mac_fsm_i record:
--                p_ready_and_capture: autonomous random ready (50/50) and
--                  scoreboard-based bit capture on valid+ready handshake.
--                p_mac_fsm_vc: blocking transaction handler.
--                  SEND: set transfer_status.
--                  CHECK_BURST: wait for captured bits, then compare
--                    against expected from BurstFifo.
--
--              Test sequencer (p_test_ctrl):
--                1. Send(rx_mac_fsm_rec, c_ongoing)
--                2. Push frame bytes, SendBurst(tx_llc_rec, N)
--                3. Push expected bits, CheckBurst(rx_mac_fsm_rec, N)
--                4. Send(rx_mac_fsm_rec, c_transmitted) + settle wait
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
  constant c_frames_to_send  : positive := 50;
  constant c_max_real_bits   : integer  := c_max_mac_frame_length;
  constant c_config_bytes    : integer  := 2;
  constant c_first_data_byte : integer  := c_config_bytes + c_llc_id_byte_count;

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal clk   : std_logic;
  signal reset : std_logic := '1';

  signal llc_i        : t_can_llc_mac_tx_if_s2d;
  signal llc_o        : t_can_llc_mac_tx_if_d2s;
  signal tx_mac_fsm_o : t_can_mac_ser_fsm_tx_if_s2m;

  -- Split into two signals to avoid multiple drivers (ready from p_ready_and_capture,
  -- transfer_status from p_mac_fsm_vc)
  signal fsm_ready           : std_logic;
  signal fsm_transfer_status : std_logic_vector(2 downto 0);

  signal test_id    : AlertLogIDType;
  signal llc_vc_id  : AlertLogIDType;
  signal fsm_vc_id  : AlertLogIDType;
  signal capture_sb : ScoreboardIdType;

  -- LLC VC transaction record
  signal tx_llc_rec : StreamRecType(
    DataToModel    (t_byte'high downto 0),
    ParamToModel   (1 downto 0),
    DataFromModel  (0 downto 0),
    ParamFromModel (0 downto 0)
  );

  -- MAC FSM VC transaction record
  signal rx_mac_fsm_rec : StreamRecType(
    DataToModel    (2 downto 0),
    ParamToModel   (0 downto 0),
    DataFromModel  (0 downto 0),
    ParamFromModel (0 downto 0)
  );

  shared variable RV : RandomPType;

  ----------------------------------------------------------------------------
  -- Procedures
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
    -- Wait for ready before driving valid (matches real LLC behavior)
    if sink.ready /= '1' then
      wait until sink.ready = '1';
    end if;

    source.valid         <= '1';
    source.data          <= data;
    source.startofpacket <= sop;
    source.endofpacket   <= eop;

    WaitForClock(clk);
    wait for 0 ns;
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

  procedure build_expected_stream (
    constant frame      : in    t_llc_frame;
    constant metadata   : in    t_llc_metadata;
    variable expected   : out   std_logic_vector;
    variable num_bits   : out   integer
  ) is
    variable v_id_remaining  : integer;
    variable v_pad_remaining : integer;
    variable v_bit_idx       : integer := 0;
    variable v_data_length   : integer;
    variable v_last_byte     : integer;
  begin
    v_data_length := dlc_to_data_length(
                       t_dlc(to_integer(unsigned(metadata.dlc))),
                       metadata.format);
    v_last_byte   := c_first_data_byte + v_data_length - 1;

    if (metadata.format(2) = '1') then
      v_id_remaining  := c_base_id_width + c_extended_id_width;
      v_pad_remaining := c_llc_id_stream_width - (c_base_id_width + c_extended_id_width);
    else
      v_id_remaining  := c_base_id_width;
      v_pad_remaining := c_llc_id_stream_width - c_base_id_width;
    end if;

    for i in c_config_bytes to v_last_byte loop
      for bit_pos in c_byte_width - 1 downto 0 loop
        if (v_pad_remaining > 0) and (v_id_remaining = 0) then
          v_pad_remaining := v_pad_remaining - 1;
        else
          expected(v_bit_idx) := frame(i)(bit_pos);
          v_bit_idx := v_bit_idx + 1;
          if (v_id_remaining > 0) then
            v_id_remaining := v_id_remaining - 1;
          end if;
        end if;
      end loop;
    end loop;

    num_bits := v_bit_idx;
  end procedure build_expected_stream;

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
    variable v_test_id   : AlertLogIDType;
    variable v_llc_vc_id : AlertLogIDType;
    variable v_fsm_vc_id : AlertLogIDType;
  begin
    SetAlertStopCount(ERROR, 10);
    v_test_id   := NewId("can_mac_ser_tx");
    v_llc_vc_id := NewID("LLC_VC");
    v_fsm_vc_id := NewID("MAC_FSM_VC");

    test_id    <= v_test_id;
    llc_vc_id  <= v_llc_vc_id;
    fsm_vc_id  <= v_fsm_vc_id;
    capture_sb <= NewID("CaptureFifo", v_fsm_vc_id);

    tx_llc_rec.BurstFifo     <= NewID("LlcBurstFifo", v_llc_vc_id);
    rx_mac_fsm_rec.BurstFifo <= NewID("MacFsmBurstFifo", v_fsm_vc_id);
    wait for 0 ns;
    wait;
  end process p_init;

  ----------------------------------------------------------------------------
  -- DUT
  ----------------------------------------------------------------------------
  u_dut : entity work.can_mac_ser_tx
    port map (
      clk_i                       => clk,
      rst_i                       => reset,
      llc_i                       => llc_i,
      llc_o                       => llc_o,
      tx_mac_fsm_i.ready           => fsm_ready,
      tx_mac_fsm_i.transfer_status => fsm_transfer_status,
      tx_mac_fsm_o                 => tx_mac_fsm_o
    );

  -- =========================================================================
  -- LLC Verification Component (Avalon-ST byte sender)
  -- SEND: single byte. SEND_BURST: pops N bytes, SOP on first.
  -- =========================================================================
  p_llc_vc : process is
  begin
    llc_i.avalon_st_source.valid         <= '0';
    llc_i.avalon_st_source.startofpacket <= '0';
    llc_i.avalon_st_source.endofpacket   <= '0';
    llc_i.avalon_st_source.data          <= (others => '0');
    wait for 0 ns; -- let p_init complete

    loop
      WaitForTransaction(clk, tx_llc_rec.Rdy, tx_llc_rec.Ack);

      case tx_llc_rec.Operation is
        when SEND =>
          avalon_st_send(llc_o.avalon_st_sink, llc_i.avalon_st_source,
                        std_logic_vector(tx_llc_rec.DataToModel),
                        tx_llc_rec.ParamToModel(1), tx_llc_rec.ParamToModel(0));
          llc_i.avalon_st_source.valid <= '0';

        when SEND_BURST =>
          -- First byte with SOP
          avalon_st_send(llc_o.avalon_st_sink, llc_i.avalon_st_source,
                        Pop(tx_llc_rec.BurstFifo), '1', '0');
          llc_i.avalon_st_source.valid <= '0';
          WaitForClock(clk);

          -- Remaining bytes with random inter-byte gaps
          for i in 1 to tx_llc_rec.IntToModel - 1 loop
            if (RV.RandInt(0, 3) > 0) then
              WaitForClock(clk, RV.RandInt(1, 3));
            end if;
            avalon_st_send(llc_o.avalon_st_sink, llc_i.avalon_st_source,
                          Pop(tx_llc_rec.BurstFifo), '0', '0');
            llc_i.avalon_st_source.valid <= '0';
            WaitForClock(clk);
          end loop;

        when WAIT_FOR_CLOCK =>
          WaitForClock(clk, tx_llc_rec.IntToModel);

        when others =>
          Alert(llc_vc_id, "LLC VC: unsupported operation", FAILURE);
      end case;
    end loop;
  end process p_llc_vc;

  -- =========================================================================
  -- MAC FSM: random ready driver + bit capture
  -- =========================================================================
  p_ready_and_capture : process is
  begin
    fsm_ready <= '0';
    wait until reset = '0';
    loop
      fsm_ready <= '1' when RV.RandBool else '0';
      WaitForClock(clk);
      if (fsm_ready = '1') and (tx_mac_fsm_o.valid = '1') then
        Push(capture_sb, to_slv(tx_mac_fsm_o.data));
      end if;
    end loop;
  end process p_ready_and_capture;

  -- =========================================================================
  -- MAC FSM Verification Component (blocking transaction handler)
  --   SEND: set transfer_status.
  --   CHECK_BURST: wait for bits, then compare against expected.
  -- =========================================================================
  p_mac_fsm_vc : process is
  begin
    fsm_transfer_status <= c_ongoing;
    wait for 0 ns; -- let p_init complete
    wait until reset = '0';

    loop
      WaitForTransaction(clk, rx_mac_fsm_rec.Rdy, rx_mac_fsm_rec.Ack);

      case rx_mac_fsm_rec.Operation is

        when SEND =>
          fsm_transfer_status <= std_logic_vector(rx_mac_fsm_rec.DataToModel);

        when CHECK_BURST =>
          -- Wait for all expected bits to arrive
          while GetFifoCount(capture_sb) < rx_mac_fsm_rec.IntToModel loop
            WaitForClock(clk);
          end loop;

          -- Compare captured bits against expected
          for i in 0 to rx_mac_fsm_rec.IntToModel - 1 loop
            AffirmIfEqual(fsm_vc_id, Pop(capture_sb), Pop(rx_mac_fsm_rec.BurstFifo),
                        "Bit " & to_string(i));
          end loop;
          AffirmIfEqual(fsm_vc_id, GetFifoCount(capture_sb), 0,
                      "No extra bits captured beyond target");

        when WAIT_FOR_CLOCK =>
          WaitForClock(clk, rx_mac_fsm_rec.IntToModel);

        when others =>
          Alert(fsm_vc_id, "MAC FSM VC: unsupported operation", FAILURE);
      end case;
    end loop;
  end process p_mac_fsm_vc;

  -- =========================================================================
  -- Test sequencer
  -- =========================================================================
  p_test_ctrl : process is
    variable v_frame        : t_llc_frame;
    variable v_metadata     : t_llc_metadata;
    variable v_total_bytes  : integer;
    variable v_expected     : std_logic_vector(c_max_real_bits - 1 downto 0);
    variable v_expected_len : integer;

  begin
    wait until reset = '0';
    WaitForClock(clk, 5);

    for frame_idx in 1 to c_frames_to_send loop

      -- Reset capture + set transfer_status to ongoing
      Send(rx_mac_fsm_rec, Data => c_ongoing);

      -- Generate random frame
      for i in v_frame'range loop
        v_frame(i) := RV.RandSlv(8);
      end loop;
      -- Constrain format field (byte 0 bits 7:5) to valid CAN formats
      -- Valid: CB="000", CE="100", FB="010", FE="110" - bit 5 always '0'
      v_frame(0)(5) := '0';

      -- Extract metadata and compute byte count
      v_metadata    := extract_metadata(v_frame(0), v_frame(1));
      v_total_bytes := c_first_data_byte + dlc_to_data_length(
                          t_dlc(to_integer(unsigned(v_metadata.dlc))),
                          v_metadata.format);

      -- Build expected serial stream
      build_expected_stream(v_frame, v_metadata, v_expected, v_expected_len);

      -- Push frame bytes into LLC BurstFifo, send as burst
      for i in 0 to v_total_bytes - 1 loop
        Push(tx_llc_rec.BurstFifo, v_frame(i));
      end loop;
      SendBurst(tx_llc_rec, v_total_bytes);

      -- Push expected bits into MAC FSM BurstFifo, check as burst
      for i in 0 to v_expected_len - 1 loop
        Push(rx_mac_fsm_rec.BurstFifo, to_slv(v_expected(i)));
      end loop;
      CheckBurst(rx_mac_fsm_rec, v_expected_len);

      -- End transfer
      Send(rx_mac_fsm_rec, Data => c_transmitted);
      WaitForClock(clk, 2); -- Let DUT deassert valid before next frame

      -- Verify LLC metadata
      AffirmIfEqual(test_id, tx_mac_fsm_o.llc_metadata.format, v_metadata.format,
                  "Frame " & to_string(frame_idx) & ": FORMAT");
      AffirmIfEqual(test_id, tx_mac_fsm_o.llc_metadata.dlc, v_metadata.dlc,
                  "Frame " & to_string(frame_idx) & ": DLC");
      AffirmIfEqual(test_id, tx_mac_fsm_o.llc_metadata.ftyp, v_metadata.ftyp,
                  "Frame " & to_string(frame_idx) & ": FTYP");
      AffirmIfEqual(test_id, tx_mac_fsm_o.llc_metadata.brs, v_metadata.brs,
                  "Frame " & to_string(frame_idx) & ": BRS");
      AffirmIfEqual(test_id, tx_mac_fsm_o.llc_metadata.esi, v_metadata.esi,
                  "Frame " & to_string(frame_idx) & ": ESI");

      Log(test_id, "Frame " & to_string(frame_idx) & " checked (" &
          to_string(v_expected_len) & " bits, fmt=" &
          to_hstring(v_metadata.format) & ")", INFO);

    end loop;

    EndOfTestReports;
    std.env.finish;

    wait;
  end process p_test_ctrl;

end architecture tb;

-- eof
