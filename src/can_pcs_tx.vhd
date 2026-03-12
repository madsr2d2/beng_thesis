--------------------------------------------------------------------------------
-- Title      : CAN Physical Signaling Layer (PCS) with TDC
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : can_pcs_tx.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Physical Signaling layer implementing bit timing, transmission,
--              and Transmitter Delay Compensation (TDC) per ISO 11898-1:2015
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
--   idle -> transmitting_nominal              (mac_to_pcs_i.valid = true)
--   transmitting_nominal -> measuring_delay   (FDF sample point, TDC enabled)
--   measuring_delay -> transmitting_data      (BRS bit boundary, BRS recessive)
--   measuring_delay -> transmitting_nominal   (BRS dominant or TDC timeout)
--   transmitting_data -> transmitting_nominal (CRC delimiter or error flag)
--   any non-idle -> idle                      (mac_to_pcs_i.valid = false)
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;
  use work.can_protocol_pkg.all;
  use work.can_timing_pkg.all;

entity can_pcs_tx is
  generic (
    -- Set generics to middle of ISO specified ranges
    -- Nominal values
    prescaler      : prescaler          := prescaler'high / 2;
    nom_sync_seg   : integer            := sync_seg_c;
    nom_prop_seg   : nominal_prop_seg   := nominal_prop_seg'high / 2;
    nom_phase_seg1 : nominal_phase_seg1 := nominal_phase_seg1'high / 2;
    nom_phase_seg2 : nominal_phase_seg2 := nominal_phase_seg2'high / 2;

    -- Data values
    data_sync_seg   : integer         := nom_sync_seg;
    data_prop_seg   : data_prop_seg   := data_prop_seg'high / 2;
    data_phase_seg1 : data_phase_seg1 := data_phase_seg1'high / 2;
    data_phase_seg2 : data_phase_seg2 := data_phase_seg2'high / 2;
    ssp_offset      : ssp_offset      := ssp_offset'high / 2;
    tdc_enable      : boolean         := true
  );
  port (
    clk : in    std_logic;
    rst : in    std_logic;

    mac_to_pcs_i : in    can_mac_pcs_tx_if_m2s_t;
    pcs_to_mac_o : out   can_mac_pcs_tx_if_s2m_t;

    tx_bus_o : out   std_logic;
    rx_bus_i : in    std_logic;

    -- Debug port (test visibility)
    debug_state_o : out   can_pcs_tx_state_t
  );
end entity can_pcs_tx;

architecture rtl of can_pcs_tx is

  -- Bit timing constants
  constant nom_bit_time     : integer := nom_sync_seg + nom_prop_seg + nom_phase_seg1 + nom_phase_seg2;
  constant data_bit_time    : integer := data_sync_seg + data_prop_seg + data_phase_seg1 + data_phase_seg2;
  constant sp_position      : integer := nom_sync_seg + nom_prop_seg + nom_phase_seg1;
  constant data_sp_position : integer := data_sync_seg + data_prop_seg + data_phase_seg1;

  -- TDC activation: caller sets tdc_enable based on should_use_tdc() policy.
  -- Prescaler must be 1 or 2 for the clock-cycle TDC counter to resolve
  -- sub-bit delays (ISO 7.3.4).
  constant tdc_prescaler_valid_c : boolean := (prescaler = 1 or prescaler = 2);
  constant use_tdc_c             : boolean := tdc_enable and tdc_prescaler_valid_c;

  -- Internal alignment terms (clock cycles)
  constant tx_output_pipeline_clk_c    : integer := 2;
  constant rx_capture_latency_clk_c    : integer := 1;
  constant max_transmitter_delay_clk_c : integer := max_transmitter_delay_c * prescaler;
  constant max_fifo_index              : integer := (max_transmitter_delay_c + ssp_offset +
                                                     tx_output_pipeline_clk_c - rx_capture_latency_clk_c) / data_bit_time;

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

  function is_error_flag_bit (
    bit_name_i : mac_frame_bit_name_t
  ) return boolean is
  begin

    return bit_name_i = active_error_flag_bit or
           bit_name_i = passive_error_flag_bit;

  end function is_error_flag_bit;

  ---------------------------------------------------------------------------
  -- Registered signals
  ---------------------------------------------------------------------------
  signal state              : can_pcs_tx_state_t;
  signal clk_count_nom      : integer range 0 to prescaler - 1;
  signal clk_count_data     : integer range 0 to prescaler - 1;
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

begin

  ---------------------------------------------------------------------------
  -- Single synchronous FSM process
  ---------------------------------------------------------------------------
  fsm : process (clk) is

    variable v_state           : can_pcs_tx_state_t;
    variable v_clk_count_nom   : integer range 0 to prescaler - 1;
    variable v_clk_count_data  : integer range 0 to prescaler - 1;
    variable v_tq_count        : integer range 0 to nom_bit_time;
    variable v_current_bit     : mac_frame_bit_t;
    variable v_delay_count_clk : integer range 0 to max_transmitter_delay_clk_c;
    variable v_tdc_armed       : boolean;
    variable v_tdc_counting    : boolean;
    variable v_ssp_position    : integer range 0 to data_bit_time - 1;
    variable v_fifo_index      : integer range 0 to transmitted_bits_fifo_depth_c - 1;
    variable v_pcs_to_mac      : can_mac_pcs_tx_if_s2m_t;

    -- Guard variables (evaluated once from registered state)
    variable frame_active_v      : boolean;
    variable tx_rising_edge_v    : boolean;
    variable tdc_timeout_v       : boolean;
    variable nom_tq_tick_v       : boolean;
    variable data_tq_tick_v      : boolean;
    variable nom_bit_boundary_v  : boolean;
    variable data_bit_boundary_v : boolean;
    variable nom_sp_v            : boolean;

    -- TDC measurement locals
    variable tdcv_physical_clk_v     : integer;
    variable delay_with_offset_clk_v : integer;
    variable delay_with_offset_tq_v  : integer;

    ---------------------------------------------------------------------------
    -- Shared procedures called from state arms
    ---------------------------------------------------------------------------

    -- Advance nominal prescaler and set nom_tq_tick_v.
    procedure tick_nom_prescaler is
    begin

      nom_tq_tick_v := false;
      if (v_clk_count_nom = prescaler - 1) then
        nom_tq_tick_v   := true;
        v_clk_count_nom := 0;
      else
        v_clk_count_nom := v_clk_count_nom + 1;
      end if;

    end procedure tick_nom_prescaler;

    -- Advance data prescaler and set data_tq_tick_v.
    procedure tick_data_prescaler is
    begin

      data_tq_tick_v := false;
      if (v_clk_count_data = prescaler - 1) then
        data_tq_tick_v   := true;
        v_clk_count_data := 0;
      else
        v_clk_count_data := v_clk_count_data + 1;
      end if;

    end procedure tick_data_prescaler;

    -- Advance TQ at nominal rate and latch next bit at boundary.
    -- Sets nom_bit_boundary_v.
    procedure latch_next_bit_nom is
    begin

      nom_bit_boundary_v := nom_tq_tick_v and (v_tq_count = nom_bit_time - 1);
      if (nom_bit_boundary_v) then
        v_current_bit := mac_to_pcs_i.data;
        v_tq_count    := 0;
      elsif (nom_tq_tick_v) then
        v_tq_count := v_tq_count + 1;
      end if;

    end procedure latch_next_bit_nom;

    -- Advance TQ at data rate and latch next bit at boundary.
    -- Sets data_bit_boundary_v.
    procedure latch_next_bit_data is
    begin

      data_bit_boundary_v := data_tq_tick_v and (v_tq_count = data_bit_time - 1);
      if (data_bit_boundary_v) then
        v_current_bit := mac_to_pcs_i.data;
        v_tq_count    := 0;
      elsif (data_tq_tick_v) then
        v_tq_count := v_tq_count + 1;
      end if;

    end procedure latch_next_bit_data;

    -- Emit nominal sample point strobe (reads registered tq_count).
    procedure emit_nom_sp is
    begin

      if (nom_tq_tick_v and tq_count = sp_position - 1) then
        v_pcs_to_mac.sample_strobe := '1';
        v_pcs_to_mac.strobe_type   := sp_strobe;
      end if;

    end procedure emit_nom_sp;

    -- Emit data-rate sample point strobe (reads registered tq_count).
    procedure emit_data_sp is
    begin

      if (data_tq_tick_v and tq_count = data_sp_position - 1) then
        v_pcs_to_mac.sample_strobe := '1';
        v_pcs_to_mac.strobe_type   := sp_strobe;
      end if;

    end procedure emit_data_sp;

    -- Emit secondary sample point strobe if TDC active and SP not already
    -- asserted this cycle (reads registered tq_count, ssp_position, fifo_index).
    procedure emit_ssp is
    begin

      if (use_tdc_c and v_pcs_to_mac.sample_strobe = '0' and
          is_ssp_monitor_bit(current_bit.bit_name) and
          data_tq_tick_v and tq_count = ssp_position) then
        v_pcs_to_mac.sample_strobe := '1';
        v_pcs_to_mac.strobe_type   := ssp_strobe;
        v_pcs_to_mac.fifo_index    := fifo_index;
      end if;

    end procedure emit_ssp;

    -- TDC delay measurement (ISO 11898-1: 7.3.4).
    -- Called only from measuring_delay state arm.
    procedure measure_tdc is
    begin

      -- Start counter on physical TX output edge
      if (v_tdc_armed and not v_tdc_counting and tx_rising_edge_v) then
        v_tdc_counting    := true;
        v_delay_count_clk := 0;
      elsif (v_tdc_counting and not rx_rising_edge_reg and
             v_delay_count_clk < max_transmitter_delay_clk_c) then
        v_delay_count_clk := v_delay_count_clk + 1;
      end if;

      -- Latch on registered RX recessive->dominant edge
      if (rx_rising_edge_reg and v_tdc_counting) then
        if (v_delay_count_clk > rx_capture_latency_clk_c) then
          tdcv_physical_clk_v := v_delay_count_clk - rx_capture_latency_clk_c;
        else
          tdcv_physical_clk_v := 0;
        end if;

        delay_with_offset_clk_v := tdcv_physical_clk_v +
                                   (ssp_offset * prescaler) +
                                   tx_output_pipeline_clk_c;
        delay_with_offset_tq_v  := (delay_with_offset_clk_v + prescaler - 1) / prescaler;
        v_fifo_index            := calculate_fifo_delay_index(delay_with_offset_tq_v, data_bit_time);
        v_ssp_position          := delay_with_offset_tq_v mod data_bit_time;
        v_tdc_counting          := false;
        v_tdc_armed             := false;
      end if;

    end procedure measure_tdc;

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
        prev_rx_bus        <= recessive_bit_c;
        prev_tx_bus        <= recessive_bit_c;
        rx_rising_edge_reg <= false;
        pcs_to_mac_o       <= pcs_to_mac_if_reset_c;
        tx_bus_o           <= recessive_bit_c;
      else
        -- Evaluate guards from registered state
        frame_active_v   := mac_to_pcs_i.valid;
        tx_rising_edge_v := (prev_tx_bus = recessive_bit_c and tx_bus_o = dominant_bit_c);
        tdc_timeout_v    := tdc_counting and (delay_count_clk >= max_transmitter_delay_clk_c);
        nom_sp_v         := (clk_count_nom = prescaler - 1) and (tq_count = sp_position - 1);

        -- Initialize v_* from registers
        v_state           := state;
        v_clk_count_nom   := clk_count_nom;
        v_clk_count_data  := clk_count_data;
        v_tq_count        := tq_count;
        v_current_bit     := current_bit;
        v_delay_count_clk := delay_count_clk;
        v_tdc_armed       := tdc_armed;
        v_tdc_counting    := tdc_counting;
        v_ssp_position    := ssp_position;
        v_fifo_index      := fifo_index;

        -- Output defaults: hold bus_polarity, clear strobe
        v_pcs_to_mac               := pcs_to_mac_o;
        v_pcs_to_mac.bus_polarity  := std_logic_to_polarity(rx_bus_i);
        v_pcs_to_mac.sample_strobe := '0';
        v_pcs_to_mac.strobe_type   := sp_strobe;
        v_pcs_to_mac.fifo_index    := 0;

        case state is

          when idle =>
            tick_nom_prescaler;
            -- Free-running TQ at nominal rate
            if (nom_tq_tick_v) then
              if (v_tq_count = nom_bit_time - 1) then
                v_tq_count := 0;
              else
                v_tq_count := v_tq_count + 1;
              end if;
            end if;
            emit_nom_sp;
            -- Gate inactive state
            v_clk_count_data := 0;
            v_tdc_armed      := false;
            v_tdc_counting   := false;
            -- Transition: latch first bit on valid
            if (frame_active_v) then
              v_current_bit := mac_to_pcs_i.data;
              v_tq_count    := 0;
              v_state       := transmitting_nominal;
            end if;

          when transmitting_nominal =>
            tick_nom_prescaler;
            latch_next_bit_nom;
            emit_nom_sp;
            -- Gate inactive state
            v_clk_count_data := 0;
            v_tdc_armed      := false;
            v_tdc_counting   := false;
            -- Transition to measuring_delay at FDF sample point (all FD frames).
            -- TDC arming is conditional on use_tdc_c; without TDC the
            -- measuring_delay state still handles the BRS rate switch.
            if (current_bit.bit_name = fdf_bit and nom_sp_v) then
              if (use_tdc_c) then
                v_tdc_armed       := true;
                v_delay_count_clk := 0;
              end if;
              v_state := measuring_delay;
            end if;
            -- Return to idle on frame end
            if (not frame_active_v) then
              v_state := idle;
            end if;

          when measuring_delay =>
            tick_nom_prescaler;
            tick_data_prescaler;
            latch_next_bit_nom;
            emit_nom_sp;
            measure_tdc;
            -- Transition at BRS bit boundary
            if (current_bit.bit_name = brs_bit and nom_bit_boundary_v) then
              if (current_bit.polarity = recessive) then
                v_state := transmitting_data;
              else
                v_state := transmitting_nominal;
              end if;
            elsif (tdc_timeout_v) then
              v_state := transmitting_nominal;
            end if;
            -- Return to idle on frame end
            if (not frame_active_v) then
              v_state := idle;
            end if;

          when transmitting_data =>
            tick_nom_prescaler;
            tick_data_prescaler;
            latch_next_bit_data;
            emit_data_sp;
            emit_ssp;
            -- Gate inactive TDC
            v_tdc_armed    := false;
            v_tdc_counting := false;
            -- Return to nominal on error flag or CRC delimiter
            if (data_bit_boundary_v and is_error_flag_bit(mac_to_pcs_i.data.bit_name)) then
              v_state := transmitting_nominal;
            elsif (data_bit_boundary_v and mac_to_pcs_i.data.bit_name = crc_delimiter_bit) then
              v_state := transmitting_nominal;
            end if;
            -- Return to idle on frame end
            if (not frame_active_v) then
              v_state := idle;
            end if;

        end case;

        -- Register all updates
        state           <= v_state;
        clk_count_nom   <= v_clk_count_nom;
        clk_count_data  <= v_clk_count_data;
        tq_count        <= v_tq_count;
        current_bit     <= v_current_bit;
        delay_count_clk <= v_delay_count_clk;
        tdc_armed       <= v_tdc_armed;
        tdc_counting    <= v_tdc_counting;
        ssp_position    <= v_ssp_position;
        fifo_index      <= v_fifo_index;
        pcs_to_mac_o    <= v_pcs_to_mac;
        tx_bus_o        <= polarity_to_std_logic(v_current_bit.polarity);

        -- Edge detection registers
        prev_rx_bus        <= rx_bus_i;
        prev_tx_bus        <= tx_bus_o;
        rx_rising_edge_reg <= (prev_rx_bus = recessive_bit_c and rx_bus_i = dominant_bit_c);
      end if;
    end if;

  end process fsm;

  debug_state_o <= state;

end architecture rtl;
