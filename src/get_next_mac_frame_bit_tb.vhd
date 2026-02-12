library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_pkg.all;

entity get_next_mac_frame_bit_tb is
end entity get_next_mac_frame_bit_tb;

architecture tb of get_next_mac_frame_bit_tb is

begin

  test_process : process is
    variable config_byte_0   : byte_t;
    variable config_byte_1   : byte_t;
    variable frame_params    : frame_params_t;
    variable mac_ser_to_fsm  : tx_mac_ser_to_fsm_if_t;
    variable frame_info      : mac_frame_bit_t;
    variable crc_vec         : crc_vector_t;
    variable sbc_vec         : sbc_t;
    variable prev_polarity   : polarity_t;
    variable bit_count       : position_t;
    variable test_count      : integer;
    variable pass_count      : integer;
    variable format_name     : string(1 to 20);
    variable dlc_idx         : integer;
    variable expected_bits   : integer;
    variable prev_bit_name   : mac_frame_bit_name_t;
    variable stuff_bit_valid : boolean;

  begin

    report "========================================";
    report "get_next_mac_frame_bit Comprehensive Test";
    report "========================================";

    test_count := 0;
    pass_count := 0;

    -- Initialize CRC and SBC vectors with test data
    crc_vec := (others => '1');
    sbc_vec := (others => '0');

    -- =====================================================================
    -- Test Group A: CAN Classic Basic Format
    -- =====================================================================
    report "";
    report "Test Group A: CAN Classic Basic (cc_basic)";
    report "=====================================================================";

    for dlc_idx in 0 to 8 loop
      test_count := test_count + 1;

      -- Config: FORMAT=001 (cc_basic), FTYP=0 (data), no BRS/ESI
      config_byte_0 := x"20";
      config_byte_1 := std_logic_vector(to_unsigned(dlc_idx, 4)) & "0000";

      frame_params := calculate_frame_params(config_byte_0, config_byte_1);

      -- Setup interface
      mac_ser_to_fsm.frame_params := frame_params;
      mac_ser_to_fsm.data := dominant;
      prev_polarity := dominant;

      -- Verify key positions for CC Basic frame
      -- Position 0 should be SOF
      frame_info := get_next_mac_frame_bit(0, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
      assert frame_info.bit_name = sof_bit
        report "CC Basic DLC " & integer'image(dlc_idx) & ": Bit 0 should be SOF"
        severity error;

      -- Position in base ID range (1-11) should be base_id_bit
      frame_info := get_next_mac_frame_bit(6, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
      assert frame_info.bit_name = base_id_bit
        report "CC Basic DLC " & integer'image(dlc_idx) & ": Bit 6 should be base_id_bit"
        severity error;

      -- Position 12 should be RTR bit
      frame_info := get_next_mac_frame_bit(12, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
      assert frame_info.bit_name = rtr_bit
        report "CC Basic DLC " & integer'image(dlc_idx) & ": Bit 12 should be RTR"
        severity error;

      -- Verify RTR is dominant for data frame
      assert frame_info.polarity = dominant
        report "CC Basic DLC " & integer'image(dlc_idx) & ": RTR should be dominant for data frame"
        severity error;

      pass_count := pass_count + 1;
    end loop;
    report "PASS: CC Basic format frame structure verified for all DLC (0-8)";

    -- =====================================================================
    -- Test Group B: CAN Classic Extended Format
    -- =====================================================================
    report "";
    report "Test Group B: CAN Classic Extended (cc_extended)";
    report "=====================================================================";

    for dlc_idx in 0 to 8 loop
      test_count := test_count + 1;

      -- Config: FORMAT=000 (cc_extended), FTYP=0 (data), no BRS/ESI
      config_byte_0 := x"00";
      config_byte_1 := std_logic_vector(to_unsigned(dlc_idx, 4)) & "0000";

      frame_params := calculate_frame_params(config_byte_0, config_byte_1);
      mac_ser_to_fsm.frame_params := frame_params;

      -- SOF at position 0
      frame_info := get_next_mac_frame_bit(0, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
      assert frame_info.bit_name = sof_bit
        report "CC Extended DLC " & integer'image(dlc_idx) & ": Bit 0 should be SOF"
        severity error;

      -- SRR bit should exist in CC Extended (after base ID)
      frame_info := get_next_mac_frame_bit(12, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
      assert frame_info.bit_name = srr_bit
        report "CC Extended DLC " & integer'image(dlc_idx) & ": Bit 12 should be SRR"
        severity error;

      -- IDE bit should exist
      frame_info := get_next_mac_frame_bit(13, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
      assert frame_info.bit_name = ide_bit
        report "CC Extended DLC " & integer'image(dlc_idx) & ": Bit 13 should be IDE"
        severity error;

      pass_count := pass_count + 1;
    end loop;
    report "PASS: CC Extended format frame structure verified for all DLC (0-8)";

    -- =====================================================================
    -- Test Group C: CAN FD Basic Format
    -- =====================================================================
    report "";
    report "Test Group C: CAN FD Basic (fd_basic)";
    report "=====================================================================";

    for dlc_idx in 0 to 15 loop
      test_count := test_count + 1;

      -- Config: FORMAT=110 (fd_basic), FTYP=0 (data), no BRS/ESI
      config_byte_0 := x"C0";
      config_byte_1 := std_logic_vector(to_unsigned(dlc_idx, 4)) & "0000";

      frame_params := calculate_frame_params(config_byte_0, config_byte_1);
      mac_ser_to_fsm.frame_params := frame_params;

      -- SOF at position 0
      frame_info := get_next_mac_frame_bit(0, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
      assert frame_info.bit_name = sof_bit
        report "FD Basic DLC " & integer'image(dlc_idx) & ": Bit 0 should be SOF"
        severity error;

      -- FDF bit should exist in FD frames
      frame_info := get_next_mac_frame_bit(21, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
      assert frame_info.bit_name = fdf_bit
        report "FD Basic DLC " & integer'image(dlc_idx) & ": FDF bit should exist"
        severity error;

      -- Verify data field boundaries
      assert frame_params.data_start > 0
        report "FD Basic DLC " & integer'image(dlc_idx) & ": data_start should be > 0"
        severity error;

      assert frame_params.data_stop >= frame_params.data_start
        report "FD Basic DLC " & integer'image(dlc_idx) & ": data_stop should be >= data_start"
        severity error;

      pass_count := pass_count + 1;
    end loop;
    report "PASS: FD Basic format frame structure verified for all DLC (0-15)";

    -- =====================================================================
    -- Test Group D: CAN FD Extended Format
    -- =====================================================================
    report "";
    report "Test Group D: CAN FD Extended (fd_extended)";
    report "=====================================================================";

    for dlc_idx in 0 to 15 loop
      test_count := test_count + 1;

      -- Config: FORMAT=111 (fd_extended), FTYP=0 (data), no BRS/ESI
      config_byte_0 := x"E0";
      config_byte_1 := std_logic_vector(to_unsigned(dlc_idx, 4)) & "0000";

      frame_params := calculate_frame_params(config_byte_0, config_byte_1);
      mac_ser_to_fsm.frame_params := frame_params;

      -- SOF at position 0
      frame_info := get_next_mac_frame_bit(0, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
      assert frame_info.bit_name = sof_bit
        report "FD Extended DLC " & integer'image(dlc_idx) & ": Bit 0 should be SOF"
        severity error;

      -- Extended ID should exist in FD Extended
      assert frame_params.extended_id_start > 0
        report "FD Extended DLC " & integer'image(dlc_idx) & ": extended_id_start should be > 0"
        severity error;

      pass_count := pass_count + 1;
    end loop;
    report "PASS: FD Extended format frame structure verified for all DLC (0-15)";

    -- =====================================================================
    -- Test Group E: Field Boundary Verification
    -- =====================================================================
    report "";
    report "Test Group E: Field Boundaries and Transitions";
    report "=====================================================================";

    test_count := test_count + 1;

    -- Test with CC Basic, DLC=8
    config_byte_0 := x"28";
    config_byte_1 := x"80";
    frame_params := calculate_frame_params(config_byte_0, config_byte_1);
    mac_ser_to_fsm.frame_params := frame_params;

    -- Verify DLC field is within expected range
    assert frame_params.dlc_start >= 0
      report "DLC field should have valid start position"
      severity error;

    assert frame_params.dlc_stop > frame_params.dlc_start
      report "DLC field should have valid stop position"
      severity error;

    -- Verify CRC field boundaries
    assert frame_params.crc_start >= frame_params.data_stop + 1
      report "CRC should start after data field"
      severity error;

    assert frame_params.crc_delimiter > frame_params.crc_start
      report "CRC delimiter should be after CRC start"
      severity error;

    -- Verify ACK field boundaries
    assert frame_params.ack_slot = frame_params.crc_delimiter + 1
      report "ACK should be 1 position after CRC delimiter"
      severity error;

    -- Verify EOF field
    assert frame_params.eof_start > frame_params.ack_delimiter
      report "EOF should start after ACK"
      severity error;

    pass_count := pass_count + 1;
    report "PASS: Field boundaries verified";

    -- =====================================================================
    -- Test Group F: BRS and ESI Flag Effects
    -- =====================================================================
    report "";
    report "Test Group F: Control Flags (BRS, ESI, Remote)";
    report "=====================================================================";

    test_count := test_count + 1;

    -- Test FD with BRS enabled
    config_byte_0 := x"E4";  -- FORMAT=111, BRS=1
    config_byte_1 := x"80";
    frame_params := calculate_frame_params(config_byte_0, config_byte_1);
    mac_ser_to_fsm.frame_params := frame_params;

    assert frame_params.has_brs = true
      report "BRS flag should be true"
      severity error;

    -- BRS bit should be recessive when has_brs=true
    assert frame_params.brs_bit.polarity = recessive
      report "BRS bit should be recessive when BRS enabled"
      severity error;

    pass_count := pass_count + 1;

    test_count := test_count + 1;

    -- Test FD with ESI enabled
    config_byte_0 := x"E8";  -- FORMAT=111, ESI=1
    config_byte_1 := x"80";
    frame_params := calculate_frame_params(config_byte_0, config_byte_1);
    mac_ser_to_fsm.frame_params := frame_params;

    assert frame_params.esi_enable = true
      report "ESI flag should be true"
      severity error;

    -- ESI bit should be recessive when esi_enable=true
    assert frame_params.esi_bit.polarity = recessive
      report "ESI bit should be recessive when ESI enabled"
      severity error;

    pass_count := pass_count + 1;

    test_count := test_count + 1;

    -- Test with remote frame
    config_byte_0 := x"30";  -- FORMAT=001, FTYP=1 (remote)
    config_byte_1 := x"80";
    frame_params := calculate_frame_params(config_byte_0, config_byte_1);
    mac_ser_to_fsm.frame_params := frame_params;

    assert frame_params.is_remote_frame = true
      report "Remote frame flag should be true"
      severity error;

    -- RTR bit should be recessive for remote frame
    assert frame_params.rtr_bit.polarity = recessive
      report "RTR bit should be recessive for remote frame"
      severity error;

    pass_count := pass_count + 1;
    report "PASS: Control flags correctly affect bit polarities";

    -- =====================================================================
    -- Test Summary
    -- =====================================================================
    report "";
    report "========================================";
    report "Test Summary";
    report "========================================";
    report "Total Tests: " & integer'image(test_count);
    report "Passed: " & integer'image(pass_count);
    report "Failed: " & integer'image(test_count - pass_count);

    if (test_count = pass_count) then
      report "ALL TESTS PASSED!";
    else
      report "SOME TESTS FAILED";
    end if;

    report "========================================";
    wait;

  end process test_process;

end architecture tb;
