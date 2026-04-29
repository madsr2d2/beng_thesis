--------------------------------------------------------------------------------
-- Title      : Combined MAC FSM (TX + RX) for CAN/CAN-FD
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_mac_fsm.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Single MAC FSM that handles both TX and RX paths in one
--              synchronous process. The mode (transmitter vs receiver) is
--              latched in the `is_transmitter` flag at SOF time. Each state's
--              case branch contains both TX and RX behavior, gated on the
--              mode flag. Submodules (bit stuffer, CRC, serializer) are shared
--              by both modes through the same interface ports.
--
--              Based structurally on the company `can_mac_fsm_tx.vhd` (kept
--              the polarity-history TDC, lost-arbitration, ACK error exemption
--              and error-delimiter logic) with the RX FSM logic merged in via
--              the mode flag. The RX byte-stream-to-LLC process is included as
--              a second process within the same entity.
--
--              Protocol references: ISO 11898-1:2024.
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
    s_sof, s_id, s_rtr_srr_rrs, s_ide, s_fdf_r1_r0, s_res_r0, s_brs, s_esi,
    s_dlc, s_data, s_sbc, s_crc, s_ack, s_ack_delimiter, s_eof,
    s_error_overload, s_error_delimiter
  );

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
  signal polarity_history                     : std_logic_vector(c_tdc_polarity_depth - 1 downto 0);
  signal was_previous_frame_tx                : boolean;
  signal ack_success_seen                     : boolean;
  signal secondary_sample_point_error_pending : boolean;
  signal skip_sof                             : boolean;
  signal ack_error_caused_flag                : boolean;
  signal saw_dominant_during_flag             : boolean;
  signal dominant_run_count                   : natural range 0 to c_bus_off_threshold;

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

  -- Local data-phase tracking (set when TX BRS=1 drives recessive, cleared at
  -- CRC delim's data_phase_stop). Used to suppress the SP-based bit error
  -- check in data phase, where SSP-based detection is the correct mechanism.
  signal in_data_phase                        : boolean;

begin

  -----------------------------------------------------------------
  -- Streams the received frame to the LLC byte by byte during the
  -- quiet phase after EOF. Verbatim from can_mac_fsm_rx.
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
    variable v_in_ack_slot            : boolean;
    -- TX bit-drive variables
    variable v_tx_polarity            : std_logic;
    variable v_bit_driven             : boolean;
    variable v_is_stuff_bit           : boolean;
    variable v_lost_arb               : boolean;
    variable v_enter_error            : boolean;
    variable v_ack_error              : boolean;
    -- RX helpers
    variable v_not_stuff_bit          : boolean;
    variable v_data_len               : natural range 0 to c_max_data_bytes;
    variable v_dlc_vec                : std_logic_vector(c_llc_frame_dlc_start downto c_llc_frame_dlc_end);
    -- Combined "MAC is actively driving the bus" predicate. The PCS uses it
    -- to choose between tx_data and recessive; the FCE uses it to gate
    -- error counter updates. Both must agree, so derive once and fan out.
    variable v_transmitting           : std_logic;
  begin

    if rising_edge(clk_i) then
      if (rst_i = '1' or fce_i.bus_off = '1') then
        state                                <= s_bus_reintegration;
        is_transmitter                       <= false;
        overload                             <= false;
        bit_count                            <= 0;
        data_len                             <= 0;
        crc_length                           <= c_crc_15_length;
        polarity_history                     <= (others => c_recessive);
        was_previous_frame_tx                <= false;
        ack_success_seen                     <= false;
        secondary_sample_point_error_pending <= false;
        skip_sof                             <= false;
        ack_error_caused_flag                <= false;
        saw_dominant_during_flag             <= false;
        dominant_run_count                   <= 0;
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
        v_in_arbitration_field   := state = s_id or state = s_rtr_srr_rrs or state = s_ide;
        v_in_dynamic_stuff_field := v_in_arbitration_field or state = s_fdf_r1_r0 or state = s_res_r0 or state = s_brs or state = s_esi or state = s_dlc or state = s_data;
        v_in_fixed_stuff_field   := state = s_sbc or state = s_crc;
        v_in_quiet_field         := state = s_bus_reintegration or state = s_intermission or state = s_suspend_transmission or state = s_bus_idle;
        -- Include s_ack_delimiter so a late-arriving ACK (when bus delay
        -- pushes the dominant into the next bit time) is not flagged as a bit error
        v_in_ack_slot            := state = s_ack or state = s_ack_delimiter;

        -----------------------------------------------------------------
        -- Defaults
        -----------------------------------------------------------------
        -- TX path uses the LLC TX metadata; RX path uses the FDF bit
        -- captured into the local llc_frame buffer during s_fdf_r1_r0.
        bs_o.fixed_bit_stuffing_en <= '1' when
          (is_transmitter and mac_ser_i.llc_metadata.fdf = '1' and (state = s_sbc or state = s_crc))
          or (not is_transmitter and llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1' and (state = s_sbc or state = s_crc))
          else '0';
        bs_o.data                  <= pcs_i.rx_data;
        bs_o.valid                 <= '0';
        bs_rst                     <= '0';
        crc_o                      <= c_mac_fsm_to_crc_if_reset;
        crc_o.crc_poly_select      <= crc_o.crc_poly_select;
        crc_rst                    <= '0';
        fce_o                      <= c_mac_to_fce_if_reset;
        -- transmitting is a LEVEL signal: held high whenever the MAC wants the
        -- PCS to drive its tx_data (instead of forcing recessive). Strobe-style
        -- assignment fails because the PCS only samples this at bit boundaries.
        --   TX: high in all active frame states except s_ack (where TX listens).
        --   RX: high in s_ack (drive ACK) and during error/overload flag drive.
        if (is_transmitter and not v_in_quiet_field and state /= s_ack)
           or (not is_transmitter and state = s_ack)
           or state = s_error_overload
           or state = s_error_delimiter then
          v_transmitting := '1';
        else
          v_transmitting := '0';
        end if;
        fce_o.transmitting <= v_transmitting;
        pcs_o.transmitting <= v_transmitting;
        fce_o.sending_error_overload_flag <= '1' when state = s_error_overload else '0';
        mac_ser_o.ready                   <= '0';
        mac_ser_o.transfer_status         <= mac_ser_o.transfer_status;
        -- Hold TDC signals until next sample point
        pcs_o.next_bit_is_res             <= '0' when pcs_i.sample_point = '1' else pcs_o.next_bit_is_res;
        pcs_o.next_bit_is_brs             <= '0' when pcs_i.sample_point = '1' else pcs_o.next_bit_is_brs;
        pcs_o.data_phase_stop             <= '0' when pcs_i.sample_point = '1' else pcs_o.data_phase_stop;
        -- do_hard_sync is a LEVEL signal: held high during quiet/idle states so
        -- the PCS can hard-sync to a SOF edge whenever it arrives (NOT a strobe).
        pcs_o.do_hard_sync                <= '1' when v_in_quiet_field else '0';
        -- SSP-based deferred bit error detection (ISO 7.3.4).
        -- The PCS reports tdc_delay = M when SSP fires inside bus bit M
        -- (counting from the first data-phase bit boundary). At MAC-SSP
        -- cycle, the polarity_history shift register reflects shifts
        -- through MAC-SP of bit M-1, so polarity_history(M) holds the
        -- TX drive that the bus pin currently reflects after the
        -- propagation delay. Compare against the SSP-sampled rx_data
        -- and defer the error so it is acted on at the next MAC-SP.
        if (pcs_i.secondary_sample_point = '1'
            and polarity_history(to_integer(unsigned(pcs_i.tdc_delay))) /= pcs_i.rx_data) then
          secondary_sample_point_error_pending <= true;
        end if;

        -----------------------------------------------------------------
        -- Working variables
        -----------------------------------------------------------------
        v_bit_driven    := false;
        v_is_stuff_bit  := false;
        v_lost_arb      := false;
        v_enter_error   := false;
        v_ack_error     := false;
        v_tx_polarity   := c_recessive;
        v_not_stuff_bit := false;

        -----------------------------------------------------------------
        -- Quiet-state defaults: clear most outputs and reset BS/CRC.
        -- Note: do_hard_sync is RE-ASSERTED below because the pcs_o reset
        -- constant has it low; we want a level-high during quiet states.
        -----------------------------------------------------------------
        if (v_in_quiet_field) then
          pcs_o                                <= c_mac_to_pcs_if_reset;
          pcs_o.do_hard_sync                   <= '1';
          fce_o                                <= c_mac_to_fce_if_reset;
          mac_ser_o                            <= c_ser_fsm_if_d2s_reset;
          bs_o                                 <= c_mac_fsm_to_bs_fd_if_reset;
          secondary_sample_point_error_pending <= false;
          bs_rst                               <= '1';
          crc_rst                              <= '1';
          ack_success_seen                     <= false;
          ack_error_caused_flag                <= false;
          saw_dominant_during_flag             <= false;
          dominant_run_count                   <= 0;
        end if;

        -----------------------------------------------------------------
        -- Stuff-bit handling
        -- TX: BS has a pending stuff bit, drive it instead of FSM data.
        -- RX: feed BS with rx_data every SP; on predicted stuff bit,
        --     verify polarity and feed FD CRC.
        -----------------------------------------------------------------
        if pcs_i.sample_point = '1' and (v_in_dynamic_stuff_field or v_in_fixed_stuff_field) then
          if is_transmitter then
            if bs_i.valid = '1' then
              v_tx_polarity  := bs_i.data;
              v_bit_driven   := true;
              v_is_stuff_bit := true;
            end if;
          else
            -- RX: feed BS with received bit every SP
            bs_o.valid <= '1';
            bs_o.data  <= pcs_i.rx_data;
            if bs_i.valid = '1' then
              -- Stuff bit (predicted): feed FD CRC with stuff bit, check polarity
              if (v_in_dynamic_stuff_field) then
                crc_o.valid_fd <= '1';
                crc_o.data_fd  <= pcs_i.rx_data;
              end if;
              if (bs_i.data /= pcs_i.rx_data) then
                fce_o.sending_error_overload_flag <= '1';
                fce_o.error                       <= '1';
                pcs_o.data_phase_stop             <= '1';
                pcs_o.tx_data                     <= c_recessive when fce_i.error_active = '0' else c_dominant;
                pcs_o.transmitting                <= '1';
                state                             <= s_error_overload;
                bit_count                         <= 0;
              end if;
            else
              -- Real bit
              v_not_stuff_bit := true;
              if (v_in_dynamic_stuff_field) then
                crc_o.valid_cc <= '1';
                crc_o.valid_fd <= '1';
                crc_o.data_cc  <= pcs_i.rx_data;
                crc_o.data_fd  <= pcs_i.rx_data;
              elsif (state = s_sbc) then
                crc_o.valid_fd <= '1';
                crc_o.data_fd  <= pcs_i.rx_data;
              end if;
            end if;
          end if;
        end if;

        -----------------------------------------------------------------
        -- State machine
        -----------------------------------------------------------------
        if pcs_i.sample_point then
          case state is

            -----------------------------------------------------------------
            -- s_bus_reintegration: 11 consecutive recessive bits before
            -- joining the bus (ISO 6.6.7.5)
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
            -- s_intermission: 3-bit inter-frame spacing (ISO 6.6.7.2)
            -----------------------------------------------------------------
            when s_intermission =>
              if (pcs_i.rx_data = c_dominant) then
                if (bit_count < c_intermission_width - 1) then
                  -- Dominant in first 2 bits is overload (ISO 6.6.21.3.2 b)
                  state     <= s_error_overload;
                  bit_count <= 0;
                  overload  <= true;
                else
                  -- Dominant at 3rd bit is SOF: go to s_sof (same path as
                  -- s_bus_idle so TX and RX use a symmetric state sequence).
                  if mac_ser_i.valid = '1' and (fce_i.error_active = '1' or not was_previous_frame_tx) then
                    -- We have a frame to send: become transmitter
                    is_transmitter   <= true;
                    state            <= s_sof;
                    bit_count        <= 0;
                    bs_rst           <= '0';
                    crc_rst          <= '0';
                    bs_o.valid       <= '1';
                    bs_o.data        <= c_dominant;
                    crc_o.valid_cc   <= '1';
                    crc_o.valid_fd   <= '1';
                    crc_o.data_cc    <= c_dominant;
                    crc_o.data_fd    <= c_dominant;
                    polarity_history <= (0 => c_dominant, others => c_recessive);
                    data_len         <= dlc_to_data_length(to_integer(unsigned(mac_ser_i.llc_metadata.dlc)), mac_ser_i.llc_metadata.fdf);
                    if (mac_ser_i.llc_metadata.fdf = '0') then
                      crc_length            <= c_crc_15_length;
                      crc_o.crc_poly_select <= c_crc_poly_15_sel;
                    elsif (dlc_to_data_length(to_integer(unsigned(mac_ser_i.llc_metadata.dlc)), mac_ser_i.llc_metadata.fdf) < c_crc_17_length) then
                      crc_length            <= c_crc_17_length;
                      crc_o.crc_poly_select <= c_crc_poly_17_sel;
                    else
                      crc_length            <= c_crc_21_length;
                      crc_o.crc_poly_select <= c_crc_poly_21_sel;
                    end if;
                  else
                    -- Receiver: another node has started a frame. Skip s_sof
                    -- (TX drives ID[0] in s_sof so RX captures it directly in s_id).
                    is_transmitter <= false;
                    state          <= s_id;
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
                  end if;
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
            -- s_suspend_transmission: 8-bit wait after error-passive TX
            -- (ISO 6.6.7.4). Only entered as transmitter.
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
            -- s_bus_idle: ready for new frame (ISO 6.6.7.3)
            -- Entry: TX intent (mac_ser valid) or RX detection (dominant)
            -----------------------------------------------------------------
            when s_bus_idle =>
              crc_mismatch       <= false;
              byte_index         <= 0;
              bit_index          <= 0;
              if (mac_ser_i.valid = '1') then
                -- Become transmitter. Drive SOF dominant, feed BS/CRC the SOF
                -- bit (override quiet-field bs_rst/crc_rst so the engines see
                -- this feed), set up frame metadata, go to s_sof. Both TX and
                -- RX use s_sof to "consume" the SOF bit time before s_id.
                is_transmitter   <= true;
                state            <= s_sof;
                bit_count        <= 0;
                pcs_o.tx_data    <= c_dominant;
                bs_rst           <= '0';
                crc_rst          <= '0';
                bs_o.valid       <= '1';
                bs_o.data        <= c_dominant;
                crc_o.valid_cc   <= '1';
                crc_o.valid_fd   <= '1';
                crc_o.data_cc    <= c_dominant;
                crc_o.data_fd    <= c_dominant;
                polarity_history <= (0 => c_dominant, others => c_recessive);
                data_len         <= dlc_to_data_length(to_integer(unsigned(mac_ser_i.llc_metadata.dlc)), mac_ser_i.llc_metadata.fdf);
                if (mac_ser_i.llc_metadata.fdf = '0') then
                  crc_length            <= c_crc_15_length;
                  crc_o.crc_poly_select <= c_crc_poly_15_sel;
                elsif (dlc_to_data_length(to_integer(unsigned(mac_ser_i.llc_metadata.dlc)), mac_ser_i.llc_metadata.fdf) < c_crc_17_length) then
                  crc_length            <= c_crc_17_length;
                  crc_o.crc_poly_select <= c_crc_poly_17_sel;
                else
                  crc_length            <= c_crc_21_length;
                  crc_o.crc_poly_select <= c_crc_poly_21_sel;
                end if;
              elsif (pcs_i.rx_data = c_dominant) then
                -- Receiver: SOF observed at this SP. Feed BS/CRC the SOF bit
                -- and go directly to s_id (skip s_sof). TX drives ID[0] in
                -- s_sof so the first ID bit is on the bus during the next bit
                -- time, which RX captures at the next SP in s_id bc=0.
                is_transmitter <= false;
                state          <= s_id;
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
              end if;

            -----------------------------------------------------------------
            -- s_sof: TX-only. The SOF was driven in s_bus_idle and is being
            -- sampled at this SP. TX drives the FIRST ID bit (mac_ser.data)
            -- for the next bit time so SOF is exactly one bit time on the
            -- bus. CRC and BS are fed explicitly here since s_sof is not in
            -- v_in_dynamic_stuff_field. RX skips this state.
            -----------------------------------------------------------------
            when s_sof =>
              if is_transmitter and bs_i.valid = '0' then
                mac_ser_o.ready <= '1';
                v_tx_polarity   := mac_ser_i.data;
                v_bit_driven    := true;
                bit_count       <= 1;
                state           <= s_id;
                -- Feed CRC the first ID bit (post-FSM only feeds CRC for
                -- states in v_in_dynamic_stuff_field, which excludes s_sof).
                crc_o.valid_cc  <= '1';
                crc_o.valid_fd  <= '1';
                crc_o.data_cc   <= mac_ser_i.data;
                crc_o.data_fd   <= mac_ser_i.data;
              end if;

            -----------------------------------------------------------------
            -- s_id: base ID (11 bits) or extended ID (18 bits)
            -----------------------------------------------------------------
            when s_id =>
              if (bs_i.valid = '0') then
                if is_transmitter then
                  mac_ser_o.ready <= '1';
                  v_tx_polarity   := mac_ser_i.data;
                  v_bit_driven    := true;
                else
                  llc_frame(c_id_offset + byte_index)((c_byte_width - 1) - bit_index) <= pcs_i.rx_data;
                  bit_index  <= 0 when bit_index = (c_byte_width - 1) else (bit_index + 1);
                  byte_index <= (byte_index + 1) when bit_index = (c_byte_width - 1);
                end if;
                bit_count <= bit_count + 1;
                if (bit_count = c_base_id_width - 1 or bit_count = c_base_id_width + c_extended_id_width - 1) then
                  state <= s_rtr_srr_rrs;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_rtr_srr_rrs: RTR/SRR/RRS bit
            -----------------------------------------------------------------
            when s_rtr_srr_rrs =>
              if (bs_i.valid = '0') then
                if is_transmitter then
                  if (mac_ser_i.llc_metadata.ide = '1' and bit_count = c_base_id_width) then
                    v_tx_polarity := c_recessive;       -- SRR
                  elsif (mac_ser_i.llc_metadata.fdf = '1') then
                    v_tx_polarity := c_dominant;        -- RRS
                  else
                    v_tx_polarity := mac_ser_i.llc_metadata.ftyp;  -- RTR
                  end if;
                  v_bit_driven := true;
                else
                  llc_frame(c_conf_0_offset)(c_llc_frame_ftyp) <= pcs_i.rx_data;
                end if;
                if (bit_count > c_base_id_width) then
                  state     <= s_fdf_r1_r0;
                  bit_count <= 0;
                else
                  if (not is_transmitter and llc_frame(c_conf_0_offset)(c_llc_frame_ide) = '1') then
                    -- RX path with IDE already set: extended ID, skip s_ide and go to s_fdf_r1_r0
                    state <= s_fdf_r1_r0;
                  else
                    state <= s_ide;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_ide: IDE bit (dominant=base, recessive=extended)
            -----------------------------------------------------------------
            when s_ide =>
              if (bs_i.valid = '0') then
                if is_transmitter then
                  v_tx_polarity := mac_ser_i.llc_metadata.ide;
                  v_bit_driven  := true;
                  if (mac_ser_i.llc_metadata.ide = c_recessive) then
                    state <= s_id;          -- extended ID, grab next 18 bits
                  else
                    state <= s_fdf_r1_r0;
                  end if;
                else
                  llc_frame(c_conf_0_offset)(c_llc_frame_ide) <= pcs_i.rx_data;
                  if (pcs_i.rx_data = c_recessive) then
                    state <= s_id;
                  else
                    state <= s_fdf_r1_r0;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_fdf_r1_r0: FDF (FD) or r0/r1 (CC). Start TDC on FD entry.
            -----------------------------------------------------------------
            when s_fdf_r1_r0 =>
              if (bs_i.valid = '0') then
                if is_transmitter then
                  v_tx_polarity         := mac_ser_i.llc_metadata.fdf;
                  v_bit_driven          := true;
                  if (mac_ser_i.llc_metadata.fdf = c_recessive or mac_ser_i.llc_metadata.ide = '1') then
                    state <= s_res_r0;
                  else
                    state     <= s_dlc;
                    bit_count <= 0;
                  end if;
                else
                  llc_frame(c_conf_0_offset)(c_llc_frame_fdf) <= pcs_i.rx_data;
                  if (pcs_i.rx_data = c_recessive) or (llc_frame(c_conf_0_offset)(c_llc_frame_ide) = '1') then
                    state <= s_res_r0;
                  else
                    state     <= s_dlc;
                    bit_count <= 0;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_res_r0: reserved bit (must be dominant)
            -----------------------------------------------------------------
            when s_res_r0 =>
              if llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1' and not is_transmitter then
                pcs_o.do_hard_sync <= '1';
              end if;
              if (bs_i.valid = '0') then
                if is_transmitter then
                  -- r0 is always dominant (ISO 11898-1 6.6.10.2). At this SP we
                  -- sample FDF and decide res for the next bit time, so this
                  -- is where we tell PCS to start TDC measurement (the next
                  -- bit driven on the bus is res = dominant edge).
                  v_tx_polarity         := c_dominant;
                  v_bit_driven          := true;
                  pcs_o.next_bit_is_res <= '1' when mac_ser_i.llc_metadata.fdf = '1';
                  if (mac_ser_i.llc_metadata.fdf = '1') then
                    state <= s_brs;
                  else
                    state     <= s_dlc;
                    bit_count <= 0;
                  end if;
                else
                  -- Form error: reserved bit must be dominant
                  if (pcs_i.rx_data = c_recessive) then
                    fce_o.sending_error_overload_flag <= '1';
                    fce_o.error                       <= '1';
                    pcs_o.tx_data                     <= c_recessive when fce_i.error_active = '0' else c_dominant;
                    pcs_o.transmitting                <= '1';
                    bit_count                         <= 0;
                    state                             <= s_error_overload;
                  else
                    if (llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1') then
                      pcs_o.next_bit_is_brs <= '1';
                      state                 <= s_brs;
                    else
                      state     <= s_dlc;
                      bit_count <= 0;
                    end if;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_brs: BRS bit (FD only)
            -----------------------------------------------------------------
            when s_brs =>
              if (bs_i.valid = '0') then
                if is_transmitter then
                  v_tx_polarity         := mac_ser_i.llc_metadata.brs;
                  pcs_o.next_bit_is_brs <= mac_ser_i.llc_metadata.brs;
                  v_bit_driven          := true;
                  -- Entering data phase if BRS=recessive
                  in_data_phase         <= (mac_ser_i.llc_metadata.brs = c_recessive);
                else
                  llc_frame(c_conf_0_offset)(c_llc_frame_brs) <= pcs_i.rx_data;
                  in_data_phase                              <= (pcs_i.rx_data = c_recessive);
                end if;
                state <= s_esi;
              end if;

            -----------------------------------------------------------------
            -- s_esi: ESI bit (FD only)
            -----------------------------------------------------------------
            when s_esi =>
              if (bs_i.valid = '0') then
                if is_transmitter then
                  v_tx_polarity := mac_ser_i.llc_metadata.esi;
                  v_bit_driven  := true;
                else
                  llc_frame(c_conf_0_offset)(c_llc_frame_esi) <= pcs_i.rx_data;
                end if;
                state     <= s_dlc;
                bit_count <= 0;
              end if;

            -----------------------------------------------------------------
            -- s_dlc: DLC field (4 bits)
            -----------------------------------------------------------------
            when s_dlc =>
              if (bs_i.valid = '0') then
                if is_transmitter then
                  v_tx_polarity := mac_ser_i.llc_metadata.dlc(c_dlc_field_width - 1 - bit_count);
                  v_bit_driven  := true;
                  if (bit_count = c_dlc_field_width - 1) then
                    bit_count <= 0;
                    -- RTR (remote) frames carry no data field (ISO 11898-1 6.6.10.4)
                    if (data_len > 0 and mac_ser_i.llc_metadata.ftyp = '0') then
                      state <= s_data;
                    elsif (mac_ser_i.llc_metadata.fdf = '1') then
                      state <= s_sbc;
                    else
                      state <= s_crc;
                    end if;
                  else
                    bit_count <= bit_count + 1;
                  end if;
                else
                  -- Receiver: store DLC bit
                  llc_frame(c_conf_1_offset)(c_llc_frame_dlc_start - bit_count) <= pcs_i.rx_data;
                  bit_count <= bit_count + 1;
                  if bit_count = (c_dlc_field_width - 1) then
                    v_dlc_vec                                    := llc_frame(c_conf_1_offset)(c_llc_frame_dlc_start downto c_llc_frame_dlc_end);
                    v_dlc_vec(c_llc_frame_dlc_start - bit_count) := pcs_i.rx_data;
                    v_data_len                                   := dlc_to_data_length(to_integer(unsigned(v_dlc_vec)), llc_frame(c_conf_0_offset)(c_llc_frame_fdf));
                    bit_count                                    <= 0;
                    bit_index                                    <= 0;
                    byte_index                                   <= 0;
                    data_len                                     <= v_data_len;
                    if (llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '0') then
                      crc_length            <= c_crc_15_length;
                      crc_o.crc_poly_select <= c_crc_poly_15_sel;
                    elsif (v_data_len < c_crc_17_length) then
                      crc_length            <= c_crc_17_length;
                      crc_o.crc_poly_select <= c_crc_poly_17_sel;
                    else
                      crc_length            <= c_crc_21_length;
                      crc_o.crc_poly_select <= c_crc_poly_21_sel;
                    end if;
                    if (v_data_len > 0 and llc_frame(c_conf_0_offset)(c_llc_frame_ftyp) = '0') then
                      state <= s_data;
                    elsif (llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1') then
                      state <= s_sbc;
                    else
                      state <= s_crc;
                    end if;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_data: data field (0..64 bytes)
            -----------------------------------------------------------------
            when s_data =>
              if (bs_i.valid = '0') then
                if is_transmitter then
                  v_tx_polarity   := mac_ser_i.data;
                  v_bit_driven    := true;
                  mac_ser_o.ready <= '1';
                  if (bit_count = data_len * c_byte_width - 1) then
                    bit_count <= 0;
                    if (mac_ser_i.llc_metadata.fdf = '1') then
                      state <= s_sbc;
                    else
                      state <= s_crc;
                    end if;
                  else
                    bit_count <= bit_count + 1;
                  end if;
                else
                  -- Receiver: store data bit
                  llc_frame(c_data_offset + byte_index)((c_byte_width - 1) - bit_index) <= pcs_i.rx_data;
                  if (byte_index = (data_len - 1)) and (bit_index = (c_byte_width - 1)) then
                    if (llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1') then
                      state <= s_sbc;
                    else
                      state <= s_crc;
                    end if;
                    bit_count <= 0;
                  else
                    bit_index  <= 0 when bit_index = (c_byte_width - 1) else (bit_index + 1);
                    byte_index <= (byte_index + 1) when bit_index = (c_byte_width - 1);
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_sbc: stuff-bit count field (FD, 4 bits) (ISO 6.6.11.5)
            -----------------------------------------------------------------
            when s_sbc =>
              if (bs_i.valid = '0') then
                if is_transmitter then
                  v_tx_polarity := bs_i.stuff_bit_count((c_sbc_field_width - 1) - bit_count);
                  v_bit_driven  := true;
                  if (bit_count = c_sbc_field_width - 1) then
                    state     <= s_crc;
                    bit_count <= 0;
                  else
                    bit_count <= bit_count + 1;
                  end if;
                else
                  -- Receiver: SBC mismatch is form error
                  if (pcs_i.rx_data /= bs_i.stuff_bit_count((c_sbc_field_width - 1) - bit_count)) then
                    fce_o.sending_error_overload_flag <= '1';
                    fce_o.error                       <= '1';
                    pcs_o.tx_data                     <= c_recessive when fce_i.error_active = '0' else c_dominant;
                    pcs_o.transmitting                <= '1';
                    pcs_o.data_phase_stop             <= '1';
                    state                             <= s_error_overload;
                    bit_count                         <= 0;
                  elsif bit_count = (c_sbc_field_width - 1) then
                    state     <= s_crc;
                    bit_count <= 0;
                  else
                    bit_count <= bit_count + 1;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_crc: CRC bits then CRC delimiter
            -----------------------------------------------------------------
            when s_crc =>
              if (bs_i.valid = '0') then
                if is_transmitter then
                  v_bit_driven := true;
                  if (bit_count < crc_length) then
                    v_tx_polarity := crc_i.crc((c_crc_21_length - 1) - bit_count);
                    if (bit_count = crc_length - 1) then
                      -- Assert data_phase_stop one MAC-SP before the CRC
                      -- delim SP. The signal is registered, so the PCS
                      -- observes data_phase_stop = '1' at its NEXT SP --
                      -- which is the delim SP. The PCS therefore performs
                      -- the phase switch (active_phase_seg2 <- nominal)
                      -- at the delim SP, making the delim itself the
                      -- mixed-timing bit (data-phase before SP, nominal
                      -- after) and ACK fully nominal. ISO 11898-1
                      -- 6.6.10.5.
                      pcs_o.data_phase_stop <= '1';
                    end if;
                    bit_count <= bit_count + 1;
                  else
                    -- bit_count = crc_length: CRC delim SP. Phase switch
                    -- already performed by PCS at this SP via the
                    -- assertion one bit earlier above. Clear
                    -- in_data_phase here so the SP-based bit-error check
                    -- (line ~1117) only goes active starting from ACK
                    -- bc=0 SP -- it must stay suppressed for the delim
                    -- itself, whose front half is still data-phase and
                    -- whose SP samples before the recessive delim level
                    -- has propagated through TDC.
                    state         <= s_ack;
                    bit_count     <= 0;
                    in_data_phase <= false;
                  end if;
                else
                  -- Receiver: compare CRC, then handle CRC delimiter
                  if (bit_count < crc_length) then
                    if (pcs_i.rx_data /= crc_i.crc((c_crc_21_length - 1) - bit_count)) then
                      crc_mismatch <= true;
                    end if;
                    if (bit_count = crc_length - 1) then
                      -- See TX path comment above: assert one bit early
                      -- so the RX PCS performs the phase switch at the
                      -- delim SP, in lockstep with TX's PCS. Both PCSs
                      -- must use identical active phase-seg widths around
                      -- the delim/ACK boundary or the bit clocks drift.
                      pcs_o.data_phase_stop <= '1';
                    end if;
                    bit_count <= bit_count + 1;
                  else
                    in_data_phase <= false;
                    -- LIMITATION (intentional, per ISO 11898-1
                    -- 6.6.10.5 + 6.6.11.6): no direct form-error check
                    -- is performed on the CRC delimiter. ISO places
                    -- the delim's SP in the data phase, where prop is
                    -- not covered, so an SP-based check at this MAC-
                    -- SP would false-fire on every frame. ISO does not
                    -- require an alternative RX-side check; delim
                    -- corruption is detected indirectly:
                    --   (a) crc_mismatch -- bit-by-bit CRC field check
                    --       below catches CRC corruption, including
                    --       the cases where a delim disturbance also
                    --       disturbs preceding CRC bits.
                    --   (b) ACK absence -- if RX sees disturbance
                    --       around the delim and goes to error/over-
                    --       load, the dominant ACK never appears at
                    --       TX, which TX detects as a missing ACK and
                    --       signals an error frame (see ISO Figure 35
                    --       and the s_ack TX path).
                    --   (c) optional extended SSP -- ISO Figure 36
                    --       allows continuing the SSP sequence past
                    --       the data-phase boundary for TX-side local
                    --       error detection. Not implemented today.
                    if crc_mismatch then
                      fce_o.sending_error_overload_flag <= '1';
                      fce_o.error                       <= '1';
                      pcs_o.tx_data                     <= c_recessive when fce_i.error_active = '0' else c_dominant;
                      pcs_o.transmitting                <= '1';
                      state                             <= s_error_overload;
                      bit_count                         <= 0;
                    else
                      pcs_o.tx_data      <= c_dominant;
                      pcs_o.transmitting <= '1';
                      state              <= s_ack;
                      bit_count          <= 0;
                    end if;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_ack: ACK slot. TX listens for dominant; RX drives dominant.
            -----------------------------------------------------------------
            when s_ack =>
              if is_transmitter then
                -- Sample ACK slot bit. CC has 1 ACK slot bit, FD has 2
                -- (ISO 11898-1 6.6.10.6). In both cases we accumulate
                -- ack_success_seen on any dominant bit observed during
                -- the slot, then transition to s_ack_delimiter.
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
                -- Receiver: drive dominant ACK on first slot bit
                pcs_o.transmitting <= '0';
                if (bit_count = 0) then
                  pcs_o.tx_data <= c_recessive;  -- release after ack drive (RX FSM legacy)
                  bit_count     <= 1;
                elsif (bit_count = 1 and llc_frame(c_conf_0_offset)(c_llc_frame_fdf) = '1') then
                  bit_count <= 2;
                else
                  if (pcs_i.rx_data = c_dominant) then
                    fce_o.sending_error_overload_flag <= '1';
                    fce_o.error                       <= '1';
                    pcs_o.tx_data                     <= c_recessive when fce_i.error_active = '0' else c_dominant;
                    state                             <= s_error_overload;
                    bit_count                         <= 0;
                  else
                    state     <= s_eof;
                    bit_count <= 0;
                  end if;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_ack_delimiter (TX path): release to recessive or error
            -- Extended ACK window: also accept dominant arriving at the
            -- delimiter SP (covers bus-delays > ACK-slot/2 in the test bench).
            -----------------------------------------------------------------
            when s_ack_delimiter =>
              if is_transmitter then
                if (not ack_success_seen and pcs_i.rx_data = c_dominant) then
                  ack_success_seen <= true;
                end if;
                if ack_success_seen or pcs_i.rx_data = c_dominant then
                  v_tx_polarity := c_recessive;
                  v_bit_driven  := true;
                  state         <= s_eof;
                else
                  ack_error_caused_flag     <= true;
                  pcs_o.tx_data             <= c_recessive when fce_i.error_active = '0' else c_dominant;
                  pcs_o.data_phase_stop     <= '1';
                  mac_ser_o.transfer_status <= c_disturbed;
                  was_previous_frame_tx     <= true;
                  bit_count                 <= 0;
                  dominant_run_count        <= 0;
                  state                     <= s_error_overload;
                  overload                  <= false;
                  pcs_o.next_bit_is_brs     <= '0';
                  pcs_o.next_bit_is_res     <= '0';
                end if;
              else
                -- RX: just consume the delimiter and advance
                state     <= s_eof;
                bit_count <= 0;
              end if;

            -----------------------------------------------------------------
            -- s_eof: 7 recessive bits
            -- TX evaluates ACK error at bit 0; RX checks recessive,
            -- triggers frame-valid at second-last bit (ISO 6.6.15.2).
            -----------------------------------------------------------------
            when s_eof =>
              if is_transmitter then
                v_tx_polarity := c_recessive;
                v_bit_driven  := true;
                if (bit_count = 0 and not ack_success_seen) then
                  v_enter_error         := true;
                  v_ack_error           := true;
                  ack_error_caused_flag <= true;
                end if;
                if (bit_count = c_eof_field_width - 1) then
                  mac_ser_o.transfer_status <= c_transmitted;
                  was_previous_frame_tx     <= true;
                  fce_o.successful_transfer <= '1';
                  state                     <= s_intermission;
                  bit_count                 <= 0;
                else
                  bit_count <= bit_count + 1;
                end if;
              else
                if (pcs_i.rx_data = c_dominant) then
                  fce_o.sending_error_overload_flag <= '1';
                  fce_o.error                       <= '1';
                  if bit_count = (c_eof_field_width - 1) then
                    -- Last bit dominant is overload
                    pcs_o.tx_data <= c_dominant;
                    overload      <= true;
                    fce_o.error   <= '0';
                  else
                    pcs_o.tx_data <= c_recessive when fce_i.error_active = '0' else c_dominant;
                  end if;
                  state     <= s_error_overload;
                  bit_count <= 0;
                else
                  if bit_count = (c_eof_field_width - 1) then
                    state     <= s_intermission;
                    bit_count <= 0;
                  elsif bit_count = (c_eof_field_width - 2) then
                    -- Frame valid (ISO 6.6.15.2): start streaming to LLC
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
            -- s_error_overload: 6 dominant or recessive flag bits
            -- TX uses passive-flag exemption tracking; RX uses simpler
            -- combined flag+delimiter sequence.
            -----------------------------------------------------------------
            when s_error_overload =>
              if is_transmitter then
                if (bit_count < c_error_flag_width - 1) then
                  if (not overload and fce_i.error_active = '0' and pcs_i.rx_data = c_dominant) then
                    saw_dominant_during_flag <= true;
                    bit_count                <= 0;
                  else
                    bit_count <= bit_count + 1;
                  end if;
                else
                  dominant_run_count <= 0;
                  bit_count          <= 0;
                  overload           <= false;
                  state              <= s_error_delimiter;
                  pcs_o.tx_data      <= c_recessive;
                  if (ack_error_caused_flag) then
                    fce_o.error                         <= '1';
                    fce_o.passive_tx_ack_error_exempt_1 <= '1' when fce_i.error_active = '0' and not saw_dominant_during_flag;
                  end if;
                end if;
              else
                -- Receiver: combined flag + delimiter sequence (legacy RX)
                fce_o.sending_error_overload_flag <= '1';
                bit_count                         <= bit_count + 1;
                if bit_count = (c_error_sequence_width - 1) then
                  bit_count <= 0;
                  if pcs_i.rx_data /= c_dominant then
                    state <= s_intermission;
                  else
                    pcs_o.tx_data <= c_dominant;
                  end if;
                elsif (bit_count < c_error_flag_width) then
                  pcs_o.tx_data <= c_recessive when (fce_i.error_active = '0') and not overload else c_dominant;
                else
                  pcs_o.tx_data <= c_recessive;
                end if;
              end if;

            -----------------------------------------------------------------
            -- s_error_delimiter (TX): 8 recessive bits, with primary-error
            -- and delimiter-too-late tracking.
            -----------------------------------------------------------------
            when s_error_delimiter =>
              pcs_o.tx_data <= c_recessive;
              if (pcs_i.rx_data = c_dominant) then
                if (dominant_run_count = c_error_delimiter_width - 1) then
                  fce_o.error_delimiter_too_late <= '1';
                  dominant_run_count             <= 0;
                else
                  fce_o.primary_error <= '1' when not overload and dominant_run_count = 0;
                  dominant_run_count  <= dominant_run_count + 1;
                end if;
                overload      <= (bit_count = c_error_delimiter_width - 2);
                fce_o.error   <= '1' when bit_count /= c_error_delimiter_width - 2;
                bit_count     <= 0;
                state         <= s_error_overload;
                pcs_o.tx_data <= c_dominant;
              else
                if (bit_count = c_error_delimiter_width - 1) then
                  state     <= s_intermission;
                  bit_count <= 0;
                else
                  bit_count <= bit_count + 1;
                end if;
              end if;

            when others =>
              state     <= s_bus_reintegration;
              bit_count <= 0;

          end case;
        end if;

        -----------------------------------------------------------------
        -- Post-FSM bit-driving block (TX-only)
        -----------------------------------------------------------------
        if (v_bit_driven and is_transmitter) then
          -- React to SSP-deferred bit error
          if (secondary_sample_point_error_pending) then
            v_enter_error                        := true;
            secondary_sample_point_error_pending <= false;
          end if;

          -- Bit error detection at SP - only valid in nominal phase. In
          -- data phase the bus has multi-bit propagation delay, so the
          -- SP-based check using polarity_history(0) is meaningless; bit
          -- errors there are detected via SSP
          -- (secondary_sample_point_error_pending). The `not in_data_phase`
          -- gate alone is sufficient: in_data_phase is set at MAC-SP of
          -- BRS body so the gate suppresses ESI and every subsequent
          -- data-phase bit. At MAC-SP of BRS itself the check is active
          -- and passes naturally (BRS-SP is in nominal timing, prop is
          -- covered, polarity_history(0) holds the BRS value). The
          -- previous additional `pcs_o.next_bit_is_brs = '0'` gate was
          -- redundant for the data-phase suppression and only had the
          -- side-effect of masking real bit errors at the BRS bit, so it
          -- has been removed.
          if (not in_data_phase
              and polarity_history(0) /= pcs_i.rx_data) then
            if (v_in_arbitration_field and pcs_i.rx_data = c_dominant) then
              v_lost_arb := true;
            elsif (not v_in_ack_slot) then
              v_enter_error := true;
            end if;
          end if;

          if v_enter_error then
            -- ACK errors defer fce_o.error to flag-end for exemption
            fce_o.error               <= '1' when not v_ack_error;
            pcs_o.tx_data             <= c_recessive when fce_i.error_active = '0' else c_dominant;
            pcs_o.next_bit_is_brs     <= '0';
            pcs_o.data_phase_stop     <= '1';
            mac_ser_o.transfer_status <= c_disturbed;
            was_previous_frame_tx     <= true;
            bit_count                 <= 0;
            dominant_run_count        <= 0;
            state                     <= s_error_overload;
            overload                  <= false;
            pcs_o.next_bit_is_res     <= '0';
          elsif v_lost_arb then
            mac_ser_o.transfer_status <= c_lost_arb;
            was_previous_frame_tx     <= false;
            is_transmitter            <= false;
            bit_count                 <= 0;
            state                     <= s_intermission;
          else
            pcs_o.tx_data    <= v_tx_polarity;
            polarity_history <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & v_tx_polarity;
            bs_o.valid       <= '1';
            bs_o.data        <= v_tx_polarity;
            -- FD CRC: dynamic stuff bits + non-stuff SBC data
            if (v_in_dynamic_stuff_field or (not v_is_stuff_bit and state = s_sbc)) then
              crc_o.valid_fd <= '1';
              crc_o.data_fd  <= v_tx_polarity;
            end if;
            -- CC CRC: non-stuff DSB only
            if (not v_is_stuff_bit and v_in_dynamic_stuff_field) then
              crc_o.valid_cc <= '1';
              crc_o.data_cc  <= v_tx_polarity;
            end if;

            if v_is_stuff_bit then
              bit_count <= bit_count;
              state     <= state;
            end if;
          end if;
        end if;

        -- Clear stream_start once it has been picked up by the streamer
        llc_stream_start <= not llc_stream_done when llc_stream_done;

      end if;
    end if;
  end process p_fsm;

end architecture rtl;

-- eof
