
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

entity tx_mac_fsm_v2 is
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
end entity tx_mac_fsm_v2;

architecture rtl of tx_mac_fsm_v2 is

  signal bit_count                     : bit_count_t;
  signal state                         : tx_mac_fsm_state_t;
  signal next_state                    : tx_mac_fsm_state_t;
  signal fifo                          : transmitted_bits_fifo_t;
  signal fifo_write_ptr                : fifo_write_ptr_t;
  signal last_transmitted_bit_polarity : polarity_t;
  signal monitored_bit_event           : tx_mac_monitor_event_t;
  signal was_previous_frame_tx         : boolean;

begin

  next_state_logic : process (all) is
  begin

    -- Default state assignment
    if (rst_i = '1') then
      next_state <= bus_reintegration;
    else
      next_state <= state;
    end if;

    case state is
      when bus_reintegration =>

        if (bit_count = bus_idle_condition_width_c - 1) then
          next_state <= bus_idle;
        end if;

      when intermission =>

        if (bit_count = intermission_width_c - 1) then
          if (fce_i.error_passive and was_previous_frame_tx) then -- ISO 11898-1 6.6.7.4
            next_state <= suspend_transmission;
          else
            next_state <= bus_idle;
          end if;
        end if;

      when suspend_transmission =>

        if (bit_count = suspend_transmission_width_c - 1) then
          next_state <= bus_idle;
        end if;

      when bus_idle =>

        if (mac_ser_i.valid) then
          next_state <= transmitting_frame;
        end if;

      when transmitting_frame =>

        if (monitored_bit_event = ack_detected or monitored_bit_event = lost_arbitration) then
          next_state <= intermission;
        elsif (monitored_bit_event = bit_error or monitored_bit_event = ack_error) then
          next_state <= transmitting_error_flag;
        end if;

      when transmitting_error_flag | transmitting_overload_flag =>

        if (bit_count = error_flag_width_c + error_delimiter_width_c - 1) then
          next_state <= intermission;
        end if;

      when others =>

    end case;

  end process next_state_logic;

  output_logic : process (clk_i) is

    variable next_bit_v           : mac_frame_bit_t;
    variable monitored_bit_info_v : observed_mac_frame_bit_info_t;

    procedure transmit_bit (
      bit : in mac_frame_bit_t
    ) is
    begin

      -- Send the bit to the PCS
      pcs_o.valid <= true;
      pcs_o.data  <= bit;

      -- Send bit to bit stuffer
      bs_fd_o.valid <= true;
      bs_fd_o.data  <= bit.polarity;

      -- Push the bit to the fifo
      fifo_write(fifo => fifo, fifo_write_ptr=> fifo_write_ptr, next_bit => bit);

      -- Update last_transmitted_bit_polarity
      last_transmitted_bit_polarity <= bit.polarity;

      if (bit.bit_name /= stuff_bit) then
        -- Increment bit count if not a stuff bit
        bit_count <= bit_count + 1;
        -- Signal mac_ser to shift out next frame bit
        mac_ser_o.ready <= true;
        -- Send bit to crc if we have not entered the CRC field of the frame
        if (bit_count < mac_ser_i.frame_params.crc_start and bit.bit_name /= fixed_stuff_bit) then
          crc_o.valid <= true;
          crc_o.data  <= polarity_to_std_logic(bit.polarity);
        end if;
      end if;

    end procedure transmit_bit;

    procedure monitor_bus_bit is
    begin

      monitored_bit_info_v := get_observed_mac_frame_bit_info(
                                                              fifo => fifo, fifo_index => pcs_i.fifo_index,
                                                              fifo_write_ptr => fifo_write_ptr,
                                                              monitored_bit_polarity => pcs_i.bus_polarity,
                                                              frame_params => mac_ser_i.frame_params
                                                            );
      -- Rout transfer status to mac_ser
      mac_ser_o.transfer_status <= monitored_bit_info_v.transfer_status;
      monitored_bit_event       <= monitored_bit_info_v.event_type;

    end procedure monitor_bus_bit;

    -- Apply deterministic per-cycle defaults before state-specific overrides.
    procedure apply_cycle_defaults is
    begin

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

    end procedure apply_cycle_defaults;

    -- Shared behavior for bus_reintegration/intermission/bus_idle.
    procedure service_bus_quiet_state is
    begin

      -- Inform the PCS layer that we are not sending a frame
      pcs_o.valid               <= false;
      fce_o.transmitting        <= '0';
      mac_ser_o.transfer_status <= ongoing;
      mac_ser_o.ready           <= false;

      if (state /= next_state) then
        -- Reset bit_count and fifo when entering a new state
        bit_count      <= 0;
        fifo           <= fifo_init;
        fifo_write_ptr <= 0;
        bs_fd_o.start  <= true;
      elsif (pcs_i.sp = '1' and pcs_i.bus_polarity = recessive) then
        -- Increment bit_count on successive recessive bits within the same state
        bit_count <= bit_count + 1;
      else
        bit_count <= 0;
      end if;

    end procedure service_bus_quiet_state;

    -- Pulse FCE status lines derived from monitor events.
    procedure pulse_fce_monitor_flags (
      event : in tx_mac_monitor_event_t
    ) is
    begin

      case event is
        when bit_error | ack_error =>
          fce_o.error <= '1';
        when others =>
          null;
      end case;

    end procedure pulse_fce_monitor_flags;

    -- Emit active error/overload flag then delimiter while in error states.
    procedure emit_error_state_bit is
    begin

      fce_o.transmitting        <= '1';
      fce_o.sending_error_flag  <= '1';
      fce_o.error               <= '1';
      mac_ser_o.transfer_status <= disturbed;
      pcs_o.valid               <= true;

      if (bit_count < error_flag_width_c) then
        next_bit_v := active_error_flag_bit_c;
      else
        next_bit_v := error_delimiter_bit_c;
      end if;

      pcs_o.data <= next_bit_v;

      if (pcs_i.sp = '1') then
        fifo_write(fifo => fifo, fifo_write_ptr=> fifo_write_ptr, next_bit => next_bit_v);
        bit_count <= bit_count + 1;
      end if;

    end procedure emit_error_state_bit;

    -- Prepare per-frame context while transmitting (status + CRC polynomial select).
    procedure prepare_transmitting_frame_context is

      variable data_length_v : integer;
      variable crc_length_v  : integer;

    begin

      fce_o.transmitting <= '1';

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

    end procedure prepare_transmitting_frame_context;

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        state                         <= bus_reintegration;
        bit_count                     <= 0;
        fifo_write_ptr                <= 0;
        fifo                          <= fifo_init;
        next_bit_v                    := reset_mac_frame_bit_c;
        last_transmitted_bit_polarity <= pcs_i.bus_polarity;
        monitored_bit_event           <= none;
        was_previous_frame_tx         <= false;

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

      else
        -- defaults
        state <= next_state;
        apply_cycle_defaults;

        case state is
          when bus_reintegration | intermission | bus_idle =>
            service_bus_quiet_state;

          when transmitting_frame =>
            prepare_transmitting_frame_context;

            if (pcs_i.sp = '1' or pcs_i.ssp = '1') then
              -- Monitor bus bit
              monitor_bus_bit;
              pulse_fce_monitor_flags(monitored_bit_info_v.event_type);

              if (monitored_bit_info_v.event_type = lost_arbitration) then
                was_previous_frame_tx <= false;
              elsif (monitored_bit_info_v.event_type = ack_detected or
                     monitored_bit_info_v.event_type = bit_error or
                     monitored_bit_info_v.event_type = ack_error) then
                was_previous_frame_tx <= true;
              end if;

              if (monitored_bit_info_v.event_type = none) then
                -- next_state_logic changes state based on the event_type
                if (bs_fd_i.valid) then
                  -- Get stuff bit if its time for stuffing
                  next_bit_v := (polarity => bs_fd_i.data, bit_name => stuff_bit);
                  -- Transmit bit to PCS
                  transmit_bit(next_bit_v);
                elsif (mac_ser_i.valid) then
                  -- Else get next frame bit
                  next_bit_v := get_next_mac_frame_bit(
                                                       bit_count => bit_count,
                                                       mac_ser_to_fsm => mac_ser_i,
                                                       previous_polarity => last_transmitted_bit_polarity,
                                                       sbc => bs_fd_i.sbc,
                                                       crc => crc_i.crc
                                                     );
                  -- Transmit bit to PCS
                  transmit_bit(next_bit_v);
                end if;
              end if;
            end if;

          when transmitting_error_flag | transmitting_overload_flag =>
            emit_error_state_bit;

          when others =>

        end case;
      end if;
    end if;

  end process output_logic;

end architecture rtl;
