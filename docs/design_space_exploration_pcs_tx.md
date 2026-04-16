# Design Space Exploration: `can_pcs_tx` {#sec:dse-pcs-tx}

**Module:** `src/can_pcs_tx/hdl_src/can_pcs_tx.vhd`
**Standard:** ISO 11898-1:2015, Sections 7.2, 7.3.2, 7.3.4

## Purpose

The transmitter-side Physical Coding Sub-layer converts MAC output units into timed bus symbols. It is responsible for bit timing generation, TX bus driving, sample point (SP) and secondary sample point (SSP) strobe generation, and Transmitter Delay Compensation (TDC) measurement. Unlike the receiver PCS, the transmitter does not perform synchronization - it is the timing master that all receivers synchronize to.

## Design Decisions

### D1: Free-running prescaler vs. restartable prescaler

| Option | Description | Trade-off |
|--------|-------------|-----------|
| **Free-running** | Prescaler counts continuously, never restarted | Simpler, deterministic timing, no glitches |
| Restartable | Prescaler can be reset by external events | Needed for resynchronization (RX only) |

**Decision:** Free-running prescaler. The transmitter defines the bit timing reference for all nodes on the bus. Restarting the prescaler would introduce timing perturbations that propagate to all receivers. The prescaler wraps at `gc_prescaler - 1` independently of any other signal.

### D2: Flat TQ counter vs. segment state machine

| Option | Description | Trade-off |
|--------|-------------|-----------|
| **Flat TQ counter** | Single counter 0..bit_time-1, SP derived by comparison | Fewer states, simpler; segment identity is implicit |
| Segment FSM | Explicit states for Sync_Seg, Prop_Seg, Phase_Seg1, Phase_Seg2 | More readable, but more transitions for the same function |

**Decision:** Flat TQ counter (`tq_count`). The TX PCS does not need to distinguish segments for synchronization decisions (no resync logic). A single counter with comparisons against `active_sp` and `active_bit_time` is sufficient and produces less logic. The sample point fires at `tq_count = active_sp - 1`, and the bit boundary fires at `tq_count = active_bit_time - 1`.

This decision differs from `can_pcs_rx`, which uses an explicit segment FSM because the resynchronization rules depend on knowing which segment the edge falls in (see @sec:dse-pcs-rx).

### D3: Rate switching FSM - 3-state vs. 2-state

| Option | Description | Trade-off |
|--------|-------------|-----------|
| **3-state (s_nominal, s_measuring, s_data)** | Intermediate state for TDC measurement | Allows one-bit delay for TDC measurement before data rate takes effect |
| 2-state (s_nominal, s_data) | Direct switch at bit boundary | Simpler, but no TDC measurement window |

**Decision:** 3-state FSM. The ISO 7.3.4 TDC measurement requires observing the transmitter delay between the TX dominant edge and the corresponding RX dominant edge. This measurement must happen at the data bit rate but before the SSP can be used. The `s_measuring` state provides exactly one data-rate bit time for this measurement. The transition path is `s_nominal` -> `s_measuring` (when `mac_i.use_data_rate = '1'`) -> `s_data` (next bit boundary). The `s_data` -> `s_nominal` transition is direct since no teardown is needed.

### D4: TDC measurement - clock-domain vs. TQ-domain counting

| Option | Description | Trade-off |
|--------|-------------|-----------|
| **Clock-domain counting** | Count `delay_count_clk` in system clock cycles, convert to TQs | Higher resolution, needed when prescaler > 1 |
| TQ-domain counting | Count delay in TQs directly | Simpler, but resolution limited to prescaler granularity |

**Decision:** Clock-domain counting with TQ conversion. The transmitter delay is a physical propagation delay measured in nanoseconds, not in TQs. Counting in clock cycles and converting with ceiling division (`(delay_count_clk + gc_prescaler - 1) / gc_prescaler`) preserves sub-TQ resolution. The TDC is gated by `c_use_tdc`, which requires `gc_prescaler <= 2` per ISO 7.3.4 recommendations, but the clock-domain approach works correctly at any prescaler value.

### D5: SSP position calculation

| Option | Description | Trade-off |
|--------|-------------|-----------|
| **Modular position with standoff delay** | `ssp_position = (delay_tq + ssp_offset) mod data_bit_time`, with standoff counter for multi-bit delays | Handles arbitrarily long transmitter delays |
| Fixed offset from SP | `ssp_position = sp_position + offset` | Simpler, but fails when delay exceeds one bit time |

**Decision:** Modular position with standoff. The SSP may fall several data-phase bit times after the transmitted bit, especially at high data rates with long transceiver delays. The `ssp_position` gives the TQ position within a bit time, and `tdc_delay` gives the number of whole bit times to wait before the SSP becomes active. The `p_ssp_standoff` process counts down `tdc_delay` bit boundaries before enabling the SSP strobe generation in `p_ssp`.

### D6: TX bus output timing - bit boundary vs. Sync_Seg

| Option | Description | Trade-off |
|--------|-------------|-----------|
| **Bit boundary** | Latch `mac_i.polarity` at `tq_count = active_bit_time - 1` | Output changes at the start of the new bit (Sync_Seg), aligning with the ISO-defined bit boundary |
| Sync_Seg start | Latch at `tq_count = 0` | One TQ late - the bus would still show the previous bit's polarity during Sync_Seg |

**Decision:** Bit boundary. The MAC presents the next bit's polarity before the bit boundary. Latching at the last TQ of the current bit means `tx_bus_o` changes at the first clock edge of the new Sync_Seg, which is when receivers expect the transition. This aligns with ISO 7.3.2, where the Sync_Seg is defined as the segment "used to synchronize the various nodes on the bus."

### D7: Bus-off behavior

| Option | Description | Trade-off |
|--------|-------------|-----------|
| **Hold recessive + idle counting** | Drive `tx_bus_o = c_recessive`, count 11-recessive-bit sequences at SP, pulse `idle_condition` | Matches ISO 8.1.4.4 bus-off recovery: 128 occurrences of 11 consecutive recessive bits |
| Disable output entirely | Tri-state or hold recessive, no counting | Simpler but requires external idle detection |

**Decision:** Hold recessive with idle counting. The PCS is the natural place for idle condition detection since it already has the sample point infrastructure. During `fce_i.bus_off = '1'`, the SP strobe is suppressed (MAC does not receive bits), and a `recessive_counter` counts consecutive recessive samples. At 11, `fce_o.idle_condition` pulses once. The FCE counts 128 such pulses for bus-off recovery.

## Process Decomposition

| Process | Responsibility | Sensitivity |
|---------|---------------|-------------|
| `p_prescaler_counter` | Clock divider: 0..`gc_prescaler-1` | `clk_i` |
| `p_tq_counter` | TQ counter + TX bus output | `clk_i`, gated by `tq_tick` |
| `p_sample_point` | SP strobe + bus-off idle counting | `clk_i`, gated by `tq_tick` |
| `p_ssp_standoff` | SSP activation delay counter | `clk_i`, gated by `bit_boundary` |
| `p_ssp` | SSP strobe generation | `clk_i`, gated by `tq_tick` |
| `p_bus_polarity` | Register `rx_bus_i` -> `mac_o.bus_polarity` | `clk_i` |
| `p_tdc` | TDC delay measurement (clock-domain) | `clk_i` |
| `p_fsm` | Rate switching FSM (3-state) | `clk_i`, gated by `bit_boundary` |

: Process decomposition for `can_pcs_tx`. {#tbl:pcs-tx-processes}

## Interface Rationale

The TX PCS uses the shared `t_can_mac_pcs_if_m2s` / `t_can_mac_pcs_if_s2m` interface records. These include TX-specific fields (`start_tdc`, `secondary_sample_point`, `tdc_delay`) that are not relevant on the RX side. The RX PCS uses separate RX-specific records (see @sec:dse-pcs-rx) to avoid carrying unused fields.
