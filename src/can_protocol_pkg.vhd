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
  use work.can_types_pkg.all;

package can_protocol_pkg is

  ---------------------------------------------------------------------------
  -- Field Layout and Parameter Calculation
  ---------------------------------------------------------------------------

  -- Calculate all frame-specific parameters once per frame.
  function calculate_frame_params (
    config_byte_0 : byte_t;
    config_byte_1 : byte_t
  ) return frame_params_t;

  -- Convert DLC to actual data length in bytes per ISO 11898-1 Table 10.
  function dlc_to_data_length (
    dlc        : dlc_t;
    can_format : can_format_t
  ) return integer;

  ---------------------------------------------------------------------------
  -- Bitstream Modeling and Extraction
  ---------------------------------------------------------------------------

  -- Calculates the next logical bit to be transmitted per protocol state.
  function get_next_mac_frame_bit (
    bit_count         : position_t;
    mac_ser_to_fsm    : can_mac_ser_fsm_tx_if_s2d_t;
    previous_polarity : polarity_t;
    sbc               : sbc_t;
    crc               : crc_vector_t
  ) return mac_frame_bit_t;

  -- Monitors transmitted bits for errors, ACK issues, and arbitration loss.
  function get_observed_mac_frame_bit_info (
    fifo                   : transmitted_bits_fifo_t;
    fifo_index             : integer range 0 to transmitted_bits_fifo_depth_c - 1;
    fifo_write_ptr         : fifo_write_ptr_t;
    monitored_bit_polarity : polarity_t;
    frame_params           : frame_params_t
  ) return observed_mac_frame_bit_info_t;

  ---------------------------------------------------------------------------
  -- Arithmetic and Encoding Utilities
  ---------------------------------------------------------------------------

  -- Standard Gray encoder for SBC field.
  function to_gray (
    v : std_logic_vector
  ) return std_logic_vector;

  -- Parity bit generator for SBC field.
  function calc_parity (
    v : std_logic_vector
  ) return std_logic;

  -- Converters between polarity domain and std_logic domain.
  function polarity_to_std_logic (
    p : polarity_t
  ) return std_logic;
  function std_logic_to_polarity (
    s : std_logic
  ) return polarity_t;
  function bit_to_polarity (
    bit_val : std_logic
  ) return polarity_t;

  -- Pack LLC frame ID field into canonical byte stream order ID3..ID0.
  function pack_llc_id_bytes (
    id         : std_logic_vector(28 downto 0);
    can_format : can_format_t
  ) return std_logic_vector;

  -- Decode the 3-bit LLC config_byte_0 format field to can_format_t enum.
  function decode_llc_format (
    format_slv : std_logic_vector(2 downto 0)
  ) return can_format_t;

  ---------------------------------------------------------------------------
  -- Helper and Initialization functions
  ---------------------------------------------------------------------------
  function fifo_init return transmitted_bits_fifo_t;

  procedure fifo_write (
    signal fifo           : inout transmitted_bits_fifo_t;
    signal fifo_write_ptr : inout fifo_write_ptr_t;
    next_bit              : in    mac_frame_bit_t
  );

end package can_protocol_pkg;

package body can_protocol_pkg is

  function polarity_to_std_logic (
    p : polarity_t
  )
  return std_logic is

    variable result_v : std_logic;

  begin

    case p is
      when recessive =>
        result_v := recessive_bit_c;
      when dominant =>
        result_v := dominant_bit_c;
      when others =>
        result_v := 'X';
    end case;

    return result_v;

  end function polarity_to_std_logic;

  function std_logic_to_polarity (
    s : std_logic
  ) return polarity_t is
  begin

    case s is
      when recessive_bit_c =>
        return recessive;
      when dominant_bit_c =>
        return dominant;
      when others =>
        return unknown;
    end case;

  end function std_logic_to_polarity;

  function get_observed_mac_frame_bit_info (
    fifo : transmitted_bits_fifo_t;
    fifo_index : integer range 0 to transmitted_bits_fifo_depth_c - 1;
    fifo_write_ptr : fifo_write_ptr_t;
    monitored_bit_polarity : polarity_t;
    frame_params : frame_params_t
  ) return observed_mac_frame_bit_info_t is

    variable result             : observed_mac_frame_bit_info_t;
    variable is_arbitration_bit : boolean;
    variable read_index         : integer;

  begin

    -- Default: no event detected, transmission ongoing
    result.event_type      := none;
    result.transfer_status := ongoing;

    -- Circular buffer indexing: most recent bit is at write_ptr - 1
    -- delay=0 means current bit, delay=N means N bits ago
    read_index := (fifo_write_ptr - 1 - fifo_index) mod transmitted_bits_fifo_depth_c;

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
      if (monitored_bit_polarity = dominant) then
        result.event_type      := ack_detected;
        result.transfer_status := ongoing;
      end if;
      return result;
    elsif (frame_params.is_fd_frame and result.expected_bit.bit_name = ack_delimiter_bit) then
      if (monitored_bit_polarity = dominant) then
        result.event_type      := ack_detected;
        result.transfer_status := ongoing;
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
      result.transfer_status := disturbed;
    end if;

    -- Determine if this bit is in the arbitration phase (ISO 11898-1: Figure 2)
    case frame_params.format is
      when cc_basic =>
        is_arbitration_bit := (result.expected_bit.bit_name = base_id_bit or
                               result.expected_bit.bit_name = rtr_bit);
      when cc_extended =>
        is_arbitration_bit := (result.expected_bit.bit_name = base_id_bit or
                               result.expected_bit.bit_name = srr_bit or
                               result.expected_bit.bit_name = ide_bit or
                               result.expected_bit.bit_name = extended_id_bit or
                               result.expected_bit.bit_name = rtr_bit);
      when fd_basic =>
        is_arbitration_bit := (result.expected_bit.bit_name = base_id_bit or
                               result.expected_bit.bit_name = rrs_bit);
      when fd_extended =>
        is_arbitration_bit := (result.expected_bit.bit_name = base_id_bit or
                               result.expected_bit.bit_name = srr_bit or
                               result.expected_bit.bit_name = ide_bit or
                               result.expected_bit.bit_name = extended_id_bit);
      when others =>
        is_arbitration_bit := false;
    end case;

    -- Determine event type based on context and mismatch (ISO 11898-1 6.6.21.2)
    if (is_arbitration_bit) then
      if (result.expected_bit.polarity = dominant) then
        -- Sent dominant but observed recessive = bit error
        result.event_type := bit_error;
      else
        -- Sent recessive but observed dominant = lost arbitration
        result.event_type      := lost_arbitration;
        result.transfer_status := lost_arbitration;
      end if;
    else
      -- Outside arbitration field: any mismatch is a bit error
      result.event_type := bit_error;
    end if;

    return result;

  end function get_observed_mac_frame_bit_info;

  -- Function calculates the parity bit of a std_logic_vector
  function calc_parity (
    v : std_logic_vector
  ) return std_logic is

    variable v_parity : std_logic := '0';

  begin

    for i in v'range loop
      v_parity := v_parity xor v(i);
    end loop;

    return v_parity;

  end function calc_parity;

  -- Function Gray encodes a std_logic_vector
  function to_gray (
    v : std_logic_vector
  ) return std_logic_vector is

    variable result : std_logic_vector(v'range);

  begin

    result(v'left) := v(v'left);

    for i in v'left - 1 downto v'right loop
      result(i) := v(i) xor v(i + 1);
    end loop;

    return result;

  end function to_gray;

  -- Convert std_logic bit value to polarity enumeration
  function bit_to_polarity (
    bit_val : std_logic
  ) return polarity_t is

    variable result_v : polarity_t;

  begin

    if (bit_val = dominant_bit_c) then
      result_v := dominant;
    elsif (bit_val = recessive_bit_c) then
      result_v := recessive;
    else
      result_v := unknown;
    end if;

    return result_v;

  end function bit_to_polarity;

  -- Helper function to convert DLC to actual data length in bytes
  function dlc_to_data_length (
    dlc        : dlc_t;
    can_format : can_format_t
  ) return integer is
  begin

    case can_format is
      when cc_basic | cc_extended =>

        if (dlc <= 8) then
          return integer(dlc);
        else
          return 8;
        end if;

      when fd_basic | fd_extended =>
        case dlc is
          when 0 to 8 => return integer(dlc);
          when 9 => return 12;
          when 10 => return 16;
          when 11 => return 20;
          when 12 => return 24;
          when 13 => return 32;
          when 14 => return 48;
          when 15 => return max_data_bytes_c;
          when others => return 0;
        end case;
      when unknown => return 0;
    end case;

  end function dlc_to_data_length;

  -- Helper function to get CRC length based on CAN format and data length
  function get_crc_length (
    can_format  : can_format_t;
    data_length : integer
  ) return integer is
  begin

    case can_format is
      when cc_basic | cc_extended =>
        return crc_15_length_c;  -- CRC-15 for classic CAN
      when fd_basic | fd_extended =>
        -- Use CRC-17 for payloads <= 16 bytes, CRC-21 otherwise
        if (data_length < crc_17_length_c) then
          return crc_17_length_c;
        else
          return crc_21_length_c;
        end if;

      when unknown => return 0;
    end case;

  end function get_crc_length;

  -- Helper function to check if format is FD
  function is_fd_format (
    can_format : can_format_t
  ) return boolean is

  begin

    case can_format is
      when fd_basic | fd_extended => return true;
      when others => return false;
    end case;

  end function is_fd_format;

  -- Helper function to check if position is a fixed stuff bit in CAN FD CRC field
  function is_fixed_stuff_bit_position (
    position_in_crc_field : integer
  ) return boolean is

  begin

    -- Every 5th position starting at 0
    return (position_in_crc_field mod 5) = 0;

  end function is_fixed_stuff_bit_position;

  -- Helper function to calculate total number of fixed stuff bits in FD CRC field
  function get_fixed_stuff_bit_count (
    sbc_and_crc_length : integer
  ) return integer is

    variable num_fixed_stuff : integer;

  begin

    -- Fixed stuff bits: 1 before first bit, then after every 4 data bits
    -- Stuff bit positions: 0, 5, 10, 15, ...
    num_fixed_stuff := 1 + (sbc_and_crc_length / 5);
    return num_fixed_stuff;

  end function get_fixed_stuff_bit_count;

  --------------------------------------------------------------------
  -- Field-specific bit extraction procedures
  --------------------------------------------------------------------

  procedure extract_arbitration_field (
    bit_count      : in position_t;
    frame_params   : in frame_params_t;
    mac_ser_to_fsm : in can_mac_ser_fsm_tx_if_s2d_t;
    result         : out mac_frame_bit_t;
    found          : out boolean
  ) is
  begin

    found  := false;
    result := (polarity => unknown, bit_name => unknown);

    -- Base ID field
    if (bit_count >= frame_params.base_id_start and bit_count <= frame_params.base_id_stop) then
      result.bit_name := base_id_bit;
      result.polarity := mac_ser_to_fsm.data;
      found           := true;
    -- RTR/RRS bits (mutually exclusive per format)
    elsif (frame_params.rtr_bit.polarity /= unknown and bit_count = frame_params.rtr_bit.position) then
      result := (bit_name => rtr_bit, polarity => frame_params.rtr_bit.polarity);
      found  := true;
    elsif (frame_params.rrs_bit.polarity /= unknown and bit_count = frame_params.rrs_bit.position) then
      result := (bit_name => rrs_bit, polarity => frame_params.rrs_bit.polarity);
      found  := true;
    -- SRR/IDE bits (extended frame only)
    elsif (frame_params.srr_bit.polarity /= unknown and bit_count = frame_params.srr_bit.position) then
      result := (bit_name => srr_bit, polarity => frame_params.srr_bit.polarity);
      found  := true;
    elsif (frame_params.ide_bit.polarity /= unknown and bit_count = frame_params.ide_bit.position) then
      result := (bit_name => ide_bit, polarity => frame_params.ide_bit.polarity);
      found  := true;
    -- Extended ID field (if present)
    elsif (frame_params.extended_id_start > 0 and bit_count >= frame_params.extended_id_start and bit_count <= frame_params.extended_id_stop) then
      result.bit_name := extended_id_bit;
      result.polarity := mac_ser_to_fsm.data;
      found           := true;
    end if;

  end procedure extract_arbitration_field;

  procedure extract_control_field (
    bit_count    : in position_t;
    frame_params : in frame_params_t;
    result       : out mac_frame_bit_t;
    found        : out boolean
  ) is
  begin

    found  := false;
    result := (polarity => unknown, bit_name => unknown);

    if (frame_params.r1_bit.polarity /= unknown and bit_count = frame_params.r1_bit.position) then
      result := (bit_name => r1_bit, polarity => frame_params.r1_bit.polarity);
      found  := true;
    elsif (frame_params.r0_bit.polarity /= unknown and bit_count = frame_params.r0_bit.position) then
      result := (bit_name => r0_bit, polarity => frame_params.r0_bit.polarity);
      found  := true;
    elsif (frame_params.fdf_bit.polarity /= unknown and bit_count = frame_params.fdf_bit.position) then
      result := (bit_name => fdf_bit, polarity => frame_params.fdf_bit.polarity);
      found  := true;
    elsif (frame_params.res_bit.polarity /= unknown and bit_count = frame_params.res_bit.position) then
      result := (bit_name => res_bit, polarity => frame_params.res_bit.polarity);
      found  := true;
    elsif (frame_params.brs_bit.polarity /= unknown and bit_count = frame_params.brs_bit.position) then
      result := (bit_name => brs_bit, polarity => frame_params.brs_bit.polarity);
      found  := true;
    elsif (frame_params.esi_bit.polarity /= unknown and bit_count = frame_params.esi_bit.position) then
      result := (bit_name => esi_bit, polarity => frame_params.esi_bit.polarity);
      found  := true;
    end if;

  end procedure extract_control_field;

  procedure extract_dlc_field (
    bit_count    : in position_t;
    frame_params : in frame_params_t;
    result       : out mac_frame_bit_t;
    found        : out boolean
  ) is

    variable dlc_bit_index : position_t;

  begin

    found  := false;
    result := (polarity => unknown, bit_name => unknown);

    if (bit_count >= frame_params.dlc_start and bit_count < frame_params.dlc_stop) then
      result.bit_name := dlc_bit;
      dlc_bit_index   := frame_params.dlc_vector'left - (bit_count - frame_params.dlc_start);
      result.polarity := bit_to_polarity(frame_params.dlc_vector(dlc_bit_index));
      found           := true;
    end if;

  end procedure extract_dlc_field;

  procedure extract_data_field (
    bit_count      : in position_t;
    frame_params   : in frame_params_t;
    mac_ser_to_fsm : in can_mac_ser_fsm_tx_if_s2d_t;
    result         : out mac_frame_bit_t;
    found          : out boolean
  ) is
  begin

    found  := false;
    result := (polarity => unknown, bit_name => unknown);

    if (bit_count >= frame_params.data_start and bit_count <= frame_params.data_stop) then
      result.bit_name := data_bit;
      result.polarity := mac_ser_to_fsm.data;
      found           := true;
    end if;

  end procedure extract_data_field;

  procedure extract_crc_sbc_field (
    bit_count         : in position_t;
    frame_params      : in frame_params_t;
    previous_polarity : in polarity_t;
    sbc               : in sbc_t;
    crc               : in crc_vector_t;
    result            : out mac_frame_bit_t;
    found             : out boolean
  ) is

    variable position_in_crc_field : position_t;

  begin

    found  := false;
    result := (polarity => unknown, bit_name => unknown);

    -- Check if bit is in CRC/SBC field range
    if ((frame_params.is_fd_frame and bit_count >= frame_params.sbc_start and bit_count < frame_params.crc_stop) or
        (not frame_params.is_fd_frame and bit_count >= frame_params.crc_start and bit_count < frame_params.crc_stop)) then
      -- Check for fixed stuff bits in CAN FD (highest priority)
      if (frame_params.is_fd_frame) then
        position_in_crc_field := bit_count - frame_params.sbc_start;
        if is_fixed_stuff_bit_position(position_in_crc_field) then
          result.bit_name := fixed_stuff_bit;
          result.polarity := recessive when previous_polarity = dominant else dominant;
          found           := true;
          return;
        end if;
      end if;

      -- Extract CRC or SBC bit
      if (frame_params.is_fd_frame and bit_count >= frame_params.sbc_start and bit_count < frame_params.sbc_stop) then
        result.bit_name := sbs_bit;
        result.polarity := bit_to_polarity(sbc(sbc'left - (bit_count - frame_params.sbc_start)));
      else
        result.bit_name := crc_bit;
        if ((bit_count - frame_params.crc_start) < crc'length) then
          result.polarity := bit_to_polarity(crc(crc'left - (bit_count - frame_params.crc_start)));
        else
          result.polarity := unknown;
        end if;
      end if;
      found := true;
    end if;

  end procedure extract_crc_sbc_field;

  procedure extract_ack_eof_field (
    bit_count    : in position_t;
    frame_params : in frame_params_t;
    result       : out mac_frame_bit_t;
    found        : out boolean
  ) is
  begin

    found  := false;
    result := (polarity => unknown, bit_name => unknown);

    -- Beyond frame end - no valid bits
    if (bit_count >= frame_params.eof_stop) then
      return;
    end if;

    if (bit_count = frame_params.crc_delimiter) then
      result := crc_delimiter_bit_c;
      found  := true;
    elsif (bit_count = frame_params.ack_slot) then
      result := tx_ack_bit_c;
      found  := true;
    elsif (bit_count = frame_params.ack_delimiter) then
      result := ack_delimiter_bit_c;
      found  := true;
    elsif (bit_count >= frame_params.eof_start and bit_count < frame_params.eof_stop) then
      result := eof_bit_c;
      found  := true;
    end if;

  end procedure extract_ack_eof_field;

  function get_next_mac_frame_bit (
    bit_count    : position_t;
    mac_ser_to_fsm : can_mac_ser_fsm_tx_if_s2d_t;
    previous_polarity : polarity_t;
    sbc : sbc_t;
    crc : crc_vector_t
  ) return mac_frame_bit_t is

    variable result_v : mac_frame_bit_t;
    variable found    : boolean;

  begin

    result_v := (polarity => unknown, bit_name => unknown);

    -- SOF bit (always first)
    if (bit_count = sof_c) then
      return sof_bit_c;
    end if;

    -- Extract bit type based on frame section
    extract_arbitration_field(bit_count, mac_ser_to_fsm.frame_params, mac_ser_to_fsm, result_v, found);

    if (found) then
      return result_v;
    end if;

    extract_control_field(bit_count, mac_ser_to_fsm.frame_params, result_v, found);

    if (found) then
      return result_v;
    end if;

    extract_dlc_field(bit_count, mac_ser_to_fsm.frame_params, result_v, found);

    if (found) then
      return result_v;
    end if;

    extract_data_field(bit_count, mac_ser_to_fsm.frame_params, mac_ser_to_fsm, result_v, found);

    if (found) then
      return result_v;
    end if;

    extract_crc_sbc_field(bit_count, mac_ser_to_fsm.frame_params, previous_polarity, sbc, crc, result_v, found);

    if (found) then
      return result_v;
    end if;

    extract_ack_eof_field(bit_count, mac_ser_to_fsm.frame_params, result_v, found);

    if (found) then
      return result_v;
    end if;

    return result_v;

  end function get_next_mac_frame_bit;

  function fifo_init return transmitted_bits_fifo_t is

    variable fifo : transmitted_bits_fifo_t;

  begin

    fifo := (others => reset_mac_frame_bit_c);
    return fifo;

  end function fifo_init;

  procedure fifo_write (
    signal fifo           : inout transmitted_bits_fifo_t;
    signal fifo_write_ptr : inout fifo_write_ptr_t;
    next_bit              : in    mac_frame_bit_t
  ) is
  begin

    fifo(fifo_write_ptr) <= next_bit;

    if (fifo_write_ptr = transmitted_bits_fifo_depth_c - 1) then
      fifo_write_ptr <= 0;
    else
      fifo_write_ptr <= fifo_write_ptr + 1;
    end if;

  end procedure fifo_write;

  function calculate_frame_params (
    config_byte_0 : byte_t;
    config_byte_1 : byte_t
  ) return frame_params_t is

    variable result              : frame_params_t;
    variable data_length_v       : integer;
    variable data_start_v        : position_t;
    variable data_bits_v         : integer;
    variable has_brs_v           : boolean;
    variable is_remote_v         : boolean;
    variable crc_length_v        : integer;
    variable fixed_stuff_count_v : integer;
    variable crc_field_length_v  : integer;
    variable sbc_start_v         : position_t;
    variable rtr_polarity_v      : polarity_t;
    variable brs_polarity_v      : polarity_t;
    variable esi_polarity_v      : polarity_t;

  begin

    -- Extract frame format from config_byte_0[7:5]
    case config_byte_0(llc_frame_config_byte_0_format_start downto llc_frame_config_byte_0_format_end) is
      when llc_fmt_cb_c => result.format := cc_basic;
      when llc_fmt_ce_c => result.format := cc_extended;
      when llc_fmt_fb_c => result.format := fd_basic;
      when llc_fmt_fe_c => result.format := fd_extended;
      when others => result.format := unknown;
    end case;

    -- Extract DLC vector from config_byte_1[7:4] (raw 4-bit value)
    result.dlc_vector := config_byte_1(llc_frame_config_byte_1_dlc_start downto llc_frame_config_byte_1_dlc_end);

    -- Extract flags from config_byte_0
    has_brs_v   := (config_byte_0(llc_frame_config_byte_0_brs) = '1');
    is_remote_v := (config_byte_0(llc_frame_config_byte_0_ftyp) = '1');

    result.is_fd_frame     := is_fd_format(result.format);
    result.has_brs         := has_brs_v;
    result.esi_enable      := (config_byte_0(llc_frame_config_byte_0_esi) = '1');
    result.is_remote_frame := is_remote_v;

    -- Determine frame-dependent polarities for control bits
    rtr_polarity_v := recessive when result.is_remote_frame else dominant;
    brs_polarity_v := recessive when result.has_brs else dominant;
    esi_polarity_v := recessive when result.esi_enable else dominant;

    -- Calculate data length from DLC vector
    data_length_v := dlc_to_data_length(dlc_t(to_integer(unsigned(result.dlc_vector))), result.format);

    -- ISO 11898-1: 6.6.10.1 - Remote frames shall not contain a Data field
    if (result.is_remote_frame) then
      data_length_v := 0;
    end if;

    data_bits_v := data_length_v * byte_width_c;

    -- Populate field boundaries based on format
    case result.format is
      when cc_basic =>
        data_start_v             := cb_data_start_c.position;
        result.dlc_start         := cb_dlc_start_c.position;
        result.base_id_start     := cb_base_id_start_c.position;
        result.base_id_stop      := cb_base_id_start_c.position + base_id_width_c - 1;
        result.extended_id_start := 0;
        result.extended_id_stop  := 0;
        result.rtr_bit           := (position => cb_rtr_c.position, polarity => rtr_polarity_v);
        result.ide_bit           := cb_ide_c;
        result.r0_bit            := cb_r0_c;
        result.srr_bit           := unknown_bit_c;
        result.rrs_bit           := unknown_bit_c;
        result.fdf_bit           := unknown_bit_c;
        result.res_bit           := unknown_bit_c;
        result.r1_bit            := unknown_bit_c;
        result.brs_bit           := unknown_bit_c;
        result.esi_bit           := unknown_bit_c;

      when cc_extended =>
        data_start_v             := ce_data_start_c.position;
        result.dlc_start         := ce_dlc_start_c.position;
        result.base_id_start     := ce_base_id_start_c.position;
        result.base_id_stop      := ce_base_id_start_c.position + base_id_width_c - 1;
        result.extended_id_start := ce_extended_id_start_c.position;
        result.extended_id_stop  := ce_extended_id_start_c.position + extended_id_width_c - 1;
        result.srr_bit           := ce_srr_c;
        result.ide_bit           := ce_ide_c;
        result.rtr_bit           := (position => ce_rtr_c.position, polarity => rtr_polarity_v);
        result.r1_bit            := ce_r1_c;
        result.r0_bit            := ce_r0_c;
        result.rrs_bit           := unknown_bit_c;
        result.fdf_bit           := unknown_bit_c;
        result.res_bit           := unknown_bit_c;
        result.brs_bit           := unknown_bit_c;
        result.esi_bit           := unknown_bit_c;

      when fd_basic =>
        data_start_v             := fb_data_start_c.position;
        result.dlc_start         := fb_dlc_start_c.position;
        result.base_id_start     := fd_base_id_start_c.position;
        result.base_id_stop      := fd_base_id_start_c.position + base_id_width_c - 1;
        result.extended_id_start := 0;
        result.extended_id_stop  := 0;
        result.rrs_bit           := fb_rrs_c;
        result.ide_bit           := fb_ide_c;
        result.fdf_bit           := fb_fdf_c;
        result.res_bit           := fb_res_c;
        result.brs_bit           := (position => fb_brs_c.position, polarity => brs_polarity_v);
        result.esi_bit           := (position => fb_esi_c.position, polarity => esi_polarity_v);
        result.srr_bit           := unknown_bit_c;
        result.rtr_bit           := unknown_bit_c;
        result.r0_bit            := unknown_bit_c;
        result.r1_bit            := unknown_bit_c;

      when fd_extended =>
        data_start_v             := fe_data_start_c.position;
        result.dlc_start         := fe_dlc_start_c.position;
        result.base_id_start     := fe_base_id_start_c.position;
        result.base_id_stop      := fe_base_id_start_c.position + base_id_width_c - 1;
        result.extended_id_start := fe_extended_id_start_c.position;
        result.extended_id_stop  := fe_extended_id_start_c.position + extended_id_width_c - 1;
        result.srr_bit           := fe_srr_c;
        result.ide_bit           := fe_ide_c;
        result.rrs_bit           := fe_rrs_c;
        result.fdf_bit           := fe_fdf_c;
        result.res_bit           := fe_res_c;
        result.brs_bit           := (position => fe_brs_c.position, polarity => brs_polarity_v);
        result.esi_bit           := (position => fe_esi_c.position, polarity => esi_polarity_v);
        result.rtr_bit           := unknown_bit_c;
        result.r0_bit            := unknown_bit_c;
        result.r1_bit            := unknown_bit_c;

      when others =>
        data_start_v             := 0;
        result.dlc_start         := 0;
        result.base_id_start     := 0;
        result.base_id_stop      := 0;
        result.extended_id_start := 0;
        result.extended_id_stop  := 0;
        result.rtr_bit           := unknown_bit_c;
        result.ide_bit           := unknown_bit_c;
        result.srr_bit           := unknown_bit_c;
        result.rrs_bit           := unknown_bit_c;
        result.fdf_bit           := unknown_bit_c;
        result.res_bit           := unknown_bit_c;
        result.r0_bit            := unknown_bit_c;
        result.r1_bit            := unknown_bit_c;
        result.brs_bit           := unknown_bit_c;
        result.esi_bit           := unknown_bit_c;
    end case;

    -- Calculate all data and CRC field positions
    result.data_start := data_start_v;

    if (data_bits_v > 0) then
      result.data_stop := data_start_v + data_bits_v - 1;
    else
      result.data_stop := data_start_v;
    end if;

    -- DLC field boundaries
    result.dlc_stop := result.dlc_start + dlc_field_width_c;

    crc_length_v     := get_crc_length(result.format, data_length_v);
    result.crc_start := result.data_stop + 1;

    -- CAN FD has SBC field after data, CAN Classic goes directly to CRC
    if (result.is_fd_frame) then
      sbc_start_v         := result.crc_start;
      result.sbc_start    := sbc_start_v;
      result.sbc_stop     := sbc_start_v + sbc_field_width_c;
      result.crc_start    := result.sbc_stop;
      fixed_stuff_count_v := get_fixed_stuff_bit_count(sbc_field_width_c + crc_length_v);
      crc_field_length_v  := crc_length_v + fixed_stuff_count_v;
      result.crc_stop     := result.crc_start + crc_field_length_v;
    else
      result.sbc_start   := 0;
      result.sbc_stop    := 0;
      crc_field_length_v := crc_length_v;
      result.crc_start   := result.data_stop + 1;
      result.crc_stop    := result.crc_start + crc_length_v;
    end if;

    result.crc_delimiter := result.crc_stop;

    -- Determine CRC polynomial selection (00=CRC15, 01=CRC17, 10=CRC21)
    case crc_length_v is
      when crc_15_length_c =>
        result.crc_poly_select := "00";
      when crc_17_length_c =>
        result.crc_poly_select := "01";
      when crc_21_length_c =>
        result.crc_poly_select := "10";
      when others =>
        result.crc_poly_select := "11";
    end case;

    -- ACK and EOF field positions
    result.ack_slot      := result.crc_delimiter + 1;
    result.ack_delimiter := result.ack_slot + 1;
    result.eof_start     := result.ack_delimiter + 1;
    result.eof_stop      := result.eof_start + eof_field_width_c;

    return result;

  end function calculate_frame_params;

  function pack_llc_id_bytes (
    id         : std_logic_vector(28 downto 0);
    can_format : can_format_t
  ) return std_logic_vector is

    variable result_v : std_logic_vector(31 downto 0);

  begin

    result_v := (others => '0');
    if (can_format = cc_extended or can_format = fd_extended) then
      result_v(31 downto 3) := id(28 downto 0);
    else
      result_v(31 downto 21) := id(10 downto 0);
    end if;

    return result_v;

  end function pack_llc_id_bytes;

  function decode_llc_format (
    format_slv : std_logic_vector(2 downto 0)
  ) return can_format_t is

  begin

    case format_slv is
      when llc_fmt_cb_c => return cc_basic;
      when llc_fmt_ce_c => return cc_extended;
      when llc_fmt_fb_c => return fd_basic;
      when llc_fmt_fe_c => return fd_extended;
      when others => return unknown;
    end case;

  end function decode_llc_format;

end package body can_protocol_pkg;
