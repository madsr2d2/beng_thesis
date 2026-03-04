# PCS Requirements Coverage: `can_node_clock_tb`

**Module under test**: `can_node_clock`
**Testbench**: `can_bus_controller/hdl_tb/can_node_clock_tb.vhd`
**Date reviewed**: 2026-03-03

The `can_node_clock` module maps onto the PCS bit timing and synchronisation state machine.
Its interface is:

- **Inputs**: `clk_i`, `reset_i`, `rx_i` (bus receive, via synchronizer)
- **Outputs**: `sample_rx_o` (sample point strobe — maps to `PCS_Data.Indicate`), `transmit_o` (maps to `PCS_Status.Transmitter`)

The TB's core measurement loop captures *when* `sample_rx_o` fires relative to the start of
each bit and checks it lands between 40%–92% of the bit period. The `send_worst` mode exercises
±1.2% clock delta at maximum frame length (111 bits).

---

## Directly Tested

**REQ-PCS-008** — *Sample point fires at end of Phase_Seg1*

This is the central assertion in `p_main_tester`. After each `bit_clk` edge it measures
`v_time_to_sample` (time from bit start to `sample_rx_o` pulse) and checks:

```vhdl
AffirmIf(..., v_time_to_sample >= v_min_rx_sample_pulse_arrival_time, ...);
AffirmIf(..., v_time_to_sample <= v_max_rx_sample_pulse_arrival_time, ...);
```

This directly verifies that `sample_rx_o` (the canonical `PCS_Data.Indicate` strobe) fires
within the valid sample point window for every bit across all 5000 frames.

**REQ-PCS-026** — *Hard sync on IFS edges / bus-integration state*

The TB resets the DUT before each frame (`reset <= '1', '0' after gc_TbClkPeriod + 1 ns`)
then waits for `rx_sync = '0'` (the SOF dominant edge) before beginning timing. This exercises
the hard sync on the bus-integration → idle boundary. If the bit time were not restarted
correctly from the SOF edge the first sample would land outside the 40%–92% window.

**REQ-PCS-028** — *Hard sync restarts bit time from sync_seg; not limited by SJW*

Covered by the same reset + SOF path as REQ-PCS-026. `v_time_to_sample` is measured from the
SOF edge and compared to fixed fractions of `v_bit_time`, verifying the bit time was fully
restarted independent of `gc_sync_jump_width`.

---

## Implicitly Tested

The bounds check would catch violations of these requirements even though no dedicated
assertion targets them directly.

**REQ-PCS-024** — *Only one synchronisation per bit time; disabled until next recessive SP*

If multiple synchronisations per bit were applied the sample point would accumulate drift and
escape the checked window. The random bit generator produces back-to-back edges via `rand_rx_bit`,
giving repeated opportunities for this failure mode.

**REQ-PCS-025** — *Sync only if bus state at previous SP was recessive*

`rand_rx_bit` with the `v_last_bits` shift register produces realistic transitions including
dominant-SP-to-edge sequences. If the DUT synchronised on ineligible edges the sample timing
would shift outside bounds over a long frame.

**REQ-PCS-027** — *All eligible recessive-to-dominant edges used for resynchronisation*

With 5000 random frames at 40/60% transition probability, many mid-frame recessive-to-dominant
edges occur. If resynchronisation were missing, accumulated phase error from the frequency
offset (`v_delta_frequency`) would push sample points outside the checked bounds.

**REQ-PCS-029** — *Phase error ≤ SJW: resync has same effect as hard sync*

Random `v_delta_frequency` delivers small phase errors on most frames. Sample timing must stay
within bounds, which is only possible if small errors are fully corrected.

**REQ-PCS-030** — *Phase error > SJW: Phase_Seg1 extended / Phase_Seg2 shortened by SJW*

`send_worst` mode drives exactly ±`c_max_clock_delta` (1.2%) over the maximum frame length.
The theoretical clock tolerance for the configured parameters (`c_clock_delta ≈ 0.75%`) is
lower than 1.2%, meaning worst-case frames push the SJW correction to and beyond its limit.
The sample-point bounds check verifies the capped SJW adjustment is applied correctly.

> **Note**: because `c_max_clock_delta` (1.2%) exceeds `c_clock_delta` (0.75%), worst-case
> frames accumulate residual phase error that SJW cannot fully correct. The 40%–92% window
> must be wide enough to absorb this residual. REQ-PCS-030 is therefore stress-tested at
> beyond the SJW-correctable range, which is a valid robustness test but means the precise
> `m_nom × (1 + prop_seg_nom + phase_seg1_nom)` formula from the requirement is not being
> verified exactly in the worst-case path.

---

## Not Tested

| Requirement | Reason not covered |
|---|---|
| **REQ-PCS-005** | t_q = m × t_q_min: bounds check uses floating-point fractions of `v_bit_time`, not integer t_q counts; no explicit granularity check at clock-cycle resolution |
| **REQ-PCS-013** | IPT ≤ 2 t_q: requires measuring the delta between `sample_rx_o` and the subsequent `transmit_o`; the TB never checks this delta |
| **REQ-PCS-027** | Resync only on recessive→dominant edges: the TB does not inject dominant→recessive edges mid-bit and verify the sample point does not shift |
| **REQ-PCS-031** | No sync after a dominant SP: requires specific dominant-SP-then-edge sequences with a timing assertion that `sample_rx_o` does not shift; not present |
| **REQ-PCS-001/002** | D_Transmit / D_Receive parameter values: `transmit_o` is present but never checked for correct value; no FD data phase exercised |
| **REQ-PCS-003** | Three bit rates (nominal, FD data, FD SSP): only nominal rate tested |
| **REQ-PCS-004** | FD data bit time used only in FD data phase: no FD frames |
| **REQ-PCS-017/018** | Separate prescalers, TDC activation conditions: no TDC port on this module |
| **REQ-PCS-022** | SSP position = measured delay + ssp_offset: no SSP output port |
| **REQ-PCS-034** | PCS_Data.Request → Output symbol forwarding to PMA: no bus drive output port tested |
| **REQ-PCS-035/036** | Bus_off / Bus_off_release symbols to PMA: no FCE interface on this module |

---

## Summary

| Category | Requirements |
|---|---|
| Directly tested | PCS-008, PCS-026, PCS-028 |
| Implicitly tested | PCS-024, PCS-025, PCS-027, PCS-029, PCS-030 |
| Not tested — gap | PCS-005, PCS-013, PCS-031 |
| Not tested — out of scope for module | PCS-001, PCS-002, PCS-003, PCS-004, PCS-017, PCS-018, PCS-022, PCS-034, PCS-035, PCS-036 |

The testbench covers the **synchronisation and sample point timing** cluster well through
direct timing assertions and stress testing with clock frequency offsets up to ±1.2%. The
three nominal-CC-only gaps (PCS-005, PCS-013, PCS-031) are testable on this module and
represent concrete candidates for additional assertions in a future revision of the TB.

The FD-specific requirements (PCS-001–004, 017–018, 022), bus-drive requirements (PCS-034),
and fault confinement requirements (PCS-035–036) are entirely out of scope for this
synchronisation sub-module.
