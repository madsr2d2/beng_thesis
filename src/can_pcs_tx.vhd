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
--   transmitting_nominal -> measuring_delay   (FDF sample point)
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
  signal clk_count          : integer range 0 to prescaler - 1;
  signal tq_count           : integer range 0 to nom_bit_time;
  signal current_bit        : mac_frame_bit_t;
  signal delay_count_clk    : natural;
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
    variable v_clk_count       : integer range 0 to prescaler - 1;
    variable v_tq_count        : integer range 0 to nom_bit_time;
    variable v_current_bit     : mac_frame_bit_t;
    variable v_delay_count_clk : natural;
    variable v_tdc_counting    : boolean;
    variable v_ssp_position    : integer range 0 to data_bit_time - 1;
    variable v_fifo_index      : integer range 0 to transmitted_bits_fifo_depth_c - 1;
    variable v_pcs_to_mac      : can_mac_pcs_tx_if_s2m_t;

    -- Guard variables (evaluated once from registered state)
    variable frame_active_v   : boolean;
    variable tx_rising_edge_v : boolean;
    variable tq_tick_v        : boolean;
    variable bit_boundary_v   : boolean;
    variable nom_sp_v         : boolean;

    -- TDC measurement local
    variable delay_tq_v : integer;

    ---------------------------------------------------------------------------
    -- Shared procedures called from state arms
    ---------------------------------------------------------------------------

    -- Advance prescaler and set tq_tick_v.
    procedure tick_prescaler is
    begin

      tq_tick_v := false;
      if (v_clk_count = prescaler - 1) then
        tq_tick_v   := true;
        v_clk_count := 0;
      else
        v_clk_count := v_clk_count + 1;
      end if;

    end procedure tick_prescaler;

    -- Advance TQ counter and latch next bit at boundary.
    -- Sets bit_boundary_v.
    procedure latch_next_bit (
      bit_time : in integer
    ) is
    begin

      bit_boundary_v := tq_tick_v and (v_tq_count = bit_time - 1);
      if (bit_boundary_v) then
        v_current_bit := mac_to_pcs_i.data;
        v_tq_count    := 0;
      elsif (tq_tick_v) then
        v_tq_count := v_tq_count + 1;
      end if;

    end procedure latch_next_bit;

    -- Emit sample point strobe at the given TQ position.
    procedure emit_sp (
      sp_pos : in integer
    ) is
    begin

      if (tq_tick_v and tq_count = sp_pos - 1) then
        v_pcs_to_mac.sample_strobe := '1';
        v_pcs_to_mac.strobe_type   := sp_strobe;
      end if;

    end procedure emit_sp;

    -- Emit secondary sample point strobe (TDC monitoring).
    procedure emit_ssp is

      variable ssp_due_v : boolean;

    begin

      ssp_due_v := use_tdc_c and
                   is_ssp_monitor_bit(current_bit.bit_name) and
                   tq_tick_v and tq_count = ssp_position;

      if (ssp_due_v) then
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
      if (use_tdc_c and not v_tdc_counting and tx_rising_edge_v) then
        v_tdc_counting    := true;
        v_delay_count_clk := 0;
      elsif (v_tdc_counting and not rx_rising_edge_reg) then
        v_delay_count_clk := v_delay_count_clk + 1;
      end if;

      -- Latch on registered RX recessive->dominant edge
      if (rx_rising_edge_reg and v_tdc_counting) then
        delay_tq_v     := (v_delay_count_clk + prescaler - 1) / prescaler + ssp_offset;
        v_fifo_index   := calculate_fifo_delay_index(delay_tq_v, data_bit_time);
        v_ssp_position := delay_tq_v mod data_bit_time;
        v_tdc_counting := false;
      end if;

    end procedure measure_tdc;

  begin

    if rising_edge(clk) then
      if (rst = '1') then
        state              <= idle;
        clk_count          <= 0;
        tq_count           <= 0;
        current_bit        <= reset_mac_frame_bit_c;
        delay_count_clk    <= 0;
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
        nom_sp_v         := (clk_count = prescaler - 1) and (tq_count = sp_position - 1);

        -- Initialize v_* from registers
        v_state           := state;
        v_clk_count       := clk_count;
        v_tq_count        := tq_count;
        v_current_bit     := current_bit;
        v_delay_count_clk := delay_count_clk;
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
            tick_prescaler;
            latch_next_bit(nom_bit_time);
            emit_sp(sp_position);
            -- Transition: latch first bit on valid
            if (frame_active_v) then
              v_current_bit := mac_to_pcs_i.data;
              v_tq_count    := 0;
              v_state       := transmitting_nominal;
            end if;

          when transmitting_nominal =>
            tick_prescaler;
            latch_next_bit(nom_bit_time);
            emit_sp(sp_position);
            -- Transition to measuring_delay at FDF bit sample point.
            if (current_bit.bit_name = fdf_bit and nom_sp_v) then
              v_tdc_counting    := false;
              v_delay_count_clk := 0;
              v_state           := measuring_delay;
            end if;

          when measuring_delay =>
            tick_prescaler;
            latch_next_bit(nom_bit_time);
            emit_sp(sp_position);
            measure_tdc;
            -- Transition at BRS bit boundary
            if (current_bit.bit_name = brs_bit and bit_boundary_v) then
              if (current_bit.polarity = recessive) then
                v_state := transmitting_data;
              else
                v_state := transmitting_nominal;
              end if;
            end if;

          when transmitting_data =>
            tick_prescaler;
            latch_next_bit(data_bit_time);
            emit_sp(data_sp_position);
            emit_ssp;
            -- Return to nominal on error flag or CRC delimiter
            if (bit_boundary_v and is_error_flag_bit(mac_to_pcs_i.data.bit_name)) then
              v_state := transmitting_nominal;
            elsif (bit_boundary_v and mac_to_pcs_i.data.bit_name = crc_delimiter_bit) then
              v_state := transmitting_nominal;
            end if;

        end case;

        -- Return to idle when frame ends (overrides any state transition).
        if (not frame_active_v) then
          v_state := idle;
        end if;

        -- Register all updates
        state           <= v_state;
        clk_count       <= v_clk_count;
        tq_count        <= v_tq_count;
        current_bit     <= v_current_bit;
        delay_count_clk <= v_delay_count_clk;
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
