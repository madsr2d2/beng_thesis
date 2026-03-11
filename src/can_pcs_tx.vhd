--------------------------------------------------------------------------------
-- Title      : CAN Physical Signaling Layer (PCS) with TDC
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : can_pcs_tx.vhd
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
--   idle -> transmitting_nominal              (mac_to_pcs_i.valid = '1')
--   transmitting_nominal -> measuring_delay   (FDF sample point, TDC enabled)
--   measuring_delay -> transmitting_data      (BRS bit boundary)
--   measuring_delay -> transmitting_nominal   (TDC timeout)
--   transmitting_data -> transmitting_nominal (CRC delimiter bit boundary)
--   any non-idle -> idle                      (mac_to_pcs_i.valid = '0')
--
-- Timing model:
--   MAC holds valid high throughout the frame. PCS generates SP/SSP strobes;
--   MAC reacts within PHASE_SEG2 to present the next frame_bit before the
--   bit boundary, where PCS latches it.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

entity can_pcs_tx is
  generic (
    -- detect ACK error at end of ACK-slot observation window.
    -- Default 100 MHz profile:
    --   Nominal phase: 500 kbit/s, SP = 80% (50 TQ @ 40 ns)
    nom_prescaler  : prescalar    := 4;
    nom_sync_seg   : sync_seg     := 1;
    nom_prop_seg   : nom_prop_seg := 24;
    nom_phase_seg1 : phase_seg1   := 15;
    nom_phase_seg2 : phase_seg2   := 10;

    -- Data phase: 2 Mbit/s, SP = 76% (25 TQ @ 20 ns)
    -- data_prescaler is constrained to 1 or 2 when TDC is used (ISO 7.3.4).
    data_prescaler  : prescalar     := 2;
    data_sync_seg   : sync_seg      := 1;
    data_prop_seg   : data_prop_seg := 8;
    data_phase_seg1 : phase_seg1    := 10;
    data_phase_seg2 : phase_seg2    := 6;
    ssp_offset      : ssp_offset    := 1;
    tdc_enable      : boolean       := true;
    -- Inputs to should_use_tdc() policy (ISO 7.3.4).
    system_clock_freq_hz            : integer := 100_000_000;
    pcs_to_pma_propagation_delay_ns : integer := 600
  );
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    mac_to_pcs_i : in    can_mac_pcs_tx_if_m2s_t;
    pcs_to_mac_o : out   can_mac_pcs_tx_if_s2m_t;

    tx_bus_o : out   std_logic;
    rx_bus_i : in    std_logic;

    -- Debug port (test visibility)
    debug_state_o : out can_pcs_tx_state_t
  );
end entity can_pcs_tx;

architecture rtl of can_pcs_tx is

  -- Bit timing constants
  constant nom_bit_time          : integer := nom_sync_seg + nom_prop_seg + nom_phase_seg1 + nom_phase_seg2;
  constant data_bit_time         : integer := data_sync_seg + data_prop_seg + data_phase_seg1 + data_phase_seg2;
  constant sp_position           : integer := nom_sync_seg + nom_prop_seg + nom_phase_seg1; -- SP at end of Phase_Seg1
  constant data_sp_position      : integer := data_sync_seg + data_prop_seg + data_phase_seg1;
  constant tdc_policy_use_c      : boolean := should_use_tdc(
                                                             system_clock_freq               => system_clock_freq_hz,
                                                             prescaler_cfg                   => data_prescaler,
                                                             sync_seg_cfg                    => data_sync_seg,
                                                             prop_seg_fd                     => data_prop_seg,
                                                             phase_seg1_fd                   => data_phase_seg1,
                                                             phase_seg2_fd                   => data_phase_seg2,
                                                             pcs_to_pma_propagation_delay_ns => pcs_to_pma_propagation_delay_ns
                                                           );
  constant tdc_prescaler_valid_c : boolean := (data_prescaler = 1 or data_prescaler = 2);
  constant use_tdc_c             : boolean := tdc_enable and tdc_policy_use_c and tdc_prescaler_valid_c;

  -- Internal alignment terms (clock cycles), kept separate from physical TDCV:
  --   tx_output_pipeline_clk_c: fixed TX output staging from MAC->PCS->bus
  --   rx_capture_latency_clk_c: registered RX edge detector latency
  -- Net effect used for FIFO alignment is +1 clock.
  constant tx_output_pipeline_clk_c    : integer := 2;
  constant rx_capture_latency_clk_c    : integer := 1;
  constant net_internal_align_clk_c    : integer := tx_output_pipeline_clk_c - rx_capture_latency_clk_c;
  constant max_transmitter_delay_clk_c : integer := max_transmitter_delay_c * data_prescaler;
  constant max_fifo_index              : integer := (max_transmitter_delay_c + ssp_offset + net_internal_align_clk_c) / data_bit_time;

  ---------------------------------------------------------------------------
  -- Registered signals (driven by state_update)
  ---------------------------------------------------------------------------
  signal state              : can_pcs_tx_state_t;
  signal clk_count_nom      : integer range 0 to nom_prescaler - 1;
  signal clk_count_data     : integer range 0 to data_prescaler - 1;
  signal tq_count           : integer range 0 to nom_bit_time;
  signal current_bit        : mac_frame_bit_t;
  signal delay_count_clk    : integer range 0 to max_transmitter_delay_clk_c;
  signal tdc_armed          : boolean;
  signal tdc_counting       : boolean;
  signal ssp_position       : integer range 0 to data_bit_time - 1;
  signal fifo_index         : integer range 0 to transmitted_bits_fifo_depth_c - 1;
  signal prev_rx_bus        : std_logic;
  signal prev_tx_bus        : std_logic;
  signal rx_rising_edge_reg : boolean;

  ---------------------------------------------------------------------------
  -- Combinational next-cycle signals (driven by output_logic)
  ---------------------------------------------------------------------------
  signal next_state           : can_pcs_tx_state_t;
  signal next_clk_count_nom   : integer range 0 to nom_prescaler - 1;
  signal next_clk_count_data  : integer range 0 to data_prescaler - 1;
  signal next_tq_count        : integer range 0 to nom_bit_time;
  signal next_current_bit     : mac_frame_bit_t;
  signal next_delay_count_clk : integer range 0 to max_transmitter_delay_clk_c;
  signal next_tdc_armed       : boolean;
  signal next_tdc_counting    : boolean;
  signal next_ssp_position    : integer range 0 to data_bit_time - 1;
  signal next_fifo_index      : integer range 0 to transmitted_bits_fifo_depth_c - 1;

  signal next_pcs_to_mac_o : can_mac_pcs_tx_if_s2m_t;

  -- Returns true for data-phase bit types that must be monitored at SSP
  -- when TDC is active.
  function is_ssp_monitor_bit (
    bit_name_i : mac_frame_bit_name_t
  ) return boolean is
  begin

    return bit_name_i = esi_bit or
           bit_name_i = data_bit or
           bit_name_i = stuff_bit or
           bit_name_i = fixed_stuff_bit or
           bit_name_i = sbs_bit or
           bit_name_i = dlc_bit or
           bit_name_i = crc_bit;

  end function is_ssp_monitor_bit;

  -- Returns true for first error-flag bit types produced by MAC.
  function is_error_flag_bit (
    bit_name_i : mac_frame_bit_name_t
  ) return boolean is
  begin

    return bit_name_i = active_error_flag_bit or
           bit_name_i = passive_error_flag_bit;

  end function is_error_flag_bit;

begin

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

  assert (not (tdc_enable and tdc_policy_use_c)) or tdc_prescaler_valid_c
    report "TDC use requires data_prescaler=1 or 2 (ISO 7.3.4)"
    severity failure;

  ---------------------------------------------------------------------------
  -- Process 1: next_state_logic (combinational)
  ---------------------------------------------------------------------------
  next_state_logic : process (all) is

    variable frame_active_v           : boolean;
    variable tdc_timeout_v            : boolean;
    variable next_is_crc_delim_v      : boolean;
    variable nom_tq_tick_v            : boolean;
    variable data_tq_tick_v           : boolean;
    variable nominal_bit_boundary_v   : boolean;
    variable data_bit_boundary_v      : boolean;
    variable nominal_sp_pulse_v       : boolean;
    variable data_error_handover_v    : boolean;
    variable crc_delimiter_handover_v : boolean;

  begin

    nom_tq_tick_v            := (clk_count_nom = nom_prescaler - 1);
    data_tq_tick_v           := (clk_count_data = data_prescaler - 1);
    nominal_bit_boundary_v   := nom_tq_tick_v and (tq_count = nom_bit_time - 1);
    data_bit_boundary_v      := data_tq_tick_v and (tq_count = data_bit_time - 1);
    nominal_sp_pulse_v       := nom_tq_tick_v and (tq_count = sp_position - 1);
    frame_active_v           := mac_to_pcs_i.valid;
    tdc_timeout_v            := tdc_counting and (delay_count_clk >= max_transmitter_delay_clk_c);
    next_is_crc_delim_v      := (mac_to_pcs_i.data.bit_name = crc_delimiter_bit);
    data_error_handover_v    := data_bit_boundary_v and is_error_flag_bit(mac_to_pcs_i.data.bit_name);
    crc_delimiter_handover_v := data_bit_boundary_v and next_is_crc_delim_v;

    next_state <= state;

    if (state /= idle and not frame_active_v) then
      next_state <= idle;
    else
      case state is
        when idle =>
          if (frame_active_v) then
            next_state <= transmitting_nominal;
          end if;

        when transmitting_nominal =>
          -- Enter measuring_delay at FDF SP; counter resets at FDF→res boundary
          if (current_bit.bit_name = fdf_bit and nominal_sp_pulse_v) then
            next_state <= measuring_delay;
          end if;

        when measuring_delay =>
          if (current_bit.bit_name = brs_bit and nominal_bit_boundary_v) then
            if (current_bit.polarity = recessive) then
              next_state <= transmitting_data;
            else
              next_state <= transmitting_nominal;
            end if;
          elsif (tdc_timeout_v) then
            next_state <= transmitting_nominal;
          end if;

        when transmitting_data =>
          -- FD data-phase error handling: return to nominal timing before EF.
          if (data_error_handover_v) then
            next_state <= transmitting_nominal;
          -- ISO 11898-1: 6.6.11.6
          -- Leave data phase at the data-bit boundary before CRC delimiter so
          -- crc_delimiter itself is transmitted with nominal timing.
          elsif (crc_delimiter_handover_v) then
            next_state <= transmitting_nominal;
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

    variable nom_tq_tick_v  : boolean;
    variable data_tq_tick_v : boolean;
    variable sp_pulse_v     : std_logic;
    variable ssp_pulse_v    : std_logic;

    variable nominal_bit_boundary_v : boolean;
    variable data_bit_boundary_v    : boolean;
    variable is_ssp_required_v      : boolean;

    procedure update_prescaler_counters_and_tq_ticks is
    begin

      nom_tq_tick_v  := false;
      data_tq_tick_v := false;

      if (clk_count_nom = nom_prescaler - 1) then
        nom_tq_tick_v      := true;
        next_clk_count_nom <= 0;
      else
        next_clk_count_nom <= clk_count_nom + 1;
      end if;

      if (state = measuring_delay or state = transmitting_data) then
        if (clk_count_data = data_prescaler - 1) then
          data_tq_tick_v      := true;
          next_clk_count_data <= 0;
        else
          next_clk_count_data <= clk_count_data + 1;
        end if;
      else
        next_clk_count_data <= 0;
      end if;

    end procedure update_prescaler_counters_and_tq_ticks;

    procedure handle_bit_boundaries_and_latch_next_bit is
    begin

      nominal_bit_boundary_v := (nom_tq_tick_v and tq_count = nom_bit_time - 1);
      data_bit_boundary_v    := (data_tq_tick_v and tq_count = data_bit_time - 1);

      case state is
        when idle =>
          if (nom_tq_tick_v) then
            if (tq_count = nom_bit_time - 1) then
              next_tq_count <= 0;
            else
              next_tq_count <= tq_count + 1;
            end if;
          end if;

          if (mac_to_pcs_i.valid) then
            next_current_bit <= mac_to_pcs_i.data;
            next_tq_count    <= 0;
          end if;

        when transmitting_nominal | measuring_delay =>
          if (nominal_bit_boundary_v) then
            next_current_bit <= mac_to_pcs_i.data;
            next_tq_count    <= 0;
          elsif (nom_tq_tick_v) then
            next_tq_count <= tq_count + 1;
          end if;

        when transmitting_data =>
          if (data_bit_boundary_v) then
            -- Latch next bit at data-phase boundary (including first EF bit
            -- on data->nominal handover).
            next_current_bit <= mac_to_pcs_i.data;
            next_tq_count    <= 0;
          elsif (data_tq_tick_v) then
            next_tq_count <= tq_count + 1;
          end if;

      end case;

    end procedure handle_bit_boundaries_and_latch_next_bit;

    -- TDC measurement (ISO 11898-1: 7.3.4)
    --
    -- Timeline:
    --   FDF SP                -> arm TDC measurement
    --   TX recessive->dominant -> start delay counter at TX output edge
    --   +propagation          -> rx_bus_i goes dominant
    --   RX rising edge        -> latch TDCV, compute SSP = TDCV + TDCO
    procedure measure_tx_rx_delay_and_update_ssp is

      variable tdcv_physical_clk_v     : integer;
      variable delay_with_offset_clk_v : integer;
      variable delay_with_offset_tq_v  : integer;
      variable ssp_position_v          : integer;
      variable tx_rising_edge_v        : boolean;

    begin

      tx_rising_edge_v := (prev_tx_bus = recessive_bit_c and tx_bus_o = dominant_bit_c);

      if (state /= measuring_delay) then
        next_tdc_armed    <= false;
        next_tdc_counting <= false;
      end if;

      if (state = transmitting_nominal and use_tdc_c and
          current_bit.bit_name = fdf_bit and
          nom_tq_tick_v and tq_count = sp_position - 1) then
        next_tdc_armed       <= true;
        next_tdc_counting    <= false;
        next_delay_count_clk <= 0;
      end if;

      if (state = measuring_delay) then
        -- Start the TDC counter on the physical TX output edge.
        if (tdc_armed and (not tdc_counting) and tx_rising_edge_v) then
          next_tdc_counting    <= true;
          next_delay_count_clk <= 0;
        elsif (tdc_counting and (not rx_rising_edge_reg) and delay_count_clk < max_transmitter_delay_clk_c) then
          -- Counter increments once per minimum time quantum (clock here).
          next_delay_count_clk <= delay_count_clk + 1;
        end if;

        -- Latch on registered RX recessive→dominant edge.
        -- Edge detection is registered in state_update to avoid a delta-cycle race.
        if (rx_rising_edge_reg and tdc_counting) then
          -- Physical TDCV per ISO intent:
          -- TX output dominant edge -> RX input dominant edge.
          -- delay_count_clk includes +1 clock from registered edge capture, so
          -- remove rx_capture_latency_clk_c to recover physical delay.
          if (delay_count_clk > rx_capture_latency_clk_c) then
            tdcv_physical_clk_v := delay_count_clk - rx_capture_latency_clk_c;
          else
            tdcv_physical_clk_v := 0;
          end if;

          -- Internal alignment for monitor FIFO indexing:
          -- physical TDCV + configured SSP offset + TX output staging.
          delay_with_offset_clk_v := tdcv_physical_clk_v +
                                     (ssp_offset * data_prescaler) +
                                     tx_output_pipeline_clk_c;
          -- Convert to TQ using ceil division to avoid sampling too early.
          delay_with_offset_tq_v := (delay_with_offset_clk_v + data_prescaler - 1) / data_prescaler;
          next_fifo_index        <= calculate_fifo_delay_index(delay_with_offset_tq_v, data_bit_time);

          ssp_position_v := delay_with_offset_tq_v mod data_bit_time;

          next_ssp_position <= ssp_position_v;
          next_tdc_counting <= false;
          next_tdc_armed    <= false;
        end if;
      end if;

    end procedure measure_tx_rx_delay_and_update_ssp;

    procedure generate_sample_strobe_and_monitor_select is
    begin

      sp_pulse_v  := '0';
      ssp_pulse_v := '0';

      if (state = transmitting_data) then
        if (data_tq_tick_v and tq_count = data_sp_position - 1) then
          sp_pulse_v := '1';
        end if;
      else
        if (nom_tq_tick_v and tq_count = sp_position - 1) then
          sp_pulse_v := '1';
        end if;
      end if;

      if (state = transmitting_data and use_tdc_c) then
        if (data_tq_tick_v and tq_count = ssp_position) then
          ssp_pulse_v := '1';
        end if;
      end if;

      -- Data-phase bits use SSP when TDC is active
      is_ssp_required_v := is_ssp_monitor_bit(current_bit.bit_name);

      next_pcs_to_mac_o.sample_strobe <= '0';
      next_pcs_to_mac_o.strobe_type   <= sp_strobe;
      next_pcs_to_mac_o.fifo_index    <= 0;

      -- SP remains the primary strobe for MAC progression/IPT timing.
      if (sp_pulse_v = '1') then
        next_pcs_to_mac_o.sample_strobe <= '1';
        next_pcs_to_mac_o.strobe_type   <= sp_strobe;
      -- SSP is emitted as an additional monitor-only strobe in data phase.
      elsif (state = transmitting_data and use_tdc_c and is_ssp_required_v and ssp_pulse_v = '1') then
        next_pcs_to_mac_o.sample_strobe <= '1';
        next_pcs_to_mac_o.strobe_type   <= ssp_strobe;
        next_pcs_to_mac_o.fifo_index    <= fifo_index;
      end if;

    end procedure generate_sample_strobe_and_monitor_select;

  begin

    -- Defaults: hold current values
    next_clk_count_nom   <= clk_count_nom;
    next_clk_count_data  <= clk_count_data;
    next_tq_count        <= tq_count;
    next_current_bit     <= current_bit;
    next_delay_count_clk <= delay_count_clk;
    next_tdc_armed       <= tdc_armed;
    next_tdc_counting    <= tdc_counting;
    next_ssp_position    <= ssp_position;
    next_fifo_index      <= fifo_index;

    next_pcs_to_mac_o <= pcs_to_mac_o;

    -- Bus polarity passthrough (combinational, not registered)
    next_pcs_to_mac_o.bus_polarity <= std_logic_to_polarity(rx_bus_i);

    update_prescaler_counters_and_tq_ticks;
    handle_bit_boundaries_and_latch_next_bit;
    measure_tx_rx_delay_and_update_ssp;
    generate_sample_strobe_and_monitor_select;

  end process output_logic;

  ---------------------------------------------------------------------------
  -- Process 3: state_update (clocked)
  ---------------------------------------------------------------------------
  state_update : process (clk) is
  begin

    if rising_edge(clk) then
      if (rst = '1') then
        state              <= idle;
        clk_count_nom      <= 0;
        clk_count_data     <= 0;
        tq_count           <= 0;
        current_bit        <= reset_mac_frame_bit_c;
        delay_count_clk    <= 0;
        tdc_armed          <= false;
        tdc_counting       <= false;
        ssp_position       <= 0;
        fifo_index         <= 0;
        prev_rx_bus        <= '1';                                                             -- recessive
        prev_tx_bus        <= '1';                                                             -- recessive
        rx_rising_edge_reg <= false;

        pcs_to_mac_o <= pcs_to_mac_if_reset_c;
        tx_bus_o     <= '1';                                                                   -- recessive
      else
        state              <= next_state;
        clk_count_nom      <= next_clk_count_nom;
        clk_count_data     <= next_clk_count_data;
        tq_count           <= next_tq_count;
        current_bit        <= next_current_bit;
        delay_count_clk    <= next_delay_count_clk;
        tdc_armed          <= next_tdc_armed;
        tdc_counting       <= next_tdc_counting;
        ssp_position       <= next_ssp_position;
        fifo_index         <= next_fifo_index;
        prev_rx_bus        <= rx_bus_i;
        prev_tx_bus        <= tx_bus_o;
        rx_rising_edge_reg <= (prev_rx_bus = recessive_bit_c and rx_bus_i = dominant_bit_c);

        pcs_to_mac_o <= next_pcs_to_mac_o;
        tx_bus_o     <= polarity_to_std_logic(current_bit.polarity);
      end if;
    end if;

  end process state_update;

  debug_state_o <= state;

end architecture rtl;
