library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.osvvmcontext;
  use work.can_pkg.all;

entity tx_mac_ser_tb is
end entity tx_mac_ser_tb;

architecture tb of tx_mac_ser_tb is

  constant clk_period : time := 10 ns;

  signal clk_i : std_logic := '0';
  signal rst_i : std_logic := '0';

  -- LLC interface signals
  signal llc_i : llc_to_mac_if_t;
  signal llc_o : mac_to_llc_if_t;

  -- tx_mac_fsm interface signals
  signal tx_mac_fsm_i : tx_mac_fsm_to_ser_if_t;
  signal tx_mac_fsm_o : tx_mac_ser_to_fsm_if_t;

begin

  -- Clock generation
  clk_i <= not clk_i after clk_period / 2;

  -- DUT instantiation
  u_dut : entity work.tx_mac_ser
    port map (
      clk_i        => clk_i,
      rst_i        => rst_i,
      llc_i        => llc_i,
      llc_o        => llc_o,
      tx_mac_fsm_i => tx_mac_fsm_i,
      tx_mac_fsm_o => tx_mac_fsm_o
    );

  -- Main test process
  main_tb_p : process is

    variable test_data : std_logic_vector(7 downto 0);
    variable bit_count : integer;

  begin

    -- Open transcript file for logging
    TranscriptOpen("sim/tx_mac_ser_tb.txt");
    SetTranscriptMirror(TRUE);

    Print("==========================================");
    Print("TX MAC Serializer Testbench Started");
    Print("==========================================");

    -- Initialize
    rst_i                         <= '1';
    llc_i.avalon_st_source.data   <= (others => '0');
    llc_i.avalon_st_source.valid  <= '0';
    llc_i.avalon_st_source.sop    <= '0';
    llc_i.avalon_st_source.eop    <= '0';
    tx_mac_fsm_i.ready            <= '0';
    tx_mac_fsm_i.transfer_status  <= transmitted;
    tx_mac_fsm_i.tx_mac_fsm_state <= idle;
    wait for clk_period * 5;

    rst_i <= '0';
    wait for clk_period;
    Print("Reset released");

    -- =====================================================================
    -- Test 1: Config byte loading (2 bytes with SOP)
    -- =====================================================================
    Print("");
    Print("Test 1: Load two config bytes when MAC FSM is idle");
    Print("-----------");

    tx_mac_fsm_i.transfer_status  <= ongoing;
    tx_mac_fsm_i.tx_mac_fsm_state <= idle;
    wait for clk_period;

    -- Check that ready is asserted in idle state
    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted in idle state", FAILURE);

    -- Send config byte 0 with SOP (Avalon-ST transfer)
    llc_i.avalon_st_source.data  <= x"C8";                                                                                                           -- Config byte 0: 11001000 → FORMAT[7:5]=110(fd_extended), FTYP[4]=0, ESI[3]=1, BRS[2]=0
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.sop   <= '1';
    llc_i.avalon_st_source.eop   <= '0';
    wait for clk_period;

    -- Clear valid after transfer
    llc_i.avalon_st_source.valid <= '0';
    wait for clk_period;

    Print("  Config byte 0 loaded: x""C8""");

    -- Check that ready is still asserted (waiting for config byte 1)
    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted waiting for config byte 1", FAILURE);

    -- Send config byte 1 with SOP='0' (Avalon-ST transfer)
    llc_i.avalon_st_source.data  <= x"50";                                                                                                           -- Config byte 1: 01010000 → DLC[7:4]=0101=5
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.sop   <= '0';
    llc_i.avalon_st_source.eop   <= '0';
    wait for clk_period;

    -- Clear valid after transfer
    llc_i.avalon_st_source.valid <= '0';
    wait for clk_period;

    Print("  Config byte 1 loaded: x""50""");

    -- Verify frame_info extraction
    -- Byte 0: x"C8" = 11001000 → FORMAT[7:5]=110(fd_extended), FTYP[4]=0, ESI[3]=1, BRS[2]=0
    -- Byte 1: x"50" = 01010000 → DLC[7:4]=0101=5
    Print("  Verifying frame_info extraction:");
    AlertIf(tx_mac_fsm_o.frame_info.format /= fd_extended, "ERROR: FORMAT should be fd_extended (110)", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_info.ftyp /= data_frame, "ERROR: FTYP should be data_frame (0)", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_info.esi_enable /= true, "ERROR: ESI should be true (1)", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_info.brs_enable /= false, "ERROR: BRS should be false (0)", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_info.dlc /= 5, "ERROR: DLC should be 5", FAILURE);
    Print("    FORMAT: fd_extended [PASS]");
    Print("    FTYP: data_frame [PASS]");
    Print("    ESI: true [PASS]");
    Print("    BRS: false [PASS]");
    Print("    DLC: 5 [PASS]");
    Print("PASS: Both config bytes loaded successfully");

    -- =====================================================================
    -- Test 2: First data byte loading and bit shifting
    -- =====================================================================
    Print("");
    Print("Test 2: Data byte loading and bit shifting (8 bits)");
    Print("-----------");

    test_data := x"F0";                                                                                                                              -- Data: 11110000

    -- Verify ready is asserted in load_llc_frame_byte state
    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted in load_llc_frame_byte state", FAILURE);

    -- Send data byte when ready is asserted (Avalon-ST transfer)
    llc_i.avalon_st_source.data  <= test_data;
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.sop   <= '0';
    llc_i.avalon_st_source.eop   <= '0';
    wait for clk_period;

    -- Check first bit is loaded
    AlertIf(tx_mac_fsm_o.valid = '0', "ERROR: frame_bit_valid should be asserted", FAILURE);
    AlertIf(tx_mac_fsm_o.data /= test_data(7), "ERROR: first bit should be " & to_string(test_data(7)) &
            " but got " & to_string(tx_mac_fsm_o.data), FAILURE);
    Print("  Bit 0 (MSB): " & to_string(tx_mac_fsm_o.data) & " (Expected: " & to_string(test_data(7)) & ")");

    llc_i.avalon_st_source.valid <= '0';
    wait for clk_period;

    -- Shift out remaining 7 bits
    bit_count := 0;

    for i in 6 downto 0 loop
      tx_mac_fsm_i.ready <= '1';
      wait for clk_period;
      AlertIf(tx_mac_fsm_o.valid = '0', "ERROR: bit " & to_string(i) & " not valid", FAILURE);
      AlertIf(tx_mac_fsm_o.data /= test_data(i), "ERROR: bit " & to_string(i) & " mismatch", FAILURE);
      Print("  Bit " & to_string(7 - i) & ": " & to_string(tx_mac_fsm_o.data) & " (Expected: " & to_string(test_data(i)) & ")");
      bit_count          := bit_count + 1;
      tx_mac_fsm_i.ready <= '0';
      wait for clk_period;
    end loop;

    AlertIf(bit_count /= 7, "ERROR: Expected 7 bits shifted, got " & to_string(bit_count), FAILURE);
    Print("PASS: All 8 bits shifted correctly");

    -- =====================================================================
    -- Test 3: Multiple data bytes
    -- =====================================================================
    Print("");
    Print("Test 3: Multiple data bytes transmission");
    Print("-----------");

    -- Reset for next test
    rst_i <= '1';
    wait for clk_period * 2;
    rst_i <= '0';
    wait for clk_period;

    tx_mac_fsm_i.transfer_status  <= ongoing;
    tx_mac_fsm_i.tx_mac_fsm_state <= idle;

    -- Send config bytes
    llc_i.avalon_st_source.data  <= x"C0";
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.sop   <= '1';
    wait for clk_period;

    llc_i.avalon_st_source.data  <= x"30";
    llc_i.avalon_st_source.sop   <= '0';
    llc_i.avalon_st_source.eop   <= '0';
    wait for clk_period;
    llc_i.avalon_st_source.valid <= '0';
    wait for clk_period;

    -- Verify frame_info extraction
    -- Byte 0: x"C0" = 11000000 → FORMAT[7:5]=110, FTYP[4]=0, ESI[3]=0, BRS[2]=0
    -- Byte 1: x"30" = 00110000 → DLC[7:4]=0011=3
    Print("  Verifying frame_info extraction:");
    AlertIf(tx_mac_fsm_o.frame_info.format /= fd_extended, "ERROR: FORMAT should be fd_extended (110)", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_info.ftyp /= data_frame, "ERROR: FTYP should be data_frame (0)", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_info.esi_enable /= false, "ERROR: ESI should be false (0)", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_info.brs_enable /= false, "ERROR: BRS should be false (0)", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_info.dlc /= 3, "ERROR: DLC should be 3", FAILURE);
    Print("    FORMAT: fd_extended [PASS]");
    Print("    FTYP: data_frame [PASS]");
    Print("    ESI: false [PASS]");
    Print("    BRS: false [PASS]");
    Print("    DLC: 3 [PASS]");

    -- Send 3 data bytes with bit-level validation
    for byte_idx in 0 to 2 loop
      test_data                    := std_logic_vector(to_unsigned(byte_idx * 16 + 1, 8));
      llc_i.avalon_st_source.data  <= test_data;
      llc_i.avalon_st_source.valid <= '1';

      if (byte_idx = 2) then
        llc_i.avalon_st_source.eop <= '1';
      end if;

      wait for clk_period;

      Print("  Byte " & to_string(byte_idx) & ": " & to_hex_string(test_data));

      -- First bit (MSB) is sent during load transition
      AlertIf(tx_mac_fsm_o.valid = '0', "ERROR: First bit not valid for byte " & to_string(byte_idx), FAILURE);
      AlertIf(tx_mac_fsm_o.data /= test_data(7), "ERROR: First bit (MSB) mismatch for byte " & to_string(byte_idx), FAILURE);

      llc_i.avalon_st_source.valid <= '0';
      wait for clk_period;

      -- Shift remaining 7 bits with validation
      for bit_idx in 6 downto 0 loop
        tx_mac_fsm_i.ready <= '1';
        wait for clk_period;
        AlertIf(tx_mac_fsm_o.valid = '0', "ERROR: Bit not valid for byte " & to_string(byte_idx) & " bit " & to_string(bit_idx), FAILURE);
        AlertIf(tx_mac_fsm_o.data /= test_data(bit_idx),
                "ERROR: Bit mismatch for byte " & to_string(byte_idx) & " bit " & to_string(bit_idx) &
                " (expected " & to_string(test_data(bit_idx)) & " got " & to_string(tx_mac_fsm_o.data) & ")", FAILURE);
        tx_mac_fsm_i.ready <= '0';
        wait for clk_period;
      end loop;

      -- Keep ready asserted one more cycle to allow count=0 transition back to load_llc_frame_byte
      tx_mac_fsm_i.ready <= '1';
      wait for clk_period;
      tx_mac_fsm_i.ready <= '0';
      wait for clk_period;

    end loop;

    Print("PASS: Multiple bytes transmitted successfully");

    -- =====================================================================
    -- Test 4: Frame termination (transfer status changes)
    -- =====================================================================
    Print("");
    Print("Test 4: Frame termination on transfer_status change");
    Print("-----------");

    rst_i <= '1';
    wait for clk_period * 2;
    rst_i <= '0';
    wait for clk_period;

    tx_mac_fsm_i.transfer_status  <= ongoing;
    tx_mac_fsm_i.tx_mac_fsm_state <= idle;

    -- Send config bytes
    llc_i.avalon_st_source.data  <= x"FF";
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.sop   <= '1';
    wait for clk_period;

    llc_i.avalon_st_source.data  <= x"F0";
    llc_i.avalon_st_source.sop   <= '0';
    wait for clk_period;
    llc_i.avalon_st_source.valid <= '0';
    wait for clk_period;

    -- Verify frame_info extraction
    -- Byte 0: x"FF" = 11111111 → FORMAT[7:5]=111, FTYP[4]=1, ESI[3]=1, BRS[2]=1
    -- Byte 1: x"F0" = 11110000 → DLC[7:4]=1111=15
    Print("  Verifying frame_info extraction:");
    AlertIf(tx_mac_fsm_o.frame_info.format /= unknown, "ERROR: FORMAT should be unknown (111)", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_info.ftyp /= remote_frame, "ERROR: FTYP should be remote_frame (1)", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_info.esi_enable /= true, "ERROR: ESI should be true (1)", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_info.brs_enable /= true, "ERROR: BRS should be true (1)", FAILURE);
    AlertIf(tx_mac_fsm_o.frame_info.dlc /= 15, "ERROR: DLC should be 15", FAILURE);
    Print("    FORMAT: unknown [PASS]");
    Print("    FTYP: remote_frame [PASS]");
    Print("    ESI: true [PASS]");
    Print("    BRS: true [PASS]");
    Print("    DLC: 15 [PASS]");

    -- Send data byte
    llc_i.avalon_st_source.data  <= x"33";
    llc_i.avalon_st_source.valid <= '1';
    wait for clk_period;
    llc_i.avalon_st_source.valid <= '0';
    wait for clk_period;

    -- Start shifting, then change transfer status mid-transmission
    tx_mac_fsm_i.ready <= '1';
    wait for clk_period * 3;

    Print("  Changing transfer_status to transmitted mid-transmission...");
    tx_mac_fsm_i.transfer_status <= transmitted;
    wait for clk_period;

    AlertIf(tx_mac_fsm_o.valid = '1', "ERROR: bit_valid should be deasserted after status change", FAILURE);
    Print("PASS: Frame terminated correctly on status change");

    -- =====================================================================
    -- Test 5: Ready/Valid handshaking
    -- =====================================================================
    Print("");
    Print("Test 5: Ready/Valid handshaking");
    Print("-----------");

    rst_i <= '1';
    wait for clk_period * 2;
    rst_i <= '0';
    wait for clk_period;

    tx_mac_fsm_i.transfer_status  <= ongoing;
    tx_mac_fsm_i.tx_mac_fsm_state <= idle;
    wait for clk_period;

    -- Check ready is asserted in idle state
    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted in idle state", FAILURE);
    Print("  Idle state ready asserted: PASS");

    -- Send config byte 0 (Avalon-ST transfer)
    llc_i.avalon_st_source.data  <= x"BB";
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.sop   <= '1';
    wait for clk_period;

    -- Clear valid, move to load_config_byte_1 state where ready is continuously asserted
    llc_i.avalon_st_source.valid <= '0';
    wait for clk_period;

    -- Check ready is asserted in load_config_byte_1 state
    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted in load_config_byte_1 state", FAILURE);
    Print("  Config byte 1 state ready asserted: PASS");

    -- Send config byte 1 with sop='0' (Avalon-ST transfer)
    llc_i.avalon_st_source.data  <= x"44";
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.sop   <= '0';
    llc_i.avalon_st_source.eop   <= '0';
    wait for clk_period;

    -- Clear valid after transfer
    llc_i.avalon_st_source.valid <= '0';
    wait for clk_period;

    -- Check ready is asserted in load_llc_frame_byte state
    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted in load_llc_frame_byte state", FAILURE);
    Print("  Data state ready asserted: PASS");

    Print("PASS: Ready/Valid handshaking correct");

    -- =====================================================================
    -- Test 6: FSM state-dependent ready logic
    -- =====================================================================
    Print("");
    Print("Test 6: FSM state-dependent ready signal");
    Print("-----------");

    rst_i <= '1';
    wait for clk_period * 2;
    rst_i <= '0';
    wait for clk_period;

    -- Start in idle state
    tx_mac_fsm_i.transfer_status  <= ongoing;
    tx_mac_fsm_i.tx_mac_fsm_state <= idle;
    wait for clk_period;

    -- Verify ready is asserted when FSM is idle (config byte 0 state)
    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted when FSM is idle", FAILURE);
    Print("  Ready asserted in idle state: PASS");

    -- Send config byte 0
    llc_i.avalon_st_source.data  <= x"AA";
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.sop   <= '1';
    wait for clk_period;
    llc_i.avalon_st_source.valid <= '0';
    wait for clk_period;

    -- Now change FSM state to transmitting_mac_frame (simulating unexpected FSM change)
    -- This should trigger fail-fast reset to load_config_byte_0
    tx_mac_fsm_i.tx_mac_fsm_state <= transmitting;
    wait for clk_period;

    AlertIf(llc_o.avalon_st_sink.ready = '1', "ERROR: ready should NOT be asserted when FSM is transmitting_mac_frame during config load", FAILURE);
    Print("  Ready deasserted when FSM leaves idle state: PASS");

    -- Return FSM to idle state (should restart from config byte 0 now)
    tx_mac_fsm_i.tx_mac_fsm_state <= idle;
    wait for clk_period;

    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted when FSM returns to idle (back in config byte 0)", FAILURE);
    Print("  Ready re-asserted when FSM returns to idle: PASS");

    -- Send config bytes again after fail-fast recovery
    llc_i.avalon_st_source.data  <= x"22";
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.sop   <= '1';
    wait for clk_period;
    llc_i.avalon_st_source.valid <= '0';
    wait for clk_period;

    -- Send config byte 1
    llc_i.avalon_st_source.data  <= x"33";
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.sop   <= '0';
    wait for clk_period;
    llc_i.avalon_st_source.valid <= '0';
    wait for clk_period;

    -- Now in load_llc_frame_byte state, verify ready IS asserted when FSM is transmitting_mac_frame
    tx_mac_fsm_i.tx_mac_fsm_state <= transmitting,;
    wait for clk_period;

    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted when FSM is transmitting_mac_frame for data load", FAILURE);
    Print("  Ready asserted for data load when FSM is transmitting: PASS");

    -- Change FSM to a different state (not idle, not transmitting_mac_frame)
    -- Simulate FSM in transmitting_error_flag state
    tx_mac_fsm_i.tx_mac_fsm_state <= transmitting_error_flag;
    wait for clk_period;

    AlertIf(llc_o.avalon_st_sink.ready = '1', "ERROR: ready should NOT be asserted when FSM is transmitting_error_flag", FAILURE);
    Print("  Ready deasserted when FSM is in transmitting_error_flag state: PASS");

    -- Return FSM to idle
    tx_mac_fsm_i.tx_mac_fsm_state <= idle;
    wait for clk_period;

    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted when FSM returns to idle", FAILURE);
    Print("  Ready re-asserted when FSM returns to idle: PASS");

    Print("PASS: FSM state-dependent ready logic correct");

    -- =====================================================================
    -- Test Summary
    -- =====================================================================
    Print("");
    Print("==========================================");
    Print("All tests completed successfully!");
    Print("==========================================");

    wait;

  end process main_tb_p;

end architecture tb;
