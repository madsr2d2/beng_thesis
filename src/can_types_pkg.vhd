--------------------------------------------------------------------------------
-- Title      : CAN Bus Types and Constants
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : can_types_pkg.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Centralized type and constant definitions for the CAN/CAN-FD
--              transmitter design per ISO 11898-1:2015.
--
-- Section map (in order):
--   1. Protocol Constants       -- field widths, max sizes, CRC polynomials
--   2. Bit Timing Configuration -- ISO Table 13 subtypes
--   3. Core Enumerations        -- all enum types
--   4. Scalar Subtypes          -- byte_t, dlc_t, position_t, etc.
--   5. Composite Frame Types    -- bit_t, mac_frame_bit_t, frame_params_t, FIFO
--   6. FSM State Types          -- state enums for each layer
--   7. Encoding Attributes      -- synthesis hints (after all types declared)
--   8. Wire Frame Constants     -- bit positions for CB/CE/FB/FE on-wire frames
--   9. LLC Frame Formats        -- both formats, their constants and types
--  10. Interface Types          -- all _if_t records with reset constants
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

package can_types_pkg is

  ---------------------------------------------------------------------------
  -- 1. Protocol Constants
  ---------------------------------------------------------------------------
  constant dominant_bit_c    : std_logic                                      := '0';
  constant recessive_bit_c   : std_logic                                      := '1';
  constant sof_c             : integer                                        := 0;
  constant crc_15_length_c   : integer                                        := 15;
  constant crc_17_length_c   : integer                                        := 17;
  constant crc_21_length_c   : integer                                        := 21;
  constant crc_poly_15_vec_c : std_logic_vector(crc_15_length_c - 1 downto 0) := 15x"4599";
  constant crc_poly_17_vec_c : std_logic_vector(crc_17_length_c - 1 downto 0) := 17x"1685B";
  constant crc_poly_21_vec_c : std_logic_vector(crc_21_length_c - 1 downto 0) := 21x"102899";
  constant crc_init_15_vec_c : std_logic_vector(crc_15_length_c - 1 downto 0) := (others => '0');
  constant crc_init_17_vec_c : std_logic_vector(crc_17_length_c - 1 downto 0) := '1' & (crc_17_length_c - 2 downto 0 => '0');
  constant crc_init_21_vec_c : std_logic_vector(crc_21_length_c - 1 downto 0) := '1' & (crc_21_length_c - 2 downto 0 => '0');
  constant dlc_field_width_c : integer                                        := 4;
  constant sbc_field_width_c : integer                                        := 4;
  constant byte_width_c      : integer                                        := 8;
  constant stuff_width_c     : integer                                        := 5;

  -- Max frame: FD extended, DLC 15 -> eof_stop = 593.
  constant max_mac_frame_length_c        : integer := 640;
  subtype  bit_count_t is integer range 0 to max_mac_frame_length_c;
  constant base_id_width_c               : integer := 11;
  constant extended_id_width_c           : integer := 18;
  constant eof_field_width_c             : integer := 7;
  constant error_flag_width_c            : integer := 6;
  constant error_delimiter_width_c       : integer := 8;
  constant bus_idle_condition_width_c    : integer := 11;   -- ISO 11898-1: 3.34
  constant intermission_width_c          : integer := 3;    -- ISO 11898-1: 6.6.7.2
  constant suspend_transmission_width_c  : integer := 8;    -- ISO 11898-1: 6.6.7.4
  constant transmitted_bits_fifo_depth_c : integer := 32;
  constant dlc_max_decimal_value         : integer := 15;
  constant max_data_bytes_c              : integer := 64;
  constant tdc_bit_time_max_c            : integer := 1000; -- ISO 11898-1: 7.3.4

  ---------------------------------------------------------------------------
  -- 2. Bit Timing Configuration (ISO 11898-1 Table 12, shared prescaler)
  ---------------------------------------------------------------------------
  -- Default reference clock used by timing helper calculations and tests.
  constant system_clock_freq_c : integer := 100_000_000; -- 100 MHz
  subtype  prescaler is integer range 1 to 32;
  subtype  nominal_prop_seg is integer range 0 to 96;
  subtype  data_prop_seg is integer range 0 to 8;
  subtype  nominal_phase_seg1 is integer range 1 to 32;
  subtype  data_phase_seg1 is integer range 1 to 8;
  subtype  nominal_phase_seg2 is integer range 2 to 32;
  subtype  data_phase_seg2 is integer range 2 to 8;
  subtype  nominal_sjw is integer range 1 to 32;
  subtype  data_sjw is integer range 1 to 8;
  -- TDC configuration: settling margin added to measured delay (ISO 7.3.4).
  -- Must not exceed data_bit_time to avoid FIFO index pointing at the wrong bit.
  subtype  ssp_offset is integer range 1 to 63;
  constant max_transmitter_delay_c : integer := 255; -- ISO 11898-1: 7.3.4
  constant sync_seg_c              : integer := 1;

  ---------------------------------------------------------------------------
  -- 3. Core Enumerations
  ---------------------------------------------------------------------------
  type mac_frame_bit_name_t is (
    -- Flag bits
    active_error_flag_bit,
    passive_error_flag_bit,
    overload_flag_bit,
    -- Inter-frame spacing bits
    bus_integration_bit,
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

  type can_format_t is (
    cc_basic,
    cc_extended,
    fd_basic,
    fd_extended,
    unknown
  );

  type transfer_status_t is (
    ongoing,
    lost_arbitration,
    transmitted,
    aborted,
    disturbed
  );

  type tx_mac_monitor_event_t is (
    none,
    ack_detected,
    ack_error,
    bit_error,
    lost_arbitration
  );

  -- Sample strobe type indicator (ISO 11898-1:2024 7.3.4).
  -- Distinguishes between primary and secondary sample points for TDC.
  type strobe_type_t is (
    sp_strobe, -- Primary Sample Point (arbitration phase and non-TDC data)
    ssp_strobe -- Secondary Sample Point (TDC-enabled data phase, ISO 7.3.4)
  );

  ---------------------------------------------------------------------------
  -- 4. Scalar Subtypes
  ---------------------------------------------------------------------------
  subtype position_t is integer range 0 to max_mac_frame_length_c;
  subtype byte_t is std_logic_vector(byte_width_c - 1 downto 0);
  subtype dlc_t is integer range 0 to dlc_max_decimal_value;
  subtype stuff_count_t is unsigned(2 downto 0);
  subtype sbc_t is std_logic_vector(sbc_field_width_c - 1 downto 0);
  subtype crc_vector_t is std_logic_vector(crc_poly_21_vec_c'left downto 0);
  subtype fifo_write_ptr_t is integer range 0 to transmitted_bits_fifo_depth_c - 1;

  ---------------------------------------------------------------------------
  -- 5. Composite Frame Types
  ---------------------------------------------------------------------------
  type bit_t is record
    position : position_t;
    polarity : polarity_t;
  end record bit_t;

  constant unknown_bit_c : bit_t := (0, unknown);

  type mac_frame_bit_t is record
    polarity : polarity_t;
    bit_name : mac_frame_bit_name_t;
  end record mac_frame_bit_t;

  constant reset_mac_frame_bit_c   : mac_frame_bit_t := (polarity => recessive, bit_name => unknown);
  constant unknown_mac_frame_bit_c : mac_frame_bit_t := (polarity => unknown,   bit_name => unknown);

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

  -- Circular buffer of recently transmitted bits (used by MAC monitor for
  -- comparing observed bus polarity against what was sent, accounting for TDC).
  type transmitted_bits_fifo_t is array (transmitted_bits_fifo_depth_c - 1 downto 0) of mac_frame_bit_t;

  -- Frame-specific cached parameters, calculated once per frame by
  -- calculate_frame_params() and passed down the pipeline via can_mac_ser_tx.
  type frame_params_t is record
    -- Frame type and control flags
    format          : can_format_t;
    dlc_vector      : std_logic_vector(dlc_field_width_c - 1 downto 0);
    is_fd_frame     : boolean;
    is_remote_frame : boolean;
    has_brs         : boolean;
    esi_enable      : boolean;

    -- Field boundaries (bit positions in the on-wire frame)
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

    -- Format-specific bit positions (polarities resolved for BRS/ESI)
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

  ---------------------------------------------------------------------------
  -- 6. FSM State Types
  ---------------------------------------------------------------------------
  type can_mac_ser_tx_state_t is (
    load_config_byte_0,
    load_config_byte_1,
    load_llc_frame_byte,
    shift_out_bits
  );

  type can_mac_fsm_tx_state_t is (
    bus_reintegration,
    bus_idle,
    intermission,
    suspend_transmission,
    transmitting_frame,
    transmitting_active_error_flag,
    transmitting_passive_error_flag,
    transmitting_overload_flag
  );

  -- PCS layer FSM states (ISO 7.3.4 TDC mechanism)
  type can_pcs_tx_state_t is (
    idle,                 -- Waiting for first bit from MAC
    measuring_delay,      -- Counting TX->RX propagation delay
    transmitting_nominal, -- Transmitting at nominal bit rate (arbitration phase)
    transmitting_data     -- Transmitting at data bit rate (FD data phase with TDC)
  );

  type can_llc_tx_state_t is (
    idle,            -- Waiting for user SOP
    capture_frame,   -- Capturing full user frame into LLC buffer
    send_frame,      -- Streaming buffered frame to MAC
    wait_for_result, -- Waiting for MAC transfer_status
    wait_for_idle    -- Waiting for bus idle before re-arbitration/retransmission
  );

  ---------------------------------------------------------------------------
  -- 7. Encoding Attributes
  ---------------------------------------------------------------------------

  attribute fsm_encoding : string;
  attribute fsm_encoding of can_format_t           : type is "one_hot";
  attribute fsm_encoding of transfer_status_t      : type is "one_hot";
  attribute fsm_encoding of can_mac_ser_tx_state_t : type is "one_hot";
  attribute fsm_encoding of can_mac_fsm_tx_state_t : type is "one_hot";

  ---------------------------------------------------------------------------
  -- 8. Wire Frame Constants (ISO 11898-1 Figure 2)
  --
  -- Bit position constants for each on-wire frame format. Each constant is a
  -- bit_t combining the absolute bit position within the frame and the fixed
  -- polarity of that field (unknown = determined by data/DLC at runtime).
  ---------------------------------------------------------------------------

  -- Common fixed-polarity bits shared across formats
  constant active_error_flag_bit_c    : mac_frame_bit_t := (dominant,   active_error_flag_bit);
  constant passive_error_flag_bit_c   : mac_frame_bit_t := (recessive,  passive_error_flag_bit);
  constant eof_bit_c                  : mac_frame_bit_t := (recessive,  eof_bit);
  constant sof_bit_c                  : mac_frame_bit_t := (dominant,   sof_bit);
  constant tx_ack_bit_c               : mac_frame_bit_t := (recessive,  ack_bit);
  constant ack_delimiter_bit_c        : mac_frame_bit_t := (recessive,  ack_delimiter_bit);
  constant crc_delimiter_bit_c        : mac_frame_bit_t := (recessive,  crc_delimiter_bit);
  constant error_delimiter_bit_c      : mac_frame_bit_t := (recessive,  error_delimiter_bit);
  constant bus_integration_bit_c      : mac_frame_bit_t := (recessive,  bus_integration_bit);
  constant intermission_bit_c         : mac_frame_bit_t := (recessive,  intermission_bit);
  constant overload_flag_bit_c        : mac_frame_bit_t := (dominant,   overload_flag_bit);
  constant suspend_transmission_bit_c : mac_frame_bit_t := (recessive,  suspend_transmission_bit);
  constant idle_bit_c                 : mac_frame_bit_t := (recessive,  idle_bit);

  -- CAN Classic Basic (CB)
  constant cb_base_id_start_c : bit_t := (sof_c + 1, dominant);
  constant cb_base_id_stop_c  : bit_t := (cb_base_id_start_c.position + base_id_width_c - 1, unknown);
  constant cb_rtr_c           : bit_t := (cb_base_id_stop_c.position + 1, unknown);
  constant cb_ide_c           : bit_t := (cb_rtr_c.position + 1, dominant);
  constant cb_r0_c            : bit_t := (cb_ide_c.position + 1, dominant);
  constant cb_dlc_start_c     : bit_t := (cb_r0_c.position + 1, unknown);
  constant cb_dlc_stop_c      : bit_t := (cb_dlc_start_c.position + dlc_field_width_c - 1, unknown);
  constant cb_data_start_c    : bit_t := (cb_dlc_stop_c.position + 1, unknown);

  -- CAN Classic Extended (CE)
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

  -- CAN FD Basic (FB)
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

  -- CAN FD Extended (FE)
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

  ---------------------------------------------------------------------------
  -- 9. LLC Frame Formats
  --
  -- Two frame formats exist at the LLC/MAC boundary. Both carry the same
  -- logical content; they differ in byte ordering and padding.
  --
  -- Internal format (variable length, used by can_llc_tx and can_mac_ser_tx):
  --   Optimised for streaming. Config bytes come first so the MAC serializer
  --   can begin as soon as the first byte is accepted. No padding.
  --
  --   Byte 0 (SOP): [7:5]=FMT, [4]=FTYP(RTR), [3]=ESI, [2]=BRS, [1:0]=00
  --   Byte 1:       [7:4]=DLC, [3:0]=0000
  --   Bytes 2-5:    ID (32-bit, left-aligned MSB first; CB uses bits[31:21],
  --                    CE uses bits[31:3])
  --   Bytes 6+:     Data (DLC count only, no padding), EOP on last byte
  --
  -- Legacy format (fixed 71 bytes, defined in the project report):
  --   Presented at the external user interface. Fixed length simplifies
  --   framing for the host. can_llc_adapter translates legacy to internal
  --   before the frame enters the TX pipeline.
  --
  --   Bytes 0-3:  ID bytes (right-aligned, same bit layout as internal bytes 2-5)
  --   Byte  4:    [7]=reserved, [6:4]=FMT, [3:0]=DLC
  --   Bytes 5-68: Data (0-64 bytes, zero-padded to fill)
  --   Byte  69:   [7:1]=reserved, [0]=IDE (redundant with FMT, not forwarded)
  --   Byte  70:   [7:3]=reserved, [2]=BRS, [1]=ESI, [0]=RTR
  --
  -- The core ordering problem: BRS, ESI, and RTR are needed in byte 0 of the
  -- internal format but arrive in byte 70 of the legacy format. The adapter
  -- must buffer the full 71 bytes before it can emit the first internal byte.
  ---------------------------------------------------------------------------

  -- FMT field encodings (3-bit field in config byte 0 / legacy byte 4 [6:4])
  constant llc_fmt_cb_c : std_logic_vector(2 downto 0) := "000"; -- Classic Basic
  constant llc_fmt_ce_c : std_logic_vector(2 downto 0) := "100"; -- Classic Extended
  constant llc_fmt_fb_c : std_logic_vector(2 downto 0) := "010"; -- FD Basic
  constant llc_fmt_fe_c : std_logic_vector(2 downto 0) := "110"; -- FD Extended

  -- Legacy frame layout constants
  constant legacy_frame_len_c    : integer := 71;
  constant legacy_fmt_dlc_byte_c : integer := 4;
  constant legacy_data_offset_c  : integer := 5;
  constant legacy_flags_byte_c   : integer := 70;

  type legacy_frame_t is array (0 to legacy_frame_len_c - 1) of byte_t;

  -- Internal format: config byte 0 bit positions
  constant llc_frame_config_byte_0_format_start : integer := byte_width_c - 1;                         -- bit 7
  constant llc_frame_config_byte_0_format_end   : integer := llc_frame_config_byte_0_format_start - 2; -- bit 5
  constant llc_frame_config_byte_0_ftyp         : integer := llc_frame_config_byte_0_format_end - 1;   -- bit 4
  constant llc_frame_config_byte_0_esi          : integer := llc_frame_config_byte_0_ftyp - 1;         -- bit 3
  constant llc_frame_config_byte_0_brs          : integer := llc_frame_config_byte_0_esi - 1;          -- bit 2
  constant llc_frame_config_byte_0_extended_bit : integer := llc_frame_config_byte_0_format_start;     -- bit 7 (MSB of FMT)

  -- Internal format: config byte 1 bit positions
  constant llc_frame_config_byte_1_dlc_start : integer := byte_width_c - 1;                      -- bit 7
  constant llc_frame_config_byte_1_dlc_end   : integer := llc_frame_config_byte_1_dlc_start - 3; -- bit 4

  -- ID stream layout (4 bytes, MSB-first, left-aligned in 32-bit vector)
  constant llc_id_byte_count_c   : integer := 4;
  constant llc_id_stream_width_c : integer := llc_id_byte_count_c * byte_width_c;

  -- Config byte 0: [7:5]=FMT, [4]=FTYP(RTR), [3]=ESI, [2]=BRS, [1:0]=00
  type llc_config_byte_0_t is record
    format : std_logic_vector(2 downto 0); -- [7:5] Frame format (llc_fmt_*_c)
    ftyp   : std_logic;                    -- [4] Frame type: '1'=remote, '0'=data
    esi    : std_logic;                    -- [3] Error state indicator (FD only)
    brs    : std_logic;                    -- [2] Bit rate switch (FD only)
    unused : std_logic_vector(1 downto 0); -- [1:0] Reserved (always '0')
  end record llc_config_byte_0_t;

  -- Config byte 1: [7:4]=DLC, [3:0]=0000
  type llc_config_byte_1_t is record
    dlc    : std_logic_vector(3 downto 0); -- [7:4] Data length code
    unused : std_logic_vector(3 downto 0); -- [3:0] Reserved (always '0')
  end record llc_config_byte_1_t;

  -- Internal LLC frame record (matches Avalon-ST byte sequence above)
  type llc_frame_t is record
    config_0 : llc_config_byte_0_t;
    config_1 : llc_config_byte_1_t;
    id       : std_logic_vector(31 downto 0);                       -- 4-byte packed ID (left-aligned)
    data     : std_logic_vector(max_data_bytes_c * 8 - 1 downto 0); -- Up to 64 data bytes
  end record llc_frame_t;

  -- ISO 11898-1 Section 6.4: minimum 6 retransmission attempts
  constant retransmission_limit_c : integer := 6;

  ---------------------------------------------------------------------------
  -- 10. Interface Types
  --
  -- Each interface record is followed immediately by its reset constant.
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

  -- can_mac_ser_tx -> can_mac_fsm_tx (subordinate to manager)
  type can_mac_ser_fsm_tx_if_s2m_t is record
    data         : polarity_t;     -- CAN polarity (MAC domain)
    valid        : boolean;        -- Data valid signal
    frame_params : frame_params_t; -- Cached frame parameters
  end record can_mac_ser_fsm_tx_if_s2m_t;

  constant tx_mac_ser_to_fsm_if_reset_c : can_mac_ser_fsm_tx_if_s2m_t :=
  (
    data         => dominant,
    valid        => false,
    frame_params => frame_params_reset_c
  );

  -- can_mac_fsm_tx -> can_mac_ser_tx (manager to subordinate)
  type can_mac_ser_fsm_tx_if_m2s_t is record
    transfer_status : transfer_status_t;
    ready           : boolean;
  end record can_mac_ser_fsm_tx_if_m2s_t;

  constant tx_mac_fsm_to_ser_if_reset_c : can_mac_ser_fsm_tx_if_m2s_t :=
  (
    transfer_status => ongoing,
    ready           => false
  );

  -- can_mac_ser_tx -> can_llc_tx (internal Avalon-ST stream)
  type can_llc_mac_tx_if_s2d_t is record
    avalon_st_source : avalon_st_source_t;
  end record can_llc_mac_tx_if_s2d_t;

  -- can_llc_tx <- can_mac_ser_tx (backpressure + status)
  type can_llc_mac_tx_if_d2s_t is record
    avalon_st_sink  : avalon_st_sink_t;
    transfer_status : transfer_status_t;
  end record can_llc_mac_tx_if_d2s_t;

  constant mac_to_llc_if_reset_c : can_llc_mac_tx_if_d2s_t :=
  (
    avalon_st_sink  => (ready => '0'),
    transfer_status => ongoing
  );

  -- User -> can_llc_tx (legacy Avalon-ST stream + abort)
  type can_user_llc_tx_if_s2d_t is record
    avalon_st_source : avalon_st_source_t;
    abort_request    : std_logic; -- Pulse: abort pending transmission
  end record can_user_llc_tx_if_s2d_t;

  -- can_llc_tx -> User (backpressure + status)
  type can_user_llc_tx_if_d2s_t is record
    avalon_st_sink  : avalon_st_sink_t;
    transfer_status : transfer_status_t;
  end record can_user_llc_tx_if_d2s_t;

  -- MAC -> PCS (manager to subordinate) (ISO 11898-1:2015 Section 7.2 PCS_Data.Request service)
  type can_mac_pcs_tx_if_m2s_t is record
    data  : mac_frame_bit_t;
    valid : boolean;
  end record can_mac_pcs_tx_if_m2s_t;

  constant mac_to_pcs_if_reset_c : can_mac_pcs_tx_if_m2s_t :=
  (
    data  => reset_mac_frame_bit_c,
    valid => false
  );

  -- PCS -> MAC (subordinate to manager) (ISO 11898-1:2015 Section 7.2 PCS_Data.Indicate service).
  -- PCS drives bus polarity continuously and pulses sample strobes.
  type can_mac_pcs_tx_if_s2m_t is record
    bus_polarity  : polarity_t;    -- Current bus polarity (continuously driven)
    sample_strobe : std_logic;     -- Pulse at the active sample point
    strobe_type   : strobe_type_t; -- Distinguishes SP from SSP (ISO 7.3.4)
    -- TDC FIFO index: offset into transmitted_bits_fifo for SSP-aligned comparison.
    -- Nominal/arbitration fields use index 0.
    fifo_index : integer range 0 to transmitted_bits_fifo_depth_c - 1;
  end record can_mac_pcs_tx_if_s2m_t;

  constant pcs_to_mac_if_reset_c : can_mac_pcs_tx_if_s2m_t :=
  (
    bus_polarity  => recessive,
    sample_strobe => '0',
    strobe_type   => sp_strobe,
    fifo_index    => 0
  );

  -- MAC FSM -> Bit Stuffer FD (manager to subordinate)
  type can_mac_fsm_bs_tx_if_m2s_t is record
    data  : polarity_t; -- Bit polarity being transmitted
    valid : boolean;    -- Pulse when a new bit is fed to bit stuffer
    start : boolean;    -- Pulse to reinitialize bit stuffer at frame start
  end record can_mac_fsm_bs_tx_if_m2s_t;

  constant mac_fsm_to_bs_fd_if_reset_c : can_mac_fsm_bs_tx_if_m2s_t :=
  (
    data  => recessive,
    valid => false,
    start => false
  );

  -- Bit Stuffer FD -> MAC FSM (subordinate to manager)
  type can_mac_fsm_bs_tx_if_s2m_t is record
    data  : polarity_t;                                       -- Polarity of required stuff bit
    valid : boolean;                                          -- true when stuff bit insertion needed
    sbc   : std_logic_vector(sbc_field_width_c - 1 downto 0); -- Gray-coded stuff bit count with parity
  end record can_mac_fsm_bs_tx_if_s2m_t;

  constant can_mac_fsm_bs_tx_if_s2m_reset_c : can_mac_fsm_bs_tx_if_s2m_t :=
  (
    data  => recessive,
    valid => false,
    sbc   => (others => '0')
  );

  -- MAC FSM -> CRC (manager to subordinate)
  type can_mac_fsm_crc_tx_if_m2s_t is record
    crc_poly_select : std_logic_vector(1 downto 0);
    start           : boolean;
    valid           : boolean;
    data            : std_logic;
  end record can_mac_fsm_crc_tx_if_m2s_t;

  constant mac_fsm_to_crc_if_reset_c : can_mac_fsm_crc_tx_if_m2s_t :=
  (
    crc_poly_select => (others => '0'),
    start           => false,
    valid           => false,
    data            => '0'
  );

  -- CRC -> MAC FSM (subordinate to manager)
  type can_mac_fsm_crc_tx_if_s2m_t is record
    crc : crc_vector_t;
  end record can_mac_fsm_crc_tx_if_s2m_t;

  -- MAC -> Fault Confinement Entity (manager to subordinate) (ISO 11898-1 Table 16/17)
  type can_mac_fce_if_m2s_t is record
    transmitting             : boolean; -- Node is currently transmitting
    error                    : boolean; -- Error detected (pulse)
    primary_error            : boolean; -- Dominant bit after error flag (pulse)
    sending_error_flag       : boolean; -- Currently sending error/overload flag
    counters_unchanged       : boolean; -- Exception: do not update counters
    error_delimiter_too_late : boolean; -- 8+ dominant bits after error flag
    successful_transfer      : boolean; -- Frame completed successfully (pulse)
  end record can_mac_fce_if_m2s_t;

  constant mac_to_fce_if_reset_c : can_mac_fce_if_m2s_t :=
  (
    transmitting             => false,
    error                    => false,
    primary_error            => false,
    sending_error_flag       => false,
    counters_unchanged       => false,
    error_delimiter_too_late => false,
    successful_transfer      => false
  );

  -- Fault Confinement Entity -> MAC (subordinate to manager)
  type can_mac_fce_if_s2m_t is record
    error_passive : boolean; -- true = error-passive node, false = error-active
    bus_off       : boolean; -- true = bus-off state, no transmission allowed
  end record can_mac_fce_if_s2m_t;

  constant fce_to_mac_if_reset_c : can_mac_fce_if_s2m_t :=
  (
    error_passive => false,
    bus_off       => false
  );

  -- FCE state enumeration (ISO 11898-1:2015 Section 8.1.4)
  type fce_state_t is (
    error_active,
    error_passive,
    bus_off
  );

  -- User -> FCE control interface
  type can_fce_ctrl_t is record
    restart_request          : boolean; -- Pulse for bus-off recovery
    error_signalling_enabled : boolean; -- ISO 8.1.4.1: FCE only active when enabled
  end record can_fce_ctrl_t;

  constant fce_ctrl_reset_c : can_fce_ctrl_t :=
  (
    restart_request          => false,
    error_signalling_enabled => true
  );

  -- FCE status (debug/monitoring)
  type can_fce_status_t is record
    state : fce_state_t;
    tec   : integer range 0 to 511;
    rec   : integer range 0 to 255;
  end record can_fce_status_t;

end package can_types_pkg;
