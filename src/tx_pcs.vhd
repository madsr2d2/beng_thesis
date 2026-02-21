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

  -- Maximum FIFO index: (max_transmitter_delay_c + ssp_offset) / data_bit_time must fit in FIFO
  constant max_fifo_index : integer := (max_transmitter_delay_c + ssp_offset) / data_bit_time;

  ---------------------------------------------------------------------------
  -- Registered signals (driven by state_update)
  ---------------------------------------------------------------------------
  signal state          : tx_pcs_fsm_state_t;
  signal clk_count_nom  : integer range 0 to nom_prescaler - 1;
  signal clk_count_data : integer range 0 to data_prescaler - 1;
  signal tq_count       : integer range 0 to nom_bit_time;
  signal current_bit    : mac_frame_bit_t;
  signal delay_count    : integer range 0 to max_transmitter_delay_c;
  signal ssp_position   : integer range 0 to data_bit_time - 1;
  signal fifo_index     : integer range 0 to transmitted_bits_fifo_depth_c - 1;

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

  -- Intermediate signals for registered outputs
  signal next_pcs_to_mac_o : pcs_to_mac_if_t;
  signal next_tx_bus_o     : std_logic;

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

  ---------------------------------------------------------------------------
  -- Process 1: next_state_logic (combinational)
  ---------------------------------------------------------------------------
  next_state_logic : process (all) is

    -- Named guard variables (RTL guide Rule 3)
    variable frame_active_v  : boolean;
    variable rx_dominant_v   : boolean;
    variable tdc_timeout_v   : boolean;
    variable is_crc_delim_v  : boolean;
    variable sample_strobe_v : boolean;

  begin

    -- Evaluate guards
    frame_active_v  := mac_to_pcs_i.valid;
    rx_dominant_v   := (rx_bus_i = dominant_bit_c);
    tdc_timeout_v   := (delay_count >= max_transmitter_delay_c);
    is_crc_delim_v  := (current_bit.bit_name = crc_delimiter_bit);
    sample_strobe_v := next_pcs_to_mac_o.sample_strobe = '1';

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
          -- ISO 11898-1: 7.3.4 - Trigger TDC measurement at res bit (FDF->res edge)
          if (current_bit.bit_name = res_bit and sample_strobe_v) then
            if (use_tdc_c) then
              next_state <= measuring_delay;
            else
              next_state <= transmitting_data;
            end if;
          elsif (current_bit.bit_name = brs_bit and sample_strobe_v) then
            -- If no TDC or measurement already done, transition to data phase at BRS SP
            next_state <= transmitting_data;
          end if;

        when measuring_delay =>
          -- Measurement complete when RX detects dominant (ISO 11898-1: 7.3.4)
          if (rx_dominant_v) then
            next_state <= transmitting_data;
          elsif (tdc_timeout_v) then
            next_state <= transmitting_nominal;
          end if;

        when transmitting_data =>
          -- ISO 11898-1: 6.6.11.6 - Exit FD data phase at the sample point of the CRC delimiter bit.
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

    -- Temporary variables for pulse generation
    variable nom_tq_tick_v  : boolean;
    variable data_tq_tick_v : boolean;
    variable sp_pulse_v     : std_logic;
    variable ssp_pulse_v    : std_logic;

    -- Named guards
    variable nominal_bit_boundary_v : boolean;
    variable data_bit_boundary_v    : boolean;
    variable rx_dominant_v          : boolean;
    variable is_ssp_required_v      : boolean;

    -------------------------------------------------------------------------
    -- Local procedures for datapath abstraction
    -------------------------------------------------------------------------

    -- Generate Time Quantum (TQ) ticks based on prescalers
    procedure generate_tq_ticks is
    begin

      nom_tq_tick_v  := false;
      data_tq_tick_v := false;

      -- Nominal TQ tick
      if (clk_count_nom = nom_prescaler - 1) then
        nom_tq_tick_v      := true;
        next_clk_count_nom <= 0;
      else
        next_clk_count_nom <= clk_count_nom + 1;
      end if;

      -- Data TQ tick
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

    -- Manage bit-level timing and data latching
    procedure manage_bit_timing is
    begin

      -- Evaluate guards
      nominal_bit_boundary_v := (nom_tq_tick_v and tq_count >= nom_bit_time - 1);
      data_bit_boundary_v    := (data_tq_tick_v and tq_count >= data_bit_time - 1);

      case state is
        when idle =>
          -- Maintain nominal timing in idle for bus monitoring
          if (nom_tq_tick_v) then
            if (tq_count >= nom_bit_time - 1) then
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

    -- Perform Transmitter Delay Compensation measurement
    procedure perform_tdc_measurement is

      variable delay_with_offset_v : integer;
      variable ssp_position_v      : integer;

    begin

      -- Evaluate guard
      rx_dominant_v := (rx_bus_i = dominant_bit_c);

      if (state = measuring_delay) then
        -- Count delay from TX to RX detection
        if (data_tq_tick_v and delay_count < max_transmitter_delay_c) then
          next_delay_count <= delay_count + 1;
        end if;

        -- Latch measurement results on dominant edge
        if (rx_dominant_v) then
          delay_with_offset_v := delay_count + ssp_offset;
          next_fifo_index     <= calculate_fifo_delay_index(delay_with_offset_v, data_bit_time);

          ssp_position_v := delay_with_offset_v;

          while (ssp_position_v >= data_bit_time) loop
            ssp_position_v := ssp_position_v - data_bit_time;
          end loop;

          next_ssp_position <= ssp_position_v;
        end if;
      end if;

      -- Reset logic
      if (state /= measuring_delay and next_state = measuring_delay) then
        next_delay_count <= 0;
      end if;

    end procedure perform_tdc_measurement;

    -- Generate primary and secondary sample points
    procedure select_effective_strobe is
    begin

      sp_pulse_v  := '0';
      ssp_pulse_v := '0';

      -- Primary SP generation
      if (state = transmitting_data) then
        if (data_tq_tick_v and tq_count = data_sp_position - 1) then
          sp_pulse_v := '1';
        end if;
      else
        if (nom_tq_tick_v and tq_count = sp_position - 1) then
          sp_pulse_v := '1';
        end if;
      end if;

      -- Secondary SP generation (ISO 7.3.4)
      if (state = transmitting_data and use_tdc_c) then
        if (data_tq_tick_v and tq_count = ssp_position) then
          ssp_pulse_v := '1';
        end if;
      end if;

      -- Effective strobe selection (ISO 11898-1: 6.6.21.3.1 TDC)
      -- ESI is first bit of FD data phase after BRS; must use SSP with TDC delay
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

    -------------------------------------------------------------------------
    -- Output defaults: hold current registered value
    -------------------------------------------------------------------------
    next_clk_count_nom  <= clk_count_nom;
    next_clk_count_data <= clk_count_data;
    next_tq_count       <= tq_count;
    next_current_bit    <= current_bit;
    next_delay_count    <= delay_count;
    next_ssp_position   <= ssp_position;
    next_fifo_index     <= fifo_index;

    next_pcs_to_mac_o <= pcs_to_mac_o;
    next_tx_bus_o     <= tx_bus_o;

    -- Continuously drive bus polarity (unregistered)
    next_pcs_to_mac_o.bus_polarity <= std_logic_to_polarity(rx_bus_i);

    -------------------------------------------------------------------------
    -- Logic evaluation
    -------------------------------------------------------------------------
    generate_tq_ticks;
    manage_bit_timing;
    perform_tdc_measurement;
    select_effective_strobe;

    -- Continuous output drive
    next_tx_bus_o <= polarity_to_std_logic(current_bit.polarity);

    -- Reset TDC on return to idle
    if (state /= idle and next_state = idle) then
      next_current_bit <= reset_mac_frame_bit_c;
      next_fifo_index  <= 0;
    end if;

  end process output_logic;

  ---------------------------------------------------------------------------
  -- Process 3: state_update (clocked)
  ---------------------------------------------------------------------------
  state_update : process (clk) is
  begin

    if rising_edge(clk) then
      if (rst = '1') then
        state          <= idle;
        clk_count_nom  <= 0;
        clk_count_data <= 0;
        tq_count       <= 0;
        current_bit    <= reset_mac_frame_bit_c;
        delay_count    <= 0;
        ssp_position   <= 0;
        fifo_index     <= 0;

        pcs_to_mac_o <= pcs_to_mac_if_reset_c;
        tx_bus_o     <= '1'; -- recessive
      else
        state          <= next_state;
        clk_count_nom  <= next_clk_count_nom;
        clk_count_data <= next_clk_count_data;
        tq_count       <= next_tq_count;
        current_bit    <= next_current_bit;
        delay_count    <= next_delay_count;
        ssp_position   <= next_ssp_position;
        fifo_index     <= next_fifo_index;

        pcs_to_mac_o <= next_pcs_to_mac_o;
        tx_bus_o     <= next_tx_bus_o;
      end if;
    end if;

  end process state_update;

end architecture rtl;
