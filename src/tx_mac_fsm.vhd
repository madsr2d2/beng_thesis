--------------------------------------------------------------------------------
-- Title      : CAN MAC Transmit FSM
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : tx_mac_fsm.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Central coordinator for CAN frame transmission. Bridges:
--   - tx_mac_ser (serializer): provides raw data as polarity_t + frame_params
--   - bit_stuffer_fd: detects stuff bits, outputs SBC (Gray+parity encoded)
--   - tx_pcs (physical layer): transmits bits with correct timing
--
-- PCS synchronization model:
--   The FSM always keeps the NEXT bit prepared on pcs_o.frame_bit.
--   PCS latches frame_bit at each bit boundary and pulses sp.
--   On sp: the prepared bit has been sampled; FSM pushes it to FIFO
--   and prepares the next bit.
--
-- Design notes:
--   - Stuff bit detection is delegated to bit_stuffer_fd (single responsibility).
--     The FSM reads stuff_bit_valid (level) to decide what to prepare next.
--   - Circular buffer FIFO: only 1 entry written per push (O(1) vs O(n) shift).
--   - SP strobe handling consolidated into a single block per state.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

entity tx_mac_fsm is
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- Serializer interface
    mac_ser_i : in    tx_mac_ser_to_fsm_if_t;
    mac_ser_o : out   tx_mac_fsm_to_ser_if_t;

    -- PCS interface
    pcs_i : in    pcs_to_mac_if_t;
    pcs_o : out   mac_to_pcs_if_t;

    -- Bit stuffer FD interface
    bs_fd_i : in    bs_fd_to_mac_fsm_if_t;
    bs_fd_o : out   mac_fsm_to_bs_fd_if_t;

    -- Fault Confinement Entity interface (ISO 11898-1 Table 16/17)
    fce_i : in    fce_to_mac_if_t;
    fce_o : out   mac_to_fce_if_t
  );
end entity tx_mac_fsm;

architecture rtl of tx_mac_fsm is

  -- FSM state register
  signal mac_state : tx_mac_fsm_state_t; -- TODO: We need a waiting_on_bus_idle state. The fsm should enter this state when in has lost arbitration or completed a frame/error flag
  -- TODO: Or maybe better an bus_is_idle process that sets the bus_is_idle flag when the bus has been observed idle.

  -- Shared counter: frame bit position during transmitting, error/delimiter bit count otherwise
  signal bit_count : integer range 0 to max_mac_frame_length_c;

  -- Transmitted bits circular FIFO for bus monitoring
  signal transmitted_bits_fifo : transmitted_bits_fifo_t;
  signal fifo_write_ptr        : fifo_write_ptr_t;

  -- Previous polarity for stuff bit context
  signal previous_polarity : polarity_t;

  -- CRC register (placeholder zeros — CRC module not yet implemented)
  signal crc_reg : crc_vector_t;

  -- SBC from bit stuffer
  signal sbc_reg : sbc_t;

  -- ACK received flag
  signal ack_received : boolean;

  -- Prepared bit: the next bit sitting on pcs_o.frame_bit waiting to be consumed
  signal prepared_bit : mac_frame_bit_t;
  signal bit_prepared : boolean;

  -- Flag to detect EOF was the last prepared bit (check after PCS consumes it)
  signal eof_pending : boolean;

begin

  p_mac_fsm : process (clk) is

    variable frame_bit_v   : mac_frame_bit_t;
    variable observation_v : observed_mac_frame_bit_info_t;
    variable fifo_v        : transmitted_bits_fifo_t;
    variable write_ptr_v   : fifo_write_ptr_t;

  begin

    if rising_edge(clk) then
      if (rst = '1') then
        mac_state             <= bus_idle;
        bit_count             <= 0;
        transmitted_bits_fifo <= fifo_init;
        fifo_write_ptr        <= 0;
        previous_polarity     <= dominant;
        crc_reg               <= (others => '0');
        sbc_reg               <= (others => '0');
        ack_received          <= false;
        bit_prepared          <= false;
        prepared_bit          <= (polarity => unknown, bit_name => unknown);
        eof_pending           <= false;

        mac_ser_o.transfer_status <= ongoing;
        mac_ser_o.ready           <= '0';

        pcs_o.frame_bit    <= (polarity => unknown, bit_name => unknown);
        pcs_o.data_request <= '0';

        bs_fd_o.data        <= dominant;
        bs_fd_o.data_valid  <= '0';
        bs_fd_o.frame_reset <= '0';

        fce_o.transmitting             <= '0';
        fce_o.error                    <= '0';
        fce_o.primary_error            <= '0';
        fce_o.sending_error_flag       <= '0';
        fce_o.counters_unchanged       <= '0';
        fce_o.error_delimiter_too_late <= '0';
        fce_o.successful_transfer      <= '0';
      else
        -- Defaults: clear one-shot signals
        mac_ser_o.ready     <= '0';
        bs_fd_o.data_valid  <= '0';
        bs_fd_o.frame_reset <= '0';

        fce_o.error                    <= '0';
        fce_o.primary_error            <= '0';
        fce_o.counters_unchanged       <= '0';
        fce_o.error_delimiter_too_late <= '0';
        fce_o.successful_transfer      <= '0';

        sbc_reg <= bs_fd_i.sbc;

        case mac_state is

          -- =================================================================
          -- IDLE
          -- =================================================================
          when bus_idle =>
            bit_count             <= 0;
            transmitted_bits_fifo <= fifo_init;
            fifo_write_ptr        <= 0;
            previous_polarity     <= dominant;
            bit_prepared          <= false;
            eof_pending           <= false;

            ack_received              <= false;
            crc_reg                   <= (others => '0');
            sbc_reg                   <= (others => '0');
            pcs_o.data_request        <= '0';
            mac_ser_o.transfer_status <= ongoing;
            fce_o.transmitting        <= '0';
            fce_o.sending_error_flag  <= '0';

            if (mac_ser_i.valid = '1') then
              mac_state <= transmitting_frame;

              bs_fd_o.frame_reset <= '1';

              -- Get SOF (bit_count=0)
              frame_bit_v := get_next_mac_frame_bit(
                bit_count         => 0,
                mac_ser_to_fsm    => mac_ser_i,
                previous_polarity => dominant,
                sbc               => (others => '0'),
                crc               => (others => '0')
              );

              -- Put SOF on frame_bit for PCS to latch on idle->transmitting
              pcs_o.frame_bit    <= frame_bit_v;
              pcs_o.data_request <= '1';
              prepared_bit       <= frame_bit_v;
              previous_polarity  <= frame_bit_v.polarity;

              -- Feed SOF to bit stuffer
              bs_fd_o.data       <= frame_bit_v.polarity;
              bs_fd_o.data_valid <= '1';

              -- Push SOF to FIFO
              fifo_v                := fifo_init;
              write_ptr_v           := 0;
              fifo_write(fifo_v, write_ptr_v, frame_bit_v);
              transmitted_bits_fifo <= fifo_v;
              fifo_write_ptr        <= write_ptr_v;

              bit_count    <= 1;
              bit_prepared <= false;

            end if;

          -- =================================================================
          -- TRANSMITTING
          -- =================================================================
          when transmitting_frame =>
            fce_o.transmitting <= '1';

            -- ---------------------------------------------------------------
            -- SP strobe: monitoring + FIFO push + EOF check + trigger next
            -- ---------------------------------------------------------------
            if (pcs_i.sp = '1') then
              -- 1. SP monitoring (error/ACK/arbitration)
              observation_v := get_observed_mac_frame_bit_info(
                                                               fifo_index                  => 0,
                                                               fifo_index  => transmitted_bits_fifo,
                                                               fifo_write_ptr              => fifo_write_ptr,
                                                               monitored_bit_polarity => pcs_i.bus_polarity,
                                                               frame_params           => mac_ser_i.frame_params
                                                             );

              case observation_v.event_type is
                when bit_error =>
                  mac_state   <= transmitting_error_flag;
                  bit_count   <= 0;
                  fce_o.error <= '1';
                when lost_arbitration =>
                  mac_ser_o.transfer_status <= lost_arbitration;
                  mac_state                 <= bus_idle;
                when ack_detected =>
                  ack_received <= true;
                when ack_error =>
                  mac_state   <= transmitting_error_flag;
                  bit_count   <= 0;
                  fce_o.error <= '1';
                when none =>
                  null;
              end case;

              -- 2. Push consumed bit to FIFO
              fifo_v                := transmitted_bits_fifo;
              write_ptr_v           := fifo_write_ptr;
              fifo_write(fifo_v, write_ptr_v, prepared_bit);
              transmitted_bits_fifo <= fifo_v;
              fifo_write_ptr        <= write_ptr_v;

              -- 3. EOF completion check
              if (eof_pending) then
                if (ack_received) then
                  mac_ser_o.transfer_status <= transmitted;
                  fce_o.successful_transfer <= '1';
                else
                  mac_ser_o.transfer_status <= disturbed;
                end if;
                pcs_o.data_request <= '0';
                mac_state          <= bus_idle;
              end if;

              -- 4. Trigger prepare of next bit
              bit_prepared <= false;
            end if;

            -- ---------------------------------------------------------------
            -- SSP monitoring (data phase with TDC)
            -- ---------------------------------------------------------------
            if (pcs_i.ssp = '1') then
              observation_v := get_observed_mac_frame_bit_info(
                                                               fifo_index                  => pcs_i.fifo_index,
                                                               fifo_index  => transmitted_bits_fifo,
                                                               fifo_write_ptr              => fifo_write_ptr,
                                                               monitored_bit_polarity => pcs_i.bus_polarity,
                                                               frame_params           => mac_ser_i.frame_params
                                                             );

              if (observation_v.event_type = bit_error) then
                mac_state   <= transmitting_error_flag;
                bit_count   <= 0;
                fce_o.error <= '1';
              end if;
            end if;

            -- ---------------------------------------------------------------
            -- Prepare next bit (runs once after idle transition or SP strobe)
            -- Checks bit_stuffer_fd for stuff bit requirement
            -- ---------------------------------------------------------------
            if (not bit_prepared and not eof_pending) then
              if (bs_fd_i.stuff_bit_valid = '1') then
                -- STUFF BIT: bit stuffer detected 5 consecutive same-polarity
                frame_bit_v := (polarity => bs_fd_i.stuff_bit, bit_name => stuff_bit);

                pcs_o.frame_bit   <= frame_bit_v;
                prepared_bit      <= frame_bit_v;
                previous_polarity <= frame_bit_v.polarity;
                bit_prepared      <= true;

                -- Feed stuff bit back to bit stuffer (resets its counter)
                bs_fd_o.data       <= bs_fd_i.stuff_bit;
                bs_fd_o.data_valid <= '1';

              else
                -- REAL FRAME BIT
                frame_bit_v := get_next_mac_frame_bit(
                                                      bit_count         => bit_count,
                                                      mac_ser_to_fsm    => mac_ser_i,
                                                      previous_polarity => previous_polarity,
                                                      sbc               => sbc_reg,
                                                      crc               => crc_reg
                                                    );

                pcs_o.frame_bit   <= frame_bit_v;
                prepared_bit      <= frame_bit_v;
                previous_polarity <= frame_bit_v.polarity;

                -- Feed to bit stuffer for consecutive tracking
                bs_fd_o.data       <= frame_bit_v.polarity;
                bs_fd_o.data_valid <= '1';

                -- Only consume serializer data for data field
                if (frame_bit_v.bit_name = data_bit) then
                  mac_ser_o.ready <= '1';
                end if;

                bit_count    <= bit_count + 1;
                bit_prepared <= true;

                -- Mark EOF pending (frame complete after PCS consumes last EOF bit)
                if (bit_count >= mac_ser_i.frame_params.eof_stop - 1) then
                  eof_pending <= true;
                end if;

              end if;
            end if;

          -- =================================================================
          -- ERROR FLAG
          -- =================================================================
          when transmitting_error_flag =>
            fce_o.transmitting       <= '1';
            fce_o.sending_error_flag <= '1';

            if (fce_i.error_passive = '1') then
              pcs_o.frame_bit <= passive_error_flag_bit_c;
            else
              pcs_o.frame_bit <= active_error_flag_bit_c;
            end if;
            pcs_o.data_request <= '1';

            if (pcs_i.sp = '1' and fce_i.error_passive = '0' and pcs_i.bus_polarity = dominant) then
              fce_o.primary_error <= '1';
            end if;

            if (pcs_i.sp = '1') then
              if (bit_count >= error_flag_width_c - 1) then
                bit_count <= 0;
                mac_state <= error_delimiter;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -- =================================================================
          -- ERROR DELIMITER
          -- =================================================================
          when error_delimiter =>
            fce_o.transmitting       <= '1';
            fce_o.sending_error_flag <= '0';
            pcs_o.frame_bit          <= error_delimiter_bit_c;
            pcs_o.data_request       <= '1';

            if (pcs_i.sp = '1' and pcs_i.bus_polarity = dominant) then
              fce_o.error_delimiter_too_late <= '1';
            end if;

            if (pcs_i.sp = '1') then
              if (bit_count >= error_delimiter_width_c - 1) then
                bit_count <= 0;
                mac_state <= intermission;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -- =================================================================
          -- INTERMISSION
          -- =================================================================
          when intermission =>
            fce_o.transmitting       <= '1';
            fce_o.sending_error_flag <= '0';
            pcs_o.frame_bit          <= intermission_bit_c;
            pcs_o.data_request       <= '1';

            if (pcs_i.sp = '1') then
              if (bit_count >= intermission_width_c - 1) then
                if (fce_i.error_passive = '1') then
                  bit_count <= 0;
                  mac_state <= suspend_transmission;
                else
                  mac_ser_o.transfer_status <= disturbed;
                  pcs_o.data_request        <= '0';
                  mac_state                 <= bus_idle;
                end if;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -- =================================================================
          -- SUSPEND TRANSMISSION
          -- =================================================================
          when suspend_transmission =>
            fce_o.transmitting       <= '1';
            fce_o.sending_error_flag <= '0';
            pcs_o.frame_bit          <= intermission_bit_c;
            pcs_o.data_request       <= '1';

            if (pcs_i.sp = '1') then
              if (bit_count >= suspend_transmission_width_c - 1) then
                mac_ser_o.transfer_status <= disturbed;
                pcs_o.data_request        <= '0';
                mac_state                 <= bus_idle;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          when others =>
            mac_state <= bus_idle;

        end case;
      end if;
    end if;

  end process p_mac_fsm;

end architecture rtl;
