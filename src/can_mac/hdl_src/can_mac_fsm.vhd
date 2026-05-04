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
  -- Shared --------------------------------------------------------
  signal state                                : t_fsm_state;
  signal is_transmitter                       : boolean;
  signal bit_count                            : natural range 0 to c_max_mac_frame_length;
  signal data_len                             : natural range 0 to c_max_data_bytes;
  signal crc_length                           : natural range 0 to c_crc_21_length;
  signal overload                             : boolean;
  signal in_data_phase                        : boolean;                            -- BRS=recessive: SSP used instead of SP (ISO 7.3.4)
  -- Transmitter stuff --------------------------------------------
  signal transmitted_bits_shift_reg           : std_logic_vector(c_tdc_polarity_depth - 1 downto 0);
  signal was_previous_frame_tx                : boolean;                            -- gates entry to s_suspend_transmission
  signal ack_success_seen                     : boolean;
  signal bit_error_at_ssp                     : boolean;
  signal ack_error_caused_flag                : boolean;
  signal saw_dominant_during_flag             : boolean;
  signal drive_bit_delay                          : std_logic;                          -- SP delayed one cycle
  signal drive_bit                            : std_logic;                          -- SP delayed two cycles
  -- Receiver stuff -----------------------------------------------
  signal byte_index                           : natural range 0 to c_internal_llc_frame_len - 1;
  signal bit_index                            : natural range 0 to c_byte_width - 1;
  signal stream_index                         : natural range 0 to c_internal_llc_frame_len - 1;
  signal llc_frame                            : t_llc_frame;
  signal llc_stream_start                     : boolean;
  signal llc_stream_active                    : boolean;
  signal crc_error_detected                   : boolean;
  signal llc_frame_len                        : natural range 0 to c_internal_llc_frame_len;
  -----------------------------------------------------------------

begin

  -----------------------------------------------------------------
  -- Streams the received frame to the LLC.
  -----------------------------------------------------------------
  p_stream_to_LLC : process(clk_i)
  begin
    if rising_edge(clk_i) then
      if (rst_i = '1' or fce_i.bus_off = '1') then
        llc_o              <= c_mac_rx_to_llc_if_reset;
        stream_index       <= 0;
        llc_stream_active  <= false;
      else
        llc_o <= c_mac_rx_to_llc_if_reset;

        if llc_stream_start then
          llc_stream_active <= true;
        end if;

        if llc_stream_start or llc_stream_active then
          llc_o.avalon_st_source.data  <= llc_frame(stream_index);
          llc_o.avalon_st_source.valid <= '1';

          if stream_index = 0 then
            llc_o.avalon_st_source.startofpacket <= '1';
          elsif stream_index = llc_frame_len - 1 then
            llc_o.avalon_st_source.endofpacket <= '1';
            stream_index      <= 0;
            llc_stream_active <= false;
          end if;
          if llc_i.avalon_st_sink.ready = '1' and stream_index /= llc_frame_len - 1 then
            stream_index <= stream_index + 1;
          end if;
        end if;
      end if;
    end if;
  end process p_stream_to_LLC;

  -----------------------------------------------------------------
  -- FSM coordinating the MAC layer 
  -----------------------------------------------------------------
  p_fsm : process(clk_i) is
    variable v_data_len               : natural range 0 to c_max_data_bytes;
    variable v_dlc_vec                : std_logic_vector(c_llc_frame_dlc_start downto c_llc_frame_dlc_end);
    variable v_fdf                    : std_logic;
    variable v_ftyp                   : std_logic;
    variable v_drive_now              : boolean;                                    -- commit drive to PCS at end of process
    variable v_drive_polarity         : std_logic;
    variable v_in_dynamic_stuff       : boolean;                                    -- s_arbitration..s_data (dynamic stuff region)
    variable v_tx_bit_error_state     : boolean;                                    -- states where TX SP bit-error monitor is active
    variable v_bit_error_at_sp        : boolean;
    variable v_skip_case              : boolean;                                    -- set in pre-case block when the case block should be skipped
    variable v_in_fixed_format_field  : boolean;                                    -- s_crc_delimiter or s_ack_delimiter
    variable v_bs_crc_src             : std_logic;                                  -- just a convenience variable 

  begin

    if rising_edge(clk_i) then
      if rst_i = '1' then
        -- Frame state
        state                                <= s_bus_reintegration;
        bit_count                            <= 0;
        is_transmitter                       <= false;
        overload                             <= false;
        in_data_phase                        <= false;
        data_len                             <= 0;
        crc_length                           <= c_crc_15_length;
        -- Transmitter stuff
        was_previous_frame_tx                <= false;
        transmitted_bits_shift_reg           <= (others => c_recessive);
        drive_bit_delay                          <= '0';
        drive_bit                            <= '0';
        ack_success_seen                     <= false;
        bit_error_at_ssp                     <= false;
        ack_error_caused_flag                <= false;
        saw_dominant_during_flag             <= false;
        -- Receiver stuff
        byte_index                           <= 0;
        bit_index                            <= 0;
        llc_frame                            <= (others => (others => '0'));
        llc_stream_start                     <= false;
        llc_frame_len                        <= 0;
        crc_error_detected                   <= false;
        -- Interfaces
        mac_ser_o                            <= c_ser_fsm_if_d2s_reset;
        bs_o                                 <= c_mac_fsm_to_bs_fd_if_reset;
        pcs_o                                <= c_mac_to_pcs_if_reset;
        fce_o                                <= c_mac_to_fce_if_reset;
        crc_o                                <= c_mac_fsm_to_crc_if_reset;
        bs_rst                               <= '0';
        crc_rst                              <= '0';
      elsif fce_i.bus_off = '1' then
        state <= s_bus_off;
      else

        -----------------------------------------------------------------
        -- Defaults
        -----------------------------------------------------------------
        v_in_dynamic_stuff   := state = s_arbitration or state = s_fdf_r1_r0 or state = s_res_r0 or state = s_brs or state = s_esi or state = s_dlc or state = s_data;
        v_tx_bit_error_state := state = s_fdf_r1_r0 or state = s_res_r0
                                or state = s_brs    or state = s_esi    or state = s_dlc or state = s_data
                                or state = s_sbc    or state = s_crc    or state = s_crc_delimiter
                                or state = s_ack_delimiter or state = s_eof;
        v_bit_error_at_sp        := not in_data_phase and state /= s_ack_delimiter and transmitted_bits_shift_reg(0) /= pcs_i.rx_data;
        v_in_fixed_format_field  := state = s_crc_delimiter or state = s_ack_delimiter;
        v_skip_case      := false;
        v_drive_now      := false;
        v_drive_polarity := c_recessive;
        -- drive_bit pipeline (SP+1 lets state/bit_count settle, SP+2 lets BS present bs_i.valid)
        drive_bit_delay <= pcs_i.sample_point;
        drive_bit   <= drive_bit_delay;
        -- interfaces
        bs_o.valid                        <= '0';
        bs_rst                            <= '0';
        crc_o                             <= c_mac_fsm_to_crc_if_reset;
        crc_o.crc_poly_select             <= crc_o.crc_poly_select;
        crc_rst                           <= '0';
        fce_o                             <= c_mac_to_fce_if_reset;
        fce_o.transmitting                <= '1' when is_transmitter else '0';
        fce_o.sending_error_overload_flag <= '1' when state = s_error_flag else '0';
        mac_ser_o.ready                   <= '0';
        mac_ser_o.transfer_status         <= mac_ser_o.transfer_status;
        llc_stream_start                  <= false;
        pcs_o.do_hard_sync                <= '0';
        -- FD frame single-bit-time control signals 
        if pcs_i.sample_point = '1' then
          pcs_o.next_bit_is_res <= '0';
          pcs_o.next_bit_is_brs <= '0';
          pcs_o.data_phase_stop <= '0';
        end if;

        -- Quiet states: reset active-frame signals on every cycle.
        if state = s_bus_reintegration or state = s_intermission or state = s_suspend_transmission or state = s_bus_idle then
          fce_o                                <= c_mac_to_fce_if_reset;
          mac_ser_o                            <= c_ser_fsm_if_d2s_reset;
          bs_o                                 <= c_mac_fsm_to_bs_fd_if_reset;
          bit_error_at_ssp <= false;
          bs_rst                               <= '1';
          crc_rst                              <= '1';
          ack_success_seen                     <= false;
          ack_error_caused_flag                <= false;
          saw_dominant_during_flag             <= false;
          crc_error_detected                   <= false;
        end if;

        -- pre-case -------------------------------------------------
        if is_transmitter then

          -- SSP bit-error (ISO 7.3.4): always fires before SP, SP branch consumes and clears it.
          if pcs_i.secondary_sample_point = '1' and transmitted_bits_shift_reg(to_integer(unsigned(pcs_i.tdc_delay))) /= pcs_i.rx_data then
            bit_error_at_ssp <= true;
          end if;

          if pcs_i.sample_point = '1' then
            -- Lost arbitration: Transmitter becomes receiver for the rest of the frame.
            if state = s_arbitration and transmitted_bits_shift_reg(0) = c_recessive and pcs_i.rx_data = c_dominant then
              mac_ser_o.transfer_status <= c_lost_arb;
              was_previous_frame_tx     <= false;
              is_transmitter            <= false;
            end if;

            if v_tx_bit_error_state and (bit_error_at_ssp or v_bit_error_at_sp) then
              -- Transmitter bit-error (ISO 6.6.21.2.a)
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
              v_skip_case                := true;

            elsif bs_i.valid = '1' then
              -- Transmitter stuff-bit: feed BS/CRC from TX drive register
              bs_o.valid <= '1';
              bs_o.data  <= transmitted_bits_shift_reg(0);
              if v_in_dynamic_stuff then
                -- FD frames compute CRC over data bits + stuff bits
                crc_o.valid_fd <= '1';
                crc_o.data_fd  <= transmitted_bits_shift_reg(0);
              end if;
              v_skip_case := true;

            elsif state = s_ack_delimiter and not (ack_success_seen or pcs_i.rx_data = c_dominant) then
              -- Transmitter ACK error (ISO 6.6.21.2.e)
              ack_error_caused_flag      <= true;
              pcs_o.tx_data              <= not fce_i.error_active;
              pcs_o.data_phase_stop      <= '1';
              bs_o.fixed_bit_stuffing_en <= '0';
              state                      <= s_error_flag;
              bit_count                  <= 0;
              overload                   <= false;
              v_skip_case                := true;
            end if;

          elsif drive_bit = '1' and bs_i.valid = '1' then
            -- Drive the stuffed polarity onto the bus
            v_drive_polarity := bs_i.data;
            v_drive_now      := true;
            v_skip_case      := true;
          end if;

        else  -- receiver

          -- Hard sync: receivers re-synchronise in quiet/waiting states and at the dominant
          -- res bit edge. Transmitters never hard sync. They drive the bus.
          pcs_o.do_hard_sync <= '1' when state = s_intermission or state = s_bus_idle or state = s_suspend_transmission or state = s_res_r0 else '0';

          if pcs_i.sample_point = '1' then
            if bs_i.valid = '1' and bs_i.data /= pcs_i.rx_data and v_in_dynamic_stuff then
              -- RX stuff-error (ISO 6.5.5)
              fce_o.sending_error_overload_flag <= '1';
              fce_o.error                       <= '1';
              pcs_o.data_phase_stop             <= '1';
              in_data_phase                     <= false;
              v_drive_polarity                  := not fce_i.error_active;
              v_drive_now                       := true;
              state                             <= s_error_flag;
              bit_count                         <= 0;
              v_skip_case                       := true;

            elsif bs_i.valid = '1' then
              -- RX SP stuff-bit: feed BS/CRC from sampled bus
              bs_o.valid <= '1';
              bs_o.data  <= pcs_i.rx_data;
              if v_in_dynamic_stuff then
                crc_o.valid_fd <= '1';
                crc_o.data_fd  <= pcs_i.rx_data;
              end if;
              v_skip_case := true;

            elsif state = s_eof and bit_count = 0 and crc_error_detected then
              -- RX CRC error: fires at first EOF bit (ISO 10.4.2.1)
              ack_error_caused_flag      <= true;
              pcs_o.tx_data              <= not fce_i.error_active;
              pcs_o.data_phase_stop      <= '1';
              bs_o.fixed_bit_stuffing_en <= '0';
              state                      <= s_error_flag;
              bit_count                  <= 0;
              overload                   <= false;
              v_skip_case                := true;

            elsif state = s_eof and pcs_i.rx_data = c_dominant then
              -- EOF dominant: overload at last bit, form error elsewhere (ISO 10.4.2.1 / 6.6.21.3.2)
              if bit_count = c_eof_field_width - 1 then
                v_drive_polarity := c_dominant;
                overload         <= true;
                fce_o.error      <= '0';
              else
                v_drive_polarity := not fce_i.error_active;
                fce_o.error      <= '1';
              end if;
              v_drive_now                       := true;
              fce_o.sending_error_overload_flag <= '1';
              state                             <= s_error_flag;
              bit_count                         <= 0;
              v_skip_case                       := true;

            elsif state = s_intermission and bit_count < c_intermission_width - 1 and pcs_i.rx_data = c_dominant then
              -- Intermission overload: dominant at bits 0 or 1 (ISO 6.6.21.3.2 b)
              fce_o.sending_error_overload_flag <= '1';
              pcs_o.tx_data                     <= c_dominant;
              state                             <= s_error_flag;
              bit_count                         <= 0;
              overload                          <= true;
              v_skip_case                       := true;

            elsif v_in_fixed_format_field and pcs_i.rx_data = c_dominant then
              -- Form error: CRC delimiter or ACK delimiter must be recessive (ISO 10.4.2.1)
              fce_o.sending_error_overload_flag <= '1';
              fce_o.error                       <= '1';
              pcs_o.data_phase_stop             <= '1';
              bs_o.fixed_bit_stuffing_en        <= '0';
              v_drive_polarity                  := not fce_i.error_active;
              v_drive_now                       := true;
              state                             <= s_error_flag;
              bit_count                         <= 0;
              v_skip_case                       := true;

            elsif state = s_res_r0 and pcs_i.rx_data = c_recessive then
              -- Form error: reserved bit must be dominant (ISO 10.4.2.1)
              fce_o.sending_error_overload_flag <= '1';
              fce_o.error                       <= '1';
              v_drive_polarity                  := not fce_i.error_active;
              v_drive_now                       := true;
              state                             <= s_error_flag;
              bit_count                         <= 0;
              v_skip_case                       := true;
            end if;

          end if;

        end if;

        if not v_skip_case then

          case state is

            -----------------------------------------------------------------
            -- s_bus_reintegration: wait for c_bus_idle_condition_width consecutive recessive bits (ISO 6.6.7.5).
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
            -- 0..1 is overload. Dominant at bit 2 is SOF (consecutive frames).
            -----------------------------------------------------------------
            when s_intermission =>
              if pcs_i.sample_point = '1' then
                if pcs_i.rx_data = c_dominant then
                  -- Overload at bits 0-1 caught in RX pre-case. Dominant here means bit 2 = SOF.
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
                else
                  if bit_count < c_intermission_width - 1 then
                    bit_count <= bit_count + 1;
                  else
                    bit_count <= 0;
                    if fce_i.error_active = '0' and was_previous_frame_tx then
                      state <= s_suspend_transmission;
                    else
                      state <= s_bus_idle;
                    end if;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_suspend_transmission: 8-bit recessive wait after an error
            -- passive TX frame (ISO 6.6.7.4). TX only entry.
            -----------------------------------------------------------------
            when s_suspend_transmission =>
              if pcs_i.sample_point = '1' and pcs_i.rx_data = c_recessive then
                if bit_count = c_suspend_transmission_width - 1 then
                  state                 <= s_bus_idle;
                  is_transmitter        <= false;
                  was_previous_frame_tx <= false;
                  bit_count             <= 0;
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
              elsif pcs_i.sample_point = '1' and (is_transmitter or pcs_i.rx_data = c_dominant) then
                -- TX: is_transmitter drove SOF so transition regardless of loopback.
                -- RX: detect dominant SOF on the bus.
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
                    -- TX: use the driven bit to decide base vs extended. Loopback may be overridden.
                    if (is_transmitter and transmitted_bits_shift_reg(0) = c_dominant) or
                       (not is_transmitter and pcs_i.rx_data = c_dominant) then
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
                -- Signal PCS to start the TDC measurement on the next dominant edge.
                if is_transmitter then
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
            -- CC ext falls to s_dlc. Form error (recessive) caught in RX pre-case.
            -----------------------------------------------------------------
            when s_res_r0 =>
              if drive_bit = '1' and is_transmitter then
                v_drive_polarity := c_dominant;
                v_drive_now      := true;
              elsif pcs_i.sample_point = '1' then
                -- Form error caught in RX pre-case; only reach here for dominant (correct).
                if llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1' then
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
                    -- llc_frame signal update is not visible yet in this delta; patch the last bit from pcs_i.rx_data.
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
              if drive_bit = '1' and is_transmitter then
                mac_ser_o.ready  <= '1';
                v_drive_polarity := mac_ser_i.data;
                v_drive_now      := true;
              -- Both roles capture from bus. TX self-receives, only RX streams to LLC.
              elsif pcs_i.sample_point = '1' then
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
                  bit_count  <= bit_count + 1;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_sbc: 4-bit stuff-bit count field (FD only, ISO 6.6.11.5).
            -----------------------------------------------------------------
            when s_sbc =>
              if drive_bit = '1' and is_transmitter then
                v_drive_polarity := bs_i.stuff_bit_count((c_sbc_field_width - 1) - bit_count);
                v_drive_now      := true;
              -- Receiver nodes check for SBC mismatch
              elsif pcs_i.sample_point = '1' then
                if not is_transmitter and pcs_i.rx_data /= bs_i.stuff_bit_count((c_sbc_field_width - 1) - bit_count) then
                  crc_error_detected <= true;
                elsif bit_count = c_sbc_field_width - 1 then
                  state     <= s_crc;
                  bit_count <= 0;
                else
                  bit_count <= bit_count + 1;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_crc: CRC field (CC : 15 bits, FD : 17 or 21 bits).
            -----------------------------------------------------------------
            when s_crc =>
              if drive_bit = '1' and is_transmitter then
                v_drive_polarity := crc_i.crc((c_crc_21_length - 1) - bit_count);
                v_drive_now      := true;
              elsif pcs_i.sample_point = '1' then
                -- Receiver nodes check for CRC mismatch
                if not is_transmitter and pcs_i.rx_data /= crc_i.crc((c_crc_21_length - 1) - bit_count) then
                  crc_error_detected <= true;
                elsif bit_count = crc_length - 1 then
                  -- Assert data_phase_stop so the PCS switch to nominal bit timing at the CRC delimiter SP (ISO 6.6.10.5)
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
            -- TX drives recessive; RX listens. Form error caught in RX pre-case.
            -----------------------------------------------------------------
            when s_crc_delimiter =>
              if drive_bit = '1' and is_transmitter then
                v_drive_polarity := c_recessive;
                v_drive_now      := true;
              elsif pcs_i.sample_point = '1' then
                -- Form error (dominant) caught in RX pre-case; only reach here for recessive.
                in_data_phase <= false;
                state         <= s_ack;
                bit_count     <= 0;
              end if;

            -----------------------------------------------------------------
            -- s_ack: ACK slot (1 bit in CC frames, 2 bits in FD frames, ISO 6.6.10.6).
            -- Transmitter listens. Receiver drives dominant at bit_count=0 only.
            -- FD bit 1 is not driven recessive by receivers.
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
            -- s_ack_delimiter: single recessive bit after ACK slot.
            -- TX ACK error caught in TX pre-case; RX form error caught in RX pre-case.
            -----------------------------------------------------------------
            when s_ack_delimiter =>
              if drive_bit = '1' and is_transmitter then
                v_drive_polarity := c_recessive;
                v_drive_now      := true;
              elsif pcs_i.sample_point = '1' then
                -- Both errors caught in pre-case; only reach here on clean path.
                state     <= s_eof;
                bit_count <= 0;
              end if;

            -----------------------------------------------------------------
            -- s_eof: 7 recessive bits.
            -----------------------------------------------------------------
            when s_eof =>
              -- Dominant (form error / overload) and CRC error caught in RX pre-case.
              -- TX dominant caught as bit error in TX pre-case (ISO note: invalid for TX).
              if drive_bit = '1' and is_transmitter then
                v_drive_polarity := c_recessive;
                v_drive_now      := true;
              elsif pcs_i.sample_point = '1' then
                -- Only reach here for recessive bits without CRC error.
                if bit_count = c_eof_field_width - 1 then
                  byte_index    <= 0;
                  llc_frame_len <= c_data_offset + data_len;
                  if is_transmitter then
                    mac_ser_o.transfer_status <= c_transmitted;
                    was_previous_frame_tx     <= true;
                    is_transmitter            <= false;
                  else
                    llc_stream_start <= true;
                  end if;
                  bit_count <= 0;
                  fce_o.successful_transfer <= '1';
                  state     <= s_intermission;
                else
                  bit_count <= bit_count + 1;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_error_flag: 6-bit flag (active=dominant, passive=recessive, overload=dominant).
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
            -- s_bus_off: one-cycle cleanup after bus_off deasserts (ISO 8.1.4.5).
            -----------------------------------------------------------------
            when s_bus_off =>
              mac_ser_o                  <= c_ser_fsm_if_d2s_reset;
              mac_ser_o.transfer_status  <= c_disturbed;
              bs_o                       <= c_mac_fsm_to_bs_fd_if_reset;
              pcs_o                      <= c_mac_to_pcs_if_reset;
              fce_o                      <= c_mac_to_fce_if_reset;
              crc_o                      <= c_mac_fsm_to_crc_if_reset;
              bs_rst                     <= '0';
              crc_rst                    <= '0';
              bit_count                  <= 0;
              byte_index                 <= 0;
              bit_index                  <= 0;
              state                      <= s_bus_reintegration;

            when others =>
              state     <= s_bus_reintegration;
              bit_count <= 0;

          end case;
        end if;

        -----------------------------------------------------------------
        -- Post-case: BS/CRC feed (sample point, not skipped) and drive
        -- commit (drive_bit intent). Mutually exclusive: SP fires when
        -- receiving; v_drive_now fires at drive_bit (TX timing).
        -----------------------------------------------------------------
        if pcs_i.sample_point = '1' and not v_skip_case then
          -- TX (non-arbitration): use the driven bit from the shift register, not the bus sample.
          -- In the FD data phase the nominal SP may fire before the bus has settled (propagation
          -- delay); the shift register echo is the reliable source. In arbitration multiple nodes
          -- drive simultaneously (wired-AND), so the actual bus value is the ground truth.
          v_bs_crc_src := transmitted_bits_shift_reg(0) when (is_transmitter and state /= s_arbitration)
                                                         else pcs_i.rx_data;
          if v_in_dynamic_stuff or state = s_sbc or state = s_crc then
            bs_o.valid <= '1';
            bs_o.data  <= v_bs_crc_src;
            if v_in_dynamic_stuff or state = s_sbc then
              crc_o.valid_fd <= '1';
              crc_o.data_fd  <= v_bs_crc_src;
            end if;
            if v_in_dynamic_stuff then
              crc_o.valid_cc <= '1';
              crc_o.data_cc  <= v_bs_crc_src;
            end if;
          end if;
        elsif v_drive_now then
          pcs_o.tx_data              <= v_drive_polarity;
          pcs_o.transmitting         <= '1';
          transmitted_bits_shift_reg <= transmitted_bits_shift_reg(c_tdc_polarity_depth - 2 downto 0) & v_drive_polarity;
        end if;

      end if;
    end if;
  end process p_fsm;

end architecture rtl;

-- eof
