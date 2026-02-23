--------------------------------------------------------------------------------
-- Title      : CAN Bus Types and Constants
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : can_types_pkg.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Centralized type and constant definitions for the CAN/CAN-FD
--              transmitter design per ISO 11898-1:2015.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

package can_types_pkg is

  ---------------------------------------------------------------------------
  -- Protocol Constants
  ---------------------------------------------------------------------------
  constant dominant_bit_c    : std_logic                     := '0';
  constant recessive_bit_c   : std_logic                     := '1';
  constant sof_c             : integer                       := 0;
  constant crc_15_length_c   : integer                       := 15;
  constant crc_17_length_c   : integer                       := 17;
  constant crc_21_length_c   : integer                       := 21;
  constant crc_poly_15_vec_c : std_logic_vector(15 downto 0) := x"C599";
  constant crc_poly_17_vec_c : std_logic_vector(19 downto 0) := x"3685B";
  constant crc_poly_21_vec_c : std_logic_vector(23 downto 0) := x"302899";
  constant dlc_field_width_c : integer                       := 4;
  constant sbc_field_width_c : integer                       := 4;
  constant byte_width_c      : integer                       := 8;

  -- Max frame: FD extended, DLC 15 → eof_stop = 593. Rounded up with margin.
  constant max_mac_frame_length_c       : integer := 640;
  subtype  bit_count_t is integer range 0 to max_mac_frame_length_c;
  constant base_id_width_c              : integer := 11;
  constant extended_id_width_c          : integer := 18;
  constant eof_field_width_c            : integer := 7;
  constant error_flag_width_c           : integer := 6;
  constant error_delimiter_width_c      : integer := 8;
  constant bus_idle_condition_width_c   : integer := 11; -- ISO 11898-1: 3.34
  constant intermission_width_c         : integer := 3;  -- ISO 11898-1: 6.6.7.2
  constant suspend_transmission_width_c : integer := 8;  -- ISO 11898-1: 6.6.7.4
  -- Circular TX history buffer depth used by MAC/PCS delay comparison logic.
  -- Sized for current PCS defaults and guarded by runtime assertions in tx_pcs.
  constant transmitted_bits_fifo_depth_c : integer := 32;
  constant dlc_max_decimal_value         : integer := 15;
  constant max_data_bytes_c              : integer := 64;
  constant tdc_bit_time_max_c            : integer := 1000; -- ISO 11898-1: 7.3.4

  ---------------------------------------------------------------------------
  -- Bit Timing Configuration (ISO 11898-1 Table 13)
  ---------------------------------------------------------------------------

  -- Default reference clock used by timing helper calculations and tests.
  constant system_clock_freq_c : integer := 100_000_000; -- 100 MHz
  -- ISO 11898-1:2015 Section 7.3.3 Table 13
  subtype prescalar is integer range 1 to 32;
  subtype sync_seg is integer range 1 to 1;
  subtype nom_prop_seg is integer range 1 to 384;
  subtype data_prop_seg is integer range 0 to 128;
  subtype phase_seg1 is integer range 1 to 128;
  subtype phase_seg2 is integer range 2 to 128;
  subtype sjw is integer range 1 to 128;
  -- TDC configuration: settling margin added to measured delay (ISO §7.3.4).
  -- Must not exceed data_bit_time to avoid FIFO index pointing at the wrong bit.
  subtype  ssp_offset is integer range 1 to 160;
  constant max_transmitter_delay_c : integer := 255; -- ISO 11898-1: 7.3.4

  ---------------------------------------------------------------------------
  -- Basic Enumerations and Records
  ---------------------------------------------------------------------------
  type mac_frame_bit_name_t is (
    -- Flag bits
    active_error_flag_bit,
    passive_error_flag_bit,
    overload_flag_bit,
    -- Inter-frame spacing bits
    intermission_bit,
    suspend_transmission_bit,
    idle_bit,
    -- CC bit types
    stuff_bit,
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
    fixed_stuff_bit,
    rrs_bit,
    fdf_bit,
    res_bit,
    brs_bit,
    esi_bit,
    sbs_bit,
    error_delimiter_bit,
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

  ---------------------------------------------------------------------------
  -- FSM State Types
  ---------------------------------------------------------------------------

  -- MAC layer TX state type
  type tx_mac_fsm_state_t is (
    bus_reintegration,
    bus_idle,
    intermission,
    suspend_transmission, -- Error-passive transmitter waits 8 bit times (ISO 11898-1)
    transmitting_frame,
    transmitting_error_flag,
    transmitting_overload_flag
  );

  -- tx_mac_ser states
  type tx_mac_ser_state_t is (
    load_config_byte_0,
    load_config_byte_1,
    load_llc_frame_byte,
    shift_out_bits
  );

  -- PCS layer FSM states (ISO 7.3.4 TDC mechanism)
  type tx_pcs_fsm_state_t is (
    idle,                 -- Waiting for first bit from MAC
    measuring_delay,      -- Counting TX→RX propagation delay
    transmitting_nominal, -- Transmitting at nominal bit rate (arbitration phase)
    transmitting_data     -- Transmitting at data bit rate (FD data phase with TDC)
  );

  -- Sample strobe type indicator (ISO 11898-1:2024 7.3.4)
  -- Distinguishes between primary and secondary sample points for TDC error handling
  type strobe_type_t is (
    sp_strobe, -- Primary Sample Point (used in arbitration phase and non-TDC data)
    ssp_strobe -- Secondary Sample Point (used in TDC-enabled data phase, ISO 7.3.4)
  );

  ---------------------------------------------------------------------------
  -- Status and Event Types
  ---------------------------------------------------------------------------

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

  constant reset_mac_frame_bit_c   : mac_frame_bit_t := (polarity => recessive, bit_name => unknown);
  constant unknown_mac_frame_bit_c : mac_frame_bit_t := (polarity => unknown, bit_name => unknown);

  -- TX monitoring info (unified monitoring function result)
  type observed_mac_frame_bit_info_t is record
    event_type        : tx_mac_monitor_event_t;
    transfer_status   : transfer_status_t;
    expected_bit      : mac_frame_bit_t;
    observed_polarity : polarity_t;
  end record observed_mac_frame_bit_info_t;

  constant reset_observed_mac_frame_bit_info_c : observed_mac_frame_bit_info_t :=
  (
    event_type        => none,
    transfer_status   => ongoing,
    expected_bit      => reset_mac_frame_bit_c,
    observed_polarity => recessive
  );

  -- Transmitted bits FIFO (circular buffer)
  type transmitted_bits_fifo_t is array (transmitted_bits_fifo_depth_c - 1 downto 0) of mac_frame_bit_t;

  subtype fifo_write_ptr_t is integer range 0 to transmitted_bits_fifo_depth_c - 1;

  -- Frame-specific cached parameters (calculated once per frame)
  -- Defined here so interfaces can use it
  type frame_params_t is record
    -- Frame type and control flags
    format          : can_format_t;
    dlc_vector      : std_logic_vector(dlc_field_width_c - 1 downto 0);
    is_fd_frame     : boolean;
    is_remote_frame : boolean;
    has_brs         : boolean;
    esi_enable      : boolean;

    -- Field boundaries (for frame layout)
    data_start        : position_t;
    data_stop         : position_t;
    dlc_start         : position_t;
    dlc_stop          : position_t;
    base_id_start     : position_t;
    base_id_stop      : position_t;
    extended_id_start : position_t;
    extended_id_stop  : position_t;

    -- CRC and SBC fields
    crc_start     : position_t;
    crc_stop      : position_t;
    crc_delimiter : position_t;
    sbc_start     : position_t;
    sbc_stop      : position_t;

    -- ACK and EOF fields
    ack_slot      : position_t;
    ack_delimiter : position_t;
    eof_start     : position_t;
    eof_stop      : position_t;

    -- CRC configuration
    crc_poly_select : std_logic_vector(1 downto 0);

    -- Format-specific bit positions (with polarities resolved for BRS/ESI)
    srr_bit : bit_t;
    ide_bit : bit_t;
    rtr_bit : bit_t;
    rrs_bit : bit_t;
    fdf_bit : bit_t;
    res_bit : bit_t;
    r0_bit  : bit_t;
    r1_bit  : bit_t;
    brs_bit : bit_t; -- Polarity resolved based on has_brs flag
    esi_bit : bit_t; -- Polarity resolved based on esi_enable flag
  end record frame_params_t;

  ---------------------------------------------------------------------------
  -- Interface Types and Reset Constants
  ---------------------------------------------------------------------------

  type avalon_st_source_t is record
    data  : byte_t;
    valid : std_logic;
    sop   : std_logic;
    eop   : std_logic;
  end record avalon_st_source_t;

  type avalon_st_sink_t is record
    ready : std_logic;
  end record avalon_st_sink_t;

  constant frame_params_reset_c : frame_params_t :=
  (
    format            => unknown,
    dlc_vector        => (others => '0'),
    is_fd_frame       => false,
    is_remote_frame   => false,
    has_brs           => false,
    esi_enable        => false,
    data_start        => 0,
    data_stop         => 0,
    dlc_start         => 0,
    dlc_stop          => 0,
    base_id_start     => 0,
    base_id_stop      => 0,
    extended_id_start => 0,
    extended_id_stop  => 0,
    crc_start         => 0,
    crc_stop          => 0,
    crc_delimiter     => 0,
    sbc_start         => 0,
    sbc_stop          => 0,
    ack_slot          => 0,
    ack_delimiter     => 0,
    eof_start         => 0,
    eof_stop          => 0,
    crc_poly_select   => "00",
    srr_bit           => unknown_bit_c,
    ide_bit           => unknown_bit_c,
    rtr_bit           => unknown_bit_c,
    rrs_bit           => unknown_bit_c,
    fdf_bit           => unknown_bit_c,
    res_bit           => unknown_bit_c,
    r0_bit            => unknown_bit_c,
    r1_bit            => unknown_bit_c,
    brs_bit           => unknown_bit_c,
    esi_bit           => unknown_bit_c
  );

  type tx_mac_ser_to_fsm_if_t is record
    data         : polarity_t;     -- CAN polarity (MAC domain)
    valid        : boolean;        -- Data valid signal
    frame_params : frame_params_t; -- Cached frame parameters (all config info consolidated)
  end record tx_mac_ser_to_fsm_if_t;

  constant tx_mac_ser_to_fsm_if_reset_c : tx_mac_ser_to_fsm_if_t :=
  (
    data         => dominant,
    valid        => false,
    frame_params => frame_params_reset_c
  );

  type tx_mac_fsm_to_ser_if_t is record
    transfer_status : transfer_status_t;
    ready           : boolean;
  end record tx_mac_fsm_to_ser_if_t;

  constant tx_mac_fsm_to_ser_if_reset_c : tx_mac_fsm_to_ser_if_t :=
  (
    transfer_status => ongoing,
    ready           => false
  );

  type llc_to_mac_if_t is record
    avalon_st_source : avalon_st_source_t;
  end record llc_to_mac_if_t;

  type mac_to_llc_if_t is record
    avalon_st_sink  : avalon_st_sink_t;
    transfer_status : transfer_status_t;
  end record mac_to_llc_if_t;

  constant mac_to_llc_if_reset_c : mac_to_llc_if_t :=
  (
    avalon_st_sink  => (ready => '0'),
    transfer_status => ongoing
  );

  -- MAC to PCS (Physical Coding Sublayer) interface
  -- MAC to PCS interface (ISO 11898-1:2024 Section 7.2 PCS Services)
  type mac_to_pcs_if_t is record
    -- PCS_Data.Request service (ISO 7.2.2)
    data  : mac_frame_bit_t;
    valid : boolean; -- true = request PCS to transmit frame_bit
  end record mac_to_pcs_if_t;

  constant mac_to_pcs_if_reset_c : mac_to_pcs_if_t :=
  (
    data  => reset_mac_frame_bit_c,
    valid => false
  );

  -- PCS to MAC interface (ISO 11898-1:2024 Section 7.2 PCS Services)
  -- PCS drives bus polarity continuously and sends strobes for sample timing
  type pcs_to_mac_if_t is record
    -- PCS_Data.Indicate service (ISO 7.2.3)
    bus_polarity : polarity_t; -- Current bus polarity (continuously driven)
    -- Effective sample strobe selected by PCS timing rules:
    -- nominal/arbitration fields use SP; FD data-field monitoring may use SSP.
    sample_strobe : std_logic;
    -- Strobe type indicator for ISO 6.6.21.3.1 TDC error handling
    -- Distinguishes between primary (SP) and secondary (SSP) sample points
    strobe_type : strobe_type_t;

    -- TDC measurement results (ISO 7.3.4)
    -- Effective FIFO index for sample_strobe-aligned comparison.
    -- Nominal/arbitration fields use index 0.
    fifo_index : integer range 0 to transmitted_bits_fifo_depth_c - 1;
  end record pcs_to_mac_if_t;

  constant pcs_to_mac_if_reset_c : pcs_to_mac_if_t :=
  (
    bus_polarity  => recessive,
    sample_strobe => '0',
    strobe_type   => sp_strobe,
    fifo_index    => 0
  );

  type mac_fsm_to_bs_fd_if_t is record
    data  : polarity_t; -- Bit polarity being transmitted
    valid : boolean;    -- Pulse when a new bit is fed to bit stuffer
    start : boolean;    -- Pulse to reinitialize bit stuffer at frame start
  end record mac_fsm_to_bs_fd_if_t;

  constant mac_fsm_to_bs_fd_if_reset_c : mac_fsm_to_bs_fd_if_t :=
  (
    data  => recessive,
    valid => false,
    start => false
  );

  type bs_fd_to_mac_fsm_if_t is record
    data  : polarity_t;                                       -- Polarity of required stuff bit
    valid : boolean;                                          -- true when stuff bit insertion needed (level)
    sbc   : std_logic_vector(sbc_field_width_c - 1 downto 0); -- Gray-coded stuff bit count with parity
  end record bs_fd_to_mac_fsm_if_t;

  constant bs_fd_to_mac_fsm_if_reset_c : bs_fd_to_mac_fsm_if_t :=
  (
    data  => recessive,
    valid => false,
    sbc   => (others => '0')
  );

  type mac_fsm_to_crc_if_t is record
    crc_poly_select : std_logic_vector(1 downto 0);
    valid           : boolean;
    data            : std_logic;
  end record mac_fsm_to_crc_if_t;

  constant mac_fsm_to_crc_if_reset_c : mac_fsm_to_crc_if_t :=
  (
    crc_poly_select => (others => '0'),
    valid           => false,
    data            => '0'
  );

  type crc_to_mac_fsm_if_t is record
    crc : crc_vector_t;
  end record crc_to_mac_fsm_if_t;

  -- MAC to Fault Confinement Entity interface (ISO 11898-1 Table 16/17)
  type mac_to_fce_if_t is record
    transmitting             : boolean; -- Node is currently transmitting
    error                    : boolean; -- Error detected (pulse)
    primary_error            : boolean; -- Dominant bit after error flag (pulse)
    sending_error_flag       : boolean; -- Currently sending error/overload flag
    counters_unchanged       : boolean; -- Exception: don't update counters
    error_delimiter_too_late : boolean; -- 8+ dominant bits after error flag
    successful_transfer      : boolean; -- Frame completed successfully (pulse)
  end record mac_to_fce_if_t;

  constant mac_to_fce_if_reset_c : mac_to_fce_if_t :=
  (
    transmitting             => false,
    error                    => false,
    primary_error            => false,
    sending_error_flag       => false,
    counters_unchanged       => false,
    error_delimiter_too_late => false,
    successful_transfer      => false
  );

  -- Fault Confinement Entity to MAC interface
  type fce_to_mac_if_t is record
    error_passive : boolean; -- true = error-passive node, false = error-active node
  end record fce_to_mac_if_t;

  --------------------------------------------------------------------
  -- Encoding
  --------------------------------------------------------------------
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

  --------------------------------------------------------------------
  -- CAN frame formats (ISO 11898-1: Figure 2)
  --------------------------------------------------------------------
  -- Common bits
  constant active_error_flag_bit_c    : mac_frame_bit_t := (dominant, active_error_flag_bit);
  constant passive_error_flag_bit_c   : mac_frame_bit_t := (recessive, passive_error_flag_bit);
  constant eof_bit_c                  : mac_frame_bit_t := (recessive, eof_bit);
  constant sof_bit_c                  : mac_frame_bit_t := (dominant, sof_bit);
  constant tx_ack_bit_c               : mac_frame_bit_t := (recessive, ack_bit);
  constant ack_delimiter_bit_c        : mac_frame_bit_t := (recessive, ack_delimiter_bit);
  constant crc_delimiter_bit_c        : mac_frame_bit_t := (recessive, crc_delimiter_bit);
  constant error_delimiter_bit_c      : mac_frame_bit_t := (recessive, error_delimiter_bit);
  constant intermission_bit_c         : mac_frame_bit_t := (recessive, intermission_bit);
  constant overload_flag_bit_c        : mac_frame_bit_t := (dominant,  overload_flag_bit);
  constant suspend_transmission_bit_c : mac_frame_bit_t := (recessive, suspend_transmission_bit);
  constant idle_bit_c                 : mac_frame_bit_t := (recessive, idle_bit);

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

  -- LLC frame config bytes (byte 0 and byte 1) format.
  -- byte0[7:5]=format, byte0[4]=ftyp, byte0[3]=esi, byte0[2]=brs
  -- byte1[7:4]=dlc
  constant llc_frame_format_cb_encoding_c       : std_logic_vector(2 downto 0) := "000";
  constant llc_frame_format_ce_encoding_c       : std_logic_vector(2 downto 0) := "100";
  constant llc_frame_format_fb_encoding_c       : std_logic_vector(2 downto 0) := "010";
  constant llc_frame_format_fe_encoding_c       : std_logic_vector(2 downto 0) := "110";
  constant llc_frame_config_byte_0_format_start : integer                      := byte_width_c - 1;
  constant llc_frame_config_byte_0_format_end   : integer                      := llc_frame_config_byte_0_format_start - 2;
  constant llc_frame_config_byte_0_ftyp         : integer                      := llc_frame_config_byte_0_format_end - 1;
  constant llc_frame_config_byte_0_esi          : integer                      := llc_frame_config_byte_0_ftyp - 1;
  constant llc_frame_config_byte_0_brs          : integer                      := llc_frame_config_byte_0_esi - 1;
  constant llc_frame_config_byte_1_dlc_start    : integer                      := byte_width_c - 1;
  constant llc_frame_config_byte_1_dlc_end      : integer                      := llc_frame_config_byte_1_dlc_start - 3;
  -- LLC layer types (ISO 11898-1 Section 6.4)
  --------------------------------------------------------------------

  -- LLC Config Byte 0 structure: [7:5]=Format, [4]=FTYP (RTR), [3]=ESI, [2]=BRS, [1:0]=00
  type llc_config_byte_0_t is record
    format : std_logic_vector(2 downto 0); -- [7:5] Format encoding (cc_basic/extended, fd_basic/extended)
    ftyp   : std_logic;                    -- [4] Frame type: '1'=remote, '0'=data
    esi    : std_logic;                    -- [3] Error state indicator (FD only)
    brs    : std_logic;                    -- [2] Bit rate switch (FD only)
    unused : std_logic_vector(1 downto 0); -- [1:0] Reserved (always '0')
  end record llc_config_byte_0_t;

  -- LLC Config Byte 1 structure: [7:4]=DLC, [3:0]=0000
  type llc_config_byte_1_t is record
    dlc    : std_logic_vector(3 downto 0); -- [7:4] Data length code
    unused : std_logic_vector(3 downto 0); -- [3:0] Reserved (always '0')
  end record llc_config_byte_1_t;

  -- LLC frame as transmitted (matches Avalon-ST byte sequence)
  -- Byte sequence: [config_0, config_1, id[31:24], id[23:16], id[15:8], id[7:0], data[0..63]]
  type llc_frame_t is record
    format   : can_format_t;                                        -- Frame format (for lookups)
    config_0 : llc_config_byte_0_t;                                 -- Config byte 0 (format, FTYP, ESI, BRS)
    config_1 : llc_config_byte_1_t;                                 -- Config byte 1 (DLC)
    id       : std_logic_vector(31 downto 0);                       -- 4-byte packed ID (format-dependent layout)
    data     : std_logic_vector(max_data_bytes_c * 8 - 1 downto 0); -- Up to 64 data bytes
  end record llc_frame_t;

  -- LLC user -> tx_llc interface (Avalon-ST frame stream + control)
  type llc_user_to_llc_if_t is record
    avalon_st_source : avalon_st_source_t;
    abort_request    : std_logic; -- Pulse: abort pending transmission
  end record llc_user_to_llc_if_t;

  -- tx_llc -> LLC user interface (Avalon-ST backpressure + status)
  type llc_to_llc_user_if_t is record
    avalon_st_sink  : avalon_st_sink_t;  -- ready='1' when LLC can accept input bytes
    transfer_status : transfer_status_t; -- Current status
  end record llc_to_llc_user_if_t;

  -- tx_llc FSM states
  type tx_llc_state_t is (
    idle,            -- Waiting for user SOP
    capture_frame,   -- Capturing full user frame into LLC buffer
    send_frame,      -- Streaming buffered frame to MAC
    wait_for_result, -- Waiting for MAC transfer_status
    wait_for_idle    -- Waiting for bus idle before re-arbitration/retransmission
  );

  -- ISO 11898-1 Section 6.4: minimum 6 retransmission attempts
  constant retransmission_limit_c : integer := 6;

end package can_types_pkg;
