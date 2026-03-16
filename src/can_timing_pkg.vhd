--------------------------------------------------------------------------------
-- Title      : CAN Bus Timing Calculations
-- Project    : CAN Bus Transmitter
--------------------------------------------------------------------------------
-- File       : can_timing_pkg.vhd
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: Timing logic and policy functions for the CAN/CAN-FD PCS layer.
--              Implements TDC activation policy per ISO 11898-1:2015.
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

package can_timing_pkg is

  -- Determines if Transmitter Delay Compensation (TDC) should be active
  -- based on the current bit rate and hardware propagation delays.
  function should_use_tdc (
    system_clock_freq               : integer;
    prescaler_cfg                   : integer;
    sync_seg_cfg                    : integer;
    prop_seg_fd                     : integer;
    phase_seg1_fd                   : integer;
    phase_seg2_fd                   : integer;
    pcs_to_pma_propagation_delay_ns : integer
  ) return boolean;

  -- Calculates circular FIFO index for SSP-aligned monitoring (ISO 7.3.4).
  function calculate_fifo_delay_index (
    delay_with_offset : integer;
    data_bit_time     : integer
  ) return integer;

end package can_timing_pkg;

package body can_timing_pkg is

  function should_use_tdc (
    system_clock_freq               : integer;
    prescaler_cfg                   : integer;
    sync_seg_cfg                    : integer;
    prop_seg_fd                     : integer;
    phase_seg1_fd                   : integer;
    phase_seg2_fd                   : integer;
    pcs_to_pma_propagation_delay_ns : integer
  ) return boolean is

    variable bit_time_tq   : integer;
    variable early_bits_tq : integer;
    variable tq_period_ns  : integer;

  begin

    -- Calculate time quantum counts (in clock periods)
    bit_time_tq   := (sync_seg_cfg + prop_seg_fd + phase_seg1_fd + phase_seg2_fd) * prescaler_cfg;
    early_bits_tq := (sync_seg_cfg + prop_seg_fd + phase_seg1_fd) * prescaler_cfg;

    -- Calculate nanoseconds per time quantum
    tq_period_ns := 1_000_000_000 / system_clock_freq;

    -- Condition 1: SHOULD use TDC if bit_time <= c_tdc_bit_time_max (ISO 11898-1: 7.3.4)
    if (bit_time_tq * tq_period_ns <= c_tdc_bit_time_max) then
      return true;
    end if;

    -- Condition 2: NEEDS use TDC if early phase < pcs_to_pma_propagation_delay_ns
    if (early_bits_tq * tq_period_ns < pcs_to_pma_propagation_delay_ns) then
      return true;
    end if;

    return false;

  end function should_use_tdc;

  function calculate_fifo_delay_index (
    delay_with_offset : integer;
    data_bit_time     : integer
  ) return integer is

    variable index : integer;

  begin

    -- Integer division: number of complete data bit times in delay
    index := delay_with_offset / data_bit_time;

    -- Clamp to FIFO depth
    if (index >= c_transmitted_bits_fifo_depth) then
      index := c_transmitted_bits_fifo_depth - 1;
    end if;

    return index;

  end function calculate_fifo_delay_index;

end package body can_timing_pkg;
