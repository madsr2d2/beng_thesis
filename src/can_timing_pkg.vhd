--------------------------------------------------------------------
-- can_timing_pkg.vhd
-- Timing and TDC helper functions for CAN/CAN-FD.
--------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.can_types_pkg.all;

package can_timing_pkg is
  function should_use_tdc (
    system_clock_freq : integer;
    prescaler_cfg : integer;
    sync_seg_cfg : integer;
    prop_seg_fd : integer;
    phase_seg1_fd : integer;
    phase_seg2_fd : integer;
    pcs_to_pma_propagation_delay_ns : integer
  ) return boolean;

  -- Calculate FIFO delay index from measured transmitter delay (ISO 7.3.4)
  -- Converts delay in time quanta to FIFO index for bit-stream comparison
  function calculate_fifo_delay_index (
    measured_delay_tq : integer;
    data_bit_time_tq  : integer
  ) return integer;
end package can_timing_pkg;

package body can_timing_pkg is

  function calculate_fifo_delay_index (
    measured_delay_tq : integer;
    data_bit_time_tq  : integer
  ) return integer is

    variable index : integer;

  begin

    -- Integer division: number of complete data bit times in delay
    index := measured_delay_tq / data_bit_time_tq;

    -- Clamp to FIFO depth
    if (index >= transmitted_bits_fifo_depth_c) then
      index := transmitted_bits_fifo_depth_c - 1;
    end if;

    return index;

  end function calculate_fifo_delay_index;

  function should_use_tdc (
    system_clock_freq : integer;
    prescaler_cfg : integer;
    sync_seg_cfg : integer;
    prop_seg_fd : integer;
    phase_seg1_fd : integer;
    phase_seg2_fd : integer;
    pcs_to_pma_propagation_delay_ns : integer
  ) return boolean is

    variable bit_time_tq   : integer;
    variable early_bits_tq : integer;
    variable tq_period_ns  : integer;

  begin

    -- Calculate time quantum counts (in clock periods)
    bit_time_tq   := (sync_seg_cfg + prop_seg_fd + phase_seg1_fd + phase_seg2_fd) * prescaler_cfg;
    early_bits_tq := (sync_seg_cfg + prop_seg_fd + phase_seg1_fd) * prescaler_cfg;

    -- Calculate nanoseconds per time quantum: tq_ns = 1_000_000_000 / system_clock_freq
    tq_period_ns := 1_000_000_000 / system_clock_freq;

    -- Condition 1: SHOULD use TDC if bit_time <= tdc_bit_time_max_c (ISO 11898-1: 7.3.4)
    if (bit_time_tq * tq_period_ns <= tdc_bit_time_max_c) then
      return true;
    end if;

    -- Condition 2: NEEDS use TDC if early phase < pcs_to_pma_propagation_delay_ns
    if (early_bits_tq * tq_period_ns < pcs_to_pma_propagation_delay_ns) then
      return true;
    end if;

    return false;

  end function should_use_tdc;

end package body can_timing_pkg;
