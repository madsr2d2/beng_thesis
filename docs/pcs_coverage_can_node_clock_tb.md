# PCS External Requirements Coverage: `can_node_clock_tb`

**Module under test**: `can_node_clock`
**Testbench**: `can_bus_controller/hdl_tb/can_node_clock_tb.vhd`
**Date reviewed**: 2026-03-03

The `can_node_clock` module maps loosely to the PCS synchronization and bit timing
responsibility. It takes `rx_i` (incoming bus bit stream) and produces `sample_rx_o`
(sample point strobe) and `transmit_o`. Only PCS external requirements are assessed here.

---

## Directly Tested

**REQ-PCS-008** — *Sample point: the point in time at which bus level is read and interpreted*
**Tested.** This is the central assertion in `p_main_tester`. After each `bit_clk` edge,
it measures `v_time_to_sample` (time from bit start to `sample_rx_o` pulse) and checks:
```vhdl
AffirmIf(..., v_time_to_sample >= v_min_rx_sample_pulse_arrival_time, ...);
AffirmIf(..., v_time_to_sample <= v_max_rx_sample_pulse_arrival_time, ...);
```
This directly verifies that `sample_rx_o` (the canonical `PCS_Data.Indicate` strobe) fires
within the valid sample point window — Rule 1b.

**REQ-PCS-026** — *Hard synchronization on SOF edge (recessive→dominant during inter-frame space)*
**Tested.** The bit source always starts a frame with `rx <= '0'` (SOF dominant) after a
recessive inter-frame gap. The `wait until rx_sync = '0'` line then immediately begins
timing the sample point from the SOF edge, which is exactly the hard sync trigger condition.
The sample-point bounds check verifies the bit timing was restarted correctly.

**REQ-PCS-028** — *After hard synchronization, bit time restarted by each bit-timing segment starting with sync_seg*
**Tested.** Same SOF hard-sync path as REQ-PCS-026. The fact that `v_time_to_sample` is
measured from the SOF edge and compared to fixed fractions of `v_bit_time` verifies the
bit time was properly restarted.

---

## Implicitly Tested (no direct assertion, but bounds check would catch violations)

**REQ-PCS-013** — *Information processing time ≤ 2 t_q*
**Not tested.** IPT is the time from `PCS_Data.Indicate` firing (sample point) to MAC
issuing `PCS_Data.Request` for the next bit — it is the MAC's computation latency, not
a PCS-internal timing property. Verifying it requires observing both signals at the
MAC↔PCS boundary. `can_node_clock_tb` only observes `sample_rx_o` and never drives a
corresponding request back; the MAC side of the interface is absent.

**REQ-PCS-024** — *Only one synchronization per bit time (between two sample points)*
**Implicitly tested.** The checker verifies the sample point stays within bounds on every
bit — which would fail if multiple synchronizations per bit caused the sample to wander.
No explicit assertion counts synchronization events.

**REQ-PCS-025** — *Edge causes sync only if previous sample saw a different bus level*
**Implicitly tested.** `rand_rx_bit` with `v_last_bits` shift register produces realistic
transitions. If the DUT synchronized on wrong edges, sample timing would fall outside
bounds. Not explicitly asserted.

**REQ-PCS-027** — *All other eligible recessive-to-dominant edges used for resynchronization*
**Implicitly tested.** With 5000 random frames including varied bit patterns (40/60%
transition probability in `rand_rx_bit`), many mid-frame recessive-to-dominant edges occur.
If resynchronization were missing, accumulated phase error would push sample points outside
the checked bounds.

**REQ-PCS-029** — *Phase error ≤ SJW: phase_seg1 extended / phase_seg2 shortened by magnitude of phase error*
**Implicitly tested.** `send_worst` mode applies `±c_max_clock_delta` (1.2%) frequency
offset and uses max frame length — worst-case resync stress. If SJW-bounded correction
weren't working, the sample point would drift outside bounds. Not explicitly asserted in
t_q units.

**REQ-PCS-030** — *Phase error > SJW: adjustment capped at SJW*
**Stress-tested.** The `c_clock_delta` computation (lines 85–87) derives the maximum
tolerable clock delta from the configured SJW, seg1, and seg2. `c_max_clock_delta = 1.2%`
is set to be within this limit. The `send_worst` path exercises the SJW cap condition,
and sample-point bounds checks verify the capped adjustment is applied correctly.

---

## Not Tested

| Requirement | Reason not covered |
|---|---|
| **REQ-PCS-005** | Time quantum as integer multiple of clock period — bounds check uses floating-point fractions of `v_bit_time`, not t_q counts; no explicit granularity check |
| **REQ-PCS-001/002** | `D_Transmit`/`D_Receive` (FD data phase signals) — `can_node_clock` has no FD data phase port; testbench is nominal-rate-only |
| **REQ-PCS-003** | Separate nominal/FD bit rate configs — only a single bit rate (`gc_bit_rate_hz`) is configured |
| **REQ-PCS-004** | FD data bit time used only in FD data phase — no FD frames, no BRS phase |
| **REQ-PCS-017** | TDC existence requirement — no TDC port on this module |
| **REQ-PCS-018** | TDC activation conditions (FD data phase only) — not applicable |
| **REQ-PCS-022** | SSP position = measured delay + offset — no SSP output port |
| **REQ-PCS-031** | No sync after own transmitted dominant edge — `transmit_o` is not exercised; no loopback |
| **REQ-PCS-034** | `PCS_Data.Request` → Output_Unit forwarding — no bus drive output port tested |
| **REQ-PCS-035/036** | `Bus_off` / `Bus_off_release` symbols — no FCE interface on this module |

---

## Summary

The testbench covers the **synchronization and sample point timing** cluster well
(REQ-PCS-008, 026, 027, 028, 029, 030) through direct timing assertions and stress
testing with clock frequency offsets up to ±1.2%.

The FD-specific requirements (PCS-001–004, 017–018, 022), bus-drive requirements
(PCS-034), and fault confinement requirements (PCS-035–036) are entirely out of scope
for this module and testbench — as expected for a clock/synchronization sub-module.

| Category | Count | Requirements |
|---|---|---|
| Directly tested | 3 | PCS-008, 026, 028 |
| Implicitly tested | 5 | PCS-024, 025, 027, 029, 030 |
| Not tested (out of scope for module) | 11 | PCS-001, 002, 003, 004, 005, 013, 017, 018, 022, 031, 034, 035, 036 |
