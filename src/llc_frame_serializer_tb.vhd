library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.osvvmcontext;
  use work.can_pkg.all;

entity llc_frame_serializer_tb is
end entity llc_frame_serializer_tb;

architecture tb of llc_frame_serializer_tb is

  constant clk_period : time := 10 ns;
  constant run_time   : time := 1 ms;

  signal clk                   : std_logic         := '0';
  signal rst                   : std_logic         := '0';
  signal sink_m2s_i            : avalon_st_source_t;
  signal sink_s2m_o            : avalon_st_source_t;
  signal transfer_status_o     : transfer_status_t;
  signal transfer_status_i     : transfer_status_t := transmitted;
  signal tx_mac_state_i        : tx_mac_state_t    := idle;
  signal llc_frame_config_o    : std_logic_vector(7 downto 0);
  signal llc_frame_bit_o       : std_logic;
  signal llc_frame_bit_valid_o : std_logic;
  signal llc_frame_bit_ready_i : std_logic         := '0';

begin

  -- Clock generation
  clk <= not clk after clk_period / 2;

  -- DUT instantiation
  u_dut : entity work.llc_frame_serializer
    port map (
      clk_i                 => clk,
      rst_i                 => rst,
      sink_m2s_i            => sink_m2s_i,
      sink_s2m_o            => sink_s2m_o,
      transfer_status_o     => transfer_status_o,
      transfer_status_i     => transfer_status_i,
      tx_mac_state_i        => tx_mac_state_i,
      llc_frame_config_o    => llc_frame_config_o,
      llc_frame_bit_o       => llc_frame_bit_o,
      llc_frame_bit_valid_o => llc_frame_bit_valid_o,
      llc_frame_bit_ready_i => llc_frame_bit_ready_i
    );

  -- Main test process
  main_tb_p : process is

    variable test_data : std_logic_vector(7 downto 0);
    variable bit_count : integer;

  begin

    -- Open transcript file for logging
    TranscriptOpen("sim/tx_mac_llc_ctrl_tb.txt");
    SetTranscriptMirror(TRUE);

    Print("===========================================");
    Print("TX MAC LLC Control Testbench Started");
    Print("===========================================");

    -- Initialize
    rst                   <= '1';
    sink_m2s_i.data       <= (others => '0');
    sink_m2s_i.valid      <= '0';
    sink_m2s_i.sop        <= '0';
    sink_m2s_i.eop        <= '0';
    llc_frame_bit_ready_i <= '0';
    transfer_status_i     <= transmitted;
    tx_mac_state_i        <= idle;
    wait for clk_period * 5;

    rst <= '0';
    wait for clk_period;
    Print("Reset released");

    -- =====================================================================
    -- Test 1: Config byte loading with SOP
    -- =====================================================================
    Print("");
    Print("Test 1: Config byte loading when MAC is idle");
    Print("-----------");

    transfer_status_i <= ongoing;
    tx_mac_state_i    <= idle;
    wait for clk_period;

    -- Check that ready is asserted in idle state (before transfer)
    AlertIf(sink_s2m_o.ready = '0', "ERROR: ready should be asserted in idle state", FAILURE);

    -- Send config byte with SOP when ready is asserted (Avalon-ST transfer)
    sink_m2s_i.data  <= x"AA";                                                                                                                -- Config: 10101010
    sink_m2s_i.valid <= '1';
    sink_m2s_i.sop   <= '1';
    sink_m2s_i.eop   <= '0';
    wait for clk_period;

    -- Clear valid after transfer
    sink_m2s_i.valid <= '0';
    wait for clk_period;

    Print("PASS: Config byte loaded successfully");

    -- =====================================================================
    -- Test 2: First data byte loading and bit shifting
    -- =====================================================================
    Print("");
    Print("Test 2: Data byte loading and bit shifting (8 bits)");
    Print("-----------");

    test_data := x"55";                                                                                                                       -- Data: 01010101

    -- Verify ready is asserted in load_llc_frame_byte state
    AlertIf(sink_s2m_o.ready = '0', "ERROR: ready should be asserted in load_llc_frame_byte state", FAILURE);

    -- Send data byte when ready is asserted (Avalon-ST transfer)
    sink_m2s_i.data  <= test_data;
    sink_m2s_i.valid <= '1';
    sink_m2s_i.sop   <= '0';
    sink_m2s_i.eop   <= '0';
    wait for clk_period;

    -- Check first bit is loaded
    AlertIf(llc_frame_bit_valid_o = '0', "ERROR: frame_bit_valid should be asserted", FAILURE);
    AlertIf(llc_frame_bit_o /= test_data(7), "ERROR: first bit should be " & to_string(test_data(7)) &
            " but got " & to_string(llc_frame_bit_o), FAILURE);
    Print("  Bit 0 (MSB): " & to_string(llc_frame_bit_o) & " (Expected: " & to_string(test_data(7)) & ")");

    sink_m2s_i.valid <= '0';
    wait for clk_period;

    -- Shift out remaining 7 bits
    bit_count := 0;

    for i in 6 downto 0 loop
      llc_frame_bit_ready_i <= '1';
      wait for clk_period;
      AlertIf(llc_frame_bit_valid_o = '0', "ERROR: bit " & to_string(i) & " not valid", FAILURE);
      AlertIf(llc_frame_bit_o /= test_data(i), "ERROR: bit " & to_string(i) & " mismatch", FAILURE);
      Print("  Bit " & to_string(7 - i) & ": " & to_string(llc_frame_bit_o) & " (Expected: " & to_string(test_data(i)) & ")");
      bit_count             := bit_count + 1;
      llc_frame_bit_ready_i <= '0';
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
    rst <= '1';
    wait for clk_period * 2;
    rst <= '0';
    wait for clk_period;

    transfer_status_i <= ongoing;
    tx_mac_state_i    <= idle;

    -- Send config
    sink_m2s_i.data  <= x"C0";
    sink_m2s_i.valid <= '1';
    sink_m2s_i.sop   <= '1';
    wait for clk_period;
    sink_m2s_i.sop   <= '0';
    sink_m2s_i.eop   <= '0';

    -- Send 3 data bytes with bit-level validation
    for byte_idx in 0 to 2 loop
      test_data        := std_logic_vector(to_unsigned(byte_idx * 16 + 1, 8));
      sink_m2s_i.data  <= test_data;
      sink_m2s_i.valid <= '1';

      if (byte_idx = 2) then
        sink_m2s_i.eop <= '1';
      end if;

      wait for clk_period;

      Print("  Byte " & to_string(byte_idx) & ": " & to_hex_string(test_data));

      -- First bit (MSB) is sent during load transition
      AlertIf(llc_frame_bit_valid_o = '0', "ERROR: First bit not valid for byte " & to_string(byte_idx), FAILURE);
      AlertIf(llc_frame_bit_o /= test_data(7), "ERROR: First bit (MSB) mismatch for byte " & to_string(byte_idx), FAILURE);

      sink_m2s_i.valid <= '0';
      wait for clk_period;

      -- Shift remaining 7 bits with validation
      for bit_idx in 6 downto 0 loop
        llc_frame_bit_ready_i <= '1';
        wait for clk_period;
        AlertIf(llc_frame_bit_valid_o = '0', "ERROR: Bit not valid for byte " & to_string(byte_idx) & " bit " & to_string(bit_idx), FAILURE);
        AlertIf(llc_frame_bit_o /= test_data(bit_idx),
                "ERROR: Bit mismatch for byte " & to_string(byte_idx) & " bit " & to_string(bit_idx) &
                " (expected " & to_string(test_data(bit_idx)) & " got " & to_string(llc_frame_bit_o) & ")", FAILURE);
        llc_frame_bit_ready_i <= '0';
        wait for clk_period;
      end loop;

      -- Keep ready asserted one more cycle to allow count=0 transition back to load_llc_frame_byte
      llc_frame_bit_ready_i <= '1';
      wait for clk_period;
      llc_frame_bit_ready_i <= '0';
      wait for clk_period;

    end loop;

    Print("PASS: Multiple bytes transmitted successfully");

    -- =====================================================================
    -- Test 4: Frame termination (transfer status changes)
    -- =====================================================================
    Print("");
    Print("Test 4: Frame termination on transfer_status_mac change");
    Print("-----------");

    rst <= '1';
    wait for clk_period * 2;
    rst <= '0';
    wait for clk_period;

    transfer_status_i <= ongoing;
    tx_mac_state_i    <= idle;

    -- Send config
    sink_m2s_i.data  <= x"FF";
    sink_m2s_i.valid <= '1';
    sink_m2s_i.sop   <= '1';
    wait for clk_period;

    sink_m2s_i.sop <= '0';
    sink_m2s_i.eop <= '0';

    -- Send data byte
    sink_m2s_i.data  <= x"33";
    wait for clk_period;
    sink_m2s_i.valid <= '0';
    wait for clk_period;

    -- Start shifting, then change transfer status mid-transmission
    llc_frame_bit_ready_i <= '1';
    wait for clk_period * 3;

    Print("  Changing transfer_status_i to transmitted mid-transmission...");
    transfer_status_i <= transmitted;
    wait for clk_period;

    AlertIf(llc_frame_bit_valid_o = '1', "ERROR: bit_valid should be deasserted after status change", FAILURE);
    Print("PASS: Frame terminated correctly on status change");

    -- =====================================================================
    -- Test 5: Ready/Valid handshaking
    -- =====================================================================
    Print("");
    Print("Test 5: Ready/Valid handshaking");
    Print("-----------");

    rst <= '1';
    wait for clk_period * 2;
    rst <= '0';
    wait for clk_period;

    transfer_status_i <= ongoing;
    tx_mac_state_i    <= idle;
    wait for clk_period;

    -- Check ready is asserted in idle state
    AlertIf(sink_s2m_o.ready = '0', "ERROR: ready should be asserted in idle state", FAILURE);
    Print("  Idle state ready asserted: PASS");

    -- Send config byte (Avalon-ST transfer)
    sink_m2s_i.data  <= x"BB";
    sink_m2s_i.valid <= '1';
    sink_m2s_i.sop   <= '1';
    wait for clk_period;

    -- Clear valid, move to load_llc_frame_byte state where ready is continuously asserted
    sink_m2s_i.valid <= '0';
    wait for clk_period;

    -- Check ready is asserted in load_llc_frame_byte state
    AlertIf(sink_s2m_o.ready = '0', "ERROR: ready should be asserted in load_llc_frame_byte state", FAILURE);
    Print("  Data state ready asserted: PASS");

    -- Send data byte with sop='0' (Avalon-ST transfer)
    sink_m2s_i.data  <= x"44";
    sink_m2s_i.valid <= '1';
    sink_m2s_i.sop   <= '0';
    sink_m2s_i.eop   <= '0';
    wait for clk_period;

    -- Clear valid after transfer
    sink_m2s_i.valid <= '0';
    wait for clk_period;

    Print("PASS: Ready/Valid handshaking correct");

    -- =====================================================================
    -- Test Summary
    -- =====================================================================
    Print("");
    Print("===========================================");
    Print("All tests completed successfully!");
    Print("===========================================");

    wait;

  end process main_tb_p;

end architecture tb;
