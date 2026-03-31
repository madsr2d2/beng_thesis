--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Media Access Control (MAC) FSM for CAN/CAN-FD transmission.
--                Coordinates serialization, bit stuffing, CRC generation, and
--                physical signaling (PCS) timing.
--                Frame transmission is split into three pipelined states:
--                s_frame_init  - compute frame_params, drive SOF
--                s_monitor_bit - wait for SP/SSP, evaluate get_bit_info
--                s_transmit_bit - drive next bit via get_mac_frame_bit
--                Protocol references: ISO 11898-1:2015
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-31  MRDSA     Converted to company header format
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

  use work.pk_man_global.all;
  use work.pk_can_types.all;

entity can_mac_fsm_tx is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- Serializer interface
    mac_ser_i : in    t_can_mac_ser_fsm_if_s2d;
    mac_ser_o : out   t_can_mac_ser_fsm_if_d2s;

    -- PCS interface
    pcs_i : in    t_can_mac_pcs_if_s2m;
    pcs_o : out   t_can_mac_pcs_if_m2s;

    -- Bit stuffer FD interface
    bs_fd_i   : in    t_can_mac_fsm_bs_if_s2m;
    bs_fd_o   : out   t_can_mac_fsm_bs_if_m2s;
    bs_fd_rst : out   std_logic;

    -- CRC interface
    crc_i   : in    t_can_mac_fsm_crc_if_s2m;
    crc_o   : out   t_can_mac_fsm_crc_if_m2s;
    crc_rst : out   std_logic;

    -- Fault Confinement Entity interface (ISO 11898-1 Table 16/17)
    fce_i : in    t_can_mac_fce_if_s2m;
    fce_o : out   t_can_mac_fce_if_m2s
  );
end entity can_mac_fsm_tx;

architecture rtl of can_mac_fsm_tx is

  ---------------------------------------------------------------------------
  -- FSM state type
  ---------------------------------------------------------------------------
  type t_fsm_state is (
    s_bus_reintegration,
    s_intermission,
    s_suspend_transmission,
    s_bus_idle,
    s_frame_init,
    s_monitor_bit,
    s_transmit_bit,
    s_active_error_flag,
    s_passive_error_flag,
    s_overload_flag
  );

  ---------------------------------------------------------------------------
  -- Registered state signals
  ---------------------------------------------------------------------------
  signal state                         : t_fsm_state;
  signal bit_count                     : t_bit_count;
  signal polarity_history              : t_tdc_polarity_history;
  signal last_transmitted_bit          : t_mac_frame_bit;
  signal last_transmitted_bit_polarity : std_logic;
  signal monitored_bit_event           : t_monitor_event_tx;
  signal was_previous_frame_tx         : boolean;
  signal ack_success_seen              : boolean;
  signal overload_condition            : boolean;
  signal ssp_error_pending             : boolean;
  signal in_data_phase                 : std_logic;

  -- Fault confinement tracking
  signal ack_error_caused_flag     : boolean;
  signal dominant_seen_during_flag : boolean;
  signal dominant_run_count        : integer range 0 to 15;

  -- ISO 11898-1: 6.6.8 - dominant at 3rd intermission bit detected as SOF;
  -- skip SOF output and start with first ID bit on next frame entry.
  signal skip_sof : boolean;

  -- Cached frame parameters (calculated once per frame from LLC metadata)
  signal frame_params : t_frame_params;

begin

  p_fsm : process (clk_i) is

    -- Temporary per-cycle values (read-back within same cycle)
    variable v_tx_bit : t_mac_frame_bit;

    -- Next-value variable (read-back within same cycle)
    variable v_in_data_phase : std_logic;

    -- Frame parameter calculation (used only during frame initialization)
    variable v_frame_params : t_frame_params;

    -- Error flag bit (active or passive, selected per FCE state)
    variable v_error_flag_bit : t_mac_frame_bit;

    -- Bus monitor result (used inline in s_monitor_bit)
    variable v_bit_info : t_bit_info;

    -- Handles logic common to quiet states (ISO 11898-1: 6.6.7):
    -- hold-signal management and SP-based idle-run counting.
    procedure process_quiet_phase_common (
      constant quiet_bit_name_c : in t_mac_frame_bit_name
    ) is
    begin

      pcs_o.valid               <= '0';
      pcs_o.polarity            <= c_recessive;
      pcs_o.use_data_rate       <= '0';
      pcs_o.start_tdc           <= '0';
      fce_o.transmitting        <= '0';
      ssp_error_pending         <= false;
      mac_ser_o.transfer_status <= c_ongoing;

      last_transmitted_bit          <= (c_recessive, quiet_bit_name_c);
      last_transmitted_bit_polarity <= c_recessive;

      if (pcs_i.sp = '1') then
        -- ISO 11898-1: 6.6.7.5 - count consecutive recessive bits at SP;
        -- dominant resets the run counter.
        if (pcs_i.bus_polarity = c_recessive) then
          if (bit_count < t_bit_count'high) then
            bit_count <= bit_count + 1;
          end if;
        else
          bit_count <= 0;
        end if;
      end if;

    end procedure process_quiet_phase_common;

    -- Transmits the next non-stuff frame bit:
    -- computes bit(bit_count+1), updates FIFO/bit_count, and drives serializer/CRC/stuffer handshakes.
    procedure transmit_normal_bit is

      variable v_prepare_position   : t_bit_count;
      variable v_serializer_sourced : boolean;
      variable v_crc_cc_eligible    : boolean;

    begin

      v_prepare_position := bit_count + 1;

      v_tx_bit := get_mac_frame_bit(
                                    bit_count         => v_prepare_position,
                                    ser_data          => mac_ser_i.data,
                                    metadata          => mac_ser_i.llc_metadata,
                                    frame_params      => frame_params,
                                    previous_polarity => last_transmitted_bit_polarity,
                                    sbc               => bs_fd_i.sbc,
                                    crc               => crc_i.crc
                                  );

      polarity_history              <= polarity_history(polarity_history'high - 1 downto 0) & v_tx_bit.polarity;
      last_transmitted_bit          <= v_tx_bit;
      last_transmitted_bit_polarity <= v_tx_bit.polarity;

      if (v_prepare_position < frame_params.crc_delimiter + c_eof_start_offset + c_eof_field_width) then
        pcs_o.valid    <= '1';
        pcs_o.polarity <= v_tx_bit.polarity;
      end if;

      bit_count <= v_prepare_position;

      v_serializer_sourced := v_tx_bit.bit_name = base_id_bit or
                              v_tx_bit.bit_name = extended_id_bit or
                              v_tx_bit.bit_name = data_bit;
      if (v_serializer_sourced) then
        mac_ser_o.ready <= '1';
      end if;

      -- ISO 11898-1: 6.6.4.4 - Logical bits fed to CRC
      v_crc_cc_eligible := v_prepare_position < frame_params.crc_start and
                           v_tx_bit.bit_name /= fixed_stuff_bit;
      if (v_crc_cc_eligible) then
        crc_o.valid <= '1';
        crc_o.data  <= v_tx_bit.polarity;
      end if;

      if (v_prepare_position < frame_params.dynamic_stuff_stop) then
        bs_fd_o.valid <= '1';
        bs_fd_o.data  <= v_tx_bit.polarity;
      end if;

      -- ISO 11898-1: 7.3.2 - data phase starts at SP of BRS (recessive);
      -- preparing ESI here means use_data_rate is registered for the ESI bit boundary.
      if (mac_ser_i.llc_metadata.brs = '1' and v_tx_bit.bit_name = esi_bit) then
        v_in_data_phase := '1';
      elsif (v_tx_bit.bit_name = crc_delimiter_bit) then
        v_in_data_phase := '0';
      end if;

      pcs_o.start_tdc     <= '1' when v_tx_bit.bit_name = fdf_bit else '0';
      pcs_o.use_data_rate <= v_in_data_phase;

    end procedure transmit_normal_bit;

    -- Handles behavior shared by active/passive error-flag and overload-flag states:
    -- flag/delimiter serialization, delimiter-dominant run tracking, and reactive overload trigger.
    procedure process_flag_transmission (
      constant flag_bit_c                       : in t_mac_frame_bit;
      constant track_error_delimiter_too_late_c : in boolean;
      constant transfer_status_c                : in std_logic_vector(2 downto 0) := c_disturbed
    ) is

      variable v_in_flag_field       : boolean;
      variable v_track_delimiter_run : boolean;

    begin

      -- Hold signals: driven every cycle in flag states
      fce_o.transmitting                <= '1';
      fce_o.sending_error_overload_flag <= '1';
      pcs_o.valid                       <= '1';
      pcs_o.use_data_rate               <= '0';
      pcs_o.start_tdc                   <= '0';
      mac_ser_o.transfer_status         <= transfer_status_c;

      v_in_flag_field := (bit_count < c_error_flag_width);

      if (v_in_flag_field) then
        v_tx_bit := flag_bit_c;
      else
        v_tx_bit := c_error_delimiter_bit;
      end if;

      pcs_o.polarity                <= v_tx_bit.polarity;
      last_transmitted_bit          <= v_tx_bit;
      last_transmitted_bit_polarity <= v_tx_bit.polarity;

      if (pcs_i.sp = '1') then
        if (bit_count < c_error_sequence_width - 1) then
          bit_count <= bit_count + 1;
        end if;

        -- ISO 11898-1: 8.1.3.3 Table 16 (Error_delimiter_too_late) and
        -- 8.1.4.2 rule f): applies to error-flag delimiter handling.
        v_track_delimiter_run := track_error_delimiter_too_late_c and not v_in_flag_field;
        if (v_track_delimiter_run) then
          if (pcs_i.bus_polarity = c_recessive) then
            dominant_run_count <= 0;
          elsif (dominant_run_count = c_error_delimiter_width - 1) then
            fce_o.error_delimiter_too_late <= '1';
            dominant_run_count             <= 0;
          else
            dominant_run_count <= dominant_run_count + 1;
          end if;
        end if;

        -- ISO 11898-1: 6.6.21.3.2 b) reactive OF:
        -- dominant at last bit of error/overload delimiter triggers OF.
        if (bit_count >= c_error_sequence_width - 1 and pcs_i.bus_polarity = c_dominant) then
          overload_condition <= true;
        end if;

        -- ISO 11898-1: 8.1.3.3 Table 16 - Primary_error:
        -- dominant detected while sending an error flag (not overload).
        if (track_error_delimiter_too_late_c and v_in_flag_field and pcs_i.bus_polarity = c_dominant) then
          fce_o.primary_error <= '1';
        end if;

      end if;

      if (overload_condition) then
        state                     <= s_overload_flag;
        bit_count                 <= 0;
        dominant_seen_during_flag <= false;
        dominant_run_count        <= 0;
      elsif (bit_count = c_error_sequence_width - 1 and pcs_i.sp = '1') then
        state     <= s_intermission;
        bit_count <= 0;
      end if;

    end procedure process_flag_transmission;

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        state                         <= s_bus_reintegration;
        bit_count                     <= 0;
        polarity_history              <= (others => c_recessive);
        last_transmitted_bit          <= c_reset_mac_frame_bit;
        last_transmitted_bit_polarity <= c_recessive;
        monitored_bit_event           <= none;
        was_previous_frame_tx         <= false;
        ack_success_seen              <= false;
        overload_condition            <= false;
        ssp_error_pending             <= false;
        ack_error_caused_flag         <= false;
        dominant_seen_during_flag     <= false;
        dominant_run_count            <= 0;
        skip_sof                      <= false;
        in_data_phase                 <= '0';
        frame_params                  <= c_frame_params_reset;

        mac_ser_o <= c_ser_fsm_if_d2s_reset;
        pcs_o     <= c_mac_to_pcs_if_reset;
        bs_fd_o   <= c_mac_fsm_to_bs_fd_if_reset;
        bs_fd_rst <= '0';
        crc_o     <= c_mac_fsm_to_crc_if_reset;
        crc_rst   <= '0';
        fce_o     <= c_mac_to_fce_if_reset;
      else
        v_tx_bit := c_reset_mac_frame_bit;

        v_in_data_phase := '0';

        ---------------------------------------------------------------------
        -- Pulse defaults (cleared every cycle, set only when active)
        ---------------------------------------------------------------------
        bs_fd_o                           <= c_mac_fsm_to_bs_fd_if_reset;
        bs_fd_rst                         <= '0';
        mac_ser_o.ready                   <= '0';
        crc_o.valid                       <= '0';
        crc_rst                           <= '0';
        fce_o.error                       <= '0';
        fce_o.primary_error               <= '0';
        fce_o.counters_unchanged          <= '0';
        fce_o.successful_transfer         <= '0';
        fce_o.error_delimiter_too_late    <= '0';
        fce_o.sending_error_overload_flag <= '0';
        monitored_bit_event               <= none;
        overload_condition                <= false;

        ---------------------------------------------------------------------
        -- State machine
        ---------------------------------------------------------------------
        case state is

          -----------------------------------------------------------------
          -- Wait for idle condition(s): 1 for normal, 128 for bus-off
          -- (ISO 11898-1: 6.6.7.5, 8.1.4.4 Figure 43 T5).
          -----------------------------------------------------------------
          when s_bus_reintegration =>
            process_quiet_phase_common(bus_integration_bit);
            if (bit_count = c_bus_idle_condition_width - 1) then
              state     <= s_bus_idle;
              bit_count <= 0;
            end if;

          when s_intermission =>
            process_quiet_phase_common(intermission_bit);
            -- ISO 11898-1: 6.6.21.3.2 b) - dominant detected during first
            -- two intermission bits triggers overload handling.
            if (pcs_i.sp = '1' and pcs_i.bus_polarity = c_dominant and bit_count < c_intermission_width - 1) then
              overload_condition <= true;
            end if;
            if (overload_condition) then
              state                     <= s_overload_flag;
              bit_count                 <= 0;
              dominant_seen_during_flag <= false;
              dominant_run_count        <= 0;
            elsif (bit_count = c_intermission_width - 1 and pcs_i.sp = '1' and pcs_i.bus_polarity = c_dominant) then
              -- ISO 11898-1: 6.6.7.2 / 6.6.8 - dominant at 3rd intermission bit
              -- interpreted as SOF; transmit first ID bit without SOF if eligible.
              if (mac_ser_i.valid = '1' and
                  (fce_i.error_passive_request = '0' or not was_previous_frame_tx)) then
                state     <= s_frame_init;
                bit_count <= 0;
                skip_sof  <= true;
              else
                state     <= s_bus_idle;
                bit_count <= 0;
              end if;
            elsif (bit_count = c_intermission_width - 1) then
              -- ISO 11898-1: 6.6.7.4 / 6.6.7.3 - error-passive transmitters
              -- enter suspend_transmission; all others enter bus_idle.
              if (fce_i.error_passive_request = '1' and was_previous_frame_tx) then
                state     <= s_suspend_transmission;
                bit_count <= 0;
              else
                state     <= s_bus_idle;
                bit_count <= 0;
              end if;
            end if;

          -----------------------------------------------------------------
          -- ISO 11898-1: 6.6.7.4 - error-passive nodes that transmitted
          -- the previous frame shall suspend for 8 additional bit times.
          -----------------------------------------------------------------
          when s_suspend_transmission =>
            process_quiet_phase_common(suspend_transmission_bit);
            if (overload_condition) then
              state                     <= s_overload_flag;
              bit_count                 <= 0;
              dominant_seen_during_flag <= false;
              dominant_run_count        <= 0;
            elsif (bit_count = c_suspend_transmission_width - 1) then
              state     <= s_bus_idle;
              bit_count <= 0;
            end if;

          -----------------------------------------------------------------
          -- ISO 11898-1: 6.6.7.3 - bus idle; any node may start transmission.
          -----------------------------------------------------------------
          when s_bus_idle =>
            process_quiet_phase_common(idle_bit);
            if (mac_ser_i.valid = '1' and pcs_i.sp = '1') then
              state     <= s_frame_init;
              bit_count <= 0;
              bs_fd_rst <= '1';
              crc_rst   <= '1';
            end if;

          -----------------------------------------------------------------
          -- Compute frame parameters, initialize counters, drive SOF.
          -- When skip_sof is true (ISO 11898-1: 6.6.7.2 / 6.6.8), the
          -- SOF has already been observed on the bus. The first ID bit
          -- (ser_data) is driven onto PCS instead.
          -----------------------------------------------------------------
          when s_frame_init =>
            fce_o     <= c_mac_to_fce_if_reset;
            pcs_o     <= c_mac_to_pcs_if_reset;
            mac_ser_o <= c_ser_fsm_if_d2s_reset;
            crc_o     <= c_mac_fsm_to_crc_if_reset;

            v_frame_params        := get_frame_params(mac_ser_i.llc_metadata);
            frame_params          <= v_frame_params;
            crc_o.crc_poly_select <= v_frame_params.crc_poly_select;

            fce_o.transmitting <= '1';
            pcs_o.valid        <= '1';

            polarity_history          <= (0 => c_dominant, others => c_recessive);
            last_transmitted_bit      <= c_sof_bit;
            ack_success_seen          <= false;
            ssp_error_pending         <= false;
            ack_error_caused_flag     <= false;
            dominant_seen_during_flag <= false;
            dominant_run_count        <= 0;
            v_in_data_phase           := '0';

            bs_fd_o.valid <= '1';
            bs_fd_o.data  <= c_dominant;

            v_tx_bit                      := c_sof_bit;
            last_transmitted_bit_polarity <= c_dominant;
            bit_count                     <= 0;

            crc_o.valid <= '1';
            crc_o.data  <= c_dominant;

            if (skip_sof) then
              pcs_o.polarity <= mac_ser_i.data;
            else
              pcs_o.polarity <= c_dominant;
            end if;
            skip_sof <= false;

            state <= s_monitor_bit;

          -----------------------------------------------------------------
          -- Wait for SP/SSP, evaluate get_bit_info, handle errors or
          -- proceed to s_transmit_bit.
          -----------------------------------------------------------------
          when s_monitor_bit =>
            v_in_data_phase := in_data_phase;

            -- EOF completion: bit_count was set by s_transmit_bit
            if (bit_count = frame_params.crc_delimiter + c_eof_start_offset + c_eof_field_width) then
              -- ISO 11898-1: 8.1.4.2 rule g) - successful transmission.
              mac_ser_o.transfer_status <= c_transmitted;
              was_previous_frame_tx     <= true;
              fce_o.successful_transfer <= '1';
              state                     <= s_intermission;
              bit_count                 <= 0;

            elsif (pcs_i.sp = '1' or pcs_i.ssp = '1') then
              if (fce_i.error_passive_request = '1') then
                v_error_flag_bit := c_passive_error_flag_bit;
              else
                v_error_flag_bit := c_active_error_flag_bit;
              end if;

              -- SSP: latch pending error (ISO 11898-1: 7.3.4)
              if (pcs_i.ssp = '1') then
                v_bit_info        := get_bit_info(
                                                  bit_name               => last_transmitted_bit.bit_name,
                                                  polarity_history       => polarity_history,
                                                  tdc_delay              => to_integer(unsigned(pcs_i.tdc_delay)),
                                                  monitored_bit_polarity => pcs_i.bus_polarity,
                                                  metadata               => mac_ser_i.llc_metadata
                                                );
                ssp_error_pending <= ssp_error_pending or (v_bit_info.event_type = bit_error);
              end if;

              -- Deferred SSP error fires at SP
              if (ssp_error_pending and pcs_i.sp = '1') then
                -- ISO 11898-1: 6.6.21.3.1 - react at SP to SSP-detected error
                was_previous_frame_tx     <= true;
                mac_ser_o.transfer_status <= c_disturbed;
                pcs_o.valid               <= '1';
                pcs_o.polarity            <= v_error_flag_bit.polarity;
                monitored_bit_event       <= bit_error;
                ssp_error_pending         <= false;
                if (fce_i.error_passive_request = '1') then
                  state <= s_passive_error_flag;
                else
                  state <= s_active_error_flag;
                end if;
                bit_count                 <= 0;
                dominant_seen_during_flag <= false;
                dominant_run_count        <= 0;

              elsif (pcs_i.sp = '1') then
                -- SP: evaluate bus monitor inline
                v_bit_info := get_bit_info(
                                           bit_name               => last_transmitted_bit.bit_name,
                                           polarity_history       => polarity_history,
                                           tdc_delay              => to_integer(unsigned(pcs_i.tdc_delay)),
                                           monitored_bit_polarity => pcs_i.bus_polarity,
                                           metadata               => mac_ser_i.llc_metadata
                                         );

                case v_bit_info.event_type is
                  when lost_arbitration =>
                    was_previous_frame_tx     <= false;
                    mac_ser_o.transfer_status <= c_lost_arb;
                    monitored_bit_event       <= lost_arbitration;
                    state                     <= s_intermission;
                    bit_count                 <= 0;

                  when ack_detected =>
                    was_previous_frame_tx     <= true;
                    ack_success_seen          <= true;
                    mac_ser_o.transfer_status <= v_bit_info.transfer_status;
                    monitored_bit_event       <= ack_detected;
                    state                     <= s_transmit_bit;

                  when bit_error | ack_error =>
                    -- ISO 11898-1: 8.1.3.3 Table 16 - Error: Error detected
                    fce_o.error               <= '1';
                    was_previous_frame_tx     <= true;
                    mac_ser_o.transfer_status <= c_disturbed;
                    pcs_o.valid               <= '1';
                    pcs_o.polarity            <= v_error_flag_bit.polarity;
                    monitored_bit_event       <= v_bit_info.event_type;
                    if (fce_i.error_passive_request = '1') then
                      state <= s_passive_error_flag;
                    else
                      state <= s_active_error_flag;
                    end if;
                    bit_count                 <= 0;
                    dominant_seen_during_flag <= false;
                    dominant_run_count        <= 0;

                  when none =>
                    mac_ser_o.transfer_status <= v_bit_info.transfer_status;
                    monitored_bit_event       <= none;

                    -- ACK error: no dominant seen during ACK window (CC and FD)
                    if (bit_count = frame_params.crc_delimiter + c_ack_delimiter_offset and
                        (not ack_success_seen)) then
                      fce_o.error               <= '1';
                      was_previous_frame_tx     <= true;
                      mac_ser_o.transfer_status <= c_disturbed;
                      pcs_o.valid               <= '1';
                      pcs_o.polarity            <= v_error_flag_bit.polarity;
                      monitored_bit_event       <= ack_error;
                      ack_error_caused_flag     <= true;
                      if (fce_i.error_passive_request = '1') then
                        state <= s_passive_error_flag;
                      else
                        state <= s_active_error_flag;
                      end if;
                      bit_count                 <= 0;
                      dominant_seen_during_flag <= false;
                      dominant_run_count        <= 0;
                    else
                      state <= s_transmit_bit;
                    end if;

                end case;
              end if;
            end if;

          -----------------------------------------------------------------
          -- Drive next bit onto PCS (stuff bit or normal bit), then
          -- return to s_monitor_bit.
          -----------------------------------------------------------------
          when s_transmit_bit =>
            v_in_data_phase := in_data_phase;

            -- Stuff bit insertion takes priority
            if (bs_fd_i.valid = '1' and bit_count < frame_params.dynamic_stuff_stop) then
              v_tx_bit                      := (polarity => bs_fd_i.data, bit_name => stuff_bit);
              polarity_history              <= polarity_history(polarity_history'high - 1 downto 0) & bs_fd_i.data;
              last_transmitted_bit          <= v_tx_bit;
              last_transmitted_bit_polarity <= bs_fd_i.data;
              pcs_o.valid                   <= '1';
              pcs_o.polarity                <= bs_fd_i.data;
              if (bit_count < frame_params.dynamic_stuff_stop) then
                bs_fd_o.valid <= '1';
                bs_fd_o.data  <= bs_fd_i.data;
              end if;
              -- ISO 11898-1: 6.6.4.4 - Stuff bits in FD frames are included in CRC
              if (mac_ser_i.llc_metadata.fdf = '1' and bit_count < frame_params.crc_start) then
                crc_o.valid <= '1';
                crc_o.data  <= bs_fd_i.data;
              end if;
            else
              transmit_normal_bit;
            end if;

            state <= s_monitor_bit;

          -----------------------------------------------------------------
          -- ISO 11898-1: 6.6.5 - active error flag (6 dominant) + delimiter
          -- (8 recessive).
          -----------------------------------------------------------------
          when s_active_error_flag =>
            process_flag_transmission(c_active_error_flag_bit, true);

          -----------------------------------------------------------------
          -- ISO 11898-1: 6.6.5 - passive error flag (6 recessive) + delimiter
          -- (8 recessive).
          -----------------------------------------------------------------
          when s_passive_error_flag =>
            process_flag_transmission(c_passive_error_flag_bit, true);
            -- ISO 11898-1: 8.1.4.2 rule c), Exception 1:
            -- passive transmitter ACK error without dominant seen in passive EF.
            if (pcs_i.sp = '1' and ack_error_caused_flag) then
              if (bit_count < c_error_flag_width and pcs_i.bus_polarity = c_dominant) then
                dominant_seen_during_flag <= true;
              end if;
              if (bit_count >= c_error_sequence_width - 1 and not dominant_seen_during_flag) then
                fce_o.counters_unchanged <= '1';
              end if;
            end if;

          -----------------------------------------------------------------
          -- ISO 11898-1: 6.6.6 - overload flag (6 dominant) + delimiter
          -- (8 recessive).
          -----------------------------------------------------------------
          when s_overload_flag =>
            process_flag_transmission(c_overload_flag_bit, false, c_ongoing);

          when others =>
            state     <= s_bus_reintegration;
            bit_count <= 0;

        end case;

        in_data_phase <= v_in_data_phase;
      end if;
    end if;

  end process p_fsm;

end architecture rtl;
