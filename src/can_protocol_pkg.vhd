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
    config_byte_0 : t_byte;
    config_byte_1 : t_byte
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
    mac_ser_to_fsm    : t_can_mac_ser_fsm_tx_if_s2m;
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

  ---------------------------------------------------------------------------
  -- Helper and Initialization functions
  ---------------------------------------------------------------------------
  function fifo_init return t_transmitted_bits_fifo;

  function is_fixed_stuff_bit_position (
    position_in_crc_field : integer
  ) return boolean;

  procedure fifo_write (
    signal fifo           : inout t_transmitted_bits_fifo;
    signal fifo_write_ptr : inout t_fifo_write_ptr;
    next_bit              : in    t_mac_frame_bit
  );

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

  -- Helper function to check if position is a fixed stuff bit in CAN FD CRC field
  function is_fixed_stuff_bit_position (
    position_in_crc_field : integer
  ) return boolean is

  begin

    -- Every 5th position starting at 0
    return (position_in_crc_field mod 5) = 0;

  end function is_fixed_stuff_bit_position;

  function get_next_mac_frame_bit (
    bit_count         : t_position;
    mac_ser_to_fsm    : t_can_mac_ser_fsm_tx_if_s2m;
    previous_polarity : std_logic;
    sbc               : t_sbc;
    crc               : t_crc_vector
  ) return t_mac_frame_bit is

    -- Alias for readability
    alias fp : t_frame_params is mac_ser_to_fsm.frame_params;

    variable result_v : t_mac_frame_bit;
    variable found    : boolean;

    -- Integer positions (converted once from slv)
    variable base_id_start_v     : t_position;
    variable base_id_stop_v      : t_position;
    variable extended_id_start_v : t_position;
    variable extended_id_stop_v  : t_position;
    variable dlc_start_v         : t_position;
    variable dlc_stop_v          : t_position;
    variable data_start_v        : t_position;
    variable data_stop_v         : t_position;
    variable sbc_start_v         : t_position;
    variable sbc_stop_v          : t_position;
    variable crc_start_v         : t_position;
    variable crc_stop_v          : t_position;
    variable crc_delimiter_v     : t_position;
    variable ack_slot_v          : t_position;
    variable ack_delimiter_v     : t_position;
    variable eof_start_v         : t_position;
    variable eof_stop_v          : t_position;

    -- RTR polarity derived from is_remote_frame flag
    variable rtr_polarity_v : std_logic;
    -- BRS polarity derived from has_brs flag
    variable brs_polarity_v : std_logic;
    -- ESI polarity derived from esi_enable flag
    variable esi_polarity_v : std_logic;

    --------------------------------------------------------------------
    -- Nested extraction procedures (share parent's local variables)
    --------------------------------------------------------------------

    procedure extract_arbitration_field is
    begin

      found := false;
      if (bit_count >= base_id_start_v and bit_count <= base_id_stop_v) then
        result_v := (bit_name => base_id_bit, polarity => mac_ser_to_fsm.data);
        found    := true;
      else
        case fp.format is
          when c_llc_fmt_cb =>
            if (bit_count = c_cb_rtr.position) then
              result_v := (bit_name => rtr_bit, polarity => rtr_polarity_v);
              found    := true;
            elsif (bit_count = c_cb_ide.position) then
              result_v := (bit_name => ide_bit, polarity => c_cb_ide.polarity);
              found    := true;
            end if;

          when c_llc_fmt_ce =>
            if (bit_count = c_ce_srr.position) then
              result_v := (bit_name => srr_bit, polarity => c_ce_srr.polarity);
              found    := true;
            elsif (bit_count = c_ce_ide.position) then
              result_v := (bit_name => ide_bit, polarity => c_ce_ide.polarity);
              found    := true;
            elsif (bit_count >= extended_id_start_v and bit_count <= extended_id_stop_v) then
              result_v := (bit_name => extended_id_bit, polarity => mac_ser_to_fsm.data);
              found    := true;
            elsif (bit_count = c_ce_rtr.position) then
              result_v := (bit_name => rtr_bit, polarity => rtr_polarity_v);
              found    := true;
            end if;

          when c_llc_fmt_fb =>
            if (bit_count = c_fb_rrs.position) then
              result_v := (bit_name => rrs_bit, polarity => c_fb_rrs.polarity);
              found    := true;
            elsif (bit_count = c_fb_ide.position) then
              result_v := (bit_name => ide_bit, polarity => c_fb_ide.polarity);
              found    := true;
            end if;

          when c_llc_fmt_fe =>
            if (bit_count = c_fe_srr.position) then
              result_v := (bit_name => srr_bit, polarity => c_fe_srr.polarity);
              found    := true;
            elsif (bit_count = c_fe_ide.position) then
              result_v := (bit_name => ide_bit, polarity => c_fe_ide.polarity);
              found    := true;
            elsif (bit_count >= extended_id_start_v and bit_count <= extended_id_stop_v) then
              result_v := (bit_name => extended_id_bit, polarity => mac_ser_to_fsm.data);
              found    := true;
            end if;

          when others =>
            null;
        end case;
      end if;

    end procedure extract_arbitration_field;

    procedure extract_control_field is
    begin

      found := false;
      case fp.format is
        when c_llc_fmt_cb =>
          if (bit_count = c_cb_r0.position) then
            result_v := (bit_name => r0_bit, polarity => c_cb_r0.polarity);
            found    := true;
          end if;

        when c_llc_fmt_ce =>
          if (bit_count = c_ce_r1.position) then
            result_v := (bit_name => r1_bit, polarity => c_ce_r1.polarity);
            found    := true;
          elsif (bit_count = c_ce_r0.position) then
            result_v := (bit_name => r0_bit, polarity => c_ce_r0.polarity);
            found    := true;
          end if;

        when c_llc_fmt_fb =>
          if (bit_count = c_fb_fdf.position) then
            result_v := (bit_name => fdf_bit, polarity => c_fb_fdf.polarity);
            found    := true;
          elsif (bit_count = c_fb_res.position) then
            result_v := (bit_name => res_bit, polarity => c_fb_res.polarity);
            found    := true;
          elsif (bit_count = c_fb_brs.position) then
            result_v := (bit_name => brs_bit, polarity => brs_polarity_v);
            found    := true;
          elsif (bit_count = c_fb_esi.position) then
            result_v := (bit_name => esi_bit, polarity => esi_polarity_v);
            found    := true;
          end if;

        when c_llc_fmt_fe =>
          if (bit_count = c_fe_rrs.position) then
            result_v := (bit_name => rrs_bit, polarity => c_fe_rrs.polarity);
            found    := true;
          elsif (bit_count = c_fe_fdf.position) then
            result_v := (bit_name => fdf_bit, polarity => c_fe_fdf.polarity);
            found    := true;
          elsif (bit_count = c_fe_res.position) then
            result_v := (bit_name => res_bit, polarity => c_fe_res.polarity);
            found    := true;
          elsif (bit_count = c_fe_brs.position) then
            result_v := (bit_name => brs_bit, polarity => brs_polarity_v);
            found    := true;
          elsif (bit_count = c_fe_esi.position) then
            result_v := (bit_name => esi_bit, polarity => esi_polarity_v);
            found    := true;
          end if;

        when others =>
          null;
      end case;

    end procedure extract_control_field;

    procedure extract_dlc_field is
    begin

      found := false;
      if (bit_count >= dlc_start_v and bit_count < dlc_stop_v) then
        result_v.bit_name := dlc_bit;
        result_v.polarity := fp.dlc_vector(fp.dlc_vector'left - (bit_count - dlc_start_v));
        found             := true;
      end if;

    end procedure extract_dlc_field;

    procedure extract_data_field is
    begin

      found := false;
      if (bit_count >= data_start_v and bit_count <= data_stop_v) then
        result_v := (bit_name => data_bit, polarity => mac_ser_to_fsm.data);
        found    := true;
      end if;

    end procedure extract_data_field;

    procedure extract_crc_sbc_field is

      variable pos_in_field : t_position;

    begin

      found := false;
      if ((fp.is_fd_frame = '1' and bit_count >= sbc_start_v and bit_count < crc_stop_v) or
          (fp.is_fd_frame = '0' and bit_count >= crc_start_v and bit_count < crc_stop_v)) then
        -- Fixed stuff bits in CAN FD (highest priority)
        if (fp.is_fd_frame = '1') then
          pos_in_field := bit_count - sbc_start_v;
          if is_fixed_stuff_bit_position(pos_in_field) then
            result_v.bit_name := fixed_stuff_bit;
            result_v.polarity := c_recessive when previous_polarity = c_dominant else c_dominant;
            found             := true;
            return;
          end if;
        end if;
        -- SBC or CRC bit
        if (fp.is_fd_frame = '1' and bit_count >= sbc_start_v and bit_count < sbc_stop_v) then
          result_v.bit_name := sbs_bit;
          result_v.polarity := sbc(sbc'left - (bit_count - sbc_start_v));
        else
          result_v.bit_name := crc_bit;
          if ((bit_count - crc_start_v) < crc'length) then
            result_v.polarity := crc(crc'left - (bit_count - crc_start_v));
          else
            result_v.polarity := 'X';
          end if;
        end if;
        found := true;
      end if;

    end procedure extract_crc_sbc_field;

    procedure extract_ack_eof_field is
    begin

      found := false;
      if (bit_count >= eof_stop_v) then
        return;
      end if;

      if (bit_count = crc_delimiter_v) then
        result_v := c_crc_delimiter_bit;
        found    := true;
      elsif (bit_count = ack_slot_v) then
        result_v := c_tx_ack_bit;
        found    := true;
      elsif (bit_count = ack_delimiter_v) then
        result_v := c_ack_delimiter_bit;
        found    := true;
      elsif (bit_count >= eof_start_v and bit_count < eof_stop_v) then
        result_v := c_eof_bit;
        found    := true;
      end if;

    end procedure extract_ack_eof_field;

  begin

    result_v := (polarity => 'X', bit_name => unknown);

    -- SOF bit (always first)
    if (bit_count = c_sof) then
      return c_sof_bit;
    end if;

    -- Convert slv positions to integers once
    base_id_start_v     := to_integer(unsigned(fp.base_id_start));
    base_id_stop_v      := to_integer(unsigned(fp.base_id_stop));
    extended_id_start_v := to_integer(unsigned(fp.extended_id_start));
    extended_id_stop_v  := to_integer(unsigned(fp.extended_id_stop));
    dlc_start_v         := to_integer(unsigned(fp.dlc_start));
    dlc_stop_v          := to_integer(unsigned(fp.dlc_stop));
    data_start_v        := to_integer(unsigned(fp.data_start));
    data_stop_v         := to_integer(unsigned(fp.data_stop));
    sbc_start_v         := to_integer(unsigned(fp.sbc_start));
    sbc_stop_v          := to_integer(unsigned(fp.sbc_stop));
    crc_start_v         := to_integer(unsigned(fp.crc_start));
    crc_stop_v          := to_integer(unsigned(fp.crc_stop));
    crc_delimiter_v     := to_integer(unsigned(fp.crc_delimiter));
    ack_slot_v          := to_integer(unsigned(fp.ack_slot));
    ack_delimiter_v     := to_integer(unsigned(fp.ack_delimiter));
    eof_start_v         := to_integer(unsigned(fp.eof_start));
    eof_stop_v          := to_integer(unsigned(fp.eof_stop));

    -- Derive per-frame polarities once
    rtr_polarity_v := c_recessive when fp.is_remote_frame = '1' else c_dominant;
    brs_polarity_v := c_recessive when fp.has_brs = '1' else c_dominant;
    esi_polarity_v := c_recessive when fp.esi_enable = '1' else c_dominant;

    -- Walk frame fields in order
    extract_arbitration_field;
    if (found) then
      return result_v;
    end if;

    extract_control_field;
    if (found) then
      return result_v;
    end if;

    extract_dlc_field;
    if (found) then
      return result_v;
    end if;

    extract_data_field;
    if (found) then
      return result_v;
    end if;

    extract_crc_sbc_field;
    if (found) then
      return result_v;
    end if;

    extract_ack_eof_field;
    if (found) then
      return result_v;
    end if;

    return result_v;

  end function get_next_mac_frame_bit;

  function fifo_init return t_transmitted_bits_fifo is

    variable fifo : t_transmitted_bits_fifo;

  begin

    fifo := (others => c_reset_mac_frame_bit);
    return fifo;

  end function fifo_init;

  procedure fifo_write (
    signal fifo           : inout t_transmitted_bits_fifo;
    signal fifo_write_ptr : inout t_fifo_write_ptr;
    next_bit              : in    t_mac_frame_bit
  ) is
  begin

    fifo(fifo_write_ptr) <= next_bit;

    if (fifo_write_ptr = c_transmitted_bits_fifo_depth - 1) then
      fifo_write_ptr <= 0;
    else
      fifo_write_ptr <= fifo_write_ptr + 1;
    end if;

  end procedure fifo_write;

  function calculate_frame_params (
    config_byte_0 : t_byte;
    config_byte_1 : t_byte
  ) return t_frame_params is

    variable result              : t_frame_params;
    variable data_length_v       : integer;
    variable data_bits_v         : integer;
    variable crc_length_v        : integer;
    variable fixed_stuff_count_v : integer;
    variable crc_field_length_v  : integer;

    -- Integer working variables for position arithmetic
    variable data_start_v        : t_position;
    variable data_stop_v         : t_position;
    variable dlc_start_v         : t_position;
    variable dlc_stop_v          : t_position;
    variable base_id_start_v     : t_position;
    variable base_id_stop_v      : t_position;
    variable extended_id_start_v : t_position;
    variable extended_id_stop_v  : t_position;
    variable sbc_start_v         : t_position;
    variable sbc_stop_v          : t_position;
    variable crc_start_v         : t_position;
    variable crc_stop_v          : t_position;
    variable crc_delimiter_v     : t_position;
    variable ack_slot_v          : t_position;
    variable ack_delimiter_v     : t_position;
    variable eof_start_v         : t_position;
    variable eof_stop_v          : t_position;

    -- Helper: convert integer position to t_mac_frame_position_vec
    function to_pos_vec (
      val : t_position
    ) return t_mac_frame_position_vec is
    begin

      return std_logic_vector(to_unsigned(val, t_mac_frame_position_vec'length));

    end function to_pos_vec;

  begin

    -- Extract frame format from config_byte_0[7:5]
    result.format := config_byte_0(c_llc_frame_config_byte_0_format_start downto c_llc_frame_config_byte_0_format_end);

    -- Extract DLC vector from config_byte_1[7:4] (raw 4-bit value)
    result.dlc_vector := config_byte_1(c_llc_frame_config_byte_1_dlc_start downto c_llc_frame_config_byte_1_dlc_end);

    -- Extract flags from config_byte_0
    result.has_brs         := config_byte_0(c_llc_frame_config_byte_0_brs);
    result.is_remote_frame := config_byte_0(c_llc_frame_config_byte_0_ftyp);
    result.esi_enable      := config_byte_0(c_llc_frame_config_byte_0_esi);
    result.is_fd_frame     := '1' when (result.format = c_llc_fmt_fb or result.format = c_llc_fmt_fe) else '0';

    -- Calculate data length from DLC vector
    data_length_v := dlc_to_data_length(t_dlc(to_integer(unsigned(result.dlc_vector))), result.format);

    -- ISO 11898-1: 6.6.10.1 - Remote frames shall not contain a Data field
    if (result.is_remote_frame = '1') then
      data_length_v := 0;
    end if;

    data_bits_v := data_length_v * c_byte_width;

    -- Default extended ID to zero (overridden for CE/FE)
    extended_id_start_v := 0;
    extended_id_stop_v  := 0;

    -- Populate field boundaries based on format (integer arithmetic)
    case result.format is
      when c_llc_fmt_cb =>
        base_id_start_v := c_cb_base_id_start.position;
        base_id_stop_v  := c_cb_base_id_stop.position;
        dlc_start_v     := c_cb_dlc_start.position;
        data_start_v    := c_cb_data_start.position;

      when c_llc_fmt_ce =>
        base_id_start_v     := c_ce_base_id_start.position;
        base_id_stop_v      := c_ce_base_id_stop.position;
        extended_id_start_v := c_ce_extended_id_start.position;
        extended_id_stop_v  := c_ce_extended_id_stop.position;
        dlc_start_v         := c_ce_dlc_start.position;
        data_start_v        := c_ce_data_start.position;

      when c_llc_fmt_fb =>
        base_id_start_v := c_fd_base_id_start.position;
        base_id_stop_v  := c_fd_base_id_stop.position;
        dlc_start_v     := c_fb_dlc_start.position;
        data_start_v    := c_fb_data_start.position;

      when c_llc_fmt_fe =>
        base_id_start_v     := c_fe_base_id_start.position;
        base_id_stop_v      := c_fe_base_id_stop.position;
        extended_id_start_v := c_fe_extended_id_start.position;
        extended_id_stop_v  := c_fe_extended_id_stop.position;
        dlc_start_v         := c_fe_dlc_start.position;
        data_start_v        := c_fe_data_start.position;

      when others =>
        base_id_start_v := 0;
        base_id_stop_v  := 0;
        dlc_start_v     := 0;
        data_start_v    := 0;
    end case;

    dlc_stop_v := dlc_start_v + c_dlc_field_width;

    if (data_bits_v > 0) then
      data_stop_v := data_start_v + data_bits_v - 1;
    else
      data_stop_v := data_start_v;
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
      sbc_start_v         := data_stop_v + 1;
      sbc_stop_v          := sbc_start_v + c_sbc_field_width;
      crc_start_v         := sbc_stop_v;
      fixed_stuff_count_v := 1 + ((c_sbc_field_width + crc_length_v) / 5);
      crc_field_length_v  := crc_length_v + fixed_stuff_count_v;
      crc_stop_v          := crc_start_v + crc_field_length_v;
    else
      sbc_start_v := 0;
      sbc_stop_v  := 0;
      crc_start_v := data_stop_v + 1;
      crc_stop_v  := crc_start_v + crc_length_v;
    end if;

    crc_delimiter_v := crc_stop_v;
    ack_slot_v      := crc_delimiter_v + 1;
    ack_delimiter_v := ack_slot_v + 1;
    eof_start_v     := ack_delimiter_v + 1;
    eof_stop_v      := eof_start_v + c_eof_field_width;

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

    -- Convert integer positions to t_mac_frame_position_vec
    result.base_id_start     := to_pos_vec(base_id_start_v);
    result.base_id_stop      := to_pos_vec(base_id_stop_v);
    result.extended_id_start := to_pos_vec(extended_id_start_v);
    result.extended_id_stop  := to_pos_vec(extended_id_stop_v);
    result.dlc_start         := to_pos_vec(dlc_start_v);
    result.dlc_stop          := to_pos_vec(dlc_stop_v);
    result.data_start        := to_pos_vec(data_start_v);
    result.data_stop         := to_pos_vec(data_stop_v);
    result.sbc_start         := to_pos_vec(sbc_start_v);
    result.sbc_stop          := to_pos_vec(sbc_stop_v);
    result.crc_start         := to_pos_vec(crc_start_v);
    result.crc_stop          := to_pos_vec(crc_stop_v);
    result.crc_delimiter     := to_pos_vec(crc_delimiter_v);
    result.ack_slot          := to_pos_vec(ack_slot_v);
    result.ack_delimiter     := to_pos_vec(ack_delimiter_v);
    result.eof_start         := to_pos_vec(eof_start_v);
    result.eof_stop          := to_pos_vec(eof_stop_v);

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
