# Content Brief: Split vs Unified FSM - Slide 5

Produced by a `/grill-with-docs` session. All claims verified against `git log`, FSM source code, and testbench source.

**Slide title:** "Unified FSM: split tried and abandoned"
**Audience:** DTU Compute examiner, digital design background.
**Time budget:** ~90 seconds.

---

## PART 1: Slide Agent Instructions

*Read this section first. The background account and full bug details are in Part 2.*

---

### Slide structure

The slide makes **two distinct arguments**. Both must be present. Neither is subordinate to the other.

**Point 1 - Implementation drift**
The TX and RX FSMs were developed sequentially, months apart. Every SP-granularity protocol boundary was defined twice, independently, and came out slightly different. Eight bugs resulted. Debugging required cross-correlating two independent waveform sets per bug.

**Point 2 - Verification methodology weakness**
Each single-path TB tested against a synthetic perfect partner using `build_bus_stream` as both test and benchmark. A passing test gave confidence in the reference model, not in the RTL. The unified approach replaces this: a passing test means a second independent CAN implementation agreed with the first - which is precisely what the protocol is supposed to guarantee.

---

### Slide-ready language

**Point 1:**
- "TX FSM stable February 2026. RX added as stubs March 31. Two weeks of parallel development produced eight timing divergences."
- "Each SP-granularity boundary was defined twice, independently, and came out slightly different."

**Point 2:**
- "Split-path tests verified the RTL agreed with the reference model. Unified-path tests verify that a second independent CAN implementation agrees with the first."

---

### Three bug examples to use

Use exactly these three as concrete evidence. Do not list all eight on the slide - the full list is in Part 2 as spoken backup.

**Bug A+C - SOF timing divergence** *(serves Point 1 - drift)*
TX and RX FSMs made structurally different choices for the same protocol event (SOF). TX used `s_sof` as a setup cycle; RX detected SOF directly in `s_idle` without an SP guard. One structural decision made differently twice produced two bugs: TX drove SOF dominant for two bit times, RX was one SP behind in all subsequent CRC feeds. Neither was caught in isolation because the TX TB's PCS VC started checking one bit late (valid=0 during the first SOF bit time) and the RX TB had only 8 assertions.

**Bug E - in_data_phase off by 1 SP** *(serves Point 1 - drift)*
TX FSM cleared `in_data_phase` one SP too early at the CRC/delimiter boundary. The same protocol boundary, defined independently in the TX FSM, came out slightly wrong. Only triggered after ~265 FD frames on specific CRC bit patterns - the definition of silent drift. Invisible in isolation because the TX TB used zero-delay loopback before April 10, and after that the TB was not run at sufficient frame counts.

**Bug D - ACK window too narrow** *(serves Point 2 - methodology)*
TX FSM `v_in_ack_slot` did not cover `s_ack_delimiter`. With realistic transceiver delay (300-750 ns), a receiver's dominant ACK arrives late, landing at the delimiter SP and triggering a false bit error. The TX TB used zero-delay loopback - ACK always arrived at `s_ack`, never delayed. Structurally impossible to trigger in the single-path TB regardless of how many frames were run. Only visible in two-node testing with realistic bus delay.

---

### What goes on the slide vs spoken backup

| Content | On slide | Spoken backup |
|---|---|---|
| Split chosen: `side` dimension misread as implementation-facing | Yes | - |
| Timeline: TX Feb, RX stubs Mar 31, two weeks parallel | Yes | - |
| Two BS instances, two CRC instances in hardware | Yes | - |
| Three named bug examples | Yes | Full list of eight |
| Debugging: two waveform sets per bug | Yes | - |
| Verification methodology contrast | Yes - one bullet | Full epistemological account |
| Arbitration-loss continuity | No | "What else does unified give you?" |
| `is_transmitter` mechanism | No | "How does unified FSM partition TX/RX?" |
| `can_bus_controller` precedent | No | "How did you know unified would work?" |
| FSM state count | No | Never cite |

---

### Language constraints

- Do NOT say "the reference model was fundamentally flawed" - reference model verification is legitimate. The specific weakness: model and RTL shared the same implicit timing assumptions, so bugs cancelled out.
- Do NOT say "frame in = frame out is the protocol definition" - it is a necessary condition, not a sufficient one for ISO compliance.
- Do NOT say "19 states" or any FSM state count - invites optimization questions with no rhetorical payoff.
- Do NOT put `is_transmitter` mechanism on this slide - it belongs on the FSM structure slide.
- Do NOT put arbitration-loss continuity on this slide - it is a real payoff but could have been done in the split path too.

---

## PART 2: Background and Reference Material

*Context for the agent to draw on if depth is needed. Not required reading before producing the slide.*

---

### Why the split path was chosen

The verification plan's `side` dimension classifies each requirement as TX-only, RX-only, or both. Many requirements are framed in terms of transmitter or receiver obligations, making separate TX and RX modules appear to be a natural fit. The initial assumption was that aligning RTL structure with this dimension would make requirements trace cleanly to modules, simplifying verification.

This assumption was wrong. The `side` dimension was misread as an implementation-facing dimension - "there are TX requirements and RX requirements, therefore there should be a TX module and an RX module." It is in fact a verification-facing dimension: it tells you how to structure testbenches (which stimulus path exercises TX obligations, which checking path covers RX obligations), not how to partition RTL logic.

The misreading felt natural because the ISO requirements language - "the transmitter shall...", "the receiver shall..." - mirrors module names directly. But that language reflects the spec's perspective on protocol roles, not the RTL's internal structure. The RTL does not care about protocol roles; it cares about shared logic. TX and RX share enough protocol logic that splitting along the `side` seam created more problems than it solved.

This is the "requirements structure is not RTL structure" lesson: verification plan dimensions describe how to assign and test requirements, not how to partition implementation logic.

The `can_bus_controller` company reference implementation - known before the split path was built - uses a unified TX/RX controlling FSM. This precedent gave confidence that consolidating was the right architectural direction and provided the template for the merger.

---

### What the split path looked like

- `can_mac_fsm_tx.vhd` - TX FSM. Stable by February 2026. ~910 lines.
- `can_mac_fsm_rx.vhd` - RX FSM. Added as stubs March 31, 2026. Actively developed April 2026.
- `can_mac_tx.vhd` and `can_mac_rx.vhd` - wrapper modules, each instantiating their own `can_mac_bs` and `can_mac_crc` instance. Same entity code for BS and CRC, but two hardware instances.
- Separate testbenches, waveform configs, and simulation configs for each path.

The TX FSM was built first and was the mature, well-tested implementation. The RX FSM was added months later as a separate implementation of the same underlying protocol logic.

---

### The complete bug list (spoken backup)

Eight concrete divergences emerged across two commits (`5a6319fc` retroactive verification, `24586d9c` unification). All are protocol boundary decisions that had to be made identically in both FSMs. There was no shared specification for these boundaries - each was decided independently and came out slightly different.

*From retroactive split-path verification (`5a6319fc`):*
- **Bug A:** TX FSM held SOF dominant for two bit times instead of one. `s_sof` used as a setup cycle without driving the bus; the SOF drive set in `s_bus_idle` persisted into the ID field.
- **Bug B:** TX FSM `s_bus_idle` SOF trigger path did not override `bs_rst`/`crc_rst`. The quiet-field reset block held the engines in reset on the same cycle the SOF feed was issued. (Part of the A+C story - B is a consequence of the SOF structural divergence.)
- **Bug C:** RX FSM detected SOF without a sample-point guard and had an extra `s_sof` state, putting it one SP behind the TX FSM in all subsequent CRC feeds.
- **Bug D:** TX FSM `v_in_ack_slot` did not cover `s_ack_delimiter`. With realistic transceiver delay (300-750 ns), a receiver's dominant ACK arrives late and lands at the delimiter SP, triggering a false bit error.
- **Bug E:** TX FSM cleared `in_data_phase` one SP too early at the CRC/delimiter boundary, causing false bit-error checks on FD frames with specific CRC bit patterns.

*Additional bugs fixed during unification (`24586d9c`):*
- **Bug F:** `do_hard_sync` and `pcs_o.transmitting` were strobed instead of level-driven.
- **Bug G:** RTR frames did not correctly skip the data field on TX and RX. RX-side bug - the RX TB had no `ftyp` coverage bin and forced `ftyp='0'` for FD frames.
- **Bug H:** `next_bit_is_res` asserted in `s_fdf_r1_r0` instead of `s_res_r0`, causing TDC measurement to start one bit early. Masked because the reference model's `start_tdc` was calibrated to fire at the FDF bit position, matching the buggy FSM.

---

### Why each bug was not caught by the split-path TBs

**Bug A - TX TB structural blind spot.** The PCS VC starts bit-checking when `pcs_o.valid = '1'`. `pcs_o.valid` is first asserted in `s_sof`, not in `s_bus_idle`. The extra SOF dominant bit driven in `s_bus_idle` (valid=0) happens before the check starts. When valid fires in `s_sof`, the reference stream's first entry (SOF dominant) matches the dominant still on the bus. The check started one bit late; the mismatch was never observed.

**Bug B - introduced in late TX FSM changes, TB not rerun.** Likely introduced in April 15-16 TX FSM commits (`48ae46fb`, `93f258d2`), after the last active TX TB run. The merger was executed 12 days later without the TB being rerun.

**Bug C - RX TB coverage too thin.** 8 assertions, "Initial happy-path testbench," started April 5. The 1-SP CRC accumulation offset did not produce frame-level failures across the limited test scenarios.

**Bug D - zero-delay loopback.** TX TB uses `pcs_i.bus_polarity <= pcs_o.polarity`, `tdc_delay <= (others => '0')`. ACK always arrives at `s_ack`. Structurally impossible to trigger with zero bus delay.

**Bug E - zero-delay loopback, then insufficient run count.** Before April 10: zero-delay loopback, false bit-error cannot fire. TDC delay model added April 10. After that, bug fires after ~265 FD frames on specific CRC patterns; development focus had shifted to PCS/FCE and the TX TB was not being run at sufficient frame counts.

**Bug F - signal not checked.** The PCS VC bit-check only verifies `start_tdc`, `use_data_rate`, and `polarity`. `pcs_o.do_hard_sync` is not in the checked set. Invisible by construction.

**Bug G - RX TB coverage omission.** RX TB forces `ftyp='0'` for FD frames and has no `ftyp` coverage bin. RTR reception was never systematically tested on the RX side.

**Bug H - reference model absorbed the bug.** The reference stream fires `start_tdc` at `v_stream.fdf_pos` (FDF bit position). The buggy TX FSM asserted `next_bit_is_res` in `s_fdf_r1_r0` (FDF state), placing `start_tdc` at the FDF bit time. Reference model and FSM agreed. Bug cancelled out.

**Pattern across the eight bugs.** Three distinct failure modes:
1. *Structural TB blind spots*: PCS VC trigger condition (Bug A) and zero-delay loopback (Bugs D, E) made certain bugs physically impossible to observe.
2. *Reference model calibration*: `build_bus_stream` was calibrated to the FSM's implicit timing assumptions. Bugs shared between model and FSM cancelled out (Bug H).
3. *Coverage gaps*: RX TB too immature and too narrow to exercise the relevant frame types and error paths (Bugs C, G).

---

### The trigger for the merger

April 13, 2026: two-node integration TB for the split path started (`can_mac_tb.vhd`: "Initial node-to-node wiring testbench. Two can_mac + can_fce pairs share a dominant-wins bus. Node A transmits, Node B receives"). During this work, the debugging cost of cross-correlating two diverged FSMs became the deciding factor. April 28: merger executed (`24586d9c`). Split-path integration TB abandoned mid-development.

---

### The unified path and its verification approach

The unified `can_mac_fsm.vhd` (1,007 lines) replaced both split FSMs. One `can_mac_bs` instance, one `can_mac_crc` instance, one testbench. The `is_transmitter` flag, latched at SOF and cleared at arbitration loss, partitions per-state logic into TX and RX branches. Shared protocol logic exists once and cannot drift.

`can_mac_pcs_fce_tb` asserts: (1) byte-by-byte frame equality DUT1 TX == DUT2 RX, (2) frame length matches, (3) `transfer_status` matches expected. No reference model for the bitstream. Bit-level correctness is checked indirectly: a wrong stuff bit causes DUT2 to signal an error frame, `transfer_status` returns non-`c_transmitted`, and the byte-equality check fails. The protocol's own error detection is the bit-level oracle.

**Limitation:** a bug symmetric across both DUTs passes undetected. "Frame in = frame out" is a necessary condition, not sufficient for ISO bit-level compliance.

---

### The arbitration-loss continuity point (spoken backup only)

When `is_transmitter` is cleared in `s_arbitration`, CRC accumulator and BS state carry over with no handoff - both were already fed from `pcs_i.rx_data` during arbitration, so the losing transmitter's state already matches a pure receiver's. Real payoff of the unified design, but not the primary reason for the merger. Could also have been engineered in a split-path design.

---

## Key Evidence for Examiner Probes

| Examiner question | Evidence |
|---|---|
| "Why did you abandon the split path?" | Commits `24586d9c` and `5a6319fc` document the eight bugs by name with root causes |
| "Was the TX FSM definitely first?" | Commit `abe012a7` (Feb 18): "Stable tx_mac_fsm" |
| "When was RX added?" | Commit `b17362dc` (Mar 31): "add RX path stubs" |
| "Did you have two copies of BS/CRC code?" | No - same entity. `b17362dc` dropped `_tx` suffix from BS/CRC on March 31. Two instances, not two files. |
| "When did you start integration testing?" | `can_mac_tb.vhd` committed April 13, abandoned April 28 at merger |
| "How did you know unified would work?" | `can_bus_controller` company reference uses unified TX/RX FSM |
| "How does is_transmitter work?" | `can_mac_fsm.vhd` line 524: latched true at SOF. Line 280: cleared at arbitration loss. |
