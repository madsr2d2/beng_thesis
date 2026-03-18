--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description: Centralized type and constant definitions for the CAN/CAN-FD design per ISO 11898-1:2015.
--
--              Section map (in order):
--                1. Protocol Constants       -- field widths, max sizes, CRC polynomials
--                2. Bit Timing Configuration -- ISO Table 13 subtypes
--                3. Core Enumerations        -- all enum types
--                4. Scalar Subtypes          -- byte_t, dlc_t, position_t, etc.
--                5. Composite Types          -- bit_t, mac_frame_bit_t, frame_params_t, FIFO
--                6. Frame Constants          -- bit positions for CB/CE/FB/FE on-wire frames
--                7. Interface Types          -- all _if_t records with reset constants
--                8. LLC frame format         -- FMT encodings, legacy frame layout, config byte bit positions
--             
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-15  TMYAES:   [TRIT-4336] Initial implementation
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

  -- Bus polarity
  constant c_dominant  : std_logic := '0';
  constant c_recessive : std_logic := '1';

  -- Field widths
  constant c_byte_width      : integer := 8;
  constant c_dlc_field_width : integer := 4;
  constant c_sbc_field_width : integer := 4;
  constant c_stuff_width     : integer := 5;
  constant c_base_id_width   : integer := 11;
  constant c_extended_id_width       : integer := 18;
  constant c_eof_field_width         : integer := 7;
  constant c_error_flag_width        : integer := 6;
  constant c_error_delimiter_width   : integer := 8;
  constant c_intermission_width      : integer := 3;    -- ISO 6.6.7.2
  constant c_suspend_transmission_width : integer := 8;  -- ISO 6.6.7.4
  constant c_bus_idle_condition_width : integer := 11;   -- ISO 3.34

  -- Frame limits
  constant c_sof               : integer := 0;
  constant c_dlc_max           : integer := 15;
  constant c_max_data_bytes    : integer := 64;
  constant c_max_mac_frame_length : integer := 640; -- TODO: Calculate this number correctly

  -- CRC polynomials and initial values (ISO 8.5.4)
  constant c_crc_15_length   : integer := 15;
  constant c_crc_17_length   : integer := 17;
  constant c_crc_21_length   : integer := 21;
  constant c_crc_poly_15_vec : std_logic_vector(c_crc_15_length - 1 downto 0) := 15x"4599";
  constant c_crc_poly_17_vec : std_logic_vector(c_crc_17_length - 1 downto 0) := 17x"1685B";
  constant c_crc_poly_21_vec : std_logic_vector(c_crc_21_length - 1 downto 0) := 21x"102899";
  constant c_crc_init_15_vec : std_logic_vector(c_crc_15_length - 1 downto 0) := (others => '0');
  constant c_crc_init_17_vec : std_logic_vector(c_crc_17_length - 1 downto 0) := '1' & (c_crc_17_length - 2 downto 0 => '0');
  constant c_crc_init_21_vec : std_logic_vector(c_crc_21_length - 1 downto 0) := '1' & (c_crc_21_length - 2 downto 0 => '0');

  -- Transfer status encoding
  constant c_ongoing     : std_logic_vector(2 downto 0) := "000";
  constant c_transmitted : std_logic_vector(2 downto 0) := "010";
  constant c_aborted     : std_logic_vector(2 downto 0) := "001";
  constant c_lost_arb    : std_logic_vector(2 downto 0) := "100";
  constant c_disturbed   : std_logic_vector(2 downto 0) := "110";

  -- FMT field encodings (3-bit, config byte 0 bits [7:5] / legacy byte 4 bits [6:4])
  constant c_llc_fmt_cb : std_logic_vector(2 downto 0) := "000"; -- Classic Basic
  constant c_llc_fmt_ce : std_logic_vector(2 downto 0) := "100"; -- Classic Extended
  constant c_llc_fmt_fb : std_logic_vector(2 downto 0) := "010"; -- FD Basic
  constant c_llc_fmt_fe : std_logic_vector(2 downto 0) := "110"; -- FD Extended

  -- FIFO
  constant c_transmitted_bits_fifo_depth : integer := 32; -- TODO: Think about the size requirements on this fifo. 32 is probably larger than necessary.

  -- Retransmission (ISO 6.4)
  constant c_retransmission_limit : integer := 6;

  -- Derived vector subtypes
  subtype t_mac_frame_position_vec is std_logic_vector(integer(ceil(log2(real(c_max_mac_frame_length)))) - 1 downto 0);
  subtype t_fifo_index_vec is std_logic_vector(integer(ceil(log2(real(c_transmitted_bits_fifo_depth)))) - 1 downto 0);

  ---------------------------------------------------------------------------
  -- 2. Bit Timing (ISO Table 12)
  ---------------------------------------------------------------------------
  constant c_sync_seg              : integer := 1;
  constant c_max_transmitter_delay : integer := 255; -- ISO 7.3.4
  constant c_tdc_bit_time_max      : integer := 1000; -- ISO 7.3.4

  subtype t_prescaler        is integer range 1 to 32;
  subtype t_nominal_prop_seg is integer range 0 to 96;
  subtype t_data_prop_seg    is integer range 0 to 8;
  subtype t_nominal_phase_seg1 is integer range 1 to 32;
  subtype t_data_phase_seg1    is integer range 1 to 8;
  subtype t_nominal_phase_seg2 is integer range 2 to 32;
  subtype t_data_phase_seg2    is integer range 2 to 8;
  subtype t_nominal_sjw is integer range 1 to 32;
  subtype t_data_sjw    is integer range 1 to 8;
  subtype t_ssp_offset  is integer range 1 to 63;

  ---------------------------------------------------------------------------
  -- 3. Enumerations
  ---------------------------------------------------------------------------
  type t_mac_frame_bit_name is (
    -- Error and overload flags
    active_error_flag_bit,
    passive_error_flag_bit,
    overload_flag_bit,
    -- Inter-frame spacing
    bus_integration_bit,
    intermission_bit,
    suspend_transmission_bit,
    idle_bit,
    -- Classic CAN fields
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
    -- CAN-FD additions
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

  type t_tx_mac_monitor_event is (
    none,
    ack_detected,
    ack_error,
    bit_error,
    lost_arbitration
  );

  ---------------------------------------------------------------------------
  -- 4. Scalar Subtypes
  ---------------------------------------------------------------------------
  subtype t_bit_count   is integer range 0 to c_max_mac_frame_length;
  subtype t_position    is integer range 0 to c_max_mac_frame_length;
  subtype t_byte        is std_logic_vector(c_byte_width - 1 downto 0);
  subtype t_dlc         is integer range 0 to c_dlc_max;
  subtype t_stuff_count is unsigned(2 downto 0);
  subtype t_sbc         is std_logic_vector(c_sbc_field_width - 1 downto 0);
  subtype t_crc_vector  is std_logic_vector(c_crc_poly_21_vec'left downto 0);
  subtype t_fifo_write_ptr is integer range 0 to c_transmitted_bits_fifo_depth - 1;

  ---------------------------------------------------------------------------
  -- 5. Composite Types
  ---------------------------------------------------------------------------
  type t_bit is record
    position : integer;
    polarity : std_logic;
  end record t_bit;

  type t_mac_frame_bit is record
    polarity : std_logic;
    bit_name : t_mac_frame_bit_name;
  end record t_mac_frame_bit;

  constant c_reset_mac_frame_bit : t_mac_frame_bit := (polarity => c_recessive, bit_name => unknown);

  type t_observed_mac_frame_bit_info is record
    event_type        : t_tx_mac_monitor_event;
    transfer_status   : std_logic_vector(2 downto 0);
    expected_bit      : t_mac_frame_bit;
    observed_polarity : std_logic;
  end record t_observed_mac_frame_bit_info;

  constant c_reset_observed_mac_frame_bit_info : t_observed_mac_frame_bit_info :=
  (
    event_type        => none,
    transfer_status   => c_ongoing,
    expected_bit      => c_reset_mac_frame_bit,
    observed_polarity => c_recessive
  );

  type t_transmitted_bits_fifo is array (c_transmitted_bits_fifo_depth - 1 downto 0) of t_mac_frame_bit;

  -- Frame parameters, calculated once per frame by the serializer
  type t_frame_params is record
    format          : std_logic_vector(2 downto 0);
    dlc_vector      : std_logic_vector(c_dlc_field_width - 1 downto 0);
    is_remote_frame : std_logic;
    has_brs         : std_logic;
    esi_enable      : std_logic;

    data_start        : t_mac_frame_position_vec;
    data_stop         : t_mac_frame_position_vec;
    crc_start     : t_mac_frame_position_vec;
    crc_delimiter : t_mac_frame_position_vec;
    sbc_start     : t_mac_frame_position_vec;
    crc_poly_select : std_logic_vector(1 downto 0);
  end record t_frame_params;

  constant c_frame_params_reset : t_frame_params :=
  (
    format            => c_llc_fmt_cb,
    dlc_vector        => (others => '0'),
    is_remote_frame   => '0',
    has_brs           => '0',
    esi_enable        => '0',
    data_start        => (others => '0'),
    data_stop         => (others => '0'),
    crc_start         => (others => '0'),
    crc_delimiter     => (others => '0'),
    sbc_start         => (others => '0'),
    crc_poly_select   => "00"
  );

  ---------------------------------------------------------------------------
  -- 6. Frame Bit Positions (ISO 11898-1 Figure 2)
  --
  -- Fixed-polarity bit constants and per-format field position chains.
  ---------------------------------------------------------------------------

  -- Common fixed-polarity bits
  constant c_sof_bit                  : t_mac_frame_bit := (c_dominant,  sof_bit);
  constant c_tx_ack_bit               : t_mac_frame_bit := (c_recessive, ack_bit);
  constant c_ack_delimiter_bit        : t_mac_frame_bit := (c_recessive, ack_delimiter_bit);
  constant c_crc_delimiter_bit        : t_mac_frame_bit := (c_recessive, crc_delimiter_bit);
  constant c_eof_bit                  : t_mac_frame_bit := (c_recessive, eof_bit);
  constant c_active_error_flag_bit    : t_mac_frame_bit := (c_dominant,  active_error_flag_bit);
  constant c_passive_error_flag_bit   : t_mac_frame_bit := (c_recessive, passive_error_flag_bit);
  constant c_error_delimiter_bit      : t_mac_frame_bit := (c_recessive, error_delimiter_bit);
  constant c_overload_flag_bit        : t_mac_frame_bit := (c_dominant,  overload_flag_bit);
  constant c_intermission_bit         : t_mac_frame_bit := (c_recessive, intermission_bit);
  constant c_suspend_transmission_bit : t_mac_frame_bit := (c_recessive, suspend_transmission_bit);
  constant c_bus_integration_bit      : t_mac_frame_bit := (c_recessive, bus_integration_bit);
  constant c_idle_bit                 : t_mac_frame_bit := (c_recessive, idle_bit);

  -- CAN Classic Basic (CB)
  constant c_cb_base_id_start : t_bit := (c_sof + 1, c_dominant);
  constant c_cb_base_id_stop  : t_bit := (c_cb_base_id_start.position + c_base_id_width - 1, c_recessive);
  constant c_cb_rtr           : t_bit := (c_cb_base_id_stop.position + 1, c_recessive);
  constant c_cb_ide           : t_bit := (c_cb_rtr.position + 1, c_dominant);
  constant c_cb_r0            : t_bit := (c_cb_ide.position + 1, c_dominant);
  constant c_cb_dlc_start     : t_bit := (c_cb_r0.position + 1, c_recessive);
  constant c_cb_dlc_stop      : t_bit := (c_cb_dlc_start.position + c_dlc_field_width - 1, c_recessive);
  constant c_cb_data_start    : t_bit := (c_cb_dlc_stop.position + 1, c_recessive);

  -- CAN Classic Extended (CE)
  constant c_ce_base_id_start     : t_bit := (c_sof + 1, c_recessive);
  constant c_ce_base_id_stop      : t_bit := (c_ce_base_id_start.position + c_base_id_width - 1, c_recessive);
  constant c_ce_srr               : t_bit := (c_ce_base_id_stop.position + 1, c_recessive);
  constant c_ce_ide               : t_bit := (c_ce_srr.position + 1, c_recessive);
  constant c_ce_extended_id_start : t_bit := (c_ce_ide.position + 1, c_recessive);
  constant c_ce_extended_id_stop  : t_bit := (c_ce_extended_id_start.position + c_extended_id_width - 1, c_recessive);
  constant c_ce_rtr               : t_bit := (c_ce_extended_id_stop.position + 1, c_recessive);
  constant c_ce_r1                : t_bit := (c_ce_rtr.position + 1, c_dominant);
  constant c_ce_r0                : t_bit := (c_ce_r1.position + 1, c_dominant);
  constant c_ce_dlc_start         : t_bit := (c_ce_r0.position + 1, c_recessive);
  constant c_ce_dlc_stop          : t_bit := (c_ce_dlc_start.position + c_dlc_field_width - 1, c_recessive);
  constant c_ce_data_start        : t_bit := (c_ce_dlc_stop.position + 1, c_recessive);

  -- CAN FD Basic (FB)
  constant c_fd_base_id_start : t_bit := (c_sof + 1, c_recessive);
  constant c_fd_base_id_stop  : t_bit := (c_fd_base_id_start.position + c_base_id_width - 1, c_recessive);
  constant c_fb_rrs           : t_bit := (c_fd_base_id_stop.position + 1, c_dominant);
  constant c_fb_ide           : t_bit := (c_fb_rrs.position + 1, c_dominant);
  constant c_fb_fdf           : t_bit := (c_fb_ide.position + 1, c_recessive);
  constant c_fb_res           : t_bit := (c_fb_fdf.position + 1, c_dominant);
  constant c_fb_brs           : t_bit := (c_fb_res.position + 1, c_recessive);
  constant c_fb_esi           : t_bit := (c_fb_brs.position + 1, c_recessive);
  constant c_fb_dlc_start     : t_bit := (c_fb_esi.position + 1, c_recessive);
  constant c_fb_dlc_stop      : t_bit := (c_fb_dlc_start.position + c_dlc_field_width - 1, c_recessive);
  constant c_fb_data_start    : t_bit := (c_fb_dlc_stop.position + 1, c_recessive);

  -- CAN FD Extended (FE)
  constant c_fe_base_id_start     : t_bit := (c_sof + 1, c_recessive);
  constant c_fe_base_id_stop      : t_bit := (c_fe_base_id_start.position + c_base_id_width - 1, c_recessive);
  constant c_fe_srr               : t_bit := (c_fe_base_id_stop.position + 1, c_recessive);
  constant c_fe_ide               : t_bit := (c_fe_srr.position + 1, c_recessive);
  constant c_fe_extended_id_start : t_bit := (c_fe_ide.position + 1, c_recessive);
  constant c_fe_extended_id_stop  : t_bit := (c_fe_extended_id_start.position + c_extended_id_width - 1, c_recessive);
  constant c_fe_rrs               : t_bit := (c_fe_extended_id_stop.position + 1, c_dominant);
  constant c_fe_fdf               : t_bit := (c_fe_rrs.position + 1, c_recessive);
  constant c_fe_res               : t_bit := (c_fe_fdf.position + 1, c_dominant);
  constant c_fe_brs               : t_bit := (c_fe_res.position + 1, c_recessive);
  constant c_fe_esi               : t_bit := (c_fe_brs.position + 1, c_recessive);
  constant c_fe_dlc_start         : t_bit := (c_fe_esi.position + 1, c_recessive);
  constant c_fe_dlc_stop          : t_bit := (c_fe_dlc_start.position + c_dlc_field_width - 1, c_recessive);
  constant c_fe_data_start        : t_bit := (c_fe_dlc_stop.position + 1, c_recessive);

  ---------------------------------------------------------------------------
  -- 7. Interface Records
  --
  -- Naming: t_can_<src>_<dst>_<layer>_if_<direction>
  -- Each record is followed by its reset constant.
  ---------------------------------------------------------------------------

  -- Serializer -> FSM
  type t_can_mac_ser_fsm_tx_if_s2m is record
    data         : std_logic;
    valid        : std_logic;
    frame_params : t_frame_params;
  end record t_can_mac_ser_fsm_tx_if_s2m;

  constant c_tx_mac_ser_to_fsm_if_reset : t_can_mac_ser_fsm_tx_if_s2m :=
  (
    data         => c_recessive,
    valid        => '0',
    frame_params => c_frame_params_reset
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

  -- LLC -> MAC (downstream)
  type t_can_llc_mac_tx_if_s2d is record
    avalon_st_source : pk_eth_st.t_eth_st_s2d;
  end record t_can_llc_mac_tx_if_s2d;

  -- MAC -> LLC (upstream)
  type t_can_llc_mac_tx_if_d2s is record
    avalon_st_sink  : pk_eth_st.t_eth_st_d2s;
    transfer_status : std_logic_vector(2 downto 0);
  end record t_can_llc_mac_tx_if_d2s;

  constant c_mac_to_llc_if_reset : t_can_llc_mac_tx_if_d2s :=
  (
    avalon_st_sink  => (ready => '0'),
    transfer_status => c_ongoing
  );

  -- User -> LLC
  type t_can_user_llc_tx_if_s2d is record
    avalon_st_source : pk_eth_st.t_eth_st_s2d;
    abort_request    : std_logic;
  end record t_can_user_llc_tx_if_s2d;

  -- LLC -> User
  type t_can_user_llc_tx_if_d2s is record
    avalon_st_sink  :  pk_eth_st.t_eth_st_d2s;
    transfer_status : std_logic_vector(2 downto 0);
  end record t_can_user_llc_tx_if_d2s;

  -- MAC -> PCS (PCS_Data.Request, ISO 7.2)
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

  -- PCS -> MAC (PCS_Data.Indicate, ISO 7.2)
  type t_can_mac_pcs_tx_if_s2m is record
    bus_polarity : std_logic;
    sp           : std_logic;
    ssp          : std_logic;
    fifo_index   : t_fifo_index_vec;
  end record t_can_mac_pcs_tx_if_s2m;

  constant c_pcs_to_mac_if_reset : t_can_mac_pcs_tx_if_s2m :=
  (
    bus_polarity => c_recessive,
    sp           => '0',
    ssp          => '0',
    fifo_index   => (others => '0')
  );

  -- FSM -> Bit Stuffer
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

  -- Bit Stuffer -> FSM
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

  -- FSM -> CRC
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
    crc : t_crc_vector;
  end record t_can_mac_fsm_crc_tx_if_s2m;

  -- MAC -> FCE (ISO Table 16/17)
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

  -- FCE -> MAC
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
  --   Byte 0:       [7:5]=FMT, [4]=FTYP(RTR), [3]=ESI, [2]=BRS, [1:0]=00
  --   Byte 1:       [7:4]=DLC, [3:0]=0000
  --   Bytes 2-5:    ID (32-bit, MSB first, left-aligned; CB uses [31:21])
  --   Bytes 6+:     Data (DLC count, no padding), EOP on last byte
  --
  -- Legacy format (fixed 71 bytes, presented at user interface):
  --   Bytes 0-3:  ID bytes
  --   Byte  4:    [7]=reserved, [6:4]=FMT, [3:0]=DLC
  --   Bytes 5-68: Data (zero-padded to 64)
  --   Byte  69:   [0]=IDE
  --   Byte  70:   [2]=BRS, [1]=ESI, [0]=RTR
  ---------------------------------------------------------------------------

  -- Config byte 0: [7:5]=FMT, [4]=FTYP(RTR), [3]=ESI, [2]=BRS, [1:0]=00
  type t_llc_config_byte_0 is record
    format : std_logic_vector(2 downto 0);
    ftyp   : std_logic;
    esi    : std_logic;
    brs    : std_logic;
    unused : std_logic_vector(1 downto 0);
  end record t_llc_config_byte_0;

  -- Config byte 1: [7:4]=DLC, [3:0]=0000
  type t_llc_config_byte_1 is record
    dlc    : std_logic_vector(3 downto 0);
    unused : std_logic_vector(3 downto 0);
  end record t_llc_config_byte_1;

  -- Internal LLC frame (testbench convenience type)
  type t_llc_frame is record
    config_0 : t_llc_config_byte_0;
    config_1 : t_llc_config_byte_1;
    id       : std_logic_vector(31 downto 0);
    data     : std_logic_vector(c_max_data_bytes * 8 - 1 downto 0);
  end record t_llc_frame;

  -- Legacy frame constants
  constant c_legacy_frame_len    : integer := 71;
  constant c_legacy_fmt_dlc_byte : integer := 4;
  constant c_legacy_data_offset  : integer := 5;
  constant c_legacy_flags_byte   : integer := 70;

  type t_legacy_frame is array (0 to c_legacy_frame_len - 1) of t_byte;

  -- Internal config byte 0 bit positions
  constant c_llc_frame_config_byte_0_format_start : integer := c_byte_width - 1;                           -- bit 7
  constant c_llc_frame_config_byte_0_format_end   : integer := c_llc_frame_config_byte_0_format_start - 2; -- bit 5
  constant c_llc_frame_config_byte_0_ftyp         : integer := c_llc_frame_config_byte_0_format_end - 1;   -- bit 4
  constant c_llc_frame_config_byte_0_esi          : integer := c_llc_frame_config_byte_0_ftyp - 1;         -- bit 3
  constant c_llc_frame_config_byte_0_brs          : integer := c_llc_frame_config_byte_0_esi - 1;          -- bit 2
  constant c_llc_frame_config_byte_0_extended_bit : integer := c_llc_frame_config_byte_0_format_start;     -- bit 7

  -- Internal config byte 1 bit positions
  constant c_llc_frame_config_byte_1_dlc_start : integer := c_byte_width - 1;                        -- bit 7
  constant c_llc_frame_config_byte_1_dlc_end   : integer := c_llc_frame_config_byte_1_dlc_start - 3; -- bit 4

  -- ID stream layout
  constant c_llc_id_byte_count   : integer := 4;
  constant c_llc_id_stream_width : integer := c_llc_id_byte_count * c_byte_width;

end package pk_can_types;


-- eof
