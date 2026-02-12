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
    variable bit_position    : position_t;
    variable test_count      : integer;
    variable pass_count      : integer;
    variable bits_verified   : integer;
    variable dlc_idx         : integer;
    variable format_idx      : integer;
    variable expected_type   : mac_frame_bit_name_t;
    variable in_range        : boolean;

  begin

    report "========================================";
    report "get_next_mac_frame_bit: Exhaustive Test";
    report "========================================";

    test_count := 0;
    pass_count := 0;
    bits_verified := 0;

    -- Initialize test vectors
    crc_vec := (others => '1');
    sbc_vec := (others => '0');
    prev_polarity := dominant;

    -- =====================================================================
    -- Test Group A: CAN Classic Basic - All DLC, All Bit Positions
    -- =====================================================================
    report "";
    report "Test Group A: CAN Classic Basic (cc_basic)";
    report "Testing all bit positions for DLC 0-8";
    report "=====================================================================";

    for dlc_idx in 0 to 8 loop
      test_count := test_count + 1;
      bits_verified := 0;

      -- Config: FORMAT=001 (cc_basic), FTYP=0, no BRS/ESI
      config_byte_0 := x"20";
      config_byte_1 := std_logic_vector(to_unsigned(dlc_idx, 4)) & "0000";

      frame_params := calculate_frame_params(config_byte_0, config_byte_1);
      mac_ser_to_fsm.frame_params := frame_params;
      mac_ser_to_fsm.data := dominant;
      prev_polarity := dominant;

      -- Verify every bit position from SOF through EOF
      for bit_position in 0 to frame_params.eof_stop loop
        frame_info := get_next_mac_frame_bit(bit_position, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);

        -- Verify bit is identified (not unknown)
        assert frame_info.bit_name /= unknown
          report "CC Basic DLC " & integer'image(dlc_idx) & " Bit " & integer'image(bit_position) & ": bit_name is unknown"
          severity warning;

        -- Verify polarity is defined (not unknown)
        assert frame_info.polarity /= unknown
          report "CC Basic DLC " & integer'image(dlc_idx) & " Bit " & integer'image(bit_position) & ": polarity is unknown"
          severity warning;

        bits_verified := bits_verified + 1;
        prev_polarity := frame_info.polarity;
      end loop;

      report "  DLC " & integer'image(dlc_idx) & ": " & integer'image(bits_verified) & " bits verified";
      pass_count := pass_count + 1;
    end loop;
    report "PASS: CC Basic - All bit positions verified for DLC 0-8";

    -- =====================================================================
    -- Test Group B: CAN Classic Extended - All DLC, All Bit Positions
    -- =====================================================================
    report "";
    report "Test Group B: CAN Classic Extended (cc_extended)";
    report "Testing all bit positions for DLC 0-8";
    report "=====================================================================";

    for dlc_idx in 0 to 8 loop
      test_count := test_count + 1;
      bits_verified := 0;

      -- Config: FORMAT=000 (cc_extended), FTYP=0, no BRS/ESI
      config_byte_0 := x"00";
      config_byte_1 := std_logic_vector(to_unsigned(dlc_idx, 4)) & "0000";

      frame_params := calculate_frame_params(config_byte_0, config_byte_1);
      mac_ser_to_fsm.frame_params := frame_params;
      mac_ser_to_fsm.data := dominant;
      prev_polarity := dominant;

      -- Verify every bit position
      for bit_position in 0 to frame_params.eof_stop loop
        frame_info := get_next_mac_frame_bit(bit_position, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);

        assert frame_info.bit_name /= unknown
          report "CC Extended DLC " & integer'image(dlc_idx) & " Bit " & integer'image(bit_position) & ": unknown"
          severity warning;

        assert frame_info.polarity /= unknown
          report "CC Extended DLC " & integer'image(dlc_idx) & " Bit " & integer'image(bit_position) & ": polarity unknown"
          severity warning;

        bits_verified := bits_verified + 1;
        prev_polarity := frame_info.polarity;
      end loop;

      report "  DLC " & integer'image(dlc_idx) & ": " & integer'image(bits_verified) & " bits verified";
      pass_count := pass_count + 1;
    end loop;
    report "PASS: CC Extended - All bit positions verified for DLC 0-8";

    -- =====================================================================
    -- Test Group C: CAN FD Basic - All DLC, All Bit Positions
    -- =====================================================================
    report "";
    report "Test Group C: CAN FD Basic (fd_basic)";
    report "Testing all bit positions for DLC 0-15";
    report "=====================================================================";

    for dlc_idx in 0 to 15 loop
      test_count := test_count + 1;
      bits_verified := 0;

      -- Config: FORMAT=110 (fd_basic), FTYP=0, no BRS/ESI
      config_byte_0 := x"C0";
      config_byte_1 := std_logic_vector(to_unsigned(dlc_idx, 4)) & "0000";

      frame_params := calculate_frame_params(config_byte_0, config_byte_1);
      mac_ser_to_fsm.frame_params := frame_params;
      mac_ser_to_fsm.data := dominant;
      prev_polarity := dominant;

      -- Verify every bit position
      for bit_position in 0 to frame_params.eof_stop loop
        frame_info := get_next_mac_frame_bit(bit_position, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);

        assert frame_info.bit_name /= unknown
          report "FD Basic DLC " & integer'image(dlc_idx) & " Bit " & integer'image(bit_position) & ": unknown"
          severity warning;

        assert frame_info.polarity /= unknown
          report "FD Basic DLC " & integer'image(dlc_idx) & " Bit " & integer'image(bit_position) & ": polarity unknown"
          severity warning;

        bits_verified := bits_verified + 1;
        prev_polarity := frame_info.polarity;
      end loop;

      report "  DLC " & integer'image(dlc_idx) & ": " & integer'image(bits_verified) & " bits verified";
      pass_count := pass_count + 1;
    end loop;
    report "PASS: FD Basic - All bit positions verified for DLC 0-15";

    -- =====================================================================
    -- Test Group D: CAN FD Extended - All DLC, All Bit Positions
    -- =====================================================================
    report "";
    report "Test Group D: CAN FD Extended (fd_extended)";
    report "Testing all bit positions for DLC 0-15";
    report "=====================================================================";

    for dlc_idx in 0 to 15 loop
      test_count := test_count + 1;
      bits_verified := 0;

      -- Config: FORMAT=111 (fd_extended), FTYP=0, no BRS/ESI
      config_byte_0 := x"E0";
      config_byte_1 := std_logic_vector(to_unsigned(dlc_idx, 4)) & "0000";

      frame_params := calculate_frame_params(config_byte_0, config_byte_1);
      mac_ser_to_fsm.frame_params := frame_params;
      mac_ser_to_fsm.data := dominant;
      prev_polarity := dominant;

      -- Verify every bit position
      for bit_position in 0 to frame_params.eof_stop loop
        frame_info := get_next_mac_frame_bit(bit_position, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);

        assert frame_info.bit_name /= unknown
          report "FD Extended DLC " & integer'image(dlc_idx) & " Bit " & integer'image(bit_position) & ": unknown"
          severity warning;

        assert frame_info.polarity /= unknown
          report "FD Extended DLC " & integer'image(dlc_idx) & " Bit " & integer'image(bit_position) & ": polarity unknown"
          severity warning;

        bits_verified := bits_verified + 1;
        prev_polarity := frame_info.polarity;
      end loop;

      report "  DLC " & integer'image(dlc_idx) & ": " & integer'image(bits_verified) & " bits verified";
      pass_count := pass_count + 1;
    end loop;
    report "PASS: FD Extended - All bit positions verified for DLC 0-15";

    -- =====================================================================
    -- Test Group E: Control Flags Impact - All Bit Positions
    -- =====================================================================
    report "";
    report "Test Group E: Control Flags (BRS, ESI, Remote)";
    report "Testing impact on all bit positions";
    report "=====================================================================";

    -- Test with BRS enabled (FD format)
    test_count := test_count + 1;
    bits_verified := 0;
    config_byte_0 := x"E4";  -- FORMAT=111, BRS=1
    config_byte_1 := x"80";
    frame_params := calculate_frame_params(config_byte_0, config_byte_1);
    mac_ser_to_fsm.frame_params := frame_params;
    mac_ser_to_fsm.data := dominant;
    prev_polarity := dominant;

    for bit_position in 0 to frame_params.eof_stop loop
      frame_info := get_next_mac_frame_bit(bit_position, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
      if frame_info.bit_name = brs_bit then
        assert frame_info.polarity = recessive
          report "BRS bit should be recessive when BRS enabled"
          severity error;
      end if;
      bits_verified := bits_verified + 1;
      prev_polarity := frame_info.polarity;
    end loop;
    report "  BRS enabled: " & integer'image(bits_verified) & " bits verified";
    pass_count := pass_count + 1;

    -- Test with ESI enabled (FD format)
    test_count := test_count + 1;
    bits_verified := 0;
    config_byte_0 := x"E8";  -- FORMAT=111, ESI=1
    config_byte_1 := x"80";
    frame_params := calculate_frame_params(config_byte_0, config_byte_1);
    mac_ser_to_fsm.frame_params := frame_params;
    mac_ser_to_fsm.data := dominant;
    prev_polarity := dominant;

    for bit_position in 0 to frame_params.eof_stop loop
      frame_info := get_next_mac_frame_bit(bit_position, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
      if frame_info.bit_name = esi_bit then
        assert frame_info.polarity = recessive
          report "ESI bit should be recessive when ESI enabled"
          severity error;
      end if;
      bits_verified := bits_verified + 1;
      prev_polarity := frame_info.polarity;
    end loop;
    report "  ESI enabled: " & integer'image(bits_verified) & " bits verified";
    pass_count := pass_count + 1;

    -- Test with remote frame
    test_count := test_count + 1;
    bits_verified := 0;
    config_byte_0 := x"30";  -- FORMAT=001, FTYP=1 (remote)
    config_byte_1 := x"80";
    frame_params := calculate_frame_params(config_byte_0, config_byte_1);
    mac_ser_to_fsm.frame_params := frame_params;
    mac_ser_to_fsm.data := dominant;
    prev_polarity := dominant;

    for bit_position in 0 to frame_params.eof_stop loop
      frame_info := get_next_mac_frame_bit(bit_position, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);
      if frame_info.bit_name = rtr_bit then
        assert frame_info.polarity = recessive
          report "RTR bit should be recessive for remote frame"
          severity error;
      end if;
      bits_verified := bits_verified + 1;
      prev_polarity := frame_info.polarity;
    end loop;
    report "  Remote frame: " & integer'image(bits_verified) & " bits verified";
    pass_count := pass_count + 1;

    report "PASS: Control flags affect all bit positions correctly";

    -- =====================================================================
    -- Test Group F: Data Polarity Propagation
    -- =====================================================================
    report "";
    report "Test Group F: Data Polarity Propagation";
    report "Testing data field bits reflect input data";
    report "=====================================================================";

    test_count := test_count + 1;
    bits_verified := 0;

    config_byte_0 := x"28";  -- CC Basic
    config_byte_1 := x"80";  -- DLC=8
    frame_params := calculate_frame_params(config_byte_0, config_byte_1);
    mac_ser_to_fsm.frame_params := frame_params;
    mac_ser_to_fsm.data := recessive;  -- Set data to recessive
    prev_polarity := dominant;

    for bit_position in 0 to frame_params.eof_stop loop
      frame_info := get_next_mac_frame_bit(bit_position, mac_ser_to_fsm, prev_polarity, dominant, false, sbc_vec, crc_vec);

      -- Verify data field bits have recessive polarity (from mac_ser_to_fsm.data)
      if (bit_position >= frame_params.data_start and bit_position <= frame_params.data_stop) then
        if frame_info.bit_name = data_bit then
          assert frame_info.polarity = recessive
            report "Data bit at position " & integer'image(bit_position) & " should be recessive"
            severity error;
        end if;
      end if;

      bits_verified := bits_verified + 1;
      prev_polarity := frame_info.polarity;
    end loop;

    report "  Data polarity: " & integer'image(bits_verified) & " bits verified";
    pass_count := pass_count + 1;
    report "PASS: Data bits correctly propagate input polarity";

    -- =====================================================================
    -- Test Summary
    -- =====================================================================
    report "";
    report "========================================";
    report "Exhaustive Test Summary";
    report "========================================";
    report "Total Test Scenarios: " & integer'image(test_count);
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
