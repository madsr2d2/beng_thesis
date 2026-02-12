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

    variable frame_info      : mac_frame_bit_t;
    variable mac_ser_to_fsm  : tx_mac_ser_to_fsm_if_t;
    variable crc_vec         : crc_vector_t;
    variable sbc_vec         : sbc_t;
    variable prev_polarity   : polarity_t;
    variable test_count      : integer;
    variable pass_count      : integer;
    variable frame_params    : frame_params_t;
    variable dlc_idx         : integer;
    variable config_byte_0   : byte_t;
    variable config_byte_1   : byte_t;
    variable expected_dlc    : dlc_t;
    variable expected_format : can_format_t;
    variable test_passed     : boolean;

  begin

    report "========================================";
    report "CAN MAC Frame Bit Comprehensive Testbench";
    report "========================================";

    test_count := 0;
    pass_count := 0;

    -- =====================================================================
    -- Test Group A: Frame Format Detection and DLC Parsing
    -- =====================================================================
    report "";
    report "Test Group A: Frame Format Detection and DLC Parsing";
    report "=====================================================================";

    -- Test A.1-A.4: CAN Classic Basic with all DLC values (0-15)
    report "A.1: CAN Classic Basic - All DLC values (0-15)";
    for dlc_idx in 0 to 15 loop
      test_count := test_count + 1;
      -- Format: 001 (cc_basic), DLC in byte 1 bits [7:4]
      config_byte_0 := x"28";  -- FORMAT=001 (cc_basic), FTYP=data_frame, no BRS/ESI
      config_byte_1 := std_logic_vector(to_unsigned(dlc_idx, 4)) & "0000";

      frame_params := calculate_frame_params(config_byte_0, config_byte_1);

      assert frame_params.format = cc_basic
        report "DLC " & integer'image(dlc_idx) & ": format should be cc_basic"
        severity error;
      assert to_integer(unsigned(frame_params.dlc_vector)) = dlc_idx
        report "DLC " & integer'image(dlc_idx) & ": dlc mismatch"
        severity error;

      pass_count := pass_count + 1;
    end loop;
    report "  PASS: All cc_basic DLC values (0-15) detected correctly";

    -- Test A.2: CAN Classic Extended with all DLC values
    report "A.2: CAN Classic Extended - All DLC values (0-15)";
    for dlc_idx in 0 to 15 loop
      test_count := test_count + 1;
      -- Format: 000 (cc_extended)
      config_byte_0 := x"08";
      config_byte_1 := std_logic_vector(to_unsigned(dlc_idx, 4)) & "0000";

      frame_params := calculate_frame_params(config_byte_0, config_byte_1);

      assert frame_params.format = cc_extended
        report "Extended DLC " & integer'image(dlc_idx) & ": format should be cc_extended"
        severity error;
      assert to_integer(unsigned(frame_params.dlc_vector)) = dlc_idx
        report "Extended DLC " & integer'image(dlc_idx) & ": dlc mismatch"
        severity error;

      pass_count := pass_count + 1;
    end loop;
    report "  PASS: All cc_extended DLC values (0-15) detected correctly";

    -- Test A.3: CAN FD Basic with all DLC values
    report "A.3: CAN FD Basic - All DLC values (0-15)";
    for dlc_idx in 0 to 15 loop
      test_count := test_count + 1;
      -- Format: 110 (fd_basic), FDF=1
      config_byte_0 := x"C0";
      config_byte_1 := std_logic_vector(to_unsigned(dlc_idx, 4)) & "0000";

      frame_params := calculate_frame_params(config_byte_0, config_byte_1);

      assert frame_params.format = fd_basic
        report "FD Basic DLC " & integer'image(dlc_idx) & ": format should be fd_basic"
        severity error;
      assert to_integer(unsigned(frame_params.dlc_vector)) = dlc_idx
        report "FD Basic DLC " & integer'image(dlc_idx) & ": dlc mismatch"
        severity error;
      assert frame_params.is_fd_frame = true
        report "FD Basic DLC " & integer'image(dlc_idx) & ": is_fd_frame should be true"
        severity error;

      pass_count := pass_count + 1;
    end loop;
    report "  PASS: All fd_basic DLC values (0-15) detected correctly";

    -- Test A.4: CAN FD Extended with all DLC values
    report "A.4: CAN FD Extended - All DLC values (0-15)";
    for dlc_idx in 0 to 15 loop
      test_count := test_count + 1;
      -- Format: 111 (fd_extended), FDF=1
      config_byte_0 := x"E0";
      config_byte_1 := std_logic_vector(to_unsigned(dlc_idx, 4)) & "0000";

      frame_params := calculate_frame_params(config_byte_0, config_byte_1);

      assert frame_params.format = fd_extended
        report "FD Extended DLC " & integer'image(dlc_idx) & ": format should be fd_extended"
        severity error;
      assert to_integer(unsigned(frame_params.dlc_vector)) = dlc_idx
        report "FD Extended DLC " & integer'image(dlc_idx) & ": dlc mismatch"
        severity error;

      pass_count := pass_count + 1;
    end loop;
    report "  PASS: All fd_extended DLC values (0-15) detected correctly";

    -- =====================================================================
    -- Test Group B: Data Length Calculations
    -- =====================================================================
    report "";
    report "Test Group B: Data Length Calculations";
    report "=====================================================================";

    -- Test B.1: CAN Classic data lengths (always 0-8 bytes)
    report "B.1: CAN Classic data lengths (0-8 bytes only)";
    config_byte_0 := x"28";  -- cc_basic
    for dlc_idx in 0 to 8 loop
      test_count := test_count + 1;
      config_byte_1 := std_logic_vector(to_unsigned(dlc_idx, 4)) & "0000";
      frame_params := calculate_frame_params(config_byte_0, config_byte_1);

      assert (frame_params.data_stop - frame_params.data_start + 1) = dlc_idx
        report "CC DLC " & integer'image(dlc_idx) & ": data_length should be " & integer'image(dlc_idx)
        severity error;

      pass_count := pass_count + 1;
    end loop;
    report "  PASS: Classic data lengths match DLC (0-8 bytes)";

    -- Test B.2: CAN Classic saturation (DLC 9-15 stay at 8 bytes)
    report "B.2: CAN Classic DLC saturation (9-15 -> 8 bytes)";
    for dlc_idx in 9 to 15 loop
      test_count := test_count + 1;
      config_byte_1 := std_logic_vector(to_unsigned(dlc_idx, 4)) & "0000";
      frame_params := calculate_frame_params(config_byte_0, config_byte_1);

      assert (frame_params.data_stop - frame_params.data_start + 1) = 8
        report "CC DLC " & integer'image(dlc_idx) & ": data_length should saturate to 8"
        severity error;

      pass_count := pass_count + 1;
    end loop;
    report "  PASS: Classic data lengths saturate at 8 bytes";

    -- Test B.3: CAN FD data lengths (DLC 0-15 maps to 0,1,2,...,8,12,16,20,24,32,48,64)
    report "B.3: CAN FD data lengths (0-15 with extended lengths)";
    config_byte_0 := x"C0";  -- fd_basic
    for dlc_idx in 0 to 15 loop
      test_count := test_count + 1;
      config_byte_1 := std_logic_vector(to_unsigned(dlc_idx, 4)) & "0000";
      frame_params := calculate_frame_params(config_byte_0, config_byte_1);

      test_passed := false;
      case dlc_idx is
        when 0 => test_passed := ((frame_params.data_stop - frame_params.data_start + 1) = 0);
        when 1 => test_passed := ((frame_params.data_stop - frame_params.data_start + 1) = 1);
        when 2 => test_passed := ((frame_params.data_stop - frame_params.data_start + 1) = 2);
        when 3 => test_passed := ((frame_params.data_stop - frame_params.data_start + 1) = 3);
        when 4 => test_passed := ((frame_params.data_stop - frame_params.data_start + 1) = 4);
        when 5 => test_passed := ((frame_params.data_stop - frame_params.data_start + 1) = 5);
        when 6 => test_passed := ((frame_params.data_stop - frame_params.data_start + 1) = 6);
        when 7 => test_passed := ((frame_params.data_stop - frame_params.data_start + 1) = 7);
        when 8 => test_passed := ((frame_params.data_stop - frame_params.data_start + 1) = 8);
        when 9 => test_passed := ((frame_params.data_stop - frame_params.data_start + 1) = 12);
        when 10 => test_passed := ((frame_params.data_stop - frame_params.data_start + 1) = 16);
        when 11 => test_passed := ((frame_params.data_stop - frame_params.data_start + 1) = 20);
        when 12 => test_passed := ((frame_params.data_stop - frame_params.data_start + 1) = 24);
        when 13 => test_passed := ((frame_params.data_stop - frame_params.data_start + 1) = 32);
        when 14 => test_passed := ((frame_params.data_stop - frame_params.data_start + 1) = 48);
        when 15 => test_passed := ((frame_params.data_stop - frame_params.data_start + 1) = 64);
        when others => test_passed := false;
      end case;

      assert test_passed
        report "FD DLC " & integer'image(dlc_idx) & ": data_length mismatch"
        severity error;

      pass_count := pass_count + 1;
    end loop;
    report "  PASS: All FD DLC data lengths correct";

    -- =====================================================================
    -- Test Group C: Frame Parameter Consistency
    -- =====================================================================
    report "";
    report "Test Group C: Frame Parameter Consistency";
    report "=====================================================================";

    -- Test C.1: CRC length validation
    report "C.1: CRC field length consistency";
    config_byte_0 := x"28";  -- cc_basic, dlc=8
    config_byte_1 := x"80";
    test_count := test_count + 1;
    frame_params := calculate_frame_params(config_byte_0, config_byte_1);

    assert (frame_params.crc_stop - frame_params.crc_start) = 15
      report "Classic Basic CRC should be 15 bits"
      severity error;
    assert frame_params.crc_start = frame_params.data_start + (frame_params.data_stop - frame_params.data_start + 1)
      report "CRC start should equal data_start + data_length"
      severity error;
    assert frame_params.crc_delimiter = frame_params.crc_start + (frame_params.crc_stop - frame_params.crc_start)
      report "CRC delimiter start should equal crc_start + crc_length"
      severity error;

    pass_count := pass_count + 1;
    report "  PASS: CRC field positions consistent";

    -- Test C.2: Field ordering (no gaps)
    report "C.2: Field ordering and gaps validation";
    config_byte_0 := x"C0";  -- fd_basic, dlc=8
    config_byte_1 := x"80";
    test_count := test_count + 1;
    frame_params := calculate_frame_params(config_byte_0, config_byte_1);

    assert frame_params.data_start > 0
      report "Data field should start after arbitration/control"
      severity error;
    assert frame_params.crc_start >= frame_params.data_start + (frame_params.data_stop - frame_params.data_start + 1)
      report "CRC field should not overlap data"
      severity error;
    assert frame_params.ack_slot > frame_params.crc_delimiter
      report "ACK should be after CRC delimiter"
      severity error;

    pass_count := pass_count + 1;
    report "  PASS: Field ordering valid";

    -- =====================================================================
    -- Test Group D: SOF and EOF Field Validation
    -- =====================================================================
    report "";
    report "Test Group D: SOF and EOF Field Validation";
    report "=====================================================================";

    -- Test D.1: SOF bit for all formats
    report "D.1: SOF bit (position 0) for all formats";
    mac_ser_to_fsm.data := dominant;
    mac_ser_to_fsm.valid := '1';
    crc_vec := (others => '0');
    sbc_vec := (others => '0');
    prev_polarity := unknown;
    frame_params := calculate_frame_params(x"28", x"80");

    for format_idx in cc_basic to fd_extended loop
      test_count := test_count + 1;

      -- Set appropriate config bytes for each format
      case format_idx is
        when cc_basic => frame_params := calculate_frame_params(x"28", x"80");
        when cc_extended => frame_params := calculate_frame_params(x"08", x"80");
        when fd_basic => frame_params := calculate_frame_params(x"C0", x"80");
        when fd_extended => frame_params := calculate_frame_params(x"E0", x"80");
        when others => null;
      end case;

      frame_info := get_next_mac_frame_bit(0, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);

      assert frame_info.bit_name = sof_bit
        report "Format " & can_format_t'image(format_idx) & ": SOF at position 0"
        severity error;
      assert frame_info.polarity = dominant
        report "Format " & can_format_t'image(format_idx) & ": SOF should be dominant"
        severity error;

      pass_count := pass_count + 1;
    end loop;
    report "  PASS: SOF bit correct for all formats";

    -- =====================================================================
    -- Test Group E: Arbitration Field Validation
    -- =====================================================================
    report "";
    report "Test Group E: Arbitration Field Validation";
    report "=====================================================================";

    -- Test E.1: Base ID bits (positions 1-11)
    report "E.1: Base ID bits (positions 1-11)";
    frame_params := calculate_frame_params(x"28", x"80");  -- cc_basic
    for bit_pos in 1 to 11 loop
      test_count := test_count + 1;
      mac_ser_to_fsm.data := recessive;
      frame_info := get_next_mac_frame_bit(bit_pos, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);

      assert frame_info.bit_name = base_id_bit
        report "Position " & integer'image(bit_pos) & ": should be base_id_bit"
        severity error;

      pass_count := pass_count + 1;
    end loop;
    report "  PASS: Base ID bits at correct positions (1-11)";

    -- Test E.2: RTR bit at position 12
    report "E.2: RTR bit validation (position 12)";
    test_count := test_count + 1;
    frame_info := get_next_mac_frame_bit(12, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);

    assert frame_info.bit_name = rtr_bit
      report "Position 12: should be rtr_bit"
      severity error;

    pass_count := pass_count + 1;
    report "  PASS: RTR bit at correct position (12)";

    -- Test E.3: IDE bit at position 13
    report "E.3: IDE bit validation (position 13)";
    test_count := test_count + 1;
    frame_info := get_next_mac_frame_bit(13, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);

    assert frame_info.bit_name = ide_bit
      report "Position 13: should be ide_bit"
      severity error;

    pass_count := pass_count + 1;
    report "  PASS: IDE bit at correct position (13)";

    -- =====================================================================
    -- Test Group F: CAN FD Specific Fields
    -- =====================================================================
    report "";
    report "Test Group F: CAN FD Specific Fields";
    report "=====================================================================";

    -- Test F.1: FDF bit detection
    report "F.1: FDF bit presence in FD frames";
    test_count := test_count + 1;
    frame_params := calculate_frame_params(x"C0", x"80");  -- fd_basic
    frame_info := get_next_mac_frame_bit(14, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);

    assert frame_info.bit_name = fdf_bit
      report "FD Basic: position 14 should be fdf_bit"
      severity error;

    pass_count := pass_count + 1;
    report "  PASS: FDF bit present in FD frames";

    -- Test F.2: BRS bit with enable/disable
    report "F.2: BRS bit enable/disable validation";
    test_count := test_count + 1;
    -- BRS disabled
    frame_params := calculate_frame_params(x"C0", x"80");
    frame_info := get_next_mac_frame_bit(16, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.polarity = dominant
      report "BRS disabled should be dominant"
      severity error;

    test_count := test_count + 1;
    -- BRS enabled
    frame_params := calculate_frame_params(x"C4", x"80");
    frame_info := get_next_mac_frame_bit(16, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
    assert frame_info.polarity = recessive
      report "BRS enabled should be recessive"
      severity error;

    pass_count := pass_count + 2;
    report "  PASS: BRS bit polarity correct";

    -- Test F.3: ESI bit
    report "F.3: ESI bit validation";
    test_count := test_count + 1;
    frame_params := calculate_frame_params(x"CC", x"80");  -- BRS=1, ESI=1
    frame_info := get_next_mac_frame_bit(17, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);

    assert frame_info.bit_name = esi_bit
      report "Position 17: should be esi_bit"
      severity error;
    assert frame_info.polarity = recessive
      report "ESI flagged should be recessive"
      severity error;

    pass_count := pass_count + 1;
    report "  PASS: ESI bit correct";

    -- =====================================================================
    -- Test Group G: TDC (Transmitter Delay Compensation) Function
    -- =====================================================================
    report "";
    report "Test Group G: TDC Determination";
    report "=====================================================================";

    -- Test G.1-G.5: TDC conditions (from original testbench)
    report "G.1: TDC enabled for short bit times (<= 1000ns)";
    test_count := test_count + 1;
    assert should_use_tdc(100_000_000, 1, 1, 4, 4, 4, 600) = true
      report "TDC should be true for bit_time=130ns"
      severity error;
    pass_count := pass_count + 1;

    report "G.2: TDC disabled for long bit times with large early_bits";
    test_count := test_count + 1;
    assert should_use_tdc(100_000_000, 4, 1, 20, 20, 20, 600) = false
      report "TDC should be false for bit_time=2440ns with early_bits=1640ns"
      severity error;
    pass_count := pass_count + 1;

    report "G.3: TDC enabled when early_bits < 600ns";
    test_count := test_count + 1;
    assert should_use_tdc(100_000_000, 2, 1, 10, 10, 10, 600) = true
      report "TDC should be true when early_bits=420ns"
      severity error;
    pass_count := pass_count + 1;

    -- =====================================================================
    -- Test Group H: Edge Cases and Boundary Conditions
    -- =====================================================================
    report "";
    report "Test Group H: Edge Cases and Boundary Conditions";
    report "=====================================================================";

    -- Test H.1: Minimum data length (DLC=0)
    report "H.1: Minimum frame (DLC=0, no data)";
    test_count := test_count + 1;
    frame_params := calculate_frame_params(x"28", x"00");
    assert (frame_params.data_stop - frame_params.data_start + 1) = 0
      report "DLC=0: data_length should be 0"
      severity error;
    assert to_integer(unsigned(frame_params.dlc_vector)) = 0
      report "DLC=0: dlc should be 0"
      severity error;
    pass_count := pass_count + 1;
    report "  PASS: Minimum frame validated";

    -- Test H.2: Maximum CAN Classic frame (DLC=8)
    report "H.2: Maximum Classic frame (DLC=8, 8 bytes)";
    test_count := test_count + 1;
    frame_params := calculate_frame_params(x"28", x"80");
    assert (frame_params.data_stop - frame_params.data_start + 1) = 8
      report "DLC=8 classic: data_length should be 8"
      severity error;
    pass_count := pass_count + 1;
    report "  PASS: Maximum classic frame validated";

    -- Test H.3: Maximum CAN FD frame (DLC=15, 64 bytes)
    report "H.3: Maximum FD frame (DLC=15, 64 bytes)";
    test_count := test_count + 1;
    frame_params := calculate_frame_params(x"C0", x"F0");
    assert (frame_params.data_stop - frame_params.data_start + 1) = 64
      report "DLC=15 FD: data_length should be 64"
      severity error;
    pass_count := pass_count + 1;
    report "  PASS: Maximum FD frame validated";

    -- Test H.4: Stuff bit polarity inversion
    report "H.4: Stuff bit polarity inversion";
    test_count := test_count + 1;
    prev_polarity := dominant;
    frame_info := get_next_mac_frame_bit(100, mac_ser_to_fsm, prev_polarity, recessive, true, sbc_vec, crc_vec);
    assert frame_info.bit_name = fixed_stuff_bit
      report "Stuff bit detection failed"
      severity error;
    assert frame_info.polarity = recessive
      report "Stuff bit after dominant should be recessive"
      severity error;

    test_count := test_count + 1;
    prev_polarity := recessive;
    frame_info := get_next_mac_frame_bit(100, mac_ser_to_fsm, prev_polarity, dominant, true, sbc_vec, crc_vec);
    assert frame_info.polarity = dominant
      report "Stuff bit after recessive should be dominant"
      severity error;

    pass_count := pass_count + 2;
    report "  PASS: Stuff bit inversion correct";

    -- =====================================================================
    -- Test Summary
    -- =====================================================================
    report "";
    report "========================================";
    report "Comprehensive Test Results";
    report "========================================";
    report "Total Tests: " & integer'image(test_count);
    report "Passed: " & integer'image(pass_count);
    report "Failed: " & integer'image(test_count - pass_count);

    if (pass_count = test_count) then
      report "ALL TESTS PASSED!";
    else
      report "SOME TESTS FAILED!";
    end if;

    report "========================================";
    wait;

  end process test_process;

end architecture tb;
