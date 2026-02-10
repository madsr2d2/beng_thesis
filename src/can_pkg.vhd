library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

package can_pkg is

  -- =================================================================
  -- Constants
  -- =================================================================
  constant dominant_bit_c         : std_logic                     := '0';
  constant recessive_bit_c        : std_logic                     := '1';
  constant max_static_form_bits_c : integer                       := 8;
  constant sof_c                  : integer                       := 0;
  constant crc_poly_15_vec_c      : std_logic_vector(15 downto 0) := x"C599";
  constant crc_poly_17_vec_c      : std_logic_vector(19 downto 0) := x"3685B";
  constant crc_poly_21_vec_c      : std_logic_vector(23 downto 0) := x"302899";
  constant dlc_max_decimal_value  : integer                       := 15;
  constant dlc_field_width_c      : integer                       := 4;
  constant sbc_field_width_c      : integer                       := 4;
  constant byte_width_c           : integer                       := 8;
  constant max_mac_frame_length_c : integer                       := 1024; -- TODO: Can we get by with 512?
  constant base_id_width          : integer                       := 11;
  constant extended_id_width      : integer                       := 18;
  constant eof_field_width_c      : integer                       := 7;

  -- Polarity type
  type polarity_t is (
    dominant,
    recessive,
    unknown
  );

  -- Bit type has a position and a polarity
  type bit_t is record
    position : integer;
    polarity : polarity_t;
  end record bit_t;

  -- CAN Classic base frame format
  constant cb_base_id_start_c : bit_t := (sof_c + 1, dominant);
  constant cb_base_id_stop_c  : bit_t := (cb_base_id_start_c.position + base_id_width - 1, unknown);
  constant cb_rtr_c           : bit_t := (cb_base_id_stop_c.position + 1, unknown);
  constant cb_ide_c           : bit_t := (cb_rtr_c.position + 1, dominant);
  constant cb_r0_c            : bit_t := (cb_ide_c.position + 1, dominant);
  constant cb_dlc_start_c     : bit_t := (cb_r0_c.position + 1, unknown);
  constant cb_dlc_stop_c      : bit_t := (cb_dlc_start_c.position + dlc_field_width_c - 1, unknown);
  constant cb_data_start_c    : bit_t := (cb_dlc_stop_c.position + 1, unknown);

  -- CAN Classic extended frame format
  constant ce_base_id_start_c     : bit_t := (sof_c + 1, unknown);
  constant ce_base_id_stop_c      : bit_t := (ce_base_id_start_c.position + base_id_width - 1, unknown);
  constant ce_srr_c               : bit_t := (ce_base_id_stop_c.position + 1, recessive);
  constant ce_ide_c               : bit_t := (ce_srr_c.position + 1, recessive);
  constant ce_extended_id_start_c : bit_t := (ce_ide_c.position + 1, unknown);
  constant ce_extended_id_stop_c  : bit_t := (ce_extended_id_start_c.position + extended_id_width - 1, unknown);
  constant ce_rtr_c               : bit_t := (ce_extended_id_stop_c.position + 1, unknown);
  constant ce_r1_c                : bit_t := (ce_rtr_c.position + 1, dominant);
  constant ce_r0_c                : bit_t := (ce_r1_c.position + 1, dominant);
  constant ce_dlc_start_c         : bit_t := (ce_r0_c.position + 1, unknown);
  constant ce_dlc_stop_c          : bit_t := (ce_dlc_start_c.position + dlc_field_width_c - 1, unknown);
  constant ce_data_start_c        : bit_t := (ce_dlc_stop_c.position + 1, unknown);

  -- FD base frame format
  constant fd_base_id_start_c : bit_t := (sof_c + 1, unknown);
  constant fd_base_id_stop_c  : bit_t := (fd_base_id_start_c.position + base_id_width - 1, unknown);
  constant fb_rrs_c           : bit_t := (fd_base_id_stop_c.position + 1, dominant);
  constant fb_ide_c           : bit_t := (fb_rrs_c.position + 1, dominant);
  constant fb_fdf_c           : bit_t := (fb_ide_c.position + 1, recessive);
  constant fb_res_c           : bit_t := (fb_fdf_c.position + 1, dominant);
  constant fb_brs_c           : bit_t := (fb_res_c.position + 1, unknown);
  constant fb_esi_c           : bit_t := (fb_brs_c.position + 1, unknown);
  constant fb_dlc_start_c     : bit_t := (fb_esi_c.position + 1, unknown);
  constant fb_dlc_stop_c      : bit_t := (fb_dlc_start_c.position + dlc_field_width_c - 1, unknown);
  constant fb_data_start_c    : bit_t := (fb_dlc_stop_c.position + 1, unknown);

  -- FD extended frame format
  constant fe_base_id_start_c     : bit_t := (sof_c + 1, unknown);
  constant fe_base_id_stop_c      : bit_t := (fe_base_id_start_c.position + base_id_width - 1, unknown);
  constant fe_srr_c               : bit_t := (fe_base_id_stop_c.position + 1, recessive);
  constant fe_ide_c               : bit_t := (fe_srr_c.position + 1, recessive);
  constant fe_extended_id_start_c : bit_t := (fe_ide_c.position + 1, unknown);
  constant fe_extended_id_stop_c  : bit_t := (fe_extended_id_start_c.position + extended_id_width - 1, unknown);
  constant fe_rrs_c               : bit_t := (fe_extended_id_stop_c.position + 1, dominant);
  constant fe_fdf_c               : bit_t := (fe_rrs_c.position + 1, recessive);
  constant fe_res_c               : bit_t := (fe_fdf_c.position + 1, dominant);
  constant fe_brs_c               : bit_t := (fe_res_c.position + 1, unknown);
  constant fe_esi_c               : bit_t := (fe_brs_c.position + 1, unknown);
  constant fe_dlc_start_c         : bit_t := (fe_esi_c.position + 1, unknown);
  constant fe_dlc_stop_c          : bit_t := (fe_dlc_start_c.position + dlc_field_width_c - 1, unknown);
  constant fe_data_start_c        : bit_t := (fe_dlc_stop_c.position + 1, unknown);

  -- LLC frame config bytes (byte 0 and byte 1) structure
  constant llc_frame_config_byte_0_format_start : integer := byte_width_c - 1;
  constant llc_frame_config_byte_0_format_end   : integer := llc_frame_config_byte_0_format_start - 2;
  constant llc_frame_config_byte_0_ftyp         : integer := llc_frame_config_byte_0_format_start - 3;
  constant llc_frame_config_byte_0_esi          : integer := llc_frame_config_byte_0_format_start - 4;
  constant llc_frame_config_byte_0_brs          : integer := llc_frame_config_byte_0_format_start - 5;
  constant llc_frame_config_byte_1_dlc_start    : integer := byte_width_c - 1;
  constant llc_frame_config_byte_1_dlc_end      : integer := llc_frame_config_byte_1_dlc_start - 3;

  -- =================================================================
  -- Types
  -- =================================================================
  -- CAN frame format types
  type can_format_t is (
    cc_basic,
    cc_extended,
    fd_basic,
    fd_extended,
    unknown
  );

  -- Node type (for ACK slot polarity)
  type can_node_type_t is (
    transmitter,
    receiver
  );

  -- Frame type (data vs remote)
  type frame_type_t is (
    data_frame,
    remote_frame
  );

  -- MAC frame fields
  type mac_frame_field_t is (
    field_sof,
    field_arbitration,
    field_control,
    field_data,
    field_crc,
    field_ack_slot,
    field_ack_delimiter,
    field_eof,
    field_unknown
  );

  -- CRC vector
  subtype crc_vector_t is std_logic_vector(crc_poly_21_vec_c'left downto 0);

  -- MAC layer TX state type
  type tx_mac_fsm_state_t is (
    idle,
    transmitting_mac_frame,
    transmitting_error_flag
  );

  -- tx_mac_ser states
  type tx_mac_ser_state_t is (
    load_config_byte_0,
    load_config_byte_1,
    load_llc_frame_byte,
    shift_out_bits
  );

  -- MAC frame error type
  type tx_mac_error_t is (
    bit_error,
    ack_error
  );

  -- MAC error flag type
  type error_flag_t is (
    active_error_flag,
    passive_error_flag
  );

  -- Transfer status type
  type transfer_status_t is (
    ongoing,
    lost_arbitration,
    transmitted,
    aborted,
    disturbed
  );

  type bit_type_t is (
    unknown,
    -- CC bit types
    stuff_bit,
    active_error_flag_bit,
    passive_error_flag_bit,
    sof_bit,
    base_id_bit,
    extended_id_bit,
    rtr_bit,
    srr_bit,
    ide_bit,
    r0_bit,
    r1_bit,
    dlc_bit,
    data_bit,
    crc_bit,
    crc_delimiter_bit,
    ack_bit,
    ack_delimiter_bit,
    eof_bit,
    -- FD bit type additions
    rrs_bit,
    fdf_bit,
    res_bit,
    brs_bit,
    esi_bit,
    sbs_bit,
    fixed_stuff_bit
  );

  -- Ensure one_hot encoding of all FSM state types
  attribute fsm_encoding : string;
  attribute fsm_encoding of can_format_t       : type is "one_hot";
  attribute fsm_encoding of can_node_type_t    : type is "one_hot";
  attribute fsm_encoding of frame_type_t       : type is "one_hot";
  attribute fsm_encoding of mac_frame_field_t  : type is "one_hot";
  attribute fsm_encoding of tx_mac_fsm_state_t : type is "one_hot";
  attribute fsm_encoding of tx_mac_ser_state_t : type is "one_hot";
  attribute fsm_encoding of tx_mac_error_t     : type is "one_hot";
  attribute fsm_encoding of error_flag_t       : type is "one_hot";
  attribute fsm_encoding of transfer_status_t  : type is "one_hot";

  -- Byte
  subtype byte_t is std_logic_vector(byte_width_c - 1 downto 0
  );

  -- Avalon-ST interface
  type avalon_st_source_t is record
    data  : byte_t;
    valid : std_logic;
    sop   : std_logic;
    eop   : std_logic;
  end record avalon_st_source_t;

  type avalon_st_sink_t is record
    ready : std_logic;
  end record avalon_st_sink_t;

  -- DLC (Data Length Code)
  subtype dlc_t is integer range 0 to dlc_max_decimal_value;

  -- SBC (Stuff Bit Count)
  subtype sbc_t is std_logic_vector(sbc_field_width_c - 1 downto 0);

  -- Record encapsulates the LLC frame info
  type llc_frame_info_t is record
    format     : can_format_t;
    ftyp       : frame_type_t;
    brs_enable : boolean;
    esi_enable : boolean;
    dlc        : dlc_t;
  end record llc_frame_info_t;

  -- error info
  type error_info_t is record
    is_error   : boolean;
    error_type : tx_mac_error_t;
  end record error_info_t;

  -- Composite type for MAC frame bit info
  type mac_frame_bit_t is record
    polarity : polarity_t;
    bit_type : bit_type_t;
  end record mac_frame_bit_t;

  -- tx_mac_ser to tx_mac_fsm interface
  type tx_mac_ser_to_fsm_if_t is record
    data       : std_logic;
    valid      : std_logic;
    frame_info : llc_frame_info_t;
  end record tx_mac_ser_to_fsm_if_t;

  -- tx_mac_fsm to tx_mac_ser interface
  type tx_mac_fsm_to_ser_if_t is record
    transfer_status  : transfer_status_t;
    tx_mac_fsm_state : tx_mac_fsm_state_t;
    ready            : std_logic;
  end record tx_mac_fsm_to_ser_if_t;

  -- LLC to MAC interface
  type llc_to_mac_if_t is record
    avalon_st_source : avalon_st_source_t;
  end record llc_to_mac_if_t;

  -- MAC to LLC interface
  type mac_to_llc_if_t is record
    avalon_st_sink  : avalon_st_sink_t;
    transfer_status : transfer_status_t;
  end record mac_to_llc_if_t;

  -- PCS (Physical Coding Sublayer) Interface
  type mac_pcs_if_t is record
    mac_bit         : std_logic;
    mac_bit_valid   : std_logic;
    mac_bit_ready   : std_logic;
    transmit_status : std_logic;
    receive_status  : std_logic;
  end record mac_pcs_if_t;

  type pcs_mac_if_t is record
    mac_bit       : std_logic;
    mac_bit_valid : std_logic;
    mac_bit_ready : std_logic;
  end record pcs_mac_if_t;

  -- Bit Stuffer FD Interface
  type mac_fsm_to_bs_fd_if_t is record
    data       : std_logic;
    data_valid : std_logic;
  end record mac_fsm_to_bs_fd_if_t;

  type bs_fd_to_mac_fsm_if_t is record
    stuff_bit       : std_logic;
    stuff_bit_valid : std_logic;
    sbc             : std_logic_vector(3 downto 0);
  end record bs_fd_to_mac_fsm_if_t;

  -- CRC Interface
  type mac_fsm_to_crc_if_t is record
    -- TODO: Remove clk and rst from the interface
    clk             : std_logic;
    rst             : std_logic;
    crc_poly_select : std_logic_vector(1 downto 0);
    shift           : std_logic;
    data            : std_logic;
  end record mac_fsm_to_crc_if_t;

  type crc_to_mac_fsm_if_t is record
    data       : std_logic;
    data_valid : std_logic;
  end record crc_to_mac_fsm_if_t;

  -- Shift Register Interface
  type shift_reg_in_if_t is record
    -- TODO: Remove clk and rst from the interface
    clk       : std_logic;
    rst       : std_logic;
    shift     : std_logic;
    load      : std_logic;
    data_in   : byte_t;
    serial_in : std_logic;
  end record shift_reg_in_if_t;

  type shift_reg_out_t is record
    empty      : std_logic;
    data_out   : byte_t;
    serial_out : std_logic;
  end record shift_reg_out_t;

  -- =================================================================
  -- Function declarations
  -- =================================================================

  -- Function returns TX error_info_t
  function is_error_tx (
    tx_mac_fsm_state : tx_mac_fsm_state_t;
    mac_error_flag : error_flag_t;
    frame_field : mac_frame_field_t;
    sent_bit : std_logic;
    monitored_bit : std_logic
  ) return error_info_t;

  -- Function calculates the parity bit for a std_logic_vector
  function calc_parity (
    v : std_logic_vector
  ) return std_logic;

  -- Function Gray encodes a std_logic_vector
  function to_gray (
    v : std_logic_vector
  ) return std_logic_vector;

  -- Function converts the LLC frame configuration byte (byte 0) to frame_type_t
  function get_frame_info (
    config_byte_0 : byte_t;
    config_byte_1 : byte_t
  ) return llc_frame_info_t;

  function get_next_frame_bit (
    bit_count    : integer;
    -- From tx_mac_ser
    mac_ser_to_fsm : tx_mac_ser_to_fsm_if_t;
    previous_polarity : polarity_t;
    -- From bit stuffer
    stuff_bit : std_logic;
    stuff_bit_valid : boolean;
    sbc : sbc_t;
    crc : crc_vector_t
  ) return mac_frame_bit_t;

end package can_pkg;

-- =================================================================
-- PACKAGE BODY
-- =================================================================

package body can_pkg is

  function is_error_tx (
    tx_mac_fsm_state : tx_mac_fsm_state_t;
    mac_error_flag : error_flag_t;
    frame_field : mac_frame_field_t;
    sent_bit : std_logic;
    monitored_bit : std_logic
  ) return error_info_t is

    variable result : error_info_t;

  begin

    -- Default value
    result.is_error   := false;
    result.error_type := bit_error;

    -- Check for ACK error
    if (frame_field = field_ack_slot) then
      if (monitored_bit = recessive_bit_c) then
        result.is_error   := true;
        result.error_type := ack_error;
      end if;
      return result;
    end if;

    -- Exception 2: Don't check during passive error flag transmission (ISO 11898-1 6.6.21.2)
    if ((tx_mac_fsm_state = transmitting_error_flag) and (mac_error_flag = passive_error_flag)) then
      return result;
    end if;

    -- Exception 1: In arbitration field, only check when sending dominant (ISO 11898-1 6.6.21.2)
    if (sent_bit /= monitored_bit) then
      if (frame_field = field_arbitration) then
        if (sent_bit = dominant_bit_c) then
          result.is_error   := true;
          result.error_type := bit_error;
        end if;
      else
        -- Everywhere else: check for mismatch
        result.is_error   := true;
        result.error_type := bit_error;
      end if;
    end if;

    return result;

  end function is_error_tx;

  function get_frame_info (
    config_byte_0 : byte_t;
    config_byte_1 : byte_t
  ) return llc_frame_info_t is

    variable result : llc_frame_info_t;

  begin

    -- Get Error State Indicator (ESI)
    result.esi_enable := true when config_byte_0(llc_frame_config_byte_0_esi) = '1' else false;
    -- Get Bit rate switch (BRS)
    result.brs_enable := true when config_byte_0(llc_frame_config_byte_0_brs) = '1' else false;
    -- Get frame type (FTYP)
    result.ftyp := remote_frame when config_byte_0(llc_frame_config_byte_0_ftyp) = '1' else data_frame;

    -- Get frame format
    case config_byte_0(llc_frame_config_byte_0_format_start downto llc_frame_config_byte_0_format_end) is
      when "000" =>
        result.format := cc_basic;
      when "100" =>
        result.format := cc_extended;
      when "010" =>
        result.format := fd_basic;
      when "110" =>
        result.format := fd_extended;
      when others =>
        result.format := unknown;
    end case;

    -- Get DLC
    result.dlc := dlc_t(to_integer(unsigned(config_byte_1(llc_frame_config_byte_1_dlc_start downto llc_frame_config_byte_1_dlc_end))));

    -- Get frame type
    return result;

  end function get_frame_info;

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
          when 15 => return 64;
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
        return 15;  -- CRC-15 for classic CAN
      when fd_basic | fd_extended =>
        -- Use CRC-17 for payloads <= 16 bytes, CRC-21 otherwise
        if (data_length <= 16) then
          return 17;
        else
          return 21;
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

  function get_next_frame_bit (
    bit_count    : integer;
    mac_ser_to_fsm : tx_mac_ser_to_fsm_if_t;
    previous_polarity : polarity_t;
    -- From bit stuffer
    stuff_bit : std_logic;
    stuff_bit_valid : boolean;
    sbc : sbc_t;
    crc : crc_vector_t
  ) return mac_frame_bit_t is

    variable result                : mac_frame_bit_t;
    variable data_start            : integer;
    variable data_stop             : integer;
    variable sbc_start             : bit_t;
    variable sbc_stop              : bit_t;
    variable data_length           : integer;
    variable data_bits             : integer;
    variable crc_length            : integer;
    variable crc_field_length      : integer;
    variable crc_delim             : bit_t;
    variable ack_slot              : bit_t;
    variable ack_delim             : bit_t;
    variable eof_start             : bit_t;
    variable eof_end               : bit_t;
    variable dlc_vector            : std_logic_vector(dlc_field_width_c - 1 downto 0);
    variable dlc_start             : integer;
    variable crc_start             : bit_t;
    variable position_in_crc_field : integer;
    variable fixed_stuff_count     : integer;

  begin

    result.polarity := unknown;
    result.bit_type := unknown;

    -- Priority 1: Check for valid stuff bit from bit stuffer
    if (stuff_bit_valid) then
      result.bit_type := fixed_stuff_bit;
      result.polarity := dominant when stuff_bit = dominant_bit_c else recessive;
      return result;
    end if;

    dlc_vector  := std_logic_vector(to_unsigned(mac_ser_to_fsm.frame_info.dlc, 4));
    data_length := dlc_to_data_length(mac_ser_to_fsm.frame_info.dlc, mac_ser_to_fsm.frame_info.format);

    -- =================================================================
    -- Calculate dynamic positions based on data length and format
    -- =================================================================
    case mac_ser_to_fsm.frame_info.format is
      when cc_basic =>
        data_start := cb_data_start_c.position;
        dlc_start  := cb_dlc_start_c.position;
      when cc_extended =>
        data_start := ce_data_start_c.position;
        dlc_start  := ce_dlc_start_c.position;
      when fd_basic =>
        data_start := fb_data_start_c.position;
        dlc_start  := fb_dlc_start_c.position;
      when fd_extended =>
        data_start := fe_data_start_c.position;
        dlc_start  := fe_dlc_start_c.position;
      when unknown =>
        data_start := 0;
        dlc_start  := 0;
    end case;

    data_bits := data_length * byte_width_c;
    data_stop := data_start + data_bits - 1;

    -- CAN FD has SBC field after data, CAN Classic goes directly to CRC
    if is_fd_format(mac_ser_to_fsm.frame_info.format) then
      sbc_start.position := data_stop + 1;
      sbc_start.polarity := unknown;
      sbc_stop.position  := sbc_start.position + sbc_field_width_c - 1;
      sbc_stop.polarity  := unknown;
      crc_start.position := sbc_stop.position + 1;
      crc_start.polarity := unknown;
      crc_length         := get_crc_length(mac_ser_to_fsm.frame_info.format, data_length);
      fixed_stuff_count  := get_fixed_stuff_bit_count(sbc_field_width_c + crc_length);
      crc_field_length   := crc_length + fixed_stuff_count;
      crc_delim.position := crc_start.position + crc_field_length;
      crc_delim.polarity := recessive;
    else
      -- CAN Classic: no SBC field, CRC follows directly after data
      crc_start.position := data_stop + 1;
      crc_start.polarity := unknown;
      crc_length         := get_crc_length(mac_ser_to_fsm.frame_info.format, data_length);
      crc_field_length   := crc_length;
      crc_delim.position := crc_start.position + crc_field_length;
      crc_delim.polarity := recessive;
    end if;

    ack_slot.position  := crc_delim.position + 1;
    ack_slot.polarity  := recessive;
    ack_delim.position := ack_slot.position + 1;
    ack_delim.polarity := recessive;
    eof_start.position := ack_delim.position + 1;
    eof_start.polarity := recessive;
    eof_end.position   := eof_start.position + eof_field_width_c - 1;
    eof_end.polarity   := recessive;

    -- =================================================================
    -- Determine bit type based on position and format using constants
    -- =================================================================
    if (bit_count = sof_c) then
      result.bit_type := sof_bit;
    elsif (bit_count >= data_start and bit_count < data_start + data_bits) then
      result.bit_type := data_bit;
    elsif (is_fd_format(mac_ser_to_fsm.frame_info.format) and bit_count >= sbc_start.position and bit_count < sbc_start.position + sbc_field_width_c) then
      -- Output SBC bits when in SBC region (CAN FD only)
      result.bit_type := sbs_bit;
      result.polarity := dominant when sbc(sbc'left - (bit_count - sbc_start.position)) = dominant_bit_c else recessive;
      return result;
    -- Output CRC bits when in CRC region
    elsif (bit_count >= crc_start.position and bit_count < crc_delim.position) then
      result.bit_type := crc_bit;
      result.polarity := dominant when crc(crc'left - (bit_count - crc_start.position)) = dominant_bit_c else recessive;
      return result;
    -- Output DLC bits when in DLC region (format-specific)
    elsif (bit_count >= dlc_start and bit_count < dlc_start + dlc_field_width_c) then
      result.bit_type := dlc_bit;
      result.polarity := dominant when dlc_vector(dlc_vector'left - (bit_count - dlc_start)) = dominant_bit_c else recessive;
      return result;
    elsif (bit_count = crc_delim.position) then
      result.bit_type := crc_delimiter_bit;
      result.polarity := crc_delim.polarity;
    elsif (bit_count = ack_slot.position) then
      result.bit_type := ack_bit;
      result.polarity := ack_slot.polarity;
    elsif (bit_count = ack_delim.position) then
      result.bit_type := ack_delimiter_bit;
      result.polarity := ack_delim.polarity;
    elsif (bit_count >= eof_start.position and bit_count < eof_start.position + eof_field_width_c) then
      result.bit_type := eof_bit;
      result.polarity := eof_start.polarity;
    else
      -- Check format-specific bits (ID, control bits) using constants directly
      case mac_ser_to_fsm.frame_info.format is
        when cc_basic =>
          if (bit_count >= cb_base_id_start_c.position and bit_count < cb_base_id_start_c.position + base_id_width) then
            result.bit_type := base_id_bit;
            result.polarity := dominant when mac_ser_to_fsm.data = dominant_bit_c else recessive;
          elsif (bit_count = cb_rtr_c.position) then
            result.bit_type := rtr_bit;
            result.polarity := cb_rtr_c.polarity;
          elsif (bit_count = cb_ide_c.position) then
            result.bit_type := ide_bit;
            result.polarity := cb_ide_c.polarity;
          elsif (bit_count = cb_r0_c.position) then
            result.bit_type := r0_bit;
            result.polarity := cb_r0_c.polarity;
          end if;

        when cc_extended =>
          if (bit_count >= ce_base_id_start_c.position and bit_count < ce_base_id_start_c.position + base_id_width) then
            result.bit_type := base_id_bit;
            result.polarity := dominant when mac_ser_to_fsm.data = dominant_bit_c else recessive;
          elsif (bit_count >= ce_extended_id_start_c.position and bit_count < ce_extended_id_start_c.position + extended_id_width) then
            result.bit_type := extended_id_bit;
            result.polarity := dominant when mac_ser_to_fsm.data = dominant_bit_c else recessive;
          elsif (bit_count = ce_srr_c.position) then
            result.bit_type := srr_bit;
            result.polarity := ce_srr_c.polarity;
          elsif (bit_count = ce_ide_c.position) then
            result.bit_type := ide_bit;
            result.polarity := ce_ide_c.polarity;
          elsif (bit_count = ce_rtr_c.position) then
            result.bit_type := rtr_bit;
            result.polarity := ce_rtr_c.polarity;
          elsif (bit_count = ce_r1_c.position) then
            result.bit_type := r1_bit;
            result.polarity := ce_r1_c.polarity;
          elsif (bit_count = ce_r0_c.position) then
            result.bit_type := r0_bit;
            result.polarity := ce_r0_c.polarity;
          end if;

        when fd_basic =>
          if (bit_count >= fd_base_id_start_c.position and bit_count < fd_base_id_start_c.position + base_id_width) then
            result.bit_type := base_id_bit;
            result.polarity := dominant when mac_ser_to_fsm.data = dominant_bit_c else recessive;
          elsif (bit_count = fb_rrs_c.position) then
            result.bit_type := rrs_bit;
            result.polarity := fb_rrs_c.polarity;
          elsif (bit_count = fb_ide_c.position) then
            result.bit_type := ide_bit;
            result.polarity := fb_ide_c.polarity;
          elsif (bit_count = fb_fdf_c.position) then
            result.bit_type := fdf_bit;
            result.polarity := fb_fdf_c.polarity;
          elsif (bit_count = fb_res_c.position) then
            result.bit_type := res_bit;
            result.polarity := fb_res_c.polarity;
          elsif (bit_count = fb_brs_c.position) then
            result.bit_type := brs_bit;
            result.polarity := fb_brs_c.polarity;
          elsif (bit_count = fb_esi_c.position) then
            result.bit_type := esi_bit;
            result.polarity := fb_esi_c.polarity;
          end if;

        when fd_extended =>
          if (bit_count >= fe_base_id_start_c.position and bit_count < fe_base_id_start_c.position + base_id_width) then
            result.bit_type := base_id_bit;
            result.polarity := dominant when mac_ser_to_fsm.data = dominant_bit_c else recessive;
          elsif (bit_count >= fe_extended_id_start_c.position and bit_count < fe_extended_id_start_c.position + extended_id_width) then
            result.bit_type := extended_id_bit;
            result.polarity := dominant when mac_ser_to_fsm.data = dominant_bit_c else recessive;
          elsif (bit_count = fe_srr_c.position) then
            result.bit_type := srr_bit;
            result.polarity := fe_srr_c.polarity;
          elsif (bit_count = fe_ide_c.position) then
            result.bit_type := ide_bit;
            result.polarity := fe_ide_c.polarity;
          elsif (bit_count = fe_rrs_c.position) then
            result.bit_type := rrs_bit;
            result.polarity := fe_rrs_c.polarity;
          elsif (bit_count = fe_fdf_c.position) then
            result.bit_type := fdf_bit;
            result.polarity := fe_fdf_c.polarity;
          elsif (bit_count = fe_res_c.position) then
            result.bit_type := res_bit;
            result.polarity := fe_res_c.polarity;
          elsif (bit_count = fe_brs_c.position) then
            result.bit_type := brs_bit;
            result.polarity := fe_brs_c.polarity;
          elsif (bit_count = fe_esi_c.position) then
            result.bit_type := esi_bit;
            result.polarity := fe_esi_c.polarity;
          end if;

        when unknown =>
          result.bit_type := unknown;
      end case;
    end if;

    -- =================================================================
    -- Check for fixed stuff bits in CAN FD CRC field
    -- =================================================================
    if (is_fd_format(mac_ser_to_fsm.frame_info.format) and bit_count >= crc_start.position and bit_count < ack_slot.position) then
      position_in_crc_field := bit_count - crc_start.position;
      if is_fixed_stuff_bit_position(position_in_crc_field) then
        result.bit_type := fixed_stuff_bit;
        result.polarity := recessive when previous_polarity = dominant else dominant;
        return result;
      end if;
    end if;

    return result;

  end function get_next_frame_bit;

end package body can_pkg;
