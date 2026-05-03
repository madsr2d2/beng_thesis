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
--
--              Refactor history and design rationale:
--                docs/can_mac_fsm_history.md
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
  -- Constants
  -----------------------------------------------------------------
  -- s_arbitration field positions (indexed by bit_count) ---------
  -- ID-base -> RTR/SRR/RRS -> IDE (if extended frame) -> ID-ext -> RTR-ext
  constant c_arb_id_base_last : natural := c_base_id_width - 1;                       -- 10
  constant c_arb_rtr_pos      : natural := c_base_id_width;                           -- 11
  constant c_arb_ide_pos      : natural := c_base_id_width + 1;                       -- 12
  constant c_arb_id_ext_first : natural := c_base_id_width + 2;                       -- 13
  constant c_arb_id_ext_last  : natural := c_base_id_width + 1 + c_extended_id_width; -- 30
  constant c_arb_rtr_ext_pos  : natural := c_base_id_width + 2 + c_extended_id_width; -- 31
  -----------------------------------------------------------------

  -----------------------------------------------------------------
  -- Signals
  -----------------------------------------------------------------
  -- Shared by both TX and RX paths --------------------------------
  signal state                                : t_fsm_state;
  signal is_transmitter                       : boolean;
  signal bit_count                            : natural range 0 to c_max_mac_frame_length;
  signal data_len                             : natural range 0 to c_max_data_bytes;
  signal crc_length                           : natural range 0 to c_crc_21_length;
  signal overload                             : boolean;
  -- True when BRS=recessive; suppresses SP bit-error check (SSP used instead, ISO 7.3.4).
  signal in_data_phase                        : boolean;
  -----------------------------------------------------------------

  -- TX-mode ------------------------------------------------------
  signal transmitted_bits_shift_reg           : std_logic_vector(c_tdc_polarity_depth - 1 downto 0);
  signal was_previous_frame_tx                : boolean;
  signal ack_success_seen                     : boolean;
  -- High when bit error was detected at the secondary sample point in the data phase
  signal bit_error_at_ssp                     : boolean;
  signal ack_error_caused_flag                : boolean;
  signal saw_dominant_during_flag             : boolean;
  -- TX drive strobe: sample_point registered twice (SP+1 settles state/bit_count, SP+2 lets BS compute valid).
  signal drive_bit_d                          : std_logic;
  signal drive_bit                            : std_logic;
  -----------------------------------------------------------------

  -- RX-mode ------------------------------------------------------
  signal byte_index                           : natural range 0 to c_internal_llc_frame_len - 1;
  signal bit_index                            : natural range 0 to c_byte_width - 1;
  signal stream_index                         : natural range 0 to c_internal_llc_frame_len - 1;
  signal llc_frame                            : t_llc_frame;
  signal llc_stream_start                     : boolean;
  signal llc_stream_done                      : boolean;
  signal llc_frame_len                        : natural range 0 to c_internal_llc_frame_len;
  -----------------------------------------------------------------

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
    -- Local helpers for DLC decode (TX and RX) and shared next-state decision.
    variable v_data_len               : natural range 0 to c_max_data_bytes;
    variable v_dlc_vec                : std_logic_vector(c_llc_frame_dlc_start downto c_llc_frame_dlc_end);
    variable v_fdf                    : std_logic;
    variable v_ftyp                   : std_logic;
    -- TX post-arb feeds own drive; RX and arb feed rx_data (avoids TDC echo lag).
    variable v_bs_crc_data         : std_logic;
    -- Drive intent committed at end of process; see drive-commit block.
    variable v_drive_now           : boolean;
    variable v_drive_polarity      : std_logic;
    -- True in dynamic-stuff region (s_arbitration through s_data).
    variable v_in_dynamic_stuff    : boolean;
    -- True in states where TX bit-error monitor is active (all active-frame except s_arb, s_ack).
    variable v_tx_bit_error_state  : boolean;
    -- True when TX SP echo differs from driven polarity (SP-based check only; SSP handles data phase).
    variable v_bit_error_at_sp       : boolean;

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1' or fce_i.bus_off = '1') then
        -- Bus-off recovery is handled by the FCE (counts 128 sequences of 11 recessive bits per ISO 8.1.4.5)
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
        bit_error_at_ssp <= false;
        ack_error_caused_flag                <= false;
        saw_dominant_during_flag             <= false;
        byte_index                           <= 0;
        bit_index                            <= 0;
        llc_frame                            <= (others => (others => '0'));
        llc_stream_start                     <= false;
        llc_frame_len                        <= 0;
        in_data_phase                        <= false;
        drive_bit_d                          <= '0';
        drive_bit                            <= '0';
        mac_ser_o                            <= c_ser_fsm_if_d2s_reset;
        bs_o                                 <= c_mac_fsm_to_bs_fd_if_reset;
        pcs_o                                <= c_mac_to_pcs_if_reset;
        bs_rst                               <= '0';
        crc_o                                <= c_mac_fsm_to_crc_if_reset;
        crc_rst                              <= '0';
        fce_o                                <= c_mac_to_fce_if_reset;
      else


        -- TX post-arbitration feeds BS/CRC from its own drive to avoid TDC-delayed echo lag.
        if is_transmitter and state /= s_arbitration then
          v_bs_crc_data := transmitted_bits_shift_reg(0);
        else
          v_bs_crc_data := pcs_i.rx_data;
        end if;

        v_in_dynamic_stuff   := state = s_arbitration or state = s_fdf_r1_r0 or state = s_res_r0 or state = s_brs or state = s_esi or state = s_dlc or state = s_data;
        v_tx_bit_error_state := state = s_fdf_r1_r0 or state = s_res_r0
                                or state = s_brs    or state = s_esi    or state = s_dlc or state = s_data
                                or state = s_sbc    or state = s_crc    or state = s_crc_delimiter
                                or state = s_ack_delimiter or state = s_eof;
        v_bit_error_at_sp      := not in_data_phase and state /= s_ack_delimiter and transmitted_bits_shift_reg(0) /= pcs_i.rx_data;


        drive_bit_d <= pcs_i.sample_point;
        drive_bit   <= drive_bit_d;

        -----------------------------------------------------------------
        -- Defaults
        -----------------------------------------------------------------
        v_drive_now      := false;
        v_drive_polarity := c_recessive;
        bs_o.data                         <= v_bs_crc_data;
        bs_o.valid                        <= '0';
        bs_rst                            <= '0';
        crc_o                             <= c_mac_fsm_to_crc_if_reset;
        crc_o.crc_poly_select             <= crc_o.crc_poly_select;
        crc_rst                           <= '0';
        fce_o                             <= c_mac_to_fce_if_reset;
        fce_o.sending_error_overload_flag <= '1' when state = s_error_flag else '0';
        mac_ser_o.ready                   <= '0';
        mac_ser_o.transfer_status         <= mac_ser_o.transfer_status;
        -- TDC hint pulses cleared each SP; case branches (s_fdf_r1_r0, s_res_r0) re-assert on the next SP.
        if pcs_i.sample_point = '1' then
          pcs_o.next_bit_is_res <= '0';
          pcs_o.next_bit_is_brs <= '0';
          pcs_o.data_phase_stop <= '0';
        end if;

        -- Hard-sync allowed in quiet/waiting states and at the FDF→res edge in FD frames.
        -- PCS gates the actual sync on mac_i.transmitting = '0'.
        pcs_o.do_hard_sync <= '1' when  state = s_intermission
                                    or state = s_bus_idle
                                    or state = s_suspend_transmission
                                    or (state = s_res_r0 and llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1')
                                  else '0';

        -- SSP bit-error (ISO 7.3.4): flag mismatch between delayed echo and bus at secondary SP.
        if pcs_i.secondary_sample_point = '1' and transmitted_bits_shift_reg(to_integer(unsigned(pcs_i.tdc_delay))) /= pcs_i.rx_data then
          bit_error_at_ssp <= true;
        end if;

        -- Quiet states: reset active-frame signals on every cycle.
        if state = s_bus_reintegration or state = s_intermission
           or state = s_suspend_transmission or state = s_bus_idle then
          fce_o                                <= c_mac_to_fce_if_reset;
          mac_ser_o                            <= c_ser_fsm_if_d2s_reset;
          bs_o                                 <= c_mac_fsm_to_bs_fd_if_reset;
          bit_error_at_ssp <= false;
          bs_rst                               <= '1';
          crc_rst                              <= '1';
          ack_success_seen                     <= false;
          ack_error_caused_flag                <= false;
          saw_dominant_during_flag             <= false;
        end if;

        -----------------------------------------------------------------
        -- Lost arbitration (ISO 6.5.2): demote to receiver.
        -- Kept outside the chain so the s_arbitration case still runs.
        -----------------------------------------------------------------
        if pcs_i.sample_point = '1' and is_transmitter and state = s_arbitration
           and transmitted_bits_shift_reg(0) = c_recessive
           and pcs_i.rx_data = c_dominant then
          mac_ser_o.transfer_status <= c_lost_arb;
          was_previous_frame_tx     <= false;
          is_transmitter            <= false;
        end if;

        -----------------------------------------------------------------
        -- SP / drive_bit chain. Runs before the per-state case so error
        -- detection and stuff-bit handling intercept before state advance.
        --   1. TX bit-error   SP, TX, active-frame state, echo mismatch
        --   2. RX stuff-error SP, RX, stuff slot, polarity mismatch
        --   3. SP stuff-bit   SP, stuff slot (no error): feed BS/CRC only
        --   4. BB stuff-bit   drive_bit, TX, stuff slot: drive the bit
        --   5. Real-bit       everything else: BS/CRC feed + per-state case
        -----------------------------------------------------------------
        if pcs_i.sample_point = '1' and is_transmitter and v_tx_bit_error_state and (bit_error_at_ssp or v_bit_error_at_sp) then
          -- 1. TX bit-error (ISO 6.5.4)
          if bit_error_at_ssp then
            bit_error_at_ssp <= false;
          end if;
          fce_o.error                <= '1';
          pcs_o.tx_data              <= not fce_i.error_active;
          pcs_o.data_phase_stop      <= '1';
          in_data_phase              <= false;
          bs_o.fixed_bit_stuffing_en <= '0';
          state                      <= s_error_flag;
          bit_count                  <= 0;
          overload                   <= false;

        elsif pcs_i.sample_point = '1' and not is_transmitter
              and bs_i.valid = '1' and bs_i.data /= pcs_i.rx_data
              and v_in_dynamic_stuff then
          -- 2. RX stuff-error (ISO 6.5.5)
          fce_o.sending_error_overload_flag <= '1';
          fce_o.error                       <= '1';
          pcs_o.data_phase_stop             <= '1';
          in_data_phase                     <= false;
          v_drive_polarity                  := not fce_i.error_active;
          v_drive_now                       := true;
          state                             <= s_error_flag;
          bit_count                         <= 0;

        elsif pcs_i.sample_point = '1' and bs_i.valid = '1' then
          -- 3. SP stuff-bit: feed BS/CRC (CC excludes stuff bits; FD s_sbc/s_crc excluded)
          bs_o.valid <= '1';
          bs_o.data  <= v_bs_crc_data;
          if v_in_dynamic_stuff then
            crc_o.valid_fd <= '1';
            crc_o.data_fd  <= v_bs_crc_data;
          end if;

        elsif drive_bit = '1' and is_transmitter and bs_i.valid = '1' then
          -- 4. BB stuff-bit: drive the stuffed polarity onto the bus
          v_drive_polarity := bs_i.data;
          v_drive_now      := true;

        else
          -- 5. Real-bit cycle (SP or drive_bit) or quiet/error state
          if pcs_i.sample_point = '1' and (v_in_dynamic_stuff or state = s_sbc or state = s_crc) then
            bs_o.valid <= '1';
            bs_o.data  <= v_bs_crc_data;
            if v_in_dynamic_stuff or state = s_sbc then
              crc_o.valid_fd <= '1';
              crc_o.data_fd  <= v_bs_crc_data;
            end if;
            if v_in_dynamic_stuff then
              crc_o.valid_cc <= '1';
              crc_o.data_cc  <= v_bs_crc_data;
            end if;
          end if;

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
              if drive_bit = '1' then
                if is_transmitter and bit_count = c_intermission_width - 1 and mac_ser_i.valid = '1' then
                  v_data_len            := dlc_to_data_length(to_integer(unsigned(mac_ser_i.llc_metadata.dlc)), mac_ser_i.llc_metadata.fdf);
                  data_len              <= v_data_len;
                  crc_length            <= f_crc_length(v_data_len, mac_ser_i.llc_metadata.fdf);
                  crc_o.crc_poly_select <= f_crc_poly_select(v_data_len, mac_ser_i.llc_metadata.fdf);
                  v_drive_polarity := c_dominant;
                  v_drive_now      := true;
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
              byte_index <= 0;
              bit_index  <= 0;
              if drive_bit = '1' then
                if mac_ser_i.valid = '1' and (fce_i.error_active = '1' or not was_previous_frame_tx) then
                  is_transmitter        <= true;
                  v_data_len            := dlc_to_data_length(to_integer(unsigned(mac_ser_i.llc_metadata.dlc)), mac_ser_i.llc_metadata.fdf);
                  data_len              <= v_data_len;
                  crc_length            <= f_crc_length(v_data_len, mac_ser_i.llc_metadata.fdf);
                  crc_o.crc_poly_select <= f_crc_poly_select(v_data_len, mac_ser_i.llc_metadata.fdf);
                  v_drive_polarity := c_dominant;
                  v_drive_now      := true;
                end if;
              elsif pcs_i.sample_point = '1' and pcs_i.rx_data = c_dominant then
                -- RX SOF: same feed as s_intermission SOF branch.
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
              if drive_bit = '1' and is_transmitter then
                case bit_count is
                  when 0 to c_arb_id_base_last | c_arb_id_ext_first to c_arb_id_ext_last =>
                    mac_ser_o.ready  <= '1';
                    v_drive_polarity := mac_ser_i.data;
                    v_drive_now      := true;
                  when c_arb_rtr_pos =>
                    v_drive_now := true;
                    if mac_ser_i.llc_metadata.ide = c_recessive then
                      v_drive_polarity := c_recessive;                  -- SRR (extended)
                    elsif mac_ser_i.llc_metadata.fdf = c_recessive then
                      v_drive_polarity := mac_ser_i.llc_metadata.ftyp;  -- RTR (CC base)
                    else
                      v_drive_polarity := c_dominant;                   -- RRS (FD base)
                    end if;
                  when c_arb_ide_pos =>
                    v_drive_polarity := mac_ser_i.llc_metadata.ide;
                    v_drive_now      := true;
                  when c_arb_rtr_ext_pos =>
                    v_drive_polarity := mac_ser_i.llc_metadata.ftyp;
                    v_drive_now      := true;
                  when others =>
                    null;
                end case;
              elsif pcs_i.sample_point = '1' then
                case bit_count is
                  when 0 to c_arb_id_base_last | c_arb_id_ext_first to c_arb_id_ext_last =>
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

            -----------------------------------------------------------------
            -- s_fdf_r1_r0: FDF (FD) / r1 (CC ext) / r0 (CC base) bit.
            -----------------------------------------------------------------
            when s_fdf_r1_r0 =>
              if drive_bit = '1' and is_transmitter then
                v_drive_polarity := mac_ser_i.llc_metadata.fdf;
                v_drive_now      := true;
              elsif pcs_i.sample_point = '1' then
                -- TDC startup hint: SP of FDF, next bit is the FD `res`
                -- (PCS begins TDC measurement at that boundary). TX-only
                -- and only on FDF=recessive (FD frame).
                if is_transmitter and pcs_i.rx_data = c_recessive then
                  pcs_o.next_bit_is_res <= '1';
                end if;
                llc_frame(c_conf_0_offset)(c_llc_frame_fdf) <= pcs_i.rx_data;
                if pcs_i.rx_data = c_recessive or llc_frame(c_conf_0_offset)(c_llc_frame_ide) = '1' then
                  state <= s_res_r0;
                else
                  state     <= s_dlc;
                  bit_count <= 0;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_res_r0: reserved bit, fixed dominant. FD continues to s_brs;
            -- CC ext falls to s_dlc. Recessive on the bus is a form error.
            -----------------------------------------------------------------
            when s_res_r0 =>
              if drive_bit = '1' and is_transmitter then
                v_drive_polarity := c_dominant;
                v_drive_now      := true;
              elsif pcs_i.sample_point = '1' then
                if pcs_i.rx_data = c_recessive then
                  -- Form error (res must be dominant; TX winning never trips).
                  fce_o.sending_error_overload_flag <= '1';
                  fce_o.error                       <= '1';
                  v_drive_polarity := not fce_i.error_active;
                  v_drive_now      := true;
                  bit_count                         <= 0;
                  state                             <= s_error_flag;
                elsif llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1' then
                  -- BRS hint: SP of res, next bit is BRS. Both roles need
                  -- this so the PCS handles the bit-rate switch.
                  pcs_o.next_bit_is_brs <= '1';
                  state                 <= s_brs;
                else
                  state     <= s_dlc;
                  bit_count <= 0;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_brs: BRS bit (FD only). BRS=recessive: all nodes enter data phase.
            -----------------------------------------------------------------
            when s_brs =>
              if drive_bit = '1' and is_transmitter then
                v_drive_polarity := mac_ser_i.llc_metadata.brs;
                v_drive_now      := true;
              elsif pcs_i.sample_point = '1' then
                llc_frame(c_conf_0_offset)(c_llc_frame_brs) <= pcs_i.rx_data;
                in_data_phase                               <= (pcs_i.rx_data = c_recessive);
                state                                       <= s_esi;
              end if;

            -----------------------------------------------------------------
            -- s_esi: ESI bit (FD only). Active=dominant, passive=recessive.
            -----------------------------------------------------------------
            when s_esi =>
              if drive_bit = '1' and is_transmitter then
                v_drive_polarity := mac_ser_i.llc_metadata.esi;
                v_drive_now      := true;
              elsif pcs_i.sample_point = '1' then
                llc_frame(c_conf_0_offset)(c_llc_frame_esi) <= pcs_i.rx_data;
                state                                       <= s_dlc;
                bit_count                                   <= 0;
              end if;

            -----------------------------------------------------------------
            -- s_dlc: 4-bit DLC. TX reads SOF-latched metadata. RX derives
            -- data_len / crc_length / poly from the captured DLC bits.
            -----------------------------------------------------------------
            when s_dlc =>
              if drive_bit = '1' and is_transmitter then
                v_drive_polarity := mac_ser_i.llc_metadata.dlc(c_dlc_field_width - 1 - bit_count);
                v_drive_now      := true;
              elsif pcs_i.sample_point = '1' then
                llc_frame(c_conf_1_offset)(c_llc_frame_dlc_start - bit_count) <= pcs_i.rx_data;
                if bit_count = c_dlc_field_width - 1 then
                  bit_count  <= 0;
                  bit_index  <= 0;
                  byte_index <= 0;
                  if is_transmitter then
                    -- TX uses metadata directly.
                    if data_len > 0 and mac_ser_i.llc_metadata.ftyp = '0' then
                      state <= s_data;
                    elsif mac_ser_i.llc_metadata.fdf = '1' then
                      state                      <= s_sbc;
                      bs_o.fixed_bit_stuffing_en <= '1';
                    else
                      state <= s_crc;
                    end if;
                  else
                    -- RX derives frame params from the captured DLC.
                    v_dlc_vec                                    := llc_frame(c_conf_1_offset)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end);
                    v_dlc_vec(c_llc_frame_dlc_start - bit_count) := pcs_i.rx_data;
                    v_fdf                                        := llc_frame(c_conf_0_offset)(c_llc_frame_fdf);
                    v_ftyp                                       := llc_frame(c_conf_0_offset)(c_llc_frame_ftyp);
                    v_data_len                                   := dlc_to_data_length(to_integer(unsigned(v_dlc_vec)), v_fdf);
                    data_len              <= v_data_len;
                    crc_length            <= f_crc_length(v_data_len, v_fdf);
                    crc_o.crc_poly_select <= f_crc_poly_select(v_data_len, v_fdf);
                    if v_data_len > 0 and v_ftyp = '0' then
                      state <= s_data;
                    elsif v_fdf = '1' then
                      state                      <= s_sbc;
                      bs_o.fixed_bit_stuffing_en <= '1';
                    else
                      state <= s_crc;
                    end if;
                  end if;
                else
                  bit_count <= bit_count + 1;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_data: data field. 0..8 bytes (CC) or 0..64 bytes (FD).
            -----------------------------------------------------------------
            when s_data =>
              -- Transmitter node: Drive bits sourced from the serializer module
              if drive_bit = '1' and is_transmitter then
                mac_ser_o.ready  <= '1';
                v_drive_polarity := mac_ser_i.data;
                v_drive_now      := true;

              elsif pcs_i.sample_point = '1' then
                -- Receiver node: Store sampled bits in the LLC frame
                llc_frame(c_data_offset + byte_index)((c_byte_width - 1) - bit_index) <= pcs_i.rx_data;

                -- Both : 
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

            -----------------------------------------------------------------
            -- s_sbc: 4-bit stuff-bit count (FD only, ISO 6.6.11.5). Fixed-
            -- stuff field. CRC FD is fed on real bits only. Both roles run
            -- the SBC-mismatch compare; TX winning never trips it.
            -----------------------------------------------------------------
            when s_sbc =>
              if drive_bit = '1' and is_transmitter then
                v_drive_polarity := bs_i.stuff_bit_count((c_sbc_field_width - 1) - bit_count);
                v_drive_now      := true;
              elsif pcs_i.sample_point = '1' then
                if not is_transmitter
                   and pcs_i.rx_data /= bs_i.stuff_bit_count((c_sbc_field_width - 1) - bit_count) then
                  fce_o.sending_error_overload_flag <= '1';
                  fce_o.error                       <= '1';
                  v_drive_polarity                  := not fce_i.error_active;
                  v_drive_now                       := true;
                  pcs_o.data_phase_stop             <= '1';
                  in_data_phase                     <= false;
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

            -----------------------------------------------------------------
            -- s_crc: CRC field (15/17/21 bits). Fixed-stuff field. Both
            -- roles run the CRC mismatch compare; TX winning never trips
            -- it. At the last CRC bit assert data_phase_stop so the PCS
            -- phase-switches at the delim SP (ISO 6.6.10.5).
            -----------------------------------------------------------------
            when s_crc =>
              if drive_bit = '1' and is_transmitter then
                v_drive_polarity := crc_i.crc((c_crc_21_length - 1) - bit_count);
                v_drive_now      := true;
              elsif pcs_i.sample_point = '1' then
                if not is_transmitter
                   and pcs_i.rx_data /= crc_i.crc((c_crc_21_length - 1) - bit_count) then
                  -- CRC error: fire the error flag immediately. TX is
                  -- excluded because its own delayed echo in the FD data
                  -- phase can transiently mismatch crc_i.crc.
                  fce_o.sending_error_overload_flag <= '1';
                  fce_o.error                       <= '1';
                  v_drive_polarity                  := not fce_i.error_active;
                  v_drive_now                       := true;
                  pcs_o.data_phase_stop             <= '1';
                  in_data_phase                     <= false;
                  bs_o.fixed_bit_stuffing_en        <= '0';
                  state                             <= s_error_flag;
                  bit_count                         <= 0;
                elsif bit_count = crc_length - 1 then
                  pcs_o.data_phase_stop      <= '1';
                  bs_o.fixed_bit_stuffing_en <= '0';
                  state                      <= s_crc_delimiter;
                  bit_count                  <= 0;
                else
                  bit_count <= bit_count + 1;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_crc_delimiter: single recessive bit between CRC and ACK.
            -- TX drives recessive; RX listens and transitions to s_ack.
            -----------------------------------------------------------------
            when s_crc_delimiter =>
              if drive_bit = '1' and is_transmitter then
                v_drive_polarity := c_recessive;
                v_drive_now      := true;
              elsif pcs_i.sample_point = '1' then
                in_data_phase <= false;
                state     <= s_ack;
                bit_count <= 0;
              end if;

            -----------------------------------------------------------------
            -- s_ack: ACK slot (1 bit CC, 2 bits FD; ISO 6.6.10.6). TX listens.
            -- RX drives dominant at bit_count=0 only; FD bit 1 is not driven (bus stays recessive).
            -----------------------------------------------------------------
            when s_ack =>
              if drive_bit = '1' and not is_transmitter and bit_count = 0 then
                v_drive_polarity := c_dominant;
                v_drive_now      := true;
              elsif pcs_i.sample_point = '1' then
                if is_transmitter and pcs_i.rx_data = c_dominant then
                  ack_success_seen <= true;
                end if;

                if not is_transmitter then
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
              if drive_bit = '1' and is_transmitter then
                v_drive_polarity := c_recessive;
                v_drive_now      := true;
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
              if drive_bit = '1' and is_transmitter then
                v_drive_polarity := c_recessive;
                v_drive_now      := true;
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
                      v_drive_polarity := c_dominant;
                      v_drive_now      := true;
                      overload    <= true;
                      fce_o.error <= '0';
                    else
                      v_drive_polarity := not fce_i.error_active;
                      v_drive_now      := true;
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
            -- s_error_flag: 6-bit flag (active=dominant, passive=recessive; overload=dominant).
            -- Followed by check, optional dominant-wait, then 8-bit recessive delimiter.
            -----------------------------------------------------------------
            when s_error_flag =>
              if drive_bit = '1' then
                v_drive_polarity := c_dominant when overload else not fce_i.error_active;
                v_drive_now      := true;
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

            -----------------------------------------------------------------
            -- s_error_flag_check: one recessive bit after the flag; dominant
            -- means another node is still flagging, start dominant-wait.
            -----------------------------------------------------------------
            when s_error_flag_check =>
              if drive_bit = '1' then
                v_drive_polarity := c_recessive;
                v_drive_now      := true;
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

            -----------------------------------------------------------------
            -- s_error_dominant_delim: wait for bus to go recessive before
            -- starting the 8-bit delimiter (ISO 6.6.13).
            -----------------------------------------------------------------
            when s_error_dominant_delim =>
              if drive_bit = '1' then
                v_drive_polarity := c_recessive;
                v_drive_now      := true;
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

            -----------------------------------------------------------------
            -- s_error_delimiter: 8 recessive bits. Dominant re-enters flag.
            -----------------------------------------------------------------
            when s_error_delimiter =>
              if drive_bit = '1' then
                v_drive_polarity := c_recessive;
                v_drive_now      := true;
              elsif pcs_i.sample_point = '1' then
                if pcs_i.rx_data = c_dominant then
                  -- Form error / overload (ISO 6.6.21.3.2): re-enter flag.
                  v_drive_polarity := not fce_i.error_active;
                  v_drive_now      := true;
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
            -- s_bus_off: park state while FCE holds bus_off high (ISO 8.1.4.5).
            -- Reset block overrides this; transition fires the cycle bus_off deasserts.
            -----------------------------------------------------------------
            when s_bus_off =>
              state <= s_bus_reintegration;

            when others =>
              state     <= s_bus_reintegration;
              bit_count <= 0;

          end case;
        end if;

        if llc_stream_done then
          llc_stream_start <= false;
        end if;

        -----------------------------------------------------------------
        -- Drive commit: any case branch that decided to drive a bit set
        -- v_drive_now / v_drive_polarity. Single point of write to the
        -- PCS tx_data, transmitting flags and polarity history.
        -----------------------------------------------------------------
        if v_drive_now then
          pcs_o.tx_data              <= v_drive_polarity;
          pcs_o.transmitting         <= '1';
          fce_o.transmitting         <= '1';
          transmitted_bits_shift_reg <= transmitted_bits_shift_reg(c_tdc_polarity_depth - 2 downto 0) & v_drive_polarity;
        end if;

      end if;
    end if;
  end process p_fsm;

end architecture rtl;

-- eof
