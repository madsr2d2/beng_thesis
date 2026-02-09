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
  constant sof_bit_position_c     : integer                       := 0;
  constant crc_poly_15_vec_c      : std_logic_vector(15 downto 0) := x"C599";
  constant crc_poly_17_vec_c      : std_logic_vector(19 downto 0) := x"3685B";
  constant crc_poly_21_vec_c      : std_logic_vector(23 downto 0) := x"302899";
  constant cc_basic_data_c        : integer                       := 19;
  constant cc_extended_data_c     : integer                       := 39;
  constant fd_basic_data_c        : integer                       := 22;
  constant fd_extended_data_c     : integer                       := 41;
  constant cc_basic_dlc_c         : integer                       := 15;
  constant cc_extended_dlc_c      : integer                       := 35;
  constant fd_basic_dlc_c         : integer                       := 18;
  constant fd_extended_dlc_c      : integer                       := 37;
  constant dlc_max_decimal_value  : integer                       := 15;
  constant dlc_field_width_c      : integer                       := 4;
  constant sbc_filed_width_c      : integer                       := 4;
  constant byte_width_c           : integer                       := 8;
  constant max_mac_frame_length_c : integer                       := 1024; -- TODO: Can we get by with 512?

  -- can classic  form bit positions
  constant cc_basic_rtr_c : integer := 12;
  constant cc_basic_ide_c : integer := 13;
  constant cc_basic_r0_c  : integer := 14;

  -- can extended form bit positions
  constant cc_extended_srr_c : integer := 12;
  constant cc_extended_ide_c : integer := 13;
  constant cc_extended_rtr_c : integer := 32;
  constant cc_extended_r1_c  : integer := 33;
  constant cc_extended_r0_c  : integer := 34;

  -- can FD basic form bit positions
  constant fd_basic_rss_c : integer := 12;
  constant fd_basic_ide_c : integer := 13;
  constant fd_basic_fdf_c : integer := 14;
  constant fd_basic_res_c : integer := 15;
  constant fd_basic_brs_c : integer := 16;
  constant fd_basic_esi_c : integer := 17;

  -- can FD extended form bit positions
  constant fd_extended_srr_c : integer := 12;
  constant fd_extended_ide_c : integer := 13;
  constant fd_extended_rrs_c : integer := 32;
  constant fd_extended_fdf_c : integer := 33;
  constant fd_extended_res_c : integer := 34;
  constant fd_extended_brs_c : integer := 35;
  constant fd_extended_esi_c : integer := 36;

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

  -- MAC layer TX state type
  type tx_mac_state_t is (
    idle,
    transmitting_mac_frame,
    transmitting_error_flag
  );

  -- LLC to MAC controller state type
  type tx_mac_llc_ctrl_state_t is (
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
  type mac_error_flag_t is (
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

  -- Ensure one_hot encoding of all FSM state types
  attribute fsm_encoding : string;
  attribute fsm_encoding of can_format_t            : type is "one_hot";
  attribute fsm_encoding of can_node_type_t         : type is "one_hot";
  attribute fsm_encoding of frame_type_t            : type is "one_hot";
  attribute fsm_encoding of mac_frame_field_t       : type is "one_hot";
  attribute fsm_encoding of tx_mac_state_t          : type is "one_hot";
  attribute fsm_encoding of tx_mac_llc_ctrl_state_t : type is "one_hot";
  attribute fsm_encoding of tx_mac_error_t          : type is "one_hot";
  attribute fsm_encoding of mac_error_flag_t        : type is "one_hot";
  attribute fsm_encoding of transfer_status_t       : type is "one_hot";

  -- Byte
  subtype byte_t is std_logic_vector(byte_width_c - 1 downto 0);

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

  -- DLC
  subtype dlc_t is integer range 0 to dlc_max_decimal_value;

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

  -- Form bit entry
  type form_bit_entry_t is record
    position : integer;
    polarity : std_logic;
  end record form_bit_entry_t;

  -- Composite type for MAC frame bit info
  type mac_frame_bit_info_t is record
    is_form_bit : boolean;
    polarity    : std_logic;
    frame_field : mac_frame_field_t;
    brs_enable  : boolean; -- Used to signal bit rate switch to PC layer
  end record mac_frame_bit_info_t;

  -- Static form bit table type
  type form_bit_table_t is array (0 to max_static_form_bits_c - 1) of form_bit_entry_t;

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
  -- Static form bit tables
  -- =================================================================
  constant cc_basic_static_form_bits : form_bit_table_t :=
  (
    0      => (position => sof_bit_position_c, polarity => dominant_bit_c), -- SOF
    1      => (position => cc_basic_ide_c, polarity => dominant_bit_c),     -- IDE
    2      => (position => cc_basic_r0_c, polarity => dominant_bit_c),      -- r0
    others => (position => -1, polarity => recessive_bit_c)
  );

  constant cc_extended_static_form_bits : form_bit_table_t :=
  (
    0      => (position => sof_bit_position_c, polarity => dominant_bit_c), -- SOF
    1      => (position => cc_extended_srr_c, polarity => recessive_bit_c), -- SRR
    2      => (position => cc_extended_ide_c, polarity => recessive_bit_c), -- IDE
    3      => (position => cc_extended_r1_c, polarity => dominant_bit_c),   -- r1
    4      => (position => cc_extended_r0_c,  polarity => dominant_bit_c),  -- r0
    others => (position => -1, polarity => recessive_bit_c)
  );

  constant fd_basic_static_form_bits : form_bit_table_t :=
  (
    0      => (position => sof_bit_position_c, polarity => dominant_bit_c), -- SOF
    1      => (position => fd_basic_rss_c, polarity => dominant_bit_c),     -- RRS
    2      => (position => fd_basic_ide_c, polarity => dominant_bit_c),     -- IDE
    3      => (position => fd_basic_fdf_c, polarity => recessive_bit_c),    -- FDF
    4      => (position => fd_basic_res_c,  polarity => dominant_bit_c),    -- RES
    others => (position => -1, polarity => recessive_bit_c)
  );

  constant fd_extended_static_form_bits : form_bit_table_t :=
  (
    0      => (position => sof_bit_position_c, polarity => dominant_bit_c), -- SOF
    1      => (position => fd_extended_srr_c, polarity => recessive_bit_c), -- SRR
    2      => (position => fd_extended_ide_c, polarity => recessive_bit_c), -- IDE
    3      => (position => fd_extended_rrs_c, polarity => dominant_bit_c),  -- RRS
    4      => (position => fd_extended_fdf_c, polarity => recessive_bit_c), -- FDF
    5      => (position => fd_extended_res_c, polarity => dominant_bit_c),  -- RES
    others => (position => -1, polarity => recessive_bit_c)
  );

  -- =================================================================
  -- Function declarations
  -- =================================================================

  -- Function return the error info on a monitored MAC frame bit
  function is_error_tx (
    mac_layer_tx_state : tx_mac_state_t;
    mac_error_flag : mac_error_flag_t;
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

  function tx_mac_frame_bit (
    bit_count    : integer;
    can_format   : can_format_t;
    frame_type   : frame_type_t;
    dlc          : dlc_t;
    brs_enable   : boolean;
    esi_flag     : boolean;
    previous_bit : std_logic
  ) return mac_frame_bit_info_t;

end package can_pkg;

-- =================================================================
-- PACKAGE BODY
-- =================================================================

package body can_pkg is

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

  -- Function returns TX error_info_t
  function is_error_tx (
    mac_layer_tx_state : tx_mac_state_t;
    mac_error_flag : mac_error_flag_t;
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
    if ((mac_layer_tx_state = transmitting_error_flag) and (mac_error_flag = passive_error_flag)) then
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

  -- Helper function to get data start position based on CAN format
  function get_data_start_position (
    can_format : can_format_t
  ) return integer is
  begin

    case can_format is
      when cc_basic => return cc_basic_data_c;
      when cc_extended => return cc_extended_data_c;
      when fd_basic => return fd_basic_data_c;
      when fd_extended => return fd_extended_data_c;
      when unknown => return 0;
    end case;

  end function get_data_start_position;

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

  -- Helper to get control field start position
  function get_control_start (
    can_format : can_format_t
  ) return integer is
  begin

    case can_format is
      when cc_basic => return cc_basic_ide_c;
      when cc_extended => return cc_extended_r1_c;
      when fd_basic => return fd_basic_ide_c;
      when fd_extended => return fd_extended_rrs_c;
      when unknown => return 0;
    end case;

  end function get_control_start;

  function tx_mac_frame_bit (
    bit_count    : integer;
    can_format   : can_format_t;
    frame_type   : frame_type_t;
    dlc          : dlc_t;
    brs_enable   : boolean;
    esi_flag     : boolean;
    previous_bit : std_logic
  ) return mac_frame_bit_info_t is

    variable result                : mac_frame_bit_info_t;
    variable static_table          : form_bit_table_t;
    variable data_start_pos        : integer;
    variable data_length           : integer;
    variable data_bits             : integer;
    variable crc_length            : integer;
    variable crc_field_length      : integer;
    variable crc_delim_pos         : integer;
    variable ack_slot_pos          : integer;
    variable ack_delim_pos         : integer;
    variable eof_start_pos         : integer;
    variable eof_end_pos           : integer;
    variable rtr_position          : integer;
    variable rtr_polarity          : std_logic;
    variable brs_position          : integer;
    variable brs_polarity          : std_logic;
    variable esi_position          : integer;
    variable esi_polarity          : std_logic;
    variable dlc_start_pos         : integer;
    variable dlc_bit_index         : integer;
    variable dlc_vector            : std_logic_vector(3 downto 0);
    variable control_start_pos     : integer;
    variable crc_start             : integer;
    variable position_in_crc_field : integer;
    variable fixed_stuff_count     : integer;

  begin

    -- Initialize return value
    result.is_form_bit := false;
    result.polarity    := '0';
    result.frame_field := field_unknown;
    result.brs_enable  := false;

    dlc_vector  := std_logic_vector(to_unsigned(dlc, 4));
    data_length := dlc_to_data_length(dlc, can_format);

    -- =================================================================
    -- Calculate positions
    -- =================================================================
    control_start_pos := get_control_start(can_format);
    data_start_pos    := get_data_start_position(can_format);
    data_bits         := data_length * 8;
    crc_start         := data_start_pos + data_bits;

    -- CAN FD CRC fields contains SBC and fixed stuff bits
    if is_fd_format(can_format) then
      crc_length        := get_crc_length(can_format, data_length); -- Get CRC length
      fixed_stuff_count := get_fixed_stuff_bit_count(sbc_filed_width_c + crc_length); -- Get fixed stiff bits count
      crc_field_length  := sbc_filed_width_c + crc_length + fixed_stuff_count; -- Get CRC field length
      crc_delim_pos     := crc_start + crc_field_length;
    else
      -- CAN Classic CRC field contains only CRC bits
      crc_length       := get_crc_length(can_format, data_length);
      crc_field_length := crc_length;  -- Just CRC, no fixed stuff bits
      crc_delim_pos    := crc_start + crc_field_length;
    end if;

    ack_slot_pos  := crc_delim_pos + 1;
    ack_delim_pos := ack_slot_pos + 1;
    eof_start_pos := ack_delim_pos + 1;
    eof_end_pos   := eof_start_pos + 6;

    -- =================================================================
    -- Determine current mac frame field
    -- =================================================================
    if (bit_count = sof_bit_position_c) then
      result.frame_field := field_sof;
    elsif (bit_count >= 1 and bit_count < control_start_pos) then
      result.frame_field := field_arbitration;
    elsif (bit_count >= control_start_pos and bit_count < data_start_pos) then
      result.frame_field := field_control;
    elsif (bit_count >= data_start_pos and bit_count < crc_start) then
      result.frame_field := field_data;
    elsif (bit_count >= crc_start and bit_count < ack_slot_pos) then
      result.frame_field := field_crc;
    elsif (bit_count = ack_slot_pos) then
      result.frame_field := field_ack_slot;
    elsif (bit_count = ack_delim_pos) then
      result.frame_field := field_ack_delimiter;
    elsif (bit_count >= eof_start_pos and bit_count < eof_end_pos + 1) then
      result.frame_field := field_eof;
    else
      result.frame_field := FIELD_UNKNOWN;
    end if;

    -- =================================================================
    -- Select static table and positions
    -- =================================================================
    case can_format is
      when cc_basic =>
        static_table  := CC_BASIC_STATIC_FORM_BITS;
        rtr_position  := cc_basic_rtr_c;
        brs_position  := -1;
        esi_position  := -1;
        dlc_start_pos := cc_basic_dlc_c;
      when cc_extended =>
        static_table  := CC_EXTENDED_STATIC_FORM_BITS;
        rtr_position  := cc_extended_rtr_c;
        brs_position  := -1;
        esi_position  := -1;
        dlc_start_pos := cc_extended_dlc_c;
      when fd_basic =>
        static_table  := FD_BASIC_STATIC_FORM_BITS;
        rtr_position  := -1;
        brs_position  := fd_basic_brs_c;
        esi_position  := fd_basic_esi_c;
        dlc_start_pos := fd_basic_dlc_c;
      when fd_extended =>
        static_table  := FD_EXTENDED_STATIC_FORM_BITS;
        rtr_position  := -1;
        brs_position  := fd_extended_brs_c;
        esi_position  := fd_extended_esi_c;
        dlc_start_pos := fd_extended_dlc_c;
      when unknown =>
        static_table  := cc_basic_static_form_bits;
        rtr_position  := -1;
        brs_position  := -1;
        esi_position  := -1;
        dlc_start_pos := -1;
    end case;

    -- =================================================================
    -- Set control bit polarities
    -- =================================================================
    case frame_type is
      when DATA_FRAME => rtr_polarity := dominant_bit_c;
      when REMOTE_FRAME => rtr_polarity := recessive_bit_c;
    end case;

    brs_polarity := recessive_bit_c when brs_enable else dominant_bit_c;
    esi_polarity := recessive_bit_c when esi_flag else dominant_bit_c;

    -- =================================================================
    -- Check control bits
    -- =================================================================
    if (rtr_position /= -1 and bit_count = rtr_position) then
      result.is_form_bit := true;
      result.polarity    := rtr_polarity;
      return result;
    end if;

    if (brs_position /= -1 and bit_count = brs_position) then
      result.is_form_bit := true;
      result.polarity    := brs_polarity;
      result.brs_enable  := true;
      return result;
    end if;

    if (esi_position /= -1 and bit_count = esi_position) then
      result.is_form_bit := true;
      result.polarity    := esi_polarity;
      return result;
    end if;

    -- =================================================================
    -- Check DLC field
    -- =================================================================
    if (bit_count >= dlc_start_pos and bit_count < dlc_start_pos + dlc_field_width_c) then
      result.is_form_bit := true;
      dlc_bit_index      := bit_count - dlc_start_pos;
      result.polarity    := dlc_vector(3 - dlc_bit_index);
      return result;
    end if;

    -- =================================================================
    -- Check static form bits
    -- =================================================================
    for i in static_table'range loop

      if (static_table(i).position = -1) then
        exit;
      end if;

      if (bit_count = static_table(i).position) then
        result.is_form_bit := true;
        result.polarity    := static_table(i).polarity;
        return result;
      end if;

    end loop;

    -- =================================================================
    -- Check for fixed stuff bits in CAN FD CRC field
    -- =================================================================
    if (is_fd_format(can_format) and bit_count >= crc_start and bit_count < ack_slot_pos) then
      position_in_crc_field := bit_count - crc_start;
      if is_fixed_stuff_bit_position(position_in_crc_field) then
        result.is_form_bit := true;
        result.polarity    := not previous_bit;
        return result;
      end if;
    end if;

    -- =================================================================
    -- Check dynamic form bits: ACK, ACK delimiter, CRC delimiter, EOF
    -- =================================================================
    if (bit_count = crc_delim_pos) then
      result.is_form_bit := true;
      result.polarity    := recessive_bit_c;
      result.brs_enable  := false;
      return result;
    end if;

    if (bit_count = ack_slot_pos) then
      result.is_form_bit := true;
      result.polarity    := recessive_bit_c;
      return result;
    end if;

    if (bit_count = ack_delim_pos) then
      result.is_form_bit := true;
      result.polarity    := recessive_bit_c;
      return result;
    end if;

    if (bit_count >= eof_start_pos and bit_count < eof_end_pos + 1) then
      result.is_form_bit := true;
      result.polarity    := recessive_bit_c;
      return result;
    end if;

    return result;

  end function tx_mac_frame_bit;

end package body can_pkg;
