--------------------------------------------------------------------------------
-- Title      : CAN Protocol Package Testbench
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_pkg_tb.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Walks every bit position of one CB, CE, FB, and FE frame,
--              checking that get_next_mac_frame_bit returns the correct
--              bit_name and polarity. Also exercises calculate_frame_params.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;
  use work.can_protocol_pkg.all;

entity can_pkg_tb is
end entity can_pkg_tb;

architecture tb of can_pkg_tb is

  -- Helper: build t_llc_metadata from config bytes
  function make_metadata (
    config_byte_0 : t_byte;
    config_byte_1 : t_byte
  ) return t_llc_metadata is
    variable m : t_llc_metadata;
  begin
    m.format          := config_byte_0(c_llc_frame_config_byte_0_format_start downto c_llc_frame_config_byte_0_format_end);
    m.dlc_vector      := config_byte_1(c_llc_frame_config_byte_1_dlc_start downto c_llc_frame_config_byte_1_dlc_end);
    m.is_remote_frame := config_byte_0(c_llc_frame_config_byte_0_ftyp);
    m.has_brs         := config_byte_0(c_llc_frame_config_byte_0_brs);
    m.esi_enable      := config_byte_0(c_llc_frame_config_byte_0_esi);
    return m;
  end function make_metadata;

  -- Helper: derive eof_stop, crc_delimiter, ack_slot, ack_delimiter, eof_start
  -- from fp.crc_stop (inline derivation matching get_next_mac_frame_bit)
  function crc_delimiter_of (fp : t_frame_params) return t_position is
  begin
    return fp.crc_stop;
  end function crc_delimiter_of;

  function ack_slot_of (fp : t_frame_params) return t_position is
  begin
    return fp.crc_stop + c_ack_slot_offset;
  end function ack_slot_of;

  function ack_delimiter_of (fp : t_frame_params) return t_position is
  begin
    return fp.crc_stop + c_ack_delimiter_offset;
  end function ack_delimiter_of;

  function eof_start_of (fp : t_frame_params) return t_position is
  begin
    return fp.crc_stop + c_eof_start_offset;
  end function eof_start_of;

  function eof_stop_of (fp : t_frame_params) return t_position is
  begin
    return fp.crc_stop + c_eof_start_offset + c_eof_field_width;
  end function eof_stop_of;

  function data_start_of (fp : t_frame_params) return t_position is
  begin
    case fp.format is
      when c_llc_fmt_cb => return c_cb_data_start.position;
      when c_llc_fmt_ce => return c_ce_data_start.position;
      when c_llc_fmt_fb => return c_fb_data_start.position;
      when c_llc_fmt_fe => return c_fe_data_start.position;
      when others       => return 0;
    end case;
  end function data_start_of;

  function sbc_start_of (fp : t_frame_params) return t_position is
  begin
    if (fp.is_fd_frame = '1') then
      return fp.data_stop + 1;
    else
      return 0;
    end if;
  end function sbc_start_of;

  function sbc_stop_of (fp : t_frame_params) return t_position is
  begin
    if (fp.is_fd_frame = '1') then
      return fp.data_stop + 1 + c_sbc_field_width;
    else
      return 0;
    end if;
  end function sbc_stop_of;

  function crc_start_of (fp : t_frame_params) return t_position is
  begin
    if (fp.is_fd_frame = '1') then
      return fp.data_stop + 1 + c_sbc_field_width;
    else
      return fp.data_stop + 1;
    end if;
  end function crc_start_of;

begin

  test_process : process is

    variable fp             : t_frame_params;
    variable ser_data_v     : std_logic;
    variable fb             : t_mac_frame_bit;
    variable crc_vec        : t_crc_vector  := (others => '0');
    variable sbc_vec        : t_sbc         := (others => '0');
    variable prev_pol       : std_logic     := c_recessive;
    variable test_count     : integer       := 0;
    variable fail_count     : integer       := 0;
    variable eof_stop_v     : integer;

    -- Check one bit: verify bit_name, and optionally polarity
    procedure check_bit (
      bit_pos       : in integer;
      expected_name : in t_mac_frame_bit_name;
      expected_pol  : in std_logic := 'X';
      tag           : in string    := ""
    ) is
    begin
      test_count := test_count + 1;
      fb := get_next_mac_frame_bit(bit_pos, ser_data_v, fp, prev_pol, sbc_vec, crc_vec);

      if (fb.bit_name /= expected_name) then
        report tag & " pos " & integer'image(bit_pos) &
               ": expected " & t_mac_frame_bit_name'image(expected_name) &
               " got " & t_mac_frame_bit_name'image(fb.bit_name)
          severity error;
        fail_count := fail_count + 1;
      end if;

      if (expected_pol /= 'X' and fb.polarity /= expected_pol) then
        report tag & " pos " & integer'image(bit_pos) &
               ": expected polarity " & std_logic'image(expected_pol) &
               " got " & std_logic'image(fb.polarity)
          severity error;
        fail_count := fail_count + 1;
      end if;
    end procedure check_bit;

    -- Check a range of bits all have the same expected name
    procedure check_range (
      first         : in integer;
      last          : in integer;
      expected_name : in t_mac_frame_bit_name;
      expected_pol  : in std_logic := 'X';
      tag           : in string    := ""
    ) is
    begin
      for i in first to last loop
        check_bit(i, expected_name, expected_pol, tag);
      end loop;
    end procedure check_range;

  begin

    -- Common setup: serializer drives all-recessive data
    ser_data_v := c_recessive;

    -- ==================================================================
    -- Frame 1: CAN Classic Basic (CB) - DLC=2, data frame
    -- Config: format=000, ftyp=0, esi=0, brs=0 -> byte0 = x"00"
    --         dlc=2                              -> byte1 = x"20"
    -- ==================================================================
    report "--- CB frame (DLC=2) ---";
    fp := calculate_frame_params(make_metadata(x"00", x"20"));

    assert fp.format = c_llc_fmt_cb report "CB: wrong format" severity error;
    assert fp.is_fd_frame = '0'     report "CB: should not be FD" severity error;

    check_bit(c_sof, sof_bit, c_dominant, "CB");
    check_range(c_cb_base_id_start.position, c_cb_base_id_stop.position, base_id_bit, tag => "CB");
    check_bit(c_cb_rtr.position, rtr_bit, c_dominant, "CB");
    check_bit(c_cb_ide.position, ide_bit, c_dominant, "CB");
    check_bit(c_cb_r0.position, r0_bit, c_dominant, "CB");
    check_range(c_cb_dlc_start.position, c_cb_dlc_stop.position, dlc_bit, tag => "CB");
    check_range(data_start_of(fp), fp.data_stop, data_bit, tag => "CB");
    check_range(crc_start_of(fp), fp.crc_stop - 1, crc_bit, tag => "CB");
    check_bit(crc_delimiter_of(fp), crc_delimiter_bit, c_recessive, "CB");
    check_bit(ack_slot_of(fp), ack_bit, c_recessive, "CB");
    check_bit(ack_delimiter_of(fp), ack_delimiter_bit, c_recessive, "CB");
    check_range(eof_start_of(fp), eof_stop_of(fp) - 1, eof_bit, c_recessive, "CB");

    report "CB: all bits checked";

    -- ==================================================================
    -- Frame 2: CAN Classic Extended (CE) - DLC=4, data frame
    -- Config: format=100, ftyp=0, esi=0, brs=0 -> byte0 = x"80"
    --         dlc=4                              -> byte1 = x"40"
    -- ==================================================================
    report "--- CE frame (DLC=4) ---";
    fp := calculate_frame_params(make_metadata(x"80", x"40"));

    assert fp.format = c_llc_fmt_ce report "CE: wrong format" severity error;

    check_bit(c_sof, sof_bit, c_dominant, "CE");
    check_range(c_ce_base_id_start.position, c_ce_base_id_stop.position, base_id_bit, tag => "CE");
    check_bit(c_ce_srr.position, srr_bit, c_recessive, "CE");
    check_bit(c_ce_ide.position, ide_bit, c_recessive, "CE");
    check_range(c_ce_extended_id_start.position, c_ce_extended_id_stop.position, extended_id_bit, tag => "CE");
    check_bit(c_ce_rtr.position, rtr_bit, c_dominant, "CE");
    check_bit(c_ce_r1.position, r1_bit, c_dominant, "CE");
    check_bit(c_ce_r0.position, r0_bit, c_dominant, "CE");
    check_range(c_ce_dlc_start.position, c_ce_dlc_stop.position, dlc_bit, tag => "CE");
    check_range(data_start_of(fp), fp.data_stop, data_bit, tag => "CE");
    check_range(crc_start_of(fp), fp.crc_stop - 1, crc_bit, tag => "CE");
    check_bit(crc_delimiter_of(fp), crc_delimiter_bit, c_recessive, "CE");
    check_bit(ack_slot_of(fp), ack_bit, c_recessive, "CE");
    check_bit(ack_delimiter_of(fp), ack_delimiter_bit, c_recessive, "CE");
    check_range(eof_start_of(fp), eof_stop_of(fp) - 1, eof_bit, c_recessive, "CE");

    report "CE: all bits checked";

    -- ==================================================================
    -- Frame 3: CAN FD Basic (FB) - DLC=8, BRS=1, ESI=0
    -- Config: format=010, ftyp=0, esi=0, brs=1 -> byte0 = x"44"
    --         dlc=8                              -> byte1 = x"80"
    -- ==================================================================
    report "--- FB frame (DLC=8, BRS=1) ---";
    fp := calculate_frame_params(make_metadata(x"44", x"80"));

    assert fp.format = c_llc_fmt_fb report "FB: wrong format" severity error;
    assert fp.is_fd_frame = '1'     report "FB: should be FD" severity error;
    assert fp.has_brs = '1'         report "FB: BRS should be set" severity error;

    check_bit(c_sof, sof_bit, c_dominant, "FB");
    check_range(c_fd_base_id_start.position, c_fd_base_id_stop.position, base_id_bit, tag => "FB");
    check_bit(c_fb_rrs.position, rrs_bit, c_dominant, "FB");
    check_bit(c_fb_ide.position, ide_bit, c_dominant, "FB");
    check_bit(c_fb_fdf.position, fdf_bit, c_recessive, "FB");
    check_bit(c_fb_res.position, res_bit, c_dominant, "FB");
    check_bit(c_fb_brs.position, brs_bit, c_recessive, "FB");
    check_bit(c_fb_esi.position, esi_bit, c_dominant, "FB");
    check_range(c_fb_dlc_start.position, c_fb_dlc_stop.position, dlc_bit, tag => "FB");
    check_range(data_start_of(fp), fp.data_stop, data_bit, tag => "FB");
    -- FD CRC field has fixed stuff bits interleaved - check SBC + CRC region
    -- SBC field
    -- SBC + CRC region (interleaved with fixed_stuff_bit in FD)
    for i in sbc_start_of(fp) to sbc_stop_of(fp) - 1 loop
      test_count := test_count + 1;
      fb := get_next_mac_frame_bit(i, ser_data_v, fp, prev_pol, sbc_vec, crc_vec);
      if (fb.bit_name /= sbs_bit and fb.bit_name /= fixed_stuff_bit) then
        report "FB: pos " & integer'image(i) & " unexpected " &
               t_mac_frame_bit_name'image(fb.bit_name) & " in SBC region"
          severity error;
        fail_count := fail_count + 1;
      end if;
    end loop;
    for i in crc_start_of(fp) to fp.crc_stop - 1 loop
      test_count := test_count + 1;
      fb := get_next_mac_frame_bit(i, ser_data_v, fp, prev_pol, sbc_vec, crc_vec);
      if (fb.bit_name /= crc_bit and fb.bit_name /= fixed_stuff_bit) then
        report "FB: pos " & integer'image(i) & " unexpected " &
               t_mac_frame_bit_name'image(fb.bit_name) & " in CRC region"
          severity error;
        fail_count := fail_count + 1;
      end if;
    end loop;
    check_bit(crc_delimiter_of(fp), crc_delimiter_bit, c_recessive, "FB");
    check_bit(ack_slot_of(fp), ack_bit, c_recessive, "FB");
    check_bit(ack_delimiter_of(fp), ack_delimiter_bit, c_recessive, "FB");
    check_range(eof_start_of(fp), eof_stop_of(fp) - 1, eof_bit, c_recessive, "FB");

    report "FB: all bits checked";

    -- ==================================================================
    -- Frame 4: CAN FD Extended (FE) - DLC=12 (=16 bytes), BRS=1, ESI=1
    -- Config: format=110, ftyp=0, esi=1, brs=1 -> byte0 = x"CC"
    --         dlc=12                             -> byte1 = x"C0"
    -- ==================================================================
    report "--- FE frame (DLC=12, BRS=1, ESI=1) ---";
    fp := calculate_frame_params(make_metadata(x"CC", x"C0"));

    assert fp.format = c_llc_fmt_fe report "FE: wrong format" severity error;
    assert fp.is_fd_frame = '1'     report "FE: should be FD" severity error;
    assert fp.has_brs = '1'         report "FE: BRS should be set" severity error;
    assert fp.esi_enable = '1'      report "FE: ESI should be set" severity error;

    check_bit(c_sof, sof_bit, c_dominant, "FE");
    check_range(c_fe_base_id_start.position, c_fe_base_id_stop.position, base_id_bit, tag => "FE");
    check_bit(c_fe_srr.position, srr_bit, c_recessive, "FE");
    check_bit(c_fe_ide.position, ide_bit, c_recessive, "FE");
    check_range(c_fe_extended_id_start.position, c_fe_extended_id_stop.position, extended_id_bit, tag => "FE");
    check_bit(c_fe_rrs.position, rrs_bit, c_dominant, "FE");
    check_bit(c_fe_fdf.position, fdf_bit, c_recessive, "FE");
    check_bit(c_fe_res.position, res_bit, c_dominant, "FE");
    check_bit(c_fe_brs.position, brs_bit, c_recessive, "FE");
    check_bit(c_fe_esi.position, esi_bit, c_recessive, "FE");
    check_range(c_fe_dlc_start.position, c_fe_dlc_stop.position, dlc_bit, tag => "FE");
    check_range(data_start_of(fp), fp.data_stop, data_bit, tag => "FE");
    -- SBC + CRC region (interleaved with fixed_stuff_bit in FD)
    for i in sbc_start_of(fp) to sbc_stop_of(fp) - 1 loop
      test_count := test_count + 1;
      fb := get_next_mac_frame_bit(i, ser_data_v, fp, prev_pol, sbc_vec, crc_vec);
      if (fb.bit_name /= sbs_bit and fb.bit_name /= fixed_stuff_bit) then
        report "FE: pos " & integer'image(i) & " unexpected " &
               t_mac_frame_bit_name'image(fb.bit_name) & " in SBC region"
          severity error;
        fail_count := fail_count + 1;
      end if;
    end loop;
    for i in crc_start_of(fp) to fp.crc_stop - 1 loop
      test_count := test_count + 1;
      fb := get_next_mac_frame_bit(i, ser_data_v, fp, prev_pol, sbc_vec, crc_vec);
      if (fb.bit_name /= crc_bit and fb.bit_name /= fixed_stuff_bit) then
        report "FE: pos " & integer'image(i) & " unexpected " &
               t_mac_frame_bit_name'image(fb.bit_name) & " in CRC region"
          severity error;
        fail_count := fail_count + 1;
      end if;
    end loop;
    check_bit(crc_delimiter_of(fp), crc_delimiter_bit, c_recessive, "FE");
    check_bit(ack_slot_of(fp), ack_bit, c_recessive, "FE");
    check_bit(ack_delimiter_of(fp), ack_delimiter_bit, c_recessive, "FE");
    check_range(eof_start_of(fp), eof_stop_of(fp) - 1, eof_bit, c_recessive, "FE");

    report "FE: all bits checked";

    -- ==================================================================
    -- Summary
    -- ==================================================================
    report "========================================";
    report "Total checks: " & integer'image(test_count);
    report "Failures:     " & integer'image(fail_count);

    if (fail_count = 0) then
      report "ALL TESTS PASSED!";
    else
      report "SOME TESTS FAILED!" severity failure;
    end if;

    report "========================================";
    wait;

  end process test_process;

end architecture tb;
