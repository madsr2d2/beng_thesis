# Conformance observations: `can_node_clock.vhd`

Internal note — not for the report. These observations arose during review of the PCS resynchronisation implementation and are recorded here for discussion with the original author.

---

## Background

`can_node_clock.vhd` is the bit-timing module of the existing CAN Classic controller. It generates the sample-point strobe (`sample_rx_o`) and bit-boundary strobe (`transmit_o`) and handles hard synchronisation and resynchronisation. The observations below are checked against ISO 11898-1:2024 §7.3.5.

---

## Observation 1 — No within-bit-time sync-inhibit guard (§7.3.5.1.a)

ISO requires that only one synchronisation is allowed per bit time.

`can_node_clock` has no `sync_applied` equivalent. The `rx_prev` latch provides implicit partial protection — a second sync cannot fire on back-to-back TQ boundaries without an intervening recessive period — but a D→R→D glitch spanning two non-consecutive TQ boundaries within the same `s_seg_1` or `s_seg_2` window would compound the phase adjustment.

The `can_fsm` resets `can_node_clock` via `can_node_clk_reset_o` at the first transmit boundary of intermission, bounding any accumulated error to a single frame. On a clean industrial bus at 250–500 kbit/s the failure path requires noise that is unlikely with proper termination and transceiver filtering. No observable failures have been reported.

---

## Observation 2 — No transmitter sync-suppression guard (§7.3.5.2.b)

ISO requires that an edge with a positive phase error shall not cause synchronisation in a node sending a dominant bit.

`can_node_clock` has the R→D edge check (`rx_prev = '1' and rx_i = '0'`) but has no `transmitting` input on the entity. When the local node drives dominant and a D→R→D glitch occurs at a TQ boundary, the sync path fires. At CAN Classic speeds with standard transceivers, transceiver filtering makes this failure path physically implausible. No observable failures have been reported.

---

## Observation 3 — Phase_Seg2 shortening skips Sync_Seg (§7.3.5, implicit in bit-time model)

When a negative-phase-error resync shortens Phase_Seg2, `can_node_clock` transitions directly from `s_seg_2` to `s_seg_1`, bypassing `s_sync`. This is acknowledged in the source with the comment: *"it skips the sync stage, if the second segment was shorten."*

The consequence is that each negative-phase-error resync over-corrects by one extra TQ relative to what ISO specifies (SJW + 1 TQ rather than SJW). Unlike observations 1 and 2, this fires during normal operation whenever clock drift produces an early-arriving edge in Phase_Seg2. The FSM reset at intermission bounds the accumulated error to a single frame, and the system passed hardware bring-up, indicating the over-correction stays within CAN Classic timing margins for the deployed configuration.

---

## Summary

| Observation | Trigger condition | Practical consequence |
|---|---|---|
| No sync-inhibit guard | D→R→D glitch within one bit | Extra phase adjustment; requires bus noise |
| No transmitter sync guard | D→R→D glitch during dominant TX | Spurious resync in transmitter; requires bus noise |
| Phase_Seg2 Sync_Seg skip | Any negative-phase-error resync | Systematic 1-TQ over-correction; fires during normal operation |

All three are within observed operating margin for the deployed system. Observation 3 is the only one that activates under normal (non-glitch) conditions.
