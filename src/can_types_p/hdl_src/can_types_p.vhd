--------------------------------------------------------------------------------
-- Description: Central package for the CAN/CAN-FD implementation per
--              ISO 11898-1:2015. Every module in the design depends on this
--              package; all types, constants, and protocol functions are
--              defined here and nowhere else.
--
--              Section map:
--                1. Protocol Constants  -- polarity, field widths, CRC params,
--                                          transfer status, TDC depth, error counts
--                2. Bit Timing         -- ISO Table 13 prescaler/segment range limits
--                3. Composite Types    -- llc_metadata and related structures
--                4. Interface Records  -- inter-layer records with reset constants
--                5. LLC Frame Format   -- internal/legacy byte layouts, bit positions
--                6. Protocol Functions -- DLC table, CRC selector, Gray code, parity
--
--              Key design decisions:
--                Parallel CC/FD CRC feeds (t_can_mac_fsm_crc_if_m2s): the RX path
--                feeds both a CC (CRC-15) and an FD (CRC-17/21) stream in parallel
--                because the frame type is not confirmed until the FDF bit is decoded.
--                Only one stream produces a valid digest; the FSM selects it at the
--                CRC check point.
--
--                Interface direction convention: m2s/s2m for control/status channels;
--                s2d/d2s (source/destination) for Avalon-ST data streams.
--
--              Reference: ISO 11898-1:2015.
--------------------------------------------------------------------------------

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

  -- TDC polarity history depth (ISO 7.3.4): ceil(2 x transceiver_d / data_bit_time).
  -- The CAN-FD transceiver TCAN1042 (~100 ns loop-delay) + default PCS (200 ns data-rate bit time): ceil(100/200) = 1 -> depth 1 suffices.
  -- ISO 7.3.4 ceiling (95 x t_q = 1900 ns): ceil(1900/200) = 10 -> depth 10 needed.
  constant c_tdc_polarity_depth : natural := 8; -- Just a number between 1 and 10

  ---------------------------------------------------------------------------
  -- 2. Bit Timing (ISO 7.3.2, Table 13)
  --
  -- Range guards for can_pcs signal declarations. All values are in Time Quanta (TQ).
  ---------------------------------------------------------------------------

  constant c_max_transmitter_delay : natural := 255;
  constant c_prescaler_min         : natural := 1;
  constant c_prescaler_max         : natural := 32;
  constant c_nom_prop_seg_min      : natural := 0;
  constant c_nom_prop_seg_max      : natural := 384;
  constant c_data_prop_seg_min     : natural := 0;
  constant c_data_prop_seg_max     : natural := 128;
  constant c_nom_phase_seg1_min    : natural := 1;
  constant c_nom_phase_seg1_max    : natural := 128;
  constant c_data_phase_seg1_min   : natural := 1;
  constant c_data_phase_seg1_max   : natural := 128;
  constant c_nom_phase_seg2_min    : natural := 2;
  constant c_nom_phase_seg2_max    : natural := 128;
  constant c_data_phase_seg2_min   : natural := 2;
  constant c_data_phase_seg2_max   : natural := 128;
  constant c_sjw_min               : natural := 1;
  constant c_sjw_max               : natural := 128;

  ---------------------------------------------------------------------------
  -- 3. Composite Types
  ---------------------------------------------------------------------------

  -- LLC frame metadata latched at SOF and carried through the MAC pipeline.
  -- Fields mirror the frame configuration bits defined in Section 5 (ISO 6.4.3, Table 4).
  type t_llc_metadata is record
    ide  : std_logic;                                                            -- Extended identifier flag
    fdf  : std_logic;                                                            -- FD frame flag
    dlc  : std_logic_vector(c_dlc_field_width - 1 downto 0);                    -- Data Length Code
    ftyp : std_logic;                                                            -- Frame type: '0'=data, '1'=remote
    brs  : std_logic;                                                            -- Bit Rate Switch
    esi  : std_logic;                                                            -- Error State Indicator
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
  -- 4. Interface Records
  --
  -- Convention: m2s/s2m for control/status channels between modules.
  --             s2d/d2s for Avalon-ST byte streams (source drives data, destination drives backpressure).
  ---------------------------------------------------------------------------

  -- Avalon-ST streaming interface (local mirror of company pk_eth_st types).
  type t_eth_st_s2d is record
    data          : std_logic_vector(c_byte_width - 1 downto 0);
    valid         : std_logic;
    startofpacket : std_logic;
    endofpacket   : std_logic;
  end record t_eth_st_s2d;

  type t_eth_st_d2s is record
    ready : std_logic;
  end record t_eth_st_d2s;

  -- Serializer -> FSM: carries the next serial bit and cached frame metadata.
  -- The FSM asserts ready on the cycles it consumes bits. The serializer
  -- advances its internal byte/bit pointer on each accepted transfer.
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

  -- FSM -> Serializer: feedback path carrying flow control and frame outcome.
  type t_can_mac_ser_fsm_if_d2s is record
    transfer_status : std_logic_vector(2 downto 0);                             -- c_ongoing / c_transmitted / c_disturbed / c_lost_arb
    ready           : std_logic;
  end record t_can_mac_ser_fsm_if_d2s;

  constant c_ser_fsm_if_d2s_reset : t_can_mac_ser_fsm_if_d2s :=
  (
    transfer_status => c_ongoing,
    ready           => '0'
  );

  -- MAC RX -> LLC RX: Avalon-ST byte stream of the received frame (source side).
  type t_can_llc_mac_rx_if_s2d is record
    avalon_st_source : t_eth_st_s2d;
  end record t_can_llc_mac_rx_if_s2d;

  constant c_mac_rx_to_llc_if_reset : t_can_llc_mac_rx_if_s2d :=
  (
    avalon_st_source => (data => (others => '0'), valid => '0', startofpacket => '0', endofpacket => '0')
  );

  -- LLC RX -> MAC RX: backpressure (destination side).
  type t_can_llc_mac_rx_if_d2s is record
    avalon_st_sink : t_eth_st_d2s;
  end record t_can_llc_mac_rx_if_d2s;

  constant c_llc_to_mac_rx_if_reset : t_can_llc_mac_rx_if_d2s :=
  (
    avalon_st_sink => (ready => '0')
  );

  -- LLC -> MAC TX: Avalon-ST byte stream carrying frame bytes for transmission (source side).
  type t_can_llc_mac_tx_if_s2d is record
    avalon_st_source : t_eth_st_s2d;
  end record t_can_llc_mac_tx_if_s2d;

  constant c_llc_to_mac_tx_if_reset : t_can_llc_mac_tx_if_s2d :=
  (
    avalon_st_source => (data => (others => '0'), valid => '0', startofpacket => '0', endofpacket => '0')
  );

  -- MAC TX -> LLC: backpressure and frame outcome (destination side).
  type t_can_llc_mac_tx_if_d2s is record
    avalon_st_sink  : t_eth_st_d2s;
    transfer_status : std_logic_vector(2 downto 0);
  end record t_can_llc_mac_tx_if_d2s;

  constant c_mac_to_llc_if_reset : t_can_llc_mac_tx_if_d2s :=
  (
    avalon_st_sink  => (ready => '1'),
    transfer_status => c_ongoing
  );

  -- User -> LLC TX: Avalon-ST byte stream using the 71-byte legacy frame format (source side).
  type t_can_user_llc_tx_if_s2d is record
    avalon_st_source : t_eth_st_s2d;
    abort_request    : std_logic;
  end record t_can_user_llc_tx_if_s2d;

  -- LLC TX -> User: backpressure and frame outcome (destination side).
  type t_can_user_llc_tx_if_d2s is record
    avalon_st_sink  : t_eth_st_d2s;
    transfer_status : std_logic_vector(2 downto 0);
  end record t_can_user_llc_tx_if_d2s;

  -- MAC -> PCS
  -- next_bit_is_res and next_bit_is_brs are asserted at the N-1 sample point of the
  -- the affected bit so the PCS can arm TDC or data-rate timing in time for the next bit boundary.
  type t_can_mac_pcs_if_m2s is record
    tx_data         : std_logic;                                                 -- Polarity to drive onto the bus this bit time.
    next_bit_is_res : std_logic;                                                 -- Arm TDC: the next bit is the FD reserved dominant res bit (ISO 7.3.4).
    next_bit_is_brs : std_logic;                                                 -- Arm data-rate timing: the next bit is the BRS bit (ISO 7.3.3).
    data_phase_stop : std_logic;                                                 -- Return to nominal timing: asserted at the last CRC bit (end of data phase or if an error occurs during the data phase).
    do_hard_sync    : std_logic;                                                 -- '1': next dominant edge triggers a hard synchronisation.
    transmitting    : std_logic;                                                 -- '1' while the MAC is driving the bus; '0' in receive-only mode.
  end record t_can_mac_pcs_if_m2s;

  constant c_mac_to_pcs_if_reset : t_can_mac_pcs_if_m2s :=
  (
    tx_data         => c_recessive,
    next_bit_is_res => '0',
    next_bit_is_brs => '0',
    data_phase_stop => '0',
    do_hard_sync    => '0',
    transmitting    => '0'
  );

  -- PCS -> MAC
  -- rx_data is valid every cycle. sample_point and secondary_sample_point are
  -- single-cycle strobes. The MAC latches rx_data on these pulses only.
  type t_can_mac_pcs_if_s2m is record
    rx_data                : std_logic;                                          -- Bus polarity sampled this cycle.
    sample_point           : std_logic;                                          -- SP strobe: latch rx_data and advance FSM.
    secondary_sample_point : std_logic;                                          -- SSP strobe: used in FD data phase for TDC bit-error check (ISO 7.3.4).
    tdc_delay              : std_logic_vector(integer(ceil(log2(real(c_tdc_polarity_depth)))) - 1 downto 0); --  index for use in the MAC FSM's transmitted_bits_shift_reg during FD data phase.
  end record t_can_mac_pcs_if_s2m;

  constant c_pcs_to_mac_if_reset : t_can_mac_pcs_if_s2m :=
  (
    rx_data                => c_recessive,
    sample_point           => '0',
    secondary_sample_point => '0',
    tdc_delay              => (others => '0')
  );

  -- FSM -> Bit Stuffer (ISO 6.6.13).
  -- The FSM feeds one bit per sample point. The stuffer inserts a complement
  -- bit after every run of c_stuff_width identical bits (dynamic mode) or
  -- at fixed 5-bit intervals with a Gray-coded count (FD fixed mode).
  type t_can_mac_fsm_bs_if_m2s is record
    data                  : std_logic;
    valid                 : std_logic;
    fixed_bit_stuffing_en : std_logic;                                           -- '1': fixed stuffing mode for FD SBC/CRC field (ISO 6.6.11.5).
  end record t_can_mac_fsm_bs_if_m2s;

  constant c_mac_fsm_to_bs_fd_if_reset : t_can_mac_fsm_bs_if_m2s :=
  (
    data                  => c_recessive,
    valid                 => '0',
    fixed_bit_stuffing_en => '0'
  );

  -- Bit Stuffer -> FSM (ISO 6.6.13).
  -- valid pulses when the stuffer has produced a stuff bit the FSM must drive.
  -- stuff_bit_count is is read by the FSM during the SBC field.
  type t_can_mac_fsm_bs_if_s2m is record
    data            : std_logic;
    valid           : std_logic;
    stuff_bit_count : std_logic_vector(c_sbc_field_width - 1 downto 0);         -- Gray-coded stuff-bit count for the SBC field (ISO 6.6.11.5).
  end record t_can_mac_fsm_bs_if_s2m;

  constant c_can_mac_fsm_bs_if_s2m_reset : t_can_mac_fsm_bs_if_s2m :=
  (
    data            => c_recessive,
    valid           => '0',
    stuff_bit_count => (others => '0')
  );

  -- FSM -> CRC (ISO 6.6.4.4).
  -- Dual-stream feed: the FSM always drives both data_cc and data_fd so the
  -- CRC engine runs CC and FD computations in parallel. The FSM selects the
  -- correct digest after DLC is decoded (see package description for rationale).
  type t_can_mac_fsm_crc_if_m2s is record
    crc_poly_select : std_logic_vector(1 downto 0);
    valid_cc        : std_logic;
    valid_fd        : std_logic;
    data_cc         : std_logic;                                                 -- CC stream: data bits only, dynamic stuff bits excluded.
    data_fd         : std_logic;                                                 -- FD stream: data bits and dynamic stuff bits included.
  end record t_can_mac_fsm_crc_if_m2s;

  constant c_mac_fsm_to_crc_if_reset : t_can_mac_fsm_crc_if_m2s :=
  (
    crc_poly_select => (others => '0'),
    valid_cc        => '0',
    valid_fd        => '0',
    data_cc         => '0',
    data_fd         => '0'
  );

  -- CRC -> FSM: exposes the running digest at full width (CRC-21).
  -- The FSM indexes into the correct sub-range based on crc_length.
  type t_can_mac_fsm_crc_if_s2m is record
    crc : std_logic_vector(c_crc_21_length - 1 downto 0);
  end record t_can_mac_fsm_crc_if_s2m;

  -- MAC -> FCE (ISO Table 16, Table 17): error and transfer events.
  -- All signals are single-cycle pulses unless noted.
  type t_can_mac_fce_if_m2s is record
    transmitting                  : std_logic;                                   -- Level: '1' while the node is the frame transmitter.
    error                         : std_logic;                                   -- Pulse: a frame error was detected (increments TX/RX error counter).
    primary_error                 : std_logic;                                   -- Pulse: node was first to detect the error (ISO 8.1.3.3, Table 16).
    sending_error_overload_flag   : std_logic;                                   -- Level: '1' while transmitting an error or overload flag.
    passive_tx_ack_error_exempt_1 : std_logic;                                   -- Pulse: passive ACK-error exemption applies (ISO 8.1.4.2.c, Exception 1).
    error_delimiter_too_late      : std_logic;                                   -- Pulse: error delimiter exceeded 8 bits (ISO 8.1.3.3, Table 16).
    successful_transfer           : std_logic;                                   -- Pulse: frame completed without error (decrements error counter).
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

  -- FCE -> MAC (ISO Table 16, Table 17): confinement state reported each cycle.
  type t_can_mac_fce_if_s2m is record
    error_active : std_logic;                                                    -- '1': error-active (drives dominant error flags); '0': error-passive.
    bus_off      : std_logic;                                                    -- '1': bus-off; MAC must suspend all activity.
  end record t_can_mac_fce_if_s2m;

  constant c_fce_to_mac_if_reset : t_can_mac_fce_if_s2m :=
  (
    error_active => '1',
    bus_off      => '0'
  );

  -- LLC -> FCE (ISO Table 14): LLC control signals to the FCE.
  type t_can_llc_fce_if_m2s is record
    normal_mode : std_logic;                                                     -- '1': LLC is active and in normal operation.
  end record t_can_llc_fce_if_m2s;

  constant c_llc_to_fce_if_reset : t_can_llc_fce_if_m2s :=
  (
    normal_mode => '0'
  );

  -- FCE -> LLC (ISO Table 15): bus-off indication.
  type t_can_fce_llc_if_s2m is record
    bus_off : std_logic;
  end record t_can_fce_llc_if_s2m;

  constant c_fce_to_llc_if_reset : t_can_fce_llc_if_s2m :=
  (
    bus_off => '0'
  );

  -- FCE -> PCS (ISO Table 18): bus-off disables PCS TX output.
  type t_can_fce_pcs_if_m2s is record
    bus_off : std_logic;
  end record t_can_fce_pcs_if_m2s;

  constant c_fce_to_pcs_if_reset : t_can_fce_pcs_if_m2s :=
  (
    bus_off => '0'
  );

  -- PCS -> FCE (ISO Table 19): bus-off recovery event.
  type t_can_pcs_fce_if_s2m is record
    idle_condition : std_logic;                                                  -- Pulse: 11 consecutive recessive bits detected (ISO 8.1.4.4).
  end record t_can_pcs_fce_if_s2m;

  constant c_pcs_to_fce_if_reset : t_can_pcs_fce_if_s2m :=
  (
    idle_condition => '0'
  );

  ---------------------------------------------------------------------------
  -- 5. LLC Frame Format
  --
  -- Internal format (variable length, streamed from can_llc to can_mac_ser):
  --   Byte 0 (SOP): [7]=IDE, [6]=FDF, [5]=FTYP(RTR), [4]=ESI, [3]=BRS, [2:0]=000
  --   Byte 1:       [7:4]=DLC, [3:0]=0000
  --   Bytes 2-5:    ID (32-bit, MSB first; base-ID frames use bits [31:21])
  --   Bytes 6+:     Data (DLC count, no padding), EOP on last byte
  --
  -- Legacy format (71 bytes, presented at the user Avalon-ST interface):
  --   Bytes 0-3:  ID bytes (right-aligned for 11-bit, full for 29-bit)
  --   Byte  4:    [6:4]=FMT, [3:0]=DLC
  --   Bytes 5-68: Data (zero-padded to 64 bytes)
  --   Byte  69:   [0]=IDE
  --   Byte  70:   [2]=BRS, [1]=ESI, [0]=RTR
  ---------------------------------------------------------------------------

  -- Internal LLC frame dimensions
  constant c_internal_llc_frame_len : natural := 70;
  constant c_conf_0_offset          : natural := 0;
  constant c_conf_1_offset          : natural := 1;
  constant c_id_offset              : natural := 2;
  constant c_data_offset            : natural := 6;

  type t_llc_frame is array (0 to c_internal_llc_frame_len - 1) of std_logic_vector(c_byte_width - 1 downto 0);

  -- Legacy frame dimensions
  constant c_legacy_frame_len    : natural := 71;
  constant c_legacy_fmt_dlc_byte : natural := 4;
  constant c_legacy_data_offset  : natural := 5;

  type t_legacy_frame is array (0 to c_legacy_frame_len - 1) of std_logic_vector(c_byte_width - 1 downto 0);

  -- Config byte 0 bit positions: [7]=IDE, [6]=FDF, [5]=FTYP, [4]=ESI, [3]=BRS
  constant c_llc_frame_ide  : natural := 7;
  constant c_llc_frame_fdf  : natural := 6;
  constant c_llc_frame_ftyp : natural := 5;
  constant c_llc_frame_esi  : natural := 4;
  constant c_llc_frame_brs  : natural := 3;

  -- Config byte 1 bit positions: [7:4]=DLC
  constant c_llc_frame_dlc_start : natural := 7;
  constant c_llc_frame_dlc_end   : natural := 4;

  -- ID stream layout
  constant c_llc_frame_data_byte : natural := 6;                                -- First data byte in the internal LLC frame (2 config + 4 ID bytes)
  constant c_llc_id_byte_count   : natural := 4;
  constant c_llc_id_field_width  : natural := c_llc_id_byte_count * c_byte_width;

  ---------------------------------------------------------------------------
  -- 6. Protocol Functions
  ---------------------------------------------------------------------------

  -- Convert DLC to actual data length in bytes (ISO Table 5).
  function dlc_to_data_length(dlc : natural; fdf : std_logic) return natural;

  -- CRC field length in bits (ISO 6.6.4.4 / 6.6.11.5).
  -- CC frames: CRC-15. FD with <= 16 data bytes: CRC-17. FD > 16 bytes: CRC-21.
  function f_crc_length(data_len : natural; fdf : std_logic) return natural;

  -- CRC polynomial selector matching f_crc_length.
  function f_crc_poly_select(data_len : natural; fdf : std_logic) return std_logic_vector;

  -- Binary-to-Gray conversion (ISO 6.6.11.5: Stuff Bit Count encoding).
  function f_to_gray(v : std_logic_vector) return std_logic_vector;

  -- XOR parity over a vector (ISO 6.6.11.5: SBC parity bit).
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
