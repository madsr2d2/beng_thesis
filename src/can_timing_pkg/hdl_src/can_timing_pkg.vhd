--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Timing logic and policy functions for the CAN/CAN-FD PCS layer.
--                Implements TDC activation policy per ISO 11898-1:2015.
--
-- Revision log:  Date:       Initial:  JIRA:
--                2026-03-31  MRDSA     Converted to company header format
--------------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.pk_can_types.all;

package can_timing_pkg is

  -- Determines if Transmitter Delay Compensation (TDC) should be active
  -- based on the current bit rate and hardware propagation delays.
  function should_use_tdc (
    system_clock_freq               : natural;
    prescaler_cfg                   : natural;
    sync_seg_cfg                    : natural;
    prop_seg_fd                     : natural;
    phase_seg1_fd                   : natural;
    phase_seg2_fd                   : natural;
    pcs_to_pma_propagation_delay_ns : natural
  ) return boolean;

  -- Calculates TDC delay in bit times for SSP-aligned monitoring (ISO 7.3.4).
  function calculate_tdc_delay (
    delay_with_offset : natural;
    data_bit_time     : natural
  ) return natural;

end package can_timing_pkg;

package body can_timing_pkg is

  function should_use_tdc (
    system_clock_freq               : natural;
    prescaler_cfg                   : natural;
    sync_seg_cfg                    : natural;
    prop_seg_fd                     : natural;
    phase_seg1_fd                   : natural;
    phase_seg2_fd                   : natural;
    pcs_to_pma_propagation_delay_ns : natural
  ) return boolean is

    variable bit_time_tq   : natural;
    variable early_bits_tq : natural;
    variable tq_period_ns  : natural;

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

  function calculate_tdc_delay (
    delay_with_offset : natural;
    data_bit_time     : natural
  ) return natural is

    variable index : natural;

  begin

    -- Integer division: number of complete data bit times in delay
    index := delay_with_offset / data_bit_time;

    if (index >= c_tdc_polarity_depth) then
      index := c_tdc_polarity_depth - 1;
    end if;

    return index;

  end function calculate_tdc_delay;

end package body can_timing_pkg;
