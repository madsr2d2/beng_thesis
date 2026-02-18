--------------------------------------------------------------------------------
-- Title      : CAN MAC Transmitter FSM
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : tx_mac_fsm.vhd
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

entity tx_mac_fsm is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- Serializer interface
    mac_ser_i : in    tx_mac_ser_to_fsm_if_t;
    mac_ser_o : out   tx_mac_fsm_to_ser_if_t;

    -- PCS interface
    pcs_i : in    pcs_to_mac_if_t;
    pcs_o : out   mac_to_pcs_if_t;

    -- Bit stuffer FD interface
    bs_fd_i : in    bs_fd_to_mac_fsm_if_t;
    bs_fd_o : out   mac_fsm_to_bs_fd_if_t;

    -- CRC interface
    crc_i : in    crc_to_mac_fsm_if_t;
    crc_o : out   mac_fsm_to_crc_if_t;

    -- Fault Confinement Entity interface (ISO 11898-1 Table 16/17)
    fce_i : in    fce_to_mac_if_t;
    fce_o : out   mac_to_fce_if_t
  );
end entity tx_mac_fsm;

architecture rtl of tx_mac_fsm is

  ---------------------------------------------------------------------------
  -- Registered state signals (driven by state_update)
  ---------------------------------------------------------------------------
  signal state                         : tx_mac_fsm_state_t;
  signal prev_state                    : tx_mac_fsm_state_t;
  signal bit_count                     : bit_count_t;
  signal fifo                          : transmitted_bits_fifo_t;
  signal fifo_write_ptr                : fifo_write_ptr_t;
  signal last_transmitted_bit_polarity : polarity_t;
  signal monitored_bit_event           : tx_mac_monitor_event_t;
  signal was_previous_frame_tx         : boolean;
  signal ack_success_seen              : boolean;
  signal bit_count_monitored           : boolean;
  signal overload_condition            : boolean;

  -- Fault confinement tracking
  signal ack_error_caused_flag     : boolean;
  signal dominant_seen_during_flag : boolean;
  signal dominant_run_count        : integer range 0 to 15;

  -- Overload chain safety limit (ISO 11898-1: 10.4.4.3)
  signal overload_chain_count : integer range 0 to 7;

  ---------------------------------------------------------------------------
  -- Combinational next-cycle signals (driven by output_logic / next_state_logic)
  ---------------------------------------------------------------------------
  signal next_state                         : tx_mac_fsm_state_t;
  signal next_bit_count                     : bit_count_t;
  signal next_fifo                          : transmitted_bits_fifo_t;
  signal next_fifo_write_ptr                : fifo_write_ptr_t;
  signal next_last_transmitted_bit_polarity : polarity_t;
  signal next_monitored_bit_event           : tx_mac_monitor_event_t;
  signal next_was_previous_frame_tx         : boolean;
  signal next_ack_success_seen              : boolean;
  signal next_bit_count_monitored           : boolean;
  signal next_overload_condition            : boolean;
  signal next_ack_error_caused_flag         : boolean;
  signal next_dominant_seen_during_flag     : boolean;
  signal next_dominant_run_count            : integer range 0 to 15;
  signal next_overload_chain_count          : integer range 0 to 7;

  -- Intermediate signals for registered outputs
  signal next_mac_ser_o : tx_mac_fsm_to_ser_if_t;
  signal next_pcs_o     : mac_to_pcs_if_t;
  signal next_bs_fd_o   : mac_fsm_to_bs_fd_if_t;
  signal next_crc_o     : mac_fsm_to_crc_if_t;
  signal next_fce_o     : mac_to_fce_if_t;

begin

  ---------------------------------------------------------------------------
  -- Process 1: next_state_logic (combinational)
  ---------------------------------------------------------------------------
  next_state_logic : process (all) is

    -- Named guard variables (RTL guide Rule 3)
    variable bus_is_idle_v                : boolean;
    variable intermission_ended_v         : boolean;
    variable must_suspend_transmission_v  : boolean;
    variable suspend_transmission_ended_v : boolean;
    variable error_detected_v             : boolean;
    variable frame_transmitted_v          : boolean;
    variable error_flag_ended_v           : boolean;

  begin

    -- Evaluate guards
    bus_is_idle_v        := (bit_count = bus_idle_condition_width_c - 1);
    intermission_ended_v := (bit_count = intermission_width_c - 1);
    -- ISO 11898-1: 10.4.4.4 - Error-passive node must wait for suspend transmission field
    must_suspend_transmission_v  := fce_i.error_passive and was_previous_frame_tx;
    suspend_transmission_ended_v := (bit_count = suspend_transmission_width_c - 1);
    error_detected_v             := (monitored_bit_event = bit_error or monitored_bit_event = ack_error);
    frame_transmitted_v          := bit_count = mac_ser_i.frame_params.eof_stop;
    error_flag_ended_v           := bit_count = error_flag_width_c + error_delimiter_width_c - 1;

    -- Default: hold current state
    next_state <= state;

    if (rst_i = '1') then
      next_state <= bus_reintegration;
    else
      case state is
        when bus_reintegration =>
          -- ISO 11898-1: 12.1.4.4 - Integration complete after 128 occurrences of 11 recessive bits
          if (bus_is_idle_v) then
            next_state <= bus_idle;
          end if;

        when intermission =>
          -- ISO 11898-1: 10.4.4.2 - Inter-frame spacing
          if (overload_condition) then
            next_state <= transmitting_overload_flag;
          elsif (intermission_ended_v) then
            if (must_suspend_transmission_v) then
              next_state <= suspend_transmission;
            else
              next_state <= bus_idle;
            end if;
          end if;

        when suspend_transmission =>
          -- ISO 11898-1: 10.4.4.4 - Additional delay for error-passive transmitters
          if (overload_condition) then
            -- Guard overload transitions with chain counter to prevent bus lockup
            if (overload_chain_count < 7) then
              next_state <= transmitting_overload_flag;
            end if;
          elsif (suspend_transmission_ended_v) then
            next_state <= bus_idle;
          end if;

        when bus_idle =>
          if (mac_ser_i.valid) then
            next_state <= transmitting_frame;
          end if;

        when transmitting_frame =>
          -- ISO 11898-1: 10.5 - Arbitration and data phase
          if (monitored_bit_event = lost_arbitration) then
            next_state <= intermission;
          elsif (error_detected_v) then
            next_state <= transmitting_error_flag;
          elsif (frame_transmitted_v) then
            next_state <= intermission;
          end if;

        when transmitting_error_flag | transmitting_overload_flag =>
          -- ISO 11898-1: 10.4.4.1 / 10.4.4.3 - Error and Overload frames
          if (overload_condition) then
            if (overload_chain_count < 7) then
              next_state <= transmitting_overload_flag;
            end if;
          elsif (error_flag_ended_v) then
            next_state <= intermission;
          end if;

        when others =>
          null;
      end case;
    end if;

  end process next_state_logic;

  ---------------------------------------------------------------------------
  -- Process 2: output_logic (combinational Mealy)
  ---------------------------------------------------------------------------
  output_logic : process (all) is

    -- Temporary variable for next-cycle bit calculation
    variable next_bit_v           : mac_frame_bit_t;
    variable monitored_bit_info_v : observed_mac_frame_bit_info_t;

    -- Named guard variables (RTL guide Rule 3)
    variable frame_transmitted_v       : boolean;
    variable sample_strobe_v           : boolean;
    variable error_sequence_complete_v : boolean;
    variable state_entry_v             : boolean;
    -- ISO 11898-1: 10.4.4.3 condition b) - reactive overload
    variable intermission_overload_v : boolean;
    variable delimiter_overload_v    : boolean;
    -- Format-dependent dynamic stuff eligibility (ISO 11898-1: 10.6.2)
    variable dynamic_stuff_eligible_v : boolean;
    -- FD-specific CRC bit stuffing (ISO 11898-1: 10.6.3)
    variable crc_fd_stuff_eligible_v : boolean;
    variable serializer_sourced_v    : boolean;
    variable crc_cc_eligible_v       : boolean;

    -------------------------------------------------------------------------
    -- Local procedures for state logic abstraction
    -------------------------------------------------------------------------

    -- Handle quiet phases: reintegration, intermission, suspend, idle
    procedure process_quiet_phases is
    begin

      if (state_entry_v) then
        next_bit_count <= 0;

        -- Deactivate transmit levels on entry to quiet states
        next_pcs_o <= mac_to_pcs_if_reset_c;
        next_fce_o <= mac_to_fce_if_reset_c;

        -- Reset transfer_status once we reach bus_idle (ready for next frame)
        if (state = bus_idle) then
          next_mac_ser_o <= tx_mac_fsm_to_ser_if_reset_c;
        end if;
      elsif (sample_strobe_v) then
        if (pcs_i.bus_polarity = recessive) then
          next_bit_count <= bit_count + 1;
        else
          -- Dominant sample breaks run length (e.g. during integration)
          next_bit_count <= 0;
        end if;

        if (intermission_overload_v) then
          next_overload_condition <= true;
        end if;
      end if;

      -- Assign semantic constant per state for waveform debugging.
      -- This override ensures the bit_name is correct for debugging even
      -- during the cycle where the reset constant was applied.
      case state is
        when intermission => next_pcs_o.data <= intermission_bit_c;
        when suspend_transmission => next_pcs_o.data <= suspend_transmission_bit_c;
        when bus_idle => next_pcs_o.data <= idle_bit_c;
        when others => next_pcs_o.data <= reset_mac_frame_bit_c;
      end case;

      -- Reset overload chain counter when reaching bus_idle (new frame opportunity)
      if (state = bus_idle) then
        next_overload_chain_count <= 0;
      end if;

    end procedure process_quiet_phases;

    -- Initialize frame transmission (state entry logic)
    procedure initialize_frame_transmission is
    begin

      -- Initialize interfaces to clean state
      next_fce_o     <= mac_to_fce_if_reset_c;
      next_pcs_o     <= mac_to_pcs_if_reset_c;
      next_mac_ser_o <= tx_mac_fsm_to_ser_if_reset_c;
      next_crc_o     <= mac_fsm_to_crc_if_reset_c;

      -- Select CRC polynomial
      next_crc_o.crc_poly_select <= mac_ser_i.frame_params.crc_poly_select;

      -- Activate transmit levels
      next_fce_o.transmitting <= true;
      next_pcs_o.valid        <= true;

      -- Frame initialization
      next_bit_count                 <= 0;
      next_fifo                      <= fifo_init;
      next_fifo_write_ptr            <= 0;
      next_ack_success_seen          <= false;
      next_bit_count_monitored       <= false;
      next_ack_error_caused_flag     <= false;
      next_dominant_seen_during_flag <= false;
      next_dominant_run_count        <= 0;

      next_bs_fd_o.start <= true;

      -- Initialize first bit (SOF)
      next_bit_v      := get_next_mac_frame_bit(
                                             bit_count         => 0,
                                             mac_ser_to_fsm    => mac_ser_i,
                                             previous_polarity => recessive,
                                             sbc               => (others => '0'),
                                             crc               => (others => '0')
                                           );
      next_pcs_o.data <= next_bit_v;

      -- Add SOF to FIFO
      next_fifo(0)                       <= next_bit_v;
      next_fifo_write_ptr                <= 1;
      next_last_transmitted_bit_polarity <= next_bit_v.polarity;

      -- SOF is always fed to CRC
      next_crc_o.valid <= true;
      next_crc_o.data  <= polarity_to_std_logic(next_bit_v.polarity);

    end procedure initialize_frame_transmission;

    -- Handle insertion of a dynamic stuff bit
    procedure transmit_stuff_bit is
    begin

      next_bit_v := (polarity => bs_fd_i.data, bit_name => stuff_bit);

      -- FIFO write (TX history for PCS delay comparison)
      next_fifo(fifo_write_ptr) <= next_bit_v;
      if (fifo_write_ptr = transmitted_bits_fifo_depth_c - 1) then
        next_fifo_write_ptr <= 0;
      else
        next_fifo_write_ptr <= fifo_write_ptr + 1;
      end if;

      next_bit_count_monitored           <= false;
      next_last_transmitted_bit_polarity <= next_bit_v.polarity;

      -- Send to PCS
      next_pcs_o.valid <= true;
      next_pcs_o.data  <= next_bit_v;

      -- Feed bit stuffer (recursive loop)
      if (dynamic_stuff_eligible_v) then
        next_bs_fd_o.valid <= true;
        next_bs_fd_o.data  <= next_bit_v.polarity;
      end if;

      -- ISO 11898-1: 10.6.3 - Stuff bits in FD frames are included in CRC
      crc_fd_stuff_eligible_v := mac_ser_i.frame_params.is_fd_frame and
                                 bit_count < mac_ser_i.frame_params.crc_start;
      if (crc_fd_stuff_eligible_v) then
        next_crc_o.valid <= true;
        next_crc_o.data  <= polarity_to_std_logic(next_bit_v.polarity);
      end if;

    end procedure transmit_stuff_bit;

    -- Pre-computes the bit at (bit_count + 1) for registered output alignment.
    -- After registration in state_update, pcs_o.data holds the correct bit for
    -- the upcoming bit time. All position checks within this procedure use
    -- prepare_position_v (= bit_count + 1), NOT bit_count.
    --
    -- Contrast with transmit_stuff_bit and transmit_frame_bit which operate
    -- at the current bit_count (the position on the wire being monitored).
    procedure transmit_normal_bit is

      variable prepare_position_v : bit_count_t;

    begin

      prepare_position_v := bit_count + 1;

      -- Calculate NEXT position for registered output alignment
      next_bit_v := get_next_mac_frame_bit(
                                           bit_count         => prepare_position_v,
                                           mac_ser_to_fsm    => mac_ser_i,
                                           previous_polarity => last_transmitted_bit_polarity,
                                           sbc               => bs_fd_i.sbc,
                                           crc               => crc_i.crc
                                         );

      -- FIFO write
      next_fifo(fifo_write_ptr) <= next_bit_v;
      if (fifo_write_ptr = transmitted_bits_fifo_depth_c - 1) then
        next_fifo_write_ptr <= 0;
      else
        next_fifo_write_ptr <= fifo_write_ptr + 1;
      end if;

      next_bit_count_monitored           <= false;
      next_last_transmitted_bit_polarity <= next_bit_v.polarity;

      -- Send to PCS
      next_pcs_o.valid <= true;
      next_pcs_o.data  <= next_bit_v;

      -- Increment logical bit counter on non-stuff bits
      if (next_bit_v.bit_name /= stuff_bit) then
        next_bit_count <= prepare_position_v;

        -- Request data from serializer for data-driven fields
        serializer_sourced_v := next_bit_v.bit_name = base_id_bit or
                                next_bit_v.bit_name = extended_id_bit or
                                next_bit_v.bit_name = data_bit;
        if (serializer_sourced_v) then
          next_mac_ser_o.ready <= true;
        end if;

        -- ISO 11898-1: 10.6.3 - Logical bits fed to CRC
        crc_cc_eligible_v := prepare_position_v < mac_ser_i.frame_params.crc_start and
                             next_bit_v.bit_name /= fixed_stuff_bit;
        if (crc_cc_eligible_v) then
          next_crc_o.valid <= true;
          next_crc_o.data  <= polarity_to_std_logic(next_bit_v.polarity);
        end if;
      end if;

      -- Feed bit stuffer (prepare_position_v: the bit being prepared is within the dynamic stuff region)
      if (mac_ser_i.frame_params.is_fd_frame) then
        if (prepare_position_v < mac_ser_i.frame_params.sbc_start) then
          next_bs_fd_o.valid <= true;
          next_bs_fd_o.data  <= next_bit_v.polarity;
        end if;
      else
        if (prepare_position_v < mac_ser_i.frame_params.crc_stop) then
          next_bs_fd_o.valid <= true;
          next_bs_fd_o.data  <= next_bit_v.polarity;
        end if;
      end if;

    end procedure transmit_normal_bit;

    -- Handle bit transmission and monitoring (sample strobe logic)
    procedure transmit_frame_bit is
    begin

      -- Monitor bus once per bit position (one-shot alignment)
      if (not bit_count_monitored) then
        monitored_bit_info_v           := get_observed_mac_frame_bit_info(
                                                                          fifo       => fifo,
                                                                          fifo_index => pcs_i.fifo_index,
                                                                          fifo_write_ptr     => fifo_write_ptr,
                                                                          monitored_bit_polarity => pcs_i.bus_polarity,
                                                                          frame_params           => mac_ser_i.frame_params
                                                                        );
        next_mac_ser_o.transfer_status <= monitored_bit_info_v.transfer_status;
        next_monitored_bit_event       <= monitored_bit_info_v.event_type;
        next_bit_count_monitored       <= true;
      else
        monitored_bit_info_v.event_type := none;
      end if;

      -- React to monitored event (ISO 11898-1: 10.5 / 12.1.4)
      case monitored_bit_info_v.event_type is
        when lost_arbitration =>
          next_was_previous_frame_tx <= false;

        when ack_detected =>
          next_was_previous_frame_tx <= true;
          next_ack_success_seen      <= true;
          -- Fix: ensure bit counter advances to the next field (delimiter)
          transmit_normal_bit;

        when bit_error =>
          next_was_previous_frame_tx     <= true;
          next_fce_o.error               <= true;
          next_mac_ser_o.transfer_status <= disturbed;

        when none =>
          -- ISO 11898-1: 12.1.4.3 - ACK error reported at ACK delimiter boundary.
          -- We monitor the slot; if no dominant bit was seen by the time we reach
          -- the delimiter index, we signal the error.
          if (bit_count = mac_ser_i.frame_params.ack_delimiter and (not ack_success_seen)) then
            next_mac_ser_o.transfer_status <= disturbed;
            next_monitored_bit_event       <= ack_error;
            next_was_previous_frame_tx     <= true;
            next_ack_error_caused_flag     <= true;

          -- Dynamic stuff bit check (ISO 11898-1: 10.6.2)
          elsif (bs_fd_i.valid and dynamic_stuff_eligible_v) then
            transmit_stuff_bit;

          else
            transmit_normal_bit;
          end if;

        when others =>
          null;
      end case;

    end procedure transmit_frame_bit;

    -- Handle error and overload flag transmission
    procedure process_error_flag_transmission is
    begin

      -- Indicate error state active
      next_fce_o.error               <= true;
      next_mac_ser_o.transfer_status <= disturbed;

      if (state_entry_v) then
        -- Activate transmit levels
        next_fce_o.transmitting       <= true;
        next_fce_o.sending_error_flag <= true;
        next_pcs_o.valid              <= true;

        next_bit_count                 <= 0;
        next_overload_chain_count      <= overload_chain_count + 1;
        next_dominant_seen_during_flag <= false;
        next_dominant_run_count        <= 0;

        -- Initialize first bit of flag
        if (state = transmitting_overload_flag) then
          next_pcs_o.data <= overload_flag_bit_c;
        elsif (fce_i.error_passive) then
          next_pcs_o.data <= passive_error_flag_bit_c;
        else
          next_pcs_o.data <= active_error_flag_bit_c;
        end if;

      else
        -- Select flag or delimiter bit based on progress (ISO 11898-1: 10.4.4.1)
        if (bit_count < error_flag_width_c) then
          if (state = transmitting_overload_flag) then
            next_bit_v := overload_flag_bit_c;
          elsif (fce_i.error_passive) then
            next_bit_v := passive_error_flag_bit_c;
          else
            next_bit_v := active_error_flag_bit_c;
          end if;
        else
          next_bit_v := error_delimiter_bit_c;
        end if;

        next_pcs_o.data <= next_bit_v;

        if (sample_strobe_v) then
          if (not error_sequence_complete_v) then
            next_bit_count <= bit_count + 1;

            -- ISO 11898-1: 8.1.3.3 Table 16 - Primary error: dominant detected during error flag
            if (bit_count < error_flag_width_c and pcs_i.bus_polarity = dominant) then
              next_fce_o.primary_error <= true;
            end if;

            -- Dominant tracking for error-passive transmitter exception rules
            if (fce_i.error_passive and pcs_i.bus_polarity = dominant) then
              next_dominant_seen_during_flag <= true;
            end if;
          end if;

          -- ISO 11898-1: 12.1.4.3 - Error delimiter too late (8+ dominant bits)
          if (bit_count >= error_flag_width_c) then
            if (pcs_i.bus_polarity = dominant) then
              if (dominant_run_count = 7) then -- TODO: Add a constant for this
                next_fce_o.error_delimiter_too_late <= true;
                next_dominant_run_count             <= 0;
              else
                next_dominant_run_count <= dominant_run_count + 1;
              end if;
            else
              next_dominant_run_count <= 0;
            end if;
          end if;

          -- ISO 11898-1: 12.1.4.3 Exception 1 - counters unchanged for passive ACK error
          if (error_sequence_complete_v) then
            if (fce_i.error_passive and ack_error_caused_flag and not dominant_seen_during_flag) then
              next_fce_o.counters_unchanged <= true;
            end if;
          end if;

          if (delimiter_overload_v) then
            next_overload_condition <= true;
          end if;
        end if;

      end if;

    end procedure process_error_flag_transmission;

  begin

    -- Per-cycle defaults
    next_bit_v           := reset_mac_frame_bit_c;
    monitored_bit_info_v := reset_observed_mac_frame_bit_info_c;

    -- Evaluate guards
    frame_transmitted_v       := bit_count = mac_ser_i.frame_params.eof_stop;
    sample_strobe_v           := pcs_i.sample_strobe = '1';
    error_sequence_complete_v := bit_count >= error_flag_width_c + error_delimiter_width_c - 1;
    state_entry_v             := prev_state /= state;

    -- ISO 11898-1: 10.4.4.3 condition b) - reactive overload
    intermission_overload_v := sample_strobe_v and state = intermission
                               and bit_count < 2 and pcs_i.bus_polarity = dominant;
    -- ISO 11898-1: 10.4.4.3 condition b) - dominant at last bit of error/overload delimiter
    delimiter_overload_v := sample_strobe_v and error_sequence_complete_v
                            and pcs_i.bus_polarity = dominant;

    -- Dynamic stuff bits apply to different regions for CC vs FD
    if (mac_ser_i.frame_params.is_fd_frame) then
      dynamic_stuff_eligible_v := bit_count < mac_ser_i.frame_params.sbc_start;
    else
      dynamic_stuff_eligible_v := bit_count < mac_ser_i.frame_params.crc_stop;
    end if;

    -----------------------------------------------------------------------
    -- Port output next-state defaults
    -----------------------------------------------------------------------
    -- Interfaces with levels: hold current registered values
    next_mac_ser_o <= mac_ser_o;
    next_pcs_o     <= pcs_o;
    next_fce_o     <= fce_o;
    next_crc_o     <= crc_o;

    -- Interfaces primarily pulse-driven: start from reset state
    next_bs_fd_o <= mac_fsm_to_bs_fd_if_reset_c;

    -- Explicitly clear pulses in level-holding interfaces
    next_mac_ser_o.ready <= tx_mac_fsm_to_ser_if_reset_c.ready;
    next_crc_o.valid     <= mac_fsm_to_crc_if_reset_c.valid;

    next_fce_o.error               <= mac_to_fce_if_reset_c.error;
    next_fce_o.primary_error       <= mac_to_fce_if_reset_c.primary_error;
    next_fce_o.counters_unchanged  <= mac_to_fce_if_reset_c.counters_unchanged;
    next_fce_o.successful_transfer <= mac_to_fce_if_reset_c.successful_transfer;

    -----------------------------------------------------------------------
    -- next_* signal defaults: hold current registered value
    -----------------------------------------------------------------------
    next_bit_count                     <= bit_count;
    next_fifo                          <= fifo;
    next_fifo_write_ptr                <= fifo_write_ptr;
    next_last_transmitted_bit_polarity <= last_transmitted_bit_polarity;
    next_was_previous_frame_tx         <= was_previous_frame_tx;
    next_ack_success_seen              <= ack_success_seen;
    next_bit_count_monitored           <= bit_count_monitored;
    next_ack_error_caused_flag         <= ack_error_caused_flag;
    next_dominant_seen_during_flag     <= dominant_seen_during_flag;
    next_dominant_run_count            <= dominant_run_count;
    next_overload_chain_count          <= overload_chain_count;

    -- Single-cycle pulse behavior: clear each cycle, only set when condition detected
    next_monitored_bit_event <= none;
    next_overload_condition  <= false;

    -----------------------------------------------------------------------
    -- State dispatch
    -----------------------------------------------------------------------
    case state is

      when bus_reintegration | intermission | suspend_transmission | bus_idle =>
        process_quiet_phases;

      when transmitting_frame =>
        if (state_entry_v) then
          initialize_frame_transmission;
        elsif (frame_transmitted_v) then
          next_mac_ser_o.transfer_status <= transmitted;
          next_was_previous_frame_tx     <= true;
          next_fce_o.successful_transfer <= true;
        elsif (sample_strobe_v) then
          transmit_frame_bit;
        end if;

      when transmitting_error_flag | transmitting_overload_flag =>
        process_error_flag_transmission;

      when others =>
        null;

    end case;

  end process output_logic;

  ---------------------------------------------------------------------------
  -- Process 3: state_update (clocked)
  ---------------------------------------------------------------------------
  state_update : process (clk_i) is
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
        ack_error_caused_flag         <= false;
        dominant_seen_during_flag     <= false;
        dominant_run_count            <= 0;
        overload_chain_count          <= 0;

        -- Reset port outputs using interface constants
        mac_ser_o <= tx_mac_fsm_to_ser_if_reset_c;
        pcs_o     <= mac_to_pcs_if_reset_c;
        bs_fd_o   <= mac_fsm_to_bs_fd_if_reset_c;
        crc_o     <= mac_fsm_to_crc_if_reset_c;
        fce_o     <= mac_to_fce_if_reset_c;
      else
        -- Register all next-cycle values
        state                         <= next_state;
        prev_state                    <= state;
        bit_count                     <= next_bit_count;
        fifo                          <= next_fifo;
        fifo_write_ptr                <= next_fifo_write_ptr;
        last_transmitted_bit_polarity <= next_last_transmitted_bit_polarity;
        monitored_bit_event           <= next_monitored_bit_event;
        was_previous_frame_tx         <= next_was_previous_frame_tx;
        ack_success_seen              <= next_ack_success_seen;
        bit_count_monitored           <= next_bit_count_monitored;
        overload_condition            <= next_overload_condition;
        ack_error_caused_flag         <= next_ack_error_caused_flag;
        dominant_seen_during_flag     <= next_dominant_seen_during_flag;
        dominant_run_count            <= next_dominant_run_count;
        overload_chain_count          <= next_overload_chain_count;

        -- Register port outputs
        mac_ser_o <= next_mac_ser_o;
        pcs_o     <= next_pcs_o;
        bs_fd_o   <= next_bs_fd_o;
        crc_o     <= next_crc_o;
        fce_o     <= next_fce_o;
      end if;
    end if;

  end process state_update;

end architecture rtl;
