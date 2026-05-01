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
    variable v_in_dynamic_stuff_field : boolean;
    variable v_in_fixed_stuff_field   : boolean;
    variable v_in_quiet_field         : boolean;
    variable v_in_tx_drive_field      : boolean;
    -- TX bit-drive variables
    variable v_tx_polarity            : std_logic;
    variable v_drive_bit              : boolean;
    variable v_is_stuff_bit           : boolean;
    -- Local data-length helper (used by TX frame setup and RX DLC decode)
    variable v_data_len               : natural range 0 to c_max_data_bytes;
    -- RX-only DLC vector helper
    variable v_dlc_vec                : std_logic_vector(c_llc_frame_dlc_start downto c_llc_frame_dlc_end);
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
        v_in_dynamic_stuff_field := v_in_arbitration_field or state = s_fdf_r1_r0 or state = s_res_r0 or state = s_brs or state = s_esi or state = s_dlc or state = s_data;
        v_in_fixed_stuff_field   := state = s_sbc or state = s_crc;
        v_in_quiet_field         := state = s_bus_reintegration or state = s_intermission or state = s_suspend_transmission or state = s_bus_idle;
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
        bs_o.data                  <= pcs_i.rx_data;
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
        -- Working variables
        -----------------------------------------------------------------
        v_drive_bit     := false;
        v_is_stuff_bit  := false;
        v_tx_polarity   := c_recessive;

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
        -- SP-gated FSM.
        --
        -- Lost arbitration (ISO 11898-1 6.5.2): when we drove recessive
        -- and the bus came back dominant during s_arbitration, report
        -- c_lost_arb and flip is_transmitter to false in-place. The s_arbitration
        -- case branch then runs in RX mode for the current and remaining
        -- arbitration bits, so the winner's ID is captured into llc_frame
        -- and the node continues as a receiver.
        --
        -- The remaining branches are mutually exclusive:
        --   1. TX SSP/SP bit error (only when is_transmitter is still true)
        --   2. stuff-bit handling
        --   3. real-bit FSM case
        -----------------------------------------------------------------
        if pcs_i.sample_point = '1' then

          if is_transmitter and v_in_arbitration_field
             and transmitted_bits_shift_reg(0) = c_recessive
             and pcs_i.rx_data = c_dominant then
            mac_ser_o.transfer_status <= c_lost_arb;
            was_previous_frame_tx     <= false;
            is_transmitter            <= false;
          end if;

          if is_transmitter and v_in_tx_drive_field
             and (secondary_sample_point_error_pending
                  or (not in_data_phase
                      and state /= s_ack_delimiter
                      and transmitted_bits_shift_reg(0) /= pcs_i.rx_data)) then
            -- TX bit error: drive first error-flag bit, end data phase,
            -- disable fixed stuffing, enter s_error_flag. The error-frame
            -- status (transfer_status, was_previous_frame_tx) is handled
            -- by s_error_flag itself. SSP-deferred errors (data phase) and
            -- direct polarity mismatch (nominal phase) share this branch;
            -- s_ack_delimiter is excluded from direct compare because the
            -- preceding ACK slot's dominant can leak past the bit boundary
            -- via propagation delay.
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

          elsif bs_i.valid = '1' and (v_in_dynamic_stuff_field or v_in_fixed_stuff_field) then
            -- Stuff bit. Both TX and RX feed BS/CRC from the bus
            -- (rx_data) so a node losing arbitration still has a CRC
            -- state matching the winner. TX drive of the stuff bit
            -- happens in the bit_boundary block below.
            bs_o.valid <= '1';
            bs_o.data  <= pcs_i.rx_data;
            if v_in_dynamic_stuff_field then
              crc_o.valid_fd <= '1';
              crc_o.data_fd  <= pcs_i.rx_data;
            end if;
            if not is_transmitter and bs_i.data /= pcs_i.rx_data then
              -- RX-side stuff error.
              fce_o.sending_error_overload_flag <= '1';
              fce_o.error                       <= '1';
              pcs_o.data_phase_stop             <= '1';
              pcs_o.tx_data                     <= not fce_i.error_active;
              pcs_o.transmitting                <= '1';
              state                             <= s_error_flag;
              bit_count                         <= 0;
            end if;

          else
            -- Real bit. Always feed BS/CRC from the bus (rx_data) at
            -- every SP, regardless of TX or RX role. Same rationale as
            -- the stuff branch: keeps state correct for both winners and
            -- losers of arbitration.
            if v_in_dynamic_stuff_field or v_in_fixed_stuff_field then
              bs_o.valid <= '1';
              bs_o.data  <= pcs_i.rx_data;
            end if;
            if v_in_dynamic_stuff_field then
              crc_o.valid_cc <= '1';
              crc_o.valid_fd <= '1';
              crc_o.data_cc  <= pcs_i.rx_data;
              crc_o.data_fd  <= pcs_i.rx_data;
            elsif state = s_sbc then
              crc_o.valid_fd <= '1';
              crc_o.data_fd  <= pcs_i.rx_data;
            end if;

            case state is

            -----------------------------------------------------------------
            -- s_bus_reintegration: wait for 11 consecutive recessive bits
            -- before joining the bus (ISO 6.6.7.5).
            -----------------------------------------------------------------
            when s_bus_reintegration =>
              if (pcs_i.rx_data = c_recessive) then
                if (bit_count = c_bus_idle_condition_width - 1) then
                  state     <= s_bus_idle;
                  bit_count <= 0;
                else
                  bit_count <= bit_count + 1;
                end if;
              else
                bit_count <= 0;
              end if;

            -----------------------------------------------------------------
            -- s_intermission: 3-bit inter-frame spacing (ISO 6.6.7.2).
            -- Dominant in bits 0..1 is overload; dominant at bit 2 is SOF.
            -----------------------------------------------------------------
            when s_intermission =>
              if (pcs_i.rx_data = c_dominant) then
                if (bit_count < c_intermission_width - 1) then
                  -- Overload (ISO 6.6.21.3.2 b). Drive the first flag bit.
                  state         <= s_error_flag;
                  bit_count     <= 0;
                  overload      <= true;
                  pcs_o.tx_data <= c_dominant;
                else
                  -- SOF detected at bit 2: feed BS/CRC SOF dominant and
                  -- transition to s_arbitration. Per-frame buffers are reset
                  -- on BOTH paths because s_arbitration captures rx_data into
                  -- llc_frame for both TX and RX (see lost-arb in 6.5.2).
                  -- is_transmitter and frame metadata are latched at the
                  -- intermission bit-2 bit_boundary (TX drive case below);
                  -- nothing role-specific belongs here.
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
                if (bit_count < c_intermission_width - 1) then
                  bit_count <= bit_count + 1;
                else
                  bit_count <= 0;
                  if (fce_i.error_active = '0' and was_previous_frame_tx) then
                    state <= s_suspend_transmission;
                  else
                    state          <= s_bus_idle;
                    is_transmitter <= false;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_suspend_transmission: 8-bit recessive wait after an error-
            -- passive TX frame (ISO 6.6.7.4). TX-only entry.
            -----------------------------------------------------------------
            when s_suspend_transmission =>
              if (pcs_i.rx_data = c_recessive) then
                if (bit_count = c_suspend_transmission_width - 1) then
                  state          <= s_bus_idle;
                  is_transmitter <= false;
                  bit_count      <= 0;
                else
                  bit_count <= bit_count + 1;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_bus_idle: bus is recessive, ready for a new frame (ISO
            -- 6.6.7.3). TX entry: mac_ser_i.valid; RX entry: dominant SOF.
            -----------------------------------------------------------------
            when s_bus_idle =>
              crc_mismatch <= false;
              byte_index   <= 0;
              bit_index    <= 0;

              -- SOF observed on the bus -> transition to s_arbitration.
              -- For TX this is our own drive looped back through the PCS;
              -- for RX it is another node's SOF. The is_transmitter flag
              -- and SOF drive are set at bit_boundary (s_bus_idle case in
              -- the bit_boundary block below) when the LLC has a frame.
              if pcs_i.rx_data = c_dominant then
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
            --
            -- bit_count = 0..10              -> ID-A (11 bits)
            -- bit_count = 11                 -> RTR (CC base) / SRR (ext) / RRS (FD base)
            -- bit_count = 12                 -> IDE
            -- bit_count = 13..30 (extended)  -> ID-B (18 bits)
            -- bit_count = 31     (extended)  -> RTR after ID-B
            --
            -- Both TX and RX capture pcs_i.rx_data into llc_frame so that
            -- a node losing arbitration retains the bits already on the
            -- bus and continues as a receiver (ISO 11898-1 6.5.2). While
            -- still winning arbitration our drive equals the bus value,
            -- so writing rx_data is also correct for TX.
            -----------------------------------------------------------------
            when s_arbitration =>

              -- Capture into llc_frame
              if (bit_count <= c_arb_id_a_last) or
                 (bit_count >= c_arb_id_b_first and bit_count <= c_arb_id_b_last) then
                -- ID-A or ID-B bit: stream into the ID byte field.
                llc_frame(c_id_offset + byte_index)((c_byte_width - 1) - bit_index) <= pcs_i.rx_data;
                bit_index  <= 0 when bit_index = (c_byte_width - 1) else (bit_index + 1);
                byte_index <= (byte_index + 1) when bit_index = (c_byte_width - 1);
              elsif (bit_count = c_arb_rtr_pos) or (bit_count = c_arb_rtr_ext_pos) then
                -- RTR/SRR/RRS bit. For ext frames the second visit (after
                -- ID-B) carries RTR and overwrites the SRR placeholder.
                llc_frame(c_conf_0_offset)(c_llc_frame_ftyp) <= pcs_i.rx_data;
              elsif (bit_count = c_arb_ide_pos) then
                llc_frame(c_conf_0_offset)(c_llc_frame_ide) <= pcs_i.rx_data;
              end if;

              -- (TX drive moved to bit_boundary block below.)

              -- Field exits and bit_count advance.
              -- After IDE: base format exits to s_fdf_r1_r0; extended
              -- continues to ID-B. After RTR-ext: always exit.
              if (bit_count = c_arb_ide_pos) then
                -- Base format (IDE dominant) exits to s_fdf_r1_r0; extended
                -- (IDE recessive) continues into ID-B. pcs_i.rx_data is the
                -- right source for both roles: TX winning has rx_data ==
                -- drive == metadata.ide (loopback); after lost-arb rx_data
                -- is the bus winner's value. RX uses it directly.
                if (pcs_i.rx_data = c_dominant) then
                  state     <= s_fdf_r1_r0;
                  bit_count <= 0;
                else
                  bit_count <= bit_count + 1;
                end if;
              elsif (bit_count = c_arb_rtr_ext_pos) then
                state     <= s_fdf_r1_r0;
                bit_count <= 0;
              else
                bit_count <= bit_count + 1;
              end if;

            -----------------------------------------------------------------
            -- s_fdf_r1_r0: FDF bit on FD frames, r1/r0 on CC frames.
            -----------------------------------------------------------------
            when s_fdf_r1_r0 =>
              -- Capture FDF/r1 into llc_frame. Same-cycle NBA semantics
              -- mean we must use pcs_i.rx_data directly (not the freshly
              -- written llc_frame[fdf]) for the state-exit decision.
              -- llc_frame[ide] was captured one cycle earlier in
              -- s_arbitration so reading it here is safe. For TX winning,
              -- rx_data == drive == metadata.fdf, so this is role-agnostic.
              llc_frame(c_conf_0_offset)(c_llc_frame_fdf) <= pcs_i.rx_data;
              if (pcs_i.rx_data = c_recessive) or (llc_frame(c_conf_0_offset)(c_llc_frame_ide) = '1') then
                state <= s_res_r0;
              else
                state     <= s_dlc;
                bit_count <= 0;
              end if;

            -----------------------------------------------------------------
            -- s_res_r0: reserved bit, fixed dominant (ISO 6.6.10.2). On TX FD
            -- entry this SP also starts TDC (next driven bit = res edge).
            -----------------------------------------------------------------
            when s_res_r0 =>
              -- PCS gates hard-sync internally (mac_i.transmitting='0'),
              -- so we don't need a role guard here.
              if llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1' then
                pcs_o.do_hard_sync <= '1';
              end if;
              -- Form error: reserved bit must be dominant (ISO 6.6.10.2).
              -- For TX winning, rx_data == drive == dominant by construction,
              -- so this branch never fires for the transmitter; running it
              -- unconditionally is therefore safe.
              if (pcs_i.rx_data = c_recessive) then
                fce_o.sending_error_overload_flag <= '1';
                fce_o.error                       <= '1';
                v_tx_polarity                     := not fce_i.error_active;
                v_drive_bit                       := true;
                bit_count                         <= 0;
                state                             <= s_error_flag;
              else
                if (llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1') then
                  -- FD: enter BRS. The TDC-startup pulse next_bit_is_res
                  -- is TX-only; next_bit_is_brs is RX-only. Both feed PCS
                  -- bit-rate-switch logic and stay role-gated.
                  if is_transmitter then
                    pcs_o.next_bit_is_res <= '1';
                  else
                    pcs_o.next_bit_is_brs <= '1';
                  end if;
                  state <= s_brs;
                else
                  state     <= s_dlc;
                  bit_count <= 0;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_brs: BRS bit (FD only). Recessive switches into data phase.
            -----------------------------------------------------------------
            when s_brs =>
              if is_transmitter then
                in_data_phase <= (mac_ser_i.llc_metadata.brs = c_recessive);
              else
                llc_frame(c_conf_0_offset)(c_llc_frame_brs) <= pcs_i.rx_data;
                in_data_phase                              <= (pcs_i.rx_data = c_recessive);
              end if;
              state <= s_esi;

            -----------------------------------------------------------------
            -- s_esi: ESI bit (FD only). Active = dominant, passive = recessive.
            -----------------------------------------------------------------
            when s_esi =>
              if not is_transmitter then
                llc_frame(c_conf_0_offset)(c_llc_frame_esi) <= pcs_i.rx_data;
              end if;
              state     <= s_dlc;
              bit_count <= 0;

            -----------------------------------------------------------------
            -- s_dlc: 4-bit data length code. RX also decodes data_len, CRC
            -- length and polynomial select once the DLC is complete.
            -----------------------------------------------------------------
            when s_dlc =>
              -- Capture DLC bit into the conf_1 byte (both TX and RX).
              -- For winning TX, rx_data == our drive of dlc(bit), so the
              -- captured value matches what we would have placed there
              -- via metadata. This lets the TX self-receive into
              -- llc_frame so the RX byte stream is correct on the
              -- transmitter as well.
              llc_frame(c_conf_1_offset)(c_llc_frame_dlc_start - bit_count) <= pcs_i.rx_data;
              if (bit_count = c_dlc_field_width - 1) then
                bit_count  <= 0;
                bit_index  <= 0;
                byte_index <= 0;
                if is_transmitter then
                  -- TX uses metadata (data_len already set at SOF entry).
                  if (data_len > 0 and mac_ser_i.llc_metadata.ftyp = '0') then
                    state <= s_data;
                  elsif (mac_ser_i.llc_metadata.fdf = '1') then
                    state                      <= s_sbc;
                    bs_o.fixed_bit_stuffing_en <= '1';
                  else
                    state <= s_crc;
                  end if;
                else
                  -- RX decodes data_len from the just-captured DLC.
                  v_dlc_vec                                    := llc_frame(c_conf_1_offset)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end);
                  v_dlc_vec(c_llc_frame_dlc_start - bit_count) := pcs_i.rx_data;
                  v_data_len                                   := dlc_to_data_length(to_integer(unsigned(v_dlc_vec)), llc_frame(c_conf_0_offset)(c_llc_frame_fdf));
                  data_len              <= v_data_len;
                  crc_length            <= f_crc_length(v_data_len, llc_frame(c_conf_0_offset)(c_llc_frame_fdf));
                  crc_o.crc_poly_select <= f_crc_poly_select(v_data_len, llc_frame(c_conf_0_offset)(c_llc_frame_fdf));
                  if (v_data_len > 0 and llc_frame(c_conf_0_offset)(c_llc_frame_ftyp) = '0') then
                    state <= s_data;
                  elsif (llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1') then
                    state                      <= s_sbc;
                    bs_o.fixed_bit_stuffing_en <= '1';
                  else
                    state <= s_crc;
                  end if;
                end if;
              else
                bit_count <= bit_count + 1;
              end if;

            -----------------------------------------------------------------
            -- s_data: data field. 0..8 bytes (CC) or 0..64 bytes (FD).
            -----------------------------------------------------------------
            when s_data =>
              -- Capture data bit into llc_frame (both TX and RX). For
              -- winning TX, rx_data == own drive, so self-reception
              -- populates llc_frame correctly for the LLC byte stream.
              llc_frame(c_data_offset + byte_index)((c_byte_width - 1) - bit_index) <= pcs_i.rx_data;
              if (byte_index = (data_len - 1)) and (bit_index = (c_byte_width - 1)) then
                if (llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1') then
                  state                      <= s_sbc;
                  bs_o.fixed_bit_stuffing_en <= '1';
                else
                  state <= s_crc;
                end if;
                bit_count  <= 0;
                bit_index  <= 0;
                byte_index <= 0;
              else
                bit_index  <= 0 when bit_index = (c_byte_width - 1) else (bit_index + 1);
                byte_index <= (byte_index + 1) when bit_index = (c_byte_width - 1);
                if is_transmitter then
                  bit_count <= bit_count + 1;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_sbc: 4-bit stuff-bit count (FD only, ISO 6.6.11.5).
            -----------------------------------------------------------------
            when s_sbc =>
              if is_transmitter then
                if (bit_count = c_sbc_field_width - 1) then
                  state     <= s_crc;
                  bit_count <= 0;
                else
                  bit_count <= bit_count + 1;
                end if;
              else
                -- RX form error: SBC mismatch.
                if (pcs_i.rx_data /= bs_i.stuff_bit_count((c_sbc_field_width - 1) - bit_count)) then
                  fce_o.sending_error_overload_flag <= '1';
                  fce_o.error                       <= '1';
                  v_tx_polarity                     := not fce_i.error_active;
                  v_drive_bit                       := true;
                  pcs_o.data_phase_stop             <= '1';
                  bs_o.fixed_bit_stuffing_en        <= '0';
                  state                             <= s_error_flag;
                  bit_count                         <= 0;
                elsif bit_count = (c_sbc_field_width - 1) then
                  state     <= s_crc;
                  bit_count <= 0;
                else
                  bit_count <= bit_count + 1;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_crc: CRC field, 15/17/21 bits. At the last CRC bit assert
            -- data_phase_stop so the PCS phase-switches at the delim SP
            -- (ISO 6.6.10.5). Both TX and RX must do this in lockstep.
            -----------------------------------------------------------------
            when s_crc =>
              if not is_transmitter then
                if (pcs_i.rx_data /= crc_i.crc((c_crc_21_length - 1) - bit_count)) then
                  crc_mismatch <= true;
                end if;
              end if;
              if (bit_count = crc_length - 1) then
                pcs_o.data_phase_stop      <= '1';
                bs_o.fixed_bit_stuffing_en <= '0';
                state                      <= s_crc_delimiter;
                bit_count                  <= 0;
              else
                bit_count <= bit_count + 1;
              end if;

            -----------------------------------------------------------------
            -- s_crc_delimiter: single recessive bit between CRC and ACK
            -- (ISO 6.6.10.5). PCS phase switch happens at this SP.
            -- in_data_phase is cleared so the SP-based bit-error check is
            -- only active from ACK bc=0 onward (the delim's SP samples
            -- before TDC has settled). RX has no direct form-error check
            -- on the delim per ISO; corruption is caught via CRC mismatch
            -- or absent ACK.
            -----------------------------------------------------------------
            when s_crc_delimiter =>
              in_data_phase <= false;
              if is_transmitter then
                state     <= s_ack;
                bit_count <= 0;
              else
                if crc_mismatch then
                  fce_o.sending_error_overload_flag <= '1';
                  fce_o.error                       <= '1';
                  v_tx_polarity                     := not fce_i.error_active;
                  v_drive_bit                       := true;
                  state                             <= s_error_flag;
                  bit_count                         <= 0;
                else
                  -- RX drives ACK dominant during the upcoming s_ack bit
                  -- period: drive at SP applies via NBA, PCS latches at
                  -- the next bit_boundary_d, tx_o = dom during s_ack.
                  v_tx_polarity := c_dominant;
                  v_drive_bit   := true;
                  state         <= s_ack;
                  bit_count     <= 0;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_ack: ACK slot (1 bit CC, 2 bits FD; ISO 6.6.10.6). TX
            -- listens for any dominant bit. RX drove the dominant ACK via
            -- s_crc_delimiter and here releases the bus so the next bit
            -- (delimiter for CC, second ACK slot then delimiter for FD) is
            -- recessive. fce_o.transmitting stays '1' so the FCE treats
            -- ACK-slot errors as TX-side per ISO 8.1.4.2,b. Both modes
            -- exit to s_ack_delimiter for the recessive delimiter bit
            -- (form-error check is performed there, not here).
            -----------------------------------------------------------------
            when s_ack =>
              if is_transmitter then
                if (pcs_i.rx_data = c_dominant) then
                  ack_success_seen <= true;
                end if;
                if (mac_ser_i.llc_metadata.fdf = '1' and bit_count = 0) then
                  bit_count <= bit_count + 1;
                else
                  state     <= s_ack_delimiter;
                  bit_count <= 0;
                end if;
              else
                pcs_o.transmitting <= '0';
                if (bit_count = 0) then
                  -- End of first ACK slot bit (dominant ACK we drove).
                  -- Release the bus so the next bit is recessive.
                  pcs_o.tx_data <= c_recessive;
                  if (llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1') then
                    bit_count <= 1;                     -- FD: enter second ACK slot bit
                  else
                    state     <= s_ack_delimiter;       -- CC: straight to delimiter
                    bit_count <= 0;
                  end if;
                else
                  -- FD only: end of second ACK slot bit.
                  state     <= s_ack_delimiter;
                  bit_count <= 0;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_ack_delimiter: single recessive bit after the ACK slot. TX
            -- accepts a late dominant here (covers bus delays > ACK-slot/2)
            -- or signals ACK error. RX checks the delimiter bit is
            -- recessive and raises a form error otherwise (ISO 6.6.21.3.2).
            -----------------------------------------------------------------
            when s_ack_delimiter =>
              if is_transmitter then
                if (not ack_success_seen and pcs_i.rx_data = c_dominant) then
                  ack_success_seen <= true;
                end if;
                if ack_success_seen or pcs_i.rx_data = c_dominant then
                  state <= s_eof;
                else
                  -- Missing ACK: defer fce_o.error to flag end (see s_eof).
                  ack_error_caused_flag      <= true;
                  pcs_o.tx_data              <= not fce_i.error_active;
                  pcs_o.data_phase_stop      <= '1';
                  bs_o.fixed_bit_stuffing_en <= '0';
                  state                      <= s_error_flag;
                  bit_count                  <= 0;
                  overload                   <= false;
                end if;
              else
                if (pcs_i.rx_data = c_dominant) then
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

            -----------------------------------------------------------------
            -- s_eof: 7 recessive bits. TX evaluates ACK error at bit 0;
            -- RX flags frame-valid at the second-last bit (ISO 6.6.15.2).
            -----------------------------------------------------------------
            when s_eof =>
              if is_transmitter then
                if (bit_count = 0 and not ack_success_seen) then
                  -- Missing ACK: enter error flag, defer fce_o.error to flag
                  -- end with passive-TX exemption (ISO 6.6.20).
                  ack_error_caused_flag      <= true;
                  pcs_o.tx_data              <= not fce_i.error_active;
                  pcs_o.data_phase_stop      <= '1';
                  bs_o.fixed_bit_stuffing_en <= '0';
                  state                      <= s_error_flag;
                  bit_count                  <= 0;
                  overload                   <= false;
                else
                  if (bit_count = c_eof_field_width - 1) then
                    mac_ser_o.transfer_status <= c_transmitted;
                    was_previous_frame_tx     <= true;
                    fce_o.successful_transfer <= '1';
                    state                     <= s_intermission;
                    bit_count                 <= 0;
                  elsif (bit_count = c_eof_field_width - 2) then
                    -- TX self-reception: same frame-valid trigger as RX so
                    -- the LLC RX stream gets populated for the transmitter
                    -- node too (consistency with the loopback model).
                    llc_stream_start <= true;
                    byte_index       <= 0;
                    llc_frame_len    <= c_data_offset + data_len;
                    bit_count        <= bit_count + 1;
                  else
                    bit_count <= bit_count + 1;
                  end if;
                end if;
              else
                if (pcs_i.rx_data = c_dominant) then
                  -- Last bit dominant is overload, otherwise bit error.
                  fce_o.sending_error_overload_flag <= '1';
                  fce_o.error                       <= '1';
                  if bit_count = (c_eof_field_width - 1) then
                    v_tx_polarity := c_dominant;
                    overload      <= true;
                    fce_o.error   <= '0';
                  else
                    v_tx_polarity := not fce_i.error_active;
                  end if;
                  v_drive_bit := true;
                  state        <= s_error_flag;
                  bit_count    <= 0;
                else
                  if bit_count = (c_eof_field_width - 1) then
                    state     <= s_intermission;
                    bit_count <= 0;
                  elsif bit_count = (c_eof_field_width - 2) then
                    -- Frame valid (ISO 6.6.15.2): start streaming to LLC.
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

            -----------------------------------------------------------------
            -- Send out 6 dominant bits, this will induce a stuff bit error at
            -- all other controllers. In error passive it "sends" 1 bits and
            -- receivers in error passive must wait for 6 recessive
            -- (6.6.5.2 Last paragraph).
            -----------------------------------------------------------------
            when s_error_flag =>
              if is_transmitter then
                -- TX-side error frame (excluding overload): mark disturbed
                -- and remember TX so next intermission applies suspend.
                if not overload then
                  mac_ser_o.transfer_status <= c_disturbed;
                  was_previous_frame_tx     <= true;
                end if;
                if (bit_count < c_error_flag_width - 1) then
                  if (not overload and fce_i.error_active = '0' and pcs_i.rx_data = c_dominant) then
                    -- 8.1.4.2.c.ex1: dominant from another node during the
                    -- passive flag restarts the equal-bit counter. Latched
                    -- for the ACK-error exemption (6.6.20).
                    saw_dominant_during_flag <= true;
                    bit_count                <= 0;
                  else
                    bit_count <= bit_count + 1;
                  end if;
                else
                  bit_count <= 0;
                  overload  <= false;
                  state     <= s_error_flag_check;
                  -- Defer ACK-error TEC update to flag end and apply passive
                  -- TX exemption when no other node co-signalled the error.
                  if ack_error_caused_flag then
                    fce_o.error <= '1';
                    if fce_i.error_active = '0' and not saw_dominant_during_flag then
                      fce_o.passive_tx_ack_error_exempt_1 <= '1';
                    end if;
                  end if;
                end if;
              else
                -- RX: count 6 flag bits (driven by held tx_data from error
                -- entry), then advance to s_error_flag_check.
                if bit_count < c_error_flag_width - 1 then
                  bit_count <= bit_count + 1;
                else
                  bit_count <= 0;
                  overload  <= false;
                  state     <= s_error_flag_check;
                end if;
              end if;

            -----------------------------------------------------------------
            -- Check if the bit after the error flag is dominant. That means
            -- it was the first to detect the error.
            -----------------------------------------------------------------
            when s_error_flag_check =>
              if pcs_i.rx_data = c_dominant then
                state     <= s_error_dominant_delim;
                bit_count <= 1;
                if not is_transmitter then                                         -- 8.1.4.2.b
                  fce_o.primary_error <= '1';
                end if;
              else
                state     <= s_error_delimiter;
                -- Either we have counted a dominant or recessive bit, so we
                -- only need to count from 1.
                bit_count <= 1;
              end if;

            -----------------------------------------------------------------
            -- Wait for the bus to recessive.
            -- 8.1.4.2.f - We can tolerate up to 7 consecutive dominant bits
            -- after sending an active error flag or overload flag, or 14 if
            -- passive error flag. And after that every 8 should count up in
            -- error count.
            -----------------------------------------------------------------
            when s_error_dominant_delim =>
              if pcs_i.rx_data = c_dominant then                            -- 8.1.4.2.f
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

            -----------------------------------------------------------------
            -- We also need to wait for 8 recessive bits. We have already sent
            -- 1, so we need to wait for 7 more. 6.6.5.3.
            -----------------------------------------------------------------
            when s_error_delimiter =>
              if pcs_i.rx_data = c_dominant then                            -- Form error and overload (6.6.21.3.2)
                v_tx_polarity := not fce_i.error_active;
                v_drive_bit   := true;
                fce_o.error   <= '1';
                state         <= s_error_flag;
                bit_count     <= 0;
                overload      <= false;
              else
                if bit_count = c_error_delimiter_width - 1 then
                  state     <= s_intermission;
                  bit_count <= 0;
                else
                  bit_count <= bit_count + 1;
                end if;
              end if;

            -----------------------------------------------------------------
            -- Bus off state. Stay here until node is reset.
            -----------------------------------------------------------------
            when s_bus_off =>
              state <= s_bus_reintegration;

            when others =>
              state     <= s_bus_reintegration;
              bit_count <= 0;

            end case;
          end if;  -- close error / lost-arb / stuff / real-bit if-elsif-else
        end if;    -- close pcs_i.sample_point

        -----------------------------------------------------------------
        -- bit_boundary block: TX drive decisions.
        --
        -- Fires once per bit period at end-of-phase_seg2, after the SP
        -- block has fed BS/CRC with the bit just sampled and after BS/CRC
        -- have had time to update their output. Reading bs_i here lets TX
        -- insert stuff bits in the correct slot (the upcoming bit period)
        -- without lookahead. PCS latches mac_i.tx_data one clock after
        -- bit_boundary (bit_boundary_d), so the v_tx_polarity assigned
        -- here lands on tx_o for the next bit period. Mirrors the
        -- transmit_i pattern used by the legacy can_fsm.
        -----------------------------------------------------------------
        if pcs_i.bit_boundary = '1' then
          if is_transmitter and bs_i.valid = '1'
             and (v_in_dynamic_stuff_field or v_in_fixed_stuff_field) then
            -- BS predicts a stuff bit for the upcoming slot.
            v_tx_polarity  := bs_i.data;
            v_drive_bit    := true;
            v_is_stuff_bit := true;
          else
            case state is

            -- s_bus_idle: TX entry happens here. When the LLC has a
            -- frame ready and we are eligible to start (error-active or
            -- not the previous TX), latch is_transmitter and drive SOF
            -- on the SAME clock. Mirrors the legacy can_fsm s_idle
            -- pattern (transmit_i drives SOF and sets is_transmitter
            -- together). The SP block transitions to s_arbitration once
            -- the SOF is observed on the bus.
            when s_bus_idle =>
              if mac_ser_i.valid = '1'
                 and (fce_i.error_active = '1' or not was_previous_frame_tx) then
                is_transmitter        <= true;
                v_data_len            := dlc_to_data_length(to_integer(unsigned(mac_ser_i.llc_metadata.dlc)), mac_ser_i.llc_metadata.fdf);
                data_len              <= v_data_len;
                crc_length            <= f_crc_length(v_data_len, mac_ser_i.llc_metadata.fdf);
                crc_o.crc_poly_select <= f_crc_poly_select(v_data_len, mac_ser_i.llc_metadata.fdf);
                v_tx_polarity         := c_dominant;
                v_drive_bit           := true;
              end if;

            when s_intermission =>
              -- Back-to-back TX entry. At the last IFS bit (bit 2) we may
              -- drive SOF dominant. is_transmitter is sticky from the
              -- previous frame; if it is true we latch the new frame's
              -- metadata here (mirroring s_bus_idle above) so the SP block
              -- in s_intermission can stay role-independent. Earlier
              -- intermission bits stay recessive.
              if is_transmitter
                 and bit_count = c_intermission_width - 1
                 and mac_ser_i.valid = '1' then
                v_data_len                 := dlc_to_data_length(to_integer(unsigned(mac_ser_i.llc_metadata.dlc)), mac_ser_i.llc_metadata.fdf);
                data_len                   <= v_data_len;
                crc_length                 <= f_crc_length(v_data_len, mac_ser_i.llc_metadata.fdf);
                crc_o.crc_poly_select      <= f_crc_poly_select(v_data_len, mac_ser_i.llc_metadata.fdf);
                transmitted_bits_shift_reg <= (0 => c_dominant, others => c_recessive);
                v_tx_polarity              := c_dominant;
                v_drive_bit                := true;
              end if;

            when s_arbitration =>
              if is_transmitter then
                if bit_count <= c_arb_id_a_last
                   or (bit_count >= c_arb_id_b_first and bit_count <= c_arb_id_b_last) then
                  mac_ser_o.ready <= '1';
                  v_tx_polarity   := mac_ser_i.data;
                  v_drive_bit     := true;
                elsif bit_count = c_arb_rtr_pos then
                  if mac_ser_i.llc_metadata.ide = c_recessive then
                    v_tx_polarity := c_recessive;            -- SRR (extended)
                  elsif mac_ser_i.llc_metadata.fdf = c_recessive then
                    v_tx_polarity := mac_ser_i.llc_metadata.ftyp;  -- RTR (CC base)
                  else
                    v_tx_polarity := c_dominant;             -- RRS (FD base)
                  end if;
                  v_drive_bit := true;
                elsif bit_count = c_arb_ide_pos then
                  v_tx_polarity := mac_ser_i.llc_metadata.ide;
                  v_drive_bit   := true;
                elsif bit_count = c_arb_rtr_ext_pos then
                  v_tx_polarity := mac_ser_i.llc_metadata.ftyp;  -- RTR-ext
                  v_drive_bit   := true;
                end if;
              end if;

            when s_fdf_r1_r0 =>
              if is_transmitter then
                v_tx_polarity := mac_ser_i.llc_metadata.fdf;
                v_drive_bit   := true;
              end if;

            when s_res_r0 =>
              if is_transmitter then
                v_tx_polarity := c_dominant;
                v_drive_bit   := true;
              end if;

            when s_brs =>
              if is_transmitter then
                v_tx_polarity         := mac_ser_i.llc_metadata.brs;
                pcs_o.next_bit_is_brs <= mac_ser_i.llc_metadata.brs;
                v_drive_bit           := true;
              end if;

            when s_esi =>
              if is_transmitter then
                v_tx_polarity := mac_ser_i.llc_metadata.esi;
                v_drive_bit   := true;
              end if;

            when s_dlc =>
              if is_transmitter then
                v_tx_polarity := mac_ser_i.llc_metadata.dlc(c_dlc_field_width - 1 - bit_count);
                v_drive_bit   := true;
              end if;

            when s_data =>
              if is_transmitter then
                mac_ser_o.ready <= '1';
                v_tx_polarity   := mac_ser_i.data;
                v_drive_bit     := true;
              end if;

            when s_sbc =>
              if is_transmitter then
                v_tx_polarity := bs_i.stuff_bit_count((c_sbc_field_width - 1) - bit_count);
                v_drive_bit   := true;
              end if;

            when s_crc =>
              if is_transmitter then
                v_tx_polarity := crc_i.crc((c_crc_21_length - 1) - bit_count);
                v_drive_bit   := true;
              end if;

            when s_crc_delimiter | s_ack_delimiter | s_eof =>
              if is_transmitter then
                v_tx_polarity := c_recessive;
                v_drive_bit   := true;
              end if;

            -- Error frame: both TX and RX drive 6 active-error bits
            -- (dominant for active, recessive for passive). RX entry is
            -- via the SP-time direct drives; subsequent bit_boundaries
            -- come through here.
            when s_error_flag =>
              if not overload then
                v_tx_polarity := not fce_i.error_active;
              else
                v_tx_polarity := c_dominant;
              end if;
              v_drive_bit := true;

            when s_error_flag_check
               | s_error_dominant_delim
               | s_error_delimiter =>
              v_tx_polarity := c_recessive;
              v_drive_bit   := true;

            when others =>
              null;

            end case;
          end if;
        end if;

        -----------------------------------------------------------------
        -- Drive block. Applies whenever v_drive_bit was set, whether by
        -- the SP block (RX-side ACK / error-flag drive) or by the
        -- bit_boundary block (TX drive). pcs_o.transmitting and
        -- fce_o.transmitting are asserted here so the PCS latches tx_o
        -- on the SAME clock as the drive, even if quiet-state defaults
        -- earlier in the process tried to clear them. BS/CRC are NOT fed
        -- here -- they are fed at SP from rx_data so the loser of
        -- arbitration accumulates the same state as the winner.
        -- polarity_history shifts unconditionally so SOF (driven from the
        -- s_bus_idle case the same clock is_transmitter is latched) lands
        -- in slot 0 in time for the lost-arb compare at the next SP.
        -----------------------------------------------------------------
        if v_drive_bit then
          pcs_o.tx_data              <= v_tx_polarity;
          transmitted_bits_shift_reg <= transmitted_bits_shift_reg(c_tdc_polarity_depth - 2 downto 0) & v_tx_polarity;
          pcs_o.transmitting         <= '1';
          fce_o.transmitting         <= '1';
        end if;

        -- Clear stream_start once it has been picked up by the streamer
        llc_stream_start <= not llc_stream_done when llc_stream_done;

      end if;
    end if;
  end process p_fsm;

end architecture rtl;

-- eof
