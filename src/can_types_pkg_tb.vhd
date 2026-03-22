--------------------------------------------------------------------------------
-- Title      : CAN Types Package Testbench
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_types_pkg_tb.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Walks every bit position of one CB, CE, FB, and FE frame,
--              checking that get_mac_frame_bit returns the correct
--              bit_name and polarity. Also exercises get_frame_params.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.osvvmcontext;
  use work.pk_can_types.all;

entity can_types_pkg_tb is
  generic (
    gc_tbtimeout   : time := 2 ms;
    gc_tbclkperiod : time := 10 ns
  );
end entity can_types_pkg_tb;

architecture tb of can_types_pkg_tb is

  -- Helper: build t_llc_metadata from config bytes
  function make_metadata (
    config_byte_0 : t_byte;
    config_byte_1 : t_byte
  ) return t_llc_metadata is

    variable m : t_llc_metadata;

  begin

    m.format := config_byte_0(c_llc_frame_config_byte_0_format_start downto c_llc_frame_config_byte_0_format_end);
    m.dlc    := config_byte_1(c_llc_frame_config_byte_1_dlc_start downto c_llc_frame_config_byte_1_dlc_end);
    m.ftyp   := config_byte_0(c_llc_frame_config_byte_0_ftyp);
    m.brs    := config_byte_0(c_llc_frame_config_byte_0_brs);
    m.esi    := config_byte_0(c_llc_frame_config_byte_0_esi);
    return m;

  end function make_metadata;

  -- Position helpers derived from t_frame_params
  function ack_slot_of (
    fp : t_frame_params
  ) return t_position is
  begin

    return fp.crc_delimiter + c_ack_slot_offset;

  end function ack_slot_of;

  function ack_delimiter_of (
    fp : t_frame_params
  ) return t_position is
  begin

    return fp.crc_delimiter + c_ack_delimiter_offset;

  end function ack_delimiter_of;

  function eof_start_of (
    fp : t_frame_params
  ) return t_position is
  begin

    return fp.crc_delimiter + c_eof_start_offset;

  end function eof_start_of;

  function eof_stop_of (
    fp : t_frame_params
  ) return t_position is
  begin

    return fp.crc_delimiter + c_eof_start_offset + c_eof_field_width;

  end function eof_stop_of;

  function data_start_of (
    md : t_llc_metadata
  ) return t_position is
  begin

    case md.format is
      when c_llc_fmt_cb => return c_cb_data_start;
      when c_llc_fmt_ce => return c_ce_data_start;
      when c_llc_fmt_fb => return c_fb_data_start;
      when c_llc_fmt_fe => return c_fe_data_start;
      when others => return 0;
    end case;

  end function data_start_of;

  function sbc_start_of (
    md : t_llc_metadata;
    fp : t_frame_params
  ) return t_position is
  begin

    if (md.format(1) = '1') then
      return fp.data_stop;
    else
      return 0;
    end if;

  end function sbc_start_of;

  function sbc_stop_of (
    md : t_llc_metadata;
    fp : t_frame_params
  ) return t_position is
  begin

    if (md.format(1) = '1') then
      return fp.data_stop + 1 + c_sbc_field_width;
    else
      return 0;
    end if;

  end function sbc_stop_of;

  function crc_start_of (
    md : t_llc_metadata;
    fp : t_frame_params
  ) return t_position is
  begin

    if (md.format(1) = '1') then
      return fp.data_stop + 1 + c_sbc_field_width;
    else
      return fp.data_stop;
    end if;

  end function crc_start_of;

  signal clk : std_logic;

begin

  CreateClock(clk, gc_TbClkPeriod);

  p_init : process is
  begin

    SetTestName("can_types_pkg_tb");
    SetAlertStopCount(ERROR, 10);
    wait;

  end process p_init;

  p_timeout : process is
  begin

    wait for gc_tbtimeout;
    Alert("Testbench timeout", FAILURE);
    std.env.finish;

  end process p_timeout;

  -- -------------------------------------------------------------------------
  -- Main test process
  -- -------------------------------------------------------------------------
  p_main_tester : process is

    variable md         : t_llc_metadata;
    variable fp         : t_frame_params;
    variable ser_data_v : std_logic;
    variable fb         : t_mac_frame_bit;
    variable crc_vec    : t_crc_vector := (others => '0');
    variable sbc_vec    : t_sbc        := (others => '0');
    variable prev_pol   : std_logic    := c_recessive;

    variable cb_id : alertlogidtype;
    variable ce_id : alertlogidtype;
    variable fb_id : alertlogidtype;
    variable fe_id : alertlogidtype;

    -- Check one bit: verify bit_name and polarity
    procedure check_bit (
      alert_id      : in alertlogidtype;
      bit_pos       : in integer;
      expected_name : in t_mac_frame_bit_name;
      expected_pol  : in std_logic;
      tag           : in string := ""
    ) is
    begin

      fb := get_mac_frame_bit(bit_pos, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(alert_id,
               fb.bit_name = expected_name,
               tag & " pos " & integer'image(bit_pos) & " bit_name correct",
               tag & " pos " & integer'image(bit_pos) &
               " expected " & t_mac_frame_bit_name'image(expected_name) &
               " got " & t_mac_frame_bit_name'image(fb.bit_name));
      AffirmIf(alert_id,
               fb.polarity = expected_pol,
               tag & " pos " & integer'image(bit_pos) & " polarity correct",
               tag & " pos " & integer'image(bit_pos) &
               " expected polarity " & std_logic'image(expected_pol) &
               " got " & std_logic'image(fb.polarity));

    end procedure check_bit;

    -- Check one bit: verify bit_name only (polarity not checked)
    procedure check_bit (
      alert_id      : in alertlogidtype;
      bit_pos       : in integer;
      expected_name : in t_mac_frame_bit_name;
      tag           : in string := ""
    ) is
    begin

      fb := get_mac_frame_bit(bit_pos, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(alert_id,
               fb.bit_name = expected_name,
               tag & " pos " & integer'image(bit_pos) & " bit_name correct",
               tag & " pos " & integer'image(bit_pos) &
               " expected " & t_mac_frame_bit_name'image(expected_name) &
               " got " & t_mac_frame_bit_name'image(fb.bit_name));

    end procedure check_bit;

    -- Check a range of bits all have the same expected name and polarity
    procedure check_range (
      alert_id      : in alertlogidtype;
      first         : in integer;
      last          : in integer;
      expected_name : in t_mac_frame_bit_name;
      expected_pol  : in std_logic;
      tag           : in string := ""
    ) is
    begin

      for i in first to last loop
        check_bit(alert_id, i, expected_name, expected_pol, tag);
      end loop;

    end procedure check_range;

    -- Check a range of bits all have the same expected name (polarity not checked)
    procedure check_range (
      alert_id      : in alertlogidtype;
      first         : in integer;
      last          : in integer;
      expected_name : in t_mac_frame_bit_name;
      tag           : in string := ""
    ) is
    begin

      for i in first to last loop
        check_bit(alert_id, i, expected_name, tag);
      end loop;

    end procedure check_range;

    -- Check FD SBC+CRC region (interleaved with fixed stuff bits)
    procedure check_fd_region (
      alert_id  : in alertlogidtype;
      first     : in integer;
      last      : in integer;
      data_name : in t_mac_frame_bit_name;
      tag       : in string := ""
    ) is
    begin

      for i in first to last loop
        fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
        AffirmIf(alert_id,
                 fb.bit_name = data_name or fb.bit_name = fixed_stuff_bit,
                 tag & " pos " & integer'image(i) & " in " &
                 t_mac_frame_bit_name'image(data_name) & " region correct",
                 tag & " pos " & integer'image(i) & " unexpected " &
                 t_mac_frame_bit_name'image(fb.bit_name));
      end loop;

    end procedure check_fd_region;

  begin

    wait for 0 ns;
    wait for 0 ns;

    cb_id := GetAlertLogID("CB Frame");
    ce_id := GetAlertLogID("CE Frame");
    fb_id := GetAlertLogID("FB Frame");
    fe_id := GetAlertLogID("FE Frame");

    -- Common setup: serializer drives all-recessive data
    ser_data_v := c_recessive;

    -- ==================================================================
    -- Frame 1: CAN Classic Basic (CB) - DLC=2, data frame
    -- Config: format=000, ftyp=0, esi=0, brs=0 -> byte0 = x"00"
    --         dlc=2                              -> byte1 = x"20"
    -- ==================================================================
    Log(cb_id, "--- CB frame (DLC=2) ---");
    md := make_metadata(x"00", x"20");
    fp := get_frame_params(md);

    AffirmIf(cb_id, md.format = c_llc_fmt_cb, "CB: format correct");
    AffirmIf(cb_id, md.format(1) = '0',       "CB: not FD");

    check_bit(cb_id, c_sof, sof_bit, c_dominant, "CB");
    check_range(cb_id, c_cb_base_id_start, c_cb_base_id_stop, base_id_bit, tag => "CB");
    check_bit(cb_id, c_cb_rtr, rtr_bit, c_dominant, "CB");
    check_bit(cb_id, c_cb_ide, ide_bit, c_dominant, "CB");
    check_bit(cb_id, c_cb_r0, r0_bit, c_dominant, "CB");
    check_range(cb_id, c_cb_dlc_start, c_cb_dlc_stop, dlc_bit, tag => "CB");
    check_range(cb_id, data_start_of(md), fp.data_stop - 1, data_bit, tag => "CB");
    check_range(cb_id, crc_start_of(md, fp), fp.crc_delimiter - 1, crc_bit, tag => "CB");
    check_bit(cb_id, fp.crc_delimiter, crc_delimiter_bit, c_recessive, "CB");
    check_bit(cb_id, ack_slot_of(fp), ack_bit, c_recessive, "CB");
    check_bit(cb_id, ack_delimiter_of(fp), ack_delimiter_bit, c_recessive, "CB");
    check_range(cb_id, eof_start_of(fp), eof_stop_of(fp) - 1, eof_bit, c_recessive, "CB");

    Log(cb_id, "CB: all bits checked");

    -- ==================================================================
    -- Frame 2: CAN Classic Extended (CE) - DLC=4, data frame
    -- Config: format=100, ftyp=0, esi=0, brs=0 -> byte0 = x"80"
    --         dlc=4                              -> byte1 = x"40"
    -- ==================================================================
    Log(ce_id, "--- CE frame (DLC=4) ---");
    md := make_metadata(x"80", x"40");
    fp := get_frame_params(md);

    AffirmIf(ce_id, md.format = c_llc_fmt_ce, "CE: format correct");

    check_bit(ce_id, c_sof, sof_bit, c_dominant, "CE");
    check_range(ce_id, c_ce_base_id_start, c_ce_base_id_stop, base_id_bit, tag => "CE");
    check_bit(ce_id, c_ce_srr, srr_bit, c_recessive, "CE");
    check_bit(ce_id, c_ce_ide, ide_bit, c_recessive, "CE");
    check_range(ce_id, c_ce_extended_id_start, c_ce_extended_id_stop, extended_id_bit, tag => "CE");
    check_bit(ce_id, c_ce_rtr, rtr_bit, c_dominant, "CE");
    check_bit(ce_id, c_ce_r1, r1_bit, c_dominant, "CE");
    check_bit(ce_id, c_ce_r0, r0_bit, c_dominant, "CE");
    check_range(ce_id, c_ce_dlc_start, c_ce_dlc_stop, dlc_bit, tag => "CE");
    check_range(ce_id, data_start_of(md), fp.data_stop - 1, data_bit, tag => "CE");
    check_range(ce_id, crc_start_of(md, fp), fp.crc_delimiter - 1, crc_bit, tag => "CE");
    check_bit(ce_id, fp.crc_delimiter, crc_delimiter_bit, c_recessive, "CE");
    check_bit(ce_id, ack_slot_of(fp), ack_bit, c_recessive, "CE");
    check_bit(ce_id, ack_delimiter_of(fp), ack_delimiter_bit, c_recessive, "CE");
    check_range(ce_id, eof_start_of(fp), eof_stop_of(fp) - 1, eof_bit, c_recessive, "CE");

    Log(ce_id, "CE: all bits checked");

    -- ==================================================================
    -- Frame 3: CAN FD Basic (FB) - DLC=8, BRS=1, ESI=0
    -- Config: format=010, ftyp=0, esi=0, brs=1 -> byte0 = x"44"
    --         dlc=8                              -> byte1 = x"80"
    -- ==================================================================
    Log(fb_id, "--- FB frame (DLC=8, BRS=1) ---");
    md := make_metadata(x"44", x"80");
    fp := get_frame_params(md);

    AffirmIf(fb_id, md.format = c_llc_fmt_fb, "FB: format correct");
    AffirmIf(fb_id, md.format(1) = '1',       "FB: is FD");
    AffirmIf(fb_id, md.brs = '1',             "FB: BRS set");

    check_bit(fb_id, c_sof, sof_bit, c_dominant, "FB");
    check_range(fb_id, c_fd_base_id_start, c_fd_base_id_stop, base_id_bit, tag => "FB");
    check_bit(fb_id, c_fb_rrs, rrs_bit, c_dominant, "FB");
    check_bit(fb_id, c_fb_ide, ide_bit, c_dominant, "FB");
    check_bit(fb_id, c_fb_fdf, fdf_bit, c_recessive, "FB");
    check_bit(fb_id, c_fb_res, res_bit, c_dominant, "FB");
    check_bit(fb_id, c_fb_brs, brs_bit, c_recessive, "FB");
    check_bit(fb_id, c_fb_esi, esi_bit, c_dominant, "FB");
    check_range(fb_id, c_fb_dlc_start, c_fb_dlc_stop, dlc_bit, tag => "FB");
    check_range(fb_id, data_start_of(md), fp.data_stop - 1, data_bit, tag => "FB");
    check_fd_region(fb_id, sbc_start_of(md, fp), sbc_stop_of(md, fp) - 1, sbs_bit, "FB");
    check_fd_region(fb_id, crc_start_of(md, fp), fp.crc_delimiter - 1, crc_bit, "FB");
    check_bit(fb_id, fp.crc_delimiter, crc_delimiter_bit, c_recessive, "FB");
    check_bit(fb_id, ack_slot_of(fp), ack_bit, c_recessive, "FB");
    check_bit(fb_id, ack_delimiter_of(fp), ack_delimiter_bit, c_recessive, "FB");
    check_range(fb_id, eof_start_of(fp), eof_stop_of(fp) - 1, eof_bit, c_recessive, "FB");

    Log(fb_id, "FB: all bits checked");

    -- ==================================================================
    -- Frame 4: CAN FD Extended (FE) - DLC=12 (=16 bytes), BRS=1, ESI=1
    -- Config: format=110, ftyp=0, esi=1, brs=1 -> byte0 = x"CC"
    --         dlc=12                             -> byte1 = x"C0"
    -- ==================================================================
    Log(fe_id, "--- FE frame (DLC=12, BRS=1, ESI=1) ---");
    md := make_metadata(x"CC", x"C0");
    fp := get_frame_params(md);

    AffirmIf(fe_id, md.format = c_llc_fmt_fe, "FE: format correct");
    AffirmIf(fe_id, md.format(1) = '1',       "FE: is FD");
    AffirmIf(fe_id, md.brs = '1',             "FE: BRS set");
    AffirmIf(fe_id, md.esi = '1',             "FE: ESI set");

    check_bit(fe_id, c_sof, sof_bit, c_dominant, "FE");
    check_range(fe_id, c_fe_base_id_start, c_fe_base_id_stop, base_id_bit, tag => "FE");
    check_bit(fe_id, c_fe_srr, srr_bit, c_recessive, "FE");
    check_bit(fe_id, c_fe_ide, ide_bit, c_recessive, "FE");
    check_range(fe_id, c_fe_extended_id_start, c_fe_extended_id_stop, extended_id_bit, tag => "FE");
    check_bit(fe_id, c_fe_rrs, rrs_bit, c_dominant, "FE");
    check_bit(fe_id, c_fe_fdf, fdf_bit, c_recessive, "FE");
    check_bit(fe_id, c_fe_res, res_bit, c_dominant, "FE");
    check_bit(fe_id, c_fe_brs, brs_bit, c_recessive, "FE");
    check_bit(fe_id, c_fe_esi, esi_bit, c_recessive, "FE");
    check_range(fe_id, c_fe_dlc_start, c_fe_dlc_stop, dlc_bit, tag => "FE");
    check_range(fe_id, data_start_of(md), fp.data_stop - 1, data_bit, tag => "FE");
    check_fd_region(fe_id, sbc_start_of(md, fp), sbc_stop_of(md, fp) - 1, sbs_bit, "FE");
    check_fd_region(fe_id, crc_start_of(md, fp), fp.crc_delimiter - 1, crc_bit, "FE");
    check_bit(fe_id, fp.crc_delimiter, crc_delimiter_bit, c_recessive, "FE");
    check_bit(fe_id, ack_slot_of(fp), ack_bit, c_recessive, "FE");
    check_bit(fe_id, ack_delimiter_of(fp), ack_delimiter_bit, c_recessive, "FE");
    check_range(fe_id, eof_start_of(fp), eof_stop_of(fp) - 1, eof_bit, c_recessive, "FE");

    Log(fe_id, "FE: all bits checked");

    -- ==================================================================
    -- Finalization
    -- ==================================================================
    EndOfTestReports(reportall => TRUE);
    std.env.finish;
    wait;

  end process p_main_tester;

end architecture tb;

-- eof
