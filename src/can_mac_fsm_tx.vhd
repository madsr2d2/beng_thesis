--------------------------------------------------------------------------------
-- Title      : CAN MAC Transmitter FSM
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_mac_fsm_tx.vhd
-- Author     : Mads Richardt
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
  use work.pk_can_types.all;
  use work.can_protocol_pkg.all;

entity can_mac_fsm_tx is
  port (
    clk_i : in    std_logic;
    rst_i : in    std_logic;

    -- Serializer interface
    mac_ser_i : in    t_can_mac_ser_fsm_tx_if_s2m;
    mac_ser_o : out   t_can_mac_ser_fsm_tx_if_m2s;

    -- PCS interface
    pcs_i : in    t_can_mac_pcs_tx_if_s2m;
    pcs_o : out   t_can_mac_pcs_tx_if_m2s;

    -- Bit stuffer FD interface
    bs_fd_i : in    t_can_mac_fsm_bs_tx_if_s2m;
    bs_fd_o : out   t_can_mac_fsm_bs_tx_if_m2s;

    -- CRC interface
    crc_i : in    t_can_mac_fsm_crc_tx_if_s2m;
    crc_o : out   t_can_mac_fsm_crc_tx_if_m2s;

    -- Fault Confinement Entity interface (ISO 11898-1 Table 16/17)
    fce_i : in    t_can_mac_fce_if_s2m;
    fce_o : out   t_can_mac_fce_if_m2s;

    -- Debug ports (test visibility)
    debug_ack_error_o  : out   std_logic;
    debug_form_error_o : out   std_logic;
    debug_data_exit_o  : out   std_logic;
    debug_fsm_state_o  : out   std_logic_vector(2 downto 0);
    debug_bit_name_o   : out   t_mac_frame_bit_name
  );
end entity can_mac_fsm_tx;

architecture rtl of can_mac_fsm_tx is

  ---------------------------------------------------------------------------
  -- FSM state type (enum for readability; debug port converts to slv)
  ---------------------------------------------------------------------------
  type t_fsm_state is (
    s_bus_reintegration,
    s_intermission,
    s_suspend_transmission,
    s_bus_idle,
    s_transmitting_frame,
    s_active_error_flag,
    s_passive_error_flag,
    s_overload_flag
  );

  function to_slv (
    constant st : t_fsm_state
  ) return std_logic_vector is
  begin

    return std_logic_vector(to_unsigned(t_fsm_state'pos(st), 3));

  end function to_slv;

  -- Threshold used for delimiter-dominant run tracking before raising
  -- Error_delimiter_too_late (ISO 11898-1: 8.1.3.3 Table 16).
  constant c_delimiter_dominant_run_limit : integer := 7;

  -- ISO 11898-1: 8.2 (T5) - bus-off recovery requires 128 idle conditions.
  constant c_bus_off_recovery_count : integer := 128;

  ---------------------------------------------------------------------------
  -- Registered state signals
  ---------------------------------------------------------------------------
  signal state                         : t_fsm_state;
  signal prev_state                    : t_fsm_state;
  signal bit_count                     : t_bit_count;
  signal fifo                          : t_transmitted_bits_fifo;
  signal fifo_write_ptr                : t_fifo_write_ptr;
  signal last_transmitted_bit_polarity : std_logic;
  signal monitored_bit_event           : t_tx_mac_monitor_event;
  signal was_previous_frame_tx         : boolean;
  signal ack_success_seen              : boolean;
  signal bit_count_monitored           : boolean;
  signal overload_condition            : boolean;
  signal ssp_error_pending             : boolean;
  signal in_data_phase                 : std_logic;

  -- Fault confinement tracking
  signal ack_error_caused_flag     : boolean;
  signal dominant_seen_during_flag : boolean;
  signal dominant_run_count        : integer range 0 to 15;

  -- Bus-off recovery: counts idle conditions (11 recessive bits) during reintegration
  signal idle_condition_count : integer range 0 to c_bus_off_recovery_count;

  -- ISO 11898-1: 6.6.8 - dominant at 3rd intermission bit detected as SOF;
  -- skip SOF output and start with first ID bit on next frame entry.
  signal skip_sof : boolean;

  -- Cached frame parameters (calculated once per frame from LLC metadata)
  signal frame_params : t_frame_params;

  -- Derived frame positions (combinational from frame_params)
  signal sbc_start          : t_position;
  signal crc_start          : t_position;
  signal ack_delimiter      : t_position;
  signal eof_stop           : t_position;
  signal dynamic_stuff_stop : t_position;

  -- Debug signals for test visibility
  signal ack_error_detected : std_logic;
  signal current_bit_name   : t_mac_frame_bit_name;

begin

  -- Derived frame positions (combinational from frame_params)
  sbc_start     <= frame_params.data_stop + 1 when frame_params.is_fd_frame = '1' else
                   0;
  crc_start     <= sbc_start + c_sbc_field_width when frame_params.is_fd_frame = '1' else
                   frame_params.data_stop + 1;
  ack_delimiter <= frame_params.crc_stop + c_ack_delimiter_offset;
  eof_stop      <= frame_params.crc_stop + c_eof_start_offset + c_eof_field_width;

  -- Dynamic stuff eligibility boundary: SBC start for FD, CRC stop for CC
  dynamic_stuff_stop <= sbc_start when frame_params.is_fd_frame = '1' else
                        frame_params.crc_stop;

  fsm_sequential : process (clk_i) is

    -- Temporary per-cycle values (read-back within same cycle)
    variable v_tx_bit             : t_mac_frame_bit;
    variable v_monitored_bit_info : t_observed_mac_frame_bit_info;

    -- Next-value variables (read-back within same cycle)
    variable v_bit_count     : t_bit_count;
    variable v_in_data_phase : std_logic;

    -- Handles logic common to quiet states (ISO 11898-1: 6.6.7):
    -- entry-side interface reset/deassertion and SP-based idle-run counting.
    procedure process_quiet_phase_common is
    begin

      if (prev_state /= state) then
        -- Deactivate transmit levels on entry to quiet states
        pcs_o             <= c_mac_to_pcs_if_reset;
        fce_o             <= c_mac_to_fce_if_reset;
        ssp_error_pending <= false;
        v_in_data_phase   := '0';

        -- Clear terminal transfer status when entering any quiet state.
        mac_ser_o.transfer_status <= c_ongoing;

      elsif (pcs_i.sp = '1') then
        -- ISO 11898-1: 6.6.7.5 - count consecutive recessive bits at SP;
        -- dominant resets the run counter.
        if (pcs_i.bus_polarity = c_recessive) then
          if (bit_count < t_bit_count'high) then
            v_bit_count := bit_count + 1;
          end if;
        else
          v_bit_count := 0;
        end if;
      end if;

    end procedure process_quiet_phase_common;

    -- Writes a frame bit to the TX history FIFO and advances the write pointer.
    procedure write_to_fifo (
      constant bit_c : in t_mac_frame_bit
    ) is
    begin

      fifo(fifo_write_ptr) <= bit_c;
      if (fifo_write_ptr = c_transmitted_bits_fifo_depth - 1) then
        fifo_write_ptr <= 0;
      else
        fifo_write_ptr <= fifo_write_ptr + 1;
      end if;

    end procedure write_to_fifo;

    -- Initializes a new frame transmission on state entry.
    -- When skip_sof_c is true (ISO 11898-1: 6.6.7.2 / 6.6.8), the SOF has
    -- already been observed on the bus. The first ID bit (ser_data) is driven
    -- onto PCS instead; bit_count stays at 0 so transmit_normal_bit prepares
    -- bit 1 for CRC, stuffer, and serializer on the next SP as usual.
    procedure initialize_frame_transmission (
      constant skip_sof_c : in boolean := false
    ) is

    begin

      -- Initialize interfaces to clean state
      fce_o     <= c_mac_to_fce_if_reset;
      pcs_o     <= c_mac_to_pcs_if_reset;
      mac_ser_o <= c_tx_mac_fsm_to_ser_if_reset;
      crc_o     <= c_mac_fsm_to_crc_if_reset;

      -- Calculate and cache frame parameters from LLC metadata
      frame_params          <= calculate_frame_params(mac_ser_i.llc_metadata);
      crc_o.crc_poly_select <= calculate_frame_params(mac_ser_i.llc_metadata).crc_poly_select;
      crc_o.start           <= '1';

      -- Activate transmit levels
      fce_o.transmitting <= '1';
      pcs_o.valid        <= '1';

      -- Frame initialization
      fifo                      <= (0 => c_sof_bit, others => c_reset_mac_frame_bit);
      fifo_write_ptr            <= 1;
      ack_success_seen          <= false;
      bit_count_monitored       <= false;
      ssp_error_pending         <= false;
      ack_error_caused_flag     <= false;
      dominant_seen_during_flag <= false;
      dominant_run_count        <= 0;
      v_in_data_phase           := '0';

      bs_fd_o.start <= '1';

      -- SOF is always dominant (ISO 11898-1: 6.6.8)
      v_tx_bit                      := c_sof_bit;
      last_transmitted_bit_polarity <= c_dominant;
      v_bit_count                   := 0;

      -- Feed SOF to CRC
      crc_o.valid <= '1';
      crc_o.data  <= c_dominant;

      if (skip_sof_c) then
        -- ISO 11898-1: 6.6.7.2 / 6.6.8 - SOF already on bus; drive first
        -- ID bit (polarity = ser_data) onto PCS instead.
        pcs_o.polarity <= mac_ser_i.data;
      else
        pcs_o.polarity <= c_dominant;
      end if;

    end procedure initialize_frame_transmission;

    -- Transmits an inserted dynamic stuff bit:
    -- writes FIFO history, drives PCS output, updates stuffer recursion and FD CRC feed.
    procedure transmit_stuff_bit is

    begin

      v_tx_bit := (polarity => bs_fd_i.data, bit_name => stuff_bit);

      -- FIFO write (TX history for PCS delay comparison)
      write_to_fifo(v_tx_bit);

      bit_count_monitored           <= false;
      last_transmitted_bit_polarity <= bs_fd_i.data;

      -- Send to PCS
      pcs_o.valid    <= '1';
      pcs_o.polarity <= bs_fd_i.data;

      -- Feed bit stuffer (recursive loop)
      if (bit_count < dynamic_stuff_stop) then
        bs_fd_o.valid <= '1';
        bs_fd_o.data  <= bs_fd_i.data;
      end if;

      -- ISO 11898-1: 10.6.3 - Stuff bits in FD frames are included in CRC
      if (frame_params.is_fd_frame = '1' and bit_count < crc_start) then
        crc_o.valid <= '1';
        crc_o.data  <= bs_fd_i.data;
      end if;

    end procedure transmit_stuff_bit;

    -- Transmits the next non-stuff frame bit:
    -- computes bit(bit_count+1), updates FIFO/bit_count, and drives serializer/CRC/stuffer handshakes.
    procedure transmit_normal_bit is

      variable prepare_position_v   : t_bit_count;
      variable serializer_sourced_v : boolean;
      variable crc_cc_eligible_v    : boolean;

    begin

      prepare_position_v := bit_count + 1;

      -- Calculate NEXT position for registered output alignment
      v_tx_bit := get_next_mac_frame_bit(
                                         bit_count         => prepare_position_v,
                                         ser_data          => mac_ser_i.data,
                                         frame_params      => frame_params,
                                         previous_polarity => last_transmitted_bit_polarity,
                                         sbc               => bs_fd_i.sbc,
                                         crc               => crc_i.crc
                                       );

      -- FIFO write
      write_to_fifo(v_tx_bit);

      bit_count_monitored           <= false;
      last_transmitted_bit_polarity <= v_tx_bit.polarity;

      -- Send to PCS only if bit is valid (not beyond frame end)
      if (v_tx_bit.bit_name /= unknown) then
        pcs_o.valid    <= '1';
        pcs_o.polarity <= v_tx_bit.polarity;
      end if;

      -- Increment logical bit counter on non-stuff bits
      if (v_tx_bit.bit_name /= stuff_bit) then
        v_bit_count := prepare_position_v;

        -- Request data from serializer for data-driven fields
        serializer_sourced_v := v_tx_bit.bit_name = base_id_bit or
                                v_tx_bit.bit_name = extended_id_bit or
                                v_tx_bit.bit_name = data_bit;
        if (serializer_sourced_v) then
          mac_ser_o.ready <= '1';
        end if;

        -- ISO 11898-1: 10.6.3 - Logical bits fed to CRC
        crc_cc_eligible_v := prepare_position_v < crc_start and
                             v_tx_bit.bit_name /= fixed_stuff_bit;
        if (crc_cc_eligible_v) then
          crc_o.valid <= '1';
          crc_o.data  <= v_tx_bit.polarity;
        end if;
      end if;

      -- Feed bit stuffer (prepare_position_v: the bit being prepared is within dynamic stuff region)
      if (prepare_position_v < dynamic_stuff_stop) then
        bs_fd_o.valid <= '1';
        bs_fd_o.data  <= v_tx_bit.polarity;
      end if;

      -- Track data phase transitions for PCS rate control
      if (frame_params.has_brs = '1' and v_tx_bit.bit_name = esi_bit) then
        v_in_data_phase := '1';
      elsif (v_tx_bit.bit_name = crc_delimiter_bit) then
        v_in_data_phase := '0';
      end if;

      -- Drive PCS control signals based on prepared bit
      pcs_o.start_tdc     <= '1' when v_tx_bit.bit_name = fdf_bit else '0';
      pcs_o.use_data_rate <= v_in_data_phase;

    end procedure transmit_normal_bit;

    -- Monitors the observed bus bit and decides frame progression:
    -- handles SSP->SP deferred error reaction, arbitration/ACK/error events, and chooses normal vs stuff bit.
    procedure transmit_frame_bit is

      variable react_ssp_error_at_sp_v : boolean;
      variable error_flag_bit_v        : t_mac_frame_bit;

      -- Common error response: flags error, disturbs transfer, drives error flag bit.
      procedure start_error_response is
      begin

        was_previous_frame_tx     <= true;
        fce_o.error               <= '1';
        mac_ser_o.transfer_status <= c_disturbed;
        pcs_o.valid               <= '1';
        pcs_o.polarity            <= error_flag_bit_v.polarity;
        v_in_data_phase           := '0';

      end procedure start_error_response;

    begin

      react_ssp_error_at_sp_v := ssp_error_pending and pcs_i.sp = '1';
      if (fce_i.error_passive_request = '1') then
        error_flag_bit_v := c_passive_error_flag_bit;
      else
        error_flag_bit_v := c_active_error_flag_bit;
      end if;

      if (react_ssp_error_at_sp_v) then
        -- ISO 11898-1: 6.6.21.3.1 (see Figure 30):
        -- react at SP to an error detected earlier at SSP.
        start_error_response;
        monitored_bit_event <= bit_error;
        ssp_error_pending   <= false;
        return;
      end if;

      -- Monitor bus once per bit position (one-shot alignment)
      if (not bit_count_monitored) then
        v_monitored_bit_info := get_observed_mac_frame_bit_info(
                                                                fifo                   => fifo,
                                                                fifo_index             => to_integer(unsigned(pcs_i.fifo_index)),
                                                                fifo_write_ptr         => fifo_write_ptr,
                                                                monitored_bit_polarity => pcs_i.bus_polarity,
                                                                frame_params           => frame_params
                                                              );
        if (pcs_i.ssp = '0') then
          mac_ser_o.transfer_status <= v_monitored_bit_info.transfer_status;
          monitored_bit_event       <= v_monitored_bit_info.event_type;
        end if;
        bit_count_monitored <= true;
      end if;

      if (pcs_i.ssp = '1') then
        -- ISO 11898-1: 6.6.21.3.1 (see Figure 30/Figure 31):
        -- detect bit error at SSP and defer reaction to following SP.
        ssp_error_pending <= ssp_error_pending or (v_monitored_bit_info.event_type = bit_error);
        return;
      end if;

      case v_monitored_bit_info.event_type is
        when lost_arbitration =>
          was_previous_frame_tx     <= false;
          mac_ser_o.transfer_status <= c_lost_arb;

        when ack_detected =>
          was_previous_frame_tx <= true;
          ack_success_seen      <= true;
          transmit_normal_bit;

        when bit_error =>
          start_error_response;

        when ack_error =>
          start_error_response;
          ack_error_caused_flag <= true;

        when none =>
          if (bit_count = ack_delimiter and (not ack_success_seen)) then
            start_error_response;
            monitored_bit_event   <= ack_error;
            ack_error_caused_flag <= true;
            ack_error_detected    <= '1';
          elsif (bs_fd_i.valid = '1' and bit_count < dynamic_stuff_stop) then
            transmit_stuff_bit;
          else
            transmit_normal_bit;
          end if;

      end case;

    end procedure transmit_frame_bit;

    -- Handles behavior shared by active/passive error-flag and overload-flag states:
    -- flag/delimiter serialization, delimiter-dominant run tracking, and reactive overload trigger.
    procedure process_flag_transmission (
      constant flag_bit_c                       : in t_mac_frame_bit;
      constant track_error_delimiter_too_late_c : in boolean
    ) is

      variable in_flag_field_v       : boolean;
      variable in_delimiter_field_v  : boolean;
      variable track_delimiter_run_v : boolean;

    begin

      fce_o.error                       <= '1';
      fce_o.sending_error_overload_flag <= '1';
      mac_ser_o.transfer_status         <= c_disturbed;

      if (prev_state /= state) then
        -- Activate transmit levels
        fce_o.transmitting <= '1';
        pcs_o.valid        <= '1';

        v_bit_count               := 0;
        dominant_seen_during_flag <= false;
        dominant_run_count        <= 0;
        v_in_data_phase           := '0';

        -- Initialize first bit of flag
        pcs_o.polarity      <= flag_bit_c.polarity;
        pcs_o.use_data_rate <= '0';
        pcs_o.start_tdc     <= '0';
      else
        in_flag_field_v      := (bit_count < c_error_flag_width);
        in_delimiter_field_v := not in_flag_field_v;

        -- Select flag or delimiter bit based on progress (ISO 11898-1: 6.6.5 / 6.6.6).
        if (in_flag_field_v) then
          v_tx_bit := flag_bit_c;
        else
          v_tx_bit := c_error_delimiter_bit;
        end if;

        pcs_o.polarity <= v_tx_bit.polarity;

        if (pcs_i.sp = '1') then
          if (bit_count < c_error_sequence_width - 1) then
            v_bit_count := bit_count + 1;
          end if;

          -- ISO 11898-1: 8.1.3.3 Table 16 (Error_delimiter_too_late) and
          -- 8.1.4.2 rule f): applies to error-flag delimiter handling.
          track_delimiter_run_v := track_error_delimiter_too_late_c and in_delimiter_field_v;
          if (track_delimiter_run_v) then
            if (pcs_i.bus_polarity = c_recessive) then
              dominant_run_count <= 0;
            elsif (dominant_run_count = c_delimiter_dominant_run_limit) then
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
        end if;

        -- State transition: overload or sequence complete
        if (overload_condition) then
          state       <= s_overload_flag;
          v_bit_count := 0;
        elsif (bit_count = c_error_sequence_width - 1) then
          state       <= s_intermission;
          v_bit_count := 0;
        end if;
      end if;

    end procedure process_flag_transmission;

    -- Applies ACK-error passive EF exception bookkeeping:
    -- tracks dominant seen in passive EF and raises counters_unchanged at sequence end when allowed.
    procedure apply_passive_ack_exception is

      variable passive_ack_exception_window_v : boolean;
      variable passive_ack_dominant_in_flag_v : boolean;
      variable passive_ack_no_dominant_end_v  : boolean;

    begin

      passive_ack_exception_window_v := pcs_i.sp = '1' and ack_error_caused_flag;
      passive_ack_dominant_in_flag_v := passive_ack_exception_window_v and
                                        bit_count < c_error_flag_width and
                                        pcs_i.bus_polarity = c_dominant;
      passive_ack_no_dominant_end_v  := passive_ack_exception_window_v and
                                        bit_count >= c_error_sequence_width - 1 and
                                        not dominant_seen_during_flag;

      -- ISO 11898-1: 8.1.4.2 rule c), Exception 1:
      -- passive transmitter ACK error without dominant seen in passive EF.
      if (passive_ack_dominant_in_flag_v) then
        dominant_seen_during_flag <= true;
      end if;

      if (passive_ack_no_dominant_end_v) then
        fce_o.counters_unchanged <= '1';
      end if;

    end procedure apply_passive_ack_exception;

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        -- Reset ALL registered signals to initial values
        state                         <= s_bus_reintegration;
        prev_state                    <= s_bus_reintegration;
        bit_count                     <= 0;
        fifo                          <= (others => c_reset_mac_frame_bit);
        fifo_write_ptr                <= 0;
        last_transmitted_bit_polarity <= c_recessive;
        monitored_bit_event           <= none;
        was_previous_frame_tx         <= false;
        ack_success_seen              <= false;
        bit_count_monitored           <= false;
        overload_condition            <= false;
        ssp_error_pending             <= false;
        ack_error_caused_flag         <= false;
        dominant_seen_during_flag     <= false;
        dominant_run_count            <= 0;
        idle_condition_count          <= 0;
        skip_sof                      <= false;
        in_data_phase                 <= '0';
        frame_params                  <= c_frame_params_reset;
        ack_error_detected            <= '0';

        -- Reset port outputs using interface constants
        mac_ser_o <= c_tx_mac_fsm_to_ser_if_reset;
        pcs_o     <= c_mac_to_pcs_if_reset;
        bs_fd_o   <= c_mac_fsm_to_bs_fd_if_reset;
        crc_o     <= c_mac_fsm_to_crc_if_reset;
        fce_o     <= c_mac_to_fce_if_reset;
      else
        -- Debug signal defaults (pulses only when errors detected)
        ack_error_detected <= '0';

        -- Per-cycle temporary defaults
        v_tx_bit             := c_reset_mac_frame_bit;
        v_monitored_bit_info := c_reset_observed_mac_frame_bit_info;

        -- Hold defaults for retained variables
        v_bit_count     := bit_count;
        v_in_data_phase := in_data_phase;

        ---------------------------------------------------------------------
        -- Pulse defaults (cleared every cycle, set only when active)
        ---------------------------------------------------------------------
        bs_fd_o                           <= c_mac_fsm_to_bs_fd_if_reset;
        mac_ser_o.ready                   <= '0';
        crc_o.valid                       <= '0';
        crc_o.start                       <= '0';
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
          -- (ISO 11898-1: 6.6.7.5, 8.2 T5).
          -----------------------------------------------------------------
          when s_bus_reintegration =>
            process_quiet_phase_common;
            pcs_o.polarity <= c_recessive;
            if (bit_count = c_bus_idle_condition_width - 1) then
              if (fce_i.bus_off = '0') then
                -- ISO 11898-1: 6.6.7.5 - non bus-off: single idle condition.
                state       <= s_bus_idle;
                v_bit_count := 0;
              elsif (idle_condition_count = c_bus_off_recovery_count - 1) then
                -- ISO 11898-1: 8.2 (T5) - bus-off: 128th idle condition reached.
                state       <= s_bus_idle;
                v_bit_count := 0;
              else
                idle_condition_count <= idle_condition_count + 1;
                v_bit_count          := 0;
              end if;
            end if;

          -----------------------------------------------------------------
          -- 3-bit inter-frame spacing.
          -----------------------------------------------------------------
          when s_intermission =>
            process_quiet_phase_common;
            pcs_o.polarity <= c_recessive;
            -- ISO 11898-1: 10.4.4.3 condition b) - dominant detected during first
            -- two intermission bits triggers overload handling.
            if (pcs_i.sp = '1' and pcs_i.bus_polarity = c_dominant and bit_count < c_intermission_width - 1) then
              overload_condition <= true;
            end if;
            if (overload_condition) then
              state       <= s_overload_flag;
              v_bit_count := 0;
            elsif (bit_count = c_intermission_width - 1 and pcs_i.sp = '1' and pcs_i.bus_polarity = c_dominant) then
              -- ISO 11898-1: 6.6.7.2 / 6.6.8 - dominant at 3rd intermission bit
              -- shall be interpreted as SOF. A node with a pending transmission
              -- that is error-active or was receiver of the previous frame shall
              -- start transmitting at the next bit with its first identifier bit,
              -- without first transmitting SOF.
              if (mac_ser_i.valid = '1' and fce_i.bus_off = '0' and
                  (fce_i.error_passive_request = '0' or not was_previous_frame_tx)) then
                state       <= s_transmitting_frame;
                skip_sof    <= true;
                v_bit_count := 0;
              else
                state       <= s_bus_idle;
                v_bit_count := 0;
              end if;
            elsif (bit_count = c_intermission_width - 1) then
              -- ISO 11898-1: 6.6.7.4 / 6.6.7.3 - error-passive transmitters
              -- enter suspend_transmission; all others enter bus_idle.
              if (fce_i.error_passive_request = '1' and was_previous_frame_tx) then
                state       <= s_suspend_transmission;
                v_bit_count := 0;
              else
                state       <= s_bus_idle;
                v_bit_count := 0;
              end if;
            end if;

          -----------------------------------------------------------------
          -- ISO 11898-1: 6.6.7.4 - error-passive nodes that transmitted
          -- the previous frame shall suspend for 8 additional bit times.
          -----------------------------------------------------------------
          when s_suspend_transmission =>
            process_quiet_phase_common;
            pcs_o.polarity <= c_recessive;
            if (overload_condition) then
              state       <= s_overload_flag;
              v_bit_count := 0;
            elsif (bit_count = c_suspend_transmission_width - 1) then
              state       <= s_bus_idle;
              v_bit_count := 0;
            end if;

          -----------------------------------------------------------------
          -- ISO 11898-1: 6.6.7.3 - bus idle; any node may start transmission.
          -----------------------------------------------------------------
          when s_bus_idle =>
            process_quiet_phase_common;
            pcs_o.polarity <= c_recessive;
            if (prev_state /= state) then
              mac_ser_o <= c_tx_mac_fsm_to_ser_if_reset;
            end if;
            -- ISO 11898-1: 8.1.4.1 - bus_off nodes shall not initiate transmissions
            if (mac_ser_i.valid = '1' and pcs_i.sp = '1' and fce_i.bus_off = '0') then
              state       <= s_transmitting_frame;
              v_bit_count := 0;
            end if;

          -----------------------------------------------------------------
          -- Active frame transmission with bit-level monitoring.
          -----------------------------------------------------------------
          when s_transmitting_frame =>
            if (prev_state /= state) then
              initialize_frame_transmission(skip_sof_c => skip_sof);
              skip_sof <= false;
            elsif (bit_count = eof_stop) then
              -- ISO 11898-1: 8.1.4.2 rule a) - successful transmission.
              mac_ser_o.transfer_status <= c_transmitted;
              was_previous_frame_tx     <= true;
              fce_o.successful_transfer <= '1';
              state                     <= s_intermission;
              v_bit_count               := 0;
              v_in_data_phase           := '0';
            elsif ((pcs_i.sp = '1' or pcs_i.ssp = '1')) then
              transmit_frame_bit;
            end if;

            -- ISO 11898-1: 6.6.3 - arbitration lost or error handling.
            if (monitored_bit_event = lost_arbitration) then
              state           <= s_intermission;
              v_bit_count     := 0;
              v_in_data_phase := '0';
            elsif ((monitored_bit_event = bit_error or monitored_bit_event = ack_error)) then
              v_in_data_phase := '0';
              v_bit_count     := 0;
              if (fce_i.error_passive_request = '1') then
                state <= s_passive_error_flag;
              else
                state <= s_active_error_flag;
              end if;
            end if;

          -----------------------------------------------------------------
          -- ISO 11898-1: 6.6.5 - active error flag (6 dominant) + delimiter
          -- (8 recessive).
          -----------------------------------------------------------------
          when s_active_error_flag =>
            process_flag_transmission(c_active_error_flag_bit, true);
            -- ISO 11898-1: 8.1.3.3 Table 16 - Primary_error
            if (pcs_i.sp = '1' and bit_count < c_error_flag_width and pcs_i.bus_polarity = c_dominant) then
              fce_o.primary_error <= '1';
            end if;

          -----------------------------------------------------------------
          -- ISO 11898-1: 6.6.6 - passive error flag (6 recessive) + delimiter
          -- (8 recessive).
          -----------------------------------------------------------------
          when s_passive_error_flag =>
            process_flag_transmission(c_passive_error_flag_bit, true);
            -- ISO 11898-1: 8.1.3.3 Table 16 - Primary_error
            if (pcs_i.sp = '1' and bit_count < c_error_flag_width and pcs_i.bus_polarity = c_dominant) then
              fce_o.primary_error <= '1';
            end if;
            apply_passive_ack_exception;

          -----------------------------------------------------------------
          -- ISO 11898-1: 6.6.4 - overload flag (6 dominant) + delimiter
          -- (8 recessive).
          -----------------------------------------------------------------
          when s_overload_flag =>
            process_flag_transmission(c_overload_flag_bit, false);

          when others =>
            state       <= s_bus_reintegration;
            v_bit_count := 0;

        end case;

        -- Register retained variables
        prev_state       <= state;
        bit_count        <= v_bit_count;
        in_data_phase    <= v_in_data_phase;
        current_bit_name <= v_tx_bit.bit_name;
      end if;
    end if;

  end process fsm_sequential;

  -- Wire debug signals to ports
  debug_ack_error_o  <= ack_error_detected;
  debug_form_error_o <= '0';
  debug_data_exit_o  <= '0';
  debug_fsm_state_o  <= to_slv(state);
  debug_bit_name_o   <= current_bit_name;

end architecture rtl;
