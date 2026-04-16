# Bug Report: `can_node_clock.vhd` {#sec:can-node-clock-bugs}

**File:** `can_bus_controller/hdl_src/can_node_clock.vhd`
**Revisions:** TRIT-3880 (2025-04-24), TRIT-4042 (2025-08-08)
**Context:** Original CAN Classic bit timing module from the company's earlier CAN controller. This module mixed TX and RX bit timing into a single entity and was used as the sole clock source for both paths. It was superseded by the separated `can_pcs_tx` and `can_pcs_rx` modules in the CAN-FD redesign.

---

## BUG-1: Edge detection limited to TQ-boundary resolution {#sec:bug-edge-resolution}

**Location:** Lines 99-101
**Severity:** Medium - reduces synchronization accuracy by up to one TQ

The `rx_prev` signal, used for recessive-to-dominant edge detection, is only updated when the prescaler wraps (`clk_div_counter = c_bit_quanta_cycles`). This means edges occurring between TQ boundaries are not detected until the next TQ tick. The resulting synchronization error can be up to `gc_prescaler - 1` clock cycles.

```vhdl
-- BUG: rx_prev only updated at TQ boundary, not every clock cycle
if (clk_div_counter = c_bit_quanta_cycles) then
  clk_div_counter <= 1;
  rx_prev         <= rx_i;  -- Edge detection delayed by up to 1 TQ
```

ISO 11898-1:2015, Section 7.3.5.1 states that edges are detected at time-quantum granularity, but the standard also notes (NOTE 1) that the bus comparator operates independently from the node clock and the synchronization of data signals to the node clock is part of the CAN node's input delay time. A clock-cycle resolution edge detector minimizes this input delay and improves the accuracy of the phase error measurement, especially at higher prescaler values.

**Fix in `can_pcs_rx`:** The `p_edge_detect` process registers `rx_bus_i` into `rx_bus_prev` on every rising clock edge, and the `edge_detected` guard predicate evaluates at full clock rate.

---

## BUG-2: Phase_Seg1 lengthening race condition {#sec:bug-phase1-race}

**Location:** Lines 141-167 (`s_seg_1` state)
**Severity:** High - can cause incorrect sample point placement

The resynchronization logic in `s_seg_1` uses a mix of variables and signals that creates a timing hazard. When an edge is detected, the code:

1. Reads `phase_seg1_length` (signal) into `v_phase_seg1_length` (variable) at line 142.
2. Computes a new extended length and assigns it back to both the variable and the signal (lines 150-157).
3. On the same TQ tick, uses the variable to compute the sample point comparison at line 161.
4. Also resets `phase_seg1_length` back to the default at line 166 if the sample point fires.

```vhdl
v_phase_seg1_length := phase_seg1_length;         -- (1) Read signal into variable

if (rx_i = '0') and (rx_prev = '1') then
  v_phase_error := time_quantum_count + 1;
  -- ...
  v_phase_seg1_length := phase_seg1_length + v_phase_error;  -- (2) Extend variable
  phase_seg1_length <= v_phase_seg1_length;                  -- (2) Write signal (takes effect next delta)
end if;

time_quantum_count  <= time_quantum_count + 1;
v_phase_seg1_length := (gc_default_prop_seg_length + v_phase_seg1_length) - 1; -- (3) Recompute with variable
if time_quantum_count = v_phase_seg1_length then
  -- ...
  phase_seg1_length  <= gc_default_phase_seg_1_length;  -- (4) Reset signal
end if;
```

The problem is that step (2) assigns `phase_seg1_length` via `<=` (signal assignment, takes effect at end of delta cycle), but step (4) can also assign `phase_seg1_length` in the same clock cycle if the sample point happens to coincide with the edge. When both assignments exist in the same process cycle, only the last sequential assignment wins. If the edge arrives on the exact TQ where the sample point would have fired, the extension is overwritten by the reset at step (4), and the sample point fires at the wrong position.

The variable `v_phase_seg1_length` partially masks this issue by carrying the extended value within the same delta cycle, but the signal `phase_seg1_length` - which persists across clock edges and is read at step (1) of the next bit - ends up with the default value instead of the extended value.

**Fix in `can_pcs_rx`:** The extension is stored in a separate `phase1_extension` signal (range 0 to `gc_sjw`). The segment FSM adds this to the `active_phase_seg1` comparison in `s_phase_seg1`. The extension and the segment counter are independent signals with no variable intermediaries, eliminating the race.

---

## BUG-3: Phase_Seg2 shortening skip logic is inverted {#sec:bug-phase2-skip}

**Location:** Lines 200-208 (`s_seg_2` state)
**Severity:** Medium - incorrect Sync_Seg skip after Phase_Seg2 shortening

After Phase_Seg2 ends, the code decides whether to skip the Sync_Seg of the next bit. The intent is: if Phase_Seg2 was shortened (resynchronization occurred), skip Sync_Seg because the edge that caused resynchronization already serves as the synchronization point. However, the comparison is inverted:

```vhdl
if (v_phase_seg2_length /= (gc_default_phase_seg_2_length - 1)) then
  segment <= s_seg_1;  -- Skip sync
end if;
```

The variable `v_phase_seg2_length` has already been decremented by 1 at line 199 (`v_phase_seg2_length := v_phase_seg2_length - 1`), so its value when Phase_Seg2 was *not* shortened equals `gc_default_phase_seg_2_length - 1`. The condition `v_phase_seg2_length /= (gc_default_phase_seg_2_length - 1)` is therefore true when shortening *did* occur - which appears correct at first glance. But this logic also triggers when `phase_seg2_length` has been persistently modified by a previous resynchronization (since the signal retains the shortened value until reset at line 204). In that case, even a bit without a new edge will have `v_phase_seg2_length /= default - 1`, causing spurious Sync_Seg skips.

**Fix in `can_pcs_rx`:** The segment FSM always transitions `s_phase_seg2` -> `s_sync_seg` at the bit boundary. Sync_Seg is always 1 TQ per ISO 7.3.2 and is never skipped. Hard synchronization restarts the bit time by jumping to `s_sync_seg` directly, which is the ISO-defined behavior (ISO 7.3.5.3: "the bit time shall be restarted with Sync_Seg completed").

---

## BUG-4: No ISO 7.3.5.1 rule a/b enforcement {#sec:bug-no-sync-guard}

**Location:** Entire process (lines 78-220)
**Severity:** High - allows multiple synchronizations per bit time

The original module does not implement the two fundamental synchronization guards from ISO 7.3.5.1:

- **Rule a)** Only one synchronization within one bit time (between two sample points) shall be allowed.
- **Rule b)** An edge shall cause synchronization only if the bus state detected at the previous sample point was recessive.

There is no `sync_inhibit` flag or equivalent mechanism. Every recessive-to-dominant edge detected at a TQ boundary triggers resynchronization, even if a synchronization has already occurred in the current bit or if the previous sample point read dominant.

In a noisy bus environment, this can cause multiple resynchronizations within a single bit time, leading to incorrect sample point placement and potential frame reception errors.

**Fix in `can_pcs_rx`:** The `sync_inhibit` boolean signal is set when a synchronization occurs and cleared at each bit boundary. The `sampled_polarity` signal latches the bus value at the sample point. Both must be checked before any synchronization is applied: `v_sync_allowed := edge_detected and not sync_inhibit and sampled_polarity = c_recessive`.

---

## BUG-5: Persistent phase segment length modification {#sec:bug-persistent-phase}

**Location:** Lines 154-157, 192-195
**Severity:** Medium - accumulated drift across bits

When resynchronization occurs, the code modifies `phase_seg1_length` or `phase_seg2_length` as persistent signals. These signals are only reset to defaults at the bit boundary (lines 166, 204), but in a specific case the reset can be missed.

In `s_seg_1`, `phase_seg1_length` is reset at line 166 only when the sample point fires (`time_quantum_count = v_phase_seg1_length`). If Phase_Seg1 was extended but the bit is cut short by a hard synchronization before the sample point is reached, the extended value persists into the next bit.

Similarly, in `s_seg_2`, `phase_seg2_length` is reset at line 204 only at the bit boundary. A hard synchronization during Phase_Seg2 jumps back to `s_seg_1` or `s_sync` without clearing the shortened value.

**Fix in `can_pcs_rx`:** The `phase1_extension` and `phase2_shortening` signals are transient adjustments (range 0 to `gc_sjw`) that are added/subtracted from the active segment lengths. They are explicitly cleared on every bit boundary transition and on every hard sync restart, making the base segment lengths immutable constants derived from generics.

---

## BUG-6: No CAN FD data-rate switching support {#sec:bug-no-fd}

**Location:** Entity generics and architecture
**Severity:** Architectural limitation

The module only supports a single set of bit timing parameters (nominal rate). There is no mechanism to switch between nominal and data bit timing, which is required for CAN FD frames where the BRS bit triggers a transition to the data-phase bit rate for the ESI, DLC, Data, SBC, and CRC fields (ISO 11898-1:2015, Section 6.6.11.3).

This is not a bug per se but an architectural limitation that prevents the module from being used in a CAN FD controller.

**Fix in `can_pcs_rx`:** The module accepts both nominal (`gc_nom_*`) and data (`gc_data_*`) segment generics. A `t_rate_state` FSM (`s_nominal`/`s_data`) switches the active segment lengths at bit boundaries based on the `mac_i.use_data_rate` signal from the MAC RX FSM.

---

## BUG-7: Mixed TX/RX concerns in a single entity {#sec:bug-mixed-tx-rx}

**Location:** Entity ports, entire process
**Severity:** Architectural - prevents independent TX/RX PCS optimization

The module generates both `sample_rx_o` (RX sample point) and `transmit_o` (TX bit boundary) from the same process and the same bit time counter. The `transmit_o` output is annotated "not used in this module" at lines 39, 89, 96, and 123, yet it is still generated and driven.

Combining TX and RX timing in a single entity means:

- The TX path cannot use a free-running prescaler (which is simpler and sufficient since the transmitter does not need synchronization).
- The RX synchronization logic affects the TX bit boundary timing.
- TDC (Transmitter Delay Compensation) cannot be implemented because the module has no concept of separate TX/RX timing domains.

**Fix in the CAN-FD redesign:** The TX and RX PCS are fully separate entities (`can_pcs_tx` and `can_pcs_rx`) with independent prescalers, counters, and state machines. The TX PCS uses a free-running prescaler and supports TDC/SSP. The RX PCS uses a restartable prescaler and supports hard sync/resync.
