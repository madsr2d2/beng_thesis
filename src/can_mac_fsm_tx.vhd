--------------------------------------------------------------------------------
-- Title      : CAN MAC Transmitter FSM
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : can_mac_fsm_tx.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Media Access Control (MAC) FSM for CAN/CAN-FD transmission.
--              Coordinates serialization, bit stuffing, CRC generation, and
--              physical signaling (PCS) timing.
--
-- Protocol references: ISO 11898-1:2015
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

entity can_mac_fsm_tx is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- Serializer interface
    mac_ser_i : in    can_mac_ser_fsm_tx_if_s2d_t;
    mac_ser_o : out   can_mac_ser_fsm_tx_if_d2s_t;

    -- PCS interface
    pcs_i : in    can_mac_pcs_tx_if_d2s_t;
    pcs_o : out   can_mac_pcs_tx_if_s2d_t;

    -- Bit stuffer FD interface
    bs_fd_i : in    can_mac_fsm_bs_tx_if_d2s_t;
    bs_fd_o : out   can_mac_fsm_bs_tx_if_s2d_t;

    -- CRC interface
    crc_i : in    can_mac_fsm_crc_tx_if_d2s_t;
    crc_o : out   can_mac_fsm_crc_tx_if_s2d_t;

    -- Fault Confinement Entity interface (ISO 11898-1 Table 16/17)
    fce_i : in    can_mac_fce_if_d2s_t;
    fce_o : out   can_mac_fce_if_s2d_t;

    -- Debug ports (test visibility)
    debug_ack_error_o  : out boolean;
    debug_form_error_o : out boolean;
    debug_data_exit_o  : out boolean;
    debug_fsm_state_o  : out can_mac_fsm_tx_state_t
  );
end entity can_mac_fsm_tx;

architecture rtl of can_mac_fsm_tx is

  ---------------------------------------------------------------------------
  -- Registered state signals (driven by fsm_sequential)
  ---------------------------------------------------------------------------
  signal state                         : can_mac_fsm_tx_state_t;
  signal prev_state                    : can_mac_fsm_tx_state_t;
  signal bit_count                     : bit_count_t;
  signal fifo                          : transmitted_bits_fifo_t;
  signal fifo_write_ptr                : fifo_write_ptr_t;
  signal last_transmitted_bit_polarity : polarity_t;
  signal monitored_bit_event           : tx_mac_monitor_event_t;
  signal was_previous_frame_tx         : boolean;
  signal ack_success_seen              : boolean;
  signal bit_count_monitored           : boolean;
  signal overload_condition            : boolean;
  signal ssp_error_pending             : boolean;

  -- Fault confinement tracking
  signal ack_error_caused_flag     : boolean;
  signal dominant_seen_during_flag : boolean;
  signal dominant_run_count        : integer range 0 to 15;

  -- Threshold used for delimiter-dominant run tracking before raising
  -- Error_delimiter_too_late (ISO 11898-1: 8.1.3.3 Table 16).
  constant delimiter_dominant_run_limit_c : integer := 7;

  -- Debug signals for test visibility
  signal ack_error_detected     : boolean; -- Pulses when ACK error is detected
  signal form_error_detected    : boolean; -- Pulses when form error is detected (placeholder)
  signal data_phase_exit_strobe : boolean; -- Pulses when data phase exits at SP

begin

  fsm_sequential : process (clk_i) is

    -- Temporary per-cycle values
    variable v_tx_bit             : mac_frame_bit_t;
    variable v_monitored_bit_info : observed_mac_frame_bit_info_t;

    -- Named guard variables
    variable frame_transmitted_v          : boolean;
    variable sample_strobe_v              : boolean;
    variable error_sequence_complete_v    : boolean;
    variable state_entry_v                : boolean;
    variable bus_is_idle_v                : boolean;
    variable intermission_ended_v         : boolean;
    variable must_suspend_transmission_v  : boolean;
    variable suspend_transmission_ended_v : boolean;
    variable error_detected_v             : boolean;
    variable error_flag_ended_v           : boolean;
    variable sp_sample_strobe_v           : boolean;

    -- Registered next-value variables
    variable v_state                         : can_mac_fsm_tx_state_t;
    variable v_bit_count                     : bit_count_t;
    variable v_fifo                          : transmitted_bits_fifo_t;
    variable v_fifo_write_ptr                : fifo_write_ptr_t;
    variable v_last_transmitted_bit_polarity : polarity_t;
    variable v_monitored_bit_event           : tx_mac_monitor_event_t;
    variable v_was_previous_frame_tx         : boolean;
    variable v_ack_success_seen              : boolean;
    variable v_bit_count_monitored           : boolean;
    variable v_overload_condition            : boolean;
    variable v_ssp_error_pending             : boolean;
    variable v_ack_error_caused_flag         : boolean;
    variable v_dominant_seen_during_flag     : boolean;
    variable v_dominant_run_count            : integer range 0 to 15;

    -- Registered output next-value variables
    variable v_mac_ser_o : can_mac_ser_fsm_tx_if_d2s_t;
    variable v_pcs_o     : can_mac_pcs_tx_if_s2d_t;
    variable v_bs_fd_o   : can_mac_fsm_bs_tx_if_s2d_t;
    variable v_crc_o     : can_mac_fsm_crc_tx_if_s2d_t;
    variable v_fce_o     : can_mac_fce_if_s2d_t;

    -- Handles logic common to quiet states:
    -- entry-side interface reset/deassertion and SP-based idle-run counting.
    procedure process_quiet_phase_common is
    begin

      if (state_entry_v) then
        -- Deactivate transmit levels on entry to quiet states
        v_pcs_o             := mac_to_pcs_if_reset_c;
        v_fce_o             := mac_to_fce_if_reset_c;
        v_ssp_error_pending := false;

        -- Clear terminal transfer status when entering any quiet state.
        v_mac_ser_o.transfer_status := ongoing;

      elsif (sp_sample_strobe_v) then
        if (pcs_i.bus_polarity = recessive) then
          if (bit_count < bit_count_t'high) then
            v_bit_count := bit_count + 1;
          end if;
        else
          -- Dominant sample breaks run length
          v_bit_count := 0;
        end if;
      end if;

    end procedure process_quiet_phase_common;

    -- Initializes a new frame transmission on state entry:
    -- resets datapath helpers, seeds SOF, primes FIFO/CRC, and asserts TX control outputs.
    procedure initialize_frame_transmission is
    begin

      -- Initialize interfaces to clean state
      v_fce_o     := mac_to_fce_if_reset_c;
      v_pcs_o     := mac_to_pcs_if_reset_c;
      v_mac_ser_o := tx_mac_fsm_to_ser_if_reset_c;
      v_crc_o     := mac_fsm_to_crc_if_reset_c;

      -- Select CRC polynomial and signal start of new computation
      v_crc_o.crc_poly_select := mac_ser_i.frame_params.crc_poly_select;
      v_crc_o.start           := true;

      -- Activate transmit levels
      v_fce_o.transmitting := true;
      v_pcs_o.valid        := true;

      -- Frame initialization
      v_bit_count                 := 0;
      v_fifo                      := fifo_init;
      v_fifo_write_ptr            := 0;
      v_ack_success_seen          := false;
      v_bit_count_monitored       := false;
      v_ssp_error_pending         := false;
      v_ack_error_caused_flag     := false;
      v_dominant_seen_during_flag := false;
      v_dominant_run_count        := 0;

      v_bs_fd_o.start := true;

      -- Initialize first bit (SOF)
      v_tx_bit     := get_next_mac_frame_bit(
                                          bit_count         => 0,
                                          mac_ser_to_fsm    => mac_ser_i,
                                          previous_polarity => recessive,
                                          sbc               => (others => '0'),
                                          crc               => (others => '0')
                                        );
      v_pcs_o.data := v_tx_bit;

      -- Add SOF to FIFO
      v_fifo(0)                       := v_tx_bit;
      v_fifo_write_ptr                := 1;
      v_last_transmitted_bit_polarity := v_tx_bit.polarity;

      -- SOF is always fed to CRC
      v_crc_o.valid := true;
      v_crc_o.data  := polarity_to_std_logic(v_tx_bit.polarity);

    end procedure initialize_frame_transmission;

    -- Transmits an inserted dynamic stuff bit:
    -- writes FIFO history, drives PCS output, updates stuffer recursion and FD CRC feed.
    procedure transmit_stuff_bit is

      variable dynamic_stuff_eligible_v : boolean;
      variable crc_fd_stuff_eligible_v  : boolean;

    begin

      v_tx_bit := (polarity => bs_fd_i.data, bit_name => stuff_bit);

      -- FIFO write (TX history for PCS delay comparison)
      v_fifo(fifo_write_ptr) := v_tx_bit;
      if (fifo_write_ptr = transmitted_bits_fifo_depth_c - 1) then
        v_fifo_write_ptr := 0;
      else
        v_fifo_write_ptr := fifo_write_ptr + 1;
      end if;

      v_bit_count_monitored           := false;
      v_last_transmitted_bit_polarity := v_tx_bit.polarity;

      -- Send to PCS
      v_pcs_o.valid := true;
      v_pcs_o.data  := v_tx_bit;

      -- Feed bit stuffer (recursive loop)
      if (mac_ser_i.frame_params.is_fd_frame) then
        dynamic_stuff_eligible_v := bit_count < mac_ser_i.frame_params.sbc_start;
      else
        dynamic_stuff_eligible_v := bit_count < mac_ser_i.frame_params.crc_stop;
      end if;

      if (dynamic_stuff_eligible_v) then
        v_bs_fd_o.valid := true;
        v_bs_fd_o.data  := v_tx_bit.polarity;
      end if;

      -- ISO 11898-1: 10.6.3 - Stuff bits in FD frames are included in CRC
      crc_fd_stuff_eligible_v := mac_ser_i.frame_params.is_fd_frame and
                                 bit_count < mac_ser_i.frame_params.crc_start;
      if (crc_fd_stuff_eligible_v) then
        v_crc_o.valid := true;
        v_crc_o.data  := polarity_to_std_logic(v_tx_bit.polarity);
      end if;

    end procedure transmit_stuff_bit;

    -- Transmits the next non-stuff frame bit:
    -- computes bit(bit_count+1), updates FIFO/bit_count, and drives serializer/CRC/stuffer handshakes.
    procedure transmit_normal_bit is

      variable prepare_position_v   : bit_count_t;
      variable serializer_sourced_v : boolean;
      variable crc_cc_eligible_v    : boolean;

    begin

      prepare_position_v := bit_count + 1;

      -- Calculate NEXT position for registered output alignment
      v_tx_bit := get_next_mac_frame_bit(
                                         bit_count         => prepare_position_v,
                                         mac_ser_to_fsm    => mac_ser_i,
                                         previous_polarity => last_transmitted_bit_polarity,
                                         sbc               => bs_fd_i.sbc,
                                         crc               => crc_i.crc
                                       );

      -- FIFO write
      v_fifo(fifo_write_ptr) := v_tx_bit;
      if (fifo_write_ptr = transmitted_bits_fifo_depth_c - 1) then
        v_fifo_write_ptr := 0;
      else
        v_fifo_write_ptr := fifo_write_ptr + 1;
      end if;

      v_bit_count_monitored           := false;
      v_last_transmitted_bit_polarity := v_tx_bit.polarity;

      -- Send to PCS only if bit is valid (not beyond frame end)
      if (v_tx_bit.bit_name /= unknown) then
        v_pcs_o.valid := true;
        v_pcs_o.data  := v_tx_bit;
      end if;

      -- Increment logical bit counter on non-stuff bits
      if (v_tx_bit.bit_name /= stuff_bit) then
        v_bit_count := prepare_position_v;

        -- Request data from serializer for data-driven fields
        serializer_sourced_v := v_tx_bit.bit_name = base_id_bit or
                                v_tx_bit.bit_name = extended_id_bit or
                                v_tx_bit.bit_name = data_bit;
        if (serializer_sourced_v) then
          v_mac_ser_o.ready := true;
        end if;

        -- ISO 11898-1: 10.6.3 - Logical bits fed to CRC
        crc_cc_eligible_v := prepare_position_v < mac_ser_i.frame_params.crc_start and
                             v_tx_bit.bit_name /= fixed_stuff_bit;
        if (crc_cc_eligible_v) then
          v_crc_o.valid := true;
          v_crc_o.data  := polarity_to_std_logic(v_tx_bit.polarity);
        end if;
      end if;

      -- Feed bit stuffer (prepare_position_v: the bit being prepared is within dynamic stuff region)
      if (mac_ser_i.frame_params.is_fd_frame) then
        if (prepare_position_v < mac_ser_i.frame_params.sbc_start) then
          v_bs_fd_o.valid := true;
          v_bs_fd_o.data  := v_tx_bit.polarity;
        end if;
      else
        if (prepare_position_v < mac_ser_i.frame_params.crc_stop) then
          v_bs_fd_o.valid := true;
          v_bs_fd_o.data  := v_tx_bit.polarity;
        end if;
      end if;

    end procedure transmit_normal_bit;

    -- Monitors the observed bus bit and decides frame progression:
    -- handles SSP->SP deferred error reaction, arbitration/ACK/error events, and chooses normal vs stuff bit.
    procedure transmit_frame_bit is

      variable react_ssp_error_at_sp_v  : boolean;
      variable error_flag_bit_v         : mac_frame_bit_t;
      variable dynamic_stuff_eligible_v : boolean;

    begin

      if (mac_ser_i.frame_params.is_fd_frame) then
        dynamic_stuff_eligible_v := bit_count < mac_ser_i.frame_params.sbc_start;
      else
        dynamic_stuff_eligible_v := bit_count < mac_ser_i.frame_params.crc_stop;
      end if;

      react_ssp_error_at_sp_v := ssp_error_pending and (pcs_i.strobe_type = sp_strobe);
      if (fce_i.error_passive) then
        error_flag_bit_v := passive_error_flag_bit_c;
      else
        error_flag_bit_v := active_error_flag_bit_c;
      end if;

      if (react_ssp_error_at_sp_v) then
        -- ISO 11898-1: 6.6.21.3.1 (see Figure 30):
        -- react at SP to an error detected earlier at SSP.
        v_was_previous_frame_tx     := true;
        v_fce_o.error               := true;
        v_mac_ser_o.transfer_status := disturbed;
        v_monitored_bit_event       := bit_error;
        v_ssp_error_pending         := false;
        v_pcs_o.valid               := true;
        v_pcs_o.data                := error_flag_bit_v;
        return;
      end if;

      -- Monitor bus once per bit position (one-shot alignment)
      if (not bit_count_monitored) then
        v_monitored_bit_info := get_observed_mac_frame_bit_info(
                                                                fifo                   => fifo,
                                                                fifo_index             => pcs_i.fifo_index,
                                                                fifo_write_ptr         => fifo_write_ptr,
                                                                monitored_bit_polarity => pcs_i.bus_polarity,
                                                                frame_params           => mac_ser_i.frame_params
                                                              );
        if (pcs_i.strobe_type /= ssp_strobe) then
          v_mac_ser_o.transfer_status := v_monitored_bit_info.transfer_status;
          v_monitored_bit_event       := v_monitored_bit_info.event_type;
        end if;
        v_bit_count_monitored := true;
      end if;

      if (pcs_i.strobe_type = ssp_strobe) then
        -- ISO 11898-1: 6.6.21.3.1 (see Figure 30/Figure 31):
        -- detect bit error at SSP and defer reaction to following SP.
        v_ssp_error_pending := v_ssp_error_pending or (v_monitored_bit_info.event_type = bit_error);
        return;
      end if;

      case v_monitored_bit_info.event_type is
        when lost_arbitration =>
          v_was_previous_frame_tx     := false;
          v_mac_ser_o.transfer_status := lost_arbitration;

        when ack_detected =>
          v_was_previous_frame_tx := true;
          v_ack_success_seen      := true;
          transmit_normal_bit;

        when bit_error =>
          v_was_previous_frame_tx     := true;
          v_fce_o.error               := true;
          v_mac_ser_o.transfer_status := disturbed;
          v_pcs_o.valid               := true;
          v_pcs_o.data                := error_flag_bit_v;

        when ack_error =>
          v_was_previous_frame_tx     := true;
          v_fce_o.error               := true;
          v_mac_ser_o.transfer_status := disturbed;
          v_ack_error_caused_flag     := true;
          v_pcs_o.valid               := true;
          v_pcs_o.data                := error_flag_bit_v;

        when none =>
          if (bit_count = mac_ser_i.frame_params.ack_delimiter and (not ack_success_seen)) then
            v_mac_ser_o.transfer_status := disturbed;
            v_monitored_bit_event       := ack_error;
            v_was_previous_frame_tx     := true;
            v_ack_error_caused_flag     := true;
            ack_error_detected          <= true;
            v_pcs_o.valid               := true;
            v_pcs_o.data                := error_flag_bit_v;
          elsif (bs_fd_i.valid and dynamic_stuff_eligible_v) then
            transmit_stuff_bit;
          else
            transmit_normal_bit;
          end if;

      end case;

    end procedure transmit_frame_bit;

    -- Handles behavior shared by active/passive error-flag and overload-flag states:
    -- flag/delimiter serialization, delimiter-dominant run tracking, and reactive overload trigger.
    procedure process_flag_transmission (
      constant flag_bit_c                       : in mac_frame_bit_t;
      constant track_error_delimiter_too_late_c : in boolean
    ) is

      variable in_flag_field_v       : boolean;
      variable in_delimiter_field_v  : boolean;
      variable track_delimiter_run_v : boolean;

    begin

      v_fce_o.error               := true;
      v_mac_ser_o.transfer_status := disturbed;

      if (state_entry_v) then
        -- Activate transmit levels
        v_fce_o.transmitting       := true;
        v_fce_o.sending_error_flag := true;
        v_pcs_o.valid              := true;

        v_bit_count                 := 0;
        v_dominant_seen_during_flag := false;
        v_dominant_run_count        := 0;

        -- Initialize first bit of flag
        v_pcs_o.data := flag_bit_c;
      else
        in_flag_field_v      := (bit_count < error_flag_width_c);
        in_delimiter_field_v := not in_flag_field_v;

        -- Select flag or delimiter bit based on progress (ISO 11898-1: 6.6.5 / 6.6.6).
        if (in_flag_field_v) then
          v_tx_bit := flag_bit_c;
        else
          v_tx_bit := error_delimiter_bit_c;
        end if;

        v_pcs_o.data := v_tx_bit;

        if (sp_sample_strobe_v) then
          if (not error_sequence_complete_v) then
            v_bit_count := bit_count + 1;
          end if;

          -- ISO 11898-1: 8.1.3.3 Table 16 (Error_delimiter_too_late) and
          -- 8.1.4.2 rule f): applies to error-flag delimiter handling.
          track_delimiter_run_v := track_error_delimiter_too_late_c and in_delimiter_field_v;
          if (track_delimiter_run_v) then
            if (pcs_i.bus_polarity = recessive) then
              v_dominant_run_count := 0;
            elsif (dominant_run_count = delimiter_dominant_run_limit_c) then
              v_fce_o.error_delimiter_too_late := true;
              v_dominant_run_count             := 0;
            else
              v_dominant_run_count := dominant_run_count + 1;
            end if;
          end if;

          -- ISO 11898-1: 6.6.21.3.2 b) reactive OF:
          -- dominant at last bit of error/overload delimiter triggers OF.
          if (error_sequence_complete_v and pcs_i.bus_polarity = dominant) then
            v_overload_condition := true;
          end if;
        end if;
      end if;

    end procedure process_flag_transmission;

    -- Asserts FCE `primary_error` for dominant samples during the error-flag field at SP.
    procedure apply_primary_error_guard is

      variable primary_error_condition_v : boolean;

    begin

      primary_error_condition_v := sp_sample_strobe_v and
                                   bit_count < error_flag_width_c and
                                   pcs_i.bus_polarity = dominant;
      -- ISO 11898-1: 8.1.3.3 Table 16 - Primary_error:
      -- dominant detected while sending an error flag.
      if (primary_error_condition_v) then
        v_fce_o.primary_error := true;
      end if;

    end procedure apply_primary_error_guard;

    -- Applies ACK-error passive EF exception bookkeeping:
    -- tracks dominant seen in passive EF and raises counters_unchanged at sequence end when allowed.
    procedure apply_passive_ack_exception is

      variable passive_ack_exception_window_v : boolean;
      variable passive_ack_dominant_in_flag_v : boolean;
      variable passive_ack_no_dominant_end_v  : boolean;

    begin

      passive_ack_exception_window_v := sp_sample_strobe_v and ack_error_caused_flag;
      passive_ack_dominant_in_flag_v := passive_ack_exception_window_v and
                                        bit_count < error_flag_width_c and
                                        pcs_i.bus_polarity = dominant;
      passive_ack_no_dominant_end_v  := passive_ack_exception_window_v and
                                        error_sequence_complete_v and
                                        not dominant_seen_during_flag;

      -- ISO 11898-1: 8.1.4.2 rule c), Exception 1:
      -- passive transmitter ACK error without dominant seen in passive EF.
      if (passive_ack_dominant_in_flag_v) then
        v_dominant_seen_during_flag := true;
      end if;

      if (passive_ack_no_dominant_end_v) then
        v_fce_o.counters_unchanged := true;
      end if;

    end procedure apply_passive_ack_exception;

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        -- Reset ALL registered signals to initial values
        state                         <= bus_reintegration;
        prev_state                    <= bus_reintegration;
        bit_count                     <= 0;
        fifo                          <= fifo_init;
        fifo_write_ptr                <= 0;
        last_transmitted_bit_polarity <= recessive;
        monitored_bit_event           <= none;
        was_previous_frame_tx         <= false;
        ack_success_seen              <= false;
        bit_count_monitored           <= false;
        overload_condition            <= false;
        ssp_error_pending             <= false;
        ack_error_caused_flag         <= false;
        dominant_seen_during_flag     <= false;
        dominant_run_count            <= 0;
        ack_error_detected            <= false;
        form_error_detected           <= false;
        data_phase_exit_strobe        <= false;

        -- Reset port outputs using interface constants
        mac_ser_o <= tx_mac_fsm_to_ser_if_reset_c;
        pcs_o     <= mac_to_pcs_if_reset_c;
        bs_fd_o   <= mac_fsm_to_bs_fd_if_reset_c;
        crc_o     <= mac_fsm_to_crc_if_reset_c;
        fce_o     <= mac_to_fce_if_reset_c;
      else
        -- Debug signal defaults (pulses only when errors detected)
        ack_error_detected     <= false;
        form_error_detected    <= false;
        data_phase_exit_strobe <= false;

        -- Per-cycle defaults
        v_tx_bit             := reset_mac_frame_bit_c;
        v_monitored_bit_info := reset_observed_mac_frame_bit_info_c;

        -- Evaluate guards
        frame_transmitted_v          := bit_count = mac_ser_i.frame_params.eof_stop;
        sample_strobe_v              := pcs_i.sample_strobe = '1';
        sp_sample_strobe_v           := sample_strobe_v and pcs_i.strobe_type = sp_strobe;
        error_sequence_complete_v    := bit_count >= error_flag_width_c + error_delimiter_width_c - 1;
        state_entry_v                := prev_state /= state;
        bus_is_idle_v                := (bit_count = bus_idle_condition_width_c - 1);
        intermission_ended_v         := (bit_count = intermission_width_c - 1);
        must_suspend_transmission_v  := fce_i.error_passive and was_previous_frame_tx;
        suspend_transmission_ended_v := (bit_count = suspend_transmission_width_c - 1);
        error_detected_v             := (monitored_bit_event = bit_error or monitored_bit_event = ack_error);
        error_flag_ended_v           := bit_count = error_flag_width_c + error_delimiter_width_c - 1;

        ---------------------------------------------------------------------
        -- Defaults: hold current registered values
        ---------------------------------------------------------------------
        v_state                         := state;
        v_bit_count                     := bit_count;
        v_fifo                          := fifo;
        v_fifo_write_ptr                := fifo_write_ptr;
        v_last_transmitted_bit_polarity := last_transmitted_bit_polarity;
        v_was_previous_frame_tx         := was_previous_frame_tx;
        v_ack_success_seen              := ack_success_seen;
        v_bit_count_monitored           := bit_count_monitored;
        v_ssp_error_pending             := ssp_error_pending;
        v_ack_error_caused_flag         := ack_error_caused_flag;
        v_dominant_seen_during_flag     := dominant_seen_during_flag;
        v_dominant_run_count            := dominant_run_count;
        v_monitored_bit_event           := none;
        v_overload_condition            := false;

        v_mac_ser_o := mac_ser_o;
        v_pcs_o     := pcs_o;
        v_fce_o     := fce_o;
        v_crc_o     := crc_o;
        v_bs_fd_o   := mac_fsm_to_bs_fd_if_reset_c;

        -- Explicitly clear pulses in level-holding interfaces
        v_mac_ser_o.ready           := tx_mac_fsm_to_ser_if_reset_c.ready;
        v_crc_o.valid               := mac_fsm_to_crc_if_reset_c.valid;
        v_fce_o.error               := mac_to_fce_if_reset_c.error;
        v_fce_o.primary_error       := mac_to_fce_if_reset_c.primary_error;
        v_fce_o.counters_unchanged  := mac_to_fce_if_reset_c.counters_unchanged;
        v_fce_o.successful_transfer := mac_to_fce_if_reset_c.successful_transfer;

        ---------------------------------------------------------------------
        -- Unified state logic: output and next-state in one case statement
        ---------------------------------------------------------------------
        case state is
          when bus_reintegration =>
            process_quiet_phase_common;
            v_pcs_o.data := bus_integration_bit_c;
            if (bus_is_idle_v) then
              v_state := bus_idle;
            end if;

          when intermission =>
            process_quiet_phase_common;
            v_pcs_o.data := intermission_bit_c;
            -- ISO 11898-1: 10.4.4.3 condition b) - dominant detected during first
            -- two intermission bits triggers overload handling.
            if (sp_sample_strobe_v and pcs_i.bus_polarity = dominant and bit_count < 2) then
              v_overload_condition := true;
            end if;
            if (overload_condition) then
              v_state := transmitting_overload_flag;
            elsif (intermission_ended_v) then
              if (must_suspend_transmission_v) then
                v_state := suspend_transmission;
              else
                v_state := bus_idle;
              end if;
            end if;

          when suspend_transmission =>
            process_quiet_phase_common;
            v_pcs_o.data := suspend_transmission_bit_c;
            if (overload_condition) then
              v_state := transmitting_overload_flag;
            elsif (suspend_transmission_ended_v) then
              v_state := bus_idle;
            end if;

          when bus_idle =>
            process_quiet_phase_common;
            v_pcs_o.data := idle_bit_c;
            if (state_entry_v) then
              -- Reset all handshake signals once we reach bus_idle.
              v_mac_ser_o := tx_mac_fsm_to_ser_if_reset_c;
            end if;
            -- ISO 11898-1: 8.1.4.1 - bus_off nodes shall not initiate transmissions
            if (mac_ser_i.valid and sp_sample_strobe_v and not fce_i.bus_off) then
              v_state := transmitting_frame;
            end if;

          when transmitting_frame =>
            if (state_entry_v) then
              initialize_frame_transmission;
            elsif (frame_transmitted_v) then
              v_mac_ser_o.transfer_status := transmitted;
              v_was_previous_frame_tx     := true;
              v_fce_o.successful_transfer := true;
            elsif (sample_strobe_v) then
              transmit_frame_bit;
            end if;

            if (monitored_bit_event = lost_arbitration) then
              v_state := intermission;
            elsif (error_detected_v) then
              if (fce_i.error_passive) then
                v_state := transmitting_passive_error_flag;
              else
                v_state := transmitting_active_error_flag;
              end if;
            elsif (frame_transmitted_v) then
              v_state := intermission;
            end if;

          when transmitting_active_error_flag =>
            process_flag_transmission(active_error_flag_bit_c, true);
            apply_primary_error_guard;
            if (overload_condition) then
              v_state := transmitting_overload_flag;
            elsif (error_flag_ended_v) then
              v_state := intermission;
            end if;

          when transmitting_passive_error_flag =>
            process_flag_transmission(passive_error_flag_bit_c, true);
            apply_primary_error_guard;
            apply_passive_ack_exception;
            if (overload_condition) then
              v_state := transmitting_overload_flag;
            elsif (error_flag_ended_v) then
              v_state := intermission;
            end if;

          when transmitting_overload_flag =>
            process_flag_transmission(overload_flag_bit_c, false);
            if (overload_condition) then
              v_state := transmitting_overload_flag;
            elsif (error_flag_ended_v) then
              v_state := intermission;
            end if;

        end case;

        -- Register all next-cycle values
        state      <= v_state;
        prev_state <= state;

        -- Reset bit_count on first cycle of a new state
        if (state /= v_state) then
          bit_count <= 0;
        else
          bit_count <= v_bit_count;
        end if;

        fifo                          <= v_fifo;
        fifo_write_ptr                <= v_fifo_write_ptr;
        last_transmitted_bit_polarity <= v_last_transmitted_bit_polarity;
        monitored_bit_event           <= v_monitored_bit_event;
        was_previous_frame_tx         <= v_was_previous_frame_tx;
        ack_success_seen              <= v_ack_success_seen;
        bit_count_monitored           <= v_bit_count_monitored;
        overload_condition            <= v_overload_condition;
        ssp_error_pending             <= v_ssp_error_pending;
        ack_error_caused_flag         <= v_ack_error_caused_flag;
        dominant_seen_during_flag     <= v_dominant_seen_during_flag;
        dominant_run_count            <= v_dominant_run_count;

        mac_ser_o <= v_mac_ser_o;
        pcs_o     <= v_pcs_o;
        bs_fd_o   <= v_bs_fd_o;
        crc_o     <= v_crc_o;
        fce_o     <= v_fce_o;
      end if;
    end if;

  end process fsm_sequential;

  -- Wire debug signals to ports
  debug_ack_error_o  <= ack_error_detected;
  debug_form_error_o <= form_error_detected;
  debug_data_exit_o  <= data_phase_exit_strobe;
  debug_fsm_state_o  <= state;

end architecture rtl;
