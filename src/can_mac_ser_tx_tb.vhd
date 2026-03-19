library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.osvvmcontext;
  use work.pk_can_types.all;
  use work.can_protocol_pkg.all;

entity can_mac_ser_tx_tb is
end entity can_mac_ser_tx_tb;

architecture tb of can_mac_ser_tx_tb is

  constant clk_period : time := 10 ns;

  signal clk_i : std_logic := '0';
  signal rst_i : std_logic := '0';

  -- LLC interface signals
  signal llc_i : t_can_llc_mac_tx_if_s2d;
  signal llc_o : t_can_llc_mac_tx_if_d2s;

  -- can_mac_fsm_tx interface signals
  signal tx_mac_fsm_i : t_can_mac_ser_fsm_tx_if_m2s;
  signal tx_mac_fsm_o : t_can_mac_ser_fsm_tx_if_s2m;

begin

  -- Clock generation
  clk_i <= not clk_i after clk_period / 2;

  -- DUT instantiation
  u_dut : entity work.can_mac_ser_tx
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
    TranscriptOpen("sim/can_mac_ser_tx_tb.txt");
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
    tx_mac_fsm_i.transfer_status  <= c_transmitted;
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

    tx_mac_fsm_i.transfer_status  <= c_ongoing;
    wait for clk_period;

    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted in idle state", FAILURE);

    -- Send config byte 0 with SOP
    llc_i.avalon_st_source.data  <= x"C8";
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.sop   <= '1';
    llc_i.avalon_st_source.eop   <= '0';
    wait for clk_period;

    llc_i.avalon_st_source.valid <= '0';
    wait for clk_period;

    Print("  Config byte 0 loaded: x""C8""");

    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted waiting for config byte 1", FAILURE);

    -- Send config byte 1
    llc_i.avalon_st_source.data  <= x"50";
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.sop   <= '0';
    llc_i.avalon_st_source.eop   <= '0';
    wait for clk_period;

    llc_i.avalon_st_source.valid <= '0';
    wait for clk_period;

    Print("  Config byte 1 loaded: x""50""");

    -- Verify frame_params extraction
    -- Byte 0: x"C8" = 11001000 -> FORMAT[7:5]=110(FE), FTYP[4]=0, ESI[3]=1, BRS[2]=0
    -- Byte 1: x"50" = 01010000 -> DLC[7:4]=0101=5
    Print("  Verifying frame_params extraction:");
    AlertIf(tx_mac_fsm_o.llc_metadata.format /= c_llc_fmt_fe, "ERROR: FORMAT should be FE (110)", FAILURE);
    AlertIf(tx_mac_fsm_o.llc_metadata.is_remote_frame /= '0', "ERROR: is_remote_frame should be 0", FAILURE);
    AlertIf(tx_mac_fsm_o.llc_metadata.esi_enable /= '1', "ERROR: ESI should be 1", FAILURE);
    AlertIf(tx_mac_fsm_o.llc_metadata.has_brs /= '0', "ERROR: BRS should be 0", FAILURE);
    AlertIf(to_integer(unsigned(tx_mac_fsm_o.llc_metadata.dlc_vector)) /= 5, "ERROR: DLC should be 5", FAILURE);
    Print("    FORMAT: FE [PASS]");
    Print("    FTYP: data_frame [PASS]");
    Print("    ESI: 1 [PASS]");
    Print("    BRS: 0 [PASS]");
    Print("    DLC: 5 [PASS]");
    Print("PASS: Both config bytes loaded successfully");

    -- =====================================================================
    -- Test 2: First data byte loading and bit shifting
    -- =====================================================================
    Print("");
    Print("Test 2: Data byte loading and bit shifting (8 bits)");
    Print("-----------");

    test_data := x"F0";

    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted in load_llc_frame_byte state", FAILURE);

    llc_i.avalon_st_source.data  <= test_data;
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.sop   <= '0';
    llc_i.avalon_st_source.eop   <= '0';
    wait for clk_period;

    AlertIf(tx_mac_fsm_o.valid = '0', "ERROR: frame_bit_valid should be asserted", FAILURE);
    AlertIf(tx_mac_fsm_o.data /= test_data(7), "ERROR: first bit should be " & to_string(test_data(7)) &
            " but got " & to_string(tx_mac_fsm_o.data), FAILURE);
    Print("  Bit 0 (MSB): " & to_string(tx_mac_fsm_o.data) & " (Expected: " & to_string(test_data(7)) & ")");

    llc_i.avalon_st_source.valid <= '0';
    wait for clk_period;

    bit_count := 0;

    for i in 6 downto 0 loop
      tx_mac_fsm_i.ready <= '1';
      wait for clk_period;
      tx_mac_fsm_i.ready <= '0';
      wait for clk_period;
      AlertIf(tx_mac_fsm_o.valid = '0', "ERROR: bit " & to_string(i) & " not valid", FAILURE);
      AlertIf(tx_mac_fsm_o.data /= test_data(i), "ERROR: bit " & to_string(i) & " mismatch", FAILURE);
      Print("  Bit " & to_string(7 - i) & ": " & to_string(tx_mac_fsm_o.data) & " (Expected: " & to_string(test_data(i)) & ")");
      bit_count := bit_count + 1;
    end loop;

    AlertIf(bit_count /= 7, "ERROR: Expected 7 bits shifted, got " & to_string(bit_count), FAILURE);
    Print("PASS: All 8 bits shifted correctly");

    -- =====================================================================
    -- Test 3: Multiple data bytes
    -- =====================================================================
    Print("");
    Print("Test 3: Multiple data bytes transmission");
    Print("-----------");

    rst_i <= '1';
    wait for clk_period * 2;
    rst_i <= '0';
    wait for clk_period;

    tx_mac_fsm_i.transfer_status  <= c_ongoing;

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

    -- Byte 0: x"C0" = 11000000 -> FORMAT[7:5]=110(FE), FTYP[4]=0, ESI[3]=0, BRS[2]=0
    -- Byte 1: x"30" = 00110000 -> DLC[7:4]=0011=3
    Print("  Verifying frame_info extraction:");
    AlertIf(tx_mac_fsm_o.llc_metadata.format /= c_llc_fmt_fe, "ERROR: FORMAT should be FE (110)", FAILURE);
    AlertIf(tx_mac_fsm_o.llc_metadata.is_remote_frame /= '0', "ERROR: FTYP should be 0", FAILURE);
    AlertIf(tx_mac_fsm_o.llc_metadata.esi_enable /= '0', "ERROR: ESI should be 0", FAILURE);
    AlertIf(tx_mac_fsm_o.llc_metadata.has_brs /= '0', "ERROR: BRS should be 0", FAILURE);
    AlertIf(to_integer(unsigned(tx_mac_fsm_o.llc_metadata.dlc_vector)) /= 3, "ERROR: DLC should be 3", FAILURE);
    Print("    FORMAT: FE [PASS]");
    Print("    FTYP: data_frame [PASS]");
    Print("    ESI: 0 [PASS]");
    Print("    BRS: 0 [PASS]");
    Print("    DLC: 3 [PASS]");

    for byte_idx in 0 to 2 loop
      test_data                    := std_logic_vector(to_unsigned(byte_idx * 16 + 1, 8));
      llc_i.avalon_st_source.data  <= test_data;
      llc_i.avalon_st_source.valid <= '1';

      if (byte_idx = 2) then
        llc_i.avalon_st_source.eop <= '1';
      end if;

      wait for clk_period;

      Print("  Byte " & to_string(byte_idx) & ": " & to_hex_string(test_data));

      AlertIf(tx_mac_fsm_o.valid = '0', "ERROR: First bit not valid for byte " & to_string(byte_idx), FAILURE);
      AlertIf(tx_mac_fsm_o.data /= test_data(7), "ERROR: First bit (MSB) mismatch for byte " & to_string(byte_idx), FAILURE);

      llc_i.avalon_st_source.valid <= '0';
      wait for clk_period;

      for bit_idx in 6 downto 0 loop
        tx_mac_fsm_i.ready <= '1';
        wait for clk_period;
        tx_mac_fsm_i.ready <= '0';
        wait for clk_period;
        AlertIf(tx_mac_fsm_o.valid = '0', "ERROR: Bit not valid for byte " & to_string(byte_idx) & " bit " & to_string(bit_idx), FAILURE);
        AlertIf(tx_mac_fsm_o.data /= test_data(bit_idx),
                "ERROR: Bit mismatch for byte " & to_string(byte_idx) & " bit " & to_string(bit_idx) &
                " (expected " & to_string(test_data(bit_idx)) & " got " & to_string(tx_mac_fsm_o.data) & ")", FAILURE);
      end loop;

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

    tx_mac_fsm_i.transfer_status  <= c_ongoing;

    llc_i.avalon_st_source.data  <= x"5F";
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.sop   <= '1';
    wait for clk_period;

    llc_i.avalon_st_source.data  <= x"F0";
    llc_i.avalon_st_source.sop   <= '0';
    wait for clk_period;
    llc_i.avalon_st_source.valid <= '0';
    wait for clk_period;

    -- Byte 0: x"5F" = 01011111 -> FORMAT[7:5]=010 (FB), FTYP[4]=1, ESI[3]=1, BRS[2]=1
    -- Byte 1: x"F0" = 11110000 -> DLC[7:4]=1111=15
    Print("  Verifying frame_info extraction:");
    AlertIf(tx_mac_fsm_o.llc_metadata.format /= c_llc_fmt_fb, "ERROR: FORMAT should be FB (010) but got " & to_hex_string(tx_mac_fsm_o.llc_metadata.format), FAILURE);
    AlertIf(tx_mac_fsm_o.llc_metadata.is_remote_frame /= '1', "ERROR: FTYP should be 1", FAILURE);
    AlertIf(tx_mac_fsm_o.llc_metadata.esi_enable /= '1', "ERROR: ESI should be 1", FAILURE);
    AlertIf(tx_mac_fsm_o.llc_metadata.has_brs /= '1', "ERROR: BRS should be 1", FAILURE);
    AlertIf(to_integer(unsigned(tx_mac_fsm_o.llc_metadata.dlc_vector)) /= 15, "ERROR: DLC should be 15", FAILURE);
    Print("    FORMAT: FB [PASS]");
    Print("    FTYP: remote_frame [PASS]");
    Print("    ESI: 1 [PASS]");
    Print("    BRS: 1 [PASS]");
    Print("    DLC: 15 [PASS]");

    llc_i.avalon_st_source.data  <= x"33";
    llc_i.avalon_st_source.valid <= '1';
    wait for clk_period;
    llc_i.avalon_st_source.valid <= '0';
    wait for clk_period;

    tx_mac_fsm_i.ready <= '1';
    wait for clk_period * 3;

    Print("  Changing transfer_status to transmitted mid-transmission...");
    tx_mac_fsm_i.transfer_status <= c_transmitted;
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

    tx_mac_fsm_i.transfer_status  <= c_ongoing;
    wait for clk_period;

    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted in idle state", FAILURE);
    Print("  Idle state ready asserted: PASS");

    llc_i.avalon_st_source.data  <= x"BB";
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.sop   <= '1';
    wait for clk_period;

    llc_i.avalon_st_source.valid <= '0';
    wait for clk_period;

    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted in load_config_byte_1 state", FAILURE);
    Print("  Config byte 1 state ready asserted: PASS");

    llc_i.avalon_st_source.data  <= x"44";
    llc_i.avalon_st_source.valid <= '1';
    llc_i.avalon_st_source.sop   <= '0';
    llc_i.avalon_st_source.eop   <= '0';
    wait for clk_period;

    llc_i.avalon_st_source.valid <= '0';
    wait for clk_period;

    AlertIf(llc_o.avalon_st_sink.ready = '0', "ERROR: ready should be asserted in load_llc_frame_byte state", FAILURE);
    Print("  Data state ready asserted: PASS");

    Print("PASS: Ready/Valid handshaking correct");

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
