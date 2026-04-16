# PCS Comparison: `can_node_clock` vs. `can_pcs_tx` / `can_pcs_rx` {#sec:pcs-comparison}

**Original module:** `can_bus_controller/hdl_src/can_node_clock.vhd` (2025, Everllence)
**New modules:** `src/can_pcs_tx/hdl_src/can_pcs_tx.vhd`, `src/can_pcs_rx/hdl_src/can_pcs_rx.vhd`
**Standard:** ISO 11898-1:2015, Sections 7.2, 7.3

## Overview

The original `can_node_clock` is a monolithic CAN Classic bit timing module that handles both sample point generation and resynchronization in a single process. It was designed for CAN Classic only (250-500 kbps). This document compares it with the two new PCS modules that replace it: `can_pcs_tx` for the transmit path and `can_pcs_rx` for the receive path. The new modules support CAN FD with dual bit rates, implement TDC for the transmitter, and address several ISO 7.3.5 compliance gaps found in the original.

## Architectural Differences {#sec:arch-differences}

@tbl:arch-comparison summarizes the structural differences between the three modules.

| Aspect | `can_node_clock` | `can_pcs_tx` | `can_pcs_rx` |
|--------|-----------------|-------------|-------------|
| Process count | 1 (monolithic) | 8 (decomposed) | 6 (decomposed) |
| Segment tracking | Implicit (merged `s_seg_1`) | Flat TQ counter | Explicit segment FSM |
| Prescaler | Built-in clock divider (`clk_div_counter`) | Dedicated free-running process | Dedicated restartable process |
| Edge detection resolution | TQ boundary only | Clock-cycle (for TDC) | Clock-cycle |
| Synchronization | Hard sync + resync (single process) | None (timing master) | Hard sync + resync (ISO 7.3.5) |
| CAN FD support | No | Yes (dual rate + TDC) | Yes (dual rate) |
| Rate switching | N/A | 3-state FSM (nom/measuring/data) | 2-state FSM (nom/data) |
| TDC / SSP | No | Yes (ISO 7.3.4) | No (receiver-side) |
| Bus-off idle detection | No | Yes (ISO 8.1.4.4) | Yes (ISO 8.1.4.4) |
| SJW generic | Yes (`gc_sync_jump_width`, 1-4) | No (not needed) | Yes (`gc_sjw`) |
| MAC interface | None (standalone) | Record-based (`t_can_mac_pcs_if_*`) | Record-based (`t_can_mac_pcs_rx_if_*`) |
| FCE interface | None | `t_can_fce_pcs_if_*` | `t_can_fce_pcs_if_*` |
| TX output | `transmit_o` (unused strobe) | `tx_bus_o` (frame bits) | `tx_bus_o` (ACK/error flags) |
| Lines of code | ~140 (1 process) | ~260 (8 processes) | ~310 (6 processes) |

: Architectural comparison of the three PCS modules. {#tbl:arch-comparison}

### Monolithic vs. decomposed architecture

The original module places all logic - prescaler, segment tracking, edge detection, resynchronization, and sample point generation - in a single 140-line process (`p_rx_sample_pulse_gen`). This makes it difficult to reason about timing interactions, particularly between the clock divider counter, the TQ counter, and the edge detection logic.

The new modules decompose responsibilities into dedicated processes. In `can_pcs_rx`, for example, `p_prescaler` handles only the restartable clock divider, `p_edge_detect` handles only bus sampling, `p_bit_timing` handles segment progression and synchronization, and `p_sample_point` handles strobe generation. Each process has a well-defined set of inputs and outputs, reducing the risk of unintended signal interactions.

### TX/RX separation

The original module was designed as a shared clock generator for both TX and RX, but in practice only served the RX path. The `transmit_o` output is explicitly commented as "not used in this module" on lines 39, 89, 96, 123, and 202. The new design cleanly separates the TX and RX timing concerns into distinct entities. This separation is motivated by a fundamental asymmetry: the transmitter is the timing master (no synchronization needed), while the receiver must synchronize to the transmitter's clock.

## Bugs and Issues in `can_node_clock` {#sec:can-node-clock-bugs}

### B1: Missing sync inhibit guard (ISO 7.3.5.1 rule a) {#sec:bug-sync-inhibit}

**ISO requirement:** "Only one synchronization within one bit time shall be allowed."

**Bug:** The original module has no `sync_inhibit` mechanism. If two recessive-to-dominant edges occur within the same bit time (e.g., due to bus noise or a glitch), both will trigger resynchronization adjustments. The edge detection in `s_seg_1` (line 144) and `s_seg_2` (line 182) fires unconditionally on every edge, with no guard preventing a second sync in the same bit.

**Fix in `can_pcs_rx`:** The `sync_inhibit` boolean signal is set on any synchronization event and cleared only at the bit boundary (Phase_Seg2 end). The guard `v_sync_allowed := edge_detected and not sync_inhibit and sampled_polarity = c_recessive` ensures exactly one synchronization per bit time.

### B2: Missing sampled polarity check (ISO 7.3.5.1 rule b) {#sec:bug-sampled-polarity}

**ISO requirement:** "An edge shall be used for synchronization only if the value detected at the previous sample point differs from the bus value immediately after the edge."

In practice, this means synchronization should only occur when the previous sample point read recessive (since synchronization is on recessive-to-dominant edges). This prevents false synchronization on a dominant-to-recessive-to-dominant glitch within a dominant bit.

**Bug:** The original module does not track the sampled polarity from the previous sample point. Any recessive-to-dominant edge triggers resynchronization, regardless of what was sampled at the last SP.

**Fix in `can_pcs_rx`:** The `sampled_polarity` signal is latched at every sample point. The sync guard includes `sampled_polarity = c_recessive` as a precondition.

### B3: TQ-resolution edge detection {#sec:bug-edge-resolution}

**Bug:** In the original module, `rx_prev` is only updated at TQ boundaries (line 101: inside the `clk_div_counter = c_bit_quanta_cycles` guard). This means edges that occur between TQ boundaries are not detected until the next TQ tick. At `c_bit_quanta_cycles = 16` (typical for 500 kbps at 100 MHz), this introduces up to 160 ns of undetected latency - a full TQ of synchronization error that compounds over consecutive bits.

**Interaction with resync:** The phase error calculation in `s_seg_1` (line 145: `v_phase_error := time_quantum_count + 1`) assumes the edge was detected at the TQ boundary. If the actual edge occurred mid-TQ, the calculated phase error is off by up to one TQ, which can cause the wrong resync action (restart vs. phase extension) for edge-case phase errors near the SJW boundary.

**Fix in `can_pcs_rx`:** `rx_bus_prev` is updated every clock cycle in `p_edge_detect`. The `edge_detected` combinational signal evaluates the current `rx_bus_i` against the previous-cycle value, detecting edges at clock-cycle resolution.

### B4: Persistent phase segment length modification {#sec:bug-persistent-phase}

**Bug:** The original module modifies `phase_seg1_length` and `phase_seg2_length` as persistent signals (lines 154-157, 192-195). Although these are reset to defaults at the end of each segment (lines 166, 204), there is a window where the modified value is visible to other logic. More critically, the modification uses the *current* persistent value as the base (`phase_seg1_length + v_phase_error`), not the default. If the reset at line 166 does not fire (e.g., because the segment end condition is not yet met), a subsequent edge in the same bit could compound the adjustment.

**Fix in `can_pcs_rx`:** `phase1_extension` and `phase2_shortening` are transient additive offsets (range 0 to `gc_sjw`) that modify the segment end comparison but not the base segment length. They are cleared unconditionally at the bit boundary (Phase_Seg2 end) or on hard sync restart. The base lengths (`active_phase_seg1`, `active_phase_seg2`) are derived combinationally from generics and cannot be corrupted.

### B5: Phase_Seg1 / Prop_Seg merged into single state {#sec:bug-phase1-race}

**Bug:** The original module merges Prop_Seg and Phase_Seg1 into a single `s_seg_1` state (lines 140-168). The combined segment boundary is computed as `gc_default_prop_seg_length + v_phase_seg1_length - 1` (line 161). When resynchronization modifies `v_phase_seg1_length`, the boundary comparison shifts, but the `time_quantum_count` continues incrementing from its current position. If a resync adjustment changes the boundary such that the count has already passed it, the segment will overrun into what should be Phase_Seg2 territory.

**Fix in `can_pcs_rx`:** Prop_Seg and Phase_Seg1 are tracked as separate states (`s_prop_seg`, `s_phase_seg1`) with independent `seg_count` tracking. The resync adjustment (`phase1_extension`) only affects the Phase_Seg1 end condition, not the Prop_Seg boundary. Segment transitions are clean: `s_prop_seg` -> `s_phase_seg1` at `seg_count = active_prop_seg - 1`, then `s_phase_seg1` -> `s_phase_seg2` at `seg_count = active_phase_seg1 + phase1_extension - 1`.

### B6: Sync_Seg skip after Phase_Seg2 shortening {#sec:bug-sync-skip}

**Bug:** Lines 206-208 of the original module:

```vhdl
if (v_phase_seg2_length /= (gc_default_phase_seg_2_length - 1)) then
  segment <= s_seg_1;
end if;
```

When Phase_Seg2 is shortened by resynchronization, the module skips the Sync_Seg entirely and jumps directly to `s_seg_1`. The ISO standard (7.3.2) defines Sync_Seg as a mandatory 1-TQ segment at the start of every bit time. Skipping it means the next bit time has no Sync_Seg, which shortens the total bit time by 1 TQ beyond the intended Phase_Seg2 adjustment.

The condition also has a subtle logic issue: it compares against `gc_default_phase_seg_2_length - 1` rather than the actual default. The `-1` accounts for the fact that `v_phase_seg2_length` was decremented on line 199, but this coupling between the comparison and a prior variable mutation is fragile.

**Fix in `can_pcs_rx`:** Sync_Seg is always traversed. The segment FSM unconditionally transitions from `s_phase_seg2` to `s_sync_seg` at the bit boundary. The 1-TQ Sync_Seg then transitions to `s_prop_seg`. No shortcut paths exist.

### B7: Reset-based hard sync re-entry {#sec:bug-no-mac-interface}

**ISO requirement:** Hard synchronization shall be performed during inter-frame space, bus integration, and at the FDF-to-res transition (ISO 7.3.5.1 rule c).

**Issue:** The original module re-enters `s_hard_sync` only via its `reset_i` port. The controlling `can_fsm` exploits this by pulsing `can_node_clk_reset_o` during intermission (`s_intermission`, `bit_count = 1`) to force the node clock back to the hard sync waiting state before the next SOF. This works for the CAN Classic inter-frame space case, but it is a blunt mechanism: a full reset clears all internal state (prescaler, TQ counter, phase segment lengths), not just the synchronization mode. It also does not cover the FDF-to-res transition (CAN FD was not supported) and cannot be pulsed mid-frame without disrupting the bit timing entirely.

**Fix in `can_pcs_rx`:** The MAC RX FSM drives a dedicated `hard_sync_en` signal. When high, any qualifying edge triggers hard sync (prescaler + segment restart). When low, edges trigger SJW-bounded resynchronization. This allows the MAC to switch synchronization mode at any point during a frame - including the FDF-to-res transition - without resetting the PCS state.

### B8: Mixed variable/signal semantics in resync logic

**Bug:** In `s_seg_1`, the code uses `v_phase_seg1_length` (variable, immediate update) to compute the segment boundary on line 162, while simultaneously assigning `phase_seg1_length` (signal, next-cycle update) on lines 154-157. The variable is reassigned on line 161 from the *signal* value, creating a dependency chain where the behavior differs depending on whether a resync edge was detected in the current TQ or a previous one. This mixed timing makes the logic difficult to verify and potentially incorrect for edge cases where the resync edge and segment boundary coincide.

**Fix in `can_pcs_rx`:** All synchronization state (`phase1_extension`, `phase2_shortening`, `sync_inhibit`) uses signals with well-defined next-cycle semantics. The segment end comparison in `p_bit_timing` reads the current signal values, and any resync adjustment takes effect on the next clock edge. No variable/signal mixing in the sync path.

## ISO 11898-1 Compliance Analysis of `can_node_clock` {#sec:iso-compliance}

@tbl:iso-compliance summarizes which ISO 7.3 requirements are met by the original module.

| ISO Section | Requirement | `can_node_clock` | Notes |
|-------------|------------|:-:|-------|
| 7.3.2 | Sync_Seg = 1 TQ, Prop_Seg + Phase_Seg1 + Phase_Seg2 configurable | Partial | Sync_Seg implemented but skipped after Phase_Seg2 shortening (@sec:bug-sync-skip) |
| 7.3.2 | SP at Phase_Seg1/Phase_Seg2 boundary | Yes | Sample strobe fires at correct position |
| 7.3.5.1(a) | One sync per bit time | No | No sync_inhibit guard (@sec:bug-sync-inhibit) |
| 7.3.5.1(b) | Sync only after recessive SP | No | No sampled_polarity check (@sec:bug-sampled-polarity) |
| 7.3.5.1(c) | Hard sync during bus integration, FDF-to-res | Partial | Re-entered via reset pulse from FSM during intermission; no FDF-to-res support (@sec:bug-no-mac-interface) |
| 7.3.5.1(d) | Resync during frame | Yes | `s_seg_1` and `s_seg_2` apply resync on edges |
| 7.3.5.3 | Hard sync: restart bit time | Yes | `s_hard_sync` restarts prescaler and counter |
| 7.3.5.4 | Resync: lengthen Phase_Seg1 or shorten Phase_Seg2, bounded by SJW | Yes | Both paths implemented, SJW capped |
| 7.3.2 | Configurable SJW (1-4 TQ) | Yes | Generic `gc_sync_jump_width` |
| 7.3.4 | Transmitter Delay Compensation | No | CAN Classic only, no TDC |
| 7.3.2 | Dual nominal/data bit rate | No | Single rate, no CAN FD |

: ISO 7.3 compliance status for `can_node_clock`. {#tbl:iso-compliance}

The original module correctly implements the core resynchronization algorithm (Phase_Seg1 lengthening and Phase_Seg2 shortening) and the SJW bounding. However, it does not enforce the two most important synchronization guards (rules a and b of ISO 7.3.5.1), which can lead to incorrect synchronization behavior on noisy buses.

## Design Improvements in the New Modules {#sec:improvements}

### ISO compliance

Both new modules enforce all four rules of ISO 7.3.5.1:

- **Rule a** (one sync per bit): `sync_inhibit` flag in `can_pcs_rx`.
- **Rule b** (recessive SP required): `sampled_polarity` latch in `can_pcs_rx`.
- **Rule c** (hard sync re-enterable): MAC-driven `hard_sync_en` in `can_pcs_rx`.
- **Rule d** (resync during frame): segment-aware resync logic in `can_pcs_rx`.

The TX PCS does not need synchronization (it is the timing master), so these rules are not applicable.

### CAN FD support

Both new modules support dual nominal/data bit rates via separate generic parameters for each rate (`gc_nom_*` and `gc_data_*`). The rate switch is controlled by the MAC FSM through `use_data_rate`. The TX PCS additionally implements TDC with SSP generation (ISO 7.3.4), which is critical for reliable CAN FD operation at data rates above 1 Mbps.

### Bus-off idle detection

Both new modules implement the ISO 8.1.4.4 bus-off recovery mechanism: counting 128 occurrences of 11 consecutive recessive bits at the sample point. The original module has no bus-off awareness and would continue normal operation regardless of fault confinement state.

### Clock-cycle edge detection

Moving edge detection from TQ resolution to clock-cycle resolution eliminates up to one TQ of synchronization latency. For a typical configuration (prescaler = 16, clock = 100 MHz), this improves worst-case edge detection from 160 ns to 10 ns - a 16x improvement in synchronization accuracy.

### Process decomposition

Splitting the monolithic process into dedicated processes (6 in RX, 8 in TX) improves readability, testability, and formal verification coverage. Each process can be independently reasoned about and verified against its ISO section.

## Reusable Logic from `can_node_clock` {#sec:reusable-logic}

Despite the bugs, several concepts from the original module were carried forward:

### Prescaler-based TQ generation

The fundamental approach of dividing the system clock into time quanta using a prescaler counter is preserved in both new modules. The original's `clk_div_counter` (1 to `c_bit_quanta_cycles`) maps directly to `prescaler_count` (0 to `gc_prescaler - 1`) in the new modules. The only difference is that the RX prescaler is restartable.

### Phase error calculation and SJW capping

The original module's approach to computing phase error and capping it at SJW (lines 145-148 for positive error, lines 183-188 for negative error) is conceptually correct and was adapted for `can_pcs_rx`. The new implementation uses the same two-case structure:

- **Positive error** (edge in Prop_Seg or Phase_Seg1): `v_phase_error` computed from segment position, capped at `gc_sjw`, applied as Phase_Seg1 extension.
- **Negative error** (edge in Phase_Seg2): `v_phase_error` computed from remaining TQs, capped at `gc_sjw`, applied as Phase_Seg2 shortening.

### Segment-based state machine concept

The original's 4-state segment FSM (`s_hard_sync`, `s_sync`, `s_seg_1`, `s_seg_2`) was refined into the `can_pcs_rx` 4-state FSM (`s_sync_seg`, `s_prop_seg`, `s_phase_seg1`, `s_phase_seg2`). The key improvement is splitting `s_seg_1` into `s_prop_seg` and `s_phase_seg1` to avoid the boundary computation issues described in @sec:bug-phase1-race.

### Prescaler divisibility assertion

The original module includes an assertion (line 68) that verifies the prescaler divides evenly into the bit quanta period. This defensive check was not carried forward (the new modules parameterize differently), but the principle of compile-time validation of timing parameters is preserved through VHDL generic range constraints.

## Design Strategies Explored {#sec:design-strategies}

The design of the new PCS modules involved exploring several strategies. These are documented in detail in the per-module design space exploration documents (@sec:dse-pcs-tx, @sec:dse-pcs-rx). The key decisions are summarized here.

### Strategy 1: TX/RX separation vs. shared module

The original `can_node_clock` attempted to serve both TX and RX paths but in practice only worked for RX. We considered three options:

1. **Shared parameterized module** - a single entity with generics selecting TX or RX behavior.
2. **Shared base with TX/RX wrappers** - common prescaler and TQ logic, with sync/TDC added by wrapper.
3. **Fully separate modules** - independent `can_pcs_tx` and `can_pcs_rx` entities.

Option 3 was chosen. The TX and RX paths share almost no logic beyond the prescaler counter. The TX needs TDC measurement and SSP generation but no synchronization. The RX needs synchronization and a restartable prescaler but no TDC. Merging them would add unused logic to both paths and complicate the control flow. The separate modules also use different interface records (`t_can_mac_pcs_if_*` for TX, `t_can_mac_pcs_rx_if_*` for RX), making the interface contracts explicit.

### Strategy 2: Flat counter vs. segment FSM (resolved differently per module)

This decision was resolved differently for TX and RX based on their respective requirements:

- **TX:** Flat TQ counter. No resynchronization needed, so segment identity is irrelevant. A single counter with `active_sp` and `active_bit_time` comparisons produces minimal logic.
- **RX:** Explicit segment FSM. The ISO 7.3.5 resynchronization rules depend on which segment an edge falls in. A flat counter would require boundary comparisons that shift dynamically with resync adjustments, reintroducing the class of bugs found in the original module.

### Strategy 3: Clock-cycle vs. TQ-boundary edge detection

Both new modules use clock-cycle edge detection, but for different reasons:

- **TX:** Required for TDC measurement accuracy. The transmitter delay is measured in clock cycles (`delay_count_clk`), not TQs, because the delay is a physical propagation quantity with sub-TQ granularity.
- **RX:** Required for synchronization accuracy. Detecting edges at clock-cycle resolution minimizes the synchronization error to one clock period instead of one TQ.

### Strategy 4: Transient offset vs. persistent modification for resync

The original module's approach of persistently modifying `phase_seg1_length` and `phase_seg2_length` was replaced with transient additive offsets (`phase1_extension`, `phase2_shortening`). This strategy eliminates the signal/variable timing hazards and the accumulation risk. Both offsets are bounded by `gc_sjw` and cleared at each bit boundary, ensuring that no resync adjustment persists beyond the current bit.

### Strategy 5: MAC-driven synchronization mode

Rather than having the PCS infer protocol state (bus idle, IFS, FDF-to-res transition) to decide between hard sync and resync, the MAC FSM communicates synchronization mode via a single-bit `hard_sync_en` signal. This keeps protocol knowledge in the MAC layer and timing knowledge in the PCS layer, following the ISO 11898-1 layered architecture.

## Summary

@tbl:summary provides a concise comparison of the three modules across the dimensions discussed in this document.

| Dimension | `can_node_clock` | `can_pcs_tx` | `can_pcs_rx` |
|-----------|-----------------|-------------|-------------|
| CAN standard | Classic only | Classic + FD | Classic + FD |
| ISO 7.3.5 rules a-d | 2 of 4 | N/A (transmitter) | 4 of 4 |
| Bugs identified | 8 (B1-B8) | - | - |
| Bus-off recovery | No | Yes | Yes |
| TDC / SSP | No | Yes | No |
| Edge resolution | TQ (up to 160 ns) | Clock cycle | Clock cycle |
| Process architecture | Monolithic | 8 processes | 6 processes |
| MAC integration | Standalone | Record-based | Record-based |

: Summary comparison. {#tbl:summary}

The new modules address all eight bugs identified in the original, add CAN FD dual-rate support with TDC, enforce all four ISO 7.3.5.1 synchronization rules, and integrate cleanly with the MAC and FCE layers through typed record interfaces. The original module's core concepts - prescaler-based TQ generation, phase error calculation, and SJW bounding - were preserved and refined in the new implementation.
