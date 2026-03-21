--------------------------------------------------------------------------------
-- Title      : MAC Serializer TX Testbench
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_mac_ser_tx_tb.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Testbench for can_mac_ser_tx. Sends c_frames_to_send random LLC
--              frames through the serializer, verifying metadata extraction and
--              bit-by-bit data integrity. Random backpressure is applied on both
--              the LLC source and FSM ready interfaces. A ~2% per-byte abort
--              probability exercises the mid-frame abort path.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

library osvvm;
  context osvvm.OsvvmContext;

entity can_mac_ser_tx_tb is
  generic (
    gc_TbTimeOut   : time := 100 ms;
    gc_TbClkPeriod : time := 10 ns
  );
end entity can_mac_ser_tx_tb;

architecture tb of can_mac_ser_tx_tb is

  ----------------------------------------------------------------------------
  -- Constants
  ----------------------------------------------------------------------------
  constant c_frames_to_send : positive := 20;

  ----------------------------------------------------------------------------
  -- Signals
  ----------------------------------------------------------------------------
  signal clk   : std_logic;
  signal reset : std_logic := '1';

  signal llc_i        : t_can_llc_mac_tx_if_s2d;
  signal llc_o        : t_can_llc_mac_tx_if_d2s;
  signal tx_mac_fsm_i : t_can_mac_ser_fsm_tx_if_m2s;
  signal tx_mac_fsm_o : t_can_mac_ser_fsm_tx_if_s2m;

  signal test_id   : AlertLogIDType;
  signal llc_frame : t_llc_frame;

  shared variable RV : RandomPType;

  ----------------------------------------------------------------------------
  -- Procedures
  ----------------------------------------------------------------------------
  procedure generate_random_llc_frame (signal llc_frame : out t_llc_frame) is
  begin
    for i in llc_frame'range loop
      llc_frame(i) <= RV.RandSlv(8);
    end loop;
    wait for 0 ns;
  end procedure generate_random_llc_frame;

  procedure avalon_st_send (
    signal   sink   : in    t_eth_st_d2s;
    signal   source : out   t_eth_st_s2d;
    constant data   : in    t_byte;
    constant sop    : in    std_logic;
    constant eop    : in    std_logic
  ) is
  begin
    source.valid         <= '1';
    source.data          <= data;
    source.startofpacket <= sop;
    source.endofpacket   <= eop;

    if sink.ready /= '1' then
      wait until sink.ready = '1';
    end if;
    WaitForClock(clk);
    wait for 0 ns;  -- Let drain side outputs settle
  end procedure avalon_st_send;

  procedure random_abort (
    signal   tx_mac_fsm_i : out   t_can_mac_ser_fsm_tx_if_m2s;
    signal   llc_i        : out   t_can_llc_mac_tx_if_s2d;
    signal   llc_o        : in    t_can_llc_mac_tx_if_d2s;
    variable aborted      : out   boolean
  ) is
  begin
    aborted := false;
    if RV.DistBool((false => 98, true => 2)) then
      tx_mac_fsm_i.transfer_status <= c_disturbed;
      llc_i.avalon_st_source.valid <= '0';
      WaitForClock(clk);
      wait for 0 ns;
      AlertIf(test_id, llc_o.avalon_st_sink.ready = '0',
              "ERROR: ready not asserted after abort", FAILURE);
      AlertIf(test_id, llc_o.transfer_status /= c_disturbed,
              "ERROR: transfer status not forwarded after abort", FAILURE);
      aborted := true;
    end if;
  end procedure random_abort;

  procedure verify_llc_metadata (
    signal tx_mac_fsm_o : in t_can_mac_ser_fsm_tx_if_s2m;
    signal llc_frame    : in t_llc_frame
  ) is
  begin
    wait until falling_edge(clk);
    AlertIf(tx_mac_fsm_o.llc_metadata.format /= llc_frame(0)(c_llc_frame_config_byte_0_format_start downto c_llc_frame_config_byte_0_format_end),
            "ERROR: FORMAT mismatch", FAILURE);
    AlertIf(tx_mac_fsm_o.llc_metadata.is_remote_frame /= llc_frame(0)(c_llc_frame_config_byte_0_ftyp),
            "ERROR: is_remote_frame mismatch", FAILURE);
    AlertIf(tx_mac_fsm_o.llc_metadata.esi_enable /= llc_frame(0)(c_llc_frame_config_byte_0_esi),
            "ERROR: ESI mismatch", FAILURE);
    AlertIf(tx_mac_fsm_o.llc_metadata.has_brs /= llc_frame(0)(c_llc_frame_config_byte_0_brs),
            "ERROR: BRS mismatch", FAILURE);
    AlertIf(tx_mac_fsm_o.llc_metadata.dlc_vector /= llc_frame(1)(c_llc_frame_config_byte_1_dlc_start downto c_llc_frame_config_byte_1_dlc_end),
            "ERROR: DLC mismatch", FAILURE);
  end procedure verify_llc_metadata;

begin

  ----------------------------------------------------------------------------
  -- Initialisation
  ----------------------------------------------------------------------------
  p_init : process is
    variable v_test_id : AlertLogIDType;
  begin
    SetAlertStopCount(ERROR, 10);
    v_test_id := NewId("can_mac_ser_tx");
    test_id   <= v_test_id;
    wait until falling_edge(clk);
    wait;
  end process p_init;

  ----------------------------------------------------------------------------
  -- Clock and timeout
  ----------------------------------------------------------------------------
  CreateClock(clk, gc_TbClkPeriod);

  p_timeout : process is
  begin
    wait for gc_TbTimeOut;
    assert false report "ERROR TEST FAILED, due to time out" severity error;
    std.env.stop(1);
  end process p_timeout;

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

  -- -------------------------------------------------------------------------
  -- Main test process
  -- -------------------------------------------------------------------------
  main_tb_p : process is
    variable v_aborted : boolean;
  begin

    reset <= '1';
    WaitForClock(clk, 5);
    wait until falling_edge(clk);

    Print("==========================================");
    Print("TX MAC Serializer Testbench Started");
    Print("==========================================");

    -- =====================================================================
    -- Test 1: Reset values
    -- =====================================================================
    Print("-----------");
    Print("Test 1: Reset values");
    Print("-----------");

    AlertIf(test_id, tx_mac_fsm_o.valid = '1',
            "ERROR: valid should be deasserted in reset", FAILURE);
    AlertIf(test_id, llc_o.avalon_st_sink.ready = '1',
            "ERROR: ready should be deasserted in reset", FAILURE);

    reset <= '0';
    WaitForClock(clk);
    wait until falling_edge(clk);

    AlertIf(test_id, llc_o.avalon_st_sink.ready = '0',
            "ERROR: ready should be asserted after reset release", FAILURE);


    -- =====================================================================
    -- Test 2: Random frames with metadata, bit-level, and abort checks
    -- =====================================================================
    Print("-----------");
    Print("Test 2: Random frames with metadata, bit-level, and abort checks");
    Print("-----------");
    for frame_idx in 1 to c_frames_to_send loop

      tx_mac_fsm_i.transfer_status <= c_ongoing;
      WaitForClock(clk);

      wait until falling_edge(clk);
      AlertIf(test_id, llc_o.avalon_st_sink.ready = '0',
              "ERROR: ready should be asserted in idle state", FAILURE);

      generate_random_llc_frame(llc_frame);

      -- Config bytes
      avalon_st_send(sink => llc_o.avalon_st_sink,
                     source => llc_i.avalon_st_source,
                     data => llc_frame(0), sop => '1', eop => '0');

      avalon_st_send(sink => llc_o.avalon_st_sink,
                     source => llc_i.avalon_st_source,
                     data => llc_frame(1), sop => '0', eop => '0');

      llc_i.avalon_st_source.valid <= '0';

      -- Verify metadata is correct
      verify_llc_metadata(tx_mac_fsm_o, llc_frame);

      -- Data bytes with random backpressure
      for i in 2 to c_internal_llc_frame_len - 1 loop

        random_abort(tx_mac_fsm_i, llc_i, llc_o, v_aborted);
        exit when v_aborted;

        -- Random wait before llc_i valid
        WaitForClock(clk, RV.RandInt(1, 10));

        avalon_st_send(sink => llc_o.avalon_st_sink,
                       source => llc_i.avalon_st_source,
                       data => llc_frame(i), sop => '0', eop => '0');
        llc_i.avalon_st_source.valid <= '0';

        for j in c_byte_width - 1 downto 0 loop

          if tx_mac_fsm_o.valid = '1' then
            AlertIf(tx_mac_fsm_o.data /= llc_frame(i)(j),
                    "ERROR: byte " & to_string(i) & " bit " & to_string(j) &
                    " mismatch: expected " & to_string(llc_frame(i)(j)) &
                    " got " & to_string(tx_mac_fsm_o.data), FAILURE);

            -- Random wait before fsm_i ready
            WaitForClock(clk, RV.RandInt(1, 10));
            tx_mac_fsm_i.ready <= '1';
            WaitForClock(clk);
            tx_mac_fsm_i.ready <= '0';
            wait until falling_edge(clk);
          else
            WaitForClock(clk);
            wait for 0 ns;
          end if;

        end loop;

      end loop;

      tx_mac_fsm_i.transfer_status <= c_transmitted;
      WaitForClock(clk, 2);

    end loop;

    -- =====================================================================
    -- Test 3: Transfer status forwarding
    -- =====================================================================
    Print("-----------");
    Print("Test 3: Transfer status forwarding");
    Print("-----------");

    for status_idx in 0 to 4 loop

      case status_idx is
        when 0 => tx_mac_fsm_i.transfer_status <= c_ongoing;
        when 1 => tx_mac_fsm_i.transfer_status <= c_transmitted;
        when 2 => tx_mac_fsm_i.transfer_status <= c_disturbed;
        when 3 => tx_mac_fsm_i.transfer_status <= c_lost_arb;
        when 4 => tx_mac_fsm_i.transfer_status <= c_aborted;
        when others => null;
      end case;
      WaitForClock(clk);
      wait for 0 ns;

      AlertIf(test_id, llc_o.transfer_status /= tx_mac_fsm_i.transfer_status,
              "ERROR: transfer status not forwarded for index " & to_string(status_idx), FAILURE);

    end loop;

    -- -----------------------------------------------------------------------
    -- Done
    -- -----------------------------------------------------------------------
    reset <= '1';
    WaitForClock(clk, 5);
    ReportNonZeroAlerts;
    Print("");
    Print("==========================================");
    Print("All tests completed successfully!");
    Print("==========================================");
    EndOfTestReports(ReportAll => TRUE);
    std.env.finish;

    wait;

  end process main_tb_p;

end architecture tb;

-- eof
