library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_pkg.all;

entity get_next_mac_frame_bit_tb is
end entity get_next_mac_frame_bit_tb;

architecture tb of get_next_mac_frame_bit_tb is

  function get_expected_bit_name (
    bit_position : integer;
    format : can_format_t;
    frame_params : frame_params_t
  ) return mac_frame_bit_name_t is
    variable result : mac_frame_bit_name_t := unknown;
  begin
    -- SOF bit is always at position 0
    if (bit_position = sof_c) then
      return sof_bit;
    end if;

    case format is
      when cc_basic =>
        if (bit_position >= cb_base_id_start_c.position and bit_position <= frame_params.base_id_stop) then
          result := base_id_bit;
        elsif (bit_position = frame_params.rtr_bit.position) then
          result := rtr_bit;
        elsif (bit_position = frame_params.ide_bit.position) then
          result := ide_bit;
        elsif (bit_position = frame_params.r0_bit.position) then
          result := r0_bit;
        elsif (bit_position >= frame_params.dlc_start and bit_position < frame_params.dlc_stop) then
          result := dlc_bit;
        elsif (bit_position >= frame_params.data_start and bit_position <= frame_params.data_stop) then
          result := data_bit;
        elsif (bit_position >= frame_params.crc_start and bit_position < frame_params.crc_stop) then
          result := crc_bit;
        elsif (bit_position = frame_params.crc_delimiter) then
          result := crc_delimiter_bit;
        elsif (bit_position = frame_params.ack_slot) then
          result := ack_bit;
        elsif (bit_position = frame_params.ack_delimiter) then
          result := ack_delimiter_bit;
        elsif (bit_position >= frame_params.eof_start and bit_position < frame_params.eof_stop) then
          result := eof_bit;
        end if;

      when cc_extended =>
        if (bit_position >= frame_params.base_id_start and bit_position <= frame_params.base_id_stop) then
          result := base_id_bit;
        elsif (bit_position = frame_params.srr_bit.position) then
          result := srr_bit;
        elsif (bit_position = frame_params.ide_bit.position) then
          result := ide_bit;
        elsif (bit_position >= frame_params.extended_id_start and bit_position <= frame_params.extended_id_stop) then
          result := extended_id_bit;
        elsif (bit_position = frame_params.rtr_bit.position) then
          result := rtr_bit;
        elsif (bit_position = frame_params.r1_bit.position) then
          result := r1_bit;
        elsif (bit_position = frame_params.r0_bit.position) then
          result := r0_bit;
        elsif (bit_position >= frame_params.dlc_start and bit_position < frame_params.dlc_stop) then
          result := dlc_bit;
        elsif (bit_position >= frame_params.data_start and bit_position <= frame_params.data_stop) then
          result := data_bit;
        elsif (bit_position >= frame_params.crc_start and bit_position < frame_params.crc_stop) then
          result := crc_bit;
        elsif (bit_position = frame_params.crc_delimiter) then
          result := crc_delimiter_bit;
        elsif (bit_position = frame_params.ack_slot) then
          result := ack_bit;
        elsif (bit_position = frame_params.ack_delimiter) then
          result := ack_delimiter_bit;
        elsif (bit_position >= frame_params.eof_start and bit_position < frame_params.eof_stop) then
          result := eof_bit;
        end if;

      when fd_basic =>
        if (bit_position >= frame_params.base_id_start and bit_position <= frame_params.base_id_stop) then
          result := base_id_bit;
        elsif (bit_position = frame_params.rrs_bit.position) then
          result := rrs_bit;
        elsif (bit_position = frame_params.ide_bit.position) then
          result := ide_bit;
        elsif (bit_position = frame_params.fdf_bit.position) then
          result := fdf_bit;
        elsif (bit_position = frame_params.res_bit.position) then
          result := res_bit;
        elsif (bit_position = frame_params.brs_bit.position) then
          result := brs_bit;
        elsif (bit_position = frame_params.esi_bit.position) then
          result := esi_bit;
        elsif (bit_position >= frame_params.dlc_start and bit_position < frame_params.dlc_stop) then
          result := dlc_bit;
        elsif (bit_position >= frame_params.data_start and bit_position <= frame_params.data_stop) then
          result := data_bit;
        elsif (bit_position >= frame_params.sbc_start and bit_position < frame_params.crc_stop) then
          -- Check for fixed stuff bits in SBC/CRC region
          if is_fixed_stuff_bit_position(bit_position - frame_params.sbc_start) then
            result := fixed_stuff_bit;
          elsif (bit_position >= frame_params.sbc_start and bit_position < frame_params.sbc_stop) then
            result := sbs_bit;
          else
            result := crc_bit;
          end if;
        elsif (bit_position = frame_params.crc_delimiter) then
          result := crc_delimiter_bit;
        elsif (bit_position = frame_params.ack_slot) then
          result := ack_bit;
        elsif (bit_position = frame_params.ack_delimiter) then
          result := ack_delimiter_bit;
        elsif (bit_position >= frame_params.eof_start and bit_position < frame_params.eof_stop) then
          result := eof_bit;
        end if;

      when fd_extended =>
        if (bit_position >= frame_params.base_id_start and bit_position <= frame_params.base_id_stop) then
          result := base_id_bit;
        elsif (bit_position = frame_params.srr_bit.position) then
          result := srr_bit;
        elsif (bit_position = frame_params.ide_bit.position) then
          result := ide_bit;
        elsif (bit_position >= frame_params.extended_id_start and bit_position <= frame_params.extended_id_stop) then
          result := extended_id_bit;
        elsif (bit_position = frame_params.rrs_bit.position) then
          result := rrs_bit;
        elsif (bit_position = frame_params.fdf_bit.position) then
          result := fdf_bit;
        elsif (bit_position = frame_params.res_bit.position) then
          result := res_bit;
        elsif (bit_position = frame_params.brs_bit.position) then
          result := brs_bit;
        elsif (bit_position = frame_params.esi_bit.position) then
          result := esi_bit;
        elsif (bit_position >= frame_params.dlc_start and bit_position < frame_params.dlc_stop) then
          result := dlc_bit;
        elsif (bit_position >= frame_params.data_start and bit_position <= frame_params.data_stop) then
          result := data_bit;
        elsif (bit_position >= frame_params.sbc_start and bit_position < frame_params.crc_stop) then
          -- Check for fixed stuff bits in SBC/CRC region
          if is_fixed_stuff_bit_position(bit_position - frame_params.sbc_start) then
            result := fixed_stuff_bit;
          elsif (bit_position >= frame_params.sbc_start and bit_position < frame_params.sbc_stop) then
            result := sbs_bit;
          else
            result := crc_bit;
          end if;
        elsif (bit_position = frame_params.crc_delimiter) then
          result := crc_delimiter_bit;
        elsif (bit_position = frame_params.ack_slot) then
          result := ack_bit;
        elsif (bit_position = frame_params.ack_delimiter) then
          result := ack_delimiter_bit;
        elsif (bit_position >= frame_params.eof_start and bit_position < frame_params.eof_stop) then
          result := eof_bit;
        end if;

      when unknown =>
        result := unknown;
    end case;

    return result;
  end function get_expected_bit_name;

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
    variable expected_name   : mac_frame_bit_name_t;

  begin

    report "========================================";
    report "get_next_mac_frame_bit: Validation Test";
    report "========================================";

    test_count := 0;
    pass_count := 0;

    -- Initialize test vectors
    crc_vec := (others => '1');
    sbc_vec := (others => '0');
    prev_polarity := dominant;

    -- =====================================================================
    -- Test Group A: CAN Classic Basic - All DLC, All Bit Positions
    -- =====================================================================
    report "";
    report "Test Group A: CAN Classic Basic - Verify Bit Types";
    report "=====================================================================" ;

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
        expected_name := get_expected_bit_name(bit_position, cc_basic, frame_params);

        -- Verify correct bit type is returned
        assert frame_info.bit_name = expected_name
          report "CC Basic DLC " & integer'image(dlc_idx) & " Bit " & integer'image(bit_position) &
                 ": Expected " & mac_frame_bit_name_t'image(expected_name) &
                 " but got " & mac_frame_bit_name_t'image(frame_info.bit_name)
          severity failure;

        bits_verified := bits_verified + 1;
        prev_polarity := frame_info.polarity;
      end loop;

      report "  DLC " & integer'image(dlc_idx) & ": " & integer'image(bits_verified) & " bits verified with correct types";
      pass_count := pass_count + 1;
    end loop;
    report "PASS: CC Basic - All bit types correct for DLC 0-8";

    -- =====================================================================
    -- Test Group B: CAN Classic Extended - All DLC, All Bit Positions
    -- =====================================================================
    report "";
    report "Test Group B: CAN Classic Extended - Verify Bit Types";
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
        expected_name := get_expected_bit_name(bit_position, cc_extended, frame_params);

        assert frame_info.bit_name = expected_name
          report "CC Extended DLC " & integer'image(dlc_idx) & " Bit " & integer'image(bit_position) &
                 ": Expected " & mac_frame_bit_name_t'image(expected_name) &
                 " but got " & mac_frame_bit_name_t'image(frame_info.bit_name)
          severity failure;

        bits_verified := bits_verified + 1;
        prev_polarity := frame_info.polarity;
      end loop;

      report "  DLC " & integer'image(dlc_idx) & ": " & integer'image(bits_verified) & " bits verified with correct types";
      pass_count := pass_count + 1;
    end loop;
    report "PASS: CC Extended - All bit types correct for DLC 0-8";

    -- =====================================================================
    -- Test Group C: CAN FD Basic - All DLC, All Bit Positions
    -- =====================================================================
    report "";
    report "Test Group C: CAN FD Basic - Verify Bit Types";
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
        expected_name := get_expected_bit_name(bit_position, fd_basic, frame_params);

        assert frame_info.bit_name = expected_name
          report "FD Basic DLC " & integer'image(dlc_idx) & " Bit " & integer'image(bit_position) &
                 ": Expected " & mac_frame_bit_name_t'image(expected_name) &
                 " but got " & mac_frame_bit_name_t'image(frame_info.bit_name)
          severity failure;

        bits_verified := bits_verified + 1;
        prev_polarity := frame_info.polarity;
      end loop;

      report "  DLC " & integer'image(dlc_idx) & ": " & integer'image(bits_verified) & " bits verified with correct types";
      pass_count := pass_count + 1;
    end loop;
    report "PASS: FD Basic - All bit types correct for DLC 0-15";

    -- =====================================================================
    -- Test Group D: CAN FD Extended - All DLC, All Bit Positions
    -- =====================================================================
    report "";
    report "Test Group D: CAN FD Extended - Verify Bit Types";
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
        expected_name := get_expected_bit_name(bit_position, fd_extended, frame_params);

        assert frame_info.bit_name = expected_name
          report "FD Extended DLC " & integer'image(dlc_idx) & " Bit " & integer'image(bit_position) &
                 ": Expected " & mac_frame_bit_name_t'image(expected_name) &
                 " but got " & mac_frame_bit_name_t'image(frame_info.bit_name)
          severity failure;

        bits_verified := bits_verified + 1;
        prev_polarity := frame_info.polarity;
      end loop;

      report "  DLC " & integer'image(dlc_idx) & ": " & integer'image(bits_verified) & " bits verified with correct types";
      pass_count := pass_count + 1;
    end loop;
    report "PASS: FD Extended - All bit types correct for DLC 0-15";

    -- =====================================================================
    -- Test Summary
    -- =====================================================================
    report "";
    report "========================================";
    report "Bit Type Validation Summary";
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
