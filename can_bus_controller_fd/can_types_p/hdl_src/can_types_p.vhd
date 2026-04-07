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
--                4. Composite Types      -- mac_frame_bit, frame_params, metadata
--                5. Frame Bit Positions  -- CB/CE/FB/FE on-wire field chains
--                6. Interface Records    -- inter-layer records with reset constants
--                7. LLC Frame Format     -- config bytes, legacy layout
--                8. Protocol Functions   -- frame params, bitstream, DLC, ID packing
--                9. TB Utility Functions -- CRC calc, metadata extraction (TB-only)
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
  constant c_byte_width        : natural := 8;
  constant c_base_id_width     : natural := 11; -- ISO 6.6.10.2
  constant c_extended_id_width : natural := 18; -- ISO 6.6.10.2
  constant c_dlc_field_width   : natural := 4;  -- ISO 6.6.10.3, Table 5
  constant c_eof_field_width   : natural := 7;  -- ISO 6.6.10.7, 6.6.11.7

  -- Bit stuffing (ISO 6.6.13.2, Table 10)
  constant c_stuff_width     : natural := 5;
  constant c_sbc_field_width : natural := 4; -- ISO 6.6.11.5, Table 8

  -- Post-CRC field offsets (relative to crc_delimiter position)
  constant c_ack_slot_offset      : natural := 1; -- ISO 6.6.10.6, 6.6.11.6
  constant c_ack_delimiter_offset : natural := 2;
  constant c_eof_start_offset     : natural := 3;

  -- Error signalling (ISO 6.6.5.2, 6.6.5.3)
  constant c_error_flag_width      : natural := 6;
  constant c_error_delimiter_width : natural := 8;
  constant c_error_sequence_width  : natural := c_error_flag_width + c_error_delimiter_width;

  -- Inter-frame spacing (ISO 6.6.7)
  constant c_intermission_width         : natural := 3;   -- ISO 6.6.7.2
  constant c_suspend_transmission_width : natural := 8;   -- ISO 6.6.7.4
  constant c_bus_idle_condition_width   : natural := 11;  -- ISO 6.6.7.5
  constant c_bus_off_recovery_count     : natural := 128; -- ISO 8.1.4.4

  -- Frame limits
  constant c_sof                  : natural := 0;
  constant c_dlc_max              : natural := 15; -- ISO Table 5
  constant c_max_data_bytes       : natural := 64; -- ISO 6.6.11.4
  constant c_max_mac_frame_length : natural := 640;

  -- CRC polynomials and initial values (ISO 6.6.4.4)
  constant c_crc_15_length   : natural                                        := 15;
  constant c_crc_17_length   : natural                                        := 17;
  constant c_crc_21_length   : natural                                        := 21;
  constant c_crc_poly_15_vec : std_logic_vector(c_crc_15_length - 1 downto 0) := 15x"4599";
  constant c_crc_poly_17_vec : std_logic_vector(c_crc_17_length - 1 downto 0) := 17x"1685B";
  constant c_crc_poly_21_vec : std_logic_vector(c_crc_21_length - 1 downto 0) := 21x"102899";
  constant c_crc_init_15_vec : std_logic_vector(c_crc_15_length - 1 downto 0) := (others => '0');
  constant c_crc_init_17_vec : std_logic_vector(c_crc_17_length - 1 downto 0) := '1' & (c_crc_17_length - 2 downto 0 => '0');
  constant c_crc_init_21_vec : std_logic_vector(c_crc_21_length - 1 downto 0) := '1' & (c_crc_21_length - 2 downto 0 => '0');
  constant c_crc_poly_15_sel : std_logic_vector(1 downto 0)                   := "00";
  constant c_crc_poly_17_sel : std_logic_vector(1 downto 0)                   := "01";
  constant c_crc_poly_21_sel : std_logic_vector(1 downto 0)                   := "10";

  -- Transfer status encoding (ISO 6.5.3, Table 7)
  constant c_ongoing     : std_logic_vector(2 downto 0) := "000";
  constant c_transmitted : std_logic_vector(2 downto 0) := "010";
  constant c_aborted     : std_logic_vector(2 downto 0) := "001";
  constant c_lost_arb    : std_logic_vector(2 downto 0) := "100";
  constant c_disturbed   : std_logic_vector(2 downto 0) := "110";

  -- TDC polarity history depth (ISO 7.3.4)
  constant c_tdc_polarity_depth : natural := 32;

  -- Retransmission (ISO 6.5.3)
  constant c_retransmission_limit : natural := 6;

  ---------------------------------------------------------------------------
  -- 2. Bit Timing (ISO 7.3.2, Table 12)
  ---------------------------------------------------------------------------

  constant c_sync_seg              : natural := 1;    -- ISO 7.3.2
  constant c_max_transmitter_delay : natural := 255;  -- ISO 7.3.4
  constant c_tdc_bit_time_max      : natural := 1000; -- ISO 7.3.4

  subtype t_prescaler is natural range 1 to 32;
  subtype t_nominal_prop_seg is natural range 0 to 96;
  subtype t_data_prop_seg is natural range 0 to 8;
  subtype t_nominal_phase_seg1 is natural range 1 to 32;
  subtype t_data_phase_seg1 is natural range 1 to 8;
  subtype t_nominal_phase_seg2 is natural range 2 to 32;
  subtype t_data_phase_seg2 is natural range 2 to 8;
  subtype t_ssp_offset is natural range 1 to 63;

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
  -- 4. Composite Types
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

  -- LLC frame metadata (ISO 6.4.3 Table 4):
  type t_llc_metadata is record
    ide  : std_logic;
    fdf  : std_logic;
    dlc  : std_logic_vector(c_dlc_field_width - 1 downto 0);
    ftyp : std_logic;
    brs  : std_logic;
    esi  : std_logic;
  end record t_llc_metadata;

  constant c_llc_metadata_reset : t_llc_metadata :=
  (
    ide  => '0',
    fdf  => '0',
    dlc  => (others => '0'),
    ftyp => '0',
    brs  => '0',
    esi  => '0'
  );

  -- Frame positions: derived bit-count thresholds, calculated once per frame.
  type t_frame_params is record
    dlc_start          : natural range 0 to c_max_mac_frame_length;
    data_stop          : natural range 0 to c_max_mac_frame_length;
    dynamic_stuff_stop : natural range 0 to c_max_mac_frame_length;
    crc_start          : natural range 0 to c_max_mac_frame_length;
    crc_delimiter      : natural range 0 to c_max_mac_frame_length;
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
  -- 5. Frame Bit Positions
  -- Fixed-polarity bits constants and per-format field positions.
  -- ISO Figure 2 field ordering.
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
  constant c_cb_base_id_start : natural := c_sof + 1;
  constant c_cb_base_id_stop  : natural := c_cb_base_id_start + c_base_id_width - 1;
  constant c_cb_rtr           : natural := c_cb_base_id_stop + 1;
  constant c_cb_ide           : natural := c_cb_rtr + 1;
  constant c_cb_r0            : natural := c_cb_ide + 1;
  constant c_cb_dlc_start     : natural := c_cb_r0 + 1;
  constant c_cb_dlc_stop      : natural := c_cb_dlc_start + c_dlc_field_width - 1;
  constant c_cb_data_start    : natural := c_cb_dlc_stop + 1;

  -- CAN Classic Extended (CEFF) positions (ISO 6.6.10)
  constant c_ce_base_id_start     : natural := c_sof + 1;
  constant c_ce_base_id_stop      : natural := c_ce_base_id_start + c_base_id_width - 1;
  constant c_ce_srr               : natural := c_ce_base_id_stop + 1;
  constant c_ce_ide               : natural := c_ce_srr + 1;
  constant c_ce_extended_id_start : natural := c_ce_ide + 1;
  constant c_ce_extended_id_stop  : natural := c_ce_extended_id_start + c_extended_id_width - 1;
  constant c_ce_rtr               : natural := c_ce_extended_id_stop + 1;
  constant c_ce_r1                : natural := c_ce_rtr + 1;
  constant c_ce_r0                : natural := c_ce_r1 + 1;
  constant c_ce_dlc_start         : natural := c_ce_r0 + 1;
  constant c_ce_dlc_stop          : natural := c_ce_dlc_start + c_dlc_field_width - 1;
  constant c_ce_data_start        : natural := c_ce_dlc_stop + 1;

  -- CAN FD Basic (FBFF) positions (ISO 6.6.11)
  constant c_fd_base_id_start : natural := c_sof + 1;
  constant c_fd_base_id_stop  : natural := c_fd_base_id_start + c_base_id_width - 1;
  constant c_fb_rrs           : natural := c_fd_base_id_stop + 1;
  constant c_fb_ide           : natural := c_fb_rrs + 1;
  constant c_fb_fdf           : natural := c_fb_ide + 1;
  constant c_fb_res           : natural := c_fb_fdf + 1;
  constant c_fb_brs           : natural := c_fb_res + 1;
  constant c_fb_esi           : natural := c_fb_brs + 1;
  constant c_fb_dlc_start     : natural := c_fb_esi + 1;
  constant c_fb_dlc_stop      : natural := c_fb_dlc_start + c_dlc_field_width - 1;
  constant c_fb_data_start    : natural := c_fb_dlc_stop + 1;

  -- CAN FD Extended (FEFF) positions (ISO 6.6.11)
  constant c_fe_base_id_start     : natural := c_sof + 1;
  constant c_fe_base_id_stop      : natural := c_fe_base_id_start + c_base_id_width - 1;
  constant c_fe_srr               : natural := c_fe_base_id_stop + 1;
  constant c_fe_ide               : natural := c_fe_srr + 1;
  constant c_fe_extended_id_start : natural := c_fe_ide + 1;
  constant c_fe_extended_id_stop  : natural := c_fe_extended_id_start + c_extended_id_width - 1;
  constant c_fe_rrs               : natural := c_fe_extended_id_stop + 1;
  constant c_fe_fdf               : natural := c_fe_rrs + 1;
  constant c_fe_res               : natural := c_fe_fdf + 1;
  constant c_fe_brs               : natural := c_fe_res + 1;
  constant c_fe_esi               : natural := c_fe_brs + 1;
  constant c_fe_dlc_start         : natural := c_fe_esi + 1;
  constant c_fe_dlc_stop          : natural := c_fe_dlc_start + c_dlc_field_width - 1;
  constant c_fe_data_start        : natural := c_fe_dlc_stop + 1;

  ---------------------------------------------------------------------------
  -- 6. Interface Records
  -- Each record is followed by its reset constant.
  ---------------------------------------------------------------------------
  -- Serializer -> FSM
  type t_can_mac_ser_fsm_if_s2d is record
    data         : std_logic;
    valid        : std_logic;
    llc_metadata : t_llc_metadata;
  end record t_can_mac_ser_fsm_if_s2d;

  constant c_ser_fsm_if_s2d_reset : t_can_mac_ser_fsm_if_s2d :=
  (
    data         => 'U',
    valid        => '0',
    llc_metadata => c_llc_metadata_reset
  );

  -- FSM -> Serializer
  type t_can_mac_ser_fsm_if_d2s is record
    transfer_status : std_logic_vector(2 downto 0);
    ready           : std_logic;
  end record t_can_mac_ser_fsm_if_d2s;

  constant c_ser_fsm_if_d2s_reset : t_can_mac_ser_fsm_if_d2s :=
  (
    transfer_status => c_ongoing,
    ready           => '0'
  );

  -- MAC RX -> LLC RX (source to destination, Avalon-ST byte stream)
  type t_can_llc_mac_rx_if_s2d is record
    avalon_st_source : pk_eth_st.t_eth_st_s2d;
  end record t_can_llc_mac_rx_if_s2d;

  constant c_mac_rx_to_llc_if_reset : t_can_llc_mac_rx_if_s2d :=
  (
    avalon_st_source => (data => (others => '0'), valid => '0', startofpacket => '0', endofpacket => '0')
  );

  -- LLC RX -> MAC RX (destination to source, backpressure)
  type t_can_llc_mac_rx_if_d2s is record
    avalon_st_sink : pk_eth_st.t_eth_st_d2s;
  end record t_can_llc_mac_rx_if_d2s;

  constant c_llc_to_mac_rx_if_reset : t_can_llc_mac_rx_if_d2s :=
  (
    avalon_st_sink => (ready => '0')
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
  type t_can_mac_pcs_if_m2s is record
    polarity      : std_logic;
    valid         : std_logic;
    use_data_rate : std_logic;
    start_tdc     : std_logic;
  end record t_can_mac_pcs_if_m2s;

  constant c_mac_to_pcs_if_reset : t_can_mac_pcs_if_m2s :=
  (
    polarity      => c_recessive,
    valid         => '0',
    use_data_rate => '0',
    start_tdc     => '0'
  );

  -- PCS -> MAC (ISO 7.2, PCS_Data.Indicate)
  type t_can_mac_pcs_if_s2m is record
    bus_polarity : std_logic;
    sp           : std_logic;
    ssp          : std_logic;
    tdc_delay    : std_logic_vector(integer(ceil(log2(real(c_tdc_polarity_depth)))) - 1 downto 0);
  end record t_can_mac_pcs_if_s2m;

  constant c_pcs_to_mac_if_reset : t_can_mac_pcs_if_s2m :=
  (
    bus_polarity => c_recessive,
    sp           => '0',
    ssp          => '0',
    tdc_delay    => (others => '0')
  );

  -- FSM -> Bit Stuffer (ISO 6.6.13)
  type t_can_mac_fsm_bs_if_m2s is record
    data  : std_logic;
    valid : std_logic;
    fsb_en: std_logic;
  end record t_can_mac_fsm_bs_if_m2s;

  constant c_mac_fsm_to_bs_fd_if_reset : t_can_mac_fsm_bs_if_m2s :=
  (
    data  => c_recessive,
    valid => '0',
    fsb_en => '0'
  );

  -- Bit Stuffer -> FSM (ISO 6.6.13)
  type t_can_mac_fsm_bs_if_s2m is record
    data  : std_logic;
    valid : std_logic;
    sbc   : std_logic_vector(c_sbc_field_width - 1 downto 0);
  end record t_can_mac_fsm_bs_if_s2m;

  constant c_can_mac_fsm_bs_if_s2m_reset : t_can_mac_fsm_bs_if_s2m :=
  (
    data  => c_recessive,
    valid => '0',
    sbc   => (others => '0')
  );

  -- FSM -> CRC (ISO 6.6.4.4)
  type t_can_mac_fsm_crc_if_m2s is record
    crc_poly_select : std_logic_vector(1 downto 0);
    valid_cc           : std_logic;
    valid_fd        : std_logic;
    data_cc         : std_logic;
    data_fd         : std_logic;
  end record t_can_mac_fsm_crc_if_m2s;

  constant c_mac_fsm_to_crc_if_reset : t_can_mac_fsm_crc_if_m2s :=
  (
    crc_poly_select => (others => '0'),
    valid_cc           => '0',
    valid_fd        => '0',
    data_cc         => '0',
    data_fd         => '0'
  );

  -- CRC -> FSM
  type t_can_mac_fsm_crc_if_s2m is record
    crc : std_logic_vector(c_crc_21_length - 1 downto 0);
  end record t_can_mac_fsm_crc_if_s2m;

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
  end record t_can_mac_fce_if_s2m;

  constant c_fce_to_mac_if_reset : t_can_mac_fce_if_s2m :=
  (
    error_passive_request => '0',
    error_active_request  => '1'
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
  -- 7. LLC Frame Format
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
  constant c_internal_llc_frame_len : natural := 70;
  constant c_conf_0_offset : natural := 0;
  constant c_conf_1_offset : natural := 1;
  constant c_id_offset : natural := 2;
  constant c_data_offset : natural := 6;

  type     t_llc_frame is array (0 to c_internal_llc_frame_len - 1) of std_logic_vector(c_byte_width - 1 downto 0);

  -- Legacy frame
  constant c_legacy_frame_len    : natural := 71;
  constant c_legacy_fmt_dlc_byte : natural := 4;
  constant c_legacy_data_offset  : natural := 5;

  type t_legacy_frame is array (0 to c_legacy_frame_len - 1) of std_logic_vector(c_byte_width - 1 downto 0);

  -- Config byte 0 bit positions: [7]=IDE, [6]=FDF, [5]=reserved, [4]=FTYP, [3]=ESI, [2]=BRS
  constant c_llc_frame_ide  : natural := 7;
  constant c_llc_frame_fdf  : natural := 6;
  constant c_llc_frame_ftyp : natural := 4;
  constant c_llc_frame_esi  : natural := 3;
  constant c_llc_frame_brs  : natural := 2;

  -- Config byte 1 bit positions: [7:4]=DLC
  constant c_llc_frame_dlc_start : natural := 7;
  constant c_llc_frame_dlc_end   : natural := 4;
  -- First data byte in the internal LLC frame (2 config bytes + 4 ID bytes)
  constant c_llc_frame_data_byte : natural := 6;
  -- ID stream layout
  constant c_llc_id_byte_count  : natural := 4;
  constant c_llc_id_field_width : natural := c_llc_id_byte_count * c_byte_width;

  ---------------------------------------------------------------------------
  -- 8. Protocol Functions
  ---------------------------------------------------------------------------

  -- Calculate all frame-specific parameters once per frame (ISO 6.6.10, 6.6.11)
  function get_frame_params (metadata : t_llc_metadata) return t_frame_params;

  -- Convert DLC to actual data length in bytes (ISO Table 5)
  function dlc_to_data_length (dlc : natural; fdf : std_logic) return natural;

  -- Return the next logical frame bit per protocol state (ISO 6.6.10, 6.6.11)
  function get_mac_frame_bit (
    bit_count         : natural;
    ser_data          : std_logic;
    metadata          : t_llc_metadata;
    frame_params      : t_frame_params;
    sbc               : std_logic_vector;
    crc               : std_logic_vector
  ) return t_mac_frame_bit;

  -- Monitor transmitted bits for errors, ACK, and arbitration loss (ISO 6.6.5.1)
  function get_bit_info (
    bit_name               : t_mac_frame_bit_name;
    polarity_history       : std_logic_vector;
    tdc_delay              : natural;
    monitored_bit_polarity : std_logic;
    metadata               : t_llc_metadata
  ) return t_bit_info;

  -- Pack LLC frame ID field into canonical byte stream order ID3..ID0
  function pack_llc_id_bytes (id : std_logic_vector; ide : std_logic) return std_logic_vector;

  -- Binary-to-Gray conversion (ISO 6.6.11.5: Stuff Bit Count encoding)
  function f_to_gray (v : std_logic_vector) return std_logic_vector;

  -- XOR parity over a vector (ISO 6.6.11.5: SBC parity bit)
  function f_calc_parity ( v : std_logic_vector) return std_logic;

  ---------------------------------------------------------------------------
  -- 10. Testbench Utility Functions
  ---------------------------------------------------------------------------

  -- CRC calculation per ISO 11898-1: 6.6.4.4 (Galois LFSR)
  function f_calc_can_crc (data : std_logic_vector; init_vec : std_logic_vector; poly : std_logic_vector) return std_logic_vector;

  -- Extract LLC metadata from config bytes 0 and 1
  function extract_metadata (config_byte_0 :std_logic_vector; config_byte_1 :std_logic_vector) return t_llc_metadata;

  -- Bus stream reference model: generates expected CAN bus bitstream from LLC frame
  constant c_max_bus_bits : natural := 1024;

  type t_bus_stream is record
    bits             : std_logic_vector(0 to c_max_bus_bits - 1);
    len              : integer;
    ack_pos          : integer;
    arb_end          : integer;
    fdf_pos          : integer;
    data_phase_start : integer;
    data_phase_end   : integer;
  end record t_bus_stream;

  procedure append (v : std_logic_vector; raw : inout std_logic_vector; raw_len : inout natural);
  procedure append_bit (b : std_logic; raw : inOut std_logic_vector; raw_len : inOut natural);
  procedure emit (pol : std_logic; stream : inOut t_bus_stream);
  procedure dynamic_bit_stuffer_feed (pol : std_logic; consec : inOut natural; last_pol : inOut std_logic; ds_count : inOut unsigned(2 downto 0); stream : inOut t_bus_stream);

  function build_cc_stream (frame : t_llc_frame; metadata : t_llc_metadata; is_passive : boolean := false) return t_bus_stream;
  function build_fd_stream (frame : t_llc_frame; metadata : t_llc_metadata; is_passive : boolean := false) return t_bus_stream;
  function build_bus_stream (frame : t_llc_frame; metadata : t_llc_metadata; is_passive : boolean := false) return t_bus_stream;

end package pk_can_types;

package body pk_can_types is

  function dlc_to_data_length (dlc : natural; fdf : std_logic) return natural is
  begin
    -- ISO 6.4.3: Table 5
    if (fdf = '0') then
      return dlc;
    end if;

    case dlc is
      when 0 to 8 => return natural(dlc);
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
    bit_count         : natural;
    ser_data          : std_logic;
    metadata          : t_llc_metadata;
    frame_params      : t_frame_params;
    sbc               : std_logic_vector;
    crc               : std_logic_vector
  ) return t_mac_frame_bit is
  begin
    -- Arbitration and control bits per format (ISO 11898-1, Figure 2)
    if (metadata.ide = '0' and metadata.fdf = '0') then
      -- Classic Basic (CB)
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
    elsif (metadata.ide = '1' and metadata.fdf = '0') then
      -- Classic Extended (CE)
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
    elsif (metadata.ide = '0' and metadata.fdf = '1') then
      -- FD Basic (FB)
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
    elsif (metadata.ide = '1' and metadata.fdf = '1') then
      -- FD Extended (FE)
      if (bit_count = c_sof) then
        return c_sof_bit;
      elsif (bit_count >= c_cb_base_id_start and bit_count <= c_cb_base_id_stop) then
        return (bit_name => base_id_bit, polarity => ser_data);
      elsif (bit_count = c_ce_srr) then
        return (bit_name => srr_bit, polarity => c_recessive);
      elsif (bit_count = c_cb_ide) then
        return (bit_name => ide_bit, polarity => c_recessive);
      elsif (bit_count >= c_ce_extended_id_start and bit_count <= c_ce_extended_id_stop) then
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
    else
      return c_reset_mac_frame_bit;
    end if;

    -- DLC field
    if (bit_count >= frame_params.dlc_start and bit_count < frame_params.dlc_start + c_dlc_field_width) then
      return (bit_name => dlc_bit, polarity => metadata.dlc(c_dlc_field_width - 1 - (bit_count - frame_params.dlc_start)));
    end if;

    -- Data field
    if (bit_count >= frame_params.dlc_start + c_dlc_field_width and bit_count < frame_params.data_stop) then
      return (bit_name => data_bit, polarity => ser_data);
    end if;

    -- SBC field (FD only, ISO 6.6.11.5): between data_stop and crc_start.
    if (metadata.fdf = '1' and bit_count >= frame_params.data_stop and bit_count < frame_params.crc_start) then
      return (bit_name => sbs_bit, polarity => sbc((c_sbc_field_width - 1) - (bit_count - frame_params.data_stop)));
    end if;

    -- CRC field (CC and FD): direct indexing, no FSB offsets
    if (bit_count >= frame_params.crc_start and bit_count < frame_params.crc_delimiter) then
      return (bit_name => crc_bit, polarity => crc((c_crc_21_length - 1) - (bit_count - frame_params.crc_start)));
    end if;

    -- CRC delimiter, ACK, EOF
    if (bit_count = frame_params.crc_delimiter) then
      return c_crc_delimiter_bit;
    elsif (bit_count = frame_params.crc_delimiter + c_ack_slot_offset) then
      return c_tx_ack_bit;
    elsif (bit_count = frame_params.crc_delimiter + c_ack_delimiter_offset) then
      return c_ack_delimiter_bit;
    elsif (bit_count >= (frame_params.crc_delimiter + c_eof_start_offset) and bit_count < (frame_params.crc_delimiter + c_eof_start_offset + c_eof_field_width)) then
      return c_eof_bit;
    end if;

    return c_reset_mac_frame_bit;
  end function get_mac_frame_bit;

  function get_frame_params ( metadata : t_llc_metadata) return t_frame_params is
    variable v_result        : t_frame_params;
    variable v_data_length : natural;
    variable v_crc_length  : natural;
  begin
    -- Calculate data length from DLC vector
    v_data_length := dlc_to_data_length(to_integer(unsigned(metadata.dlc)), metadata.fdf);
    -- Look up DLC start from format constants
    if (metadata.ide = '0' and metadata.fdf = '0') then
      v_result.dlc_start := c_cb_dlc_start;
    elsif (metadata.ide = '1' and metadata.fdf = '0') then
      v_result.dlc_start := c_ce_dlc_start;
    elsif (metadata.ide = '0' and metadata.fdf = '1') then
      v_result.dlc_start := c_fb_dlc_start;
    elsif (metadata.ide = '1' and metadata.fdf = '1') then
      v_result.dlc_start := c_fe_dlc_start;
    else
      v_result.dlc_start := 0;
    end if;

    v_result.data_stop := v_result.dlc_start + c_dlc_field_width + v_data_length * c_byte_width;

    -- CRC length: CRC-15 for classic, CRC-17 for FD <= 16 bytes, CRC-21 otherwise
    if (metadata.fdf = '0') then
      v_crc_length           := c_crc_15_length;
      v_result.crc_poly_select := c_crc_poly_15_sel;
    elsif (v_data_length < c_crc_17_length) then
      v_crc_length           := c_crc_17_length;
      v_result.crc_poly_select := c_crc_poly_17_sel;
    else
      v_crc_length           := c_crc_21_length;
      v_result.crc_poly_select := c_crc_poly_21_sel;
    end if;

    -- CAN FD has SBC field after data, CAN Classic goes directly to CRC
    -- ISO 6.6.13.3.1: FSB before SBC, then 4 SBC bits, then CRC with FSBs
    if (metadata.fdf = '1') then
      v_result.dynamic_stuff_stop := v_result.data_stop;
      -- SBC field immediately follows data (FSBs handled by can_mac_bs)
      v_result.crc_start := v_result.data_stop + c_sbc_field_width;
      v_result.crc_delimiter := v_result.crc_start + v_crc_length;
    else
      v_result.crc_start          := v_result.data_stop;
      v_result.crc_delimiter      := v_result.crc_start + v_crc_length;
      v_result.dynamic_stuff_stop := v_result.crc_delimiter;
    end if;
    return v_result;
  end function get_frame_params;

  function get_bit_info (
    bit_name               : t_mac_frame_bit_name;
    polarity_history       : std_logic_vector;
    tdc_delay              : natural;
    monitored_bit_polarity : std_logic;
    metadata               : t_llc_metadata
  ) return t_bit_info is
    -- Default assignment
    variable v_result : t_bit_info := c_reset_bit_info;
  begin
    -- ACK handling (ISO 6.6.10.6, 6.6.11.6)
    -- Returns ack_detected on dominant, none otherwise.
    if (bit_name = ack_bit or (metadata.fdf = '1' and bit_name = ack_delimiter_bit)) then
      if (monitored_bit_polarity = c_dominant) then
        v_result.event_type := ack_detected;
      end if;
      return v_result;
    end if;

    -- Polarity match: no error (TDC delay handled via history index)
    if (polarity_history(tdc_delay) = monitored_bit_polarity) then
      return v_result;
    end if;

    -- If get to here we have polarity mismatch:
    -- bit error or lost arbitration (ISO 6.6.21.2.a)
    v_result.event_type      := bit_error;
    v_result.transfer_status := c_disturbed;

    -- Override to lost arbitration when a recessive arbitration bit
    -- is observed as dominant (ISO 6.6.21.2.a, Exception 1).
    if monitored_bit_polarity = c_dominant and
        (((bit_name = base_id_bit) or (bit_name = rtr_bit)) or
          (metadata.ide = '1' and (bit_name = srr_bit or bit_name = ide_bit or bit_name = extended_id_bit))) then
      v_result.event_type      := lost_arbitration;
      v_result.transfer_status := c_lost_arb;
    end if;
    return v_result;
  end function get_bit_info;

  function pack_llc_id_bytes (id : std_logic_vector; ide : std_logic) return std_logic_vector is
    variable v_result : std_logic_vector(31 downto 0);
  begin
    v_result := (others => '0');
    if (ide = '1') then
      v_result(31 downto 3) := id(28 downto 0);
    else
      v_result(31 downto 21) := id(10 downto 0);
    end if;
    return v_result;
  end function pack_llc_id_bytes;

  function f_to_gray (v : std_logic_vector) return std_logic_vector is
    variable v_result : std_logic_vector(v'range);
  begin
    v_result(v'left) := v(v'left);
    for i in v'left - 1 downto v'right loop
      v_result(i) := v(i) xor v(i + 1);
    end loop;
    return v_result;
  end function f_to_gray;

  function f_calc_parity (v : std_logic_vector) return std_logic is
    variable v_parity : std_logic := '0';
  begin
    for i in v'range loop
      v_parity := v_parity xor v(i);
    end loop;
    return v_parity;
  end function f_calc_parity;

  -- Algorithm from ISO 6.6.4.4 
  function f_calc_can_crc (data : std_logic_vector; init_vec : std_logic_vector; poly : std_logic_vector) return std_logic_vector is
    variable v_crc      : std_logic_vector(init_vec'length - 1 downto 0);
    variable v_crc_next : std_logic;
  begin
    v_crc := init_vec;
    for i in data'range loop
      v_crc_next := data(i) xor v_crc(v_crc'high);
      v_crc      := v_crc sll 1;
      if (v_crc_next) then
        v_crc := v_crc xor poly;
      end if;
    end loop;
    return v_crc;
  end function f_calc_can_crc;

  function extract_metadata (config_byte_0 :std_logic_vector; config_byte_1 :std_logic_vector) return t_llc_metadata is
    variable v_result : t_llc_metadata;
  begin
    v_result.ide  := config_byte_0(c_llc_frame_ide);
    v_result.fdf  := config_byte_0(c_llc_frame_fdf);
    v_result.ftyp := config_byte_0(c_llc_frame_ftyp);
    v_result.esi  := config_byte_0(c_llc_frame_esi);
    v_result.brs  := config_byte_0(c_llc_frame_brs);
    v_result.dlc  := config_byte_1(c_llc_frame_dlc_start downto c_llc_frame_dlc_end);
    return v_result;
  end function extract_metadata;

  ---------------------------------------------------------------------------
  -- Bus stream reference model helpers
  ---------------------------------------------------------------------------
  procedure append (v : std_logic_vector; raw : inout std_logic_vector; raw_len : inOut natural) is
    variable va : std_logic_vector(v'length - 1 downto 0) := v;
  begin
    for i in va'length - 1 downto 0 loop
      raw(raw_len) := va(i);
      raw_len      := raw_len + 1;
    end loop;
  end procedure append;

  procedure append_bit (b : std_logic; raw : inOut std_logic_vector; raw_len : inOut natural) is
  begin
    raw(raw_len) := b;
    raw_len      := raw_len + 1;
  end procedure append_bit;

  procedure emit (pol : std_logic; stream : inOut t_bus_stream) is
  begin
    stream.bits(stream.len) := pol;
    stream.len              := stream.len + 1;
  end procedure emit;

  procedure dynamic_bit_stuffer_feed (pol : std_logic; consec : inOut natural; last_pol : inOut std_logic; ds_count : inOut unsigned(2 downto 0); stream : inOut t_bus_stream) is
  begin
    emit(pol, stream);
    if pol = last_pol then
      consec := consec + 1;
      if consec = c_stuff_width then
        emit(not pol, stream);
        consec    := 1;
        last_pol  := not pol;
        ds_count  := ds_count + 1;
      end if;
    else
      consec   := 1;
      last_pol := pol;
    end if;
  end procedure dynamic_bit_stuffer_feed;

  ---------------------------------------------------------------------------
  -- build_cc_stream: build raw fields -> CRC-15 -> stuff -> tail
  ---------------------------------------------------------------------------
  function build_cc_stream (frame : t_llc_frame; metadata : t_llc_metadata; is_passive : boolean := false) return t_bus_stream is
    variable raw         : std_logic_vector(0 to c_max_bus_bits - 1);
    variable raw_len     : natural := 0;
    variable arb_end_raw : natural;
    variable id_full     : std_logic_vector(c_llc_id_field_width - 1 downto 0);
    variable crc         : std_logic_vector(c_crc_15_length - 1 downto 0);
    variable result      : t_bus_stream;
    variable consec      : natural range 0 to c_stuff_width := 0;
    variable last_pol    : std_logic := c_recessive;
    variable ds_count    : unsigned(2 downto 0) := (others => '0');
    variable arb_done    : boolean := false;
    variable tail_len    : natural;
  begin
    result.len              := 0;
    result.ack_pos          := 0;
    result.arb_end          := 0;
    result.fdf_pos          := -1;
    result.data_phase_start := -1;
    result.data_phase_end   := -1;

    id_full := frame(2) & frame(3) & frame(4) & frame(5);
    append_bit(c_dominant, raw, raw_len);
    append(id_full(c_llc_id_field_width - 1 downto (c_llc_id_field_width - c_base_id_width)), raw, raw_len);

    if metadata.ide = '0' then
      append_bit(metadata.ftyp, raw, raw_len);
      append_bit(c_dominant, raw, raw_len);
      append_bit(c_dominant, raw, raw_len);
      arb_end_raw := raw_len - 1;
    else
      append_bit(c_recessive, raw, raw_len);
      append_bit(c_recessive, raw, raw_len);
      append(id_full(c_llc_id_field_width - 1 - c_base_id_width downto
                     c_llc_id_field_width - c_base_id_width - c_extended_id_width), raw, raw_len);
      append_bit(metadata.ftyp, raw, raw_len);
      append_bit(c_dominant, raw, raw_len);
      arb_end_raw := raw_len - 1;
      append_bit(c_dominant, raw, raw_len);
    end if;

    append(frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end), raw, raw_len);
    for i in 0 to dlc_to_data_length(to_integer(unsigned(metadata.dlc)), '0') - 1 loop
      append(frame(c_llc_frame_data_byte + i), raw, raw_len);
    end loop;

    crc := f_calc_can_crc(raw(0 to raw_len - 1), c_crc_init_15_vec, c_crc_poly_15_vec);
    append(crc, raw, raw_len);

    for i in 0 to raw_len - 1 loop
      dynamic_bit_stuffer_feed(raw(i), consec, last_pol, ds_count, result);
      if not arb_done and i = arb_end_raw then
        result.arb_end := result.len - 1;
        arb_done       := true;
      end if;
    end loop;

    result.ack_pos := result.len + c_ack_slot_offset;
    tail_len := c_eof_start_offset + c_eof_field_width + c_intermission_width;
    if is_passive then
      tail_len := tail_len + c_suspend_transmission_width;
    end if;
    for i in 0 to tail_len - 1 loop
      emit(c_recessive, result);
    end loop;

    return result;
  end function build_cc_stream;

  ---------------------------------------------------------------------------
  -- build_fd_stream: build raw fields -> stuff -> SBC -> CRC -> FSB -> tail
  ---------------------------------------------------------------------------
  function build_fd_stream (frame : t_llc_frame; metadata : t_llc_metadata; is_passive : boolean := false) return t_bus_stream is
    variable raw          : std_logic_vector(0 to c_max_bus_bits - 1);
    variable raw_len      : natural := 0;
    variable arb_end_raw  : natural;
    variable fdf_raw      : natural;
    variable esi_raw      : natural;
    variable id_full      : std_logic_vector(c_llc_id_field_width - 1 downto 0);
    variable frame_params : t_frame_params;
    variable crc          : std_logic_vector(c_crc_21_length - 1 downto 0) := (others => '0');
    variable crc_len_nat  : natural;
    variable sbc          : std_logic_vector(c_sbc_field_width - 1 downto 0);
    variable gray         : std_logic_vector(2 downto 0);
    variable crc_input    : std_logic_vector(0 to c_max_bus_bits - 1);
    variable crc_in_len   : natural;
    variable stuffed_len  : natural;
    variable payload      : std_logic_vector(0 to c_sbc_field_width + c_crc_21_length - 1);
    variable pi           : natural;
    variable result       : t_bus_stream;
    variable consec       : natural range 0 to c_stuff_width := 0;
    variable last_pol     : std_logic := c_recessive;
    variable ds_count     : unsigned(2 downto 0) := (others => '0');
    variable arb_done     : boolean := false;
    variable tail_len     : natural;
    variable fsb_pos      : natural;
    variable pre_last_len : natural;
  begin
    result.len              := 0;
    result.ack_pos          := 0;
    result.arb_end          := 0;
    result.fdf_pos          := -1;
    result.data_phase_start := -1;
    result.data_phase_end   := -1;

    id_full := frame(2) & frame(3) & frame(4) & frame(5);
    append_bit(c_dominant, raw, raw_len);
    append(id_full(c_llc_id_field_width - 1 downto c_llc_id_field_width - c_base_id_width), raw, raw_len);

    if metadata.ide = '0' then
      arb_end_raw := c_fb_rrs;
      fdf_raw     := c_fb_fdf;
      esi_raw     := c_fb_esi;
      append_bit(c_dominant, raw, raw_len);
      append_bit(c_dominant, raw, raw_len);
      append_bit(c_recessive, raw, raw_len);
      append_bit(c_dominant, raw, raw_len);
      append_bit(metadata.brs, raw, raw_len);
      append_bit(metadata.esi, raw, raw_len);
    else
      arb_end_raw := c_fe_rrs;
      fdf_raw     := c_fe_fdf;
      esi_raw     := c_fe_esi;
      append_bit(c_recessive, raw, raw_len);
      append_bit(c_recessive, raw, raw_len);
      append(id_full(c_llc_id_field_width - 1 - c_base_id_width downto
                     c_llc_id_field_width - c_base_id_width - c_extended_id_width), raw, raw_len);
      append_bit(c_dominant, raw, raw_len);
      append_bit(c_recessive, raw, raw_len);
      append_bit(c_dominant, raw, raw_len);
      append_bit(metadata.brs, raw, raw_len);
      append_bit(metadata.esi, raw, raw_len);
    end if;

    append(frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end), raw, raw_len);
    for i in 0 to dlc_to_data_length(to_integer(unsigned(metadata.dlc)), '1') - 1 loop
      append(frame(c_llc_frame_data_byte + i), raw, raw_len);
    end loop;

    for i in 0 to raw_len - 1 loop
      pre_last_len := result.len;
      dynamic_bit_stuffer_feed(raw(i), consec, last_pol, ds_count, result);
      if not arb_done and i = arb_end_raw then
        result.arb_end := result.len - 1;
        arb_done       := true;
      end if;
      if i = fdf_raw then
        result.fdf_pos := result.len - 1;
      end if;
      if i = esi_raw and metadata.brs = '1' then
        result.data_phase_start := result.len - 1;
      end if;
    end loop;

    -- ISO 6.6.13.3.1: if the last data bit triggered a dynamic stuff bit,
    -- suppress it - "there shall be only the fixed stuff bit, there shall
    -- not be two consecutive stuff bits."
    if result.len - pre_last_len = 2 then
      result.len := result.len - 1;
      ds_count   := ds_count - 1;
      last_pol   := result.bits(result.len - 1);
    end if;

    stuffed_len := result.len;

    gray := f_to_gray(std_logic_vector(ds_count));
    sbc  := gray & f_calc_parity(gray);

    frame_params := get_frame_params(metadata);
    crc_input(0 to stuffed_len - 1) := result.bits(0 to stuffed_len - 1);
    crc_in_len := stuffed_len;
    for i in c_sbc_field_width - 1 downto 0 loop
      crc_input(crc_in_len) := sbc(i);
      crc_in_len            := crc_in_len + 1;
    end loop;

    case frame_params.crc_poly_select is
      when "01" =>
        crc_len_nat := c_crc_17_length;
        crc(c_crc_21_length - 1 downto c_crc_21_length - c_crc_17_length) :=
          f_calc_can_crc(crc_input(0 to crc_in_len - 1), c_crc_init_17_vec, c_crc_poly_17_vec);
      when others =>
        crc_len_nat := c_crc_21_length;
        crc         :=
          f_calc_can_crc(crc_input(0 to crc_in_len - 1), c_crc_init_21_vec, c_crc_poly_21_vec);
    end case;
    -- Debug: REF FD CRC trace (disabled for speed)

    for i in 0 to c_sbc_field_width - 1 loop
      payload(i) := sbc(c_sbc_field_width - 1 - i);
    end loop;
    for i in 0 to crc_len_nat - 1 loop
      payload(c_sbc_field_width + i) := crc(c_crc_21_length - 1 - i);
    end loop;

    pi      := 0;
    fsb_pos := 0;
    while pi < c_sbc_field_width + crc_len_nat loop
      if fsb_pos mod c_stuff_width = 0 then
        emit(not last_pol, result);
        last_pol := not last_pol;
      else
        emit(payload(pi), result);
        last_pol := payload(pi);
        pi       := pi + 1;
      end if;
      fsb_pos := fsb_pos + 1;
    end loop;

    if result.data_phase_start >= 0 then
      result.data_phase_end := result.len - 1;
    end if;

    result.ack_pos := result.len + c_ack_slot_offset;
    tail_len := c_eof_start_offset + c_eof_field_width + c_intermission_width;
    if is_passive then
      tail_len := tail_len + c_suspend_transmission_width;
    end if;
    for i in 0 to tail_len - 1 loop
      emit(c_recessive, result);
    end loop;

    return result;
  end function build_fd_stream;

  ---------------------------------------------------------------------------
  -- build_bus_stream: stream dispatcher
  ---------------------------------------------------------------------------
  function build_bus_stream (frame : t_llc_frame; metadata : t_llc_metadata; is_passive : boolean := false) return t_bus_stream is
  begin
    if metadata.fdf = '1' then
      return build_fd_stream(frame, metadata, is_passive);
    else
      return build_cc_stream(frame, metadata, is_passive);
    end if;
  end function build_bus_stream;

end package body pk_can_types;

-- eof
