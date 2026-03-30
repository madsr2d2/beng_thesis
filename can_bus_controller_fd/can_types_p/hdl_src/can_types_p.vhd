--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description: Centralized types, constants, and protocol functions for the
--              CAN/CAN-FD design per ISO 11898-1:2015.
--
--              Section map:
--                1. Protocol Constants   -- polarity, field widths, CRC, status
--                2. Bit Timing           -- ISO Table 12 subtypes and limits
--                3. Enumerations         -- bit names, monitor events
--                4. Scalar Subtypes      -- byte, DLC, position, CRC vectors
--                5. Composite Types      -- mac_frame_bit, frame_params, metadata
--                6. Frame Bit Positions  -- CB/CE/FB/FE on-wire field chains
--                7. Interface Records    -- inter-layer records with reset constants
--                8. LLC Frame Format     -- config bytes, legacy layout
--                9. Protocol Functions   -- frame params, bitstream, DLC, ID packing
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-15  TMYAES:   [TRIT-4336] Initial implementation
--                2026-03-20  TMYAES:   [TRIT-4336] Removed redundant config byte records
--                2026-03-21  TMYAES:   [TRIT-4336] Refactored type system and constants.
--                                      Added get_frame_params, get_mac_frame_bit.
--                2026-03-22  TMYAES:   [TRIT-4336] Added get_bit_info. Cleaned up
--                                      type and function names.
--
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

  use work.pk_man_global.all;
  use work.pk_eth_st;

package pk_can_types is

  ---------------------------------------------------------------------------
  -- 1. Protocol Constants
  ---------------------------------------------------------------------------

  -- Bus polarity (ISO 7.4.3)
  constant c_dominant  : std_logic := '0';
  constant c_recessive : std_logic := '1';

  -- Frame field widths (ISO 6.6.10, 6.6.11)
  constant c_byte_width        : integer := 8;
  constant c_base_id_width     : integer := 11; -- ISO 6.6.10.2
  constant c_extended_id_width : integer := 18; -- ISO 6.6.10.2
  constant c_dlc_field_width   : integer := 4;  -- ISO 6.6.10.3, Table 5
  constant c_eof_field_width   : integer := 7;  -- ISO 6.6.10.7, 6.6.11.7

  -- Bit stuffing (ISO 6.6.13.2, Table 10)
  constant c_stuff_width     : integer := 5;
  constant c_sbc_field_width : integer := 4; -- ISO 6.6.11.5, Table 8

  -- Post-CRC field offsets (relative to crc_delimiter position)
  constant c_ack_slot_offset      : integer := 1; -- ISO 6.6.10.6, 6.6.11.6
  constant c_ack_delimiter_offset : integer := 2;
  constant c_eof_start_offset     : integer := 3;

  -- Error signalling (ISO 6.6.5.2, 6.6.5.3)
  constant c_error_flag_width      : integer := 6;
  constant c_error_delimiter_width : integer := 8;
  constant c_error_sequence_width  : integer := c_error_flag_width + c_error_delimiter_width;
  constant c_bus_off_recovery_count : integer := 128; -- ISO 8.8.4.4

  -- Inter-frame spacing (ISO 6.6.7)
  constant c_intermission_width         : integer := 3;  -- ISO 6.6.7.2
  constant c_suspend_transmission_width : integer := 8;  -- ISO 6.6.7.4
  constant c_bus_idle_condition_width   : integer := 11; -- ISO 6.6.7.5

  -- Frame limits
  constant c_sof                  : integer := 0;
  constant c_dlc_max              : integer := 15; -- ISO Table 5
  constant c_max_data_bytes       : integer := 64; -- ISO 6.6.11.4
  constant c_max_mac_frame_length : integer := 640;

  -- CRC polynomials and initial values (ISO 6.6.4.4)
  constant c_crc_15_length   : integer                                        := 15;
  constant c_crc_17_length   : integer                                        := 17;
  constant c_crc_21_length   : integer                                        := 21;
  constant c_crc_poly_15_vec : std_logic_vector(c_crc_15_length - 1 downto 0) := 15x"4599";
  constant c_crc_poly_17_vec : std_logic_vector(c_crc_17_length - 1 downto 0) := 17x"1685B";
  constant c_crc_poly_21_vec : std_logic_vector(c_crc_21_length - 1 downto 0) := 21x"102899";
  constant c_crc_init_15_vec : std_logic_vector(c_crc_15_length - 1 downto 0) := (others => '0');
  constant c_crc_init_17_vec : std_logic_vector(c_crc_17_length - 1 downto 0) := '1' & (c_crc_17_length - 2 downto 0 => '0');
  constant c_crc_init_21_vec : std_logic_vector(c_crc_21_length - 1 downto 0) := '1' & (c_crc_21_length - 2 downto 0 => '0');

  -- Transfer status encoding (ISO 6.5.3, Table 7)
  constant c_ongoing     : std_logic_vector(2 downto 0) := "000";
  constant c_transmitted : std_logic_vector(2 downto 0) := "010";
  constant c_aborted     : std_logic_vector(2 downto 0) := "001";
  constant c_lost_arb    : std_logic_vector(2 downto 0) := "100";
  constant c_disturbed   : std_logic_vector(2 downto 0) := "110";

  -- Frame format encodings (ISO Figure 2)
  constant c_llc_fmt_cb : std_logic_vector(2 downto 0) := "000"; -- Classic Basic
  constant c_llc_fmt_ce : std_logic_vector(2 downto 0) := "100"; -- Classic Extended
  constant c_llc_fmt_fb : std_logic_vector(2 downto 0) := "010"; -- FD Basic
  constant c_llc_fmt_fe : std_logic_vector(2 downto 0) := "110"; -- FD Extended

  -- CRC poly select encodings
  constant c_crc_poly_15_sel : std_logic_vector(1 downto 0) := "00";
  constant c_crc_poly_17_sel : std_logic_vector(1 downto 0) := "01";
  constant c_crc_poly_21_sel : std_logic_vector(1 downto 0) := "10";

  -- TDC polarity history depth (ISO 7.3.4)
  constant c_tdc_polarity_depth : integer := 32;

  -- Retransmission (ISO 6.5.3)
  constant c_retransmission_limit : integer := 6;

  -- Derived vector subtypes
  subtype t_tdc_delay_vec is std_logic_vector(integer(ceil(log2(real(c_tdc_polarity_depth)))) - 1 downto 0);

  ---------------------------------------------------------------------------
  -- 2. Bit Timing (ISO 7.3.2, Table 12)
  ---------------------------------------------------------------------------

  constant c_sync_seg              : integer := 1;    -- ISO 7.3.2
  constant c_max_transmitter_delay : integer := 255;  -- ISO 7.3.4
  constant c_tdc_bit_time_max      : integer := 1000; -- ISO 7.3.4

  subtype t_prescaler is integer range 1 to 32;
  subtype t_nominal_prop_seg is integer range 0 to 96;
  subtype t_data_prop_seg is integer range 0 to 8;
  subtype t_nominal_phase_seg1 is integer range 1 to 32;
  subtype t_data_phase_seg1 is integer range 1 to 8;
  subtype t_nominal_phase_seg2 is integer range 2 to 32;
  subtype t_data_phase_seg2 is integer range 2 to 8;
  subtype t_ssp_offset is integer range 1 to 63;

  ---------------------------------------------------------------------------
  -- 3. Enumerations (simulation/debug only, not on synthesized ports)
  ---------------------------------------------------------------------------

  type t_mac_frame_bit_name is (
    -- Error and overload flags (ISO 6.6.5, 6.6.6)
    active_error_flag_bit,
    passive_error_flag_bit,
    overload_flag_bit,
    error_delimiter_bit,
    -- Inter-frame spacing (ISO 6.6.7)
    bus_integration_bit,
    intermission_bit,
    suspend_transmission_bit,
    idle_bit,
    -- Arbitration and control fields (ISO 6.6.10, 6.6.11)
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
    -- CAN-FD additions (ISO 6.6.11)
    fixed_stuff_bit,
    rrs_bit,
    fdf_bit,
    res_bit,
    brs_bit,
    esi_bit,
    sbs_bit
  );

  -- Transmitter-side bus monitoring events (ISO 6.6.5.1)
  type t_monitor_event_tx is (
    none,
    ack_detected,
    ack_error,
    bit_error,
    lost_arbitration
  );

  ---------------------------------------------------------------------------
  -- 4. Scalar Subtypes
  ---------------------------------------------------------------------------

  subtype t_bit_count is integer range 0 to c_max_mac_frame_length;
  subtype t_position is integer range 0 to c_max_mac_frame_length;
  subtype t_byte is std_logic_vector(c_byte_width - 1 downto 0);
  subtype t_dlc is integer range 0 to c_dlc_max;
  subtype t_stuff_count is unsigned(2 downto 0);
  subtype t_sbc is std_logic_vector(c_sbc_field_width - 1 downto 0);
  -- subtype t_crc_vector is std_logic_vector(c_crc_21_length - 1 downto 0);

  ---------------------------------------------------------------------------
  -- 5. Composite Types
  ---------------------------------------------------------------------------

  type t_mac_frame_bit is record
    polarity : std_logic;
    bit_name : t_mac_frame_bit_name;
  end record t_mac_frame_bit;

  constant c_reset_mac_frame_bit : t_mac_frame_bit := (polarity => c_recessive, bit_name => idle_bit);

  type t_bit_info is record
    event_type      : t_monitor_event_tx;
    transfer_status : std_logic_vector(2 downto 0);
  end record t_bit_info;

  constant c_reset_bit_info : t_bit_info :=
  (
    event_type      => none,
    transfer_status => c_ongoing
  );

  -- TDC polarity history: shift register for SSP delay lookup (ISO 7.3.4)
  subtype t_tdc_polarity_history is std_logic_vector(c_tdc_polarity_depth - 1 downto 0);

  -- LLC frame metadata (ISO 6.4.3 Table 4):
  type t_llc_metadata is record
    format : std_logic_vector(2 downto 0);
    dlc    : std_logic_vector(c_dlc_field_width - 1 downto 0);
    ftyp   : std_logic;
    brs    : std_logic;
    esi    : std_logic;
  end record t_llc_metadata;

  constant c_llc_metadata_reset : t_llc_metadata :=
  (
    format => c_llc_fmt_cb,
    dlc    => (others => '0'),
    ftyp   => '0',
    brs    => '0',
    esi    => '0'
  );

  -- Frame positions: derived bit-count thresholds, calculated once per frame.
  -- LLC metadata fields (format, dlc, brs, esi, rtr) are read directly
  -- from the serializer interface where needed.
  type t_frame_params is record
    dlc_start          : t_position;
    data_stop          : t_position;
    dynamic_stuff_stop : t_position;
    crc_start          : t_position;
    crc_delimiter      : t_position;
    crc_poly_select    : std_logic_vector(1 downto 0);
  end record t_frame_params;

  constant c_frame_params_reset : t_frame_params :=
  (
    dlc_start          => 0,
    data_stop          => 0,
    dynamic_stuff_stop => 0,
    crc_start          => 0,
    crc_delimiter      => 0,
    crc_poly_select    => c_crc_poly_15_sel
  );

  ---------------------------------------------------------------------------
  -- 6. Frame Bit Positions
  --
  -- Fixed-polarity bit constants and per-format field position chains.
  -- Position chains follow ISO Figure 2 field ordering.
  ---------------------------------------------------------------------------

  -- Common fixed-polarity bits (ISO 6.6.8, 6.6.10.5-7, 6.6.5)
  constant c_sof_bit                : t_mac_frame_bit := (c_dominant,  sof_bit);
  constant c_tx_ack_bit             : t_mac_frame_bit := (c_recessive, ack_bit);
  constant c_ack_delimiter_bit      : t_mac_frame_bit := (c_recessive, ack_delimiter_bit);
  constant c_crc_delimiter_bit      : t_mac_frame_bit := (c_recessive, crc_delimiter_bit);
  constant c_eof_bit                : t_mac_frame_bit := (c_recessive, eof_bit);
  constant c_active_error_flag_bit  : t_mac_frame_bit := (c_dominant,  active_error_flag_bit);
  constant c_passive_error_flag_bit : t_mac_frame_bit := (c_recessive, passive_error_flag_bit);
  constant c_error_delimiter_bit    : t_mac_frame_bit := (c_recessive, error_delimiter_bit);
  constant c_overload_flag_bit      : t_mac_frame_bit := (c_dominant,  overload_flag_bit);

  -- CAN Classic Basic (CBFF) positions (ISO 6.6.10)
  constant c_cb_base_id_start : integer := c_sof + 1;
  constant c_cb_base_id_stop  : integer := c_cb_base_id_start + c_base_id_width - 1;
  constant c_cb_rtr           : integer := c_cb_base_id_stop + 1;
  constant c_cb_ide           : integer := c_cb_rtr + 1;
  constant c_cb_r0            : integer := c_cb_ide + 1;
  constant c_cb_dlc_start     : integer := c_cb_r0 + 1;
  constant c_cb_dlc_stop      : integer := c_cb_dlc_start + c_dlc_field_width - 1;
  constant c_cb_data_start    : integer := c_cb_dlc_stop + 1;

  -- CAN Classic Extended (CEFF) positions (ISO 6.6.10)
  constant c_ce_base_id_start     : integer := c_sof + 1;
  constant c_ce_base_id_stop      : integer := c_ce_base_id_start + c_base_id_width - 1;
  constant c_ce_srr               : integer := c_ce_base_id_stop + 1;
  constant c_ce_ide               : integer := c_ce_srr + 1;
  constant c_ce_extended_id_start : integer := c_ce_ide + 1;
  constant c_ce_extended_id_stop  : integer := c_ce_extended_id_start + c_extended_id_width - 1;
  constant c_ce_rtr               : integer := c_ce_extended_id_stop + 1;
  constant c_ce_r1                : integer := c_ce_rtr + 1;
  constant c_ce_r0                : integer := c_ce_r1 + 1;
  constant c_ce_dlc_start         : integer := c_ce_r0 + 1;
  constant c_ce_dlc_stop          : integer := c_ce_dlc_start + c_dlc_field_width - 1;
  constant c_ce_data_start        : integer := c_ce_dlc_stop + 1;

  -- CAN FD Basic (FBFF) positions (ISO 6.6.11)
  constant c_fd_base_id_start : integer := c_sof + 1;
  constant c_fd_base_id_stop  : integer := c_fd_base_id_start + c_base_id_width - 1;
  constant c_fb_rrs           : integer := c_fd_base_id_stop + 1;
  constant c_fb_ide           : integer := c_fb_rrs + 1;
  constant c_fb_fdf           : integer := c_fb_ide + 1;
  constant c_fb_res           : integer := c_fb_fdf + 1;
  constant c_fb_brs           : integer := c_fb_res + 1;
  constant c_fb_esi           : integer := c_fb_brs + 1;
  constant c_fb_dlc_start     : integer := c_fb_esi + 1;
  constant c_fb_dlc_stop      : integer := c_fb_dlc_start + c_dlc_field_width - 1;
  constant c_fb_data_start    : integer := c_fb_dlc_stop + 1;

  -- CAN FD Extended (FEFF) positions (ISO 6.6.11)
  constant c_fe_base_id_start     : integer := c_sof + 1;
  constant c_fe_base_id_stop      : integer := c_fe_base_id_start + c_base_id_width - 1;
  constant c_fe_srr               : integer := c_fe_base_id_stop + 1;
  constant c_fe_ide               : integer := c_fe_srr + 1;
  constant c_fe_extended_id_start : integer := c_fe_ide + 1;
  constant c_fe_extended_id_stop  : integer := c_fe_extended_id_start + c_extended_id_width - 1;
  constant c_fe_rrs               : integer := c_fe_extended_id_stop + 1;
  constant c_fe_fdf               : integer := c_fe_rrs + 1;
  constant c_fe_res               : integer := c_fe_fdf + 1;
  constant c_fe_brs               : integer := c_fe_res + 1;
  constant c_fe_esi               : integer := c_fe_brs + 1;
  constant c_fe_dlc_start         : integer := c_fe_esi + 1;
  constant c_fe_dlc_stop          : integer := c_fe_dlc_start + c_dlc_field_width - 1;
  constant c_fe_data_start        : integer := c_fe_dlc_stop + 1;

  ---------------------------------------------------------------------------
  -- 7. Interface Records
  -- Each record is followed by its reset constant.
  ---------------------------------------------------------------------------
  -- Serializer -> FSM
  type t_can_mac_ser_fsm_tx_if_s2m is record
    data         : std_logic;
    valid        : std_logic;
    llc_metadata : t_llc_metadata;
  end record t_can_mac_ser_fsm_tx_if_s2m;

  constant c_tx_mac_ser_to_fsm_if_reset : t_can_mac_ser_fsm_tx_if_s2m :=
  (
    data         => 'U',
    valid        => '0',
    llc_metadata => c_llc_metadata_reset
  );

  -- FSM -> Serializer
  type t_can_mac_ser_fsm_tx_if_m2s is record
    transfer_status : std_logic_vector(2 downto 0);
    ready           : std_logic;
  end record t_can_mac_ser_fsm_tx_if_m2s;

  constant c_tx_mac_fsm_to_ser_if_reset : t_can_mac_ser_fsm_tx_if_m2s :=
  (
    transfer_status => c_ongoing,
    ready           => '0'
  );

  -- LLC -> MAC
  type t_can_llc_mac_tx_if_s2d is record
    avalon_st_source : pk_eth_st.t_eth_st_s2d;
  end record t_can_llc_mac_tx_if_s2d;

  -- MAC -> LLC
  type t_can_llc_mac_tx_if_d2s is record
    avalon_st_sink  : pk_eth_st.t_eth_st_d2s;
    transfer_status : std_logic_vector(2 downto 0);
  end record t_can_llc_mac_tx_if_d2s;

  constant c_mac_to_llc_if_reset : t_can_llc_mac_tx_if_d2s :=
  (
    avalon_st_sink  => (ready => '1'),
    transfer_status => c_ongoing
  );

  -- User -> LLC
  type t_can_user_llc_tx_if_s2d is record
    avalon_st_source : pk_eth_st.t_eth_st_s2d;
    abort_request    : std_logic;
  end record t_can_user_llc_tx_if_s2d;

  -- LLC -> User
  type t_can_user_llc_tx_if_d2s is record
    avalon_st_sink  : pk_eth_st.t_eth_st_d2s;
    transfer_status : std_logic_vector(2 downto 0);
  end record t_can_user_llc_tx_if_d2s;

  -- MAC -> PCS (ISO 7.2, PCS_Data.Request)
  type t_can_mac_pcs_tx_if_m2s is record
    polarity      : std_logic;
    valid         : std_logic;
    use_data_rate : std_logic;
    start_tdc     : std_logic;
  end record t_can_mac_pcs_tx_if_m2s;

  constant c_mac_to_pcs_if_reset : t_can_mac_pcs_tx_if_m2s :=
  (
    polarity      => c_recessive,
    valid         => '0',
    use_data_rate => '0',
    start_tdc     => '0'
  );

  -- PCS -> MAC (ISO 7.2, PCS_Data.Indicate)
  type t_can_mac_pcs_tx_if_s2m is record
    bus_polarity : std_logic;
    sp           : std_logic;
    ssp          : std_logic;
    tdc_delay    : t_tdc_delay_vec;
  end record t_can_mac_pcs_tx_if_s2m;

  constant c_pcs_to_mac_if_reset : t_can_mac_pcs_tx_if_s2m :=
  (
    bus_polarity => c_recessive,
    sp           => '0',
    ssp          => '0',
    tdc_delay    => (others => '0')
  );


  -- FSM -> Bit Stuffer (ISO 6.6.13)
  type t_can_mac_fsm_bs_tx_if_m2s is record
    data  : std_logic;
    valid : std_logic;
    start : std_logic;
  end record t_can_mac_fsm_bs_tx_if_m2s;

  constant c_mac_fsm_to_bs_fd_if_reset : t_can_mac_fsm_bs_tx_if_m2s :=
  (
    data  => c_recessive,
    valid => '0',
    start => '0'
  );

  -- Bit Stuffer -> FSM (ISO 6.6.13)
  type t_can_mac_fsm_bs_tx_if_s2m is record
    data  : std_logic;
    valid : std_logic;
    sbc   : std_logic_vector(c_sbc_field_width - 1 downto 0);
  end record t_can_mac_fsm_bs_tx_if_s2m;

  constant c_can_mac_fsm_bs_tx_if_s2m_reset : t_can_mac_fsm_bs_tx_if_s2m :=
  (
    data  => c_recessive,
    valid => '0',
    sbc   => (others => '0')
  );

  -- FSM -> CRC (ISO 6.6.4.4)
  type t_can_mac_fsm_crc_tx_if_m2s is record
    crc_poly_select : std_logic_vector(1 downto 0);
    start           : std_logic;
    valid           : std_logic;
    data            : std_logic;
  end record t_can_mac_fsm_crc_tx_if_m2s;

  constant c_mac_fsm_to_crc_if_reset : t_can_mac_fsm_crc_tx_if_m2s :=
  (
    crc_poly_select => (others => '0'),
    start           => '0',
    valid           => '0',
    data            => '0'
  );

  -- CRC -> FSM
  type t_can_mac_fsm_crc_tx_if_s2m is record
    crc : std_logic_vector(c_crc_21_length - 1 downto 0);
  end record t_can_mac_fsm_crc_tx_if_s2m;

  -- MAC -> FCE (ISO Table 16, Table 17)
  type t_can_mac_fce_if_m2s is record
    transmitting                : std_logic;
    error                       : std_logic;
    primary_error               : std_logic;
    sending_error_overload_flag : std_logic;
    counters_unchanged          : std_logic;
    error_delimiter_too_late    : std_logic;
    successful_transfer         : std_logic;
    error_passive_response      : std_logic;
    error_active_response       : std_logic;
  end record t_can_mac_fce_if_m2s;

  constant c_mac_to_fce_if_reset : t_can_mac_fce_if_m2s :=
  (
    transmitting                => '0',
    error                       => '0',
    primary_error               => '0',
    sending_error_overload_flag => '0',
    counters_unchanged          => '0',
    error_delimiter_too_late    => '0',
    successful_transfer         => '0',
    error_passive_response      => '0',
    error_active_response       => '0'
  );

  -- FCE -> MAC (ISO Table 16, Table 17)
  type t_can_mac_fce_if_s2m is record
    error_passive_request : std_logic;
    error_active_request  : std_logic;
    bus_off               : std_logic;
  end record t_can_mac_fce_if_s2m;

  constant c_fce_to_mac_if_reset : t_can_mac_fce_if_s2m :=
  (
    error_passive_request => '0',
    error_active_request  => '0',
    bus_off               => '0'
  );

  -- LLC -> FCE (ISO Table 14)
  type t_can_llc_fce_if_m2s is record
    normal_mode_request : std_logic;
  end record t_can_llc_fce_if_m2s;

  constant c_llc_to_fce_if_reset : t_can_llc_fce_if_m2s :=
  (
    normal_mode_request => '0'
  );

  -- FCE -> LLC (ISO Table 15)
  type t_can_fce_llc_if_s2m is record
    normal_mode_response : std_logic;
    bus_off              : std_logic;
  end record t_can_fce_llc_if_s2m;

  constant c_fce_to_llc_if_reset : t_can_fce_llc_if_s2m :=
  (
    normal_mode_response => '0',
    bus_off              => '0'
  );

  -- FCE -> PCS (ISO Table 18)
  type t_can_fce_pcs_if_m2s is record
    bus_off_request         : std_logic;
    bus_off_release_request : std_logic;
  end record t_can_fce_pcs_if_m2s;

  constant c_fce_to_pcs_if_reset : t_can_fce_pcs_if_m2s :=
  (
    bus_off_request         => '0',
    bus_off_release_request => '0'
  );

  -- PCS -> FCE (ISO Table 19)
  type t_can_pcs_fce_if_s2m is record
    bus_off_response         : std_logic;
    bus_off_release_response : std_logic;
  end record t_can_pcs_fce_if_s2m;

  constant c_pcs_to_fce_if_reset : t_can_pcs_fce_if_s2m :=
  (
    bus_off_response         => '0',
    bus_off_release_response => '0'
  );

  ---------------------------------------------------------------------------
  -- 8. LLC Frame Format
  --
  -- Internal format (variable length, streamed by can_llc_tx to can_mac_ser_tx):
  --   Byte 0 (SOP): [7:5]=FMT, [4]=FTYP(RTR), [3]=ESI, [2]=BRS, [1:0]=00
  --   Byte 1:       [7:4]=DLC, [3:0]=0000
  --   Bytes 2-5:    ID (32-bit, MSB first, left-aligned; CB uses [31:21])
  --   Bytes 6+:     Data (DLC count, no padding), EOP on last byte
  --
  -- Legacy format (up to 71 bytes, presented at user interface):
  --   Bytes 0-3:  ID bytes
  --   Byte  4:    [7]=reserved, [6:4]=FMT, [3:0]=DLC
  --   Bytes 5-68: Data (zero-padded to 64)
  --   Byte  69:   [0]=IDE
  --   Byte  70:   [2]=BRS, [1]=ESI, [0]=RTR
  ---------------------------------------------------------------------------

  -- Internal LLC frame
  constant c_internal_llc_frame_len : integer := 70;
  type     t_llc_frame is array (0 to c_internal_llc_frame_len - 1) of t_byte;

  -- Legacy frame
  constant c_legacy_frame_len    : integer := 71;
  constant c_legacy_fmt_dlc_byte : integer := 4;
  constant c_legacy_data_offset  : integer := 5;

  type t_legacy_frame is array (0 to c_legacy_frame_len - 1) of t_byte;

  -- Config byte 0 bit positions: [7:5]=FMT, [4]=FTYP, [3]=ESI, [2]=BRS
  constant c_llc_frame_config_byte_0_format_start : integer := c_byte_width - 1;                           -- bit 7
  constant c_llc_frame_config_byte_0_format_end   : integer := c_llc_frame_config_byte_0_format_start - 2; -- bit 5
  constant c_llc_frame_config_byte_0_ftyp         : integer := c_llc_frame_config_byte_0_format_end - 1;   -- bit 4
  constant c_llc_frame_config_byte_0_esi          : integer := c_llc_frame_config_byte_0_ftyp - 1;         -- bit 3
  constant c_llc_frame_config_byte_0_brs          : integer := c_llc_frame_config_byte_0_esi - 1;          -- bit 2
  constant c_llc_frame_config_byte_0_ide          : integer := c_llc_frame_config_byte_0_format_start;     -- bit 7

  -- Config byte 1 bit positions: [7:4]=DLC
  constant c_llc_frame_config_byte_1_dlc_start : integer := c_byte_width - 1;                        -- bit 7
  constant c_llc_frame_config_byte_1_dlc_end   : integer := c_llc_frame_config_byte_1_dlc_start - 3; -- bit 4

  -- ID stream layout
  constant c_llc_id_byte_count   : integer := 4;
  constant c_llc_id_field_width : integer := c_llc_id_byte_count * c_byte_width;

  ---------------------------------------------------------------------------
  -- 9. Protocol Functions
  ---------------------------------------------------------------------------

  -- Calculate all frame-specific parameters once per frame (ISO 6.6.10, 6.6.11)
  function get_frame_params (
    metadata : t_llc_metadata
  ) return t_frame_params;

  -- Convert DLC to actual data length in bytes (ISO Table 5)
  function dlc_to_data_length (
    dlc        : t_dlc;
    can_format : std_logic_vector(2 downto 0)
  ) return integer;

  -- Return the next logical frame bit per protocol state (ISO 6.6.10, 6.6.11)
  function get_mac_frame_bit (
    bit_count         : t_position;
    ser_data          : std_logic;
    metadata          : t_llc_metadata;
    frame_params      : t_frame_params;
    previous_polarity : std_logic;
    sbc               : t_sbc;
    crc               : std_logic_vector(c_crc_21_length - 1 downto 0)
  ) return t_mac_frame_bit;

  -- Monitor transmitted bits for errors, ACK, and arbitration loss (ISO 6.6.5.1)
  function get_bit_info (
    bit_name               : t_mac_frame_bit_name;
    polarity_history       : t_tdc_polarity_history;
    tdc_delay              : integer range 0 to c_tdc_polarity_depth - 1;
    monitored_bit_polarity : std_logic;
    metadata               : t_llc_metadata
  ) return t_bit_info;


end package pk_can_types;

package body pk_can_types is

  function dlc_to_data_length (
    dlc        : t_dlc;
    can_format : std_logic_vector(2 downto 0)
  ) return integer is
  begin

    -- ISO 6.4.3: Table 5
    if (can_format(1) = '0') then
      return minimum(integer(dlc), 8);
    end if;

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

  end function dlc_to_data_length;

  function get_mac_frame_bit (
    bit_count         : t_position;
    ser_data          : std_logic;
    metadata          : t_llc_metadata;
    frame_params      : t_frame_params;
    previous_polarity : std_logic;
    sbc               : t_sbc;
    crc               : std_logic_vector(c_crc_21_length - 1 downto 0)
  ) return t_mac_frame_bit is

    variable pos_in_field : t_position;
    variable crc_offset_v : t_position;
    variable fsb_count_v  : t_position;

  begin

    -- Arbitration and control bits per format (ISO 11898-1, Figure 2)
    case metadata.format is
      when c_llc_fmt_cb =>
        if (bit_count = c_sof) then
          return c_sof_bit;
        elsif (bit_count >= c_cb_base_id_start and bit_count <= c_cb_base_id_stop) then
          return (bit_name => base_id_bit, polarity => ser_data);
        elsif (bit_count = c_cb_rtr) then
          return (bit_name => rtr_bit, polarity => metadata.ftyp);
        elsif (bit_count = c_cb_ide) then
          return (bit_name => ide_bit, polarity => c_dominant);
        elsif (bit_count = c_cb_r0) then
          return (bit_name => r0_bit, polarity => c_dominant);
        end if;

      when c_llc_fmt_ce =>
        if (bit_count = c_sof) then
          return c_sof_bit;
        elsif (bit_count >= c_cb_base_id_start and bit_count <= c_cb_base_id_stop) then
          return (bit_name => base_id_bit, polarity => ser_data);
        elsif (bit_count = c_ce_srr) then
          return (bit_name => srr_bit, polarity => c_recessive);
        elsif (bit_count = c_cb_ide) then
          return (bit_name => ide_bit, polarity => c_recessive);
        elsif (bit_count >= c_ce_extended_id_start and
               bit_count <= c_ce_extended_id_stop) then
          return (bit_name => extended_id_bit, polarity => ser_data);
        elsif (bit_count = c_ce_rtr) then
          return (bit_name => rtr_bit, polarity => metadata.ftyp);
        elsif (bit_count = c_ce_r1) then
          return (bit_name => r1_bit, polarity => c_dominant);
        elsif (bit_count = c_ce_r0) then
          return (bit_name => r0_bit, polarity => c_dominant);
        end if;

      when c_llc_fmt_fb =>
        if (bit_count = c_sof) then
          return c_sof_bit;
        elsif (bit_count >= c_cb_base_id_start and bit_count <= c_cb_base_id_stop) then
          return (bit_name => base_id_bit, polarity => ser_data);
        elsif (bit_count = c_fb_rrs) then
          return (bit_name => rrs_bit, polarity => c_dominant);
        elsif (bit_count = c_cb_ide) then
          return (bit_name => ide_bit, polarity => c_dominant);
        elsif (bit_count = c_fb_fdf) then
          return (bit_name => fdf_bit, polarity => c_recessive);
        elsif (bit_count = c_fb_res) then
          return (bit_name => res_bit, polarity => c_dominant);
        elsif (bit_count = c_fb_brs) then
          return (bit_name => brs_bit, polarity => metadata.brs);
        elsif (bit_count = c_fb_esi) then
          return (bit_name => esi_bit, polarity => metadata.esi);
        end if;

      when c_llc_fmt_fe =>
        if (bit_count = c_sof) then
          return c_sof_bit;
        elsif (bit_count >= c_cb_base_id_start and bit_count <= c_cb_base_id_stop) then
          return (bit_name => base_id_bit, polarity => ser_data);
        elsif (bit_count = c_ce_srr) then
          return (bit_name => srr_bit, polarity => c_recessive);
        elsif (bit_count = c_cb_ide) then
          return (bit_name => ide_bit, polarity => c_recessive);
        elsif (bit_count >= c_ce_extended_id_start and
               bit_count <= c_ce_extended_id_stop) then
          return (bit_name => extended_id_bit, polarity => ser_data);
        elsif (bit_count = c_fe_rrs) then
          return (bit_name => rrs_bit, polarity => c_dominant);
        elsif (bit_count = c_fe_fdf) then
          return (bit_name => fdf_bit, polarity => c_recessive);
        elsif (bit_count = c_fe_res) then
          return (bit_name => res_bit, polarity => c_dominant);
        elsif (bit_count = c_fe_brs) then
          return (bit_name => brs_bit, polarity => metadata.brs);
        elsif (bit_count = c_fe_esi) then
          return (bit_name => esi_bit, polarity => metadata.esi);
        end if;

      when others =>
        return c_reset_mac_frame_bit;
    end case;

    -- DLC field
    if (bit_count >= frame_params.dlc_start and
        bit_count < frame_params.dlc_start + c_dlc_field_width) then
      return (bit_name => dlc_bit,
              polarity => metadata.dlc(c_dlc_field_width - 1 -
                          (bit_count - frame_params.dlc_start)));
    end if;

    -- Data field
    if (bit_count >= frame_params.dlc_start + c_dlc_field_width and
        bit_count < frame_params.data_stop) then
      return (bit_name => data_bit, polarity => ser_data);
    end if;

    -- CRC region (ISO 6.6.13.3.1)
    -- CC: plain CRC-15, no stuff bits.
    -- FD: FSB + SBC(3..0) + [FSB + 4 CRC bits]... with a fixed stuff bit at
    -- every 5th position (pos_in_field mod 5 = 0).
    -- SBC bits occupy positions 1-4, CRC data follows from crc_start.
    if (bit_count >= frame_params.data_stop and bit_count < frame_params.crc_delimiter) then
      if (metadata.format(1) = '1') then -- FD format
        pos_in_field := bit_count - frame_params.data_stop;

        -- Fixed stuff bit at every 5th position (including the initial one)
        if ((pos_in_field mod c_stuff_width) = 0) then
          return (bit_name => fixed_stuff_bit, polarity => not previous_polarity);

        -- SBC region: positions 1-4 (between initial FSB and crc_start).
        -- pos_in_field - 1 compensates for the initial FSB at position 0.
        elsif (bit_count < frame_params.crc_start) then
          return (bit_name => sbs_bit,
                  polarity => sbc(c_sbc_field_width - 1 - (pos_in_field - 1)));

        -- CRC data: subtract interleaved FSBs to get the CRC vector index.
        else
          crc_offset_v := bit_count - frame_params.crc_start;
          fsb_count_v  := (c_sbc_field_width + crc_offset_v) / c_stuff_width;
          return (bit_name => crc_bit,
                  polarity => crc((c_crc_21_length - 1) +
                              fsb_count_v - crc_offset_v));
        end if;
      else
        -- CC: direct CRC-15 indexing, no stuff bits
        return (bit_name => crc_bit,
                polarity => crc(c_crc_21_length - 1 -
                            (bit_count - frame_params.crc_start)));
      end if;
    end if;

    -- CRC delimiter, ACK, EOF
    if (bit_count = frame_params.crc_delimiter) then
      return c_crc_delimiter_bit;
    elsif (bit_count = frame_params.crc_delimiter + c_ack_slot_offset) then
      return c_tx_ack_bit;
    elsif (bit_count = frame_params.crc_delimiter + c_ack_delimiter_offset) then
      return c_ack_delimiter_bit;
    elsif (bit_count >= frame_params.crc_delimiter + c_eof_start_offset and
           bit_count < frame_params.crc_delimiter + c_eof_start_offset +
           c_eof_field_width) then
      return c_eof_bit;
    end if;

    return c_reset_mac_frame_bit;

  end function get_mac_frame_bit;

  function get_frame_params (
    metadata : t_llc_metadata
  ) return t_frame_params is

    variable result        : t_frame_params;
    variable data_length_v : integer;
    variable crc_length_v  : integer;

  begin

    -- Calculate data length from DLC vector
    data_length_v := dlc_to_data_length(t_dlc(to_integer(unsigned(metadata.dlc))), metadata.format);

    -- ISO 6.6.10.1: Remote frames shall not contain a Data field
    if (metadata.ftyp = '1') then
      data_length_v := 0;
    end if;

    -- Look up DLC start from format constants
    case metadata.format is
      when c_llc_fmt_cb => result.dlc_start := c_cb_dlc_start;
      when c_llc_fmt_ce => result.dlc_start := c_ce_dlc_start;
      when c_llc_fmt_fb => result.dlc_start := c_fb_dlc_start;
      when c_llc_fmt_fe => result.dlc_start := c_fe_dlc_start;
      when others => result.dlc_start := 0;
    end case;

    result.data_stop := result.dlc_start + c_dlc_field_width +
                        data_length_v * c_byte_width;

    -- CRC length: CRC-15 for classic, CRC-17 for FD <= 16 bytes, CRC-21 otherwise
    if (metadata.format(1) = '0') then
      crc_length_v           := c_crc_15_length;
      result.crc_poly_select := c_crc_poly_15_sel;
    elsif (data_length_v < c_crc_17_length) then
      crc_length_v           := c_crc_17_length;
      result.crc_poly_select := c_crc_poly_17_sel;
    else
      crc_length_v           := c_crc_21_length;
      result.crc_poly_select := c_crc_poly_21_sel;
    end if;

    -- CAN FD has SBC field after data, CAN Classic goes directly to CRC
    -- ISO 6.6.13.3.1: FSB before SBC, then 4 SBC bits, then CRC with FSBs
    if (metadata.format(1) = '1') then
      result.dynamic_stuff_stop := result.data_stop;
      -- crc_start: skip initial FSB (+1) and 4 SBC data bits
      result.crc_start := result.data_stop + 1 + c_sbc_field_width;
      -- crc_delimiter = CRC delimiter position. From crc_start: crc_length data bits,
      -- 1 FSB at crc_start, plus floor((sbc_width + crc_length) / stuff_width)
      -- additional FSBs from the continuing every-5th-position pattern.
      result.crc_delimiter := result.crc_start + crc_length_v +
                              1 + ((c_sbc_field_width + crc_length_v) / c_stuff_width);
    else
      result.crc_start          := result.data_stop;
      result.crc_delimiter      := result.crc_start + crc_length_v;
      result.dynamic_stuff_stop := result.crc_delimiter;
    end if;

    return result;

  end function get_frame_params;

  function get_bit_info (
    bit_name               : t_mac_frame_bit_name;
    polarity_history       : t_tdc_polarity_history;
    tdc_delay              : integer range 0 to c_tdc_polarity_depth - 1;
    monitored_bit_polarity : std_logic;
    metadata               : t_llc_metadata
  ) return t_bit_info is

    -- Default assignment
    variable result : t_bit_info := c_reset_bit_info;

  begin

    -- ACK handling (ISO 6.6.10.6, 6.6.11.6)
    -- Returns ack_detected on dominant, none otherwise.
    if (bit_name = ack_bit or
        (metadata.format(1) = '1' and bit_name = ack_delimiter_bit)) then
      if (monitored_bit_polarity = c_dominant) then
        result.event_type := ack_detected;
      end if;
      return result;
    end if;

    -- Polarity match: no error (TDC delay handled via history index)
    if (polarity_history(tdc_delay) = monitored_bit_polarity) then
      return result;
    end if;

    -- Polarity mismatch: bit error or lost arbitration (ISO 6.6.21.2.a)
    result.event_type      := bit_error;
    result.transfer_status := c_disturbed;

    -- Override to lost arbitration when a recessive arbitration bit
    -- is observed as dominant (ISO 6.6.21.2.a, Exception 1).
    if (monitored_bit_polarity = c_dominant and
        ((bit_name = base_id_bit) or
          (bit_name = rtr_bit) or
          (metadata.format(2) = '1' and -- Extended format
            (bit_name = srr_bit or
              bit_name = ide_bit or
              bit_name = extended_id_bit)))) then
      result.event_type      := lost_arbitration;
      result.transfer_status := c_lost_arb;
    end if;

    return result;

  end function get_bit_info;

end package body pk_can_types;
