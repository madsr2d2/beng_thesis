--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Media Access Control (MAC) FSM for CAN/CAN-FD transmission.
--                Coordinates serialization, bit stuffing, CRC generation, and
--                physical signaling (PCS) timing.
--                Protocol references: ISO 11898-1:2015
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
    -- Fault Confinement Entity interface (ISO 11898-1 Table 16/17)
    fce_i : in    t_can_mac_fce_if_s2m;
    fce_o : out   t_can_mac_fce_if_m2s
  );
end entity can_mac_fsm_tx;

architecture rtl of can_mac_fsm_tx is

  type t_fsm_state is (
    s_bus_reintegration, s_intermission, s_suspend_transmission, s_bus_idle,
    s_sof, s_id, s_rtr_srr_rrs, s_ide, s_fdf_r1_r0, s_res_r0, s_brs, s_esi,
    s_dlc, s_data, s_sbc, s_crc, s_ack, s_eof,
    s_error_overload
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

  -- Frame metadata (read directly from serializer; held stable for frame)
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
    variable v_in_frame     : boolean;  -- In active frame transmission (drives fce_o.transmitting)

    -- Bit transmission and monitoring results
    variable v_tx_polarity : std_logic; -- Polarity to drive onto bus
    variable v_bit_driven  : boolean;   -- A bit was driven this SP
    variable v_is_stuff_bit : boolean;  -- The driven bit was a stuff bit (BS-sourced)
    variable v_lost_arb    : boolean;   -- Arbitration lost
    variable v_enter_error : boolean;   -- Enter error flag state (bit/SSP/ACK error)

  begin

    if rising_edge(clk_i) then
      if (rst_i = '1') then
        state                     <= s_bus_reintegration;
        flag_type                 <= active_error;
        bit_count                 <= 0;
        polarity_history          <= (others => c_recessive);
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
        -- start_tdc pulse is held for one bit time, cleared at next SP.
        if (pcs_i.sp = '1') then
          pcs_o.start_tdc <= '0';
        end if;

        -----------------------------------------------------------------
        -- Guard predicates
        -----------------------------------------------------------------
        v_in_arb_field := state = s_id or state = s_rtr_srr_rrs or state = s_ide;
        v_in_dsb_field := v_in_arb_field or state = s_fdf_r1_r0 or state = s_res_r0 or state = s_brs or state = s_esi or state = s_dlc or state = s_data;
        v_in_fsb_field := state = s_sbc or state = s_crc;
        v_in_frame     := v_in_dsb_field or v_in_fsb_field or state = s_sof or state = s_ack or state = s_eof;
        fce_o.transmitting <= '1' when v_in_frame else '0';

        v_bit_driven   := false;
        v_is_stuff_bit := false;
        v_lost_arb     := false;
        v_enter_error  := false;
        v_tx_polarity  := c_recessive;

        -----------------------------------------------------------------
        -- Quiet-state defaults (not transmitting a frame)
        -----------------------------------------------------------------
        if (state = s_bus_reintegration or state = s_intermission or state = s_suspend_transmission or state = s_bus_idle) then
          pcs_o.valid               <= '0';
          pcs_o.polarity            <= c_recessive;
          pcs_o.use_data_rate       <= '0';
          pcs_o.start_tdc           <= '0';
          fce_o.transmitting        <= '0';
          ssp_error_pending         <= false;
          mac_ser_o.transfer_status <= c_ongoing;
        end if;

        -----------------------------------------------------------------
        -- Enable fixed stuff bit (FSB) mode for SBC and FD CRC fields
        -- (ISO 11898-1: 6.6.13.3)
        -----------------------------------------------------------------
        if (state = s_sbc) then
          bs_o.fsb_en <= '1';
        elsif (state = s_crc and crc_length /= c_crc_15_length) then
          bs_o.fsb_en <= '1';
        end if;

        -- SSP: latch deferred bit error (ISO 7.3.4)
        if (pcs_i.ssp = '1' and (v_in_dsb_field or v_in_fsb_field)) then
          if (polarity_history(to_integer(unsigned(pcs_i.tdc_delay))) /= pcs_i.bus_polarity) then
            ssp_error_pending <= true;
          end if;
        end if;

        -----------------------------------------------------------------
        -- Stuff bit: BS has a pending bit, drive it instead of the FSM's.
        -----------------------------------------------------------------
        if (pcs_i.sp = '1' and (v_in_dsb_field or v_in_fsb_field)) then
          if (bs_i.valid = '1') then
            v_tx_polarity  := bs_i.data;
            v_bit_driven   := true;
            v_is_stuff_bit := true;
          end if;
        end if;

        -----------------------------------------------------------------
        -- State machine
        -----------------------------------------------------------------
        case state is

          -----------------------------------------------------------------
          -- s_bus_reintegration : Wait for 11 consecutive recessive bits
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
          -- s_intermission : 3-bit inter-frame spacing (ISO 11898-1: 6.6.7.2)
          -----------------------------------------------------------------
          when s_intermission =>
            if (pcs_i.sp = '1') then
              if (pcs_i.bus_polarity = c_dominant) then
                if (bit_count < c_intermission_width - 1) then
                  -- ISO 6.6.21.3.2 b): dominant during first two bits
                  state                     <= s_error_overload;
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
          -- s_suspend_transmission : Error-passive TX waits 8 extra bits
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
          -- s_bus_idle : Ready for new frame (ISO 11898-1: 6.6.7.3)
          -----------------------------------------------------------------
          when s_bus_idle =>
            if (mac_ser_i.valid = '1' and pcs_i.sp = '1') then
              state     <= s_sof;
              bit_count <= 0;
              bs_rst    <= '1';
              crc_rst   <= '1';
            end if;

          -----------------------------------------------------------------
          -- s_sof : Drive SOF (dominant) and feed BS/CRC. Runs once on
          -- entry (not SP-gated). skip_sof (ISO 6.6.8): SOF is already
          -- on the bus from the 3rd intermission dominant, drive and
          -- feed the first ID bit directly instead.
          -----------------------------------------------------------------
          when s_sof =>
            pcs_o.valid         <= '1';
            pcs_o.use_data_rate <= '0';
            pcs_o.start_tdc     <= '0';

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

            -- Reset tracking
            ack_success_seen          <= false;
            ssp_error_pending         <= false;
            ack_error_caused_flag     <= false;
            dominant_seen_during_flag <= false;
            dominant_run_count        <= 0;
            fsb_active                <= '0';

            bs_o.valid     <= '1';
            crc_o.valid_cc <= '1';
            crc_o.valid_fd <= '1';

            if (skip_sof) then
              -- SOF already on bus: drive and feed first ID bit directly
              pcs_o.polarity   <= mac_ser_i.data;
              bs_o.data        <= mac_ser_i.data;
              crc_o.data_cc    <= mac_ser_i.data;
              crc_o.data_fd    <= mac_ser_i.data;
              mac_ser_o.ready  <= '1';
              polarity_history <= (0 => mac_ser_i.data, others => c_recessive);
              bit_count        <= 1;
              skip_sof         <= false;
            else
              pcs_o.polarity   <= c_dominant;
              bs_o.data        <= c_dominant;
              crc_o.data_cc    <= c_dominant;
              crc_o.data_fd    <= c_dominant;
              polarity_history <= (0 => c_dominant, others => c_recessive);
              bit_count        <= 0;
            end if;

            state <= s_id;

          -----------------------------------------------------------------
          -- s_id : Base ID (11 bits) or extended ID (18 bits) from ser.
          -----------------------------------------------------------------
          when s_id =>
            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              v_tx_polarity   := mac_ser_i.data;
              v_bit_driven    := true;
              mac_ser_o.ready <= '1';
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
            if (pcs_i.sp = '1' and bs_i.valid = '0') then
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
          -- s_ide : IDE bit. Dominant for basic, recessive for extended.
          -----------------------------------------------------------------
          when s_ide =>
            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              v_tx_polarity := mac_ser_i.llc_metadata.ide;
              v_bit_driven  := true;
              if (mac_ser_i.llc_metadata.ide = c_recessive) then
                state <= s_id;    -- continue with extended ID (bits 11..28)
              else
                state <= s_fdf_r1_r0;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_fdf_r1_r0 : FDF (FD) or r0/r1 (CC). start_tdc on FD entry.
          -----------------------------------------------------------------
          when s_fdf_r1_r0 =>
            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              v_tx_polarity   := mac_ser_i.llc_metadata.fdf;
              v_bit_driven    := true;
              pcs_o.start_tdc <= '1' when mac_ser_i.llc_metadata.fdf = '1' else '0';
              if (mac_ser_i.llc_metadata.fdf = c_recessive or mac_ser_i.llc_metadata.ide = '1') then
                state <= s_res_r0;
              else
                state     <= s_dlc;
                bit_count <= 0;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_res_r0 : Reserved bit (dominant). FD -> BRS, CC ext -> DLC.
          -----------------------------------------------------------------
          when s_res_r0 =>
            if (pcs_i.sp = '1' and bs_i.valid = '0') then
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
          -- at the BRS/ESI boundary (ISO 11898-1: 10.4.2.3.1).
          -----------------------------------------------------------------
          when s_brs =>
            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              v_tx_polarity       := mac_ser_i.llc_metadata.brs;
              v_bit_driven        := true;
              pcs_o.use_data_rate <= mac_ser_i.llc_metadata.brs;
              state               <= s_esi;
            end if;

          -----------------------------------------------------------------
          -- s_esi : ESI bit (FD only).
          -----------------------------------------------------------------
          when s_esi =>
            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              v_tx_polarity := mac_ser_i.llc_metadata.esi;
              v_bit_driven  := true;
              state         <= s_dlc;
              bit_count     <= 0;
            end if;

          -----------------------------------------------------------------
          -- s_dlc : 4-bit DLC field from metadata.
          -----------------------------------------------------------------
          when s_dlc =>
            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              v_tx_polarity := mac_ser_i.llc_metadata.dlc(c_dlc_field_width - 1 - bit_count);
              v_bit_driven  := true;
              if (bit_count = c_dlc_field_width - 1) then
                bit_count <= 0;
                if (data_len > 0) then
                  state <= s_data;
                elsif (mac_ser_i.llc_metadata.fdf = '1') then
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
          -- s_data : Data field, bits from serializer.
          -----------------------------------------------------------------
          when s_data =>
            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              v_tx_polarity   := mac_ser_i.data;
              v_bit_driven    := true;
              mac_ser_o.ready <= '1';
              if (bit_count = data_len * c_byte_width - 1) then
                bit_count <= 0;
                if (mac_ser_i.llc_metadata.fdf = '1') then
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
          -- s_sbc : Stuff bit count field (FD only, 4 bits) from bit stuffer.
          -----------------------------------------------------------------
          when s_sbc =>
            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              v_tx_polarity := bs_i.sbc((c_sbc_field_width - 1) - bit_count);
              v_bit_driven  := true;
              if (bit_count = c_sbc_field_width - 1) then
                state     <= s_crc;
                bit_count <= 0;
              else
                bit_count <= bit_count + 1;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_crc : CRC bits then CRC delimiter (ISO 11898-1: 6.6.10.5,
          -- 6.6.11.5). Drops use_data_rate/fsb_active before the delimiter.
          -----------------------------------------------------------------
          when s_crc =>
            if (pcs_i.sp = '1' and bs_i.valid = '0') then
              if (bit_count < crc_length) then
                v_tx_polarity := crc_i.crc((c_crc_21_length - 1) - bit_count);
                v_bit_driven  := true;
                bit_count     <= bit_count + 1;
              else
                -- CRC delimiter (single recessive).
                v_tx_polarity       := c_recessive;
                v_bit_driven        := true;
                pcs_o.use_data_rate <= '0';
                fsb_active          <= '0';
                state               <= s_ack;
                bit_count           <= 0;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_ack : ACK slot (bc=0) and ACK delimiter (bc=1), both recessive.
          -- (ISO 11898-1: 6.6.10.6, 6.6.11.6).
          -----------------------------------------------------------------
          when s_ack =>
            if (pcs_i.sp = '1') then
              v_tx_polarity := c_recessive;
              v_bit_driven  := true;

              if (bit_count = 0) then
                bit_count <= 1;
                -- CC (ISO 6.6.10.6): ACK slot is bc=1 only.
                ack_success_seen <= true when pcs_i.bus_polarity = c_dominant else false;
              else
                -- FD (ISO 6.6.11.6): accept dominant at either bc=0 or bc=1
                ack_success_seen <= true when ack_success_seen or (pcs_i.bus_polarity = c_dominant and mac_ser_i.llc_metadata.fdf = '1') else false;
                state     <= s_eof;
                bit_count <= 0;
              end if;
            end if;

          -----------------------------------------------------------------
          -- s_eof : 7 recessive bits (ISO 11898-1: 6.6.10.7, 6.6.11.7).
          -- ACK error enters the error flag at bc=0 (the bit following
          -- the ACK delimiter, per ISO 6.6.10.6).
          -----------------------------------------------------------------
          when s_eof =>
            if (pcs_i.sp = '1') then
              v_tx_polarity := c_recessive;
              v_bit_driven  := true;
              if (bit_count = 0 and not ack_success_seen) then
                v_enter_error         := true;
                v_bit_driven          := false;
                ack_error_caused_flag <= true;
              end if;
              if (bit_count = c_eof_field_width - 1) then
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
          -- s_error_overload : Error flag (active/passive) or overload
          -- flag, followed by 8-bit recessive delimiter (ISO 11898-1:
          -- 6.6.5, 6.6.6).
          -----------------------------------------------------------------
          when s_error_overload =>
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

            -- Flag polarity: 6 dominant (active/overload) or 6 recessive
            -- (passive), then 8 recessive delimiter
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
                if (bit_count = c_error_sequence_width - 1 and not dominant_seen_during_flag) then
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
        -- Bit error / arb-loss monitor (SP-gated): driven bit vs sampled.
        -- Clearing v_bit_driven inline keeps the post-case effects chain
        -- mutually exclusive.
        -----------------------------------------------------------------
        if (pcs_i.sp = '1' and (v_in_dsb_field or v_in_fsb_field or state = s_ack or state = s_eof)) then
          if (polarity_history(to_integer(unsigned(pcs_i.tdc_delay))) /= pcs_i.bus_polarity) then
            if (v_in_arb_field and pcs_i.bus_polarity = c_dominant) then
              v_lost_arb   := true;
              v_bit_driven := false;
            elsif not (state = s_ack and (bit_count = 0 or bit_count = 1)) then
              v_enter_error := true;
              v_bit_driven  := false;
            end if;
          end if;
        end if;

        -- SSP-deferred bit error latched at SP (ISO 7.3.4)
        if (pcs_i.sp = '1' and ssp_error_pending) then
          v_enter_error     := true;
          v_bit_driven      := false;
          ssp_error_pending <= false;
        end if;

        -----------------------------------------------------------------
        -- Post-case effects: normal drive, error entry, or arb loss.
        -- Mutually exclusive by construction (see suppression above and
        -- the monitor block that sets v_enter_error / v_lost_arb).
        -----------------------------------------------------------------
        if (v_bit_driven) then
          pcs_o.valid      <= '1';
          pcs_o.polarity   <= v_tx_polarity;
          polarity_history <= polarity_history(c_tdc_polarity_depth - 2 downto 0) & v_tx_polarity;

          -- BS feed: every bit in a stuffing region except the CRC delimiter
          if (v_in_dsb_field or state = s_sbc or (state = s_crc and bit_count < crc_length) or v_is_stuff_bit) then
            bs_o.valid <= '1';
            bs_o.data  <= v_tx_polarity;
          end if;

          -- CRC feed. ISO 6.6.4.4: only FD dynamic stuff bits feed the FD
          -- CRC; fixed stuff bits (s_sbc / FD s_crc) feed no CRC.
          if (v_is_stuff_bit and v_in_dsb_field and
              mac_ser_i.llc_metadata.fdf = '1' and fsb_active = '0') then
            crc_o.valid_fd <= '1';
            crc_o.data_fd  <= v_tx_polarity;
          elsif (not v_is_stuff_bit and v_in_dsb_field) then
            crc_o.valid_cc <= '1';
            crc_o.valid_fd <= '1';
            crc_o.data_cc  <= v_tx_polarity;
            crc_o.data_fd  <= v_tx_polarity;
          elsif (not v_is_stuff_bit and state = s_sbc) then
            crc_o.valid_fd <= '1';
            crc_o.data_fd  <= v_tx_polarity;
          end if;

        elsif (v_enter_error) then
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
          state                     <= s_error_overload;
          flag_type                 <= passive_error when fce_i.error_passive_request = '1' else active_error;
        elsif (v_lost_arb) then
          mac_ser_o.transfer_status <= c_lost_arb;
          was_previous_frame_tx     <= false;
          bit_count                 <= 0;
          state                     <= s_intermission;
        end if;

      end if;
    end if;

  end process p_fsm;

end architecture rtl;
