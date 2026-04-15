--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Media Access Control (MAC) FSM for CAN/CAN-FD transmission.
--                Coordinates serialization, bit stuffing, CRC generation, and
--                physical signaling (PCS) timing.
--                Protocol references: ISO 11898-1:2024 (ISO)
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-31  MRDSA     Converted to company header format
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
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
    -- Fault Confinement Entity interface (ISO : Table 16/17)
    fce_i : in    t_can_mac_fce_if_s2m;
    fce_o : out   t_can_mac_fce_if_m2s
  );
end entity can_mac_fsm_tx;

architecture rtl of can_mac_fsm_tx is

  -----------------------------------------------------------------
  -- Types
  -----------------------------------------------------------------
  type t_fsm_state is (
    s_bus_reintegration, s_intermission, s_suspend_transmission, s_bus_idle,
    s_sof, s_id, s_rtr_srr_rrs, s_ide, s_fdf_r1_r0, s_res_r0, s_brs, s_esi,
    s_dlc, s_data, s_sbc, s_crc, s_ack, s_eof,
    s_error_overload, s_error_delimiter
  );

  -----------------------------------------------------------------
  -- Signals
  -----------------------------------------------------------------
  signal state     : t_fsm_state;
  signal overload  : boolean;
  signal bit_count : natural range 0 to c_max_mac_frame_length;
  -- Polarity history for TDC bit error detection (ISO : 7.3.4)
  signal polarity_history : std_logic_vector(c_tdc_polarity_depth - 1 downto 0);
  -- Frame metadata (read directly from serializer; held stable for frame)
  signal data_len   : natural range 0 to c_max_data_bytes;
  signal crc_length : natural range 0 to c_crc_21_length;
  -- Transmission tracking
  signal was_previous_frame_tx                : boolean;
  signal ack_success_seen                     : boolean;
  signal secondary_sample_point_error_pending : boolean;
  signal skip_sof                             : boolean;
  -- Fault confinement tracking
  signal ack_error_caused_flag     : boolean;
  signal saw_dominant_during_flag  : boolean; -- Tracks dominant bits seen during our passive error flag (ISO 8.1.4.2 c) Exc.1)
  signal dominant_run_count        : natural range 0 to c_bus_off_threshold; -- Node will go bus off before this limit is reached


begin

  p_fsm : process (clk_i) is
    -- Guards
    variable v_in_arbitration_field   : boolean; -- Arbitration field
    variable v_in_dynamic_stuff_field : boolean; -- Dynamic stuff bit region
    variable v_in_fixed_stuff_field   : boolean; -- Fixed stuff bit region
    variable v_in_quiet_field         : boolean; -- In quiet fields (bus reintegration, intermission, suspend transmission, bus idle)
    variable v_in_ack_slot            : boolean; -- In ACK slot bit(s) where a recessive TX may be legitimately overwritten with dominant

    -- Bit transmission and monitoring results
    variable v_tx_polarity  : std_logic; -- Polarity to drive onto bus
    variable v_bit_driven   : boolean;   -- A bit was driven this SP
    variable v_is_stuff_bit : boolean;  -- The driven bit was a stuff bit (BS-sourced)
    variable v_lost_arb     : boolean;   -- Arbitration lost
    variable v_enter_error  : boolean;   -- Enter error flag state (bit/SSP/ACK error)
    variable v_ack_error    : boolean;   -- This v_enter_error was triggered by an ACK error (defer fce_o.error to flag end)

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1' or fce_i.bus_off = '1') then
        state                                <= s_bus_reintegration;
        overload                             <= false;
        bit_count                            <= 0;
        polarity_history                     <= (others => c_recessive);
        data_len                             <= 0;
        crc_length                           <= c_crc_15_length;
        was_previous_frame_tx                <= false;
        ack_success_seen                     <= false;
        secondary_sample_point_error_pending <= false;
        skip_sof                             <= false;
        ack_error_caused_flag                <= false;
        saw_dominant_during_flag             <= false;
        mac_ser_o                            <= c_ser_fsm_if_d2s_reset;
        bs_o                                 <= c_mac_fsm_to_bs_fd_if_reset;
        pcs_o                                <= c_mac_to_pcs_if_reset;
        bs_rst                               <= '0';
        crc_o                                <= c_mac_fsm_to_crc_if_reset;
        crc_rst                              <= '0';
        fce_o                                <= c_mac_to_fce_if_reset;
      else

        -----------------------------------------------------------------
        -- Guards
        -----------------------------------------------------------------
        v_in_arbitration_field := state = s_id or state = s_rtr_srr_rrs or state = s_ide;
        v_in_dynamic_stuff_field := v_in_arbitration_field or state = s_fdf_r1_r0 or state = s_res_r0 or state = s_brs or state = s_esi or state = s_dlc or state = s_data;
        v_in_fixed_stuff_field := state = s_sbc or state = s_crc;
        v_in_quiet_field := state = s_bus_reintegration or state = s_intermission or state = s_suspend_transmission or state = s_bus_idle;
        -- ACK slot is 1 bit for CC and 2 bits for FD (ISO : 6.6.11.6)
        v_in_ack_slot := state = s_ack and (bit_count = 0 or (bit_count = 1 and mac_ser_i.llc_metadata.fdf = '1'));
        -----------------------------------------------------------------

        -----------------------------------------------------------------
        -- Defaults
        -----------------------------------------------------------------
        -- Enable fixed stuff bit mode for SBC and CRC fields in FD frames (ISO : 6.6.13.3)
        bs_o.fixed_bit_stuffing_en <= '1' when mac_ser_i.llc_metadata.fdf = '1' and (state = s_sbc or state = s_crc) else '0';
        bs_o.data  <= pcs_i.bus_polarity;
        bs_o.valid <= '0';
        bs_rst     <= '0';
        -----------------------------------------------------------------
        crc_o                 <= c_mac_fsm_to_crc_if_reset;
        crc_o.crc_poly_select <= crc_o.crc_poly_select; -- Override reset with current value
        crc_rst               <= '0';
        -----------------------------------------------------------------
        fce_o              <= c_mac_to_fce_if_reset;
        fce_o.transmitting <= '1' when v_in_dynamic_stuff_field or v_in_fixed_stuff_field or state = s_sof or state = s_ack or state = s_eof or state = s_error_overload else '0';
        fce_o.sending_error_overload_flag <= '1' when state = s_error_overload else '0';
        -----------------------------------------------------------------
        mac_ser_o.ready           <= '0';
        mac_ser_o.transfer_status <= mac_ser_o.transfer_status;
        -----------------------------------------------------------------
        -- Hold Transmitter Delay Compensation (TDC) signal until next sample point (ISO : 7.3.4)
        pcs_o.start_tdc <= '0' when pcs_i.sample_point = '1' else pcs_o.start_tdc;
        -- SSP: latch deferred bit error (ISO : 7.3.4). Hold until consumed at SP.
        if (pcs_i.secondary_sample_point = '1' and polarity_history(to_integer(unsigned(pcs_i.tdc_delay))) /= pcs_i.bus_polarity) then
          secondary_sample_point_error_pending <= true;
        end if;
        -----------------------------------------------------------------
        v_bit_driven   := false;
        v_is_stuff_bit := false;
        v_lost_arb     := false;
        v_enter_error  := false;
        v_ack_error    := false;
        v_tx_polarity  := c_recessive;
        -----------------------------------------------------------------
        -- Quiet-state defaults
        if (v_in_quiet_field) then
          pcs_o                     <= c_mac_to_pcs_if_reset;
          fce_o                     <= c_mac_to_fce_if_reset;
          mac_ser_o                 <= c_ser_fsm_if_d2s_reset;
          bs_o                      <= c_mac_fsm_to_bs_fd_if_reset;
          secondary_sample_point_error_pending         <= false;
          bs_rst                    <= '1';
          crc_rst                   <= '1';
          ack_success_seen          <= false;
          ack_error_caused_flag     <= false;
          saw_dominant_during_flag  <= false;
          dominant_run_count        <= 0;
          pcs_o.use_data_rate       <= '0';
        end if;
        -----------------------------------------------------------------

        -----------------------------------------------------------------
        -- Stuff bit: BS has a pending bit, drive it instead of the FSM's.
        -----------------------------------------------------------------
        if bs_i.valid = '1' and pcs_i.sample_point = '1' and (v_in_dynamic_stuff_field or v_in_fixed_stuff_field) then
          v_tx_polarity  := bs_i.data;
          v_bit_driven   := true;
          v_is_stuff_bit := true;
        end if;


        -----------------------------------------------------------------
        -- State machine
        -----------------------------------------------------------------
        case state is
          -----------------------------------------------------------------
          -- s_bus_reintegration : Wait for 11 consecutive recessive bits
          -- before participating on the bus (ISO : 6.6.7.5)
          -----------------------------------------------------------------
          when s_bus_reintegration =>
            if (pcs_i.sample_point = '1' and pcs_i.bus_polarity = c_recessive) then
              if (bit_count = c_bus_idle_condition_width - 1) then
                state     <= s_bus_idle;
                bit_count <= 0;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_intermission : 3-bit inter-frame spacing (ISO : 6.6.7.2)
          -----------------------------------------------------------------
          when s_intermission =>
            if (pcs_i.sample_point = '1') then
              if (pcs_i.bus_polarity = c_dominant) then
                if (bit_count < c_intermission_width - 1) then
                  -- Dominant bit at first 2 bits is overload (ISO : 6.6.21.3.2 b)
                  state     <= s_error_overload;
                  bit_count <= 0;
                  overload  <= true;
                else
                  -- Dominant bit ar 3rd bit is SOF
                  if (mac_ser_i.valid = '1' and (fce_i.error_active = '1' or not was_previous_frame_tx)) then
                    state     <= s_sof;
                    bit_count <= 0;
                    skip_sof  <= true;
                  end if;
                end if;
              else
                if (bit_count < c_intermission_width - 1) then
                  bit_count <= bit_count + 1;
                else
                  bit_count <= 0;
                  if (fce_i.error_active = '0' and was_previous_frame_tx) then
                    -- Suspend transmission if was transmitter of last frame and in error passive state (ISO : 6.6.7.4)
                    state <= s_suspend_transmission;
                  else
                    state <= s_bus_idle;
                    bit_count <= 0;
                  end if;
                end if;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_suspend_transmission : Error-passive TX waits 8 extra bits
          -- after transmitting (ISO : 6.6.7.4)
          -----------------------------------------------------------------
          when s_suspend_transmission =>
            if (pcs_i.sample_point = '1' and pcs_i.bus_polarity = c_recessive) then
              if (bit_count = c_suspend_transmission_width - 1) then
                state     <= s_bus_idle;
                bit_count <= 0;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_bus_idle : Ready for new frame (ISO : 6.6.7.3)
          -----------------------------------------------------------------
          when s_bus_idle =>
            if (mac_ser_i.valid = '1' and pcs_i.sample_point = '1') then
              state     <= s_sof;
              bit_count <= 0;
            end if;

          -----------------------------------------------------------------
          -- s_sof : Drive SOF bit and feed BS/CRC.
          -- If SOF detected in 3rd intermission dominant (skip_sof),
          -- drive first ID bit instead (ISO : 6.6.8).
          -----------------------------------------------------------------
          when s_sof =>
            -- Frame setup (runs every clock; values are constant from metadata)
            data_len <= dlc_to_data_length(to_integer(unsigned(mac_ser_i.llc_metadata.dlc)), mac_ser_i.llc_metadata.fdf);

            -- Select CRC polynomial
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

            -- Hold SOF dominant on the bus until the sample point
            pcs_o.polarity <= c_dominant;

            if skip_sof then
              -- SOF was already detected as 3rd intermission dominant;
              -- drive first ID bit immediately.
              pcs_o.polarity   <= mac_ser_i.data;
              bs_o.valid       <= '1';
              bs_o.data        <= mac_ser_i.data;
              crc_o.valid_cc   <= '1';
              crc_o.valid_fd   <= '1';
              crc_o.data_fd    <= mac_ser_i.data;
              crc_o.data_cc    <= mac_ser_i.data;
              mac_ser_o.ready  <= '1';
              polarity_history <= (0 => mac_ser_i.data, others => c_recessive);
              bit_count        <= 1;
              skip_sof         <= false;
              state            <= s_id;
            elsif (pcs_i.sample_point = '1') then
              -- SOF sampled: feed BS/CRC and advance to s_id
              bs_o.valid       <= '1';
              bs_o.data        <= c_dominant;
              crc_o.valid_cc   <= '1';
              crc_o.valid_fd   <= '1';
              crc_o.data_cc    <= c_dominant;
              crc_o.data_fd    <= c_dominant;
              polarity_history <= (0 => c_dominant, others => c_recessive);
              bit_count        <= 0;
              state            <= s_id;
            end if;

          -----------------------------------------------------------------
          -- s_id : Base ID (11 bits) or extended ID (18 bits) from mac_ser.
          -----------------------------------------------------------------
          when s_id =>
            if (pcs_i.sample_point = '1' and bs_i.valid = '0') then
              mac_ser_o.ready <= '1';
              v_tx_polarity   := mac_ser_i.data;
              v_bit_driven    := true;
              bit_count       <= bit_count + 1;
              if (bit_count = c_base_id_width - 1 or bit_count = c_base_id_width + c_extended_id_width - 1) then
                state <= s_rtr_srr_rrs;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_rtr_srr_rrs : RTR/SRR/RRS bit, selected by format and pass
          -- (first pass after base ID, second pass after extended ID).
          -----------------------------------------------------------------
          when s_rtr_srr_rrs =>
            if (pcs_i.sample_point = '1' and bs_i.valid = '0') then
              if (mac_ser_i.llc_metadata.ide = '1' and bit_count = c_base_id_width) then
                v_tx_polarity := c_recessive;                   -- SRR
              elsif (mac_ser_i.llc_metadata.fdf = '1') then
                v_tx_polarity := c_dominant;                    -- RRS
              else
                v_tx_polarity := mac_ser_i.llc_metadata.ftyp;   -- RTR
              end if;
              v_bit_driven := true;
              if (bit_count > c_base_id_width) then
                state <= s_fdf_r1_r0;
              else
                state <= s_ide;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_ide : IDE bit. Dominant for base, recessive for extended.
          -----------------------------------------------------------------
          when s_ide =>
            if (pcs_i.sample_point = '1' and bs_i.valid = '0') then
              v_tx_polarity := mac_ser_i.llc_metadata.ide;
              v_bit_driven  := true;
              if (mac_ser_i.llc_metadata.ide = c_recessive) then
                state <= s_id;
              else
                state <= s_fdf_r1_r0;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_fdf_r1_r0 : FDF (FD) or r0/r1 (CC). start_tdc on FD entry.
          -----------------------------------------------------------------
          when s_fdf_r1_r0 =>
            if (pcs_i.sample_point = '1' and bs_i.valid = '0') then
              v_tx_polarity   := mac_ser_i.llc_metadata.fdf;
              v_bit_driven    := true;
              -- Signal PCS to start Transmitter Delay Compensation (ISO : 7.3.4)
              pcs_o.start_tdc <= '1' when mac_ser_i.llc_metadata.fdf = '1';
              if (mac_ser_i.llc_metadata.fdf = c_recessive or mac_ser_i.llc_metadata.ide = '1') then
                state <= s_res_r0;
              else
                state     <= s_dlc;
                bit_count <= 0;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_res_r0 : Reserved bit (dominant).
          -----------------------------------------------------------------
          when s_res_r0 =>
            if (pcs_i.sample_point = '1' and bs_i.valid = '0') then
              v_tx_polarity := c_dominant;
              v_bit_driven  := true;
              if (mac_ser_i.llc_metadata.fdf = '1') then
                state <= s_brs;
              else
                state     <= s_dlc;
                bit_count <= 0;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_brs : BRS bit (FD only). Signals PCS to switch bit rate
          -----------------------------------------------------------------
          when s_brs =>
            if (pcs_i.sample_point = '1' and bs_i.valid = '0') then
              v_tx_polarity       := mac_ser_i.llc_metadata.brs;
              pcs_o.use_data_rate <= mac_ser_i.llc_metadata.brs;
              v_bit_driven        := true;
              state               <= s_esi;
            end if;

          -----------------------------------------------------------------
          -- s_esi : ESI bit (FD only).
          -----------------------------------------------------------------
          when s_esi =>
            if (pcs_i.sample_point = '1' and bs_i.valid = '0') then
              v_tx_polarity := mac_ser_i.llc_metadata.esi;
              v_bit_driven  := true;
              state         <= s_dlc;
              bit_count     <= 0;
            end if;

          -----------------------------------------------------------------
          -- s_dlc : DLC field from metadata.
          -----------------------------------------------------------------
          when s_dlc =>
            if (pcs_i.sample_point = '1' and bs_i.valid = '0') then
              v_tx_polarity := mac_ser_i.llc_metadata.dlc(c_dlc_field_width - 1 - bit_count);
              v_bit_driven  := true;
              if (bit_count = c_dlc_field_width - 1) then
                bit_count <= 0;
                if (data_len > 0) then
                  state <= s_data;
                elsif (mac_ser_i.llc_metadata.fdf = '1') then
                  state      <= s_sbc;
                else
                  state <= s_crc;
                end if;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_data : Data field, bits from mac_ser.
          -----------------------------------------------------------------
          when s_data =>
            if (pcs_i.sample_point = '1' and bs_i.valid = '0') then
              v_tx_polarity   := mac_ser_i.data;
              v_bit_driven    := true;
              mac_ser_o.ready <= '1';
              if (bit_count = data_len * c_byte_width - 1) then
                bit_count <= 0;
                if (mac_ser_i.llc_metadata.fdf = '1') then
                  state      <= s_sbc;
                else
                  state <= s_crc;
                end if;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_sbc : Stuff bit count field from bit stuffer (ISO : 6.6.11.5).
          -----------------------------------------------------------------
          when s_sbc =>
            if (pcs_i.sample_point = '1' and bs_i.valid = '0') then
              v_tx_polarity := bs_i.stuff_bit_count((c_sbc_field_width - 1) - bit_count);
              v_bit_driven  := true;
              if (bit_count = c_sbc_field_width - 1) then
                state     <= s_crc;
                bit_count <= 0;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_crc : CRC bits then CRC delimiter (ISO : 6.6.10.5,
          -- 6.6.11.5). Drops use_data_rate at CRC delimiter.
          -----------------------------------------------------------------
          when s_crc =>
            if (pcs_i.sample_point = '1' and bs_i.valid = '0') then
              v_bit_driven  := true;

              if (bit_count < crc_length) then
                v_tx_polarity := crc_i.crc((c_crc_21_length - 1) - bit_count);
                bit_count     <= bit_count + 1;
              else
                -- CRC delimiter (single recessive).
                pcs_o.use_data_rate <= '0';
                state               <= s_ack;
                bit_count           <= 0;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_ack : CC ACK slot (1 bit) + delim (1 bit) = 2 bits (ISO 6.6.10.6).
          -- FD ACK slot (2 bits) + delim (1 bit) = 3 bits (ISO 6.6.11.6).
          -----------------------------------------------------------------
          when s_ack =>
            if (pcs_i.sample_point = '1') then
              v_tx_polarity := c_recessive;
              v_bit_driven  := true;

              if (bit_count = 0) then
                bit_count <= 1;
                if (pcs_i.bus_polarity = c_dominant) then
                  ack_success_seen <= true;
                end if;
              elsif (bit_count = 1 and mac_ser_i.llc_metadata.fdf = '1') then
                bit_count <= 2;
                if (pcs_i.bus_polarity = c_dominant) then
                  ack_success_seen <= true;
                end if;
              else
                state     <= s_eof;
                bit_count <= 0;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_eof : 7 recessive bits (ISO : 6.6.10.7, 6.6.11.7).
          -- ACK error is evaluated at bit_count = 0 of EOF field (ISO : 6.6.21.3.1, 6.6.15.2)
          -----------------------------------------------------------------
          when s_eof =>
            if (pcs_i.sample_point = '1') then
              v_tx_polarity := c_recessive;
              v_bit_driven  := true;
              bit_count     <= bit_count + 1;

              -- ACK error: no dominant seen in ACK slot (ISO : 6.6.21.3.1).
              if (bit_count = 0 and not ack_success_seen) then
                v_enter_error         := true;
                v_ack_error           := true;
                ack_error_caused_flag <= true;
              end if;

              -- Dominant in EOF bits 0..5 is a form error (ISO : 6.6.21.3.2,a).
              if (bit_count < c_eof_field_width - 1 and pcs_i.bus_polarity = c_dominant) then
                v_enter_error := true;
              end if;

              -- Last EOF bit: frame successfully transmitted. A dominant here
              -- is an overload condition, not a bit error (ISO : 6.6.21.3.2,b).
              if (bit_count = c_eof_field_width - 1) then
                mac_ser_o.transfer_status <= c_transmitted;
                was_previous_frame_tx     <= true;
                fce_o.successful_transfer <= '1';
                bit_count                 <= 0;
                if (pcs_i.bus_polarity = c_dominant) then
                  v_bit_driven        := false; -- bypass generic bit-error path
                  state               <= s_error_overload;
                  overload            <= true;
                  dominant_run_count  <= 0;
                  pcs_o.polarity      <= c_dominant;
                  pcs_o.use_data_rate <= '0';
                  pcs_o.start_tdc     <= '0';
                else
                  state <= s_intermission;
                end if;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_error_overload : Error flag (active/passive) or overload
          -----------------------------------------------------------------
          when s_error_overload =>
            if (pcs_i.sample_point = '1') then
              -----------------------------------------------------------------
              -- Count flag bits
              -----------------------------------------------------------------
              if (bit_count < c_error_flag_width - 1) then
                -- Passive flag requires 6 consecutive recessive bits so restart count on dominant.
                if (not overload and fce_i.error_active = '0' and pcs_i.bus_polarity = c_dominant) then
                  -- Track dominant observation for the ISO 8.1.4.2.c  Exemption 1.
                  saw_dominant_during_flag <= true;
                  bit_count <= 0;
                else
                  bit_count <= bit_count + 1;
                end if;
              else
                -----------------------------------------------------------------
                -- Flag complete: release bus to recessive and transition to
                -- delimiter. Monitor bus for dominant-run behaviour there
                -- (ISO 8.1.4.2 rule f, primary-error ISO 8.1.3.3 Table 16).
                -----------------------------------------------------------------
                dominant_run_count <= 0;
                bit_count          <= 0;
                overload           <= false;
                state              <= s_error_delimiter;
                pcs_o.polarity     <= c_recessive;
                if (ack_error_caused_flag) then
                  fce_o.error                       <= '1';
                  fce_o.passive_tx_ack_error_exempt <= '1' when fce_i.error_active = '0' and not saw_dominant_during_flag;
                end if;
              end if;
            end if;

          when s_error_delimiter =>
            if (pcs_i.sample_point = '1') then
              pcs_o.polarity <= c_recessive;
              if (pcs_i.bus_polarity = c_dominant) then
                -- Dominant during delimiter: track primary-error / delimiter-too-late.
                if (dominant_run_count = c_error_delimiter_width - 1) then
                  fce_o.error_delimiter_too_late <= '1';
                  dominant_run_count <= 0;
                else
                  fce_o.primary_error <= '1' when not overload and dominant_run_count = 0;
                  dominant_run_count  <= dominant_run_count + 1;
                end if;
                -- Dominant at last delimiter bit is overload (ISO : 6.6.21.3.2,b);
                -- dominant earlier is a form error.
                overload       <= (bit_count = c_error_delimiter_width - 2);
                fce_o.error    <= '1' when bit_count /= c_error_delimiter_width - 2;
                bit_count      <= 0;
                state          <= s_error_overload;
                pcs_o.polarity <= c_dominant;
              else
                if (bit_count = c_error_delimiter_width - 2) then
                  state     <= s_intermission;
                  bit_count <= 0;
                else
                  bit_count <= bit_count + 1;
                end if;
              end if;
            end if;

          when others =>
            state     <= s_bus_reintegration;
            bit_count <= 0;
        end case;

        -----------------------------------------------------------------
        -- Drive bit, error entry, or arbitration loss.
        -----------------------------------------------------------------
        if (v_bit_driven) then
          -- React to SSP-deferred bit error (ISO 7.3.4)
          if (secondary_sample_point_error_pending) then
            v_enter_error     := true;
            secondary_sample_point_error_pending <= false;
          end if;

          -- Only detect errors at the sample point if we are not using transmitter delay compensation (use_data_rate = '0').
          if (pcs_o.use_data_rate = '0' and polarity_history(0) /= pcs_i.bus_polarity) then
            if (v_in_arbitration_field and pcs_i.bus_polarity = c_dominant) then
              v_lost_arb := true; -- Recessive bit sent, dominant observed in arbitration field is lost arbitration
            elsif (not v_in_ack_slot) then
              v_enter_error := true; -- Mismatch outside of the ACK slot is a bit error
            end if;
          end if;

          if v_enter_error then -- Error was detected
            -- ACK errors must defer fce_o.error to flag-end so the exemption decision (ISO 8.1.4.2 c) Exc.1) can accompany the strobe.
            fce_o.error               <= '1' when not v_ack_error;
            pcs_o.polarity            <= c_recessive when fce_i.error_active = '0' else c_dominant;
            pcs_o.use_data_rate       <= '0';
            mac_ser_o.transfer_status <= c_disturbed;
            was_previous_frame_tx     <= true;
            bit_count                 <= 0;
            dominant_run_count        <= 0;
            state                     <= s_error_overload;
            overload                  <= false;
            pcs_o.start_tdc                   <= '0';
          elsif v_lost_arb then -- Lost arbitration
            mac_ser_o.transfer_status <= c_lost_arb;
            was_previous_frame_tx     <= false;
            bit_count                 <= 0;
            state                     <= s_intermission;
          else -- Drive bit
            pcs_o.polarity   <= v_tx_polarity;
            -- Push to polarity history
            polarity_history <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & v_tx_polarity;
            -- Feed bit stuffer
            bs_o.valid <= '1';
            bs_o.data  <= v_tx_polarity;
            -- FD CRC: all dynamic stuff bits + SBC data bits (ISO 6.6.11.5)
            if (v_in_dynamic_stuff_field or (not v_is_stuff_bit and state = s_sbc)) then
              crc_o.valid_fd <= '1';
              crc_o.data_fd  <= v_tx_polarity;
            end if;
            -- CC CRC: non-stuff DSB bits only (ISO 6.6.10.5)
            if (not v_is_stuff_bit and v_in_dynamic_stuff_field) then
              crc_o.valid_cc <= '1';
              crc_o.data_cc  <= v_tx_polarity;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process p_fsm;
end architecture rtl;

-- eof
