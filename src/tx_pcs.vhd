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
    ssp_offset      : ssp_offset    := 4
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
  constant nom_bit_time  : integer := nom_sync_seg + nom_prop_seg + nom_phase_seg1 + nom_phase_seg2;
  constant data_bit_time : integer := data_sync_seg + data_prop_seg + data_phase_seg1 + data_phase_seg2;
  constant sp_position   : integer := nom_sync_seg + nom_prop_seg + nom_phase_seg1; -- SP at end of Phase_Seg1

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
  signal delay_count  : integer range 0 to max_transmitter_delay_c           := 0;
  signal ssp_position : integer range 0 to data_bit_time - 1                 := 0;
  signal fifo_index   : integer range 0 to transmitted_bits_fifo_depth_c - 1 := 0;

  -- Sample point pulses
  signal sp_pulse  : std_logic := '0';
  signal ssp_pulse : std_logic := '0';

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

  -- Output assignments
  pcs_to_mac_o.bus_polarity <= std_logic_to_polarity(rx_bus_i);
  pcs_to_mac_o.sp           <= sp_pulse;
  pcs_to_mac_o.ssp          <= ssp_pulse;
  pcs_to_mac_o.fifo_index   <= fifo_index;

  tx_bus_o <= polarity_to_std_logic(current_bit.polarity);
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
        if (clk_count_data = data_prescaler - 1) then
          data_tq_tick   <= '1';
          clk_count_data <= 0;
        else
          clk_count_data <= clk_count_data + 1;
        end if;

      end if;
    end if;

  end process tq_generator;

  ------------------------------------------------------------------------------
  -- Main PCS FSM (Registered Process)
  ------------------------------------------------------------------------------
  pcs_fsm : process (clk) is

    -- Advance bit timing: latch next frame_bit at bit boundary
    procedure advance_bit_timing_and_latch_bit (
      tq_tick  : std_logic;
      bit_time : integer
    ) is
    begin

      if (tq_tick = '1') then
        if (tq_count >= bit_time - 1) then
          tq_count    <= 0;
          current_bit <= mac_to_pcs_i.data;
        else
          tq_count <= tq_count + 1;
        end if;
      end if;

    end procedure advance_bit_timing_and_latch_bit;

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
        state <= next_state;

        -- Reset delay counter on entry to measuring_delay
        if (state /= measuring_delay and next_state = measuring_delay) then
          delay_count <= 0;
        end if;

        -- Reset TDC outputs on return to idle
        if (next_state = idle and state /= idle) then
          fifo_index <= 0;
        end if;

        case state is

          when idle =>
            -- Wait for first bit request from MAC
            if (mac_to_pcs_i.valid) then
              current_bit <= mac_to_pcs_i.data;
              tq_count    <= 0;
            end if;

          when transmitting_nominal =>
            advance_bit_timing_and_latch_bit(nom_tq_tick, nom_bit_time);

          when measuring_delay =>
            advance_bit_timing_and_latch_bit(nom_tq_tick, nom_bit_time);

            -- Latch measurement results when RX detects dominant
            if (rx_bus_i = dominant_bit_c) then
              ssp_position <= (delay_count + ssp_offset) mod data_bit_time;
              fifo_index   <= calculate_fifo_delay_index(delay_count + ssp_offset, data_bit_time);
            end if;

            -- Count delay from TX to RX detection (increment on data TQ ticks)
            if (data_tq_tick = '1' and delay_count < max_transmitter_delay_c) then
              delay_count <= delay_count + 1;
            end if;

          when transmitting_data =>
            advance_bit_timing_and_latch_bit(data_tq_tick, data_bit_time);

        end case;

      end if;
    end if;

  end process pcs_fsm;

  ------------------------------------------------------------------------------
  -- FSM Next State Logic (Combinational)
  ------------------------------------------------------------------------------
  next_state_logic : process (all) is
  begin

    -- Default: stay in current state
    next_state <= state;

    -- Global: return to idle when MAC deasserts data_request (frame complete)
    if (state /= idle and not mac_to_pcs_i.valid) then
      next_state <= idle;
    else

      case state is

        when idle =>
          if (mac_to_pcs_i.valid) then
            next_state <= transmitting_nominal;
          end if;

        when transmitting_nominal =>
          -- Start TDC measurement when res bit detected (res_bit only exists in FD frames)
          if (current_bit.bit_name = res_bit) then
            next_state <= measuring_delay;
          end if;

        when measuring_delay =>
          -- Measurement complete when RX detects dominant
          if (rx_bus_i = dominant_bit_c) then
            next_state <= transmitting_data;
          end if;

          -- Timeout: abort TDC, fall back to nominal
          if (delay_count >= max_transmitter_delay_c) then
            next_state <= transmitting_nominal;
          end if;

        when transmitting_data =>
          -- Exit data phase when CRC delimiter detected (PCS derives phase from bit_name)
          if (current_bit.bit_name = crc_delimiter_bit) then
            next_state <= transmitting_nominal;
          end if;

      end case;

    end if;

  end process next_state_logic;

  ------------------------------------------------------------------------------
  -- Sample Point Pulse Generator
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

          when transmitting_nominal | measuring_delay =>
            -- Generate SP pulse at sample point position (nominal timing)
            -- tq_count increments on nom_tq_tick, so check count - 1 on tick
            if (nom_tq_tick = '1' and tq_count = sp_position - 1) then
              sp_pulse <= '1';
            end if;

          when transmitting_data =>
            -- Generate SSP pulse once per data bit at the computed position within each bit
            if (data_tq_tick = '1' and tq_count = ssp_position) then
              ssp_pulse <= '1';
            end if;

          when others =>
            null;

        end case;

      end if;
    end if;

  end process sp_pulse_gen;

end architecture rtl;
