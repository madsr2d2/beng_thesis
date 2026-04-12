--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   MAC FSM for CAN/CAN-FD transmission side.
--                Coordinates serialization, bit stuffing, CRC generation, and
--                PCS control.
--                Frame transmission is split into three pipelined states:
--                s_frame_init  - compute frame_params, drive SOF
--                s_monitor_bit - wait for SP/SSP, evaluate get_bit_info
--                s_transmit_bit - drive next bit via get_mac_frame_bit
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-23  TMYAES    [TRIT-4355] Initial implementation
--
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
    bs_i   : in    t_can_mac_fsm_bs_if_s2m;
    bs_o   : out   t_can_mac_fsm_bs_if_m2s;
    bs_rst : out   std_logic;
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
    s_flag
  );

  type t_flag_type is (active_error, passive_error, overload);

  ---------------------------------------------------------------------------
  -- Registered state signals
  ---------------------------------------------------------------------------
  signal state                         : t_fsm_state;
  signal flag_type                     : t_flag_type;
  signal bit_count                     : natural range 0 to c_max_mac_frame_length;
  signal polarity_history              : std_logic_vector(c_tdc_polarity_depth - 1 downto 0);
  signal last_transmitted_bit          : t_mac_frame_bit;
  signal was_previous_frame_tx         : boolean;
  signal ack_success_seen              : boolean;
  signal ssp_error_pending             : boolean;

  -- Fault confinement tracking
  signal ack_error_caused_flag     : boolean;
  signal dominant_seen_during_flag : boolean;
  signal dominant_run_count        : natural range 0 to 15;
  signal primary_error_sent        : boolean;
  signal skip_sof : boolean;
  signal fsb_active : std_logic;
  signal frame_params : t_frame_params;
  signal bit_info : t_bit_info; -- Debug signal (Unused in the rtl)
begin
  p_fsm : process (clk_i) is
    variable v_next_bit : t_mac_frame_bit;    -- Holds next calculated bit
    variable v_frame_params : t_frame_params; -- Holds frame parameters for current frame
    variable v_enter_error_flag : boolean;    -- Common error-flag entry guard
    variable v_bit_info : t_bit_info;         -- Bus monitor result
  begin
    if rising_edge(clk_i) then
      if (rst_i = '1') then
        state                         <= s_bus_reintegration;
        flag_type                     <= active_error;
        bit_count                     <= 0;
        polarity_history              <= (others => c_recessive);
        last_transmitted_bit          <= c_reset_mac_frame_bit;
        was_previous_frame_tx         <= false;
        ack_success_seen              <= false;
        ssp_error_pending             <= false;
        ack_error_caused_flag         <= false;
        dominant_seen_during_flag     <= false;
        dominant_run_count            <= 0;
        primary_error_sent            <= false;
        skip_sof                      <= false;
        fsb_active                    <= '0';
        frame_params                  <= c_frame_params_reset;

        mac_ser_o <= c_ser_fsm_if_d2s_reset;
        pcs_o     <= c_mac_to_pcs_if_reset;
        bs_o   <= c_mac_fsm_to_bs_fd_if_reset;
        bs_rst <= '0';
        crc_o     <= c_mac_fsm_to_crc_if_reset;
        crc_rst   <= '0';
        fce_o     <= c_mac_to_fce_if_reset;
      else
        ---------------------------------------------------------------------
        -- Pulse defaults (cleared every cycle, set only when active)
        ---------------------------------------------------------------------
        bs_o            <= c_mac_fsm_to_bs_fd_if_reset;
        mac_ser_o.ready <= '0';
        crc_o.valid_cc     <= '0';
        crc_o.valid_fd  <= '0';
        bs_rst          <= '0';
        crc_rst         <= '0';

        bs_o.fsb_en <= fsb_active;
        fce_o.error                       <= '0';
        fce_o.primary_error               <= '0';
        fce_o.counters_unchanged          <= '0';
        fce_o.successful_transfer         <= '0';
        fce_o.error_delimiter_too_late    <= '0';
        fce_o.sending_error_overload_flag <= '0';

        ---------------------------------------------------------------------
        -- Quiet-state defaults (bus_reintegration, intermission, suspend, idle)
        ---------------------------------------------------------------------
        if (state = s_bus_reintegration or state = s_intermission or state = s_suspend_transmission or state = s_bus_idle) then
          pcs_o.valid               <= '0';
          pcs_o.polarity            <= c_recessive;
          pcs_o.use_data_rate       <= '0';
          pcs_o.start_tdc           <= '0';
          fce_o.transmitting        <= '0';
          ssp_error_pending         <= false;
          mac_ser_o.transfer_status <= c_ongoing;
        end if;

        ---------------------------------------------------------------------
        -- State machine
        ---------------------------------------------------------------------
        case state is
          -----------------------------------------------------------------
          -- Wait for idle condition(s): ISO 11898-1: 6.6.7.5
          -----------------------------------------------------------------
          when s_bus_reintegration =>
            -- Set bus_integration_bit
            last_transmitted_bit <= (c_recessive, bus_integration_bit);
            -- Idle count
            if (pcs_i.sp = '1') then
              if (pcs_i.bus_polarity = c_recessive) then
                if (bit_count < c_bus_idle_condition_width - 1) then
                  bit_count <= bit_count + 1;
                else
                  state     <= s_bus_idle;
                  bit_count <= 0;
                end if;
              else
                bit_count <= 0;
              end if;
            end if;

          -----------------------------------------------------------------
         -- Intermission state: ISO 11898-1: 6.6.7.2
          -----------------------------------------------------------------
          when s_intermission =>
            -- Set intermission_bit
            last_transmitted_bit <= (c_recessive, intermission_bit);
            -- Intermission logic
            if (pcs_i.sp = '1') then
              if (pcs_i.bus_polarity = c_dominant) then
                if (bit_count < c_intermission_width - 1) then
                  -- ISO 11898-1: 6.6.21.3.2 b) - dominant during first two bits
                  state                     <= s_flag;
                  flag_type                 <= overload;
                  bit_count                 <= 0;
                  dominant_seen_during_flag <= false;
                  dominant_run_count        <= 0;
                  primary_error_sent        <= false;
                else
                  -- ISO 11898-1: 6.6.7.2 / 6.6.8 - SOF at 3rd bit
                  if (mac_ser_i.valid = '1' and (fce_i.error_passive_request = '0' or not was_previous_frame_tx)) then
                    state     <= s_frame_init;
                    bit_count <= 0;
                    skip_sof  <= true;
                    bs_rst <= '1';
                    crc_rst   <= '1';
                  else
                    state     <= s_bus_idle;
                    bit_count <= 0;
                  end if;
                end if;
              else -- Recessive
                if (bit_count < c_intermission_width - 1) then
                  bit_count <= bit_count + 1;
                else
                  -- ISO 11898-1: 6.6.7.4 / 6.6.7.3 - Full intermission completed
                  if (fce_i.error_passive_request = '1' and was_previous_frame_tx) then
                    state <= s_suspend_transmission;
                  else
                    state <= s_bus_idle;
                  end if;
                  bit_count <= 0;
                end if;
              end if;
            end if;

          -----------------------------------------------------------------
          -- ISO 11898-1: 6.6.7.4 - error-passive nodes that transmitted
          -- the previous frame shall suspend for 8 additional bit times.
          -----------------------------------------------------------------
          when s_suspend_transmission =>
            -- Set suspend_transmission_bit
            last_transmitted_bit <= (c_recessive, suspend_transmission_bit);
            if (pcs_i.sp = '1') then
              if (pcs_i.bus_polarity = c_recessive) then
                if (bit_count < c_suspend_transmission_width - 1) then
                  bit_count <= bit_count + 1;
                else
                  state     <= s_bus_idle;
                  bit_count <= 0;
                end if;
              else
                bit_count <= 0;
              end if;
            end if;

          -----------------------------------------------------------------
          -- ISO 11898-1: 6.6.7.3 - bus idle, node may start transmission.
          -----------------------------------------------------------------
          when s_bus_idle =>
            last_transmitted_bit <= (c_recessive, idle_bit);
              if (mac_ser_i.valid = '1' and pcs_i.sp = '1') then
                state     <= s_frame_init;
                bit_count <= 0;
                bs_rst <= '1';
                crc_rst   <= '1';
              end if;

          -----------------------------------------------------------------
          -- Compute frame parameters, initialize counters, drive SOF.
          -- When skip_sof is true (ISO 11898-1: 6.6.7.2 / 6.6.8), the
          -- SOF has already been observed on the bus. The first ID bit
          -- (ser_data) is driven onto PCS instead.
          -----------------------------------------------------------------
          when s_frame_init =>
            mac_ser_o           <= c_ser_fsm_if_d2s_reset;
            crc_o               <= c_mac_fsm_to_crc_if_reset;
            fce_o               <= c_mac_to_fce_if_reset;
            fce_o.transmitting  <= '1';
            pcs_o.valid         <= '1';
            pcs_o.use_data_rate <= '0';
            pcs_o.start_tdc     <= '0';

            -- Calculate frame_params
            v_frame_params        := get_frame_params(mac_ser_i.llc_metadata);
            frame_params          <= v_frame_params;
            crc_o.crc_poly_select <= v_frame_params.crc_poly_select;

            polarity_history          <= (0 => c_dominant, others => c_recessive);
            ack_success_seen          <= false;
            ssp_error_pending         <= false;
            ack_error_caused_flag     <= false;
            dominant_seen_during_flag <= false;
            dominant_run_count        <= 0;


            -- Feed SOF to BS/CRC (both paths need it)
            bs_o.valid <= '1';
            bs_o.data  <= c_dominant;
            crc_o.valid_cc    <= '1';
            crc_o.valid_fd <= '1';
            crc_o.data_cc  <= c_dominant;
            crc_o.data_fd  <= c_dominant;

            if (skip_sof) then
              -- ISO 11898-1: 6.6.8 - SOF was the 3rd intermission dominant.
              -- Drive first ID bit on PCS; SOF already on the bus.
              pcs_o.polarity       <= mac_ser_i.data;
              bit_count            <= 1;
              mac_ser_o.ready      <= '1';
              last_transmitted_bit <= (mac_ser_i.data, base_id_bit);
            else
              pcs_o.polarity       <= c_dominant;
              bit_count            <= 0;
              last_transmitted_bit <= c_sof_bit;
            end if;
            state <= s_monitor_bit;

          -----------------------------------------------------------------
          -- Wait for SP/SSP, evaluate get_bit_info, handle errors or
          -- proceed to s_transmit_bit.
          -----------------------------------------------------------------
          when s_monitor_bit =>
            fce_o.transmitting <= '1';
            v_enter_error_flag := false;

            -- Feed first ID bit to BS/CRC after skip_sof (ISO 6.6.8).
            if (skip_sof) then
              bs_o.valid <= '1';
              bs_o.data  <= last_transmitted_bit.polarity;
              crc_o.valid_cc    <= '1';
              crc_o.valid_fd <= '1';
              crc_o.data_cc  <= last_transmitted_bit.polarity;
              crc_o.data_fd  <= last_transmitted_bit.polarity;
              skip_sof      <= false;
            end if;

            -- EOF completion: bit_count was set by s_transmit_bit
            if (bit_count = frame_params.crc_delimiter + c_eof_start_offset + c_eof_field_width) then
              -- ISO 11898-1: 8.1.4.2 rule g) - successful transmission.
              mac_ser_o.transfer_status <= c_transmitted;
              was_previous_frame_tx     <= true;
              fce_o.successful_transfer <= '1';
              state                     <= s_intermission;
              bit_count                 <= 0;

            elsif (pcs_i.sp = '1' or pcs_i.ssp = '1') then

              -- Evaluate bus monitor (SP or SSP)
              v_bit_info := get_bit_info(
                last_transmitted_bit.bit_name, 
                polarity_history, 
                to_integer(unsigned(pcs_i.tdc_delay)), 
                pcs_i.bus_polarity, 
                mac_ser_i.llc_metadata);

              bit_info <= v_bit_info; -- Debug signal 

              -- SSP: latch pending error (ISO 7.3.4)
              if (pcs_i.ssp = '1') then
                ssp_error_pending <= ssp_error_pending or (v_bit_info.event_type = bit_error);
              end if;

              -- Sample Point processing (ISO 6.6.21.3)
              if (pcs_i.sp = '1') then
                mac_ser_o.transfer_status <= v_bit_info.transfer_status;

                -- Check for bit error (including deferred SSP)
                if (ssp_error_pending or v_bit_info.event_type = bit_error or v_bit_info.event_type = ack_error) then
                  v_enter_error_flag := true;
                else
                  case v_bit_info.event_type is
                    when lost_arbitration =>
                      was_previous_frame_tx <= false;
                      bit_count             <= 0;
                      state                 <= s_intermission;

                    when ack_detected =>
                      was_previous_frame_tx <= true;
                      ack_success_seen      <= true;
                      state                 <= s_transmit_bit;

                    when none =>
                      -- ACK error detection: no dominant seen during entire ACK slot
                      if (bit_count = frame_params.crc_delimiter + c_ack_delimiter_offset and not ack_success_seen) then
                        v_enter_error_flag    := true;
                        ack_error_caused_flag <= true;
                      else
                        state <= s_transmit_bit;
                      end if;
                    when others =>
                  end case;
                end if;
                ssp_error_pending <= false;
              end if;

              -- Global error-flag entry
              if (v_enter_error_flag) then
                fce_o.error               <= '1';
                pcs_o.polarity            <= c_passive_error_flag_bit.polarity when fce_i.error_passive_request = '1' else c_active_error_flag_bit.polarity;
                pcs_o.valid               <= '1';
                mac_ser_o.transfer_status <= c_disturbed;
                was_previous_frame_tx     <= true;
                dominant_seen_during_flag <= false;
                primary_error_sent        <= false;
                fsb_active                <= '0';
                bit_count                 <= 0;
                dominant_run_count        <= 0;
                state                     <= s_flag;
                flag_type                 <= passive_error when fce_i.error_passive_request = '1' else active_error;
              end if;
            end if;

          -----------------------------------------------------------------
          -- Drive next bit onto PCS (stuff bit or normal bit), then
          -- return to s_monitor_bit.
          -----------------------------------------------------------------
          when s_transmit_bit =>
            fce_o.transmitting <= '1';
            -- Stuff bit (dynamic or FSB) takes priority over normal bit
            if (bs_i.valid = '1') then
              v_next_bit := (polarity => bs_i.data, bit_name => stuff_bit);
              bs_o.valid <= '1';
              bs_o.data  <= bs_i.data;
              -- ISO 6.6.4.4: FD dynamic stuff bits included in CRC; FSBs are not.
              if (mac_ser_i.llc_metadata.fdf = '1' and fsb_active = '0') then
                crc_o.valid_fd <= '1';
                crc_o.data_fd  <= bs_i.data;
              end if;

            else

              -- Normal bit: increment position counter
              bit_count <= bit_count + 1;
              -- v_next_bit := get_mac_frame_bit(bit_count + 1, mac_ser_i.data, mac_ser_i.llc_metadata, frame_params, last_transmitted_bit.polarity, bs_i.sbc, crc_i.crc);
              v_next_bit := get_mac_frame_bit(bit_count + 1, mac_ser_i.data, mac_ser_i.llc_metadata, frame_params, bs_i.sbc, crc_i.crc);

              -- Signal ready if the bit is sourced from mac_ser_tx
              if (v_next_bit.bit_name = base_id_bit or v_next_bit.bit_name = extended_id_bit or v_next_bit.bit_name = data_bit) then
                mac_ser_o.ready <= '1';
              end if;

              -- CRC feeding: all logical bits before crc_start
              if (bit_count + 1 < frame_params.crc_start) then
                crc_o.valid_cc    <= '1';
                crc_o.valid_fd <= '1';
                crc_o.data_cc  <= v_next_bit.polarity;
                crc_o.data_fd  <= v_next_bit.polarity;
              end if;

              -- Feed bit stuffer (dynamic and FSB regions, up to crc_delimiter)
              if (bit_count + 1 < frame_params.crc_delimiter) then
                bs_o.valid <= '1';
                bs_o.data  <= v_next_bit.polarity;
              end if;

              -- FSB activation: set one position before data_stop so BS sees
              -- fsb_en rising edge at the correct cycle.
              if (mac_ser_i.llc_metadata.fdf = '1' and bit_count + 1 = frame_params.data_stop - 1) then
                fsb_active <= '1';
              end if;
              if (bit_count + 1 = frame_params.crc_delimiter) then
                fsb_active <= '0';
              end if;

              -- ISO 11898-1: 7.3.2 - data phase boundary
              if (mac_ser_i.llc_metadata.brs = '1' and v_next_bit.bit_name = esi_bit) then
                pcs_o.use_data_rate <= '1';
              elsif (v_next_bit.bit_name = crc_delimiter_bit) then
                pcs_o.use_data_rate <= '0';
              end if;

              pcs_o.start_tdc <= '1' when v_next_bit.bit_name = fdf_bit else '0';
            end if;

            -- Common to both stuff bit and normal bit
            polarity_history              <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & v_next_bit.polarity;
            last_transmitted_bit          <= v_next_bit;

            if (bit_count + 1 < frame_params.crc_delimiter + c_eof_start_offset + c_eof_field_width) then
              pcs_o.valid    <= '1';
              pcs_o.polarity <= v_next_bit.polarity;
            end if;

            state <= s_monitor_bit;

          -----------------------------------------------------------------
          -- ISO 11898-1: 6.6.5 - error flags (active/passive)
          -- ISO 11898-1: 6.6.6 - overload flag
          -----------------------------------------------------------------
          when s_flag =>
            fce_o.transmitting                <= '1';
            fce_o.sending_error_overload_flag <= '1';
            pcs_o.valid                       <= '1';
            pcs_o.use_data_rate               <= '0';
            pcs_o.start_tdc                   <= '0';

            if (flag_type = overload) then
              mac_ser_o.transfer_status <= c_ongoing;
            else
              mac_ser_o.transfer_status <= c_disturbed;
            end if;

            -- Select the flag bit type

            -- Set flag delimiter type when flag has been sent
            if (bit_count < c_error_flag_width) then
              case flag_type is
                when active_error  => v_next_bit := c_active_error_flag_bit;
                when passive_error => v_next_bit := c_passive_error_flag_bit;
                when overload      => v_next_bit := c_overload_flag_bit;
              end case;
            else
              v_next_bit := c_error_delimiter_bit;
            end if;

            -- Present next bit to PCS and update last_transmitted_bit
            pcs_o.polarity                <= v_next_bit.polarity;
            last_transmitted_bit          <= v_next_bit;

            -- SP counter and error tracking
            if (pcs_i.sp = '1') then
              if (bit_count < c_error_sequence_width - 1) then
                bit_count <= bit_count + 1;
              end if;

              -- ISO 11898-1: 8.1.4.2 rule f) - delimiter-too-late tracking
              if (bit_count >= c_error_flag_width) then
                if (pcs_i.bus_polarity = c_recessive) then
                  dominant_run_count <= 0;
                elsif (dominant_run_count = c_error_delimiter_width - 1) then
                  fce_o.error_delimiter_too_late <= '1';
                  dominant_run_count             <= 0;
                else
                  dominant_run_count <= dominant_run_count + 1;
                end if;
              end if;

              -- Primary error (error flags only, not overload)
              if (flag_type /= overload and not primary_error_sent and bit_count < c_error_flag_width and pcs_i.bus_polarity = c_dominant) then
                fce_o.primary_error <= '1';
                primary_error_sent  <= true;
              end if;

              -- ISO 11898-1: 8.1.4.2 rule c), Exception 1:
              -- passive transmitter ACK error without dominant seen in passive EF.
              -- Exception 2 is implicitly handled:
              -- get_bit_info classifies that case as lost_arbitration, so no error
              -- flag is entered and the TEC is never incremented.
              if (flag_type = passive_error and ack_error_caused_flag) then
                if (bit_count < c_error_flag_width and pcs_i.bus_polarity = c_dominant) then
                  dominant_seen_during_flag <= true;
                end if;
                if (bit_count >= c_error_sequence_width - 1 and not dominant_seen_during_flag) then
                  fce_o.counters_unchanged <= '1';
                end if;
              end if;

              -- ISO 11898-1: 6.6.21.3.2 b) - dominant at last delimiter bit
              -- triggers reactive overload
              if (bit_count = c_error_sequence_width - 1 and pcs_i.bus_polarity = c_dominant) then
                flag_type                 <= overload;
                bit_count                 <= 0;
                dominant_seen_during_flag <= false;
                dominant_run_count        <= 0;
                primary_error_sent        <= false;
              elsif (bit_count = c_error_sequence_width - 1) then
                state     <= s_intermission;
                bit_count <= 0;
              end if;
            end if;

          when others =>
            state     <= s_bus_reintegration;
            bit_count <= 0;
        end case;
      end if;
    end if;
  end process p_fsm;
end architecture rtl;

-- ===========================================================================
-- rtl_v2: Per-field state machine with explicit pre-case bit handling.
-- Mirrors the RX FSM style: guard predicates, common BS/CRC/error blocks
-- before the case statement, post-case error-flag entry.
-- ===========================================================================
architecture rtl_v2 of can_mac_fsm_tx is

  type t_fsm_state is (
    s_bus_reintegration, s_intermission, s_suspend_transmission, s_bus_idle,
    s_sof, s_id, s_rtr_srr_rrs, s_ide, s_fdf, s_res, s_brs, s_esi,
    s_dlc, s_data, s_sbc, s_crc,
    s_crc_delimiter, s_ack, s_ack_delimiter, s_eof,
    s_flag
  );

  type t_flag_type is (active_error, passive_error, overload);

  -----------------------------------------------------------------
  -- Registered state signals
  -----------------------------------------------------------------
  signal state     : t_fsm_state;
  signal flag_type : t_flag_type;
  signal bit_count : natural range 0 to c_max_mac_frame_length;

  -- Polarity history for TDC bit error detection (ISO 7.3.4)
  signal polarity_history : std_logic_vector(c_tdc_polarity_depth - 1 downto 0);

  -- Frame metadata (latched from serializer at SOF)
  signal metadata  : t_llc_metadata;
  signal data_len  : natural range 0 to c_max_data_bytes;
  signal crc_length : natural range 0 to c_crc_21_length;

  -- Transmission tracking
  signal was_previous_frame_tx : boolean;
  signal ack_success_seen      : boolean;
  signal ssp_error_pending     : boolean;
  signal skip_sof              : boolean;
  signal fsb_active            : std_logic;
  -- Fault confinement tracking
  signal ack_error_caused_flag     : boolean;
  signal dominant_seen_during_flag : boolean;
  signal dominant_run_count        : natural range 0 to 15;
  signal primary_error_sent        : boolean;


begin

  p_fsm : process (clk_i) is

    -- Guard predicates
    variable v_in_arb_field : boolean;  -- Arbitration field (arb loss possible)
    variable v_in_dsb_field : boolean;  -- Dynamic stuff bit region
    variable v_in_fsb_field : boolean;  -- Fixed stuff bit region
    variable v_in_frame     : boolean;  -- In active frame transmission

    -- Bit transmission and monitoring results
    variable v_tx_polarity    : std_logic;         -- Polarity to drive onto bus
    variable v_bit_driven     : boolean;           -- A bit was driven this SP
    variable v_bit_error      : boolean;           -- Bit error detected
    variable v_lost_arb       : boolean;           -- Arbitration lost
    variable v_enter_error    : boolean;           -- Enter error flag state
    variable v_data_len       : natural;

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        state                     <= s_bus_reintegration;
        flag_type                 <= active_error;
        bit_count                 <= 0;
        polarity_history          <= (others => c_recessive);
        metadata                  <= c_llc_metadata_reset;
        data_len                  <= 0;
        crc_length                <= c_crc_15_length;
        was_previous_frame_tx     <= false;
        ack_success_seen          <= false;
        ssp_error_pending         <= false;
        skip_sof                  <= false;
        fsb_active                <= '0';
        ack_error_caused_flag     <= false;
        dominant_seen_during_flag <= false;
        dominant_run_count        <= 0;
        primary_error_sent        <= false;

        mac_ser_o <= c_ser_fsm_if_d2s_reset;
        pcs_o     <= c_mac_to_pcs_if_reset;
        bs_o      <= c_mac_fsm_to_bs_fd_if_reset;
        bs_rst    <= '0';
        crc_o     <= c_mac_fsm_to_crc_if_reset;
        crc_rst   <= '0';
        fce_o     <= c_mac_to_fce_if_reset;
      else

        -----------------------------------------------------------------
        -- Pulse defaults (cleared every cycle, set only when active)
        -----------------------------------------------------------------
        bs_o            <= c_mac_fsm_to_bs_fd_if_reset;
        bs_o.fsb_en     <= fsb_active;
        bs_rst          <= '0';
        crc_o.valid_cc  <= '0';
        crc_o.valid_fd  <= '0';
        crc_rst         <= '0';
        mac_ser_o.ready <= '0';
        fce_o           <= c_mac_to_fce_if_reset;

        -----------------------------------------------------------------
        -- Quiet-state defaults (not transmitting a frame)
        -----------------------------------------------------------------
        if (state = s_bus_reintegration or state = s_intermission or
            state = s_suspend_transmission or state = s_bus_idle) then
          pcs_o.valid               <= '0';
          pcs_o.polarity            <= c_recessive;
          pcs_o.use_data_rate       <= '0';
          pcs_o.start_tdc           <= '0';
          fce_o.transmitting        <= '0';
          ssp_error_pending         <= false;
          mac_ser_o.transfer_status <= c_ongoing;
        end if;

        -----------------------------------------------------------------
        -- Guard predicates
        -----------------------------------------------------------------
        v_in_arb_field := state = s_id or state = s_rtr_srr_rrs or
                          state = s_ide;
        v_in_dsb_field := v_in_arb_field or state = s_fdf or
                          state = s_res or state = s_brs or
                          state = s_esi or state = s_dlc or
                          state = s_data;
        v_in_fsb_field := state = s_sbc or state = s_crc;

        v_bit_driven  := false;
        v_bit_error   := false;
        v_lost_arb    := false;
        v_enter_error := false;


        -----------------------------------------------------------------
        -- Enable fixed stuff bit (FSB) mode for SBC and FD CRC fields
        -- (ISO 11898-1: 6.6.13.3)
        -----------------------------------------------------------------
        if (state = s_sbc) then
          bs_o.fsb_en <= '1';
        elsif (state = s_crc and crc_length /= c_crc_15_length) then
          bs_o.fsb_en <= '1';
        end if;

        -----------------------------------------------------------------
        -- Common bit monitoring at SP: bit error and arbitration loss.
        -- polarity_history holds the PREVIOUS bit (from last clock's
        -- signal assignment). bus_polarity also reflects the previous
        -- bit (TB loopback captured at TQ 0). So comparing them is
        -- correct: we verify the bit we drove last SP appeared on the
        -- bus as expected.
        -----------------------------------------------------------------
        if (pcs_i.sp = '1' and (v_in_dsb_field or v_in_fsb_field or
            state = s_crc_delimiter or state = s_ack or
            state = s_ack_delimiter or state = s_eof)) then
          if (polarity_history(to_integer(unsigned(pcs_i.tdc_delay))) /= pcs_i.bus_polarity) then
            if (v_in_arb_field and pcs_i.bus_polarity = c_dominant) then
              v_lost_arb := true;
            elsif (state = s_ack_delimiter) then
              -- bus_polarity here reflects the ACK slot (previous bit).
              -- Mismatch means another node drove dominant = ACK received.
              null;
            else
              v_bit_error := true;
            end if;
          end if;
        end if;

        -- SSP: latch pending error (ISO 7.3.4)
        if (pcs_i.ssp = '1' and (v_in_dsb_field or v_in_fsb_field)) then
          if (polarity_history(to_integer(unsigned(pcs_i.tdc_delay))) /= pcs_i.bus_polarity) then
            ssp_error_pending <= true;
          end if;
        end if;

        -- Deferred SSP error surfaces at next SP
        if (pcs_i.sp = '1' and ssp_error_pending) then
          v_bit_error       := true;
          ssp_error_pending <= false;
        end if;

        -----------------------------------------------------------------
        -- SP-gated defaults: clear single-bit pulses at every SP so
        -- state logic only needs to set them, not clear them.
        -----------------------------------------------------------------
        if (pcs_i.sp = '1') then
          pcs_o.start_tdc <= '0';
        end if;

        -----------------------------------------------------------------
        -- Common BS feeding at SP (dsb and fsb regions)
        -- Stuff bits are consumed here; real bits handled in state logic.
        -----------------------------------------------------------------
        if (pcs_i.sp = '1' and (v_in_dsb_field or v_in_fsb_field)) then
          if (bs_i.valid = '1') then
            -- Stuff bit pending: drive it onto PCS, feed back to BS
            v_tx_polarity  := bs_i.data;
            v_bit_driven   := true;
            pcs_o.valid    <= '1';
            pcs_o.polarity <= bs_i.data;
            bs_o.valid     <= '1';
            bs_o.data      <= bs_i.data;
            polarity_history <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & bs_i.data;
            -- ISO 6.6.4.4: FD dynamic stuff bits included in CRC
            if (metadata.fdf = '1' and fsb_active = '0') then
              crc_o.valid_fd <= '1';
              crc_o.data_fd  <= bs_i.data;
            end if;
          end if;
        end if;

        -----------------------------------------------------------------
        -- State machine
        -----------------------------------------------------------------
        case state is

          -----------------------------------------------------------------
          -- s_bus_reintegration: Wait for 11 consecutive recessive bits
          -- before participating on the bus (ISO 11898-1: 6.6.7.5)
          -----------------------------------------------------------------
          when s_bus_reintegration =>
            if (pcs_i.sp = '1') then
              if (pcs_i.bus_polarity = c_recessive) then
                if (bit_count = c_bus_idle_condition_width - 1) then
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
          -- s_intermission: 3-bit inter-frame spacing (ISO 11898-1: 6.6.7.2)
          -----------------------------------------------------------------
          when s_intermission =>
            if (pcs_i.sp = '1') then
              if (pcs_i.bus_polarity = c_dominant) then
                if (bit_count < c_intermission_width - 1) then
                  -- ISO 6.6.21.3.2 b): dominant during first two bits
                  state                     <= s_flag;
                  flag_type                 <= overload;
                  bit_count                 <= 0;
                  dominant_seen_during_flag <= false;
                  dominant_run_count        <= 0;
                  primary_error_sent        <= false;
                else
                  -- ISO 6.6.7.2 / 6.6.8: SOF at 3rd bit
                  if (mac_ser_i.valid = '1' and
                      (fce_i.error_passive_request = '0' or not was_previous_frame_tx)) then
                    state     <= s_sof;
                    bit_count <= 0;
                    skip_sof  <= true;
                    bs_rst    <= '1';
                    crc_rst   <= '1';
                  else
                    state     <= s_bus_idle;
                    bit_count <= 0;
                  end if;
                end if;
              else
                if (bit_count < c_intermission_width - 1) then
                  bit_count <= bit_count + 1;
                else
                  -- ISO 6.6.7.4 / 6.6.7.3: full intermission completed
                  if (fce_i.error_passive_request = '1' and was_previous_frame_tx) then
                    state <= s_suspend_transmission;
                  else
                    state <= s_bus_idle;
                  end if;
                  bit_count <= 0;
                end if;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_suspend_transmission: Error-passive nodes wait 8 extra bits
          -- after transmitting (ISO 11898-1: 6.6.7.4)
          -----------------------------------------------------------------
          when s_suspend_transmission =>
            if (pcs_i.sp = '1') then
              if (pcs_i.bus_polarity = c_recessive) then
                if (bit_count = c_suspend_transmission_width - 1) then
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
          -- s_bus_idle: Ready for new frame (ISO 11898-1: 6.6.7.3)
          -----------------------------------------------------------------
          when s_bus_idle =>
            if (mac_ser_i.valid = '1' and pcs_i.sp = '1') then
              state     <= s_sof;
              bit_count <= 0;
              bs_rst    <= '1';
              crc_rst   <= '1';
            end if;

          -----------------------------------------------------------------
          -- s_sof: Drive SOF (dominant), latch metadata, feed BS/CRC.
          -- When skip_sof is true (ISO 6.6.8), SOF was already on the bus
          -- from the 3rd intermission bit - drive first ID bit instead.
          -----------------------------------------------------------------
          when s_sof =>
            fce_o.transmitting  <= '1';
            pcs_o.valid         <= '1';
            pcs_o.use_data_rate <= '0';
            pcs_o.start_tdc     <= '0';

            -- Latch frame metadata (unconditional setup)
            metadata <= mac_ser_i.llc_metadata;
            v_data_len := dlc_to_data_length(
              to_integer(unsigned(mac_ser_i.llc_metadata.dlc)),
              mac_ser_i.llc_metadata.fdf
            );
            data_len <= v_data_len;

            -- Select CRC polynomial
            if (mac_ser_i.llc_metadata.fdf = '0') then
              crc_length            <= c_crc_15_length;
              crc_o.crc_poly_select <= c_crc_poly_15_sel;
            elsif (v_data_len < c_crc_17_length) then
              crc_length            <= c_crc_17_length;
              crc_o.crc_poly_select <= c_crc_poly_17_sel;
            else
              crc_length            <= c_crc_21_length;
              crc_o.crc_poly_select <= c_crc_poly_21_sel;
            end if;

            -- Reset tracking
            ack_success_seen          <= false;
            ssp_error_pending         <= false;
            ack_error_caused_flag     <= false;
            dominant_seen_during_flag <= false;
            dominant_run_count        <= 0;
            fsb_active                <= '0';

            -- Feed SOF to BS and CRC
            bs_o.valid     <= '1';
            bs_o.data      <= c_dominant;
            crc_o.valid_cc <= '1';
            crc_o.valid_fd <= '1';
            crc_o.data_cc  <= c_dominant;
            crc_o.data_fd  <= c_dominant;

            polarity_history <= (0 => c_dominant, others => c_recessive);

            if (skip_sof) then
              -- SOF already on bus: drive first ID bit
              pcs_o.polarity  <= mac_ser_i.data;
              mac_ser_o.ready <= '1';
              polarity_history <= (0 => mac_ser_i.data, others => c_recessive);
            else
              pcs_o.polarity <= c_dominant;
            end if;

            state     <= s_id;
            bit_count <= 0;

          -----------------------------------------------------------------
          -- s_id: Transmit base ID (11 bits) or extended ID (18 bits).
          -- Data sourced from serializer.
          -----------------------------------------------------------------
          when s_id =>
            fce_o.transmitting <= '1';

            -- skip_sof: first ID bit was driven on PCS in s_sof but
            -- not fed to BS/CRC. Feed it now (one clock after SOF feed).
            if (skip_sof) then
              bs_o.valid     <= '1';
              bs_o.data      <= polarity_history(0);
              crc_o.valid_cc <= '1';
              crc_o.valid_fd <= '1';
              crc_o.data_cc  <= polarity_history(0);
              crc_o.data_fd  <= polarity_history(0);
              bit_count      <= 1;
              skip_sof       <= false;

            elsif (pcs_i.sp = '1' and bs_i.valid = '0') then
              -- Drive next ID bit from serializer
              v_tx_polarity := mac_ser_i.data;
              v_bit_driven  := true;
              pcs_o.valid    <= '1';
              pcs_o.polarity <= v_tx_polarity;
              mac_ser_o.ready <= '1';

              -- Feed BS and CRC
              bs_o.valid     <= '1';
              bs_o.data      <= v_tx_polarity;
              crc_o.valid_cc <= '1';
              crc_o.valid_fd <= '1';
              crc_o.data_cc  <= v_tx_polarity;
              crc_o.data_fd  <= v_tx_polarity;

              polarity_history <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & v_tx_polarity;
              bit_count <= bit_count + 1;

              -- After 11 base ID bits or 18 extended ID bits
              if (bit_count = c_base_id_width - 1 or
                  bit_count = c_base_id_width + c_extended_id_width - 1) then
                state <= s_rtr_srr_rrs;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_rtr_srr_rrs: RTR (CC basic), SRR (CC/FD extended), or
          -- RRS (FD basic). Polarity from metadata.ftyp or fixed.
          -----------------------------------------------------------------
          when s_rtr_srr_rrs =>
            fce_o.transmitting <= '1';

            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              -- First pass (after base ID, bit_count = c_base_id_width):
              --   SRR for extended, RTR for CC basic, RRS for FD basic.
              -- Second pass (after ext ID, bit_count > c_base_id_width):
              --   RTR for CC extended, RRS for FD extended.
              if (bit_count > c_base_id_width) then
                -- Second pass: RTR (CC) or RRS (FD)
                if (metadata.fdf = '1') then
                  v_tx_polarity := c_dominant;     -- RRS always dominant
                else
                  v_tx_polarity := metadata.ftyp;  -- RTR from metadata
                end if;
              elsif (metadata.ide = '1') then
                v_tx_polarity := c_recessive;      -- SRR always recessive
              elsif (metadata.fdf = '1') then
                v_tx_polarity := c_dominant;        -- RRS always dominant
              else
                v_tx_polarity := metadata.ftyp;     -- RTR from metadata
              end if;
              v_bit_driven := true;

              pcs_o.valid    <= '1';
              pcs_o.polarity <= v_tx_polarity;
              bs_o.valid     <= '1';
              bs_o.data      <= v_tx_polarity;
              crc_o.valid_cc <= '1';
              crc_o.valid_fd <= '1';
              crc_o.data_cc  <= v_tx_polarity;
              crc_o.data_fd  <= v_tx_polarity;
              polarity_history <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & v_tx_polarity;

              if (bit_count > c_base_id_width) then
                -- Second pass: skip IDE, go directly to FDF/r1
                state <= s_fdf;
              else
                -- First pass: next is IDE
                state <= s_ide;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_ide: IDE bit. Dominant for basic, recessive for extended.
          -----------------------------------------------------------------
          when s_ide =>
            fce_o.transmitting <= '1';

            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              v_tx_polarity := metadata.ide;
              v_bit_driven  := true;

              pcs_o.valid    <= '1';
              pcs_o.polarity <= v_tx_polarity;
              bs_o.valid     <= '1';
              bs_o.data      <= v_tx_polarity;
              crc_o.valid_cc <= '1';
              crc_o.valid_fd <= '1';
              crc_o.data_cc  <= v_tx_polarity;
              crc_o.data_fd  <= v_tx_polarity;
              polarity_history <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & v_tx_polarity;

              if (metadata.ide = c_recessive) then
                -- Extended frame: go to extended ID
                state     <= s_id;
                bit_count <= c_base_id_width;
              else
                -- Basic frame: next is FDF/r0
                state <= s_fdf;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_fdf: FDF bit. Recessive for FD, dominant (r0) for CC.
          -- For CC basic this is r0, for CC extended this is r1.
          -----------------------------------------------------------------
          when s_fdf =>
            fce_o.transmitting <= '1';

            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              v_tx_polarity := metadata.fdf;
              v_bit_driven  := true;

              pcs_o.valid    <= '1';
              pcs_o.polarity <= v_tx_polarity;
              pcs_o.start_tdc <= '1' when metadata.fdf = '1' else '0';
              bs_o.valid     <= '1';
              bs_o.data      <= v_tx_polarity;
              crc_o.valid_cc <= '1';
              crc_o.valid_fd <= '1';
              crc_o.data_cc  <= v_tx_polarity;
              crc_o.data_fd  <= v_tx_polarity;
              polarity_history <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & v_tx_polarity;

              if (metadata.fdf = c_recessive or metadata.ide = '1') then
                -- FD frame or CC extended: consume reserved bit(s)
                state <= s_res;
              else
                -- CC basic: r0 already sent as FDF=dominant, go to DLC
                state     <= s_dlc;
                bit_count <= 0;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_res: Reserved bit (dominant). FD: res then BRS.
          -- CC extended: r0, then DLC.
          -----------------------------------------------------------------
          when s_res =>
            fce_o.transmitting <= '1';

            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              v_tx_polarity := c_dominant;
              v_bit_driven  := true;

              pcs_o.valid    <= '1';
              pcs_o.polarity <= v_tx_polarity;
              bs_o.valid     <= '1';
              bs_o.data      <= v_tx_polarity;
              crc_o.valid_cc <= '1';
              crc_o.valid_fd <= '1';
              crc_o.data_cc  <= v_tx_polarity;
              crc_o.data_fd  <= v_tx_polarity;
              polarity_history <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & v_tx_polarity;

              if (metadata.fdf = '1') then
                state <= s_brs;
              else
                -- CC extended: r0 consumed, go to DLC
                state     <= s_dlc;
                bit_count <= 0;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_brs: BRS bit (FD only). Switches to data rate if recessive.
          -----------------------------------------------------------------
          when s_brs =>
            fce_o.transmitting <= '1';

            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              v_tx_polarity := metadata.brs;
              v_bit_driven  := true;

              pcs_o.valid         <= '1';
              pcs_o.polarity      <= v_tx_polarity;
              bs_o.valid          <= '1';
              bs_o.data           <= v_tx_polarity;
              crc_o.valid_cc      <= '1';
              crc_o.valid_fd      <= '1';
              crc_o.data_cc       <= v_tx_polarity;
              crc_o.data_fd       <= v_tx_polarity;
              polarity_history    <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & v_tx_polarity;

              state <= s_esi;
            end if;

          -----------------------------------------------------------------
          -- s_esi: ESI bit (FD only). Error passive indicator.
          -- Data rate switches here (ISO 7.3.2).
          -----------------------------------------------------------------
          when s_esi =>
            fce_o.transmitting <= '1';

            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              v_tx_polarity := metadata.esi;
              v_bit_driven  := true;

              pcs_o.valid         <= '1';
              pcs_o.polarity      <= v_tx_polarity;
              pcs_o.use_data_rate <= metadata.brs;
              bs_o.valid     <= '1';
              bs_o.data      <= v_tx_polarity;
              crc_o.valid_cc <= '1';
              crc_o.valid_fd <= '1';
              crc_o.data_cc  <= v_tx_polarity;
              crc_o.data_fd  <= v_tx_polarity;
              polarity_history <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & v_tx_polarity;

              state     <= s_dlc;
              bit_count <= 0;
            end if;

          -----------------------------------------------------------------
          -- s_dlc: 4-bit DLC field. Data from metadata.dlc vector.
          -----------------------------------------------------------------
          when s_dlc =>
            fce_o.transmitting <= '1';

            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              v_tx_polarity := metadata.dlc(c_dlc_field_width - 1 - bit_count);
              v_bit_driven  := true;

              pcs_o.valid    <= '1';
              pcs_o.polarity <= v_tx_polarity;
              bs_o.valid     <= '1';
              bs_o.data      <= v_tx_polarity;
              crc_o.valid_cc <= '1';
              crc_o.valid_fd <= '1';
              crc_o.data_cc  <= v_tx_polarity;
              crc_o.data_fd  <= v_tx_polarity;
              polarity_history <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & v_tx_polarity;

              if (bit_count = c_dlc_field_width - 1) then
                bit_count <= 0;
                if (data_len > 0) then
                  state <= s_data;
                elsif (metadata.fdf = '1') then
                  fsb_active <= '1';
                  state      <= s_sbc;
                else
                  state <= s_crc;
                end if;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_data: Data field. Bits from serializer, byte-by-byte.
          -----------------------------------------------------------------
          when s_data =>
            fce_o.transmitting <= '1';

            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              v_tx_polarity := mac_ser_i.data;
              v_bit_driven  := true;

              pcs_o.valid     <= '1';
              pcs_o.polarity  <= v_tx_polarity;
              mac_ser_o.ready <= '1';
              bs_o.valid      <= '1';
              bs_o.data       <= v_tx_polarity;
              crc_o.valid_cc  <= '1';
              crc_o.valid_fd  <= '1';
              crc_o.data_cc   <= v_tx_polarity;
              crc_o.data_fd   <= v_tx_polarity;
              polarity_history <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & v_tx_polarity;

              if (bit_count = data_len * c_byte_width - 1) then
                bit_count <= 0;
                -- Activate FSB one bit early so BS sees rising edge
                if (metadata.fdf = '1') then
                  fsb_active <= '1';
                  state      <= s_sbc;
                else
                  state <= s_crc;
                end if;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_sbc: Stuff bit count field (FD only, 4 bits).
          -- SBC bits from bs_i.sbc. FSB mode enabled above.
          -----------------------------------------------------------------
          when s_sbc =>
            fce_o.transmitting <= '1';

            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              v_tx_polarity := bs_i.sbc((c_sbc_field_width - 1) - bit_count);
              v_bit_driven  := true;

              pcs_o.valid    <= '1';
              pcs_o.polarity <= v_tx_polarity;
              bs_o.valid     <= '1';
              bs_o.data      <= v_tx_polarity;
              -- SBC feeds FD CRC only
              crc_o.valid_fd <= '1';
              crc_o.data_fd  <= v_tx_polarity;
              polarity_history <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & v_tx_polarity;

              if (bit_count = c_sbc_field_width - 1) then
                state     <= s_crc;
                bit_count <= 0;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_crc: CRC field. Bits from crc_i.crc vector. No CRC feed.
          -----------------------------------------------------------------
          when s_crc =>
            fce_o.transmitting <= '1';

            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              v_tx_polarity := crc_i.crc((c_crc_21_length - 1) - bit_count);
              v_bit_driven  := true;

              pcs_o.valid    <= '1';
              pcs_o.polarity <= v_tx_polarity;
              -- Feed BS (still in stuffing region)
              bs_o.valid     <= '1';
              bs_o.data      <= v_tx_polarity;
              polarity_history <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & v_tx_polarity;

              if (bit_count = crc_length - 1) then
                state      <= s_crc_delimiter;
                bit_count  <= 0;
                fsb_active <= '0';
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_crc_delimiter: Single recessive bit. Switch back to nominal
          -- bit rate.
          -----------------------------------------------------------------
          when s_crc_delimiter =>
            fce_o.transmitting <= '1';
            pcs_o.valid        <= '1';

            if (pcs_i.sp = '1') then
              v_tx_polarity       := c_recessive;
              v_bit_driven        := true;
              pcs_o.polarity      <= c_recessive;
              pcs_o.use_data_rate <= '0';
              polarity_history    <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & c_recessive;
              state <= s_ack;
            end if;

          -----------------------------------------------------------------
          -- s_ack: ACK slot (recessive from TX). Monitor for dominant
          -- from another node confirming reception.
          -----------------------------------------------------------------
          when s_ack =>
            fce_o.transmitting <= '1';
            pcs_o.valid        <= '1';

            if (pcs_i.sp = '1') then
              -- bus_polarity here reflects CRC delimiter (previous bit).
              -- ACK detection deferred to s_ack_delimiter where bus_polarity
              -- reflects the actual ACK slot.
              v_tx_polarity    := c_recessive;
              v_bit_driven     := true;
              pcs_o.polarity   <= c_recessive;
              polarity_history <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & c_recessive;
              state <= s_ack_delimiter;
            end if;

          -----------------------------------------------------------------
          -- s_ack_delimiter: Single recessive bit after ACK slot.
          -- Check for ACK error if no dominant was seen.
          -----------------------------------------------------------------
          when s_ack_delimiter =>
            fce_o.transmitting <= '1';
            pcs_o.valid        <= '1';

            if (pcs_i.sp = '1') then
              -- bus_polarity here reflects the ACK slot (previous bit).
              -- Dominant means another node acknowledged the frame.
              if (pcs_i.bus_polarity = c_dominant) then
                ack_success_seen <= true;
              end if;
              v_tx_polarity    := c_recessive;
              v_bit_driven     := true;
              pcs_o.polarity   <= c_recessive;
              polarity_history <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & c_recessive;
              state     <= s_eof;
              bit_count <= 0;
            end if;

          -----------------------------------------------------------------
          -- s_eof: 7 recessive bits (ISO 11898-1: 6.6.10.7, 6.6.11.7)
          -----------------------------------------------------------------
          when s_eof =>
            fce_o.transmitting <= '1';
            pcs_o.valid        <= '1';

            if (pcs_i.sp = '1') then
              -- ACK error check at first EOF bit: bus_polarity here
              -- reflects ACK delimiter (previous bit). The ACK slot was
              -- checked in s_ack_delimiter.
              if (bit_count = 0 and not ack_success_seen) then
                v_enter_error         := true;
                ack_error_caused_flag <= true;
              end if;

              v_tx_polarity    := c_recessive;
              v_bit_driven     := true;
              pcs_o.polarity   <= c_recessive;
              polarity_history <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & c_recessive;
              if (bit_count = c_eof_field_width - 1) then
                -- Successful transmission
                mac_ser_o.transfer_status <= c_transmitted;
                was_previous_frame_tx     <= true;
                fce_o.successful_transfer <= '1';
                state                     <= s_intermission;
                bit_count                 <= 0;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_flag: Error flags (active/passive) and overload flag.
          -- ISO 11898-1: 6.6.5, 6.6.6
          -----------------------------------------------------------------
          when s_flag =>
            fce_o.transmitting                <= '1';
            fce_o.sending_error_overload_flag <= '1';
            pcs_o.valid                       <= '1';
            pcs_o.use_data_rate               <= '0';
            pcs_o.start_tdc                   <= '0';

            if (flag_type = overload) then
              mac_ser_o.transfer_status <= c_ongoing;
            else
              mac_ser_o.transfer_status <= c_disturbed;
            end if;

            -- Flag polarity: 6 dominant (active/overload) or 6 recessive (passive)
            -- then 8 recessive delimiter
            if (bit_count < c_error_flag_width and flag_type /= passive_error) then
              pcs_o.polarity <= c_dominant;
            else
              pcs_o.polarity <= c_recessive;
            end if;

            if (pcs_i.sp = '1') then
              if (bit_count < c_error_sequence_width - 1) then
                bit_count <= bit_count + 1;
              end if;

              -- ISO 8.1.4.2 rule f): delimiter-too-late tracking
              if (bit_count >= c_error_flag_width) then
                if (pcs_i.bus_polarity = c_recessive) then
                  dominant_run_count <= 0;
                elsif (dominant_run_count = c_error_delimiter_width - 1) then
                  fce_o.error_delimiter_too_late <= '1';
                  dominant_run_count             <= 0;
                else
                  dominant_run_count <= dominant_run_count + 1;
                end if;
              end if;

              -- Primary error (error flags only, not overload)
              if (flag_type /= overload and not primary_error_sent and
                  bit_count < c_error_flag_width and pcs_i.bus_polarity = c_dominant) then
                fce_o.primary_error <= '1';
                primary_error_sent  <= true;
              end if;

              -- ISO 8.1.4.2 rule c) Exception 1: passive TX ACK error
              if (flag_type = passive_error and ack_error_caused_flag) then
                if (bit_count < c_error_flag_width and pcs_i.bus_polarity = c_dominant) then
                  dominant_seen_during_flag <= true;
                end if;
                if (bit_count >= c_error_sequence_width - 1 and not dominant_seen_during_flag) then
                  fce_o.counters_unchanged <= '1';
                end if;
              end if;

              -- ISO 6.6.21.3.2 b): dominant at last delimiter bit -> overload
              if (bit_count = c_error_sequence_width - 1 and pcs_i.bus_polarity = c_dominant) then
                flag_type                 <= overload;
                bit_count                 <= 0;
                dominant_seen_during_flag <= false;
                dominant_run_count        <= 0;
                primary_error_sent        <= false;
              elsif (bit_count = c_error_sequence_width - 1) then
                state     <= s_intermission;
                bit_count <= 0;
              end if;
            end if;

          when others =>
            state     <= s_bus_reintegration;
            bit_count <= 0;

        end case;

        -----------------------------------------------------------------
        -- Bit error entry (frame-content states)
        -----------------------------------------------------------------
        if (v_bit_error) then
          fce_o.error               <= '1';
          pcs_o.polarity            <= c_recessive when fce_i.error_passive_request = '1' else c_dominant;
          pcs_o.valid               <= '1';
          mac_ser_o.transfer_status <= c_disturbed;
          was_previous_frame_tx     <= true;
          dominant_seen_during_flag <= false;
          primary_error_sent        <= false;
          fsb_active                <= '0';
          bit_count                 <= 0;
          dominant_run_count        <= 0;
          state                     <= s_flag;
          flag_type                 <= passive_error when fce_i.error_passive_request = '1' else active_error;
        end if;

        -----------------------------------------------------------------
        -- Arbitration loss (arb-field states only)
        -----------------------------------------------------------------
        if (v_lost_arb) then
          mac_ser_o.transfer_status <= c_lost_arb;
          was_previous_frame_tx     <= false;
          bit_count                 <= 0;
          state                     <= s_intermission;
        end if;

        -----------------------------------------------------------------
        -- ACK error / protocol error entry
        -----------------------------------------------------------------
        if (v_enter_error) then
          fce_o.error               <= '1';
          pcs_o.polarity            <= c_recessive when fce_i.error_passive_request = '1' else c_dominant;
          pcs_o.valid               <= '1';
          mac_ser_o.transfer_status <= c_disturbed;
          was_previous_frame_tx     <= true;
          dominant_seen_during_flag <= false;
          primary_error_sent        <= false;
          fsb_active                <= '0';
          bit_count                 <= 0;
          dominant_run_count        <= 0;
          state                     <= s_flag;
          flag_type                 <= passive_error when fce_i.error_passive_request = '1' else active_error;
        end if;

      end if;
    end if;

  end process p_fsm;

end architecture rtl_v2;
