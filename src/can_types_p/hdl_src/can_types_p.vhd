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

  -- Post-CRC field offsets (used by TB stream model)
  constant c_ack_slot_offset  : natural := 1;
  constant c_eof_start_offset : natural := 3;


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
  -- 4. Composite Types
  ---------------------------------------------------------------------------

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

  ---------------------------------------------------------------------------
  -- 6. Interface Records
  -- Each record is followed by its reset constant.
  ---------------------------------------------------------------------------

  -- Avalon-ST streaming interface (matches company pk_eth_st)
  type t_eth_st_s2d is record
    data          :std_logic_vector(c_byte_width - 1 downto 0);
    valid         : std_logic;
    startofpacket : std_logic;
    endofpacket   : std_logic;
  end record t_eth_st_s2d;

  type t_eth_st_d2s is record
    ready : std_logic;
  end record t_eth_st_d2s;

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
    avalon_st_source : t_eth_st_s2d;
  end record t_can_llc_mac_rx_if_s2d;

  constant c_mac_rx_to_llc_if_reset : t_can_llc_mac_rx_if_s2d :=
  (
    avalon_st_source => (data => (others => '0'), valid => '0', startofpacket => '0', endofpacket => '0')
  );

  -- LLC RX -> MAC RX (destination to source, backpressure)
  type t_can_llc_mac_rx_if_d2s is record
    avalon_st_sink : t_eth_st_d2s;
  end record t_can_llc_mac_rx_if_d2s;

  constant c_llc_to_mac_rx_if_reset : t_can_llc_mac_rx_if_d2s :=
  (
    avalon_st_sink => (ready => '0')
  );

  -- LLC -> MAC
  type t_can_llc_mac_tx_if_s2d is record
    avalon_st_source : t_eth_st_s2d;
  end record t_can_llc_mac_tx_if_s2d;

  -- MAC -> LLC
  type t_can_llc_mac_tx_if_d2s is record
    avalon_st_sink  : t_eth_st_d2s;
    transfer_status : std_logic_vector(2 downto 0);
  end record t_can_llc_mac_tx_if_d2s;

  constant c_mac_to_llc_if_reset : t_can_llc_mac_tx_if_d2s :=
  (
    avalon_st_sink  => (ready => '1'),
    transfer_status => c_ongoing
  );

  -- User -> LLC
  type t_can_user_llc_tx_if_s2d is record
    avalon_st_source : t_eth_st_s2d;
    abort_request    : std_logic;
  end record t_can_user_llc_tx_if_s2d;

  -- LLC -> User
  type t_can_user_llc_tx_if_d2s is record
    avalon_st_sink  : t_eth_st_d2s;
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

  -- Convert DLC to actual data length in bytes (ISO Table 5)
  function dlc_to_data_length (dlc : natural; fdf : std_logic) return natural;

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

  -----------------------------------------------------------------
  -- Bus stream reference model: generates the expected bus bit
  -- sequence for a CAN/CAN-FD frame.
  -----------------------------------------------------------------

  -- Append a multi-bit field MSB-first
  procedure append (v : std_logic_vector; raw : inout std_logic_vector; raw_len : inOut natural) is
    variable va : std_logic_vector(v'length - 1 downto 0) := v;
  begin
    for i in va'length - 1 downto 0 loop
      raw(raw_len) := va(i);
      raw_len      := raw_len + 1;
    end loop;
  end procedure append;

  -- Append a single bit
  procedure append_bit (b : std_logic; raw : inOut std_logic_vector; raw_len : inOut natural) is
  begin
    raw(raw_len) := b;
    raw_len      := raw_len + 1;
  end procedure append_bit;

  -- Convenience record keeping track of the stuff state
  type t_stuff_state is record
    consec         : natural;              -- consecutive same-polarity bits (dynamic)
    last_pol       : std_logic;            -- last bit on the wire
    ds_count       : unsigned(2 downto 0); -- dynamic stuff bit count (for SBC)
    bits_since_fsb : natural;              -- real bits since last FSB (fixed)
    just_stuffed   : boolean;              -- last dyn call inserted a stuff bit
  end record;

  constant c_stuff_state_init : t_stuff_state := (
    consec         => 0,
    last_pol       => c_recessive,
    ds_count       => (others => '0'),
    bits_since_fsb => 0,
    just_stuffed   => false
  );

  -- Bit stuffing procedure
  -- fixed=false: 5-in-a-row (dynamic bit stuffing)
  -- fixed=true: 1 FSB per 4 real bits (fixed bit stuffing).
  procedure stuff_feed (pol : std_logic; fixed : boolean; st : inout t_stuff_state; stream : inout t_bus_stream) is
  begin
    if fixed then
      if st.bits_since_fsb mod (c_stuff_width - 1) = 0 then
        append_bit(not st.last_pol, stream.bits, stream.len);
        st.last_pol := not st.last_pol;
      end if;
      append_bit(pol, stream.bits, stream.len);
      st.last_pol       := pol;
      st.bits_since_fsb := st.bits_since_fsb + 1;
    else
      append_bit(pol, stream.bits, stream.len);
      if pol = st.last_pol then
        st.consec := st.consec + 1;
        if st.consec = c_stuff_width then
          append_bit(not pol, stream.bits, stream.len);
          st.consec       := 1;
          st.last_pol     := not pol;
          st.ds_count     := st.ds_count + 1;
          st.just_stuffed := true;
          return;
        end if;
      else
        st.consec   := 1;
        st.last_pol := pol;
      end if;
      st.just_stuffed := false;
    end if;
  end procedure stuff_feed;

  -- Dynamic->fixed boundary (ISO 6.6.13.3.1): drop a trailing dyn stuff bit so
  procedure enter_fixed_mode (st : inout t_stuff_state; stream : inout t_bus_stream) is
  begin
    if st.just_stuffed then
      stream.len  := stream.len - 1;
      st.ds_count := st.ds_count - 1;
      st.last_pol := stream.bits(stream.len - 1);
    end if;
  end procedure enter_fixed_mode;

  -- Classic CAN reference stream (ISO Figure 2):
  function build_cc_stream (frame : t_llc_frame; metadata : t_llc_metadata; is_passive : boolean := false) return t_bus_stream is
    type t_idx_map is array (natural range <>) of natural;
    variable raw         : std_logic_vector(0 to c_max_bus_bits - 1);
    variable raw_len     : natural := 0;
    variable arb_end_raw : natural;
    variable stream_idx  : t_idx_map(0 to c_max_bus_bits - 1);
    variable id_full     : std_logic_vector(c_base_id_width + c_extended_id_width - 1 downto 0);
    variable crc         : std_logic_vector(c_crc_15_length - 1 downto 0);
    variable result      : t_bus_stream;
    variable st          : t_stuff_state := c_stuff_state_init;
    variable tail_len    : natural;
  begin
    result.len              := 0;
    result.ack_pos          := 0;
    result.arb_end          := 0;
    result.fdf_pos          := -1;
    result.data_phase_start := -1;
    result.data_phase_end   := -1;

    id_full := frame(2) & frame(3) & frame(4) & frame(5)(c_byte_width - 1 downto c_byte_width - 5);

    -- SOF + base ID
    append_bit(c_dominant, raw, raw_len);
    append(id_full(id_full'high downto c_extended_id_width), raw, raw_len);

    if metadata.ide = '0' then
      -- CBFF: RTR, IDE=0, r0
      append_bit(metadata.ftyp, raw, raw_len);
      append_bit(c_dominant, raw, raw_len);
      append_bit(c_dominant, raw, raw_len);
      arb_end_raw := raw_len - 1;
    else
      -- CEFF: SRR, IDE=1, ext ID, RTR, r1, r0
      append_bit(c_recessive, raw, raw_len);
      append_bit(c_recessive, raw, raw_len);
      append(id_full(c_extended_id_width - 1 downto 0), raw, raw_len);
      append_bit(metadata.ftyp, raw, raw_len);
      append_bit(c_dominant, raw, raw_len);
      arb_end_raw := raw_len - 1;
      append_bit(c_dominant, raw, raw_len);
    end if;

    -- DLC + data
    append(frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end), raw, raw_len);
    for i in 0 to dlc_to_data_length(to_integer(unsigned(metadata.dlc)), '0') - 1 loop
      append(frame(c_llc_frame_data_byte + i), raw, raw_len);
    end loop;

    -- CRC-15 over SOF..data
    crc := f_calc_can_crc(raw(0 to raw_len - 1), c_crc_init_15_vec, c_crc_poly_15_vec);
    append(crc, raw, raw_len);

    -- Stuff raw onto the wire, recording raw->stream index mapping
    for i in 0 to raw_len - 1 loop
      stuff_feed(raw(i), false, st, result);
      stream_idx(i) := result.len - 1;
    end loop;

    -- Remap bookmarks into stream index
    result.arb_end := stream_idx(arb_end_raw);

    -- Tail: CRC delim + ACK + ACK delim + EOF + intermission [+ suspend]
    result.ack_pos := result.len + c_ack_slot_offset;
    tail_len := c_eof_start_offset + c_eof_field_width + c_intermission_width;
    if is_passive then
      tail_len := tail_len + c_suspend_transmission_width;
    end if;
    for i in 0 to tail_len - 1 loop
      append_bit(c_recessive, result.bits, result.len);
    end loop;

    return result;
  end function build_cc_stream;

  -- CAN-FD CAN reference stream (ISO Figure 2):
  function build_fd_stream (frame : t_llc_frame; metadata : t_llc_metadata; is_passive : boolean := false) return t_bus_stream is
    type t_idx_map is array (natural range <>) of natural;
    variable raw          : std_logic_vector(0 to c_max_bus_bits - 1);
    variable raw_len      : natural := 0;
    variable arb_end_raw  : natural;
    variable fdf_raw      : natural;
    variable brs_raw      : natural;
    variable stream_idx   : t_idx_map(0 to c_max_bus_bits - 1);
    variable id_full      : std_logic_vector(c_base_id_width + c_extended_id_width - 1 downto 0);
    variable fixed_raw    : std_logic_vector(0 to c_sbc_field_width + c_crc_21_length - 1);
    variable fixed_len    : natural;
    variable sbc          : std_logic_vector(c_sbc_field_width - 1 downto 0);
    variable result       : t_bus_stream;
    variable st           : t_stuff_state := c_stuff_state_init;
    variable tail_len     : natural;
  begin
    result.len              := 0;
    result.ack_pos          := 0;
    result.arb_end          := 0;
    result.fdf_pos          := -1;
    result.data_phase_start := -1;
    result.data_phase_end   := -1;

    id_full := frame(2) & frame(3) & frame(4) & frame(5)(c_byte_width - 1 downto c_byte_width - 5);

    -- SOF + base ID
    append_bit(c_dominant, raw, raw_len);
    append(id_full(id_full'high downto c_extended_id_width), raw, raw_len);

    if metadata.ide = '0' then
      -- FBFF: RRS, IDE=0, FDF=1, RES=0, BRS, ESI
      arb_end_raw := 1 + c_base_id_width;
      fdf_raw     := arb_end_raw + 2;
      brs_raw     := arb_end_raw + 4;
      append_bit(c_dominant, raw, raw_len);
      append_bit(c_dominant, raw, raw_len);
      append_bit(c_recessive, raw, raw_len);
      append_bit(c_dominant, raw, raw_len);
      append_bit(metadata.brs, raw, raw_len);
      append_bit(metadata.esi, raw, raw_len);
    else
      -- FEFF: SRR, IDE=1, ext ID, RRS, FDF=1, RES=0, BRS, ESI
      arb_end_raw := 1 + c_base_id_width + 2 + c_extended_id_width;
      fdf_raw     := arb_end_raw + 1;
      brs_raw     := arb_end_raw + 3;
      append_bit(c_recessive, raw, raw_len);
      append_bit(c_recessive, raw, raw_len);
      append(id_full(c_extended_id_width - 1 downto 0), raw, raw_len);
      append_bit(c_dominant, raw, raw_len);
      append_bit(c_recessive, raw, raw_len);
      append_bit(c_dominant, raw, raw_len);
      append_bit(metadata.brs, raw, raw_len);
      append_bit(metadata.esi, raw, raw_len);
    end if;

    -- DLC + data
    append(frame(1)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end), raw, raw_len);
    for i in 0 to dlc_to_data_length(to_integer(unsigned(metadata.dlc)), '1') - 1 loop
      append(frame(c_llc_frame_data_byte + i), raw, raw_len);
    end loop;

    -- Stuff SOF..data onto the wire, recording raw->stream index mapping
    for i in 0 to raw_len - 1 loop
      stuff_feed(raw(i), false, st, result);
      stream_idx(i) := result.len - 1;
    end loop;

    -- Remap bookmarks into stream index
    result.arb_end := stream_idx(arb_end_raw);
    result.fdf_pos := stream_idx(fdf_raw);
    if metadata.brs = '1' then
      result.data_phase_start := stream_idx(brs_raw);
    end if;

    -- Consume preceding stuff bit (ISO 6.6.13.3.1)
    enter_fixed_mode(st, result);

    -- SBC (6.6.11.5): Gray(ds_count) and parity
    sbc(c_sbc_field_width - 1 downto 1) := f_to_gray(std_logic_vector(st.ds_count));
    sbc(0)                               := f_calc_parity(sbc(c_sbc_field_width - 1 downto 1));

    -- Build fixed-region raw vector: SBC (MSB-first) & CRC (MSB-first).
    -- CRC-17 for < 16 data bytes, else CRC-21.
    fixed_len := 0;
    append(sbc, fixed_raw, fixed_len);
    if dlc_to_data_length(to_integer(unsigned(metadata.dlc)), metadata.fdf) < c_crc_17_length then
      append(f_calc_can_crc(result.bits(0 to result.len - 1) & sbc, c_crc_init_17_vec, c_crc_poly_17_vec), fixed_raw, fixed_len);
    else
      append(f_calc_can_crc(result.bits(0 to result.len - 1) & sbc, c_crc_init_21_vec, c_crc_poly_21_vec), fixed_raw, fixed_len);
    end if;

    -- Fixed stuffing of SBC & CRC (initial FSB + 1 FSB per 4 real bits)
    for i in 0 to fixed_len - 1 loop
      stuff_feed(fixed_raw(i), true, st, result);
    end loop;

    if result.data_phase_start >= 0 then
      result.data_phase_end := result.len - 1;
    end if;

    -- Tail: CRC delim + ACK + ACK delim + EOF + intermission [+ suspend]
    result.ack_pos := result.len + c_ack_slot_offset;
    tail_len := c_eof_start_offset + c_eof_field_width + c_intermission_width;
    if is_passive then
      tail_len := tail_len + c_suspend_transmission_width;
    end if;
    for i in 0 to tail_len - 1 loop
      append_bit(c_recessive, result.bits, result.len);
    end loop;

    return result;
  end function build_fd_stream;

  -- Dispatcher: pick CC vs FD based on metadata.fdf
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
