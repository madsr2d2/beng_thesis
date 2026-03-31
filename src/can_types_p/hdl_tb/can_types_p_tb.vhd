--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for pk_can_types. Exercises get_mac_frame_bit
--                across all four frame formats (CB, CE, FB, FE) and
--                get_bit_info for ACK, bit error, and arbitration events.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-22  TMYAES:   Initial implementation
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library osvvm;
  context osvvm.osvvmcontext;
  use work.pk_can_types.all;

entity can_types_p_tb is
  generic (
    gc_tbtimeout : time := 2 ms
  );
end entity can_types_p_tb;

architecture tb of can_types_p_tb is

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

begin

  p_init : process is
  begin

    SetTestName("can_types_p_tb");
    SetAlertStopCount(ERROR, 10);
    wait;

  end process p_init;

  p_timeout : process is
  begin

    wait for gc_tbtimeout;
    Alert("Testbench timeout", FAILURE);
    std.env.finish;

  end process p_timeout;

  p_main_tester : process is

    variable md         : t_llc_metadata;
    variable fp         : t_frame_params;
    variable ser_data_v : std_logic              := c_recessive;
    variable fb         : t_mac_frame_bit;
    variable crc_vec    : std_logic_vector(c_crc_21_length - 1 downto 0)           := (others => '0');
    variable sbc_vec    : t_sbc                  := (others => '0');
    variable prev_pol   : std_logic              := c_recessive;
    variable tid        : alertlogidtype;
    variable bi         : t_bit_info;
    variable pol_hist   : t_tdc_polarity_history := (others => c_recessive);
    variable tid_bi     : alertlogidtype;

  begin

    wait for 0 ns;
    tid    := GetAlertLogID("get_mac_frame_bit");
    tid_bi := GetAlertLogID("get_bit_info");

    -- CB: Classic Basic, DLC=2
    md := make_metadata(x"00", x"20");
    fp := get_frame_params(md);

    fb := get_mac_frame_bit(c_sof, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = sof_bit and fb.polarity = c_dominant, "CB SOF");

    for i in c_cb_base_id_start to c_cb_base_id_stop loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = base_id_bit, "CB base_id " & integer'image(i));
    end loop;

    fb := get_mac_frame_bit(c_cb_rtr, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = rtr_bit and fb.polarity = c_dominant, "CB RTR");
    fb := get_mac_frame_bit(c_cb_ide, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = ide_bit and fb.polarity = c_dominant, "CB IDE");
    fb := get_mac_frame_bit(c_cb_r0, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = r0_bit and fb.polarity = c_dominant, "CB R0");

    for i in c_cb_dlc_start to c_cb_dlc_stop loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = dlc_bit, "CB DLC " & integer'image(i));
    end loop;

    for i in c_cb_data_start to fp.data_stop - 1 loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = data_bit, "CB data " & integer'image(i));
    end loop;

    for i in fp.data_stop to fp.crc_delimiter - 1 loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = crc_bit, "CB CRC " & integer'image(i));
    end loop;

    fb := get_mac_frame_bit(fp.crc_delimiter, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = crc_delimiter_bit and fb.polarity = c_recessive, "CB CRC delim");
    fb := get_mac_frame_bit(fp.crc_delimiter + c_ack_slot_offset, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = ack_bit and fb.polarity = c_recessive, "CB ACK");
    fb := get_mac_frame_bit(fp.crc_delimiter + c_ack_delimiter_offset, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = ack_delimiter_bit and fb.polarity = c_recessive, "CB ACK delim");

    for i in fp.crc_delimiter + c_eof_start_offset to fp.crc_delimiter + c_eof_start_offset + c_eof_field_width - 1 loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = eof_bit and fb.polarity = c_recessive, "CB EOF " & integer'image(i));
    end loop;

    -- CE: Classic Extended, DLC=4
    md := make_metadata(x"80", x"40");
    fp := get_frame_params(md);

    fb := get_mac_frame_bit(c_sof, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = sof_bit and fb.polarity = c_dominant, "CE SOF");

    for i in c_ce_base_id_start to c_ce_base_id_stop loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = base_id_bit, "CE base_id " & integer'image(i));
    end loop;

    fb := get_mac_frame_bit(c_ce_srr, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = srr_bit and fb.polarity = c_recessive, "CE SRR");
    fb := get_mac_frame_bit(c_ce_ide, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = ide_bit and fb.polarity = c_recessive, "CE IDE");

    for i in c_ce_extended_id_start to c_ce_extended_id_stop loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = extended_id_bit, "CE ext_id " & integer'image(i));
    end loop;

    fb := get_mac_frame_bit(c_ce_rtr, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = rtr_bit and fb.polarity = c_dominant, "CE RTR");
    fb := get_mac_frame_bit(c_ce_r1, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = r1_bit and fb.polarity = c_dominant, "CE R1");
    fb := get_mac_frame_bit(c_ce_r0, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = r0_bit and fb.polarity = c_dominant, "CE R0");

    for i in c_ce_dlc_start to c_ce_dlc_stop loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = dlc_bit, "CE DLC " & integer'image(i));
    end loop;

    for i in c_ce_data_start to fp.data_stop - 1 loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = data_bit, "CE data " & integer'image(i));
    end loop;

    for i in fp.data_stop to fp.crc_delimiter - 1 loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = crc_bit, "CE CRC " & integer'image(i));
    end loop;

    fb := get_mac_frame_bit(fp.crc_delimiter, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = crc_delimiter_bit and fb.polarity = c_recessive, "CE CRC delim");
    fb := get_mac_frame_bit(fp.crc_delimiter + c_ack_slot_offset, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = ack_bit and fb.polarity = c_recessive, "CE ACK");
    fb := get_mac_frame_bit(fp.crc_delimiter + c_ack_delimiter_offset, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = ack_delimiter_bit and fb.polarity = c_recessive, "CE ACK delim");

    for i in fp.crc_delimiter + c_eof_start_offset to fp.crc_delimiter + c_eof_start_offset + c_eof_field_width - 1 loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = eof_bit and fb.polarity = c_recessive, "CE EOF " & integer'image(i));
    end loop;

    -- FB: FD Basic, DLC=8, BRS=1
    md := make_metadata(x"44", x"80");
    fp := get_frame_params(md);

    fb := get_mac_frame_bit(c_sof, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = sof_bit and fb.polarity = c_dominant, "FB SOF");

    for i in c_fd_base_id_start to c_fd_base_id_stop loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = base_id_bit, "FB base_id " & integer'image(i));
    end loop;

    fb := get_mac_frame_bit(c_fb_rrs, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = rrs_bit and fb.polarity = c_dominant, "FB RRS");
    fb := get_mac_frame_bit(c_fb_ide, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = ide_bit and fb.polarity = c_dominant, "FB IDE");
    fb := get_mac_frame_bit(c_fb_fdf, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = fdf_bit and fb.polarity = c_recessive, "FB FDF");
    fb := get_mac_frame_bit(c_fb_res, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = res_bit and fb.polarity = c_dominant, "FB RES");
    fb := get_mac_frame_bit(c_fb_brs, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = brs_bit and fb.polarity = c_recessive, "FB BRS");
    fb := get_mac_frame_bit(c_fb_esi, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = esi_bit and fb.polarity = c_dominant, "FB ESI");

    for i in c_fb_dlc_start to c_fb_dlc_stop loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = dlc_bit, "FB DLC " & integer'image(i));
    end loop;

    for i in c_fb_data_start to fp.data_stop - 1 loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = data_bit, "FB data " & integer'image(i));
    end loop;

    -- FD SBC region (interleaved with fixed stuff bits)
    for i in fp.data_stop to fp.data_stop + c_sbc_field_width loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = sbs_bit or fb.bit_name = fixed_stuff_bit, "FB SBC " & integer'image(i));
    end loop;

    -- FD CRC region (interleaved with fixed stuff bits)
    for i in fp.data_stop + 1 + c_sbc_field_width to fp.crc_delimiter - 1 loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = crc_bit or fb.bit_name = fixed_stuff_bit, "FB CRC " & integer'image(i));
    end loop;

    fb := get_mac_frame_bit(fp.crc_delimiter, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = crc_delimiter_bit and fb.polarity = c_recessive, "FB CRC delim");
    fb := get_mac_frame_bit(fp.crc_delimiter + c_ack_slot_offset, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = ack_bit and fb.polarity = c_recessive, "FB ACK");
    fb := get_mac_frame_bit(fp.crc_delimiter + c_ack_delimiter_offset, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = ack_delimiter_bit and fb.polarity = c_recessive, "FB ACK delim");

    for i in fp.crc_delimiter + c_eof_start_offset to fp.crc_delimiter + c_eof_start_offset + c_eof_field_width - 1 loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = eof_bit and fb.polarity = c_recessive, "FB EOF " & integer'image(i));
    end loop;

    -- FE: FD Extended, DLC=12, BRS=1, ESI=1
    md := make_metadata(x"CC", x"C0");
    fp := get_frame_params(md);

    fb := get_mac_frame_bit(c_sof, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = sof_bit and fb.polarity = c_dominant, "FE SOF");

    for i in c_fe_base_id_start to c_fe_base_id_stop loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = base_id_bit, "FE base_id " & integer'image(i));
    end loop;

    fb := get_mac_frame_bit(c_fe_srr, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = srr_bit and fb.polarity = c_recessive, "FE SRR");
    fb := get_mac_frame_bit(c_fe_ide, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = ide_bit and fb.polarity = c_recessive, "FE IDE");

    for i in c_fe_extended_id_start to c_fe_extended_id_stop loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = extended_id_bit, "FE ext_id " & integer'image(i));
    end loop;

    fb := get_mac_frame_bit(c_fe_rrs, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = rrs_bit and fb.polarity = c_dominant, "FE RRS");
    fb := get_mac_frame_bit(c_fe_fdf, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = fdf_bit and fb.polarity = c_recessive, "FE FDF");
    fb := get_mac_frame_bit(c_fe_res, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = res_bit and fb.polarity = c_dominant, "FE RES");
    fb := get_mac_frame_bit(c_fe_brs, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = brs_bit and fb.polarity = c_recessive, "FE BRS");
    fb := get_mac_frame_bit(c_fe_esi, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = esi_bit and fb.polarity = c_recessive, "FE ESI");

    for i in c_fe_dlc_start to c_fe_dlc_stop loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = dlc_bit, "FE DLC " & integer'image(i));
    end loop;

    for i in c_fe_data_start to fp.data_stop - 1 loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = data_bit, "FE data " & integer'image(i));
    end loop;

    for i in fp.data_stop to fp.data_stop + c_sbc_field_width loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = sbs_bit or fb.bit_name = fixed_stuff_bit, "FE SBC " & integer'image(i));
    end loop;

    for i in fp.data_stop + 1 + c_sbc_field_width to fp.crc_delimiter - 1 loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = crc_bit or fb.bit_name = fixed_stuff_bit, "FE CRC " & integer'image(i));
    end loop;

    fb := get_mac_frame_bit(fp.crc_delimiter, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = crc_delimiter_bit and fb.polarity = c_recessive, "FE CRC delim");
    fb := get_mac_frame_bit(fp.crc_delimiter + c_ack_slot_offset, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = ack_bit and fb.polarity = c_recessive, "FE ACK");
    fb := get_mac_frame_bit(fp.crc_delimiter + c_ack_delimiter_offset, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
    AffirmIf(tid, fb.bit_name = ack_delimiter_bit and fb.polarity = c_recessive, "FE ACK delim");

    for i in fp.crc_delimiter + c_eof_start_offset to fp.crc_delimiter + c_eof_start_offset + c_eof_field_width - 1 loop
      fb := get_mac_frame_bit(i, ser_data_v, md, fp, prev_pol, sbc_vec, crc_vec);
      AffirmIf(tid, fb.bit_name = eof_bit and fb.polarity = c_recessive, "FE EOF " & integer'image(i));
    end loop;

    ---------------------------------------------------------------------------
    -- get_bit_info
    ---------------------------------------------------------------------------

    -- CC metadata for arbitration tests
    md := make_metadata(x"00", x"20");

    -- CC ACK: dominant => ack_detected, recessive => none
    bi := get_bit_info(ack_bit, pol_hist, 0, c_dominant, md);
    AffirmIf(tid_bi, bi.event_type = ack_detected, "CC ACK dominant");
    bi := get_bit_info(ack_bit, pol_hist, 0, c_recessive, md);
    AffirmIf(tid_bi, bi.event_type = none, "CC ACK recessive");

    -- CC ACK delimiter is not an ACK field
    bi := get_bit_info(ack_delimiter_bit, pol_hist, 0, c_dominant, md);
    AffirmIf(tid_bi, bi.event_type /= ack_detected, "CC ACK delim not ack_detected");

    md := make_metadata(x"44", x"80");

    -- FD ACK: dominant => ack_detected at both slot and delimiter
    bi := get_bit_info(ack_bit, pol_hist, 0, c_dominant, md);
    AffirmIf(tid_bi, bi.event_type = ack_detected, "FD ACK slot dominant");
    bi := get_bit_info(ack_delimiter_bit, pol_hist, 0, c_dominant, md);
    AffirmIf(tid_bi, bi.event_type = ack_detected, "FD ACK delim dominant");

    -- FD ACK: recessive => none
    bi := get_bit_info(ack_bit, pol_hist, 0, c_recessive, md);
    AffirmIf(tid_bi, bi.event_type = none, "FD ACK slot recessive");
    bi := get_bit_info(ack_delimiter_bit, pol_hist, 0, c_recessive, md);
    AffirmIf(tid_bi, bi.event_type = none, "FD ACK delim recessive");

    -- Polarity match: no error (history[0] = recessive, bus = recessive)
    pol_hist := (others => c_recessive);
    bi       := get_bit_info(data_bit, pol_hist, 0, c_recessive, md);
    AffirmIf(tid_bi, bi.event_type = none and bi.transfer_status = c_ongoing, "polarity match => none");

    -- Polarity match with TDC delay: history[5] = dominant, bus = dominant
    pol_hist    := (others => c_recessive);
    pol_hist(5) := c_dominant;
    bi          := get_bit_info(data_bit, pol_hist, 5, c_dominant, md);
    AffirmIf(tid_bi, bi.event_type = none, "TDC delay match => none");

    -- Bit error: polarity mismatch on data bit
    pol_hist := (others => c_recessive);
    bi       := get_bit_info(data_bit, pol_hist, 0, c_dominant, md);
    AffirmIf(tid_bi, bi.event_type = bit_error and bi.transfer_status = c_disturbed, "data bit error");

    -- Lost arbitration: dominant observed on base_id (tx recessive)
    md       := make_metadata(x"00", x"20");
    pol_hist := (others => c_recessive);
    bi       := get_bit_info(base_id_bit, pol_hist, 0, c_dominant, md);
    AffirmIf(tid_bi, bi.event_type = lost_arbitration and bi.transfer_status = c_lost_arb, "lost arb base_id");

    -- Lost arbitration: dominant observed on rtr
    bi := get_bit_info(rtr_bit, pol_hist, 0, c_dominant, md);
    AffirmIf(tid_bi, bi.event_type = lost_arbitration and bi.transfer_status = c_lost_arb, "lost arb rtr");

    -- CE: lost arbitration on extended_id
    md := make_metadata(x"80", x"40");
    bi := get_bit_info(extended_id_bit, pol_hist, 0, c_dominant, md);
    AffirmIf(tid_bi, bi.event_type = lost_arbitration and bi.transfer_status = c_lost_arb, "lost arb ext_id");

    -- CE: lost arbitration on srr
    bi := get_bit_info(srr_bit, pol_hist, 0, c_dominant, md);
    AffirmIf(tid_bi, bi.event_type = lost_arbitration and bi.transfer_status = c_lost_arb, "lost arb srr");

    -- CB: srr on basic format is bit error (not arbitration field)
    md := make_metadata(x"00", x"20");
    bi := get_bit_info(srr_bit, pol_hist, 0, c_dominant, md);
    AffirmIf(tid_bi, bi.event_type = bit_error, "CB srr mismatch => bit_error not lost_arb");

    EndOfTestReports(reportall => TRUE);
    std.env.finish;
    wait;

  end process p_main_tester;

end architecture tb;

-- eof
