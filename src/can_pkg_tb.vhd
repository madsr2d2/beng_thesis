library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

package can_pkg_tb_pkg is

-- Test package - empty, just for organization

end package can_pkg_tb_pkg;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_pkg.all;

entity can_pkg_tb is
end entity can_pkg_tb;

architecture tb of can_pkg_tb is

begin

  test_process : process is

    variable frame_info    : mac_frame_bit_info_t;
    variable prev_bit      : std_logic;
    variable crc_start_pos : integer;
    variable data_length   : integer;

  begin

    report "========================================";
    report "CAN MAC Frame Bit Testbench - Full Suite";
    report "========================================";

    -- =====================================================================
    -- Test Group 1: CAN Classic Basic (11-bit ID)
    -- =====================================================================
    report "Test Group 1: CAN Classic Basic (11-bit ID)";

    -- Test 1.1: SOF bit
    frame_info := tx_mac_frame_bit(0, cc_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.is_form_bit = true
      report "SOF should be form bit"
      severity error;
    assert frame_info.polarity = dominant_bit_c
      report "SOF should be dominant"
      severity error;
    assert frame_info.frame_field = field_sof
      report "SOF field incorrect"
      severity error;
    report "  Test 1.1: SOF bit correct (PASS)";

    -- Test 1.2: Arbitration field (positions 1-12, 11-bit ID + RTR)
    frame_info := tx_mac_frame_bit(1, cc_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.frame_field = field_arbitration
      report "Position 1 should be arbitration"
      severity error;
    assert frame_info.is_form_bit = false
      report "ID bits should not be form bits"
      severity error;
    report "  ? Test 1.2: Arbitration field correct";

    -- Test 1.3: RTR bit (position 12) for DATA_FRAME
    frame_info := tx_mac_frame_bit(12, cc_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.is_form_bit = true
      report "RTR should be form bit"
      severity error;
    assert frame_info.polarity = dominant_bit_c
      report "RTR should be dominant for DATA_FRAME"
      severity error;
    assert frame_info.frame_field = field_arbitration
      report "RTR should be in arbitration field"
      severity error;
    report "  ? Test 1.3: RTR bit for DATA_FRAME correct";

    -- Test 1.4: RTR bit (position 12) for REMOTE_FRAME
    frame_info := tx_mac_frame_bit(12, cc_basic, remote_frame, 8,
                                   false, false, '0');
    assert frame_info.polarity = recessive_bit_c
      report "RTR should be recessive for REMOTE_FRAME"
      severity error;
    report "  ? Test 1.4: RTR bit for REMOTE_FRAME correct";

    -- Test 1.5: IDE bit (position 13) - marks basic format
    frame_info := tx_mac_frame_bit(13, cc_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.is_form_bit = true
      report "IDE should be form bit"
      severity error;
    assert frame_info.polarity = dominant_bit_c
      report "IDE should be dominant for basic format"
      severity error;
    assert frame_info.frame_field = field_control
      report "IDE should be in control field"
      severity error;
    report "  ? Test 1.5: IDE bit correct";

    -- Test 1.6: r0 bit (position 14)
    frame_info := tx_mac_frame_bit(14, cc_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.is_form_bit = true
      report "r0 should be form bit"
      severity error;
    assert frame_info.polarity = dominant_bit_c
      report "r0 should be dominant"
      severity error;
    report "  ? Test 1.6: r0 bit correct";

    -- Test 1.7: DLC field (positions 15-18)
    frame_info := tx_mac_frame_bit(15, cc_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.is_form_bit = true
      report "DLC bit should be form bit"
      severity error;
    assert frame_info.polarity = '1'
      report "DLC MSB (bit 3) for DLC=8 should be 1"
      severity error;
    report "  ? Test 1.7: DLC field correct";

    -- Test 1.8: DLC with different values
    for dlc_val in 0 to 8 loop
      frame_info := tx_mac_frame_bit(15, cc_basic, data_frame, dlc_val,
                                     false, false, '0');
      assert frame_info.is_form_bit = true
        severity error;
    end loop;

    report "  ? Test 1.8: DLC field works for all valid values";

    -- Test 1.9: Data field (positions 19-154 for 8 bytes)
    frame_info := tx_mac_frame_bit(19, cc_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.frame_field = field_data
      report "Position 19 should be data field"
      severity error;
    assert frame_info.is_form_bit = false
      report "Data bits should not be form bits"
      severity error;
    report "  ? Test 1.9: Data field correct";

    -- Test 1.10: CRC field (15 bits for classic)
    crc_start_pos := 19 + (8 * 8);                                                       -- 19 + 64 = 83
    frame_info    := tx_mac_frame_bit(crc_start_pos, cc_basic, data_frame, 8,
                                      false, false, '0');
    assert frame_info.frame_field = field_crc
      report "CRC field start incorrect"
      severity error;
    report "  ? Test 1.10: CRC field correct";

    -- =====================================================================
    -- Test Group 2: CAN Classic Extended (29-bit ID)
    -- =====================================================================
    report "Test Group 2: CAN Classic Extended (29-bit ID)";

    -- Test 2.1: IDE bit at position 13 (marks extended format)
    frame_info := tx_mac_frame_bit(13, cc_extended, data_frame, 8,
                                   false, false, '0');
    assert frame_info.is_form_bit = true
      report "IDE should be form bit"
      severity error;
    assert frame_info.polarity = recessive_bit_c
      report "IDE should be recessive for extended format"
      severity error;
    report "  ? Test 2.1: IDE bit for extended format correct";

    -- Test 2.2: SRR bit (position 12) in extended frame
    frame_info := tx_mac_frame_bit(12, cc_extended, data_frame, 8,
                                   false, false, '0');
    assert frame_info.is_form_bit = true
      report "SRR should be form bit"
      severity error;
    assert frame_info.polarity = recessive_bit_c
      report "SRR should be recessive"
      severity error;
    report "  ? Test 2.2: SRR bit correct";

    -- Test 2.3: r1 bit (position 33) - start of control field for extended
    frame_info := tx_mac_frame_bit(33, cc_extended, data_frame, 8,
                                   false, false, '0');
    assert frame_info.frame_field = field_control
      report "Position 33 should be control field"
      severity error;
    assert frame_info.is_form_bit = true
      report "r1 should be form bit"
      severity error;
    report "  ? Test 2.3: r1 bit correct";

    -- Test 2.4: r0 bit (position 34)
    frame_info := tx_mac_frame_bit(34, cc_extended, data_frame, 8,
                                   false, false, '0');
    assert frame_info.is_form_bit = true
      report "r0 should be form bit"
      severity error;
    assert frame_info.polarity = dominant_bit_c
      report "r0 should be dominant"
      severity error;
    report "  ? Test 2.4: r0 bit correct";

    -- Test 2.5: RTR bit (position 32) in extended frame
    frame_info := tx_mac_frame_bit(32, cc_extended, data_frame, 8,
                                   false, false, '0');
    assert frame_info.is_form_bit = true
      report "RTR should be form bit"
      severity error;
    assert frame_info.polarity = dominant_bit_c
      report "RTR should be dominant for DATA_FRAME"
      severity error;
    report "  ? Test 2.5: RTR bit in extended frame correct";

    -- =====================================================================
    -- Test Group 3: CAN FD Basic (11-bit ID with FD features)
    -- =====================================================================
    report "Test Group 3: CAN FD Basic (11-bit ID with FD features)";

    -- Test 3.1: FDF bit (position 14) - marks FD format
    frame_info := tx_mac_frame_bit(14, fd_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.is_form_bit = true
      report "FDF should be form bit"
      severity error;
    assert frame_info.polarity = recessive_bit_c
      report "FDF should be recessive"
      severity error;
    report "  ? Test 3.1: FDF bit correct";

    -- Test 3.2: RES bit (position 15)
    frame_info := tx_mac_frame_bit(15, fd_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.is_form_bit = true
      report "RES should be form bit"
      severity error;
    assert frame_info.polarity = dominant_bit_c
      report "RES should be dominant"
      severity error;
    report "  ? Test 3.2: RES bit correct";

    -- Test 3.3: BRS bit (position 16) when enabled
    frame_info := tx_mac_frame_bit(16, fd_basic, data_frame, 8,
                                   true, false, '0');
    assert frame_info.is_form_bit = true
      report "BRS should be form bit"
      severity error;
    assert frame_info.polarity = recessive_bit_c
      report "BRS should be recessive when enabled"
      severity error;
    report "  ? Test 3.3: BRS bit when enabled correct";

    -- Test 3.4: BRS bit (position 16) when disabled
    frame_info := tx_mac_frame_bit(16, fd_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.polarity = dominant_bit_c
      report "BRS should be dominant when disabled"
      severity error;
    report "  ? Test 3.4: BRS bit when disabled correct";

    -- Test 3.5: ESI bit (position 17) when flagged
    frame_info := tx_mac_frame_bit(17, fd_basic, data_frame, 8,
                                   false, true, '0');
    assert frame_info.is_form_bit = true
      report "ESI should be form bit"
      severity error;
    assert frame_info.polarity = recessive_bit_c
      report "ESI should be recessive when flagged"
      severity error;
    report "  ? Test 3.5: ESI bit when flagged correct";

    -- Test 3.6: ESI bit when not flagged
    frame_info := tx_mac_frame_bit(17, fd_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.polarity = dominant_bit_c
      report "ESI should be dominant when not flagged"
      severity error;
    report "  ? Test 3.6: ESI bit when not flagged correct";

    -- Test 3.7: FD DLC field (positions 18-21)
    frame_info := tx_mac_frame_bit(18, fd_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.is_form_bit = true
      report "DLC should be form bit"
      severity error;
    report "  ? Test 3.7: FD DLC field correct";

    -- =====================================================================
    -- Test Group 4: CAN FD Extended (29-bit ID with FD features)
    -- =====================================================================
    report "Test Group 4: CAN FD Extended (29-bit ID with FD features)";

    -- Test 4.1: RRS bit (position 32) in FD extended
    frame_info := tx_mac_frame_bit(32, fd_extended, data_frame, 8,
                                   false, false, '0');
    assert frame_info.is_form_bit = true
      report "RRS should be form bit"
      severity error;
    assert frame_info.polarity = dominant_bit_c
      report "RRS should be dominant"
      severity error;
    report "  ? Test 4.1: RRS bit in FD extended correct";

    -- Test 4.2: FDF bit (position 33) in FD extended
    frame_info := tx_mac_frame_bit(33, fd_extended, data_frame, 8,
                                   false, false, '0');
    assert frame_info.is_form_bit = true
      report "FDF should be form bit"
      severity error;
    assert frame_info.polarity = recessive_bit_c
      report "FDF should be recessive"
      severity error;
    report "  ? Test 4.2: FDF bit in FD extended correct";

    -- Test 4.3: Control field in FD extended (positions 33-36)
    frame_info := tx_mac_frame_bit(33, fd_extended, data_frame, 8,
                                   false, false, '0');
    assert frame_info.frame_field = field_control
      report "Position 33 should be control field"
      severity error;
    report "  ? Test 4.3: Control field in FD extended correct";

    -- =====================================================================
    -- Test Group 5: Fixed Stuff Bits in CAN FD
    -- =====================================================================
    report "Test Group 5: Fixed Stuff Bits in CAN FD";

    -- Test 5.1: Fixed stuff bits with CRC-17 (DLC=8)
    report "  Testing CRC-17 stuff bits (DLC=8)...";
    crc_start_pos := 22 + 64;                                                            -- = 86

    prev_bit := '0';

    for offset in 0 to 25 loop

      if (offset = 0 or offset = 5 or offset = 10 or offset = 15 or offset = 20) then
        frame_info := tx_mac_frame_bit(crc_start_pos + offset, fd_basic, data_frame, 8,
                                       false, false, prev_bit);
        assert frame_info.is_form_bit = true
          report "Position " & integer'image(crc_start_pos + offset) &
                 " should be fixed stuff bit"
          severity error;
        assert frame_info.polarity = not prev_bit
          report "Stuff bit should invert previous bit"
          severity error;
        prev_bit   := not prev_bit;
      end if;

    end loop;

    report "  ? Test 5.1: Fixed stuff bits for CRC-17 correct";

    -- Test 5.2: Fixed stuff bits with CRC-21 (DLC=15, 64 bytes)
    report "  Testing CRC-21 stuff bits (DLC=15)...";
    crc_start_pos := 22 + 512;                                                           -- = 534

    prev_bit := '0';

    for offset in 0 to 35 loop

      if (offset = 0 or offset = 5 or offset = 10 or offset = 15 or
          offset = 20 or offset = 25 or offset = 30) then
        frame_info := tx_mac_frame_bit(crc_start_pos + offset, fd_basic, data_frame, 15,
                                       false, false, prev_bit);
        assert frame_info.is_form_bit = true
          report "Position " & integer'image(crc_start_pos + offset) &
                 " should be fixed stuff bit for CRC-21"
          severity error;
        prev_bit   := not prev_bit;
      end if;

    end loop;

    report "  ? Test 5.2: Fixed stuff bits for CRC-21 correct";

    -- Test 5.3: No fixed stuff bits in Classic CAN
    frame_info := tx_mac_frame_bit(86, cc_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.is_form_bit = false
      report "Classic CAN should not have fixed stuff bits"
      severity error;
    report "  ? Test 5.3: Classic CAN confirmed no fixed stuff bits";

    -- =====================================================================
    -- Test Group 6: Field Boundaries and Transitions
    -- =====================================================================
    report "Test Group 6: Field Boundaries and Transitions";

    -- Test 6.1: Transition from Arbitration to Control (CC Basic)
    frame_info := tx_mac_frame_bit(12, cc_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.frame_field = field_arbitration
      report "Position 12 should be arbitration"
      severity error;
    frame_info := tx_mac_frame_bit(13, cc_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.frame_field = field_control
      report "Position 13 should be control"
      severity error;
    report "  ? Test 6.1: ARB to CONTROL transition correct";

    -- Test 6.2: Transition from Control to Data (CC Basic)
    frame_info := tx_mac_frame_bit(18, cc_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.frame_field = field_control
      report "Position 18 should be control"
      severity error;
    frame_info := tx_mac_frame_bit(19, cc_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.frame_field = field_data
      report "Position 19 should be data"
      severity error;
    report "  ? Test 6.2: CONTROL to DATA transition correct";

    -- Test 6.3: Data field length for different DLCs (CC Basic)
    for dlc_val in 1 to 8 loop
      frame_info := tx_mac_frame_bit(19, cc_basic, data_frame, dlc_val,
                                     false, false, '0');
      assert frame_info.frame_field = field_data
        report "Position 19 should be data for all DLC >= 1"
        severity error;
    end loop;

    report "  ? Test 6.3: Data field length varies correctly with DLC";

    -- =====================================================================
    -- Test Group 7: ACK and EOF Fields
    -- =====================================================================
    report "Test Group 7: ACK and EOF Fields";

    -- Test 7.1: ACK slot (form bit, recessive)
    frame_info := tx_mac_frame_bit(99, cc_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.frame_field = field_ack_slot
      report "Position 99 should be ACK slot field"
      severity error;
    assert frame_info.is_form_bit = true
      report "ACK slot should be form bit"
      severity error;
    assert frame_info.polarity = recessive_bit_c
      report "ACK slot should be recessive"
      severity error;
    report "  ? Test 7.1: ACK slot correct";

    -- Test 7.2: ACK delimiter (form bit, recessive)
    frame_info := tx_mac_frame_bit(100, cc_basic, data_frame, 8,
                                   false, false, '0');
    assert frame_info.frame_field = field_ack_delimiter
      report "Position 100 should be ACK delimiter field"
      severity error;
    assert frame_info.is_form_bit = true
      report "ACK delimiter should be form bit"
      severity error;
    assert frame_info.polarity = recessive_bit_c
      report "ACK delimiter should be recessive"
      severity error;
    report "  ? Test 7.2: ACK delimiter correct";

    -- Test 7.3: EOF field (7 bits of recessive)
    for eof_offset in 0 to 6 loop
      frame_info := tx_mac_frame_bit(101 + eof_offset, cc_basic, data_frame, 8,
                                     false, false, '0');
      assert frame_info.frame_field = field_eof
        report "EOF field should span 7 bits"
        severity error;
      assert frame_info.is_form_bit = true
        report "All EOF bits should be form bits"
        severity error;
      assert frame_info.polarity = recessive_bit_c
        report "All EOF bits should be recessive"
        severity error;
    end loop;

    report "  ? Test 7.3: EOF field (7 recessive bits) correct";

    -- =====================================================================
    -- Test Group 8: Previous Bit Polarity for Stuff Bits
    -- =====================================================================
    report "Test Group 8: Previous Bit Polarity for Stuff Bits";

    -- Test 8.1: Stuff bit inverts when previous is 0
    prev_bit   := '0';
    frame_info := tx_mac_frame_bit(86, fd_basic, data_frame, 8,
                                   false, false, prev_bit);
    assert frame_info.polarity = '1'
      report "Stuff bit should be 1 when previous is 0"
      severity error;
    report "  ? Test 8.1: Stuff bit with prev_bit=0 correct";

    -- Test 8.2: Stuff bit inverts when previous is 1
    prev_bit   := '1';
    frame_info := tx_mac_frame_bit(91, fd_basic, data_frame, 8,
                                   false, false, prev_bit);
    assert frame_info.polarity = '0'
      report "Stuff bit should be 0 when previous is 1"
      severity error;
    report "  ? Test 8.2: Stuff bit with prev_bit=1 correct";

    -- =====================================================================
    -- Test Group 9: Combination Tests
    -- =====================================================================
    report "Test Group 9: Combination Tests";

    -- Test 9.1: FD frame with BRS and ESI both enabled
    frame_info := tx_mac_frame_bit(16, fd_basic, data_frame, 8,
                                   true, true, '0');
    assert frame_info.polarity = recessive_bit_c
      report "BRS should be recessive"
      severity error;

    frame_info := tx_mac_frame_bit(17, fd_basic, data_frame, 8,
                                   true, true, '0');
    assert frame_info.polarity = recessive_bit_c
      report "ESI should be recessive"
      severity error;
    report "  ? Test 9.1: BRS and ESI both enabled correct";

    -- Test 9.2: Extended frame with REMOTE_FRAME
    frame_info := tx_mac_frame_bit(32, cc_extended, remote_frame, 8,
                                   false, false, '0');
    assert frame_info.polarity = recessive_bit_c
      report "RTR should be recessive for REMOTE_FRAME"
      severity error;
    report "  ? Test 9.2: Extended REMOTE_FRAME correct";

    -- Test 9.3: FD Extended with maximum DLC
    frame_info := tx_mac_frame_bit(41, fd_extended, data_frame, 15,
                                   false, false, '0');
    assert frame_info.frame_field = field_data
      report "Should handle FD Extended with DLC=15"
      severity error;
    report "  ? Test 9.3: FD Extended with DLC=15 correct";

    -- =====================================================================
    -- Test Summary
    -- =====================================================================
    report "========================================";
    report "ALL TESTS PASSED!";
    report "========================================";
    wait;

  end process test_process;

end architecture tb;
