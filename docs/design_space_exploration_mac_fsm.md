# Design Space Exploration: MAC FSM {#sec:dse-mac-fsm}

**Module:** `src/can_mac/hdl_src/can_mac_fsm.vhd`
**Reference implementation:** `can_bus_controller/hdl_src/can_fsm.vhd` (CC-only)
**Standard:** ISO 11898-1:2015, Sections 6.6, 8.1.4

## Purpose

This note captures the design path that produced the current combined MAC FSM, what was ported from the previous CC-only controller, what was deliberately not ported, and which architectural choices proved to be detours. It exists to make the rationale visible in the final report so that an external reader can understand both the chosen design and the discarded alternatives.

## Implementation history

The MAC FSM went through three distinct shapes during the project:

1. **Combined TX/RX FSM with internal FCE** - inherited shape of the previous CC-only `can_bus_controller`. Not re-implemented for FD; used only as a reference.
2. **Split TX and RX FSMs** (`can_mac_fsm_tx`, `can_mac_fsm_rx`) - the design described in @sec:combined-vs-separated-fsm of the main report. Each path had its own bit stuffer and CRC instance; the only inter-path coupling was a `transmitting_i` flag and a dominant-wins merge of the two PCS outputs at the `can_mac.vhd` top level.
3. **Combined TX/RX FSM with external FCE** (current). One synchronous process, one state enum (24 states), shared bit stuffer / CRC / serializer submodules, and a separate `can_fce.vhd` entity. The split-FSM files are kept on disk for reference but no longer compiled.

The transition from shape 2 to shape 3 was driven by a concrete debugging episode (the `c_disturbed`-instead-of-`c_transmitted` failure in `can_mac_pcs_fce_tb`). Tracking a single bit time across two parallel FSMs proved to be the dominant source of wasted time: every "why did this state transition not fire?" question had to be answered by looking at *two* state vectors and *two* sets of bit counters that re-derived the frame position independently. Combining them into one process made the same questions answerable from a single waveform pane.

## Ports of the old `can_fsm.vhd`

The current FSM borrows a small number of ideas from the previous CC-only controller. Each port is listed with its source location and the reason it was kept.

### P1: Granular error-frame state structure (4 states + bus_off)

**Ported from** `can_bus_controller/hdl_src/can_fsm.vhd:683-795`.

Earlier iterations of the new FSM used two states (`s_error_overload`, `s_error_delimiter`) plus a `dominant_run_count` register to express the four ISO error-frame phases. This was correct but compressed: locating "where in the error sequence are we" in a waveform required reading the bit counter in addition to the state name, and the dominant-run counter had to be reset and incremented from inside both states.

The previous controller already had the right structure for this: separate states for *flag drive*, *first-bit-after-flag check*, *consecutive-dominant counting*, and *recessive delimiter counting*. Adopting that shape (renamed and adapted to the FD-aware port surface) gave four explicit states:

| State | ISO | Replaces |
|-------|-----|----------|
| `s_error_flag` | 6.6.13, 6.6.5.2 | flag-drive part of `s_error_overload` |
| `s_error_flag_check` | 8.1.4.2.b | implicit first-iteration of `s_error_delimiter` |
| `s_error_dominant_delim` | 8.1.4.2.f | `dominant_run_count` register |
| `s_error_delimiter` | 6.6.5.3 | recessive-counting part of `s_error_delimiter` |

The new layout also fixes a subtle ambiguity that existed in the two-state version: a dominant during the recessive delimiter (a form error per ISO 6.6.21.3.2) and a dominant from another node's late error flag (tolerated per ISO 8.1.4.2.f) used to share the same code path. The split makes them distinct - tolerated dominants are handled in `s_error_dominant_delim`, while form errors in `s_error_delimiter` start a fresh error frame.

### P2: Explicit `s_bus_off` state for waveform visibility

**Ported from** `can_bus_controller/hdl_src/can_fsm.vhd:794-795` (`when s_bus_off => null;`).

The earlier shape of the new FSM treated bus-off as a reset condition (`if rst_i = '1' or fce_i.bus_off = '1'`) and snapped the FSM back to `s_bus_reintegration`. This was efficient in gates but invisible in waveforms - there was no way to tell, at a glance, whether the FSM was sitting in `s_bus_reintegration` because it had just come out of reset or because the FCE had flagged bus-off.

The old FSM kept bus-off as a real state with a single `null` body. The current FSM follows the same idea: `s_bus_off` is entered when `fce_i.bus_off = '1'` and exits to `s_bus_reintegration` once bus_off clears. The transition is now visible as a state edge in GTKWave, which speeds up FCE-recovery debugging.

### P3: Verbatim ISO comments

**Ported from** `can_bus_controller/hdl_src/can_fsm.vhd:680-795`.

The old controller's inline comments cite the relevant ISO sub-clauses precisely (`8.1.4.2.b`, `8.1.4.2.f`, `6.6.5.2 Last paragraph`, `6.6.21.3.2`). These were carried over verbatim where the corresponding code path still exists. Comments are a cheap form of traceability - they survive copy/edit cycles in a way that external traceability tables typically do not - and using the wording from the prior implementation removed the temptation to invent fresh paraphrases that might subtly drift from the standard.

## Deliberate non-ports

Several other patterns from the old controller were considered and rejected.

### N1: Internal FCE

**Source:** `can_bus_controller/hdl_src/can_fsm.vhd` processes `p_node_error_state` and `p_error_count`.

The old controller embedded TEC/REC counting and active/passive/bus-off state logic directly in the FSM file. This made the entity self-contained: a reader could understand all protocol behaviour from one file.

**Why not ported:** Fault confinement is a separable concern with a clean ISO-defined interface (Tables 16-19 of ISO 11898-1). Keeping it external (`can_fce.vhd`) gives three concrete benefits in this project:

- The FCE can be unit-tested independently with its own testbench, which is much easier than driving error sequences through a full MAC FSM.
- The MAC FSM file stays focused on frame structure; reading it does not require reading the counter arithmetic too.
- Future scope changes (e.g. additional fault-handling rules) touch one file rather than risking regressions in unrelated frame-handling code.

The cost is that understanding the full error-handling story requires reading two files. In practice this has been worth it.

### N2: `transmit_i` / `sample_rx_i` two-strobe timing model

**Source:** `can_bus_controller/hdl_src/can_fsm.vhd` body (case branches gated on `transmit_i = '1'` and `sample_rx_i = '1'`).

The old controller received two separate strobes from `can_node_clock`: one to drive `tx_o` and a later one to sample `rx_i`. The drive-vs-sample distinction was visible in signal names.

**Why not ported:** The new PCS exposes a single `sample_point` strobe and accepts a registered `pcs_o.tx_data` that holds across cycles. The PCS internally schedules the bit-boundary tx edge from the registered value. This decouples the FSM from the bit-time structure entirely - the FSM produces *what* to drive on each sample point and lets the PCS decide *when* the bus edge happens. This is required for FD's TDC and SSP behaviour anyway, so reverting to two strobes would have been a step backward.

A side effect of the single-strobe model: the old FSM needed transitional "setup" states (e.g. `s_to_error_frame` at line 650 of the reference) to reconfigure outputs *between* drive and sample phases. The new FSM has no such setup states - any case branch can change `pcs_o.tx_data` and the change takes effect at the next bit edge.

### N3: `do_not_count_stuff_error` flag (partial ACK-error exemption)

**Source:** `can_bus_controller/hdl_src/can_fsm.vhd:657, 667`.

The old controller used a single boolean to suppress TEC counting on ACK errors (per ISO 8.1.4.2.c.ex1).

**Why not ported:** The ISO exemption is more nuanced than a single boolean: a passive transmitter that sees a missing ACK should *not* count the resulting error against its TEC, *unless* another node co-signalled the error during the transmitter's own passive flag (in which case the ACK-error origin is no longer unique). The new FSM expresses this with two signals (`ack_error_caused_flag` to mark the cause, `saw_dominant_during_flag` to detect co-signalling) and applies the exemption via `fce_o.passive_tx_ack_error_exempt_1` to the FCE. This matches ISO 6.6.20 / 8.1.4.2.c.ex1 fully rather than approximately.

### N4: Compact `s_arbitration` state

**Source:** `can_bus_controller/hdl_src/can_fsm.vhd` (single arbitration state with bit_count comparisons covering ID, RTR, SRR, IDE).

The old FSM handled all of arbitration in a single state with bit-count branches. This is short and direct for CC.

**Why not ported:** For FD the arbitration field has more sub-fields with format-dependent positions (RRS instead of RTR for FD, SRR-then-IDE-then-ID-B for extended). A single compact state would re-introduce the nested if/elsif on bit count and format that the per-field state structure was specifically chosen to avoid (see @sec:combined-vs-separated-fsm of the main report). The per-field split costs a few extra states for CC base format, where most states are visited once with no logic, but the readability gain for FD justifies the cost.

## Detour 1: the split TX/RX FSM

The first attempt at the new MAC was a **split** TX/RX architecture: `can_mac_tx` containing `can_mac_fsm_tx` (~700 lines, 21 states) plus its own `can_mac_bs` and `can_mac_crc`, and `can_mac_rx` containing `can_mac_fsm_rx` (~640 lines, 19 states) plus its own copies of the same submodules. The two FSMs shared no state.

The argument for this split, captured in @sec:combined-vs-separated-fsm of the main report, was: **TX-only and RX-only requirements should map onto disjoint code paths, so each path can be verified independently against its own subset of the verification plan.** This sounds reasonable. In practice it was the wrong choice and caused real cost.

### Why it looked good on paper

- *Separation of concerns:* TX and RX have genuinely different responsibilities. TX drives bits derived from LLC bytes; RX captures bits and writes them to a frame buffer.
- *Verification mapping:* The AI-generated verification plan had used "TX side" and "RX side" as one of its primary classification dimensions (alongside layer and frame format). A 1:1 mapping between verification-plan dimensions and design entities looked elegant.
- *Independence:* In principle, a bug in the TX path could not affect the RX path because they shared no state. This made each path "easier to reason about in isolation".

### What actually happened

- *Frame structure is shared.* CC and FD frames have the same field order and the same bit-stuffing rules regardless of who is driving them. Encoding the frame layout twice (once in `can_mac_fsm_tx`, once in `can_mac_fsm_rx`) duplicated maintenance cost: a fix to the FD CRC delimiter handling in TX had to be replicated in RX, and vice versa, with no compiler help to enforce that the two copies stayed in sync.
- *Submodule duplication is not free.* `can_mac_bs` and `can_mac_crc` were instantiated twice. This is fine in gates but it doubled the surface area for "is the BS handling fixed stuffing the same way on both sides?" investigations.
- *Single-bit-time bugs need a single-bit-time view.* The `c_disturbed`-instead-of-`c_transmitted` debugging session needed to correlate, in the same waveform pane: TX FSM state, TX bit count, RX FSM state, RX bit count, BS state on both sides, CRC state on both sides, and the merged PCS output. Two parallel FSMs each re-deriving the frame position from their own counters made this much harder than it needed to be.
- *Mental load while writing the code was higher, not lower.* "If I am in `s_data` on the TX side and the bus shows a bit error, what state is the RX side in right now?" became a constant question. With a unified FSM the question goes away - there is only one state, and it is the state.

### Why the dimension-to-design mapping was a mistake

The AI-generated verification plan classified each requirement by side (TX, RX, both), layer (LLC, MAC, PCS, FCE), and frame format. These are good *verification* axes - they describe *what* you have to test and *what configuration* you have to drive to test it. They do not describe *what natural code units* the design should have.

The natural code unit of the MAC is **the frame**, not the side. A frame is the same shape regardless of whether the local node is driving it or sampling it. Splitting the FSM by side meant cutting the natural code unit in half along an artificial seam, then having to bolt the two halves back together with shared submodules and dominant-wins merging. The verification plan still maps cleanly onto the unified FSM - TX-only requirements run with `is_transmitter = true` stimulus, RX-only with `is_transmitter = false` - but the design no longer has to bend itself around the verification taxonomy.

The lesson is: verification plan dimensions are inputs to test-bench architecture, not to RTL architecture. RTL architecture should follow the structure of the protocol being implemented. In hindsight this is obvious; at the start of the project it was not.

## Detour 2: AI-extracted normative requirements

The verification plan was originally bootstrapped by feeding the ISO 11898-1 markdown into an LLM and asking it to extract every normative ("shall" / "should") clause as a TOML entry. This is the procedure described in @sec:ai-assisted-extraction of the main report.

The technique worked in the narrow sense: the LLM did extract the clauses, in roughly the right format, with passable shape/scope tagging. The output was used as the basis for the manual review described in @sec:human-in-the-loop-validation.

The technique did not work as well as hoped:

- **Scale.** The first-pass extraction produced several hundred entries. After de-duplication, compound-splitting, and consolidation, the verification plan landed at 168 requirements. A large fraction of the original entries were either redundant (the standard restates the same constraint several times in different chapters), structural (definitions and figures, not testable behaviour), or compound clauses where the LLM had failed to split out the individual requirements. Manual review of the extraction took longer than writing the plan from scratch would have.
- **Black-box mismatch.** The advisor's verification methodology is black-box: only behaviour observable at module boundaries counts. A large fraction of the LLM-extracted "shall" statements describe internal counter thresholds, structural definitions, configuration constraints, or error counter arithmetic - none of which produce a unique observable boundary effect. The observability classification (@sec:observability-classification) was added specifically to filter these out, and roughly 13% of the surviving 168 entries were tagged `internal`. The original raw extraction had a much higher internal-fraction; most of those entries had to be deleted rather than tagged.
- **Authority drift.** The LLM occasionally rephrased the standard's wording in ways that were almost-but-not-quite faithful. Each rephrase was a potential source of verification error if it had been carried into a test. The manual-review step had to compare each extracted entry against the standard's exact wording, which is the same effort as transcribing the requirement directly.

The net value of the AI extraction was modest: it accelerated the *first* draft, but the second-draft cost (review, prune, re-classify, re-word) absorbed most of that saving. A more targeted approach - using the LLM to extract requirements *for one specific layer at a time*, with explicit black-box filtering in the prompt - would likely have produced a smaller, cleaner first draft that needed less rework. This is a candidate methodology improvement for future projects rather than a defect of the current plan, which has converged to a usable size.

## Outcome

The current MAC FSM is one file (`src/can_mac/hdl_src/can_mac_fsm.vhd`, ~1100 lines) containing one synchronous process, one state enum, and one set of bit counters. It instantiates one `can_mac_bs`, one `can_mac_crc`, one `can_mac_ser_tx`, and one `can_fce`. The split FSM files (`can_mac_fsm_tx.vhd`, `can_mac_fsm_rx.vhd` and their wrappers) are kept on disk for reference but are no longer compiled.

The two end-to-end testbenches that exercise the MAC (`can_mac_pcs_fce_tb`) pass with **15,707 affirmations** across normal frame coverage (IDE × FDF × DLC bins) and a five-point bus/transceiver delay sweep. The reduced-scope `can_mac_n2n_tb` (no realistic bus delays) was retired because it duplicated coverage already provided by `can_mac_pcs_fce_tb`.

The cost of the two detours - the split FSM and the bulk AI extraction - was real but bounded: roughly two weeks of design and debugging that did not contribute to the final RTL. Both detours produced useful side effects: the split FSM made the per-field state structure (kept in the unified FSM) feel obviously correct by the time it was being written, and the AI extraction produced the verification-plan tooling (`mcp_tools/verification_plan_manager.py`) that has paid back its development cost in subsequent plan maintenance.

## Cross-references

- @sec:combined-vs-separated-fsm (main report, original split-FSM rationale)
- @sec:ai-assisted-extraction (main report, original AI-extraction rationale)
- @sec:observability-classification (main report, black-box filtering framework)
- @sec:requirement-taxonomy (main report, verification-plan dimensions)
