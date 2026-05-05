--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:  
--
-- Description:   Centralized types, constants, and protocol functions for the
--                CAN/CAN-FD design per ISO 11898-1:2015.
--                
--                Section map:
--                1. Protocol Constants   -- polarity, field widths, CRC, status
--                2. Bit Timing           -- ISO Table 12 subtypes and limits
--                4. Composite Types      -- mac_frame_bit, frame_params, metadata
--                6. Interface Records    -- inter-layer records with reset constants
--                7. LLC Frame Format     -- config bytes, legacy layout
--                8. Protocol Functions   -- frame params, bitstream, DLC, ID packing
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-15  TMYAES:   [TRIT-4336] [FPGA] CAN FD extensions of TRIT-3880
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
  constant c_base_id_width     : natural := 11;                                 -- ISO 6.6.10.2
  constant c_extended_id_width : natural := 18;                                 -- ISO 6.6.10.2
  constant c_dlc_field_width   : natural := 4;                                  -- ISO 6.6.10.3, Table 5
  constant c_eof_field_width   : natural := 7;                                  -- ISO 6.6.10.7, 6.6.11.7

  -- Bit stuffing (ISO 6.6.13.2, Table 10)
  constant c_stuff_width     : natural := 5;
  constant c_sbc_field_width : natural := 4;                                    -- ISO 6.6.11.5, Table 8

  -- Post-CRC field offsets (used by TB stream model).
  -- CC: CRC_delim(1) + ACK_slot(1) + ACK_delim(1) = 3 before EOF.
  -- FD: CRC_delim(1) + ACK_slot(2) + ACK_delim(1) = 4 before EOF (ISO 6.6.11.6).
  constant c_ack_slot_offset     : natural := 1;
  constant c_cc_eof_start_offset : natural := 3;
  constant c_fd_eof_start_offset : natural := 4;

  -- Error signalling (ISO 6.6.5.2, 6.6.5.3)
  constant c_error_flag_width      : natural := 6;
  constant c_error_delimiter_width : natural := 8;
  constant c_error_sequence_width  : natural := c_error_flag_width + c_error_delimiter_width;

  -- Inter-frame spacing (ISO 6.6.7)
  constant c_intermission_width         : natural := 3;                         -- ISO 6.6.7.2
  constant c_suspend_transmission_width : natural := 8;                         -- ISO 6.6.7.4
  constant c_bus_idle_condition_width   : natural := 11;                        -- ISO 6.6.7.5
  constant c_bus_off_recovery_count     : natural := 128;                       -- ISO 8.1.4.4
  constant c_error_count_threshold      : natural := 127;                       -- ISO 8.1.4.4
  constant c_bus_off_threshold          : natural := 255;                       -- ISO 8.1.4.4

  -- Frame limits
  constant c_dlc_max              : natural := 15;                              -- ISO Table 5
  constant c_max_data_bytes       : natural := 64;                              -- ISO 6.6.11.4
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


  ---------------------------------------------------------------------------
  -- 2. Bit Timing (ISO 7.3.2, Table 13)
  ---------------------------------------------------------------------------

  constant c_max_transmitter_delay : natural := 255;                            -- ISO 7.3.4
  constant prescaler_min           : natural := 1;
  constant prescaler_max           : natural := 32;
  constant nom_prop_seg_min        : natural := 0;
  constant nom_prop_seg_max        : natural := 384;
  constant data_prop_seg_min       : natural := 0;
  constant data_prop_seg_max       : natural := 128;
  constant nom_phase_seg1_min      : natural := 1;
  constant nom_phase_seg1_max      : natural := 128;
  constant data_phase_seg1_min     : natural := 1;
  constant data_phase_seg1_max     : natural := 128;
  constant nom_phase_seg2_min      : natural := 2;
  constant nom_phase_seg2_max      : natural := 128;
  constant data_phase_seg2_min     : natural := 2;
  constant data_phase_seg2_max     : natural := 128;
  constant sjw_min                 : natural := 1;
  constant sjw_max                 : natural := 128;


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
    tx_data            : std_logic;                                             -- Polarity of the next bit to transmit.
    next_bit_is_res : std_logic;                                             -- High when the PCS should start the Transmitter Delay Compensation (TDC) measurement (ISO : 7.3.4).
    next_bit_is_brs : std_logic;                                             -- High when the PCS should use the data rate bit timing (FD frames, BRS=1).
    data_phase_stop    : std_logic;                                             -- High when the PCS should use the data rate bit timing (FD frames, BRS=1).
    do_hard_sync       : std_logic;                                             -- '1': next valid edge triggers hard sync
    transmitting       : std_logic;                                             -- '1' when the MAC is transmitting, '0' when receiving.
  end record t_can_mac_pcs_if_m2s;

  constant c_mac_to_pcs_if_reset : t_can_mac_pcs_if_m2s :=
  (
    tx_data            => c_recessive,
    next_bit_is_res => '0',
    next_bit_is_brs => '0',
    data_phase_stop    => '0',
    do_hard_sync       => '0',                                                  -- '1': next valid edge triggers hard sync
    transmitting       => '0'

  );

  -- PCS -> MAC (ISO 7.2, PCS_Data.Indicate)
  type t_can_mac_pcs_if_s2m is record
    rx_data                : std_logic;                                         -- Bus polarity
    sample_point           : std_logic;                                         -- Sample point strobe
    secondary_sample_point : std_logic;                                         -- Secondary sample point strobe (used in FD frames only)
    -- Transmitter delay. This is the index used by the MAC TX FSM to fetch the correct bit from the polarity history shift register.
    -- Used FD frames to compensate for the transmitter delay when checking bit errors (ISO : 7.3.4)
    tdc_delay              : std_logic_vector(integer(ceil(log2(real(c_tdc_polarity_depth)))) - 1 downto 0);
  end record t_can_mac_pcs_if_s2m;

  constant c_pcs_to_mac_if_reset : t_can_mac_pcs_if_s2m :=
  (
    rx_data                => c_recessive,
    sample_point           => '0',
    secondary_sample_point => '0',
    tdc_delay              => (others => '0')
  );

  -- FSM -> Bit Stuffer (ISO 6.6.13)
  type t_can_mac_fsm_bs_if_m2s is record
    data                  : std_logic;
    valid                 : std_logic;
    fixed_bit_stuffing_en : std_logic;                                          -- When high, the bit stuffer operates in the fixed bit stuffing mode (FD frames only).
  end record t_can_mac_fsm_bs_if_m2s;

  constant c_mac_fsm_to_bs_fd_if_reset : t_can_mac_fsm_bs_if_m2s :=
  (
    data                  => c_recessive,
    valid                 => '0',
    fixed_bit_stuffing_en => '0'
  );

  -- Bit Stuffer -> FSM (ISO 6.6.13)
  type t_can_mac_fsm_bs_if_s2m is record
    data            : std_logic;
    valid           : std_logic;
    stuff_bit_count : std_logic_vector(c_sbc_field_width - 1 downto 0);         -- Stuff Bit Count (SBC) field (FD frames only) (ISO : 6.6.11.5)
  end record t_can_mac_fsm_bs_if_s2m;

  constant c_can_mac_fsm_bs_if_s2m_reset : t_can_mac_fsm_bs_if_s2m :=
  (
    data            => c_recessive,
    valid           => '0',
    stuff_bit_count => (others => '0')
  );

  -- FSM -> CRC (ISO 6.6.4.4)
  type t_can_mac_fsm_crc_if_m2s is record
    crc_poly_select : std_logic_vector(1 downto 0);
    valid_cc        : std_logic;
    valid_fd        : std_logic;
    -- We need a data feed for each frame type (CC or FD) in order for the CRC module to work in both the TX and RX paths.
    -- The reason is, that the RX path does not know which CRC engine to use until after the DLC field has been received
    -- and the CC and FD frames compute their CRC values over different bit streams:
    -- FD frames: dynamic stuff bits + data bits
    -- CC frames: data bits only (no stuff bits)
    data_cc         : std_logic;                                                -- Data fed to the CRC_15 engine
    data_fd         : std_logic;                                                -- Data fed to the CRC_17/CRC_21 engines
  end record t_can_mac_fsm_crc_if_m2s;

  constant c_mac_fsm_to_crc_if_reset : t_can_mac_fsm_crc_if_m2s :=
  (
    crc_poly_select => (others => '0'),
    valid_cc        => '0',
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
    transmitting                  : std_logic;
    error                         : std_logic;
    primary_error                 : std_logic;
    sending_error_overload_flag   : std_logic;
    passive_tx_ack_error_exempt_1 : std_logic;                                  -- ISO 8.1.4.2 c) Exc.1: asserted when exemption applies (passive + ACK-caused + no dominant during flag)
    error_delimiter_too_late      : std_logic;
    successful_transfer           : std_logic;
  end record t_can_mac_fce_if_m2s;

  constant c_mac_to_fce_if_reset : t_can_mac_fce_if_m2s :=
  (
    transmitting                  => '0',
    error                         => '0',
    primary_error                 => '0',
    sending_error_overload_flag   => '0',
    passive_tx_ack_error_exempt_1 => '0',
    error_delimiter_too_late      => '0',
    successful_transfer           => '0'
  );

  -- FCE -> MAC (ISO Table 16, Table 17)
  type t_can_mac_fce_if_s2m is record
    error_active : std_logic;
    bus_off      : std_logic;
  end record t_can_mac_fce_if_s2m;

  constant c_fce_to_mac_if_reset : t_can_mac_fce_if_s2m :=
  (
    error_active => '1',
    bus_off      => '0'
  );

  -- LLC -> FCE (ISO Table 14)
  type t_can_llc_fce_if_m2s is record
    normal_mode : std_logic;
  end record t_can_llc_fce_if_m2s;

  constant c_llc_to_fce_if_reset : t_can_llc_fce_if_m2s :=
  (
    normal_mode => '0'
  );

  -- FCE -> LLC (ISO Table 15)
  type t_can_fce_llc_if_s2m is record
    bus_off : std_logic;
  end record t_can_fce_llc_if_s2m;

  constant c_fce_to_llc_if_reset : t_can_fce_llc_if_s2m :=
  (
    bus_off => '0'
  );

  -- FCE -> PCS (ISO Table 18)
  type t_can_fce_pcs_if_m2s is record
    bus_off : std_logic;
  end record t_can_fce_pcs_if_m2s;

  constant c_fce_to_pcs_if_reset : t_can_fce_pcs_if_m2s :=
  (
    bus_off => '0'
  );

  -- PCS -> FCE (ISO Table 19)
  type t_can_pcs_fce_if_s2m is record
    idle_condition : std_logic;                                                 -- Pulse: 11 consecutive recessive bits detected (bus-off recovery)
  end record t_can_pcs_fce_if_s2m;

  constant c_pcs_to_fce_if_reset : t_can_pcs_fce_if_s2m :=
  (
    idle_condition => '0'
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
  constant c_conf_0_offset          : natural := 0;
  constant c_conf_1_offset          : natural := 1;
  constant c_id_offset              : natural := 2;
  constant c_data_offset            : natural := 6;

  type t_llc_frame is array (0 to c_internal_llc_frame_len - 1) of std_logic_vector(c_byte_width - 1 downto 0);

  -- Legacy frame
  constant c_legacy_frame_len    : natural := 71;
  constant c_legacy_fmt_dlc_byte : natural := 4;
  constant c_legacy_data_offset  : natural := 5;

  type t_legacy_frame is array (0 to c_legacy_frame_len - 1) of std_logic_vector(c_byte_width - 1 downto 0);

  -- Config byte 0 bit positions: [7]=IDE, [6]=FDF, [4]=FTYP, [3]=ESI, [2]=BRS
  constant c_llc_frame_ide  : natural := 7;
  constant c_llc_frame_fdf  : natural := 6;
  constant c_llc_frame_ftyp : natural := 5;
  constant c_llc_frame_esi  : natural := 4;
  constant c_llc_frame_brs  : natural := 3;

  -- Config byte 1 bit positions: [7:4]=DLC
  constant c_llc_frame_dlc_start : natural := 7;
  constant c_llc_frame_dlc_end   : natural := 4;
  -- First data byte in the internal LLC frame (2 config bytes + 4 ID bytes)
  constant c_llc_frame_data_byte : natural := 6;
  -- ID stream layout
  constant c_llc_id_byte_count   : natural := 4;
  constant c_llc_id_field_width  : natural := c_llc_id_byte_count * c_byte_width;

  ---------------------------------------------------------------------------
  -- 8. Protocol Functions
  ---------------------------------------------------------------------------

  -- Convert DLC to actual data length in bytes (ISO Table 5)
  function dlc_to_data_length(dlc : natural; fdf : std_logic) return natural;

  -- CRC field length in bits (ISO 6.6.4.4 / 6.6.11.5).
  -- CC frames: CRC15. FD with <= 16 data bytes: CRC17. FD > 16 bytes: CRC21.
  function f_crc_length(data_len : natural; fdf : std_logic) return natural;

  -- CRC polynomial selector matching f_crc_length.
  function f_crc_poly_select(data_len : natural; fdf : std_logic) return std_logic_vector;

  -- Binary-to-Gray conversion (ISO 6.6.11.5: Stuff Bit Count encoding)
  function f_to_gray(v : std_logic_vector) return std_logic_vector;

  -- XOR parity over a vector (ISO 6.6.11.5: SBC parity bit)
  function f_calc_parity(v : std_logic_vector) return std_logic;

end package pk_can_types;

package body pk_can_types is

  function dlc_to_data_length(dlc : natural; fdf : std_logic) return natural is
  begin
    -- ISO 6.4.3: Table 5
    if (fdf = '0') then
      return dlc;
    end if;

    case dlc is
      when 0 to 8 => return natural(dlc);
      when 9      => return 12;
      when 10     => return 16;
      when 11     => return 20;
      when 12     => return 24;
      when 13     => return 32;
      when 14     => return 48;
      when 15     => return c_max_data_bytes;
      when others => return 0;
    end case;
  end function dlc_to_data_length;

  function f_crc_length(data_len : natural; fdf : std_logic) return natural is
  begin
    -- ISO 6.6.4.4 / 6.6.11.5
    if fdf = '0' then
      return c_crc_15_length;
    elsif data_len < c_crc_17_length then
      return c_crc_17_length;
    else
      return c_crc_21_length;
    end if;
  end function f_crc_length;

  function f_crc_poly_select(data_len : natural; fdf : std_logic) return std_logic_vector is
  begin
    if fdf = '0' then
      return c_crc_poly_15_sel;
    elsif data_len < c_crc_17_length then
      return c_crc_poly_17_sel;
    else
      return c_crc_poly_21_sel;
    end if;
  end function f_crc_poly_select;

  function f_to_gray(v : std_logic_vector) return std_logic_vector is
    variable v_result : std_logic_vector(v'range);
  begin
    v_result(v'left) := v(v'left);
    for i in v'left - 1 downto v'right loop
      v_result(i) := v(i) xor v(i + 1);
    end loop;
    return v_result;
  end function f_to_gray;

  function f_calc_parity(v : std_logic_vector) return std_logic is
    variable v_parity : std_logic := '0';
  begin
    for i in v'range loop
      v_parity := v_parity xor v(i);
    end loop;
    return v_parity;
  end function f_calc_parity;

end package body pk_can_types;

-- eof
