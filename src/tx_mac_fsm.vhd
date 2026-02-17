
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

  signal bit_count                     : bit_count_t;
  signal state                         : tx_mac_fsm_state_t;
  signal next_state                    : tx_mac_fsm_state_t;
  signal fifo                          : transmitted_bits_fifo_t;
  signal fifo_write_ptr                : fifo_write_ptr_t;
  signal last_transmitted_bit_polarity : polarity_t;
  signal monitored_bit_event           : tx_mac_monitor_event_t;
  signal was_previous_frame_tx         : boolean;
  signal ack_success_seen              : boolean;
  signal bit_count_monitored           : boolean;
  signal prev_state                    : tx_mac_fsm_state_t;
  signal overload_condition            : boolean;

begin

  next_state_logic : process (all) is

    -- Guards
    variable bus_is_idle_v                : boolean;
    variable intermission_ended_v         : boolean;
    variable must_suspend_transmission_v  : boolean;
    variable suspend_transmission_ended_v : boolean;
    variable error_detected_v             : boolean;
    variable frame_transmitted_v          : boolean;
    variable error_flag_ended_v           : boolean;

  begin

    if (rst_i = '1') then
      next_state <= bus_reintegration;
    else
      -- Evaluate guards
      bus_is_idle_v                := (bit_count = bus_idle_condition_width_c - 1);
      intermission_ended_v         := (bit_count = intermission_width_c - 1);
      must_suspend_transmission_v  := fce_i.error_passive and was_previous_frame_tx; -- ISO 11898-1 6.6.7.4
      suspend_transmission_ended_v := (bit_count = suspend_transmission_width_c - 1);
      error_detected_v             := (monitored_bit_event = bit_error or monitored_bit_event = ack_error);
      frame_transmitted_v          := bit_count = mac_ser_i.frame_params.eof_stop;
      error_flag_ended_v           := bit_count = error_flag_width_c + error_delimiter_width_c - 1;

      -- Default
      next_state <= state;

    end if;

    -- Next logic FSM
    case state is
      when bus_reintegration =>
        if (bus_is_idle_v) then
          next_state <= bus_idle;
        end if;

      when intermission =>
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
        if (suspend_transmission_ended_v) then
          next_state <= bus_idle;
        end if;

      when bus_idle =>
        if (mac_ser_i.valid) then
          next_state <= transmitting_frame;
        end if;

      when transmitting_frame =>
        if (monitored_bit_event = lost_arbitration) then
          next_state <= intermission;
        elsif (error_detected_v) then
          next_state <= transmitting_error_flag;
        elsif (frame_transmitted_v) then
          next_state <= intermission;
        end if;

      when transmitting_error_flag | transmitting_overload_flag =>
        if (overload_condition) then
          next_state <= transmitting_overload_flag;
        elsif (error_flag_ended_v) then
          next_state <= intermission;
        end if;

      when others =>
    end case;

  end process next_state_logic;

  output_logic : process (clk_i) is

    variable next_bit_v           : mac_frame_bit_t;
    variable monitored_bit_info_v : observed_mac_frame_bit_info_t;

    -- Guards
    variable frame_transmitted_v       : boolean;
    variable sample_strobe_detected_v  : boolean;
    variable error_sequence_complete_v : boolean;
    variable state_entry_v             : boolean;
    variable intermission_overload_v   : boolean; -- ISO 6.6.21.3.2 b1
    variable delimiter_overload_v      : boolean; -- ISO 6.6.21.3.2 b2

    -- Transmit the given bit to the PCS, bit stuffer, CRC module, and FIFO as appropriate.
    procedure transmit_bit (
      bit : in mac_frame_bit_t
    ) is

      -- Guards
      variable serializer_sourced_v : boolean;
      variable crc_eligible_v       : boolean;

    begin

      serializer_sourced_v := bit.bit_name = base_id_bit or
                              bit.bit_name = extended_id_bit or
                              bit.bit_name = data_bit;
      crc_eligible_v       := bit_count < mac_ser_i.frame_params.crc_start and
                              bit.bit_name /= fixed_stuff_bit;

      -- Send the bit to the PCS
      pcs_o.valid <= true;
      pcs_o.data  <= bit;

      -- Send bit to bit stuffer
      if (bit_count < mac_ser_i.frame_params.crc_stop) then
        bs_fd_o.valid <= true;
        bs_fd_o.data  <= bit.polarity;
      else
        bs_fd_o.valid <= false;
      end if;

      -- Push the bit to the fifo
      fifo_write(fifo => fifo, fifo_write_ptr=> fifo_write_ptr, next_bit => bit);

      -- Update last_transmitted_bit_polarity
      last_transmitted_bit_polarity <= bit.polarity;

      if (bit.bit_name /= stuff_bit) then
        bit_count           <= bit_count + 1;
        bit_count_monitored <= false;
        if (serializer_sourced_v) then
          mac_ser_o.ready <= true;
        end if;
        if (crc_eligible_v) then
          crc_o.valid <= true;
          crc_o.data  <= polarity_to_std_logic(bit.polarity);
        end if;
      end if;

    end procedure transmit_bit;

    -- Apply defaults.
    procedure apply_defaults is
    begin

      mac_ser_o.ready           <= false;
      mac_ser_o.transfer_status <= ongoing;
      monitored_bit_event       <= none;

      bs_fd_o.data  <= recessive;
      bs_fd_o.valid <= false;
      bs_fd_o.start <= false;

      crc_o.valid <= false;
      crc_o.data  <= '0';

      fce_o.transmitting             <= '0';
      fce_o.error                    <= '0';
      fce_o.primary_error            <= '0';
      fce_o.sending_error_flag       <= '0';
      fce_o.counters_unchanged       <= '0';
      fce_o.error_delimiter_too_late <= '0';
      fce_o.successful_transfer      <= '0';

      overload_condition <= false;

    end procedure apply_defaults;

    -- Shared behavior for bus_reintegration/intermission/bus_idle.
    procedure service_bus_quiet_state is
    begin

      if (state_entry_v) then
        -- Reset bit_count
        bit_count <= 0;
      elsif (sample_strobe_detected_v) then
        if (pcs_i.bus_polarity = recessive) then
          bit_count <= bit_count + 1;
        else
          -- Dominant sample breaks bus-idle / intermission run length.
          bit_count <= 0;
        end if;

        if (intermission_overload_v) then
          overload_condition <= true;
        end if;
      end if;

    end procedure service_bus_quiet_state;

    -- Emit active error/overload flag (6 dominant) then delimiter (8 recessive),
    -- and detect reactive overload at the last delimiter bit (ISO 6.6.21.3.2 b2).
    procedure service_error_or_overload_flag is
    begin

      fce_o.transmitting        <= '1';
      fce_o.sending_error_flag  <= '1';
      fce_o.error               <= '1';
      mac_ser_o.transfer_status <= disturbed;
      pcs_o.valid               <= true;

      if (state_entry_v) then
        bit_count <= 0;
      else
        if (bit_count < error_flag_width_c) then
          -- Overload flags are always active; error flags depend on FCE state.
          if (state = transmitting_error_flag and fce_i.error_passive) then
            next_bit_v := passive_error_flag_bit_c;
          else
            next_bit_v := active_error_flag_bit_c;
          end if;
        else
          next_bit_v := error_delimiter_bit_c;
        end if;

        pcs_o.data <= next_bit_v;

        if (sample_strobe_detected_v and not error_sequence_complete_v) then
          bit_count <= bit_count + 1;
        end if;

        if (delimiter_overload_v) then
          overload_condition <= true;
        end if;
      end if;

    end procedure service_error_or_overload_flag;

    -- Monitor the bus, react to events, and transmit the next bit on each strobe.
    procedure service_sample_strobe is
    begin

      -- Monitor bus once per bit position.
      if (not bit_count_monitored) then
        monitored_bit_info_v      := get_observed_mac_frame_bit_info(
                                                                     fifo => fifo, fifo_index => pcs_i.fifo_index,
                                                                     fifo_write_ptr => fifo_write_ptr,
                                                                     monitored_bit_polarity => pcs_i.bus_polarity,
                                                                     frame_params => mac_ser_i.frame_params
                                                                   );
        mac_ser_o.transfer_status <= monitored_bit_info_v.transfer_status;
        monitored_bit_event       <= monitored_bit_info_v.event_type;
        bit_count_monitored       <= true;
      else
        monitored_bit_info_v.event_type := none;
      end if;

      -- React to monitored event.
      case monitored_bit_info_v.event_type is
        when lost_arbitration =>
          was_previous_frame_tx <= false;

        when ack_detected =>
          was_previous_frame_tx <= true;
          ack_success_seen      <= true;

        when bit_error =>
          was_previous_frame_tx     <= true;
          fce_o.error               <= '1';
          mac_ser_o.transfer_status <= disturbed;

        when none =>
          -- ISO 11898-1 6.6.21.2 e): no dominant level in ACK slot is ACK error.
          if (bit_count = mac_ser_i.frame_params.ack_delimiter and (not ack_success_seen)) then
            mac_ser_o.transfer_status <= disturbed;
            monitored_bit_event       <= ack_error;
            was_previous_frame_tx     <= true;
          elsif (bs_fd_i.valid and bit_count < mac_ser_i.frame_params.crc_stop) then
            next_bit_v := (polarity => bs_fd_i.data, bit_name => stuff_bit);
            transmit_bit(next_bit_v);
          else
            next_bit_v := get_next_mac_frame_bit(
                                                 bit_count => bit_count,
                                                 mac_ser_to_fsm => mac_ser_i,
                                                 previous_polarity => last_transmitted_bit_polarity,
                                                 sbc => bs_fd_i.sbc,
                                                 crc => crc_i.crc
                                               );
            transmit_bit(next_bit_v);
          end if;

        when others =>
          null;

      end case;

    end procedure service_sample_strobe;

    -- One-time initialization when a new frame transmission begins.
    procedure initialize_frame_transmission is

      variable data_length_v : integer;
      variable crc_length_v  : integer;

    begin

      bit_count           <= 0;
      fifo                <= fifo_init;
      fifo_write_ptr      <= 0;
      ack_success_seen    <= false;
      bit_count_monitored <= false;
      bs_fd_o.start       <= true;

      -- Select CRC polynomial based on frame format and data length.
      data_length_v := dlc_to_data_length(
                                          dlc_t(to_integer(unsigned(mac_ser_i.frame_params.dlc_vector))),
                                          mac_ser_i.frame_params.format
                                        );
      crc_length_v  := get_crc_length(mac_ser_i.frame_params.format, data_length_v);

      case crc_length_v is
        when crc_15_length_c =>
          crc_o.crc_poly_select <= "00";
        when crc_17_length_c =>
          crc_o.crc_poly_select <= "01";
        when crc_21_length_c =>
          crc_o.crc_poly_select <= "10";
        when others =>
          crc_o.crc_poly_select <= "11";
      end case;

    end procedure initialize_frame_transmission;

    -- Apply reset values to all signals and outputs.
    procedure apply_reset is
    begin

      state          <= bus_reintegration;
      bit_count      <= 0;
      fifo_write_ptr <= 0;
      fifo           <= fifo_init;
      next_bit_v     := reset_mac_frame_bit_c;
      -- TODO: We are missing this reset type
      -- observed_bit_info_v           := reset_observed_mac_frame_bit_info_c;
      last_transmitted_bit_polarity <= pcs_i.bus_polarity;
      monitored_bit_event           <= none;
      was_previous_frame_tx         <= false;
      ack_success_seen              <= false;
      bit_count_monitored           <= false;
      prev_state                    <= bus_reintegration;
      overload_condition            <= false;

      pcs_o.valid <= false;
      pcs_o.data  <= reset_mac_frame_bit_c;

      mac_ser_o.ready           <= false;
      mac_ser_o.transfer_status <= ongoing;

      bs_fd_o.data  <= recessive;
      bs_fd_o.valid <= false;
      bs_fd_o.start <= false;

      crc_o.valid           <= false;
      crc_o.data            <= '0';
      crc_o.crc_poly_select <= "00";

      fce_o.transmitting             <= '0';
      fce_o.error                    <= '0';
      fce_o.primary_error            <= '0';
      fce_o.sending_error_flag       <= '0';
      fce_o.counters_unchanged       <= '0';
      fce_o.error_delimiter_too_late <= '0';
      fce_o.successful_transfer      <= '0';

    end procedure apply_reset;

  begin

    -- Output logic FSM
    if rising_edge(clk_i) then
      if (rst_i = '1') then
        -- Set reset values.
        apply_reset;
      else
        -- Evaluate guards.
        frame_transmitted_v       := bit_count = mac_ser_i.frame_params.eof_stop;
        sample_strobe_detected_v  := pcs_i.sample_strobe = '1';
        error_sequence_complete_v := bit_count >= error_flag_width_c + error_delimiter_width_c - 1;
        state_entry_v             := prev_state /= state;
        -- ISO 6.6.21.3.2 b1: dominant during first 2 bits of intermission
        intermission_overload_v := sample_strobe_detected_v and state = intermission
                                   and bit_count < 2 and pcs_i.bus_polarity = dominant;
        -- ISO 6.6.21.3.2 b2: dominant at last bit of error/overload delimiter
        delimiter_overload_v := sample_strobe_detected_v and error_sequence_complete_v
                                and pcs_i.bus_polarity = dominant;

        -- Update states.
        prev_state <= state;
        state      <= next_state;

        -- Set defaults.
        apply_defaults;

        case state is
          when bus_reintegration | intermission | bus_idle =>
            service_bus_quiet_state;

          when transmitting_frame =>
            -- Inform PCS and FCE that a frame is being transmitted.
            fce_o.transmitting <= '1';
            pcs_o.valid        <= true;

            if (state_entry_v) then
              initialize_frame_transmission;
            elsif (frame_transmitted_v) then
              mac_ser_o.transfer_status <= transmitted;
              was_previous_frame_tx     <= true;
              fce_o.successful_transfer <= '1';
            elsif (sample_strobe_detected_v) then
              service_sample_strobe;
            end if;

          when transmitting_error_flag | transmitting_overload_flag =>
            service_error_or_overload_flag;

          when others =>
        end case;
      end if;
    end if;

  end process output_logic;

end architecture rtl;
