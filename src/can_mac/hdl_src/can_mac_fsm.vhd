--------------------------------------------------------------------------------
-- Title      : Combined MAC FSM (TX + RX) for CAN/CAN-FD
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_mac_fsm.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Single MAC FSM handling TX and RX in one synchronous process.
--              is_transmitter is latched at SOF; each state's case branch
--              contains both TX and RX behaviour gated on it. The bit stuffer,
--              CRC and serializer submodules are shared between modes.
--
--              Frame layouts (d = fixed dominant, r = fixed recessive):
--
--                CC Base
--                  |SOF(d)|ID(11)|RTR|IDE(d)|r0(d)|DLC(4)|DATA(0..8B)|CRC(15)|delim(r)|ACK|delim(r)|EOF(7r)|
--
--                CC Extended
--                  |SOF(d)|ID-A(11)|SRR(r)|IDE(r)|ID-B(18)|RTR|r1(d)|r0(d)|DLC(4)|DATA(0..8B)|CRC(15)|delim(r)|ACK|delim(r)|EOF(7r)|
--
--                FD Base
--                  |SOF(d)|ID(11)|RRS(d)|IDE(d)|FDF(r)|res(d)|BRS|ESI|DLC(4)|DATA(0..64B)|SBC(4)|CRC(17/21)|delim(r)|ACK(2)|delim(r)|EOF(7r)|
--
--                FD Extended
--                   |SOF(d)|ID-A(11)|SRR(r)|IDE(r)|ID-B(18)|RRS(d)|FDF(r)|res(d)|BRS|ESI|DLC(4)|DATA(0..64B)|SBC(4)|CRC(17/21)|delim(r)|ACK(2)|delim(r)|EOF(7r)|
--
--              Reference: ISO 11898-1:2024.
--------------------------------------------------------------------------------
-- Design rationale and refactor history
-- =====================================
--
-- Starting point: the MAC was split into two independent FSM entities,
-- can_mac_fsm_tx (~700 lines, 21 states) and can_mac_fsm_rx (~640 lines,
-- 19 states), wired together at the can_mac top via a transmitting_i
-- flag from TX to RX and dominant-wins OR-merging of their PCS outputs.
-- Most states were duplicated and the two FSMs re-derived frame position
-- independently. Debugging cross-FSM behaviour was painful (the trigger
-- was can_mac_pcs_fce_tb reporting c_disturbed instead of c_transmitted
-- on a node that had successfully transmitted), and any new feature had
-- to be added in two places at once.
--
-- This file is the unified replacement: a single synchronous process
-- with one t_fsm_state enum, one is_transmitter mode flag latched at
-- SOF, one shared bit stuffer, one shared CRC engine, and the existing
-- TX byte serializer. RX path produces a byte stream to the LLC RX
-- sink; TX path consumes bytes from the LLC TX serializer. FCE stays
-- external (as in the split version).
--
-- The interesting part is *how* the unification was done. The first
-- attempt put both TX drive and RX state advance at the PCS sample
-- point (SP), which seemed natural ("everything happens at SP") but was
-- wrong for several reasons. The bugs we hit and the fixes that
-- accumulated are listed below; each one nudged the design toward what
-- the legacy CC-only can_fsm had been doing all along, and the final
-- shape is essentially the same model -- TX-drive at bit_boundary, RX
-- at SP, BS/CRC fed from the bus -- extended with FD support and an
-- external FCE.
--
--   1. TX drive at SP arrived too late.
--      PCS latches mac_i.tx_data into tx_o at bit_boundary_d (one clock
--      after the bit boundary). Driving at SP meant tx_data updated
--      mid-bit; PCS missed the latch window and tx_o was stale by a
--      whole bit period. Fix: TX drive moved to a bit_boundary branch
--      per state. Each drive site calls a drive_bit(polarity)
--      procedure that writes pcs_o.tx_data, asserts
--      pcs_o.transmitting / fce_o.transmitting and shifts the
--      polarity history. Mirrors the transmit_i pattern of the
--      legacy can_fsm.
--
--   2. polarity_history was shifted at SP.
--      transmitted_bits_shift_reg(0) is consumed by the TX bit-error
--      monitor and the SSP/TDC compare. With drive moving to
--      bit_boundary, the shift had to move too -- otherwise the
--      monitor compared the wrong bit. Fix: drive_bit() shifts the
--      history at the moment of the drive.
--
--   3. PCS hard-sync was firing on TX nodes too.
--      Hard-sync re-aligns the PCS to a bus edge it observes during
--      quiet/arbitration. On a TX node the bus edge is our own drive,
--      and re-syncing throws our bit timing off. Fix: PCS gates
--      hard-sync on (mac_i.transmitting = '0'). The MAC FSM in turn
--      only needs to assert pcs_o.do_hard_sync; it does not need a
--      role guard. (We keep the FSM's role-agnostic assignment of
--      do_hard_sync, and the gating happens one level down.)
--
--   4. Lost-arb and TX bit error fought over the same SP.
--      In s_arbitration, "we drove recessive and bus came back
--      dominant" is *lost arbitration*, not a bit error. The original
--      check fired both. Fix: the TX bit-error monitor gates on a
--      named v_in_tx_drive_field that explicitly excludes
--      s_arbitration; lost-arb is detected first, flips
--      is_transmitter to false in-place, and the s_arbitration case
--      then runs in RX mode for the remaining bits.
--
--   5. BS/CRC state diverged after a lost arbitration.
--      Initial design: TX feeds BS/CRC from its own drive (lookahead);
--      RX feeds them from rx_data (the bus). After losing arbitration
--      the previously-TX node had to continue as RX with BS/CRC state
--      matching the *winner*, but its BS/CRC had been fed lookahead
--      bits from its own (losing) frame. Fix: feed BS/CRC from
--      pcs_i.rx_data at SP for *both* modes. Loopback guarantees
--      rx_data == drive for the winner, so this is correct for
--      winning TX and naturally correct after a lost-arb flip.
--
--   6. SOF drive in s_bus_idle had to land on tx_o the same clock
--      is_transmitter was latched. The bit_boundary branch latches
--      is_transmitter <= true and calls drive_bit(c_dominant) on the
--      same clock, so PCS sees pcs_o.transmitting = '1' and
--      pcs_o.tx_data = c_dominant at the next bit_boundary_d.
--
--   7. fce_o.transmitting in s_ack contradicted ISO 8.1.4.2.b.
--      An earlier centralised v_transmitting derivation forced
--      fce_o.transmitting <= '0' for TX in s_ack ("TX listens"), but
--      ISO 8.1.4.2.b says ACK-slot bit errors must count as TX-side.
--      Replacement: drive_bit() sets transmitting = '1' on every TX
--      drive, NBA holds the level across s_ack, and the s_ack RX
--      branch explicitly clears pcs_o.transmitting (so the receiver
--      releases the bus) without touching fce_o.transmitting.
--
--   8. Process variables hiding state.
--      An early cut had a v_is_tx variable as a delayed copy of
--      is_transmitter. Redundant -- bit_boundary and SP are different
--      strobes that never fire in the same cycle. Dropped.
--
--   9. Per-state TX/RX branching in the SP case was mostly redundant.
--      Once BS/CRC are fed from the bus and TX drive lives at
--      bit_boundary, the SP-time case body for most states does not
--      need to know who is driving. For TX winning, rx_data == drive
--      everywhere except s_ack, so:
--        - llc_frame is captured from rx_data unconditionally (TX
--          self-receives so the LLC RX byte stream is also populated
--          on the transmitter).
--        - State-exit decisions use rx_data and previously captured
--          llc_frame fields rather than mac_ser_i.llc_metadata.
--        - SBC and CRC compares are role-independent (TX winning
--          never trips them).
--      States that genuinely diverge -- s_ack, s_ack_delimiter,
--      s_eof -- keep an explicit "if is_transmitter" branch.
--
--  10. Big nested if/elsif chains for bit_count.
--      s_arbitration originally had two if/elsif chains over bit_count
--      (capture and state-exit). Both became a single "case bit_count
--      is" with one branch per sub-field (ID-A/ID-B share a branch via
--      VHDL-2008 range/choice syntax).
--
--  11. SP block and bit_boundary block were 500 lines apart.
--      Reading e.g. s_arbitration meant flipping between two case
--      statements: a per-state SP branch high in the file and a per-
--      state TX-drive branch near the bottom. Folded the bit_boundary
--      case body into each per-state branch, so each state owns its
--      bit_boundary TX drive AND its SP capture/advance in one place
--      (matches the legacy can_fsm "if transmit_i / elsif sample_rx_i"
--      shape). BS/CRC feed and stuff-bit handling are inlined per
--      state too, so the v_in_dynamic_stuff_field /
--      v_in_fixed_stuff_field guards are gone.
--
-- Net result: a single FSM that occupies roughly the same conceptual
-- space as the legacy CC-only can_fsm, with FD support folded in via
-- the FDF/BRS/ESI/SBC states and the data-phase / TDC machinery, and
-- with FCE pulled out as a separate entity instead of being
-- intertwined with the FSM. The structure (TX-drive at bit_boundary,
-- RX at SP, BS/CRC from the bus, mode flag latched at SOF) is the
-- same. Most of the bugs above were the cost of rediscovering why
-- the legacy code looked the way it did.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.pk_can_types.all;

entity can_mac_fsm is
  port(
    clk_i     : in  std_logic;
    rst_i     : in  std_logic;
    -- LLC TX byte serializer interface (TX-side input, FSM consumes bits)
    mac_ser_i : in  t_can_mac_ser_fsm_if_s2d;
    mac_ser_o : out t_can_mac_ser_fsm_if_d2s;
    -- LLC RX byte sink interface (RX-side output, FSM produces frame bytes)
    llc_i     : in  t_can_llc_mac_rx_if_d2s;
    llc_o     : out t_can_llc_mac_rx_if_s2d;
    -- PCS interface (shared)
    pcs_i     : in  t_can_mac_pcs_if_s2m;
    pcs_o     : out t_can_mac_pcs_if_m2s;
    -- Bit stuffer interface (shared)
    bs_i      : in  t_can_mac_fsm_bs_if_s2m;
    bs_o      : out t_can_mac_fsm_bs_if_m2s;
    bs_rst    : out std_logic;
    -- CRC interface (shared)
    crc_i     : in  t_can_mac_fsm_crc_if_s2m;
    crc_o     : out t_can_mac_fsm_crc_if_m2s;
    crc_rst   : out std_logic;
    -- Fault Confinement Entity interface
    fce_i     : in  t_can_mac_fce_if_s2m;
    fce_o     : out t_can_mac_fce_if_m2s
  );
end entity can_mac_fsm;

architecture rtl of can_mac_fsm is

  -----------------------------------------------------------------
  -- Types
  -----------------------------------------------------------------
  type t_fsm_state is (
    s_bus_reintegration, s_intermission, s_suspend_transmission, s_bus_idle,
    s_arbitration, s_fdf_r1_r0, s_res_r0, s_brs, s_esi,
    s_dlc, s_data, s_sbc, s_crc, s_crc_delimiter, s_ack, s_ack_delimiter, s_eof,
    s_error_flag, s_error_flag_check, s_error_dominant_delim, s_error_delimiter,
    s_bus_off
  );

  -----------------------------------------------------------------
  -- s_arbitration sub-field positions, indexed by bit_count.
  -- ID-A (11 bits) -> RTR/SRR/RRS -> IDE -> [if extended: ID-B (18
  -- bits) -> RTR-ext]. SOF is driven by the s_intermission /
  -- s_bus_idle SOF-detection branches before entry, so bit_count = 0
  -- in s_arbitration is the FIRST ID-A bit.
  -----------------------------------------------------------------
  constant c_arb_id_a_last   : natural := c_base_id_width - 1;                       -- 10
  constant c_arb_rtr_pos     : natural := c_base_id_width;                           -- 11
  constant c_arb_ide_pos    : natural := c_base_id_width + 1;                        -- 12
  constant c_arb_id_b_first  : natural := c_base_id_width + 2;                       -- 13
  constant c_arb_id_b_last   : natural := c_base_id_width + 1 + c_extended_id_width; -- 30
  constant c_arb_rtr_ext_pos : natural := c_base_id_width + 2 + c_extended_id_width; -- 31

  -----------------------------------------------------------------
  -- Signals (shared)
  -----------------------------------------------------------------
  signal state                                : t_fsm_state;
  signal is_transmitter                       : boolean;
  signal bit_count                            : natural range 0 to c_max_mac_frame_length;
  signal data_len                             : natural range 0 to c_max_data_bytes;
  signal crc_length                           : natural range 0 to c_crc_21_length;
  signal overload                             : boolean;

  -----------------------------------------------------------------
  -- TX-mode tracking
  -----------------------------------------------------------------
  signal transmitted_bits_shift_reg           : std_logic_vector(c_tdc_polarity_depth - 1 downto 0);
  signal was_previous_frame_tx                : boolean;
  signal ack_success_seen                     : boolean;
  signal secondary_sample_point_error_pending : boolean;
  signal ack_error_caused_flag                : boolean;
  signal saw_dominant_during_flag             : boolean;

  -----------------------------------------------------------------
  -- RX-mode tracking (frame buffer + LLC streaming)
  -----------------------------------------------------------------
  signal byte_index                           : natural range 0 to c_internal_llc_frame_len - 1;
  signal bit_index                            : natural range 0 to c_byte_width - 1;
  signal stream_index                         : natural range 0 to c_internal_llc_frame_len - 1;
  signal llc_frame                            : t_llc_frame;
  signal crc_mismatch                         : boolean;
  signal llc_stream_start                     : boolean;
  signal llc_stream_done                      : boolean;
  signal llc_frame_len                        : natural range 0 to c_internal_llc_frame_len;

  -- Set when BRS=recessive enters data phase; cleared at the CRC delim.
  -- Suppresses the SP-based bit error check during the data phase, where
  -- SSP-based detection is the correct mechanism (ISO 7.3.4).
  signal in_data_phase                        : boolean;

begin

  -----------------------------------------------------------------
  -- Streams the received frame to the LLC byte by byte during the
  -- quiet phase after EOF.
  -----------------------------------------------------------------
  p_stream_to_LLC : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if (rst_i = '1' or fce_i.bus_off = '1') then
        llc_o           <= c_mac_rx_to_llc_if_reset;
        stream_index    <= 0;
        llc_stream_done <= false;
      else
        llc_o           <= c_mac_rx_to_llc_if_reset;
        llc_stream_done <= false;

        if (llc_stream_start and not llc_stream_done) then
          llc_o.avalon_st_source.data  <= llc_frame(stream_index);
          llc_o.avalon_st_source.valid <= '1';

          if (stream_index = 0) then
            llc_o.avalon_st_source.startofpacket <= '1';
          elsif (stream_index = llc_frame_len - 1) then
            llc_o.avalon_st_source.endofpacket <= '1';
            stream_index                       <= 0;
            llc_stream_done                    <= true;
          end if;
          if (llc_i.avalon_st_sink.ready = '1' and stream_index /= llc_frame_len - 1) then
            stream_index <= stream_index + 1;
          end if;
        end if;
      end if;
    end if;
  end process p_stream_to_LLC;

  -----------------------------------------------------------------
  -- Combined MAC FSM
  -----------------------------------------------------------------
  p_fsm : process(clk_i) is
    -- Field guards
    variable v_in_arbitration_field   : boolean;
    variable v_in_quiet_field         : boolean;
    variable v_in_tx_drive_field      : boolean;
    -- Local data-length helper (used by TX frame setup and RX DLC decode)
    variable v_data_len               : natural range 0 to c_max_data_bytes;
    -- RX-only DLC vector helper
    variable v_dlc_vec                : std_logic_vector(c_llc_frame_dlc_start downto c_llc_frame_dlc_end);
    -- BS / CRC data source. TX feeds its own most-recently-driven bit so
    -- BS stuff-count and CRC track the outgoing stream rather than the
    -- (TDC-delayed) bus echo in FD data phase. RX and the arbitration
    -- field still feed from the bus so a TX-loser converges with the
    -- winner's BS/CRC state.
    variable v_bs_crc_data            : std_logic;

    -- Drive a single bit on the bus. Asserts pcs_o.transmitting /
    -- fce_o.transmitting (PCS will latch tx_o at the next bit_boundary_d,
    -- FCE counts errors as TX-side) and shifts polarity_history so the
    -- TX bit-error monitor and SSP/TDC compare see this drive at the
    -- next SP. Called from any case branch that drives a bit, whether at
    -- bit_boundary (TX) or SP (RX-side ACK / error-flag drive).
    procedure drive_bit(polarity : in std_logic) is
    begin
      pcs_o.tx_data              <= polarity;
      pcs_o.transmitting         <= '1';
      fce_o.transmitting         <= '1';
      transmitted_bits_shift_reg <= transmitted_bits_shift_reg(c_tdc_polarity_depth - 2 downto 0) & polarity;
    end procedure drive_bit;

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1' or fce_i.bus_off = '1') then
        -- Bus-off recovery is handled by the FCE (counts 128 sequences of 11
        -- recessive bits per ISO 8.1.4.5). Park the FSM in s_bus_off while
        -- bus_off is asserted so the state is visible in waveforms; rst_i
        -- always returns the FSM to bus reintegration.
        if (fce_i.bus_off = '1') then
          state <= s_bus_off;
        else
          state <= s_bus_reintegration;
        end if;
        is_transmitter                       <= false;
        overload                             <= false;
        bit_count                            <= 0;
        data_len                             <= 0;
        crc_length                           <= c_crc_15_length;
        transmitted_bits_shift_reg                     <= (others => c_recessive);
        was_previous_frame_tx                <= false;
        ack_success_seen                     <= false;
        secondary_sample_point_error_pending <= false;
        ack_error_caused_flag                <= false;
        saw_dominant_during_flag             <= false;
        byte_index                           <= 0;
        bit_index                            <= 0;
        llc_frame                            <= (others => (others => '0'));
        crc_mismatch                         <= false;
        llc_stream_start                     <= false;
        llc_frame_len                        <= 0;
        in_data_phase                        <= false;
        mac_ser_o                            <= c_ser_fsm_if_d2s_reset;
        bs_o                                 <= c_mac_fsm_to_bs_fd_if_reset;
        pcs_o                                <= c_mac_to_pcs_if_reset;
        bs_rst                               <= '0';
        crc_o                                <= c_mac_fsm_to_crc_if_reset;
        crc_rst                              <= '0';
        fce_o                                <= c_mac_to_fce_if_reset;
      else

        -----------------------------------------------------------------
        -- Field guards
        -----------------------------------------------------------------
        v_in_arbitration_field   := state = s_arbitration;
        v_in_quiet_field         := state = s_bus_reintegration or state = s_intermission or state = s_suspend_transmission or state = s_bus_idle;

        -- BS/CRC data feed: TX uses its own drive (post-arbitration) so
        -- stuff-count and CRC track the outgoing stream, even when the bus
        -- echo lags by TDC in the FD data phase. RX and the arbitration
        -- field always feed from the bus.
        if is_transmitter and not v_in_arbitration_field then
          v_bs_crc_data := transmitted_bits_shift_reg(0);
        else
          v_bs_crc_data := pcs_i.rx_data;
        end if;
        -- TX bit-error monitoring (ISO 11898-1 6.5.4) is active in any
        -- state where the transmitter drives its own polarity and expects
        -- the bus to read back the same value. Excluded by construction:
        --   s_arbitration       - lost-arb handles drive/bus mismatch
        --   s_ack               - drives recessive expecting receivers' ACK
        --   s_error_*           - already in error frame
        --   quiet states        - no drive
        v_in_tx_drive_field      := state = s_fdf_r1_r0 or state = s_res_r0
                                    or state = s_brs or state = s_esi
                                    or state = s_dlc or state = s_data
                                    or state = s_sbc or state = s_crc
                                    or state = s_crc_delimiter
                                    or state = s_ack_delimiter
                                    or state = s_eof;

        -----------------------------------------------------------------
        -- Defaults
        -----------------------------------------------------------------
        -- bs_o.fixed_bit_stuffing_en is owned by the case branches: set
        -- on entry to s_sbc, cleared on every exit from s_sbc/s_crc.
        bs_o.data                  <= v_bs_crc_data;
        bs_o.valid                 <= '0';
        bs_rst                     <= '0';
        crc_o                      <= c_mac_fsm_to_crc_if_reset;
        crc_o.crc_poly_select      <= crc_o.crc_poly_select;
        crc_rst                    <= '0';
        fce_o                      <= c_mac_to_fce_if_reset;
        -- pcs_o.transmitting / fce_o.transmitting are level signals telling
        -- the PCS to drive tx_data (vs force recessive) and the FCE to
        -- count TX-side errors. They are set to '1' by the drive block at
        -- the end of this process whenever v_drive_bit is asserted (TX
        -- bit-drive at bit_boundary, RX-side ACK / error-flag drive at
        -- SP), and held at '1' across the rest of the bit period via NBA
        -- semantics. The quiet-field reset below clears them on entry to
        -- intermission / suspend / reintegration / idle; the drive block
        -- restores them on the same cycle when SOF is being driven from
        -- s_bus_idle, so PCS latches tx_o on time.
        fce_o.sending_error_overload_flag <= '1' when state = s_error_flag else '0';
        mac_ser_o.ready                   <= '0';
        mac_ser_o.transfer_status         <= mac_ser_o.transfer_status;
        -- Hold TDC signals until next sample point
        pcs_o.next_bit_is_res             <= '0' when pcs_i.sample_point = '1' else pcs_o.next_bit_is_res;
        pcs_o.next_bit_is_brs             <= '0' when pcs_i.sample_point = '1' else pcs_o.next_bit_is_brs;
        pcs_o.data_phase_stop             <= '0' when pcs_i.sample_point = '1' else pcs_o.data_phase_stop;
        -- do_hard_sync is a level held high during quiet states so the PCS
        -- can hard-sync to a SOF edge whenever it arrives.
        pcs_o.do_hard_sync                <= '1' when v_in_quiet_field else '0';
        -- SSP-deferred bit error detection (ISO 7.3.4). polarity_history is
        -- indexed by tdc_delay so we compare the bit currently reflected on
        -- the bus pin (via TDC) against the SSP-sampled rx_data, and defer
        -- the error to the next MAC-SP.
        if (pcs_i.secondary_sample_point = '1'
            and transmitted_bits_shift_reg(to_integer(unsigned(pcs_i.tdc_delay))) /= pcs_i.rx_data) then
          secondary_sample_point_error_pending <= true;
        end if;

        -----------------------------------------------------------------
        -- Quiet-state defaults: reset most outputs and BS/CRC.
        -- do_hard_sync is reasserted because the pcs_o reset constant has
        -- it low. pcs_o.transmitting and fce_o.transmitting are cleared
        -- here too; the drive block at the end of this process re-asserts
        -- them on the same cycle when SOF is driven from s_bus_idle (or
        -- when any other v_drive_bit fires while v_in_quiet_field, e.g.
        -- back-to-back TX SOF at the intermission bit_boundary).
        -----------------------------------------------------------------
        if (v_in_quiet_field) then
          pcs_o.do_hard_sync                   <= '1';
          pcs_o.transmitting                   <= '0';
          fce_o                                <= c_mac_to_fce_if_reset;
          mac_ser_o                            <= c_ser_fsm_if_d2s_reset;
          bs_o                                 <= c_mac_fsm_to_bs_fd_if_reset;
          secondary_sample_point_error_pending <= false;
          bs_rst                               <= '1';
          crc_rst                              <= '1';
          ack_success_seen                     <= false;
          ack_error_caused_flag                <= false;
          saw_dominant_during_flag             <= false;
        end if;

        -----------------------------------------------------------------
        -- Lost arbitration (ISO 11898-1 6.5.2). Always at SP. Flips
        -- is_transmitter false in-place; the s_arbitration case branch
        -- below then captures the winner's bits via the RX path.
        -----------------------------------------------------------------
        if pcs_i.sample_point = '1'
           and is_transmitter and v_in_arbitration_field
           and transmitted_bits_shift_reg(0) = c_recessive
           and pcs_i.rx_data = c_dominant then
          mac_ser_o.transfer_status <= c_lost_arb;
          was_previous_frame_tx     <= false;
          is_transmitter            <= false;
        end if;

        -----------------------------------------------------------------
        -- TX bit-error monitor (ISO 11898-1 6.5.4). When TX is driving
        -- a non-arbitration / non-ACK / non-error bit at SP and the bus
        -- doesn't read back what we drove, enter the error frame and
        -- skip the per-state case for this cycle. Funnel for both the
        -- SSP-deferred (FD data phase) and direct-compare (nominal
        -- phase) errors. s_ack_delimiter is excluded from direct
        -- compare because the preceding ACK slot's dominant can leak
        -- past the bit boundary via propagation delay.
        -----------------------------------------------------------------
        if pcs_i.sample_point = '1'
           and is_transmitter and v_in_tx_drive_field
           and (secondary_sample_point_error_pending
                or (not in_data_phase
                    and state /= s_ack_delimiter
                    and transmitted_bits_shift_reg(0) /= pcs_i.rx_data)) then
          if secondary_sample_point_error_pending then
            secondary_sample_point_error_pending <= false;
          end if;
          fce_o.error                <= '1';
          pcs_o.tx_data              <= not fce_i.error_active;
          pcs_o.data_phase_stop      <= '1';
          bs_o.fixed_bit_stuffing_en <= '0';
          state                      <= s_error_flag;
          bit_count                  <= 0;
          overload                   <= false;

        else
          -----------------------------------------------------------------
          -- Per-state FSM. Each branch handles its own bit_boundary TX
          -- drive AND sample-point capture / state-advance, plus any
          -- BS / CRC feed and stuff handling local to the state.
          -- Mirrors the legacy can_fsm: TX drive in the bit_boundary
          -- half, RX in the SP half, BS/CRC fed from the bus on every
          -- SP so a node losing arbitration accumulates the same state
          -- as the winner.
          -----------------------------------------------------------------
          case state is

            -----------------------------------------------------------------
            -- s_bus_reintegration: wait for 11 consecutive recessive bits
            -- before joining the bus (ISO 6.6.7.5).
            -----------------------------------------------------------------
            when s_bus_reintegration =>
              if pcs_i.sample_point = '1' then
                if pcs_i.rx_data = c_recessive then
                  if bit_count = c_bus_idle_condition_width - 1 then
                    state     <= s_bus_idle;
                    bit_count <= 0;
                  else
                    bit_count <= bit_count + 1;
                  end if;
                else
                  bit_count <= 0;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_intermission: 3-bit IFS (ISO 6.6.7.2). Dominant in bits
            -- 0..1 is overload; dominant at bit 2 is SOF (back-to-back).
            -- Back-to-back TX latches new-frame metadata and drives SOF
            -- at the bit-2 bit_boundary.
            -----------------------------------------------------------------
            when s_intermission =>
              if pcs_i.bit_boundary = '1' then
                if is_transmitter
                   and bit_count = c_intermission_width - 1
                   and mac_ser_i.valid = '1' then
                  v_data_len            := dlc_to_data_length(to_integer(unsigned(mac_ser_i.llc_metadata.dlc)), mac_ser_i.llc_metadata.fdf);
                  data_len              <= v_data_len;
                  crc_length            <= f_crc_length(v_data_len, mac_ser_i.llc_metadata.fdf);
                  crc_o.crc_poly_select <= f_crc_poly_select(v_data_len, mac_ser_i.llc_metadata.fdf);
                  drive_bit(c_dominant);
                end if;
              elsif pcs_i.sample_point = '1' then
                if pcs_i.rx_data = c_dominant then
                  if bit_count < c_intermission_width - 1 then
                    -- Overload (ISO 6.6.21.3.2 b)
                    state         <= s_error_flag;
                    bit_count     <= 0;
                    overload      <= true;
                    pcs_o.tx_data <= c_dominant;
                  else
                    -- SOF: feed BS/CRC the SOF dominant, advance.
                    bit_count      <= 0;
                    byte_index     <= 0;
                    bit_index      <= 0;
                    llc_frame      <= (others => (others => '0'));
                    bs_rst         <= '0';
                    crc_rst        <= '0';
                    bs_o.valid     <= '1';
                    bs_o.data      <= c_dominant;
                    crc_o.valid_cc <= '1';
                    crc_o.valid_fd <= '1';
                    crc_o.data_cc  <= c_dominant;
                    crc_o.data_fd  <= c_dominant;
                    state          <= s_arbitration;
                  end if;
                else
                  if bit_count < c_intermission_width - 1 then
                    bit_count <= bit_count + 1;
                  else
                    bit_count <= 0;
                    if fce_i.error_active = '0' and was_previous_frame_tx then
                      state <= s_suspend_transmission;
                    else
                      state          <= s_bus_idle;
                      is_transmitter <= false;
                    end if;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_suspend_transmission: 8-bit recessive wait after an error-
            -- passive TX frame (ISO 6.6.7.4). TX-only entry.
            -----------------------------------------------------------------
            when s_suspend_transmission =>
              if pcs_i.sample_point = '1' and pcs_i.rx_data = c_recessive then
                if bit_count = c_suspend_transmission_width - 1 then
                  state          <= s_bus_idle;
                  is_transmitter <= false;
                  bit_count      <= 0;
                else
                  bit_count <= bit_count + 1;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_bus_idle: ready for a new frame (ISO 6.6.7.3). TX entry
            -- latches is_transmitter and drives SOF at bit_boundary; RX
            -- entry triggers on dominant SOF at SP.
            -----------------------------------------------------------------
            when s_bus_idle =>
              crc_mismatch <= false;
              byte_index   <= 0;
              bit_index    <= 0;
              if pcs_i.bit_boundary = '1' then
                if mac_ser_i.valid = '1'
                   and (fce_i.error_active = '1' or not was_previous_frame_tx) then
                  is_transmitter        <= true;
                  v_data_len            := dlc_to_data_length(to_integer(unsigned(mac_ser_i.llc_metadata.dlc)), mac_ser_i.llc_metadata.fdf);
                  data_len              <= v_data_len;
                  crc_length            <= f_crc_length(v_data_len, mac_ser_i.llc_metadata.fdf);
                  crc_o.crc_poly_select <= f_crc_poly_select(v_data_len, mac_ser_i.llc_metadata.fdf);
                  drive_bit(c_dominant);
                end if;
              elsif pcs_i.sample_point = '1' and pcs_i.rx_data = c_dominant then
                bit_count      <= 0;
                bs_rst         <= '0';
                crc_rst        <= '0';
                bs_o.valid     <= '1';
                bs_o.data      <= c_dominant;
                crc_o.valid_cc <= '1';
                crc_o.valid_fd <= '1';
                crc_o.data_cc  <= c_dominant;
                crc_o.data_fd  <= c_dominant;
                state          <= s_arbitration;
                if not is_transmitter then
                  llc_frame <= (others => (others => '0'));
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_arbitration: ID-A, RTR/SRR/RRS, IDE, ID-B, RTR-ext.
            -- Both roles capture rx_data into llc_frame so the loser of
            -- arbitration retains the winner's bits (ISO 6.5.2).
            -----------------------------------------------------------------
            when s_arbitration =>
              if pcs_i.bit_boundary = '1' and is_transmitter then
                if bs_i.valid = '1' then
                  drive_bit(bs_i.data);
                else
                  case bit_count is
                    when 0 to c_arb_id_a_last | c_arb_id_b_first to c_arb_id_b_last =>
                      mac_ser_o.ready <= '1';
                      drive_bit(mac_ser_i.data);
                    when c_arb_rtr_pos =>
                      if mac_ser_i.llc_metadata.ide = c_recessive then
                        drive_bit(c_recessive);                  -- SRR (extended)
                      elsif mac_ser_i.llc_metadata.fdf = c_recessive then
                        drive_bit(mac_ser_i.llc_metadata.ftyp);  -- RTR (CC base)
                      else
                        drive_bit(c_dominant);                   -- RRS (FD base)
                      end if;
                    when c_arb_ide_pos =>
                      drive_bit(mac_ser_i.llc_metadata.ide);
                    when c_arb_rtr_ext_pos =>
                      drive_bit(mac_ser_i.llc_metadata.ftyp);
                    when others =>
                      null;
                  end case;
                end if;
              elsif pcs_i.sample_point = '1' then
                bs_o.valid <= '1';
                bs_o.data  <= v_bs_crc_data;
                if bs_i.valid = '1' then
                  -- Stuff slot: feed CRC FD only (CC CRC excludes stuff).
                  crc_o.valid_fd <= '1';
                  crc_o.data_fd  <= v_bs_crc_data;
                  if not is_transmitter and bs_i.data /= pcs_i.rx_data then
                    fce_o.sending_error_overload_flag <= '1';
                    fce_o.error                       <= '1';
                    pcs_o.data_phase_stop             <= '1';
                    drive_bit(not fce_i.error_active);
                    state                             <= s_error_flag;
                    bit_count                         <= 0;
                  end if;
                else
                  -- Real bit: feed CC and FD CRC, then capture / advance.
                  crc_o.valid_cc <= '1';
                  crc_o.valid_fd <= '1';
                  crc_o.data_cc  <= v_bs_crc_data;
                  crc_o.data_fd  <= v_bs_crc_data;
                  case bit_count is
                    when 0 to c_arb_id_a_last | c_arb_id_b_first to c_arb_id_b_last =>
                      llc_frame(c_id_offset + byte_index)((c_byte_width - 1) - bit_index) <= pcs_i.rx_data;
                      bit_index  <= 0 when bit_index = (c_byte_width - 1) else (bit_index + 1);
                      byte_index <= (byte_index + 1) when bit_index = (c_byte_width - 1);
                      bit_count  <= bit_count + 1;
                    when c_arb_rtr_pos =>
                      llc_frame(c_conf_0_offset)(c_llc_frame_ftyp) <= pcs_i.rx_data;
                      bit_count <= bit_count + 1;
                    when c_arb_ide_pos =>
                      llc_frame(c_conf_0_offset)(c_llc_frame_ide) <= pcs_i.rx_data;
                      if pcs_i.rx_data = c_dominant then
                        state     <= s_fdf_r1_r0;
                        bit_count <= 0;
                      else
                        bit_count <= bit_count + 1;
                      end if;
                    when c_arb_rtr_ext_pos =>
                      llc_frame(c_conf_0_offset)(c_llc_frame_ftyp) <= pcs_i.rx_data;
                      state     <= s_fdf_r1_r0;
                      bit_count <= 0;
                    when others =>
                      bit_count <= bit_count + 1;
                  end case;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_fdf_r1_r0: FDF (FD) / r1 (CC ext) / r0 (CC base) bit.
            -----------------------------------------------------------------
            when s_fdf_r1_r0 =>
              if pcs_i.bit_boundary = '1' and is_transmitter then
                if bs_i.valid = '1' then
                  drive_bit(bs_i.data);
                else
                  drive_bit(mac_ser_i.llc_metadata.fdf);
                end if;
              elsif pcs_i.sample_point = '1' then
                bs_o.valid <= '1';
                bs_o.data  <= v_bs_crc_data;
                if bs_i.valid = '1' then
                  crc_o.valid_fd <= '1';
                  crc_o.data_fd  <= v_bs_crc_data;
                  if not is_transmitter and bs_i.data /= pcs_i.rx_data then
                    fce_o.sending_error_overload_flag <= '1';
                    fce_o.error                       <= '1';
                    pcs_o.data_phase_stop             <= '1';
                    drive_bit(not fce_i.error_active);
                    state                             <= s_error_flag;
                    bit_count                         <= 0;
                  end if;
                else
                  -- TDC startup hint to PCS: SP of FDF, next bit is the FD
                  -- `res` so PCS begins TDC measurement at that boundary.
                  -- TX-only and only on FDF=recessive (FD frame). CC ext
                  -- also enters s_res_r0 but the next bit is r0 and TDC
                  -- is not used.
                  if is_transmitter and pcs_i.rx_data = c_recessive then
                    pcs_o.next_bit_is_res <= '1';
                  end if;
                  crc_o.valid_cc <= '1';
                  crc_o.valid_fd <= '1';
                  crc_o.data_cc  <= v_bs_crc_data;
                  crc_o.data_fd  <= v_bs_crc_data;
                  llc_frame(c_conf_0_offset)(c_llc_frame_fdf) <= pcs_i.rx_data;
                  if pcs_i.rx_data = c_recessive or llc_frame(c_conf_0_offset)(c_llc_frame_ide) = '1' then
                    state <= s_res_r0;
                  else
                    state     <= s_dlc;
                    bit_count <= 0;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_res_r0: reserved bit, fixed dominant. FD continues to s_brs;
            -- CC ext falls to s_dlc. Recessive on the bus is a form error.
            -----------------------------------------------------------------
            when s_res_r0 =>
              if llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1' then
                pcs_o.do_hard_sync <= '1';
              end if;
              if pcs_i.bit_boundary = '1' and is_transmitter then
                if bs_i.valid = '1' then
                  drive_bit(bs_i.data);
                else
                  drive_bit(c_dominant);
                end if;
              elsif pcs_i.sample_point = '1' then
                bs_o.valid <= '1';
                bs_o.data  <= v_bs_crc_data;
                if bs_i.valid = '1' then
                  crc_o.valid_fd <= '1';
                  crc_o.data_fd  <= v_bs_crc_data;
                  if not is_transmitter and bs_i.data /= pcs_i.rx_data then
                    fce_o.sending_error_overload_flag <= '1';
                    fce_o.error                       <= '1';
                    pcs_o.data_phase_stop             <= '1';
                    drive_bit(not fce_i.error_active);
                    state                             <= s_error_flag;
                    bit_count                         <= 0;
                  end if;
                else
                  crc_o.valid_cc <= '1';
                  crc_o.valid_fd <= '1';
                  crc_o.data_cc  <= v_bs_crc_data;
                  crc_o.data_fd  <= v_bs_crc_data;
                  if pcs_i.rx_data = c_recessive then
                    -- Form error. (TX winning has rx_data == drive == dom.)
                    fce_o.sending_error_overload_flag <= '1';
                    fce_o.error                       <= '1';
                    drive_bit(not fce_i.error_active);
                    bit_count                         <= 0;
                    state                             <= s_error_flag;
                  elsif llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1' then
                    -- BRS hint: SP of res, next bit is BRS. Both roles
                    -- need this so the PCS handles the bit-rate switch.
                    pcs_o.next_bit_is_brs <= '1';
                    state                 <= s_brs;
                  else
                    state     <= s_dlc;
                    bit_count <= 0;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_brs: BRS bit (FD only). Recessive switches to data phase.
            -----------------------------------------------------------------
            when s_brs =>
              if pcs_i.bit_boundary = '1' and is_transmitter then
                if bs_i.valid = '1' then
                  drive_bit(bs_i.data);
                else
                  drive_bit(mac_ser_i.llc_metadata.brs);
                end if;
              elsif pcs_i.sample_point = '1' then
                bs_o.valid <= '1';
                bs_o.data  <= v_bs_crc_data;
                if bs_i.valid = '1' then
                  crc_o.valid_fd <= '1';
                  crc_o.data_fd  <= v_bs_crc_data;
                  if not is_transmitter and bs_i.data /= pcs_i.rx_data then
                    fce_o.sending_error_overload_flag <= '1';
                    fce_o.error                       <= '1';
                    pcs_o.data_phase_stop             <= '1';
                    drive_bit(not fce_i.error_active);
                    state                             <= s_error_flag;
                    bit_count                         <= 0;
                  end if;
                else
                  crc_o.valid_cc <= '1';
                  crc_o.valid_fd <= '1';
                  crc_o.data_cc  <= v_bs_crc_data;
                  crc_o.data_fd  <= v_bs_crc_data;
                  llc_frame(c_conf_0_offset)(c_llc_frame_brs) <= pcs_i.rx_data;
                  in_data_phase                               <= (pcs_i.rx_data = c_recessive);
                  state                                       <= s_esi;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_esi: ESI bit (FD only). Active=dominant, passive=recessive.
            -----------------------------------------------------------------
            when s_esi =>
              if pcs_i.bit_boundary = '1' and is_transmitter then
                if bs_i.valid = '1' then
                  drive_bit(bs_i.data);
                else
                  drive_bit(mac_ser_i.llc_metadata.esi);
                end if;
              elsif pcs_i.sample_point = '1' then
                bs_o.valid <= '1';
                bs_o.data  <= v_bs_crc_data;
                if bs_i.valid = '1' then
                  crc_o.valid_fd <= '1';
                  crc_o.data_fd  <= v_bs_crc_data;
                  if not is_transmitter and bs_i.data /= pcs_i.rx_data then
                    fce_o.sending_error_overload_flag <= '1';
                    fce_o.error                       <= '1';
                    pcs_o.data_phase_stop             <= '1';
                    drive_bit(not fce_i.error_active);
                    state                             <= s_error_flag;
                    bit_count                         <= 0;
                  end if;
                else
                  crc_o.valid_cc <= '1';
                  crc_o.valid_fd <= '1';
                  crc_o.data_cc  <= v_bs_crc_data;
                  crc_o.data_fd  <= v_bs_crc_data;
                  llc_frame(c_conf_0_offset)(c_llc_frame_esi) <= pcs_i.rx_data;
                  state                                       <= s_dlc;
                  bit_count                                   <= 0;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_dlc: 4-bit DLC. data_len / crc_length / poly_select are
            -- re-derived at the last bit from the just-captured DLC plus
            -- llc_frame[fdf]; for TX winning this re-derives the same
            -- values set at SOF entry.
            -----------------------------------------------------------------
            when s_dlc =>
              if pcs_i.bit_boundary = '1' and is_transmitter then
                if bs_i.valid = '1' then
                  drive_bit(bs_i.data);
                else
                  drive_bit(mac_ser_i.llc_metadata.dlc(c_dlc_field_width - 1 - bit_count));
                end if;
              elsif pcs_i.sample_point = '1' then
                bs_o.valid <= '1';
                bs_o.data  <= v_bs_crc_data;
                if bs_i.valid = '1' then
                  crc_o.valid_fd <= '1';
                  crc_o.data_fd  <= v_bs_crc_data;
                  if not is_transmitter and bs_i.data /= pcs_i.rx_data then
                    fce_o.sending_error_overload_flag <= '1';
                    fce_o.error                       <= '1';
                    pcs_o.data_phase_stop             <= '1';
                    drive_bit(not fce_i.error_active);
                    state                             <= s_error_flag;
                    bit_count                         <= 0;
                  end if;
                else
                  crc_o.valid_cc <= '1';
                  crc_o.valid_fd <= '1';
                  crc_o.data_cc  <= v_bs_crc_data;
                  crc_o.data_fd  <= v_bs_crc_data;
                  llc_frame(c_conf_1_offset)(c_llc_frame_dlc_start - bit_count) <= pcs_i.rx_data;
                  if bit_count = c_dlc_field_width - 1 then
                    v_dlc_vec                                    := llc_frame(c_conf_1_offset)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end);
                    v_dlc_vec(c_llc_frame_dlc_start - bit_count) := pcs_i.rx_data;
                    v_data_len                                   := dlc_to_data_length(to_integer(unsigned(v_dlc_vec)), llc_frame(c_conf_0_offset)(c_llc_frame_fdf));
                    data_len              <= v_data_len;
                    crc_length            <= f_crc_length(v_data_len, llc_frame(c_conf_0_offset)(c_llc_frame_fdf));
                    crc_o.crc_poly_select <= f_crc_poly_select(v_data_len, llc_frame(c_conf_0_offset)(c_llc_frame_fdf));
                    bit_count             <= 0;
                    bit_index             <= 0;
                    byte_index            <= 0;
                    if v_data_len > 0 and llc_frame(c_conf_0_offset)(c_llc_frame_ftyp) = '0' then
                      state <= s_data;
                    elsif llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1' then
                      state                      <= s_sbc;
                      bs_o.fixed_bit_stuffing_en <= '1';
                    else
                      state <= s_crc;
                    end if;
                  else
                    bit_count <= bit_count + 1;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_data: data field. 0..8 bytes (CC) or 0..64 bytes (FD).
            -----------------------------------------------------------------
            when s_data =>
              if pcs_i.bit_boundary = '1' and is_transmitter then
                if bs_i.valid = '1' then
                  drive_bit(bs_i.data);
                else
                  mac_ser_o.ready <= '1';
                  drive_bit(mac_ser_i.data);
                end if;
              elsif pcs_i.sample_point = '1' then
                bs_o.valid <= '1';
                bs_o.data  <= v_bs_crc_data;
                if bs_i.valid = '1' then
                  crc_o.valid_fd <= '1';
                  crc_o.data_fd  <= v_bs_crc_data;
                  if not is_transmitter and bs_i.data /= pcs_i.rx_data then
                    fce_o.sending_error_overload_flag <= '1';
                    fce_o.error                       <= '1';
                    pcs_o.data_phase_stop             <= '1';
                    drive_bit(not fce_i.error_active);
                    state                             <= s_error_flag;
                    bit_count                         <= 0;
                  end if;
                else
                  crc_o.valid_cc <= '1';
                  crc_o.valid_fd <= '1';
                  crc_o.data_cc  <= v_bs_crc_data;
                  crc_o.data_fd  <= v_bs_crc_data;
                  llc_frame(c_data_offset + byte_index)((c_byte_width - 1) - bit_index) <= pcs_i.rx_data;
                  if byte_index = data_len - 1 and bit_index = c_byte_width - 1 then
                    if llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1' then
                      state                      <= s_sbc;
                      bs_o.fixed_bit_stuffing_en <= '1';
                    else
                      state <= s_crc;
                    end if;
                    bit_count  <= 0;
                    bit_index  <= 0;
                    byte_index <= 0;
                  else
                    bit_index  <= 0 when bit_index = c_byte_width - 1 else bit_index + 1;
                    byte_index <= byte_index + 1 when bit_index = c_byte_width - 1;
                    if is_transmitter then
                      bit_count <= bit_count + 1;
                    end if;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_sbc: 4-bit stuff-bit count (FD only, ISO 6.6.11.5). Fixed-
            -- stuff field. CRC FD is fed on real bits only. Both roles run
            -- the SBC-mismatch compare; TX winning never trips it.
            -----------------------------------------------------------------
            when s_sbc =>
              if pcs_i.bit_boundary = '1' and is_transmitter then
                if bs_i.valid = '1' then
                  drive_bit(bs_i.data);
                else
                  drive_bit(bs_i.stuff_bit_count((c_sbc_field_width - 1) - bit_count));
                end if;
              elsif pcs_i.sample_point = '1' then
                bs_o.valid <= '1';
                bs_o.data  <= v_bs_crc_data;
                if bs_i.valid = '1' then
                  if not is_transmitter and bs_i.data /= pcs_i.rx_data then
                    fce_o.sending_error_overload_flag <= '1';
                    fce_o.error                       <= '1';
                    pcs_o.data_phase_stop             <= '1';
                    drive_bit(not fce_i.error_active);
                    state                             <= s_error_flag;
                    bit_count                         <= 0;
                  end if;
                else
                  crc_o.valid_fd <= '1';
                  crc_o.data_fd  <= v_bs_crc_data;
                  if pcs_i.rx_data /= bs_i.stuff_bit_count((c_sbc_field_width - 1) - bit_count) then
                    fce_o.sending_error_overload_flag <= '1';
                    fce_o.error                       <= '1';
                    drive_bit(not fce_i.error_active);
                    pcs_o.data_phase_stop             <= '1';
                    bs_o.fixed_bit_stuffing_en        <= '0';
                    state                             <= s_error_flag;
                    bit_count                         <= 0;
                  elsif bit_count = c_sbc_field_width - 1 then
                    state     <= s_crc;
                    bit_count <= 0;
                  else
                    bit_count <= bit_count + 1;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_crc: CRC field (15/17/21 bits). Fixed-stuff field. Both
            -- roles run the CRC mismatch compare; TX winning never trips
            -- it. At the last CRC bit assert data_phase_stop so the PCS
            -- phase-switches at the delim SP (ISO 6.6.10.5).
            -----------------------------------------------------------------
            when s_crc =>
              if pcs_i.bit_boundary = '1' and is_transmitter then
                if bs_i.valid = '1' then
                  drive_bit(bs_i.data);
                else
                  drive_bit(crc_i.crc((c_crc_21_length - 1) - bit_count));
                end if;
              elsif pcs_i.sample_point = '1' then
                bs_o.valid <= '1';
                bs_o.data  <= v_bs_crc_data;
                if bs_i.valid = '1' then
                  if not is_transmitter and bs_i.data /= pcs_i.rx_data then
                    fce_o.sending_error_overload_flag <= '1';
                    fce_o.error                       <= '1';
                    pcs_o.data_phase_stop             <= '1';
                    drive_bit(not fce_i.error_active);
                    state                             <= s_error_flag;
                    bit_count                         <= 0;
                  end if;
                else
                  if pcs_i.rx_data /= crc_i.crc((c_crc_21_length - 1) - bit_count) then
                    crc_mismatch <= true;
                  end if;
                  if bit_count = crc_length - 1 then
                    pcs_o.data_phase_stop      <= '1';
                    bs_o.fixed_bit_stuffing_en <= '0';
                    state                      <= s_crc_delimiter;
                    bit_count                  <= 0;
                  else
                    bit_count <= bit_count + 1;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_crc_delimiter: single recessive bit between CRC and ACK.
            -- RX drives the dominant ACK at this SP (latched at next
            -- bit_boundary_d); TX listens. RX CRC error enters the error
            -- flag instead.
            -----------------------------------------------------------------
            when s_crc_delimiter =>
              if pcs_i.bit_boundary = '1' and is_transmitter then
                drive_bit(c_recessive);
              elsif pcs_i.sample_point = '1' then
                in_data_phase <= false;
                if not is_transmitter and crc_mismatch then
                  fce_o.sending_error_overload_flag <= '1';
                  fce_o.error                       <= '1';
                  drive_bit(not fce_i.error_active);
                  state                             <= s_error_flag;
                  bit_count                         <= 0;
                else
                  if not is_transmitter then
                    drive_bit(c_dominant);
                  end if;
                  state     <= s_ack;
                  bit_count <= 0;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_ack: ACK slot (1 bit CC, 2 bits FD; ISO 6.6.10.6). TX
            -- listens (no bit_boundary drive). RX drove dominant via
            -- s_crc_delimiter and now releases the bus.
            -----------------------------------------------------------------
            when s_ack =>
              if pcs_i.sample_point = '1' then
                if is_transmitter then
                  if pcs_i.rx_data = c_dominant then
                    ack_success_seen <= true;
                  end if;
                else
                  pcs_o.transmitting <= '0';
                  if bit_count = 0 then
                    pcs_o.tx_data <= c_recessive;
                  end if;
                end if;
                if llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1' and bit_count = 0 then
                  bit_count <= bit_count + 1;
                else
                  state     <= s_ack_delimiter;
                  bit_count <= 0;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_ack_delimiter: single recessive bit after ACK slot. TX
            -- accepts a late dominant or signals ACK error. RX form-error
            -- check (ISO 6.6.21.3.2).
            -----------------------------------------------------------------
            when s_ack_delimiter =>
              if pcs_i.bit_boundary = '1' and is_transmitter then
                drive_bit(c_recessive);
              elsif pcs_i.sample_point = '1' then
                if is_transmitter then
                  if not ack_success_seen and pcs_i.rx_data = c_dominant then
                    ack_success_seen <= true;
                  end if;
                  if ack_success_seen or pcs_i.rx_data = c_dominant then
                    state <= s_eof;
                  else
                    -- Missing ACK: enter error flag; defer fce_o.error to flag end.
                    ack_error_caused_flag      <= true;
                    pcs_o.tx_data              <= not fce_i.error_active;
                    pcs_o.data_phase_stop      <= '1';
                    bs_o.fixed_bit_stuffing_en <= '0';
                    state                      <= s_error_flag;
                    bit_count                  <= 0;
                    overload                   <= false;
                  end if;
                else
                  if pcs_i.rx_data = c_dominant then
                    fce_o.sending_error_overload_flag <= '1';
                    fce_o.error                       <= '1';
                    pcs_o.tx_data                     <= not fce_i.error_active;
                    state                             <= s_error_flag;
                    bit_count                         <= 0;
                  else
                    state     <= s_eof;
                    bit_count <= 0;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_eof: 7 recessive bits. TX evaluates ACK error at bit 0;
            -- both roles flag frame valid at the second-last bit (ISO
            -- 6.6.15.2).
            -----------------------------------------------------------------
            when s_eof =>
              if pcs_i.bit_boundary = '1' and is_transmitter then
                drive_bit(c_recessive);
              elsif pcs_i.sample_point = '1' then
                if is_transmitter then
                  if bit_count = 0 and not ack_success_seen then
                    -- Missing ACK
                    ack_error_caused_flag      <= true;
                    pcs_o.tx_data              <= not fce_i.error_active;
                    pcs_o.data_phase_stop      <= '1';
                    bs_o.fixed_bit_stuffing_en <= '0';
                    state                      <= s_error_flag;
                    bit_count                  <= 0;
                    overload                   <= false;
                  elsif bit_count = c_eof_field_width - 1 then
                    mac_ser_o.transfer_status <= c_transmitted;
                    was_previous_frame_tx     <= true;
                    fce_o.successful_transfer <= '1';
                    state                     <= s_intermission;
                    bit_count                 <= 0;
                  elsif bit_count = c_eof_field_width - 2 then
                    -- Frame valid (TX self-reception so the LLC RX byte
                    -- stream is populated on the transmitter too).
                    llc_stream_start <= true;
                    byte_index       <= 0;
                    llc_frame_len    <= c_data_offset + data_len;
                    bit_count        <= bit_count + 1;
                  else
                    bit_count <= bit_count + 1;
                  end if;
                else
                  if pcs_i.rx_data = c_dominant then
                    fce_o.sending_error_overload_flag <= '1';
                    fce_o.error                       <= '1';
                    if bit_count = c_eof_field_width - 1 then
                      drive_bit(c_dominant);
                      overload    <= true;
                      fce_o.error <= '0';
                    else
                      drive_bit(not fce_i.error_active);
                    end if;
                    state     <= s_error_flag;
                    bit_count <= 0;
                  else
                    if bit_count = c_eof_field_width - 1 then
                      state     <= s_intermission;
                      bit_count <= 0;
                    elsif bit_count = c_eof_field_width - 2 then
                      fce_o.successful_transfer <= '1';
                      llc_stream_start          <= true;
                      byte_index                <= 0;
                      llc_frame_len             <= c_data_offset + data_len;
                      bit_count                 <= bit_count + 1;
                    else
                      bit_count <= bit_count + 1;
                    end if;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- Error frame: 6 active-error bits, error-flag-check, optional
            -- dominant-delimiter wait, then 8-bit recessive delimiter.
            -- Both roles drive at every bit_boundary (active = dominant,
            -- passive = recessive).
            -----------------------------------------------------------------
            when s_error_flag =>
              if pcs_i.bit_boundary = '1' then
                if not overload then
                  drive_bit(not fce_i.error_active);
                else
                  drive_bit(c_dominant);
                end if;
              elsif pcs_i.sample_point = '1' then
                if is_transmitter then
                  if not overload then
                    mac_ser_o.transfer_status <= c_disturbed;
                    was_previous_frame_tx     <= true;
                  end if;
                  if bit_count < c_error_flag_width - 1 then
                    if not overload and fce_i.error_active = '0' and pcs_i.rx_data = c_dominant then
                      -- Passive flag: dominant from another node restarts
                      -- the equal-bit counter (ISO 8.1.4.2.c.ex1).
                      saw_dominant_during_flag <= true;
                      bit_count                <= 0;
                    else
                      bit_count <= bit_count + 1;
                    end if;
                  else
                    bit_count <= 0;
                    overload  <= false;
                    state     <= s_error_flag_check;
                    if ack_error_caused_flag then
                      fce_o.error <= '1';
                      if fce_i.error_active = '0' and not saw_dominant_during_flag then
                        fce_o.passive_tx_ack_error_exempt_1 <= '1';
                      end if;
                    end if;
                  end if;
                else
                  if bit_count < c_error_flag_width - 1 then
                    bit_count <= bit_count + 1;
                  else
                    bit_count <= 0;
                    overload  <= false;
                    state     <= s_error_flag_check;
                  end if;
                end if;
              end if;

            when s_error_flag_check =>
              if pcs_i.bit_boundary = '1' then
                drive_bit(c_recessive);
              elsif pcs_i.sample_point = '1' then
                if pcs_i.rx_data = c_dominant then
                  state     <= s_error_dominant_delim;
                  bit_count <= 1;
                  if not is_transmitter then
                    fce_o.primary_error <= '1';
                  end if;
                else
                  state     <= s_error_delimiter;
                  bit_count <= 1;
                end if;
              end if;

            when s_error_dominant_delim =>
              if pcs_i.bit_boundary = '1' then
                drive_bit(c_recessive);
              elsif pcs_i.sample_point = '1' then
                if pcs_i.rx_data = c_dominant then
                  if bit_count = c_error_delimiter_width - 1 then
                    fce_o.error_delimiter_too_late <= '1';
                    bit_count                      <= 1;
                  else
                    bit_count <= bit_count + 1;
                  end if;
                else
                  state     <= s_error_delimiter;
                  bit_count <= 1;
                end if;
              end if;

            when s_error_delimiter =>
              if pcs_i.bit_boundary = '1' then
                drive_bit(c_recessive);
              elsif pcs_i.sample_point = '1' then
                if pcs_i.rx_data = c_dominant then
                  -- Form error / overload (ISO 6.6.21.3.2): re-enter flag.
                  drive_bit(not fce_i.error_active);
                  fce_o.error <= '1';
                  state       <= s_error_flag;
                  bit_count   <= 0;
                  overload    <= false;
                else
                  if bit_count = c_error_delimiter_width - 1 then
                    state     <= s_intermission;
                    bit_count <= 0;
                  else
                    bit_count <= bit_count + 1;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- Bus off state. Stay here until rst clears bus_off.
            -----------------------------------------------------------------
            when s_bus_off =>
              state <= s_bus_reintegration;

            when others =>
              state     <= s_bus_reintegration;
              bit_count <= 0;

          end case;
        end if;

        -- Clear stream_start once it has been picked up by the streamer
        llc_stream_start <= not llc_stream_done when llc_stream_done;

      end if;
    end if;
  end process p_fsm;

end architecture rtl;

-- eof
