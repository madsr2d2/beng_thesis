--------------------------------------------------------------------------------
-- Title      : CAN Physical Signaling Layer (PCS) with TDC
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : tx_pcs.vhd
-- Author     :
-- Created    : 2026-02-13
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Physical Signaling layer implementing bit timing, transmission,
--              and Transmitter Delay Compensation (TDC) per ISO 11898-1:2024
--              Section 7.2 (PCS Services) and 7.3.4 (TDC).
--
-- Responsibilities:
--   - Bit timing generation (nominal and data bit rates)
--   - Serial bit transmission to bus
--   - TDC delay measurement at FDF->res edge
--   - Sample Point (SP) and Secondary Sample Point (SSP) generation
--   - Bus monitoring (RX input for loopback and delay measurement)
--
-- FSM State Transitions:
--   idle -> transmitting_nominal              (data_request = '1')
--   transmitting_nominal -> measuring_delay   (current_bit = res_bit)
--   measuring_delay -> transmitting_data      (RX dominant detected)
--   measuring_delay -> transmitting_nominal   (timeout: delay_count >= max_transmitter_delay_c)
--   transmitting_data -> transmitting_nominal (crc_delimiter_bit detected)
--   any non-idle -> idle                      (data_request = '0')
--
-- Timing model:
--   data_request: MAC holds high throughout the entire frame (frame active)
--   SP/SSP strobes: MAC reacts to sample point strobes and has PHASE_SEG2
--   to compute and present the next frame_bit before the bit boundary
--   PCS latches frame_bit at each bit boundary
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

entity tx_pcs is
  generic (
    -- Nominal bit timing (arbitration phase)
    nom_prescaler  : prescalar    := 2; -- Prescaler for nominal bit time
    nom_sync_seg   : sync_seg     := 1;
    nom_prop_seg   : nom_prop_seg := 8;
    nom_phase_seg1 : phase_seg1   := 8;
    nom_phase_seg2 : phase_seg2   := 8;

    -- Data bit timing (FD data phase)
    data_prescaler  : prescalar     := 1; -- Prescaler for data bit time (faster)
    data_sync_seg   : sync_seg      := 1;
    data_prop_seg   : data_prop_seg := 4;
    data_phase_seg1 : phase_seg1    := 4;
    data_phase_seg2 : phase_seg2    := 4;
    ssp_offset      : ssp_offset    := 4;
    -- Inputs to should_use_tdc() policy (ISO 7.3.4).
    system_clock_freq_hz            : integer := 100_000_000;
    pcs_to_pma_propagation_delay_ns : integer := 600
  );
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    -- MAC to PCS interface (receive frame bits from MAC)
    mac_to_pcs_i : in    mac_to_pcs_if_t;

    -- PCS to MAC interface (send timing strobes and FIFO index to MAC)
    pcs_to_mac_o : out   pcs_to_mac_if_t;

    -- Bus interface (physical layer)
    tx_bus_o : out   std_logic; -- Transmitted bit to bus
    rx_bus_i : in    std_logic  -- Received bit from bus (only for monitoring in TX side)
  );
end entity tx_pcs;

architecture rtl of tx_pcs is

  -- Bit timing constants
  constant nom_bit_time     : integer := nom_sync_seg + nom_prop_seg + nom_phase_seg1 + nom_phase_seg2;
  constant data_bit_time    : integer := data_sync_seg + data_prop_seg + data_phase_seg1 + data_phase_seg2;
  constant sp_position      : integer := nom_sync_seg + nom_prop_seg + nom_phase_seg1; -- SP at end of Phase_Seg1
  constant data_sp_position : integer := data_sync_seg + data_prop_seg + data_phase_seg1;
  constant use_tdc_c        : boolean := should_use_tdc(
                                                        system_clock_freq               => system_clock_freq_hz,
                                                        prescaler_cfg                   => data_prescaler,
                                                        sync_seg_cfg                    => data_sync_seg,
                                                        prop_seg_fd                     => data_prop_seg,
                                                        phase_seg1_fd                   => data_phase_seg1,
                                                        phase_seg2_fd                   => data_phase_seg2,
                                                        pcs_to_pma_propagation_delay_ns => pcs_to_pma_propagation_delay_ns
                                                      );

  -- Maximum transmitter delay: 255 t_q.min (SSP offset 160 + delay 95)
  -- ISO 11898-1:2015 Section 7.3.4

  -- Maximum FIFO index: (max_transmitter_delay_c + ssp_offset) / data_bit_time must fit in FIFO
  constant max_fifo_index : integer := (max_transmitter_delay_c + ssp_offset) / data_bit_time;

  -- FSM state
  signal state      : tx_pcs_fsm_state_t := idle;
  signal next_state : tx_pcs_fsm_state_t;

  -- Time quantum tick generators
  signal nom_tq_tick    : std_logic                             := '0';
  signal data_tq_tick   : std_logic                             := '0';
  signal clk_count_nom  : integer range 0 to nom_prescaler - 1  := 0;
  signal clk_count_data : integer range 0 to data_prescaler - 1 := 0;

  -- Bit time counter (counts TQ within current bit)
  signal tq_count : integer range 0 to nom_bit_time := 0;

  -- Current bit being transmitted
  signal current_bit : mac_frame_bit_t := (polarity => recessive, bit_name => unknown);

  -- TDC measurement signals
  signal delay_count            : integer range 0 to max_transmitter_delay_c           := 0;
  signal ssp_position           : integer range 0 to data_bit_time - 1                 := 0;
  signal fifo_index             : integer range 0 to transmitted_bits_fifo_depth_c - 1 := 0;
  signal effective_fifo_index   : integer range 0 to transmitted_bits_fifo_depth_c - 1 := 0;
  signal effective_fifo_index_r : integer range 0 to transmitted_bits_fifo_depth_c - 1 := 0;

  -- Sample point pulses
  signal sp_pulse        : std_logic := '0';
  signal ssp_pulse       : std_logic := '0';
  signal sample_strobe   : std_logic := '0';
  signal sample_strobe_r : std_logic := '0';

begin

  -- Validate generic constraints at elaboration time
  assert ssp_offset <= data_bit_time
    report "ssp_offset (" & integer'image(ssp_offset) &
           ") exceeds data_bit_time (" & integer'image(data_bit_time) &
           ") - SSP would compare against wrong FIFO entry"
    severity failure;

  assert max_fifo_index < transmitted_bits_fifo_depth_c
    report "Maximum FIFO index (" & integer'image(max_fifo_index) &
           ") exceeds FIFO depth (" & integer'image(transmitted_bits_fifo_depth_c) &
           ") - FIFO index will saturate at extreme delays"
    severity warning;

  assert (not use_tdc_c) or (data_prescaler = 1 or data_prescaler = 2)
    report "TDC enabled while data_prescaler is not 1 or 2 (ISO 7.3.4 recommendation)"
    severity warning;

  -- Output assignments
  pcs_to_mac_o.bus_polarity  <= std_logic_to_polarity(rx_bus_i);
  pcs_to_mac_o.sample_strobe <= sample_strobe_r;
  pcs_to_mac_o.fifo_index    <= effective_fifo_index_r;
  tx_bus_o                   <= polarity_to_std_logic(current_bit.polarity);

  ------------------------------------------------------------------------------
  -- Time Quantum (TQ) Tick Generator
  ------------------------------------------------------------------------------
  tq_generator : process (clk) is
  begin

    if rising_edge(clk) then
      if (rst = '1') then
        clk_count_nom  <= 0;
        clk_count_data <= 0;
        nom_tq_tick    <= '0';
        data_tq_tick   <= '0';
      else
        nom_tq_tick  <= '0';
        data_tq_tick <= '0';

        -- Nominal TQ tick
        if (clk_count_nom = nom_prescaler - 1) then
          nom_tq_tick   <= '1';
          clk_count_nom <= 0;
        else
          clk_count_nom <= clk_count_nom + 1;
        end if;

        -- Data TQ tick
        -- Only run data-phase prescaler when data timing is consumed.
        if (state = measuring_delay or state = transmitting_data) then
          if (clk_count_data = data_prescaler - 1) then
            data_tq_tick   <= '1';
            clk_count_data <= 0;
          else
            clk_count_data <= clk_count_data + 1;
          end if;
        else
          clk_count_data <= 0;
        end if;

      end if;
    end if;

  end process tq_generator;

  ------------------------------------------------------------------------------
  -- State Register + Sequential Datapath (Clocked)
  ------------------------------------------------------------------------------
  pcs_fsm : process (clk) is

    -- Advance bit timing counter only. State logic owns data latching policy.
    procedure advance_bit_timing (
      tq_tick  : std_logic;
      bit_time : integer
    ) is
    begin

      if (tq_tick = '1') then
        if (tq_count >= bit_time - 1) then
          tq_count <= 0;
        else
          tq_count <= tq_count + 1;
        end if;
      end if;

    end procedure advance_bit_timing;

    variable delay_with_offset_v        : integer;
    variable ssp_position_v             : integer;
    variable entering_measuring_delay_v : boolean;
    variable returning_to_idle_v        : boolean;
    variable nominal_bit_boundary_v     : boolean;
    variable data_bit_boundary_v        : boolean;
    variable rx_dominant_v              : boolean;

  begin

    if rising_edge(clk) then
      if (rst = '1') then
        state        <= idle;
        tq_count     <= 0;
        current_bit  <= reset_mac_frame_bit_c;
        ssp_position <= 0;

        -- TDC measurement
        delay_count <= 0;
        fifo_index  <= 0;

      else
        entering_measuring_delay_v := (state /= measuring_delay and next_state = measuring_delay);
        returning_to_idle_v        := (next_state = idle and state /= idle);
        nominal_bit_boundary_v     := (nom_tq_tick = '1' and tq_count >= nom_bit_time - 1);
        data_bit_boundary_v        := (data_tq_tick = '1' and tq_count >= data_bit_time - 1);
        rx_dominant_v              := (rx_bus_i = dominant_bit_c);

        state <= next_state;

        -- Reset delay counter on entry to measuring_delay
        if (entering_measuring_delay_v) then
          delay_count <= 0;
        end if;

        -- Reset TDC outputs on return to idle
        if (returning_to_idle_v) then
          current_bit <= reset_mac_frame_bit_c;
          fifo_index  <= 0;
        end if;

        case state is

          when idle =>
            -- Keep nominal bit timing running in idle so MAC can monitor bus idle
            -- via sample points during reintegration/intermission checks.
            advance_bit_timing(nom_tq_tick, nom_bit_time);

            -- Wait for first bit request from MAC
            if (mac_to_pcs_i.valid) then
              current_bit <= mac_to_pcs_i.data;
              tq_count    <= 0;
            end if;

          when transmitting_nominal =>
            if (nominal_bit_boundary_v) then
              current_bit <= mac_to_pcs_i.data;
            end if;
            advance_bit_timing(nom_tq_tick, nom_bit_time);

          when measuring_delay =>
            if (nominal_bit_boundary_v) then
              current_bit <= mac_to_pcs_i.data;
            end if;
            advance_bit_timing(nom_tq_tick, nom_bit_time);

            -- Latch measurement results when RX detects dominant
            if (rx_dominant_v) then
              delay_with_offset_v := delay_count + ssp_offset;
              fifo_index          <= calculate_fifo_delay_index(delay_with_offset_v, data_bit_time);

              -- Derive in-bit SSP position without modulo operator.
              ssp_position_v := delay_with_offset_v;

              while (ssp_position_v >= data_bit_time) loop
                ssp_position_v := ssp_position_v - data_bit_time;
              end loop;

              ssp_position <= ssp_position_v;
            end if;

            -- Count delay from TX to RX detection (increment on data TQ ticks)
            if (data_tq_tick = '1' and delay_count < max_transmitter_delay_c) then
              delay_count <= delay_count + 1;
            end if;

          when transmitting_data =>
            if (data_bit_boundary_v) then
              current_bit <= mac_to_pcs_i.data;
            end if;
            advance_bit_timing(data_tq_tick, data_bit_time);

        end case;

      end if;
    end if;

  end process pcs_fsm;

  ------------------------------------------------------------------------------
  -- Next-State Logic (Combinational)
  ------------------------------------------------------------------------------
  next_state_logic : process (all) is

    variable frame_active_v : boolean;
    variable is_res_bit_v   : boolean;
    variable rx_dominant_v  : boolean;
    variable tdc_timeout_v  : boolean;
    variable is_crc_delim_v : boolean;

  begin

    frame_active_v := mac_to_pcs_i.valid;
    is_res_bit_v   := (current_bit.bit_name = res_bit);
    rx_dominant_v  := (rx_bus_i = dominant_bit_c);
    tdc_timeout_v  := (delay_count >= max_transmitter_delay_c);
    is_crc_delim_v := (current_bit.bit_name = crc_delimiter_bit);

    -- Default: stay in current state
    next_state <= state;

    -- Global: return to idle when MAC deasserts data_request (frame complete)
    if (state /= idle and not frame_active_v) then
      next_state <= idle;
    else

      case state is

        when idle =>
          if (frame_active_v) then
            next_state <= transmitting_nominal;
          end if;

        when transmitting_nominal =>
          -- Start TDC measurement when res bit detected (res_bit only exists in FD frames)
          if (is_res_bit_v) then
            if (use_tdc_c) then
              next_state <= measuring_delay;
            else
              next_state <= transmitting_data;
            end if;
          end if;

        when measuring_delay =>
          -- Measurement complete when RX detects dominant
          if (rx_dominant_v) then
            next_state <= transmitting_data;
          -- Timeout: abort TDC, fall back to nominal.
          -- Keep RX-dominant transition higher priority when both conditions coincide.
          elsif (tdc_timeout_v) then
            next_state <= transmitting_nominal;
          end if;

        when transmitting_data =>
          -- Exit data phase when CRC delimiter detected (PCS derives phase from bit_name)
          if (is_crc_delim_v) then
            next_state <= transmitting_nominal;
          end if;

      end case;

    end if;

  end process next_state_logic;

  ------------------------------------------------------------------------------
  -- Output Logic (Combinational): monitor selection
  ------------------------------------------------------------------------------
  monitor_select : process (all) is

    variable in_data_phase_v    : boolean;
    variable is_data_or_stuff_v : boolean;

  begin

    in_data_phase_v    := (state = transmitting_data);
    is_data_or_stuff_v := (current_bit.bit_name = data_bit or current_bit.bit_name = stuff_bit);

    -- Default to nominal-phase monitoring.
    sample_strobe        <= sp_pulse;
    effective_fifo_index <= 0;

    if (in_data_phase_v) then
      -- ISO intent: SSP monitoring is used in FD data field only when TDC is active.
      if (is_data_or_stuff_v) then
        if (use_tdc_c) then
          sample_strobe        <= ssp_pulse;
          effective_fifo_index <= fifo_index;
        else
          -- No TDC: compare at primary sample point with zero additional delay.
          sample_strobe        <= sp_pulse;
          effective_fifo_index <= 0;
        end if;
      end if;
    end if;

  end process monitor_select;

  ------------------------------------------------------------------------------
  -- Output Logic (Clocked): register monitor outputs for clean module boundary
  ------------------------------------------------------------------------------
  monitor_output_reg : process (clk) is
  begin

    if rising_edge(clk) then
      if (rst = '1') then
        sample_strobe_r        <= '0';
        effective_fifo_index_r <= 0;
      else
        sample_strobe_r        <= sample_strobe;
        effective_fifo_index_r <= effective_fifo_index;
      end if;
    end if;

  end process monitor_output_reg;

  ------------------------------------------------------------------------------
  -- Output Logic (Clocked): SP/SSP pulse generation
  ------------------------------------------------------------------------------
  sp_pulse_gen : process (clk) is
  begin

    if rising_edge(clk) then
      if (rst = '1') then
        sp_pulse  <= '0';
        ssp_pulse <= '0';
      else
        -- Default: no pulse
        sp_pulse  <= '0';
        ssp_pulse <= '0';

        case state is

          when idle | transmitting_nominal | measuring_delay =>
            -- Generate SP pulse at sample point position (nominal timing)
            -- tq_count increments on nom_tq_tick, so check count - 1 on tick
            if (nom_tq_tick = '1' and tq_count = sp_position - 1) then
              sp_pulse <= '1';
            end if;

          when transmitting_data =>
            if (use_tdc_c) then
              -- Generate SSP pulse once per data bit at the computed position within each bit.
              if (data_tq_tick = '1' and tq_count = ssp_position) then
                ssp_pulse <= '1';
              end if;
            else
              -- No TDC: use data-phase primary sample point.
              if (data_tq_tick = '1' and tq_count = data_sp_position - 1) then
                sp_pulse <= '1';
              end if;
            end if;

          when others =>
            null;

        end case;

      end if;
    end if;

  end process sp_pulse_gen;

end architecture rtl;
