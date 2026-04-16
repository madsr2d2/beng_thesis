# Design Space Exploration: `can_pcs_rx` {#sec:dse-pcs-rx}

**Module:** `src/can_pcs_rx/hdl_src/can_pcs_rx.vhd`
**Standard:** ISO 11898-1:2015, Sections 7.2, 7.3.2, 7.3.5

## Purpose

The receiver-side Physical Coding Sub-layer synchronizes the local bit timing to the transmitting node by detecting recessive-to-dominant edges on `rx_bus_i` and adjusting the bit time counter accordingly. It generates sample point strobes for the MAC RX FSM and drives `tx_bus_o` for ACK and error/overload flag transmission. An earlier implementation (`can_node_clock.vhd`) mixed TX and RX timing in a single entity; the bugs found in that module (@sec:can-node-clock-bugs) directly motivated several design decisions documented here.

## Design Decisions

### D1: Restartable prescaler vs. free-running prescaler

| Option | Description | Trade-off |
|--------|-------------|-----------|
| **Restartable** | Prescaler resets to 0 on hard sync and small-phase-error resync | Aligns TQ grid to detected edge, required for ISO 7.3.5.3 |
| Free-running | Prescaler wraps independently | Simpler, but synchronization can only adjust at TQ boundaries |

**Decision:** Restartable prescaler. Hard synchronization per ISO 7.3.5.3 requires that "the bit time shall be restarted with Sync_Seg completed." Restarting the prescaler realigns the entire TQ grid to the detected edge. Without this, the phase error introduced by a free-running prescaler (up to `gc_prescaler - 1` clock cycles) would persist until the next TQ boundary.

The `prescaler_restart` signal is set by `p_bit_timing` and consumed by `p_prescaler` in the same clock cycle, ensuring the prescaler is zeroed synchronously.

This contrasts with the TX PCS (@sec:dse-pcs-tx, D1), which uses a free-running prescaler because the transmitter does not synchronize.

### D2: Segment state machine vs. flat TQ counter

| Option | Description | Trade-off |
|--------|-------------|-----------|
| **Segment FSM** | Explicit `t_segment` states: `s_sync_seg`, `s_prop_seg`, `s_phase_seg1`, `s_phase_seg2` | Resync rules map directly to segment identity; clearer, less error-prone |
| Flat TQ counter | Single counter, segment derived by range comparison | Fewer signals, but phase error sign must be inferred from counter position |

**Decision:** Segment state machine. The ISO 7.3.5 resynchronization rules depend on which segment the detected edge falls in:

- Edge in Sync_Seg (e = 0): no adjustment needed (ISO 7.3.5.2).
- Edge in Prop_Seg or Phase_Seg1 (e > 0): lengthen Phase_Seg1 (ISO 7.3.5.4).
- Edge in Phase_Seg2 (e < 0): shorten Phase_Seg2 (ISO 7.3.5.4).

With a flat counter, determining the segment requires comparison against accumulating boundary values (sync end, prop end, phase1 end). These boundaries shift dynamically when resync adjustments are applied, making the comparisons fragile and hard to reason about (see @sec:bug-phase1-race for a concrete example of this going wrong). An explicit state machine eliminates this class of bugs: the segment identity is always known, and the `seg_count` tracks position within the current segment only.

The TX PCS uses a flat counter (D2 in @sec:dse-pcs-tx) because it has no resynchronization logic.

### D3: Clock-cycle edge detection vs. TQ-boundary edge detection

| Option | Description | Trade-off |
|--------|-------------|-----------|
| **Clock-cycle resolution** | `rx_bus_prev` updated every `rising_edge(clk_i)` | Maximum accuracy, detects edges between TQ boundaries |
| TQ-boundary resolution | `rx_prev` updated only at prescaler wrap | Simpler, but up to 1 TQ of undetected latency |

**Decision:** Clock-cycle resolution. The original `can_node_clock.vhd` used TQ-boundary edge detection (@sec:bug-edge-resolution), which introduced up to one full TQ of synchronization error. At `gc_prescaler = 16` with a 100 MHz clock, this is 160 ns of undetected latency. With clock-cycle detection, the worst-case latency is one clock period (10 ns at 100 MHz).

The `edge_detected` combinational guard evaluates `rx_bus_prev` (registered every clock) against `rx_bus_i` (current value), detecting edges at the earliest possible moment.

### D4: Synchronization mode signaling - MAC-driven vs. PCS-inferred

| Option | Description | Trade-off |
|--------|-------------|-----------|
| **MAC-driven `hard_sync_en`** | MAC FSM tells PCS whether to use hard sync or resync via a single-bit signal | Clean separation: protocol knowledge stays in MAC, timing logic in PCS |
| PCS-inferred | PCS detects bus idle / IFS patterns internally | Duplicates protocol state tracking, violates layering |
| No distinction | Always resync, never hard sync | Violates ISO 7.3.5.1 rule c |

**Decision:** MAC-driven `hard_sync_en`. The conditions for hard synchronization (ISO 7.3.5.1 rule c) depend on the MAC protocol state: bus integration, inter-frame space, and the FDF-to-res transition. The PCS has no visibility into frame-level protocol state. Adding frame tracking to the PCS would duplicate the MAC FSM and create a maintenance burden.

The `hard_sync_en` bit is the minimal correct interface. When high, any qualifying edge triggers hard sync (prescaler + segment counter restart). When low, edges trigger resynchronization with SJW-bounded phase adjustment.

### D5: Phase_Seg1 extension mechanism - additive offset vs. persistent length modification

| Option | Description | Trade-off |
|--------|-------------|-----------|
| **Additive offset (`phase1_extension`)** | Transient signal added to `active_phase_seg1` for current bit only | No accumulation, no race conditions, cleared at bit boundary |
| Persistent length modification | Modify `phase_seg1_length` signal directly | Simpler concept, but creates race conditions when edge and SP coincide |

**Decision:** Additive offset. The original `can_node_clock.vhd` modified `phase_seg1_length` persistently, creating a race condition (@sec:bug-phase1-race) and accumulation risk (@sec:bug-persistent-phase). The additive approach keeps the base segment lengths as immutable constants derived from generics. `phase1_extension` (range 0 to `gc_sjw`) is set when resync lengthening is needed and cleared at the next bit boundary or hard sync restart.

The same principle applies to `phase2_shortening` for Phase_Seg2 truncation.

### D6: Sync inhibit clearing - bit boundary vs. sample point

| Option | Description | Trade-off |
|--------|-------------|-----------|
| **Bit boundary** | `sync_inhibit` cleared when segment FSM returns to `s_sync_seg` | One sync per bit time, matches ISO 7.3.5.1 rule a |
| Sample point | Clear at SP when bus reads recessive | More permissive: allows sync in Phase_Seg2 of the same bit if SP was recessive |

**Decision:** Bit boundary clearing. ISO 7.3.5.1 rule a states "only one synchronization within one bit time (between two sample points) shall be allowed." Clearing at the bit boundary enforces exactly this: once `sync_inhibit` is set, no further synchronization occurs until the current bit ends. The rule b guard (`sampled_polarity = c_recessive`) separately ensures that the previous SP read recessive.

### D7: Rate switching FSM - 2-state vs. 3-state

| Option | Description | Trade-off |
|--------|-------------|-----------|
| **2-state (s_nominal, s_data)** | Direct switch at bit boundary | Sufficient for RX: no TDC measurement needed |
| 3-state (s_nominal, s_measuring, s_data) | Intermediate measurement state | Only needed for TX TDC; see @sec:dse-pcs-tx, D3 |

**Decision:** 2-state FSM. The RX PCS does not perform TDC measurement (that is a transmitter concern). When the MAC RX FSM asserts `use_data_rate` after receiving a BRS=1 bit, the rate switch takes effect at the next bit boundary. The switch is immediate: `s_nominal` -> `s_data`. No measurement delay is needed.

This contrasts with the TX PCS, which requires a 3-state FSM with an intermediate `s_measuring` state for TDC.

### D8: RX-specific interface records vs. reusing TX interface records

| Option | Description | Trade-off |
|--------|-------------|-----------|
| **RX-specific records** | `t_can_mac_pcs_rx_if_m2s` with `hard_sync_en`, without `start_tdc`; `t_can_mac_pcs_rx_if_s2m` without `secondary_sample_point` and `tdc_delay` | Clean interface, no unused fields, self-documenting |
| Reuse TX records | Tie unused fields to defaults | Fewer types, but unused fields obscure the actual interface contract |

**Decision:** RX-specific records. The TX and RX PCS modules serve fundamentally different roles. Reusing the TX interface would leave `start_tdc`, `secondary_sample_point`, and `tdc_delay` as dead fields on the RX side, and would lack the `hard_sync_en` field that the RX path needs. Separate records make the interface contract explicit in the type system.

### D9: TX bus output from RX PCS

| Option | Description | Trade-off |
|--------|-------------|-----------|
| **Driven from RX PCS at bit boundary** | `tx_bus_o` latches `mac_i.polarity` at each Phase_Seg2 end | RX PCS owns the receiver's bit timing; ACK/error flags must be aligned to it |
| Driven from MAC directly | MAC drives `tx_bus_o` without PCS timing | Timing not aligned to bit boundaries, could violate bit timing constraints |

**Decision:** Driven from RX PCS. When the receiver sends an ACK slot or error/overload flag, the polarity must be driven at the correct bit boundary as seen by the receiver's local clock. Since the RX PCS owns this clock, it is the natural place to latch `mac_i.polarity` onto `tx_bus_o`. During bus-off, the output is held recessive per ISO 8.1.3.4.

## Process Decomposition

| Process | Responsibility | Key signals |
|---------|---------------|-------------|
| `p_edge_detect` | Register `rx_bus_i`, drive `mac_o.bus_polarity` | `rx_bus_prev`, `edge_detected` |
| `p_prescaler` | Restartable clock divider: 0..`gc_prescaler-1` | `prescaler_count`, `prescaler_restart` |
| `p_bit_timing` | Segment FSM + synchronization logic (ISO 7.3.5) | `segment`, `seg_count`, `sync_inhibit`, `phase1_extension`, `phase2_shortening` |
| `p_sample_point` | SP strobe + `sampled_polarity` latch + bus-off idle counting | `mac_o.sample_point`, `sampled_polarity`, `recessive_counter` |
| `p_tx_output` | ACK/error flag bus driver at bit boundary | `tx_bus_o` |
| `p_rate_switch` | 2-state nominal/data rate FSM | `rate_state` |

: Process decomposition for `can_pcs_rx`. {#tbl:pcs-rx-processes}

## Comparison with `can_pcs_tx`

| Aspect | `can_pcs_tx` | `can_pcs_rx` |
|--------|-------------|-------------|
| Prescaler | Free-running | Restartable |
| Bit time tracking | Flat TQ counter | Segment state machine |
| Synchronization | None (timing master) | Hard sync + resync (ISO 7.3.5) |
| Edge detection | TX/RX edge for TDC only | RX edge at clock resolution |
| Rate FSM | 3-state (with TDC measurement) | 2-state (no TDC) |
| TDC/SSP | Yes (ISO 7.3.4) | No (receiver does not need TDC) |
| Interface records | `t_can_mac_pcs_if_m2s/s2m` | `t_can_mac_pcs_rx_if_m2s/s2m` |
| SJW generic | No | Yes (`gc_sjw`) |
| TX bus output | Drives transmitted frame bits | Drives ACK/error flags only |

: Feature comparison between TX and RX PCS modules. {#tbl:pcs-comparison}
