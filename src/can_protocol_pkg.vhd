--------------------------------------------------------------------
-- can_protocol_pkg.vhd
-- Protocol algorithms and frame helpers for CAN/CAN-FD.
--------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Title      : CAN Bus Protocol Logic and Calculations
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : can_protocol_pkg.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Core protocol logic for the CAN/CAN-FD transmitter. Implements
--              frame layout calculation, bitstream modeling, and SBC encoding.
--
-- Protocol references: ISO 11898-1:2015
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

package can_protocol_pkg is

  ---------------------------------------------------------------------------
  -- Field Layout and Parameter Calculation
  ---------------------------------------------------------------------------

  -- Calculate all frame-specific parameters once per frame.
  function calculate_frame_params (
    metadata : t_llc_metadata
  ) return t_frame_params;

  -- Convert DLC to actual data length in bytes per ISO 11898-1 Table 10.
  function dlc_to_data_length (
    dlc        : t_dlc;
    can_format : std_logic_vector(2 downto 0)
  ) return integer;

  ---------------------------------------------------------------------------
  -- Bitstream Modeling and Extraction
  ---------------------------------------------------------------------------

  -- Calculates the next logical bit to be transmitted per protocol state.
  function get_next_mac_frame_bit (
    bit_count         : t_position;
    ser_data          : std_logic;
    frame_params      : t_frame_params;
    previous_polarity : std_logic;
    sbc               : t_sbc;
    crc               : t_crc_vector
  ) return t_mac_frame_bit;

  -- Monitors transmitted bits for errors, ACK issues, and arbitration loss.
  function get_observed_mac_frame_bit_info (
    fifo                   : t_transmitted_bits_fifo;
    fifo_index             : integer range 0 to c_transmitted_bits_fifo_depth - 1;
    fifo_write_ptr         : t_fifo_write_ptr;
    monitored_bit_polarity : std_logic;
    frame_params           : t_frame_params
  ) return t_observed_mac_frame_bit_info;

  -- Pack LLC frame ID field into canonical byte stream order ID3..ID0.
  function pack_llc_id_bytes (
    id         : std_logic_vector(28 downto 0);
    can_format : std_logic_vector(2 downto 0)
  ) return std_logic_vector;

end package can_protocol_pkg;

package body can_protocol_pkg is

  function get_observed_mac_frame_bit_info (
    fifo : t_transmitted_bits_fifo;
    fifo_index : integer range 0 to c_transmitted_bits_fifo_depth - 1;
    fifo_write_ptr : t_fifo_write_ptr;
    monitored_bit_polarity : std_logic;
    frame_params : t_frame_params
  ) return t_observed_mac_frame_bit_info is

    variable result             : t_observed_mac_frame_bit_info;
    variable is_arbitration_bit : boolean;
    variable read_index         : integer;

  begin

    -- Default: no event detected, transmission ongoing
    result.event_type      := none;
    result.transfer_status := c_ongoing;

    -- Circular buffer indexing: most recent bit is at write_ptr - 1
    -- delay=0 means current bit, delay=N means N bits ago
    read_index := (fifo_write_ptr - 1 - fifo_index) mod c_transmitted_bits_fifo_depth;

    -- Get the transmitted bit at the specified delay from FIFO
    result.expected_bit := fifo(read_index);
    -- Get monitored bit polarity
    result.observed_polarity := monitored_bit_polarity;

    -- Check for ACK bit (ISO 11898-1: 6.6.21.2)
    -- Only report positive ACK detection here. ACK error determination is deferred
    -- to the FSM at the ACK delimiter, since a later sample may still see dominant.
    --
    -- ISO 6.6.11.6: In FD frames, nodes shall accept an up to two bit long dominant
    -- phase of overlapping ACK slot bits as a valid ACK.
    if (result.expected_bit.bit_name = ack_bit) then
      if (monitored_bit_polarity = c_dominant) then
        result.event_type      := ack_detected;
        result.transfer_status := c_ongoing;
      end if;
      return result;
    elsif (frame_params.is_fd_frame = '1' and result.expected_bit.bit_name = ack_delimiter_bit) then
      if (monitored_bit_polarity = c_dominant) then
        result.event_type      := ack_detected;
        result.transfer_status := c_ongoing;
        return result;
      end if;
    end if;

    -- Skip error monitoring for control bits with predetermined polarity
    -- ESI, BRS, FDF, res, RRS have fixed polarity and shouldn't trigger errors
    -- (polarity conflicts only occur in arbitration field per ISO 11898-1)
    if (result.expected_bit.bit_name = esi_bit or
        result.expected_bit.bit_name = brs_bit or
        result.expected_bit.bit_name = fdf_bit or
        result.expected_bit.bit_name = res_bit or
        result.expected_bit.bit_name = rrs_bit) then
      -- These control bits have predetermined polarity, no need to check
      return result;
    end if;

    -- Return if no polarity mismatch
    if (result.expected_bit.polarity = monitored_bit_polarity) then
      return result;
    else
      -- Polarity mismatch detected: default to disturbed status
      result.transfer_status := c_disturbed;
    end if;

    -- Determine if this bit is in the arbitration phase (ISO 11898-1: Figure 2)
    case frame_params.format is
      when c_llc_fmt_cb =>
        is_arbitration_bit := (result.expected_bit.bit_name = base_id_bit or
                               result.expected_bit.bit_name = rtr_bit);
      when c_llc_fmt_ce =>
        is_arbitration_bit := (result.expected_bit.bit_name = base_id_bit or
                               result.expected_bit.bit_name = srr_bit or
                               result.expected_bit.bit_name = ide_bit or
                               result.expected_bit.bit_name = extended_id_bit or
                               result.expected_bit.bit_name = rtr_bit);
      when c_llc_fmt_fb =>
        is_arbitration_bit := (result.expected_bit.bit_name = base_id_bit or
                               result.expected_bit.bit_name = rrs_bit);
      when c_llc_fmt_fe =>
        is_arbitration_bit := (result.expected_bit.bit_name = base_id_bit or
                               result.expected_bit.bit_name = srr_bit or
                               result.expected_bit.bit_name = ide_bit or
                               result.expected_bit.bit_name = extended_id_bit);
      when others =>
        is_arbitration_bit := false;
    end case;

    -- Determine event type based on context and mismatch (ISO 11898-1 6.6.21.2)
    if (is_arbitration_bit) then
      if (result.expected_bit.polarity = c_dominant) then
        -- Sent dominant but observed recessive = bit error
        result.event_type := bit_error;
      else
        -- Sent recessive but observed dominant = lost arbitration
        result.event_type      := lost_arbitration;
        result.transfer_status := c_lost_arb;
      end if;
    else
      -- Outside arbitration field: any mismatch is a bit error
      result.event_type := bit_error;
    end if;

    return result;

  end function get_observed_mac_frame_bit_info;

  -- Helper function to convert DLC to actual data length in bytes
  function dlc_to_data_length (
    dlc        : t_dlc;
    can_format : std_logic_vector(2 downto 0)
  ) return integer is
  begin

    case can_format is
      when c_llc_fmt_cb | c_llc_fmt_ce =>

        if (dlc <= 8) then
          return integer(dlc);
        else
          return 8;
        end if;

      when c_llc_fmt_fb | c_llc_fmt_fe =>
        case dlc is
          when 0 to 8 => return integer(dlc);
          when 9 => return 12;
          when 10 => return 16;
          when 11 => return 20;
          when 12 => return 24;
          when 13 => return 32;
          when 14 => return 48;
          when 15 => return c_max_data_bytes;
          when others => return 0;
        end case;
      when others => return 0;
    end case;

  end function dlc_to_data_length;

  function get_next_mac_frame_bit (
    bit_count         : t_position;
    ser_data          : std_logic;
    frame_params      : t_frame_params;
    previous_polarity : std_logic;
    sbc               : t_sbc;
    crc               : t_crc_vector
  ) return t_mac_frame_bit is

    alias fp : t_frame_params is frame_params;

    variable result_v     : t_mac_frame_bit;
    variable dlc_start_v  : t_position;
    variable dlc_stop_v   : t_position;
    variable data_start_v : t_position;
    variable sbc_start_v  : t_position;
    variable sbc_stop_v   : t_position;
    variable crc_start_v  : t_position;
    variable pos_in_field : t_position;
    variable polarity_v   : std_logic;

  begin

    result_v := (polarity => 'X', bit_name => unknown);

    -- SOF bit (always position 0)
    if (bit_count = c_sof) then
      return c_sof_bit;
    end if;

    -- Base ID: always positions 1..11 across all formats
    if (bit_count >= c_cb_base_id_start.position and bit_count <= c_cb_base_id_stop.position) then
      return (bit_name => base_id_bit, polarity => ser_data);
    end if;

    -- Format-specific arbitration and control bits
    case fp.format is
      when c_llc_fmt_cb =>
        if (bit_count = c_cb_rtr.position) then
          polarity_v := c_recessive when fp.is_remote_frame = '1' else c_dominant;
          return (bit_name => rtr_bit, polarity => polarity_v);
        elsif (bit_count = c_cb_ide.position) then
          return (bit_name => ide_bit, polarity => c_cb_ide.polarity);
        elsif (bit_count = c_cb_r0.position) then
          return (bit_name => r0_bit, polarity => c_cb_r0.polarity);
        end if;

        dlc_start_v  := c_cb_dlc_start.position;
        data_start_v := c_cb_data_start.position;

      when c_llc_fmt_ce =>
        if (bit_count = c_ce_srr.position) then
          return (bit_name => srr_bit, polarity => c_ce_srr.polarity);
        elsif (bit_count = c_ce_ide.position) then
          return (bit_name => ide_bit, polarity => c_ce_ide.polarity);
        elsif (bit_count >= c_ce_extended_id_start.position and
               bit_count <= c_ce_extended_id_stop.position) then
          return (bit_name => extended_id_bit, polarity => ser_data);
        elsif (bit_count = c_ce_rtr.position) then
          polarity_v := c_recessive when fp.is_remote_frame = '1' else c_dominant;
          return (bit_name => rtr_bit, polarity => polarity_v);
        elsif (bit_count = c_ce_r1.position) then
          return (bit_name => r1_bit, polarity => c_ce_r1.polarity);
        elsif (bit_count = c_ce_r0.position) then
          return (bit_name => r0_bit, polarity => c_ce_r0.polarity);
        end if;

        dlc_start_v  := c_ce_dlc_start.position;
        data_start_v := c_ce_data_start.position;

      when c_llc_fmt_fb =>
        if (bit_count = c_fb_rrs.position) then
          return (bit_name => rrs_bit, polarity => c_fb_rrs.polarity);
        elsif (bit_count = c_fb_ide.position) then
          return (bit_name => ide_bit, polarity => c_fb_ide.polarity);
        elsif (bit_count = c_fb_fdf.position) then
          return (bit_name => fdf_bit, polarity => c_fb_fdf.polarity);
        elsif (bit_count = c_fb_res.position) then
          return (bit_name => res_bit, polarity => c_fb_res.polarity);
        elsif (bit_count = c_fb_brs.position) then
          polarity_v := c_recessive when fp.has_brs = '1' else c_dominant;
          return (bit_name => brs_bit, polarity => polarity_v);
        elsif (bit_count = c_fb_esi.position) then
          polarity_v := c_recessive when fp.esi_enable = '1' else c_dominant;
          return (bit_name => esi_bit, polarity => polarity_v);
        end if;

        dlc_start_v  := c_fb_dlc_start.position;
        data_start_v := c_fb_data_start.position;

      when c_llc_fmt_fe =>
        if (bit_count = c_fe_srr.position) then
          return (bit_name => srr_bit, polarity => c_fe_srr.polarity);
        elsif (bit_count = c_fe_ide.position) then
          return (bit_name => ide_bit, polarity => c_fe_ide.polarity);
        elsif (bit_count >= c_fe_extended_id_start.position and
               bit_count <= c_fe_extended_id_stop.position) then
          return (bit_name => extended_id_bit, polarity => ser_data);
        elsif (bit_count = c_fe_rrs.position) then
          return (bit_name => rrs_bit, polarity => c_fe_rrs.polarity);
        elsif (bit_count = c_fe_fdf.position) then
          return (bit_name => fdf_bit, polarity => c_fe_fdf.polarity);
        elsif (bit_count = c_fe_res.position) then
          return (bit_name => res_bit, polarity => c_fe_res.polarity);
        elsif (bit_count = c_fe_brs.position) then
          polarity_v := c_recessive when fp.has_brs = '1' else c_dominant;
          return (bit_name => brs_bit, polarity => polarity_v);
        elsif (bit_count = c_fe_esi.position) then
          polarity_v := c_recessive when fp.esi_enable = '1' else c_dominant;
          return (bit_name => esi_bit, polarity => polarity_v);
        end if;

        dlc_start_v  := c_fe_dlc_start.position;
        data_start_v := c_fe_data_start.position;

      when others =>
        return result_v;
    end case;

    -- DLC field
    dlc_stop_v := dlc_start_v + c_dlc_field_width;
    if (bit_count >= dlc_start_v and bit_count < dlc_stop_v) then
      return (bit_name => dlc_bit,
              polarity => fp.dlc_vector(fp.dlc_vector'left - (bit_count - dlc_start_v)));
    end if;

    -- Data field
    if (bit_count >= data_start_v and bit_count <= fp.data_stop) then
      return (bit_name => data_bit, polarity => ser_data);
    end if;

    -- SBC / CRC field (with fixed stuff bits for FD)
    if (fp.is_fd_frame = '1') then
      sbc_start_v := fp.data_stop + 1;
      sbc_stop_v  := sbc_start_v + c_sbc_field_width;
      crc_start_v := sbc_stop_v;
    else
      sbc_start_v := 0;
      sbc_stop_v  := 0;
      crc_start_v := fp.data_stop + 1;
    end if;

    if ((fp.is_fd_frame = '1' and bit_count >= sbc_start_v and bit_count < fp.crc_stop) or
        (fp.is_fd_frame = '0' and bit_count >= crc_start_v and bit_count < fp.crc_stop)) then
      -- Fixed stuff bits in CAN FD (highest priority)
      if (fp.is_fd_frame = '1') then
        pos_in_field := bit_count - sbc_start_v;
        if ((pos_in_field mod c_stuff_width) = 0) then
          polarity_v := c_recessive when previous_polarity = c_dominant else c_dominant;
          return (bit_name => fixed_stuff_bit, polarity => polarity_v);
        end if;
      end if;
      -- SBC or CRC bit
      if (fp.is_fd_frame = '1' and bit_count >= sbc_start_v and bit_count < sbc_stop_v) then
        return (bit_name => sbs_bit,
                polarity => sbc(sbc'left - (bit_count - sbc_start_v)));
      else
        if ((bit_count - crc_start_v) < crc'length) then
          return (bit_name => crc_bit,
                  polarity => crc(crc'left - (bit_count - crc_start_v)));
        else
          return (bit_name => crc_bit, polarity => 'X');
        end if;
      end if;
    end if;

    -- CRC delimiter, ACK, EOF (derived inline from fp.crc_stop)
    if (bit_count = fp.crc_stop + c_crc_delimiter_offset) then
      return c_crc_delimiter_bit;
    elsif (bit_count = fp.crc_stop + c_ack_slot_offset) then
      return c_tx_ack_bit;
    elsif (bit_count = fp.crc_stop + c_ack_delimiter_offset) then
      return c_ack_delimiter_bit;
    elsif (bit_count >= fp.crc_stop + c_eof_start_offset and
           bit_count < fp.crc_stop + c_eof_start_offset + c_eof_field_width) then
      return c_eof_bit;
    end if;

    return result_v;

  end function get_next_mac_frame_bit;

  function calculate_frame_params (
    metadata : t_llc_metadata
  ) return t_frame_params is

    variable result              : t_frame_params;
    variable data_length_v       : integer;
    variable data_bits_v         : integer;
    variable crc_length_v        : integer;
    variable fixed_stuff_count_v : integer;
    variable crc_field_length_v  : integer;
    variable data_start_v        : t_position;
    variable sbc_start_v         : t_position;
    variable sbc_stop_v          : t_position;
    variable crc_start_v         : t_position;

  begin

    -- Copy LLC metadata fields
    result.format          := metadata.format;
    result.dlc_vector      := metadata.dlc_vector;
    result.is_remote_frame := metadata.is_remote_frame;
    result.has_brs         := metadata.has_brs;
    result.esi_enable      := metadata.esi_enable;
    result.is_fd_frame     := '1' when (result.format = c_llc_fmt_fb or result.format = c_llc_fmt_fe) else '0';

    -- Calculate data length from DLC vector
    data_length_v := dlc_to_data_length(t_dlc(to_integer(unsigned(result.dlc_vector))), result.format);

    -- ISO 11898-1: 6.6.10.1 - Remote frames shall not contain a Data field
    if (result.is_remote_frame = '1') then
      data_length_v := 0;
    end if;

    data_bits_v := data_length_v * c_byte_width;

    -- Look up data_start from format constants
    case result.format is
      when c_llc_fmt_cb => data_start_v := c_cb_data_start.position;
      when c_llc_fmt_ce => data_start_v := c_ce_data_start.position;
      when c_llc_fmt_fb => data_start_v := c_fb_data_start.position;
      when c_llc_fmt_fe => data_start_v := c_fe_data_start.position;
      when others => data_start_v := 0;
    end case;

    if (data_bits_v > 0) then
      result.data_stop := data_start_v + data_bits_v - 1;
    else
      result.data_stop := data_start_v;
    end if;

    -- CRC length: CRC-15 for classic, CRC-17 for FD <= 16 bytes, CRC-21 otherwise
    if (result.is_fd_frame = '0') then
      crc_length_v := c_crc_15_length;
    elsif (data_length_v < c_crc_17_length) then
      crc_length_v := c_crc_17_length;
    else
      crc_length_v := c_crc_21_length;
    end if;

    -- CAN FD has SBC field after data, CAN Classic goes directly to CRC
    if (result.is_fd_frame = '1') then
      sbc_start_v         := result.data_stop + 1;
      sbc_stop_v          := sbc_start_v + c_sbc_field_width;
      crc_start_v         := sbc_stop_v;
      fixed_stuff_count_v := 1 + ((c_sbc_field_width + crc_length_v) / c_stuff_width);
      crc_field_length_v  := crc_length_v + fixed_stuff_count_v;
      result.crc_stop     := crc_start_v + crc_field_length_v;
    else
      crc_start_v     := result.data_stop + 1;
      result.crc_stop := crc_start_v + crc_length_v;
    end if;

    -- Determine CRC polynomial selection (00=CRC15, 01=CRC17, 10=CRC21)
    case crc_length_v is
      when c_crc_15_length =>
        result.crc_poly_select := "00";
      when c_crc_17_length =>
        result.crc_poly_select := "01";
      when c_crc_21_length =>
        result.crc_poly_select := "10";
      when others =>
        result.crc_poly_select := "11";
    end case;

    return result;

  end function calculate_frame_params;

  function pack_llc_id_bytes (
    id         : std_logic_vector(28 downto 0);
    can_format : std_logic_vector(2 downto 0)
  ) return std_logic_vector is

    variable result_v : std_logic_vector(31 downto 0);

  begin

    result_v := (others => '0');
    if (can_format = c_llc_fmt_ce or can_format = c_llc_fmt_fe) then
      result_v(31 downto 3) := id(28 downto 0);
    else
      result_v(31 downto 21) := id(10 downto 0);
    end if;

    return result_v;

  end function pack_llc_id_bytes;

end package body can_protocol_pkg;
