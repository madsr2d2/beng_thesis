library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

package can_pkg is

  -- =================================================================
  -- Basic constants
  -- =================================================================
  constant dominant_bit_c                : std_logic                     := '0';
  constant recessive_bit_c               : std_logic                     := '1';
  constant sof_c                         : integer                       := 0;
  constant crc_15_length_c               : integer                       := 15;
  constant crc_17_length_c               : integer                       := 17;
  constant crc_21_length_c               : integer                       := 21;
  constant crc_poly_15_vec_c             : std_logic_vector(15 downto 0) := x"C599";
  constant crc_poly_17_vec_c             : std_logic_vector(19 downto 0) := x"3685B";
  constant crc_poly_21_vec_c             : std_logic_vector(23 downto 0) := x"302899";
  constant dlc_field_width_c             : integer                       := 4;
  constant sbc_field_width_c             : integer                       := 4;
  constant byte_width_c                  : integer                       := 8;
  constant max_mac_frame_length_c        : integer                       := 1024; -- TODO: Can we get by with 512?
  constant base_id_width_c               : integer                       := 11;
  constant extended_id_width_c           : integer                       := 18;
  constant eof_field_width_c             : integer                       := 7;
  constant error_flag_width_c            : integer                       := 6;
  constant transmitted_bits_fifo_depth_c : integer                       := 32;   -- TODO:: random number...
  constant dlc_max_decimal_value         : integer                       := 15;
  constant max_data_bytes_c              : integer                       := 64;
  constant tdc_bit_time_max_c            : integer                       := 1000; -- ISO 11898-1: 7.3.4

  -- =================================================================
  -- CAN FD Bit Timing Configuration (Table 13, ISO 11898-1)
  -- =================================================================
  constant system_clock_freq_c : integer                := 100_000_000; -- 100 MHz
  constant prescalar_c         : integer range 1 to 32  := 1;
  constant sync_seg_c          : integer                := 1;
  constant prop_seg_c          : integer range 1 to 384 := 8;
  constant prop_seg_fd_c       : integer range 1 to 128 := 4;
  constant phase_seg1_c        : integer range 1 to 128 := 4;
  constant phase_seg1_fd_c     : integer range 1 to 128 := 4;
  constant phase_seg2_c        : integer range 1 to 128 := 4;
  constant phase_seg2_fd_c     : integer range 1 to 128 := 4;
  constant sjw_c               : integer range 1 to 128 := 4;
  constant ssp_offset_c        : integer range 1 to 160 := 160;

  -- =================================================================
  -- Type declarations
  -- =================================================================
  type mac_frame_bit_name_t is (
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
    fixed_stuff_bit,
    --
    unknown
  );

  type polarity_t is (
    dominant,
    recessive,
    unknown
  );

  -- MAC frame position
  subtype position_t is integer range 0 to max_mac_frame_length_c;

  -- Bit type has a position and a polarity
  type bit_t is record
    position : position_t;
    polarity : polarity_t;
  end record bit_t;

  constant unknown_bit_c : bit_t := (0, unknown);

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

  -- CRC vector
  subtype crc_vector_t is std_logic_vector(crc_poly_21_vec_c'left downto 0);

  -- MAC layer TX state type
  type tx_mac_fsm_state_t is (
    idle,
    transmitting,
    error
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

  -- TX monitoring event type
  type tx_mac_monitor_event_t is (
    none,
    ack_detected,
    ack_error,
    bit_error,
    lost_arbitration
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

  -- Byte
  subtype byte_t is std_logic_vector(byte_width_c - 1 downto 0);

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
  type tx_mac_error_info_t is record
    is_error   : boolean;
    error_type : tx_mac_error_t;
  end record tx_mac_error_info_t;

  -- Composite type for MAC frame bit info
  type mac_frame_bit_t is record
    polarity : polarity_t;
    bit_name : mac_frame_bit_name_t;
  end record mac_frame_bit_t;

  -- TX monitoring info (unified monitoring function result)
  type observed_mac_frame_bit_info_t is record
    event_type        : tx_mac_monitor_event_t;
    transfer_status   : transfer_status_t;
    expected_bit      : mac_frame_bit_t;
    observed_polarity : polarity_t;
  end record observed_mac_frame_bit_info_t;

  -- Transmitted bits FIFO
  type transmitted_bits_fifo_t is array (transmitted_bits_fifo_depth_c - 1 downto 0) of mac_frame_bit_t;

  -- =================================================================
  -- Interface types
  -- =================================================================
  type avalon_st_source_t is record
    data  : byte_t;
    valid : std_logic;
    sop   : std_logic;
    eop   : std_logic;
  end record avalon_st_source_t;

  type avalon_st_sink_t is record
    ready : std_logic;
  end record avalon_st_sink_t;

  type tx_mac_ser_to_fsm_if_t is record
    data       : polarity_t;        -- CAN polarity (MAC domain)
    valid      : std_logic;         -- Data valid signal
    frame_info : llc_frame_info_t;  -- Frame configuration from LLC
  end record tx_mac_ser_to_fsm_if_t;

  type tx_mac_fsm_to_ser_if_t is record
    transfer_status  : transfer_status_t;
    tx_mac_fsm_state : tx_mac_fsm_state_t;
    ready            : std_logic;
  end record tx_mac_fsm_to_ser_if_t;

  type llc_to_mac_if_t is record
    avalon_st_source : avalon_st_source_t;
  end record llc_to_mac_if_t;

  type mac_to_llc_if_t is record
    avalon_st_sink  : avalon_st_sink_t;
    transfer_status : transfer_status_t;
  end record mac_to_llc_if_t;

  -- MAC to PCS (Physical Coding Sublayer) interface
  type mac_to_pcs_if_t is record
    frame_bit : mac_frame_bit_t; -- Bit with name/polarity for delay calculation
    valid     : std_logic;       -- Frame bit data is valid
    ready     : std_logic;       -- PCS ready to accept next bit
  end record mac_to_pcs_if_t;

  -- PCS to MAC interface
  -- PCS drives bus polarity continuously and sends strobes for sample timing
  type pcs_to_mac_if_t is record
    polarity : polarity_t; -- Current bus polarity (continuously driven)
    sp       : std_logic;  -- Sample Point strobe (pulse: MAC samples polarity at SP)
    ssp      : std_logic;  -- Secondary Sample Point strobe (pulse: MAC samples polarity at SSP)
  end record pcs_to_mac_if_t;

  type mac_fsm_to_bs_fd_if_t is record
    data       : std_logic;
    data_valid : std_logic;
  end record mac_fsm_to_bs_fd_if_t;

  type bs_fd_to_mac_fsm_if_t is record
    stuff_bit       : std_logic;
    stuff_bit_valid : std_logic;
    sbc             : std_logic_vector(3 downto 0);
  end record bs_fd_to_mac_fsm_if_t;

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
  -- Encoding
  -- =================================================================
  -- Ensure one_hot encoding of all FSM state types
  attribute fsm_encoding : string;
  attribute fsm_encoding of can_format_t       : type is "one_hot";
  attribute fsm_encoding of can_node_type_t    : type is "one_hot";
  attribute fsm_encoding of frame_type_t       : type is "one_hot";
  attribute fsm_encoding of tx_mac_fsm_state_t : type is "one_hot";
  attribute fsm_encoding of tx_mac_ser_state_t : type is "one_hot";
  attribute fsm_encoding of tx_mac_error_t     : type is "one_hot";
  attribute fsm_encoding of error_flag_t       : type is "one_hot";
  attribute fsm_encoding of transfer_status_t  : type is "one_hot";

  -- =================================================================
  -- CAN frame formats (ISO 11898-1: Figure 2)
  -- =================================================================
  -- Common bits
  constant active_error_flag_bit_c  : mac_frame_bit_t := (dominant, active_error_flag_bit);
  constant passive_error_flag_bit_c : mac_frame_bit_t := (recessive, passive_error_flag_bit);
  constant eof_bit_c                : mac_frame_bit_t := (recessive, eof_bit);
  constant sof_bit_c                : mac_frame_bit_t := (dominant, sof_bit);
  constant tx_ack_bit_c             : mac_frame_bit_t := (recessive, ack_bit);
  constant ack_delimiter_bit_c      : mac_frame_bit_t := (recessive, ack_delimiter_bit);
  constant crc_delimiter_bit_c      : mac_frame_bit_t := (recessive, crc_delimiter_bit);

  -- CAN Classic base frame format
  constant cb_base_id_start_c : bit_t := (sof_c + 1, dominant);
  constant cb_base_id_stop_c  : bit_t := (cb_base_id_start_c.position + base_id_width_c - 1, unknown);
  constant cb_rtr_c           : bit_t := (cb_base_id_stop_c.position + 1, unknown);
  constant cb_ide_c           : bit_t := (cb_rtr_c.position + 1, dominant);
  constant cb_r0_c            : bit_t := (cb_ide_c.position + 1, dominant);
  constant cb_dlc_start_c     : bit_t := (cb_r0_c.position + 1, unknown);
  constant cb_dlc_stop_c      : bit_t := (cb_dlc_start_c.position + dlc_field_width_c - 1, unknown);
  constant cb_data_start_c    : bit_t := (cb_dlc_stop_c.position + 1, unknown);

  -- CAN Classic extended frame format
  constant ce_base_id_start_c     : bit_t := (sof_c + 1, unknown);
  constant ce_base_id_stop_c      : bit_t := (ce_base_id_start_c.position + base_id_width_c - 1, unknown);
  constant ce_srr_c               : bit_t := (ce_base_id_stop_c.position + 1, recessive);
  constant ce_ide_c               : bit_t := (ce_srr_c.position + 1, recessive);
  constant ce_extended_id_start_c : bit_t := (ce_ide_c.position + 1, unknown);
  constant ce_extended_id_stop_c  : bit_t := (ce_extended_id_start_c.position + extended_id_width_c - 1, unknown);
  constant ce_rtr_c               : bit_t := (ce_extended_id_stop_c.position + 1, unknown);
  constant ce_r1_c                : bit_t := (ce_rtr_c.position + 1, dominant);
  constant ce_r0_c                : bit_t := (ce_r1_c.position + 1, dominant);
  constant ce_dlc_start_c         : bit_t := (ce_r0_c.position + 1, unknown);
  constant ce_dlc_stop_c          : bit_t := (ce_dlc_start_c.position + dlc_field_width_c - 1, unknown);
  constant ce_data_start_c        : bit_t := (ce_dlc_stop_c.position + 1, unknown);

  -- FD base frame format
  constant fd_base_id_start_c : bit_t := (sof_c + 1, unknown);
  constant fd_base_id_stop_c  : bit_t := (fd_base_id_start_c.position + base_id_width_c - 1, unknown);
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
  constant fe_base_id_stop_c      : bit_t := (fe_base_id_start_c.position + base_id_width_c - 1, unknown);
  constant fe_srr_c               : bit_t := (fe_base_id_stop_c.position + 1, recessive);
  constant fe_ide_c               : bit_t := (fe_srr_c.position + 1, recessive);
  constant fe_extended_id_start_c : bit_t := (fe_ide_c.position + 1, unknown);
  constant fe_extended_id_stop_c  : bit_t := (fe_extended_id_start_c.position + extended_id_width_c - 1, unknown);
  constant fe_rrs_c               : bit_t := (fe_extended_id_stop_c.position + 1, dominant);
  constant fe_fdf_c               : bit_t := (fe_rrs_c.position + 1, recessive);
  constant fe_res_c               : bit_t := (fe_fdf_c.position + 1, dominant);
  constant fe_brs_c               : bit_t := (fe_res_c.position + 1, unknown);
  constant fe_esi_c               : bit_t := (fe_brs_c.position + 1, unknown);
  constant fe_dlc_start_c         : bit_t := (fe_esi_c.position + 1, unknown);
  constant fe_dlc_stop_c          : bit_t := (fe_dlc_start_c.position + dlc_field_width_c - 1, unknown);
  constant fe_data_start_c        : bit_t := (fe_dlc_stop_c.position + 1, unknown);

  -- LLC frame config bytes (byte 0 and byte 1) format
  constant llc_frame_config_byte_0_format_start : integer := byte_width_c - 1;
  constant llc_frame_config_byte_0_format_end   : integer := llc_frame_config_byte_0_format_start - 2;
  constant llc_frame_config_byte_0_ftyp         : integer := llc_frame_config_byte_0_format_start - 3;
  constant llc_frame_config_byte_0_esi          : integer := llc_frame_config_byte_0_format_start - 4;
  constant llc_frame_config_byte_0_brs          : integer := llc_frame_config_byte_0_format_start - 5;
  constant llc_frame_config_byte_1_dlc_start    : integer := byte_width_c - 1;
  constant llc_frame_config_byte_1_dlc_end      : integer := llc_frame_config_byte_1_dlc_start - 3;

  -- =================================================================
  -- Function and procedure declarations
  -- =================================================================
  -- Function calculates the parity bit for a std_logic_vector
  function calc_parity (
    v : std_logic_vector
  ) return std_logic;

  -- Function Gray encodes a std_logic_vector
  function to_gray (
    v : std_logic_vector
  ) return std_logic_vector;

  -- Convert std_logic bit value to polarity enumeration
  function bit_to_polarity (
    bit_val : std_logic
  ) return polarity_t;

  -- Function converts the LLC frame configuration bytes (byte 0 to 1) to llc_frame_info_t
  function get_frame_info (
    config_byte_0 : byte_t;
    config_byte_1 : byte_t
  ) return llc_frame_info_t;

  -- Function calculates the next bit to be transmitted
  function get_next_mac_frame_bit (
    bit_count    : position_t;
    -- From tx_mac_ser
    mac_ser_to_fsm : tx_mac_ser_to_fsm_if_t;
    previous_polarity : polarity_t;
    -- From bit stuffer
    stuff_bit_polarity : polarity_t;
    stuff_bit_valid : boolean;
    sbc : sbc_t;
    -- From CRC module
    crc : crc_vector_t
  ) return mac_frame_bit_t;

  -- Function monitors transmitted bits for errors, ACK issues, and arbitration loss
  function get_observed_mac_frame_bit_info (
    delay : integer range 0 to transmitted_bits_fifo_depth_c - 1;
    transmitted_bits_fifo : transmitted_bits_fifo_t;
    monitored_bit_polarity : polarity_t;
    frame_info : llc_frame_info_t
  ) return observed_mac_frame_bit_info_t;

  -- Initialize FIFO to empty state (all bits unknown)
  function fifo_init return transmitted_bits_fifo_t;

  -- Push a new bit into FIFO (shifts all existing bits, new bit enters at position 0)
  procedure fifo_push (
    fifo : inout transmitted_bits_fifo_t;
    bit  : in    mac_frame_bit_t
  );

  -- Determine if Transmitter Delay Compensation should be used (ISO 11898-1: 7.3.4)
  function should_use_tdc (
    system_clock_freq : integer;
    prescalar : integer;
    sync_seg : integer;
    prop_seg_fd : integer;
    phase_seg1_fd : integer;
    phase_seg2_fd : integer;
    pcs_to_pma_propagation_delay_ns : integer
  ) return boolean;

end package can_pkg;

-- =================================================================
-- PACKAGE BODY
-- =================================================================

package body can_pkg is

  function get_observed_mac_frame_bit_info (
    delay : integer range 0 to transmitted_bits_fifo_depth_c - 1;
    transmitted_bits_fifo : transmitted_bits_fifo_t;
    monitored_bit_polarity : polarity_t;
    frame_info : llc_frame_info_t
  ) return observed_mac_frame_bit_info_t is

    variable result : observed_mac_frame_bit_info_t;
    variable transmitted_bit : mac_frame_bit_t;
    variable is_arbitration_bit : boolean;

  begin

    -- Default: no event detected, transmission ongoing
    result.event_type      := none;
    result.transfer_status := ongoing;

    -- Get the transmitted bit at the specified delay from FIFO
    result.expected_bit := transmitted_bits_fifo(delay);
    -- Get monitored bit polarity
    result.observed_polarity := monitored_bit_polarity;

    -- Check for ACK bit (ISO 11898-1: 6.6.21.2)
    if (transmitted_bit.bit_name = ack_bit) then
      if (monitored_bit_polarity = recessive) then
        result.event_type      := ack_error;
        result.transfer_status := disturbed;
      else
        result.event_type      := ack_detected;
        result.transfer_status := transmitted;
      end if;
      return result;
    end if;

    -- Return if no polarity mismatch
    if (transmitted_bit.polarity = monitored_bit_polarity) then
      return result;
    else
      -- Polarity mismatch detected: default to disturbed status
      result.transfer_status := disturbed;
    end if;

    -- Determine if this bit is in the arbitration phase (ISO 11898-1: Figure 2)
    case frame_info.format is
      when cc_basic =>
        is_arbitration_bit := (transmitted_bit.bit_name = base_id_bit or
                               transmitted_bit.bit_name = rtr_bit);
      when cc_extended =>
        is_arbitration_bit := (transmitted_bit.bit_name = base_id_bit or
                               transmitted_bit.bit_name = srr_bit or
                               transmitted_bit.bit_name = ide_bit or
                               transmitted_bit.bit_name = extended_id_bit or
                               transmitted_bit.bit_name = rtr_bit);
      when fd_basic =>
        is_arbitration_bit := (transmitted_bit.bit_name = base_id_bit or
                               transmitted_bit.bit_name = rrs_bit);
      when fd_extended =>
        is_arbitration_bit := (transmitted_bit.bit_name = base_id_bit or
                               transmitted_bit.bit_name = srr_bit or
                               transmitted_bit.bit_name = ide_bit or
                               transmitted_bit.bit_name = extended_id_bit);
      when others =>
        is_arbitration_bit := false;
    end case;

    -- Determine event type based on context and mismatch (ISO 11898-1 6.6.21.2)
    if (is_arbitration_bit) then
      if (transmitted_bit.polarity = dominant) then
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

  -- Convert std_logic bit value to polarity enumeration
  function bit_to_polarity (
    bit_val : std_logic
  ) return polarity_t is

    variable result_v : polarity_t;

  begin

    if (bit_val = dominant_bit_c) then
      result_v := dominant;
    else
      result_v := recessive;
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

  function get_next_mac_frame_bit (
    bit_count    : position_t;
    mac_ser_to_fsm : tx_mac_ser_to_fsm_if_t;
    previous_polarity : polarity_t;
    -- From bit stuffer
    stuff_bit_polarity : polarity_t;
    stuff_bit_valid : boolean;
    sbc : sbc_t;
    crc : crc_vector_t
  ) return mac_frame_bit_t is

    -- Result
    variable result_v : mac_frame_bit_t;

    -- Data field calculations
    variable data_start_v  : position_t;
    variable data_stop_v   : position_t;
    variable data_length_v : integer range 0 to max_data_bytes_c;
    variable data_bits_v   : integer range 0 to max_data_bytes_c * byte_width_c;

    -- CRC field calculations
    variable crc_start_v             : position_t;
    variable crc_length_v            : integer range 0 to crc_21_length_c;
    variable crc_field_length_v      : integer range 0 to 2 * crc_21_length_c;
    variable position_in_crc_field_v : position_t;
    variable fixed_stuff_count_v     : integer;
    variable sbc_start_v             : position_t;
    variable sbc_stop_v              : position_t;

    -- ID field positions
    variable base_id_start_v     : position_t;
    variable base_id_stop_v      : position_t;
    variable extended_id_start_v : position_t;
    variable extended_id_stop_v  : position_t;

    -- DLC field
    variable dlc_vector_v    : std_logic_vector(dlc_field_width_c - 1 downto 0);
    variable dlc_start_v     : position_t;
    variable dlc_bit_index_v : position_t;

    -- Other field positions
    variable crc_delim_v : position_t;
    variable ack_v       : position_t;
    variable ack_delim_v : position_t;
    variable eof_start_v : position_t;

    -- Format-specific bit positions (bit_t type includes position and polarity)
    variable srr_v : bit_t;
    variable ide_v : bit_t;
    variable rtr_v : bit_t;
    variable rrs_v : bit_t;
    variable fdf_v : bit_t;
    variable res_v : bit_t;
    variable r0_v  : bit_t;
    variable r1_v  : bit_t;
    variable brs_v : bit_t;
    variable esi_v : bit_t;

    -- Frame-dependent polarities
    variable rtr_polarity_v : polarity_t;
    variable brs_polarity_v : polarity_t;
    variable esi_polarity_v : polarity_t;

    -- Format flag
    variable is_fd_v : boolean;

  begin

    result_v := (polarity => unknown, bit_name => unknown);

    -- Priority 1: Check for valid stuff bit from bit stuffer
    if (stuff_bit_valid) then
      result_v := (polarity => stuff_bit_polarity, bit_name => stuff_bit);
      return result_v;
    end if;

    dlc_vector_v := std_logic_vector(to_unsigned(mac_ser_to_fsm.frame_info.dlc, 4));
    -- Note: For remote frames, data_bits_v = 0, so data field is skipped
    data_length_v := dlc_to_data_length(mac_ser_to_fsm.frame_info.dlc, mac_ser_to_fsm.frame_info.format);

    -- Determine frame-dependent polarities
    rtr_polarity_v := recessive when mac_ser_to_fsm.frame_info.ftyp = remote_frame else dominant;
    brs_polarity_v := recessive when mac_ser_to_fsm.frame_info.brs_enable else dominant;
    esi_polarity_v := recessive when mac_ser_to_fsm.frame_info.esi_enable else dominant;

    -- =================================================================
    -- Calculate dynamic positions based on data length and format
    -- =================================================================
    case mac_ser_to_fsm.frame_info.format is
      when cc_basic =>
        data_start_v        := cb_data_start_c.position;
        dlc_start_v         := cb_dlc_start_c.position;
        base_id_start_v     := cb_base_id_start_c.position;
        base_id_stop_v      := cb_base_id_start_c.position + base_id_width_c - 1;
        extended_id_start_v := 0;
        extended_id_stop_v  := 0;
        rtr_v               := (position => cb_rtr_c.position, polarity => rtr_polarity_v);
        ide_v               := cb_ide_c;
        r0_v                := cb_r0_c;
        -- Not used in CC basic format
        srr_v := unknown_bit_c;
        rrs_v := unknown_bit_c;
        fdf_v := unknown_bit_c;
        res_v := unknown_bit_c;
        r1_v  := unknown_bit_c;
        brs_v := unknown_bit_c;
        esi_v := unknown_bit_c;

      when cc_extended =>
        data_start_v        := ce_data_start_c.position;
        dlc_start_v         := ce_dlc_start_c.position;
        base_id_start_v     := ce_base_id_start_c.position;
        base_id_stop_v      := ce_base_id_start_c.position + base_id_width_c - 1;
        extended_id_start_v := ce_extended_id_start_c.position;
        extended_id_stop_v  := ce_extended_id_start_c.position + extended_id_width_c - 1;
        srr_v               := ce_srr_c;
        ide_v               := ce_ide_c;
        rtr_v               := (position => ce_rtr_c.position, polarity => rtr_polarity_v);
        r1_v                := ce_r1_c;
        r0_v                := ce_r0_c;
        -- Not used in CC extended format
        rrs_v := unknown_bit_c;
        fdf_v := unknown_bit_c;
        res_v := unknown_bit_c;
        brs_v := unknown_bit_c;
        esi_v := unknown_bit_c;

      when fd_basic =>
        data_start_v        := fb_data_start_c.position;
        dlc_start_v         := fb_dlc_start_c.position;
        base_id_start_v     := fd_base_id_start_c.position;
        base_id_stop_v      := fd_base_id_start_c.position + base_id_width_c - 1;
        extended_id_start_v := 0;
        extended_id_stop_v  := 0;
        rrs_v               := fb_rrs_c;
        ide_v               := fb_ide_c;
        fdf_v               := fb_fdf_c;
        res_v               := fb_res_c;
        brs_v               := (position => fb_brs_c.position, polarity => brs_polarity_v);
        esi_v               := (position => fb_esi_c.position, polarity => esi_polarity_v);
        -- Not used in FD basic format
        srr_v := unknown_bit_c;
        rtr_v := unknown_bit_c;
        r0_v  := unknown_bit_c;
        r1_v  := unknown_bit_c;

      when fd_extended =>
        data_start_v        := fe_data_start_c.position;
        dlc_start_v         := fe_dlc_start_c.position;
        base_id_start_v     := fe_base_id_start_c.position;
        base_id_stop_v      := fe_base_id_start_c.position + base_id_width_c - 1;
        extended_id_start_v := fe_extended_id_start_c.position;
        extended_id_stop_v  := fe_extended_id_start_c.position + extended_id_width_c - 1;
        srr_v               := fe_srr_c;
        ide_v               := fe_ide_c;
        rrs_v               := fe_rrs_c;
        fdf_v               := fe_fdf_c;
        res_v               := fe_res_c;
        brs_v               := (position => fe_brs_c.position, polarity => brs_polarity_v);
        esi_v               := (position => fe_esi_c.position, polarity => esi_polarity_v);
        -- Not used in FD extended format
        rtr_v := unknown_bit_c;
        r0_v  := unknown_bit_c;
        r1_v  := unknown_bit_c;

      when unknown =>
        data_start_v        := 0;
        dlc_start_v         := 0;
        base_id_start_v     := 0;
        base_id_stop_v      := 0;
        extended_id_start_v := 0;
        extended_id_stop_v  := 0;
        srr_v               := unknown_bit_c;
        ide_v               := unknown_bit_c;
        rtr_v               := unknown_bit_c;
        rrs_v               := unknown_bit_c;
        fdf_v               := unknown_bit_c;
        res_v               := unknown_bit_c;
        r0_v                := unknown_bit_c;
        r1_v                := unknown_bit_c;
        brs_v               := unknown_bit_c;
        esi_v               := unknown_bit_c;
    end case;

    data_bits_v := data_length_v * byte_width_c;
    data_stop_v := data_start_v + data_bits_v - 1;
    is_fd_v     := is_fd_format(mac_ser_to_fsm.frame_info.format);

    -- Calculate CRC field and delimiter position
    crc_start_v  := data_stop_v + 1;
    crc_length_v := get_crc_length(mac_ser_to_fsm.frame_info.format, data_length_v);

    -- CAN FD has SBC field after data, CAN Classic goes directly to CRC
    if (is_fd_v) then
      sbc_start_v         := crc_start_v;
      sbc_stop_v          := sbc_start_v + sbc_field_width_c - 1;
      crc_start_v         := sbc_stop_v + 1;
      fixed_stuff_count_v := get_fixed_stuff_bit_count(sbc_field_width_c + crc_length_v);
      crc_field_length_v  := crc_length_v + fixed_stuff_count_v;
    else
      crc_field_length_v := crc_length_v;
    end if;

    crc_delim_v := crc_start_v + crc_field_length_v;
    ack_v       := crc_delim_v + 1;
    ack_delim_v := ack_v + 1;
    eof_start_v := ack_delim_v + 1;

    -- =================================================================
    -- Determine bit type based on position and format using constants
    -- =================================================================
    if (bit_count = sof_c) then
      result_v := sof_bit_c;

    -- Base arbitration field
    elsif (bit_count >= base_id_start_v and bit_count < base_id_stop_v + 1) then
      result_v.bit_name := base_id_bit;
      result_v.polarity := mac_ser_to_fsm.data;
    elsif (rtr_v.polarity /= unknown and bit_count = rtr_v.position) then
      result_v := (bit_name => rtr_bit, polarity => rtr_v.polarity);
    elsif (rrs_v.polarity /= unknown and bit_count = rrs_v.position) then
      result_v := (bit_name => rrs_bit, polarity => rrs_v.polarity);

    -- Extended arbitration field
    elsif (srr_v.polarity /= unknown and bit_count = srr_v.position) then
      result_v := (bit_name => srr_bit, polarity => srr_v.polarity);
    elsif (ide_v.polarity /= unknown and bit_count = ide_v.position) then
      result_v := (bit_name => ide_bit, polarity => ide_v.polarity);
    elsif (extended_id_start_v > 0 and bit_count >= extended_id_start_v and bit_count < extended_id_stop_v + 1) then
      result_v.bit_name := extended_id_bit;
      result_v.polarity := mac_ser_to_fsm.data;

    -- Control field
    elsif (r1_v.polarity /= unknown and bit_count = r1_v.position) then
      result_v := (bit_name => r1_bit, polarity => r1_v.polarity);
    elsif (r0_v.polarity /= unknown and bit_count = r0_v.position) then
      result_v := (bit_name => r0_bit, polarity => r0_v.polarity);
    elsif (fdf_v.polarity /= unknown and bit_count = fdf_v.position) then
      result_v := (bit_name => fdf_bit, polarity => fdf_v.polarity);
    elsif (res_v.polarity /= unknown and bit_count = res_v.position) then
      result_v := (bit_name => res_bit, polarity => res_v.polarity);
    elsif (brs_v.polarity /= unknown and bit_count = brs_v.position) then
      result_v := (bit_name => brs_bit, polarity => brs_v.polarity);
    elsif (esi_v.polarity /= unknown and bit_count = esi_v.position) then
      result_v := (bit_name => esi_bit, polarity => esi_v.polarity);
    elsif (bit_count >= dlc_start_v and bit_count < dlc_start_v + dlc_field_width_c) then
      result_v.bit_name := dlc_bit;
      dlc_bit_index_v   := dlc_vector_v'left - (bit_count - dlc_start_v);
      result_v.polarity := bit_to_polarity(dlc_vector_v(dlc_bit_index_v));

    -- Data field
    elsif (bit_count >= data_start_v and bit_count < data_start_v + data_bits_v) then
      result_v.bit_name := data_bit;
      result_v.polarity := mac_ser_to_fsm.data;

    -- CRC field
    elsif (bit_count >= crc_start_v and bit_count < crc_delim_v) then
      -- Check for fixed stuff bits in CAN FD (highest priority in CRC field)
      if (is_fd_v) then
        position_in_crc_field_v := bit_count - crc_start_v;
        if is_fixed_stuff_bit_position(position_in_crc_field_v) then
          result_v.bit_name := fixed_stuff_bit;
          result_v.polarity := recessive when previous_polarity = dominant else dominant;
          return result_v;
        end if;
      end if;
      -- If not a fixed stuff bit, extract CRC or SBC bit
      if (is_fd_v and bit_count >= sbc_start_v and bit_count < sbc_start_v + sbc_field_width_c) then
        result_v.bit_name := sbs_bit;
        result_v.polarity := bit_to_polarity(sbc(sbc'left - (bit_count - sbc_start_v)));
      else
        result_v.bit_name := crc_bit;
        result_v.polarity := bit_to_polarity(crc(crc'left - (bit_count - crc_start_v)));
      end if;
    elsif (bit_count = crc_delim_v) then
      result_v := crc_delimiter_bit_c;

    -- ACK field
    elsif (bit_count = ack_v) then
      result_v := tx_ack_bit_c;
    elsif (bit_count = ack_delim_v) then
      result_v := ack_delimiter_bit_c;

    -- EOF field
    elsif (bit_count >= eof_start_v and bit_count < eof_start_v + eof_field_width_c) then
      result_v := eof_bit_c;

    end if;

    return result_v;

  end function get_next_mac_frame_bit;

  function fifo_init return transmitted_bits_fifo_t is

    variable fifo : transmitted_bits_fifo_t;

  begin

    fifo := (others => (polarity => unknown, bit_name => unknown));
    return fifo;

  end function fifo_init;

  procedure fifo_push (
    fifo : inout transmitted_bits_fifo_t;
    bit  : in    mac_frame_bit_t
  ) is
  begin

    -- Shift all bits left
    for i in fifo'high downto 1 loop
      fifo(i) := fifo(i - 1);
    end loop;

    fifo(0) := bit;

  end procedure fifo_push;

  function should_use_tdc (
    system_clock_freq : integer;
    prescalar : integer;
    sync_seg : integer;
    prop_seg_fd : integer;
    phase_seg1_fd : integer;
    phase_seg2_fd : integer;
    pcs_to_pma_propagation_delay_ns : integer
  ) return boolean is

    variable bit_time_tq   : integer;
    variable early_bits_tq : integer;
    variable tq_period_ns  : integer;

  begin

    -- Calculate time quantum counts (in clock periods)
    bit_time_tq   := (sync_seg + prop_seg_fd + phase_seg1_fd + phase_seg2_fd) * prescalar;
    early_bits_tq := (sync_seg + prop_seg_fd + phase_seg1_fd) * prescalar;

    -- Calculate nanoseconds per time quantum: tq_ns = 1_000_000_000 / system_clock_freq
    tq_period_ns := 1_000_000_000 / system_clock_freq;

    -- Condition 1: SHOULD use TDC if bit_time <= tdc_bit_time_max_c (ISO 11898-1: 7.3.4)
    if (bit_time_tq * tq_period_ns <= tdc_bit_time_max_c) then
      return true;
    end if;

    -- Condition 2: NEEDS use TDC if early phase < pcs_to_pma_propagation_delay_ns
    if (early_bits_tq * tq_period_ns < pcs_to_pma_propagation_delay_ns) then
      return true;
    end if;

    return false;

  end function should_use_tdc;

end package body can_pkg;
