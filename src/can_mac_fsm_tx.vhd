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
    debug_ack_error_o  : out std_logic;
    debug_form_error_o : out std_logic;
    debug_data_exit_o  : out std_logic;
    debug_fsm_state_o  : out std_logic_vector(2 downto 0);
    debug_bit_name_o   : out t_mac_frame_bit_name
  );
end entity can_mac_fsm_tx;

architecture rtl of can_mac_fsm_tx is

  ---------------------------------------------------------------------------
  -- Local state encoding
  ---------------------------------------------------------------------------
  constant c_st_bus_reintegration    : std_logic_vector(2 downto 0) := "000";
  constant c_st_intermission         : std_logic_vector(2 downto 0) := "001";
  constant c_st_suspend_transmission : std_logic_vector(2 downto 0) := "010";
  constant c_st_bus_idle             : std_logic_vector(2 downto 0) := "011";
  constant c_st_transmitting_frame   : std_logic_vector(2 downto 0) := "100";
  constant c_st_active_error_flag    : std_logic_vector(2 downto 0) := "101";
  constant c_st_passive_error_flag   : std_logic_vector(2 downto 0) := "110";
  constant c_st_overload_flag        : std_logic_vector(2 downto 0) := "111";

  -- Threshold used for delimiter-dominant run tracking before raising
  -- Error_delimiter_too_late (ISO 11898-1: 8.1.3.3 Table 16).
  constant c_delimiter_dominant_run_limit : integer := 7;

  ---------------------------------------------------------------------------
  -- Registered state signals
  ---------------------------------------------------------------------------
  signal state                         : std_logic_vector(2 downto 0);
  signal prev_state                    : std_logic_vector(2 downto 0);
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

  -- Cached frame parameters (calculated once per frame from LLC metadata)
  signal frame_params : t_frame_params;

  -- Debug signals for test visibility
  signal ack_error_detected     : std_logic;
  signal form_error_detected    : std_logic;
  signal data_phase_exit_strobe : std_logic;
  signal current_bit_name       : t_mac_frame_bit_name;

begin

  fsm_sequential : process (clk_i) is

    -- Temporary per-cycle values (read-back within same cycle)
    variable v_tx_bit             : t_mac_frame_bit;
    variable v_monitored_bit_info : t_observed_mac_frame_bit_info;

    -- Next-value variables (read-back within same cycle)
    variable v_state          : std_logic_vector(2 downto 0);
    variable v_bit_count      : t_bit_count;
    variable v_frame_params   : t_frame_params;
    variable v_fifo           : t_transmitted_bits_fifo;
    variable v_fifo_write_ptr : t_fifo_write_ptr;
    variable v_in_data_phase  : std_logic;

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
    variable ssp_sample_strobe_v          : boolean;

    -- Derived position variables (from frame_params.data_stop / crc_stop)
    variable sbc_start_v     : t_position;
    variable crc_start_v     : t_position;
    variable ack_delimiter_v : t_position;
    variable eof_stop_v      : t_position;

    -- Handles logic common to quiet states:
    -- entry-side interface reset/deassertion and SP-based idle-run counting.
    procedure process_quiet_phase_common is
    begin

      if (state_entry_v) then
        -- Deactivate transmit levels on entry to quiet states
        pcs_o            <= c_mac_to_pcs_if_reset;
        fce_o            <= c_mac_to_fce_if_reset;
        ssp_error_pending <= false;
        v_in_data_phase  := '0';

        -- Clear terminal transfer status when entering any quiet state.
        mac_ser_o.transfer_status <= c_ongoing;

      elsif (sp_sample_strobe_v) then
        if (pcs_i.bus_polarity = c_recessive) then
          if (bit_count < t_bit_count'high) then
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

      -- Calculate frame parameters from LLC metadata
      v_frame_params := calculate_frame_params(mac_ser_i.llc_metadata);

      -- Initialize interfaces to clean state
      fce_o     <= c_mac_to_fce_if_reset;
      pcs_o     <= c_mac_to_pcs_if_reset;
      mac_ser_o <= c_tx_mac_fsm_to_ser_if_reset;
      crc_o     <= c_mac_fsm_to_crc_if_reset;

      -- Select CRC polynomial and signal start of new computation
      crc_o.crc_poly_select <= v_frame_params.crc_poly_select;
      crc_o.start           <= '1';

      -- Activate transmit levels
      fce_o.transmitting <= '1';
      pcs_o.valid        <= '1';

      -- Frame initialization
      v_bit_count      := 0;
      v_fifo           := (others => c_reset_mac_frame_bit);
      v_fifo_write_ptr := 0;
      ack_success_seen          <= false;
      bit_count_monitored       <= false;
      ssp_error_pending         <= false;
      ack_error_caused_flag     <= false;
      dominant_seen_during_flag <= false;
      dominant_run_count        <= 0;
      v_in_data_phase  := '0';

      bs_fd_o.start <= '1';

      -- Initialize first bit (SOF)
      v_tx_bit     := get_next_mac_frame_bit(
                                          bit_count         => 0,
                                          ser_data          => mac_ser_i.data,
                                          frame_params      => v_frame_params,
                                          previous_polarity => c_recessive,
                                          sbc               => (others => '0'),
                                          crc               => (others => '0')
                                        );
      pcs_o.polarity <= v_tx_bit.polarity;

      -- Add SOF to FIFO
      v_fifo(0)                        := v_tx_bit;
      v_fifo_write_ptr                 := 1;
      last_transmitted_bit_polarity    <= v_tx_bit.polarity;

      -- SOF is always fed to CRC
      crc_o.valid <= '1';
      crc_o.data  <= v_tx_bit.polarity;

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
      if (fifo_write_ptr = c_transmitted_bits_fifo_depth - 1) then
        v_fifo_write_ptr := 0;
      else
        v_fifo_write_ptr := fifo_write_ptr + 1;
      end if;

      bit_count_monitored           <= false;
      last_transmitted_bit_polarity <= v_tx_bit.polarity;

      -- Send to PCS
      pcs_o.valid    <= '1';
      pcs_o.polarity <= v_tx_bit.polarity;

      -- Feed bit stuffer (recursive loop)
      if (frame_params.is_fd_frame = '1') then
        dynamic_stuff_eligible_v := bit_count < sbc_start_v;
      else
        dynamic_stuff_eligible_v := bit_count < frame_params.crc_stop;
      end if;

      if (dynamic_stuff_eligible_v) then
        bs_fd_o.valid <= '1';
        bs_fd_o.data  <= v_tx_bit.polarity;
      end if;

      -- ISO 11898-1: 10.6.3 - Stuff bits in FD frames are included in CRC
      crc_fd_stuff_eligible_v := frame_params.is_fd_frame = '1' and
                                 bit_count < crc_start_v;
      if (crc_fd_stuff_eligible_v) then
        crc_o.valid <= '1';
        crc_o.data  <= v_tx_bit.polarity;
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
      v_fifo(fifo_write_ptr) := v_tx_bit;
      if (fifo_write_ptr = c_transmitted_bits_fifo_depth - 1) then
        v_fifo_write_ptr := 0;
      else
        v_fifo_write_ptr := fifo_write_ptr + 1;
      end if;

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
        crc_cc_eligible_v := prepare_position_v < crc_start_v and
                             v_tx_bit.bit_name /= fixed_stuff_bit;
        if (crc_cc_eligible_v) then
          crc_o.valid <= '1';
          crc_o.data  <= v_tx_bit.polarity;
        end if;
      end if;

      -- Feed bit stuffer (prepare_position_v: the bit being prepared is within dynamic stuff region)
      if (frame_params.is_fd_frame = '1') then
        if (prepare_position_v < sbc_start_v) then
          bs_fd_o.valid <= '1';
          bs_fd_o.data  <= v_tx_bit.polarity;
        end if;
      else
        if (prepare_position_v < frame_params.crc_stop) then
          bs_fd_o.valid <= '1';
          bs_fd_o.data  <= v_tx_bit.polarity;
        end if;
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

      variable react_ssp_error_at_sp_v  : boolean;
      variable error_flag_bit_v         : t_mac_frame_bit;
      variable dynamic_stuff_eligible_v : boolean;

    begin

      if (frame_params.is_fd_frame = '1') then
        dynamic_stuff_eligible_v := bit_count < sbc_start_v;
      else
        dynamic_stuff_eligible_v := bit_count < frame_params.crc_stop;
      end if;

      react_ssp_error_at_sp_v := ssp_error_pending and sp_sample_strobe_v;
      if (fce_i.error_passive_request = '1') then
        error_flag_bit_v := c_passive_error_flag_bit;
      else
        error_flag_bit_v := c_active_error_flag_bit;
      end if;

      if (react_ssp_error_at_sp_v) then
        -- ISO 11898-1: 6.6.21.3.1 (see Figure 30):
        -- react at SP to an error detected earlier at SSP.
        was_previous_frame_tx     <= true;
        fce_o.error               <= '1';
        mac_ser_o.transfer_status <= c_disturbed;
        monitored_bit_event       <= bit_error;
        ssp_error_pending         <= false;
        pcs_o.valid               <= '1';
        pcs_o.polarity            <= error_flag_bit_v.polarity;
        v_in_data_phase           := '0';
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
        if (not ssp_sample_strobe_v) then
          mac_ser_o.transfer_status <= v_monitored_bit_info.transfer_status;
          monitored_bit_event       <= v_monitored_bit_info.event_type;
        end if;
        bit_count_monitored <= true;
      end if;

      if (ssp_sample_strobe_v) then
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
          was_previous_frame_tx     <= true;
          fce_o.error               <= '1';
          mac_ser_o.transfer_status <= c_disturbed;
          pcs_o.valid               <= '1';
          pcs_o.polarity            <= error_flag_bit_v.polarity;
          v_in_data_phase           := '0';

        when ack_error =>
          was_previous_frame_tx     <= true;
          fce_o.error               <= '1';
          mac_ser_o.transfer_status <= c_disturbed;
          ack_error_caused_flag     <= true;
          pcs_o.valid               <= '1';
          pcs_o.polarity            <= error_flag_bit_v.polarity;
          v_in_data_phase           := '0';

        when none =>
          if (bit_count = ack_delimiter_v and (not ack_success_seen)) then
            mac_ser_o.transfer_status <= c_disturbed;
            monitored_bit_event       <= ack_error;
            was_previous_frame_tx     <= true;
            ack_error_caused_flag     <= true;
            ack_error_detected        <= '1';
            pcs_o.valid               <= '1';
            pcs_o.polarity            <= error_flag_bit_v.polarity;
            v_in_data_phase           := '0';
          elsif (bs_fd_i.valid = '1' and dynamic_stuff_eligible_v) then
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

      if (state_entry_v) then
        -- Activate transmit levels
        fce_o.transmitting <= '1';
        pcs_o.valid        <= '1';

        v_bit_count := 0;
        dominant_seen_during_flag <= false;
        dominant_run_count        <= 0;
        v_in_data_phase := '0';

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

        if (sp_sample_strobe_v) then
          if (not error_sequence_complete_v) then
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
          if (error_sequence_complete_v and pcs_i.bus_polarity = c_dominant) then
            overload_condition <= true;
          end if;
        end if;
      end if;

    end procedure process_flag_transmission;

    -- Asserts FCE `primary_error` for dominant samples during the error-flag field at SP.
    procedure apply_primary_error_guard is

      variable primary_error_condition_v : boolean;

    begin

      primary_error_condition_v := sp_sample_strobe_v and
                                   bit_count < c_error_flag_width and
                                   pcs_i.bus_polarity = c_dominant;
      -- ISO 11898-1: 8.1.3.3 Table 16 - Primary_error:
      -- dominant detected while sending an error flag.
      if (primary_error_condition_v) then
        fce_o.primary_error <= '1';
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
                                        bit_count < c_error_flag_width and
                                        pcs_i.bus_polarity = c_dominant;
      passive_ack_no_dominant_end_v  := passive_ack_exception_window_v and
                                        error_sequence_complete_v and
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
        state                         <= c_st_bus_reintegration;
        prev_state                    <= c_st_bus_reintegration;
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
        in_data_phase                 <= '0';
        frame_params                  <= c_frame_params_reset;
        ack_error_detected            <= '0';
        form_error_detected           <= '0';
        data_phase_exit_strobe        <= '0';

        -- Reset port outputs using interface constants
        mac_ser_o <= c_tx_mac_fsm_to_ser_if_reset;
        pcs_o     <= c_mac_to_pcs_if_reset;
        bs_fd_o   <= c_mac_fsm_to_bs_fd_if_reset;
        crc_o     <= c_mac_fsm_to_crc_if_reset;
        fce_o     <= c_mac_to_fce_if_reset;
      else
        -- Debug signal defaults (pulses only when errors detected)
        ack_error_detected     <= '0';
        form_error_detected    <= '0';
        data_phase_exit_strobe <= '0';

        -- Per-cycle temporary defaults
        v_tx_bit             := c_reset_mac_frame_bit;
        v_monitored_bit_info := c_reset_observed_mac_frame_bit_info;

        -- Hold defaults for retained variables
        v_state          := state;
        v_bit_count      := bit_count;
        v_frame_params   := frame_params;
        v_fifo           := fifo;
        v_fifo_write_ptr := fifo_write_ptr;
        v_in_data_phase  := in_data_phase;

        -- Derive positions from frame_params.data_stop and crc_stop
        if (frame_params.is_fd_frame = '1') then
          sbc_start_v := frame_params.data_stop + 1;
          crc_start_v := sbc_start_v + c_sbc_field_width;
        else
          sbc_start_v := 0;
          crc_start_v := frame_params.data_stop + 1;
        end if;
        ack_delimiter_v := frame_params.crc_stop + c_ack_delimiter_offset;
        eof_stop_v      := frame_params.crc_stop + c_eof_start_offset + c_eof_field_width;

        -- Evaluate guards
        frame_transmitted_v          := bit_count = eof_stop_v;
        sp_sample_strobe_v           := pcs_i.sp = '1';
        ssp_sample_strobe_v          := pcs_i.ssp = '1';
        sample_strobe_v              := sp_sample_strobe_v or ssp_sample_strobe_v;
        error_sequence_complete_v    := bit_count >= c_error_flag_width + c_error_delimiter_width - 1;
        state_entry_v                := prev_state /= state;
        bus_is_idle_v                := (bit_count = c_bus_idle_condition_width - 1);
        intermission_ended_v         := (bit_count = c_intermission_width - 1);
        must_suspend_transmission_v  := fce_i.error_passive_request = '1' and was_previous_frame_tx;
        suspend_transmission_ended_v := (bit_count = c_suspend_transmission_width - 1);
        error_detected_v             := (monitored_bit_event = bit_error or monitored_bit_event = ack_error);
        error_flag_ended_v           := bit_count = c_error_flag_width + c_error_delimiter_width - 1;

        ---------------------------------------------------------------------
        -- Pulse defaults (cleared every cycle, set only when active)
        ---------------------------------------------------------------------
        bs_fd_o                        <= c_mac_fsm_to_bs_fd_if_reset;
        mac_ser_o.ready                <= '0';
        crc_o.valid                    <= '0';
        crc_o.start                    <= '0';
        fce_o.error                    <= '0';
        fce_o.primary_error            <= '0';
        fce_o.counters_unchanged       <= '0';
        fce_o.successful_transfer      <= '0';
        fce_o.error_delimiter_too_late <= '0';
        fce_o.sending_error_overload_flag <= '0';
        monitored_bit_event            <= none;
        overload_condition             <= false;

        ---------------------------------------------------------------------
        -- State machine
        ---------------------------------------------------------------------
        case state is

          -----------------------------------------------------------------
          -- Wait for 11 consecutive recessive bits.
          -----------------------------------------------------------------
          when c_st_bus_reintegration =>
            process_quiet_phase_common;
            pcs_o.polarity <= c_recessive;
            if (bus_is_idle_v) then
              v_state := c_st_bus_idle;
            end if;

          -----------------------------------------------------------------
          -- 3-bit inter-frame spacing.
          -----------------------------------------------------------------
          when c_st_intermission =>
            process_quiet_phase_common;
            pcs_o.polarity <= c_recessive;
            -- ISO 11898-1: 10.4.4.3 condition b) - dominant detected during first
            -- two intermission bits triggers overload handling.
            if (sp_sample_strobe_v and pcs_i.bus_polarity = c_dominant and bit_count < 2) then
              overload_condition <= true;
            end if;
            if (overload_condition) then
              v_state := c_st_overload_flag;
            elsif (intermission_ended_v) then
              if (must_suspend_transmission_v) then
                v_state := c_st_suspend_transmission;
              else
                v_state := c_st_bus_idle;
              end if;
            end if;

          -----------------------------------------------------------------
          -- Error-passive extra wait after own transmission.
          -----------------------------------------------------------------
          when c_st_suspend_transmission =>
            process_quiet_phase_common;
            pcs_o.polarity <= c_recessive;
            if (overload_condition) then
              v_state := c_st_overload_flag;
            elsif (suspend_transmission_ended_v) then
              v_state := c_st_bus_idle;
            end if;

          -----------------------------------------------------------------
          -- Ready for new frame.
          -----------------------------------------------------------------
          when c_st_bus_idle =>
            process_quiet_phase_common;
            pcs_o.polarity <= c_recessive;
            if (state_entry_v) then
              -- Reset all handshake signals once we reach bus_idle.
              mac_ser_o <= c_tx_mac_fsm_to_ser_if_reset;
            end if;
            -- ISO 11898-1: 8.1.4.1 - bus_off nodes shall not initiate transmissions
            if (mac_ser_i.valid = '1' and sp_sample_strobe_v and fce_i.bus_off = '0') then
              v_state := c_st_transmitting_frame;
            end if;

          -----------------------------------------------------------------
          -- Active frame transmission with bit-level monitoring.
          -----------------------------------------------------------------
          when c_st_transmitting_frame =>
            if (state_entry_v) then
              initialize_frame_transmission;
            elsif (frame_transmitted_v) then
              mac_ser_o.transfer_status <= c_transmitted;
              was_previous_frame_tx     <= true;
              fce_o.successful_transfer <= '1';
            elsif (sample_strobe_v) then
              transmit_frame_bit;
            end if;

            if (monitored_bit_event = lost_arbitration) then
              v_state         := c_st_intermission;
              v_in_data_phase := '0';
            elsif (error_detected_v) then
              v_in_data_phase := '0';
              if (fce_i.error_passive_request = '1') then
                v_state := c_st_passive_error_flag;
              else
                v_state := c_st_active_error_flag;
              end if;
            elsif (frame_transmitted_v) then
              v_state         := c_st_intermission;
              v_in_data_phase := '0';
            end if;

          -----------------------------------------------------------------
          -- 6 dominant + 8 recessive delimiter.
          -----------------------------------------------------------------
          when c_st_active_error_flag =>
            process_flag_transmission(c_active_error_flag_bit, true);
            apply_primary_error_guard;
            if (overload_condition) then
              v_state := c_st_overload_flag;
            elsif (error_flag_ended_v) then
              v_state := c_st_intermission;
            end if;

          -----------------------------------------------------------------
          -- 6 recessive + 8 recessive delimiter.
          -----------------------------------------------------------------
          when c_st_passive_error_flag =>
            process_flag_transmission(c_passive_error_flag_bit, true);
            apply_primary_error_guard;
            apply_passive_ack_exception;
            if (overload_condition) then
              v_state := c_st_overload_flag;
            elsif (error_flag_ended_v) then
              v_state := c_st_intermission;
            end if;

          -----------------------------------------------------------------
          -- Overload flag + delimiter.
          -----------------------------------------------------------------
          when c_st_overload_flag =>
            process_flag_transmission(c_overload_flag_bit, false);
            if (overload_condition) then
              v_state := c_st_overload_flag;
            elsif (error_flag_ended_v) then
              v_state := c_st_intermission;
            end if;

          when others =>
            v_state := c_st_bus_reintegration;

        end case;

        -- Register retained variables
        state      <= v_state;
        prev_state <= state;

        if (state /= v_state) then
          bit_count <= 0;
        else
          bit_count <= v_bit_count;
        end if;

        fifo           <= v_fifo;
        fifo_write_ptr <= v_fifo_write_ptr;
        in_data_phase  <= v_in_data_phase;
        frame_params   <= v_frame_params;
        current_bit_name <= v_tx_bit.bit_name;
      end if;
    end if;

  end process fsm_sequential;

  -- Wire debug signals to ports
  debug_ack_error_o  <= ack_error_detected;
  debug_form_error_o <= form_error_detected;
  debug_data_exit_o  <= data_phase_exit_strobe;
  debug_fsm_state_o  <= state;
  debug_bit_name_o   <= current_bit_name;

end architecture rtl;
