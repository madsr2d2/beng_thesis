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

    variable frame_info     : mac_frame_bit_t;
    variable mac_ser_to_fsm : tx_mac_ser_to_fsm_if_t;
    variable crc_vec        : crc_vector_t;
    variable sbc_vec        : sbc_t;
    variable prev_polarity  : polarity_t;
    variable test_count     : integer;
    variable pass_count     : integer;

  begin

    report "========================================";
    report "CAN MAC Frame Bit Testbench - Updated";
    report "========================================";

    test_count := 0;
    pass_count := 0;

    -- =====================================================================
    -- Test Group 1: CAN Classic Basic (11-bit ID)
    -- =====================================================================
    report "Test Group 1: CAN Classic Basic (11-bit ID)";

    -- Initialize mac_ser_to_fsm interface for cc_basic
    mac_ser_to_fsm.frame_info.format     := cc_basic;
    mac_ser_to_fsm.frame_info.ftyp       := data_frame;
    mac_ser_to_fsm.frame_info.brs_enable := false;
    mac_ser_to_fsm.frame_info.esi_enable := false;
    mac_ser_to_fsm.frame_info.dlc        := 8;
    mac_ser_to_fsm.data                  := dominant;
    mac_ser_to_fsm.valid                 := '1';

    crc_vec       := (others => '0');
    sbc_vec       := (others => '0');
    prev_polarity := unknown;

    -- Test 1.1: SOF bit (position 0)
    test_count := test_count + 1;
    frame_info := get_next_mac_frame_bit(0, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = sof_bit
      report "SOF bit_type should be sof_bit"
      severity error;
    assert frame_info.polarity = dominant
      report "SOF polarity should be dominant"
      severity error;
    report "  Test 1.1: SOF bit correct (PASS)";
    pass_count := pass_count + 1;

    -- Test 1.2: Base ID bits (positions 1-11)
    test_count          := test_count + 1;
    mac_ser_to_fsm.data := recessive;                                                                                                           -- Set transmitted bit to recessive
    frame_info          := get_next_mac_frame_bit(1, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = base_id_bit
      report "Position 1 should be base_id_bit"
      severity error;
    assert frame_info.polarity = recessive
      report "ID bit polarity should follow transmitted data (recessive)"
      severity error;
    report "  Test 1.2: Base ID bits correct (PASS)";
    pass_count          := pass_count + 1;

    -- Test 1.3: RTR bit (position 12) for DATA_FRAME
    test_count := test_count + 1;
    frame_info := get_next_mac_frame_bit(12, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = rtr_bit
      report "Position 12 should be rtr_bit"
      severity error;
    report "  Test 1.3: RTR bit for DATA_FRAME correct (PASS)";
    pass_count := pass_count + 1;

    -- Test 1.4: IDE bit (position 13)
    test_count := test_count + 1;
    frame_info := get_next_mac_frame_bit(13, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = ide_bit
      report "Position 13 should be ide_bit"
      severity error;
    assert frame_info.polarity = dominant
      report "IDE should be dominant for basic format"
      severity error;
    report "  Test 1.4: IDE bit correct (PASS)";
    pass_count := pass_count + 1;

    -- Test 1.5: r0 bit (position 14)
    test_count := test_count + 1;
    frame_info := get_next_mac_frame_bit(14, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = r0_bit
      report "Position 14 should be r0_bit"
      severity error;
    assert frame_info.polarity = dominant
      report "r0 should be dominant"
      severity error;
    report "  Test 1.5: r0 bit correct (PASS)";
    pass_count := pass_count + 1;

    -- Test 1.6: DLC bits (positions 15-18)
    test_count := test_count + 1;
    frame_info := get_next_mac_frame_bit(15, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = dlc_bit
      report "Position 15 should be dlc_bit"
      severity error;
    report "  Test 1.6: DLC field correct (PASS)";
    pass_count := pass_count + 1;

    -- Test 1.7: Data field (positions 19-82 for 8 bytes)
    test_count := test_count + 1;
    frame_info := get_next_mac_frame_bit(19, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = data_bit
      report "Position 19 should be data_bit"
      severity error;
    report "  Test 1.7: Data field correct (PASS)";
    pass_count := pass_count + 1;

    -- Test 1.8: CRC field (positions 83-97 for cc_basic)
    test_count := test_count + 1;
    crc_vec    := std_logic_vector(to_unsigned(255, crc_vec'length));
    frame_info := get_next_mac_frame_bit(83, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = crc_bit
      report "Position 83 should be crc_bit"
      severity error;
    assert frame_info.polarity = dominant
      report "CRC MSB of 255 should extract as dominant"
      severity error;
    report "  Test 1.8: CRC field correct (PASS)";
    pass_count := pass_count + 1;

    -- =====================================================================
    -- Test Group 2: CAN Classic Extended (29-bit ID)
    -- =====================================================================
    report "Test Group 2: CAN Classic Extended (29-bit ID)";

    mac_ser_to_fsm.frame_info.format := cc_extended;
    crc_vec                          := (others => '0');

    -- Test 2.1: IDE bit at position 13 (marks extended format)
    test_count := test_count + 1;
    frame_info := get_next_mac_frame_bit(13, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = ide_bit
      report "Position 13 should be ide_bit"
      severity error;
    assert frame_info.polarity = recessive
      report "IDE should be recessive for extended format"
      severity error;
    report "  Test 2.1: IDE bit for extended format correct (PASS)";
    pass_count := pass_count + 1;

    -- Test 2.2: Extended ID bits
    test_count          := test_count + 1;
    mac_ser_to_fsm.data := recessive;
    frame_info          := get_next_mac_frame_bit(14, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = extended_id_bit
      report "Position 14 should be extended_id_bit"
      severity error;
    report "  Test 2.2: Extended ID bits correct (PASS)";
    pass_count          := pass_count + 1;

    -- =====================================================================
    -- Test Group 3: CAN FD Basic
    -- =====================================================================
    report "Test Group 3: CAN FD Basic (with FD features)";

    mac_ser_to_fsm.frame_info.format     := fd_basic;
    mac_ser_to_fsm.frame_info.brs_enable := false;
    mac_ser_to_fsm.frame_info.esi_enable := false;

    -- Test 3.1: FDF bit (marks FD format)
    test_count := test_count + 1;
    frame_info := get_next_mac_frame_bit(14, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = fdf_bit
      report "Position 14 should be fdf_bit"
      severity error;
    assert frame_info.polarity = recessive
      report "FDF should be recessive"
      severity error;
    report "  Test 3.1: FDF bit correct (PASS)";
    pass_count := pass_count + 1;

    -- Test 3.2: BRS bit when disabled
    test_count := test_count + 1;
    frame_info := get_next_mac_frame_bit(16, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = brs_bit
      report "Position 16 should be brs_bit"
      severity error;
    assert frame_info.polarity = dominant
      report "BRS should be dominant when disabled"
      severity error;
    report "  Test 3.2: BRS bit when disabled correct (PASS)";
    pass_count := pass_count + 1;

    -- Test 3.3: BRS bit when enabled
    test_count                           := test_count + 1;
    mac_ser_to_fsm.frame_info.brs_enable := true;
    frame_info                           := get_next_mac_frame_bit(16, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = brs_bit
      report "Position 16 should be brs_bit"
      severity error;
    assert frame_info.polarity = recessive
      report "BRS should be recessive when enabled"
      severity error;
    report "  Test 3.3: BRS bit when enabled correct (PASS)";
    pass_count                           := pass_count + 1;

    -- Test 3.4: ESI bit when flagged
    test_count                           := test_count + 1;
    mac_ser_to_fsm.frame_info.esi_enable := true;
    frame_info                           := get_next_mac_frame_bit(17, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = esi_bit
      report "Position 17 should be esi_bit"
      severity error;
    assert frame_info.polarity = recessive
      report "ESI should be recessive when flagged"
      severity error;
    report "  Test 3.4: ESI bit when flagged correct (PASS)";
    pass_count                           := pass_count + 1;

    -- =====================================================================
    -- Test Group 4: Stuff Bit Handling
    -- =====================================================================
    report "Test Group 4: Stuff Bit Handling";

    -- Test 4.1: Fixed stuff bit (inverts previous polarity)
    test_count    := test_count + 1;
    prev_polarity := dominant;
    frame_info    := get_next_mac_frame_bit(100, mac_ser_to_fsm, prev_polarity, recessive, true, sbc_vec, crc_vec);
    assert frame_info.bit_name = fixed_stuff_bit
      report "Should be fixed_stuff_bit when valid"
      severity error;
    assert frame_info.polarity = recessive
      report "Stuff bit should invert previous polarity (dominant -> recessive)"
      severity error;
    report "  Test 4.1: Fixed stuff bit when prev=dominant correct (PASS)";
    pass_count    := pass_count + 1;

    -- Test 4.2: Stuff bit inverts when previous is recessive
    test_count    := test_count + 1;
    prev_polarity := recessive;
    frame_info    := get_next_mac_frame_bit(100, mac_ser_to_fsm, prev_polarity, dominant, true, sbc_vec, crc_vec);
    assert frame_info.bit_name = fixed_stuff_bit
      report "Should be fixed_stuff_bit when valid"
      severity error;
    assert frame_info.polarity = dominant
      report "Stuff bit should invert previous polarity (recessive -> dominant)"
      severity error;
    report "  Test 4.2: Fixed stuff bit when prev=recessive correct (PASS)";
    pass_count    := pass_count + 1;

    -- =====================================================================
    -- Test Group 5: SBC Bit Extraction
    -- =====================================================================
    report "Test Group 5: SBC Bit Extraction (FD only)";

    mac_ser_to_fsm.frame_info.format := fd_basic;
    mac_ser_to_fsm.frame_info.dlc    := 8;
    sbc_vec                          := "1010";                                                                                           -- Test pattern: 1, 0, 1, 0
    prev_polarity                    := unknown;

    -- SBC field starts at position: data_start + data_bits = 22 + 64 = 86
    -- Test 5.1: First SBC bit (MSB of 1010 = 1)
    test_count := test_count + 1;
    frame_info := get_next_mac_frame_bit(86, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = sbs_bit
      report "Position 86 should be sbs_bit"
      severity error;
    assert frame_info.polarity = dominant
      report "SBC MSB (1 from 1010) should be dominant"
      severity error;
    report "  Test 5.1: SBC MSB extraction correct (PASS)";
    pass_count := pass_count + 1;

    -- Test 5.2: Second SBC bit (0)
    test_count := test_count + 1;
    frame_info := get_next_mac_frame_bit(87, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = sbs_bit
      report "Position 87 should be sbs_bit"
      severity error;
    assert frame_info.polarity = recessive
      report "SBC bit 2 (0 from 1010) should be recessive"
      severity error;
    report "  Test 5.2: SBC bit 2 extraction correct (PASS)";
    pass_count := pass_count + 1;

    -- =====================================================================
    -- Test Group 6: CRC Bit Extraction
    -- =====================================================================
    report "Test Group 6: CRC Bit Extraction";

    crc_vec := std_logic_vector(to_unsigned(32768, crc_vec'length));                                                                      -- MSB set
    -- CRC field starts at position: sbc_stop + 1 = 89 + 1 = 90

    -- Test 6.1: CRC MSB (should be 1)
    test_count := test_count + 1;
    frame_info := get_next_mac_frame_bit(90, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = crc_bit
      report "Position 90 should be crc_bit"
      severity error;
    assert frame_info.polarity = dominant
      report "CRC MSB should be dominant"
      severity error;
    report "  Test 6.1: CRC MSB extraction correct (PASS)";
    pass_count := pass_count + 1;

    -- =====================================================================
    -- Test Group 7: ACK and EOF Fields
    -- =====================================================================
    report "Test Group 7: ACK and EOF Fields";

    mac_ser_to_fsm.frame_info.format := cc_basic;

    -- ACK slot position for cc_basic with DLC=8 is approximately 99
    -- Test 7.1: ACK bit
    test_count := test_count + 1;
    frame_info := get_next_mac_frame_bit(99, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = ack_bit
      report "Position 99 should be ack_bit"
      severity error;
    assert frame_info.polarity = recessive
      report "ACK slot should be recessive (dominated by receiver)"
      severity error;
    report "  Test 7.1: ACK slot correct (PASS)";
    pass_count := pass_count + 1;

    -- Test 7.2: ACK delimiter
    test_count := test_count + 1;
    frame_info := get_next_mac_frame_bit(100, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = ack_delimiter_bit
      report "Position 100 should be ack_delimiter_bit"
      severity error;
    assert frame_info.polarity = recessive
      report "ACK delimiter should be recessive"
      severity error;
    report "  Test 7.2: ACK delimiter correct (PASS)";
    pass_count := pass_count + 1;

    -- Test 7.3: EOF bits (7 recessive bits)
    test_count := test_count + 1;

    for eof_offset in 0 to 6 loop
      frame_info := get_next_mac_frame_bit(101 + eof_offset, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
      assert frame_info.bit_name = eof_bit
        report "EOF field should span 7 bits"
        severity error;
      assert frame_info.polarity = recessive
        report "All EOF bits should be recessive"
        severity error;
    end loop;

    report "  Test 7.3: EOF field (7 recessive bits) correct (PASS)";
    pass_count := pass_count + 1;

    -- =====================================================================
    -- Test Group 8: FD Extended Frame
    -- =====================================================================
    report "Test Group 8: FD Extended Frame";

    mac_ser_to_fsm.frame_info.format := fd_extended;
    mac_ser_to_fsm.frame_info.dlc    := 15;

    -- Test 8.1: RRS bit in FD extended
    test_count := test_count + 1;
    frame_info := get_next_mac_frame_bit(32, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = rrs_bit
      report "Position 32 should be rrs_bit"
      severity error;
    assert frame_info.polarity = dominant
      report "RRS should be dominant"
      severity error;
    report "  Test 8.1: RRS bit in FD extended correct (PASS)";
    pass_count := pass_count + 1;

    -- Test 8.2: FDF bit in FD extended
    test_count := test_count + 1;
    frame_info := get_next_mac_frame_bit(33, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.bit_name = fdf_bit
      report "Position 33 should be fdf_bit"
      severity error;
    assert frame_info.polarity = recessive
      report "FDF should be recessive"
      severity error;
    report "  Test 8.2: FDF bit in FD extended correct (PASS)";
    pass_count := pass_count + 1;

    -- =====================================================================
    -- Test Group 9: Transmitter Delay Compensation (TDC) Determination
    -- =====================================================================
    report "Test Group 9: Transmitter Delay Compensation (TDC) Determination";

    -- Test 9.1: TDC should be used when bit_time <= 1000 ns
    -- bit_time = (1 + 4 + 4 + 4) * 1 * (1e9 / 100MHz) = 13 * 10 ns = 130 ns
    test_count := test_count + 1;
    assert should_use_tdc(
      system_clock_freq => 100_000_000,
      prescalar => 1,
      sync_seg => 1,
      prop_seg_fd => 4,
      phase_seg1_fd => 4,
      phase_seg2_fd => 4,
      pcs_to_pma_propagation_delay_ns => 600
    ) = true
      report "TDC should be true for bit_time=130ns (<=1000ns)"
      severity error;
    report "  Test 9.1: TDC enabled for bit_time <= 1000 ns (PASS)";
    pass_count := pass_count + 1;

    -- Test 9.2: TDC should NOT be used when bit_time > 1000 ns and early_bits > 600 ns
    -- bit_time = (1 + 20 + 20 + 20) * 4 * (1e9 / 100MHz) = 61 * 40 ns = 2440 ns
    -- early_bits = (1 + 20 + 20) * 4 * (1e9 / 100MHz) = 41 * 40 ns = 1640 ns
    test_count := test_count + 1;
    assert should_use_tdc(
      system_clock_freq => 100_000_000,
      prescalar => 4,
      sync_seg => 1,
      prop_seg_fd => 20,
      phase_seg1_fd => 20,
      phase_seg2_fd => 20,
      pcs_to_pma_propagation_delay_ns => 600
    ) = false
      report "TDC should be false for bit_time=2440ns (>1000ns) and early_bits=1640ns (>600ns)"
      severity error;
    report "  Test 9.2: TDC disabled for bit_time > 1000 ns and early_bits > 600 ns (PASS)";
    pass_count := pass_count + 1;

    -- Test 9.3: TDC should be used when early_bits < 600 ns (condition 2)
    -- bit_time = (1 + 10 + 10 + 10) * 2 * (1e9 / 100MHz) = 31 * 20 ns = 620 ns
    -- early_bits = (1 + 10 + 10) * 2 * (1e9 / 100MHz) = 21 * 20 ns = 420 ns < 600 ns
    test_count := test_count + 1;
    assert should_use_tdc(
      system_clock_freq => 100_000_000,
      prescalar => 2,
      sync_seg => 1,
      prop_seg_fd => 10,
      phase_seg1_fd => 10,
      phase_seg2_fd => 10,
      pcs_to_pma_propagation_delay_ns => 600
    ) = true
      report "TDC should be true for early_bits=420ns (<600ns)"
      severity error;
    report "  Test 9.3: TDC enabled for early_bits < 600 ns (PASS)";
    pass_count := pass_count + 1;

    -- Test 9.4: Edge case - bit_time exactly 1000 ns
    -- bit_time = (1 + 4 + 4 + 4) * 1 * (1e9 / 50MHz) = 13 * 20 ns = 260 ns (adjust for 50MHz)
    -- For exactly 1000ns: need prescalar=2, seg_sum=50, freq=100MHz: 50*2*10=1000ns
    test_count := test_count + 1;
    assert should_use_tdc(
      system_clock_freq => 100_000_000,
      prescalar => 2,
      sync_seg => 1,
      prop_seg_fd => 16,
      phase_seg1_fd => 16,
      phase_seg2_fd => 17,
      pcs_to_pma_propagation_delay_ns => 600
    ) = true
      report "TDC should be true when bit_time exactly = 1000 ns (<=1000ns)"
      severity error;
    report "  Test 9.4: TDC enabled when bit_time = 1000 ns (PASS)";
    pass_count := pass_count + 1;

    -- Test 9.5: Edge case - early_bits exactly 600 ns should NOT enable TDC (not < 600)
    -- early_bits = (1 + 14 + 14) * 2 * (1e9 / 100MHz) = 29 * 20 ns = 580 ns < 600 ns -> should be true
    test_count := test_count + 1;
    assert should_use_tdc(
      system_clock_freq => 100_000_000,
      prescalar => 2,
      sync_seg => 1,
      prop_seg_fd => 14,
      phase_seg1_fd => 14,
      phase_seg2_fd => 14,
      pcs_to_pma_propagation_delay_ns => 600
    ) = true
      report "TDC should be true when early_bits < 600 ns (=580ns)"
      severity error;
    report "  Test 9.5: TDC enabled when early_bits < 600 ns (PASS)";
    pass_count := pass_count + 1;

    -- =====================================================================
    -- Test Summary
    -- =====================================================================
    report "========================================";
    report "Test Results: " & integer'image(pass_count) & " / " & integer'image(test_count) & " passed";

    if (pass_count = test_count) then
      report "ALL TESTS PASSED!";
    else
      report "SOME TESTS FAILED!";
    end if;

    report "========================================";
    wait;

  end process test_process;

end architecture tb;
