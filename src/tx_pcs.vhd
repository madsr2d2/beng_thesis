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
--   idle -> transmitting_nominal              (mac_to_pcs_i.valid = '1')
--   transmitting_nominal -> measuring_delay   (FDF sample point, TDC enabled)
--   measuring_delay -> transmitting_data      (BRS bit boundary)
--   measuring_delay -> transmitting_nominal   (TDC timeout)
--   transmitting_data -> transmitting_nominal (CRC delimiter sample point)
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

entity tx_pcs is
  generic (
    -- Nominal bit timing (arbitration phase)
    nom_prescaler  : prescalar    := 2;
    nom_sync_seg   : sync_seg     := 1;
    nom_prop_seg   : nom_prop_seg := 8;
    nom_phase_seg1 : phase_seg1   := 8;
    nom_phase_seg2 : phase_seg2   := 8;

    -- Data bit timing (FD data phase)
    data_prescaler  : prescalar     := 1;
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

    mac_to_pcs_i : in    mac_to_pcs_if_t;
    pcs_to_mac_o : out   pcs_to_mac_if_t;

    tx_bus_o : out   std_logic;
    rx_bus_i : in    std_logic
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

  -- Pipeline compensation for TDC measurement.
  -- The physical TX pipeline is 2 cycles (MAC pcs_o + PCS tx_bus_o), but
  -- the registered edge detector (rx_rising_edge_reg) adds 1 cycle of
  -- latency to the capture, absorbing one pipeline cycle. Net compensation = 1.
  constant tx_pipeline_comp_c : integer := 1;

  constant max_fifo_index : integer := (max_transmitter_delay_c + ssp_offset + tx_pipeline_comp_c) / data_bit_time;

  ---------------------------------------------------------------------------
  -- Registered signals (driven by state_update)
  ---------------------------------------------------------------------------
  signal state              : tx_pcs_fsm_state_t;
  signal clk_count_nom      : integer range 0 to nom_prescaler - 1;
  signal clk_count_data     : integer range 0 to data_prescaler - 1;
  signal tq_count           : integer range 0 to nom_bit_time;
  signal current_bit        : mac_frame_bit_t;
  signal delay_count        : integer range 0 to max_transmitter_delay_c;
  signal ssp_position       : integer range 0 to data_bit_time - 1;
  signal fifo_index         : integer range 0 to transmitted_bits_fifo_depth_c - 1;
  signal prev_rx_bus        : std_logic;
  signal rx_rising_edge_reg : boolean;

  ---------------------------------------------------------------------------
  -- Combinational next-cycle signals (driven by output_logic)
  ---------------------------------------------------------------------------
  signal next_state          : tx_pcs_fsm_state_t;
  signal next_clk_count_nom  : integer range 0 to nom_prescaler - 1;
  signal next_clk_count_data : integer range 0 to data_prescaler - 1;
  signal next_tq_count       : integer range 0 to nom_bit_time;
  signal next_current_bit    : mac_frame_bit_t;
  signal next_delay_count    : integer range 0 to max_transmitter_delay_c;
  signal next_ssp_position   : integer range 0 to data_bit_time - 1;
  signal next_fifo_index     : integer range 0 to transmitted_bits_fifo_depth_c - 1;

  signal next_pcs_to_mac_o : pcs_to_mac_if_t;
  signal next_tx_bus_o     : std_logic;

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

  assert (not use_tdc_c) or (data_prescaler = 1 or data_prescaler = 2)
    report "TDC enabled while data_prescaler is not 1 or 2 (ISO 7.3.4 recommendation)"
    severity warning;

  ---------------------------------------------------------------------------
  -- Process 1: next_state_logic (combinational)
  ---------------------------------------------------------------------------
  next_state_logic : process (all) is

    variable frame_active_v         : boolean;
    variable tdc_timeout_v          : boolean;
    variable is_crc_delim_v         : boolean;
    variable sample_strobe_v        : boolean;
    variable nom_tq_tick_v          : boolean;
    variable nominal_bit_boundary_v : boolean;

  begin

    nom_tq_tick_v          := (clk_count_nom = nom_prescaler - 1);
    nominal_bit_boundary_v := nom_tq_tick_v and (tq_count = nom_bit_time - 1);

    frame_active_v  := mac_to_pcs_i.valid;
    tdc_timeout_v   := (delay_count >= max_transmitter_delay_c);
    is_crc_delim_v  := (current_bit.bit_name = crc_delimiter_bit);
    sample_strobe_v := next_pcs_to_mac_o.sample_strobe = '1';

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
          if (current_bit.bit_name = fdf_bit and sample_strobe_v) then
            if (use_tdc_c) then
              next_state <= measuring_delay;
            end if;
          elsif (current_bit.bit_name = brs_bit and nominal_bit_boundary_v) then
            next_state <= transmitting_data;
          end if;

        when measuring_delay =>
          if (current_bit.bit_name = brs_bit and nominal_bit_boundary_v) then
            next_state <= transmitting_data;
          elsif (tdc_timeout_v) then
            next_state <= transmitting_nominal;
          end if;

        when transmitting_data =>
          -- ISO 11898-1: 6.6.11.6
          if (is_crc_delim_v and sample_strobe_v) then
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

    procedure generate_tq_ticks is
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

    end procedure generate_tq_ticks;

    procedure manage_bit_timing is
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
            next_current_bit <= mac_to_pcs_i.data;
            next_tq_count    <= 0;
          elsif (data_tq_tick_v) then
            next_tq_count <= tq_count + 1;
          end if;

      end case;

    end procedure manage_bit_timing;

    -- TDC measurement (ISO 11898-1: 7.3.4)
    --
    -- Timeline:
    --   FDF SP           → enter measuring_delay
    --   FDF→res boundary → reset delay_count (TX dominant edge reference)
    --   +2 clocks        → tx_bus_o goes dominant (registration pipeline)
    --   +propagation     → rx_bus_i goes dominant
    --   RX rising edge   → latch TDCV, compute SSP = TDCV + TDCO
    procedure perform_tdc_measurement is

      variable delay_with_offset_v : integer;
      variable ssp_position_v      : integer;

    begin

      if (state = measuring_delay) then
        if (data_tq_tick_v and delay_count < max_transmitter_delay_c) then
          next_delay_count <= delay_count + 1;
        end if;

        -- Reset at FDF→res boundary (TX dominant edge reference point)
        if (nominal_bit_boundary_v and current_bit.bit_name = fdf_bit) then
          next_delay_count <= 0;
        end if;

        -- Latch on registered RX recessive→dominant edge.
        -- Edge detection is registered in state_update to avoid a delta-cycle
        -- race; the 1-clock latency is compensated by tx_pipeline_comp_c.
        if (rx_rising_edge_reg) then
          delay_with_offset_v := delay_count + ssp_offset + tx_pipeline_comp_c;
          next_fifo_index     <= calculate_fifo_delay_index(delay_with_offset_v, data_bit_time);

          ssp_position_v := delay_with_offset_v;

          while (ssp_position_v >= data_bit_time) loop
            ssp_position_v := ssp_position_v - data_bit_time;
          end loop;

          next_ssp_position <= ssp_position_v;
        end if;
      end if;

    end procedure perform_tdc_measurement;

    procedure select_effective_strobe is
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
      is_ssp_required_v := current_bit.bit_name = esi_bit or
                           current_bit.bit_name = data_bit or
                           current_bit.bit_name = stuff_bit or
                           current_bit.bit_name = fixed_stuff_bit or
                           current_bit.bit_name = sbs_bit or
                           current_bit.bit_name = dlc_bit or
                           current_bit.bit_name = crc_bit;

      next_pcs_to_mac_o.sample_strobe <= sp_pulse_v;
      next_pcs_to_mac_o.strobe_type   <= sp_strobe;
      next_pcs_to_mac_o.fifo_index    <= 0;

      if (state = transmitting_data and use_tdc_c and is_ssp_required_v) then
        next_pcs_to_mac_o.sample_strobe <= ssp_pulse_v;
        next_pcs_to_mac_o.strobe_type   <= ssp_strobe;
        next_pcs_to_mac_o.fifo_index    <= fifo_index;
      end if;

    end procedure select_effective_strobe;

  begin

    -- Defaults: hold current values
    next_clk_count_nom  <= clk_count_nom;
    next_clk_count_data <= clk_count_data;
    next_tq_count       <= tq_count;
    next_current_bit    <= current_bit;
    next_delay_count    <= delay_count;
    next_ssp_position   <= ssp_position;
    next_fifo_index     <= fifo_index;

    next_pcs_to_mac_o <= pcs_to_mac_o;
    next_tx_bus_o     <= tx_bus_o;

    -- Bus polarity passthrough (combinational, not registered)
    next_pcs_to_mac_o.bus_polarity <= std_logic_to_polarity(rx_bus_i);

    generate_tq_ticks;
    manage_bit_timing;
    perform_tdc_measurement;
    select_effective_strobe;

    next_tx_bus_o <= polarity_to_std_logic(current_bit.polarity);

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
        delay_count        <= 0;
        ssp_position       <= 0;
        fifo_index         <= 0;
        prev_rx_bus        <= '1';                                                           -- recessive
        rx_rising_edge_reg <= false;

        pcs_to_mac_o <= pcs_to_mac_if_reset_c;
        tx_bus_o     <= '1';                                                                 -- recessive
      else
        state              <= next_state;
        clk_count_nom      <= next_clk_count_nom;
        clk_count_data     <= next_clk_count_data;
        tq_count           <= next_tq_count;
        current_bit        <= next_current_bit;
        delay_count        <= next_delay_count;
        ssp_position       <= next_ssp_position;
        fifo_index         <= next_fifo_index;
        prev_rx_bus        <= rx_bus_i;
        rx_rising_edge_reg <= (prev_rx_bus = recessive_bit_c and rx_bus_i = dominant_bit_c);

        pcs_to_mac_o <= next_pcs_to_mac_o;
        tx_bus_o     <= next_tx_bus_o;
      end if;
    end if;

  end process state_update;

end architecture rtl;
