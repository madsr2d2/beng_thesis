# CAN FD LE Explosion — Investigation Briefing

## Context

This document summarises a resource usage analysis of a CAN controller VHDL implementation,
comparing a CAN Classic (CC) node and a CAN FD node. The goal is to locate the root cause
of an unexpectedly large Logic Element (LE) increase in the FD implementation.

The implementation uses an Intel/Altera FPGA target (LE = LUT+FF pair in Quartus terminology).

---

## Measured Resource Usage

| Node  | LEs   | Registers |
|-------|-------|-----------|
| CC    | 1146  | 334       |
| FD    | 4109  | 684       |
| Delta | +2963 | +350      |

### Module breakdown

All modules other than the MAC FSM account for approximately **500 LEs total** in both
implementations (i.e. the delta between CC and FD outside the MAC FSM is negligible).

**The entire +2963 LE delta lives inside the MAC FSM.**

---

## Architecture Overview

Both CC and FD share the same high-level MAC FSM architecture:

- **Shared TX/RX FSM** with an `is_transmitter` flag gating output decode logic
- **Frame register array** — received/transmitted frame stored as `frame(bit_count) <= value`
  and read back as `condition <= frame(index_of_interest)`
- **`get_current_bit` function** consuming a `frame_params_t` record to produce the current
  TX bit based on field boundaries
- **Pre-case error handler** for state-agnostic errors
- **`bs_valid` gate** stripping stuff bits before the case statement
- **Running CRC** computation gated differently for CC vs FD per ISO 11898-1

The FD node adds a small number of extra FSM states for FD-only fields (FDF, BRS, ESI,
stuff count field). The FSM state count difference is modest — a few states.

---

## Register Delta — Well Understood

The +350 register delta is consistent with the payload size increase:

| Field            | CC       | FD        | Delta   |
|------------------|----------|-----------|---------|
| Payload bits     | 120 (15B)| 512 (64B) | +392    |
| Other frame bits | ~214     | ~260      | +46     |
| **Total FFs**    | ~334     | ~684      | **+350**|

This matches measured values well. The register delta is **payload-dominated and expected**.

---

## LE Delta — The Problem

The +2963 LE delta is not well explained by any single identified source.

### Payload-attributable LEs (quantifiable)

| Source                        | Delta LUTs |
|-------------------------------|------------|
| Frame register write decoder  | ~+65       |
| Bit counter widening (7→9b)   | ~+5        |
| Field boundary comparators    | ~+5–10     |
| **Subtotal**                  | **~+75–80**|

This accounts for roughly **2.5% of the observed LE delta**. The frame array write decoder
scales as O(N/6) LUTs where N is the number of payload bits; the read mux for a 1-bit
runtime-indexed read scales as O(N/64) LUT stages.

### Protocol logic (partially quantifiable)

| Source                                        | Rough estimate |
|-----------------------------------------------|----------------|
| CRC datapath (17/21-bit poly, fixed stuffing) | ~200–400 LUTs  |
| Stuff bit mode-switch (normal → fixed)        | ~100–200 LUTs  |
| DLC→length nonlinear mapping                  | ~10–20 LUTs    |
| Extra FSM states (FDF, BRS, ESI, stuff count) | ~10–30 LUTs    |
| **Subtotal**                                  | **~320–650 LUTs** |

### Unexplained remainder

Even summing generously: **~75 + ~650 = ~725 LUTs**, leaving approximately
**~2200–2400 LEs unaccounted for**.

---

## Hypotheses to Investigate

The following are the most likely root causes of the unexplained LE usage, in rough
priority order:

### H1 — `frame_params_t` record width causing wide muxes in `get_current_bit`

If `frame_params_t` grew significantly wider for FD (more fields, wider fields, larger
payload length constants), every mux and comparator inside `get_current_bit` widens.
This function is called combinationally and its output fans into the TX datapath.
A wide record with many fields synthesises into a large mux tree.

**Check:** compare the `frame_params_t` definition between CC and FD. Count total bits.
Look at the synthesis-elaborated width of `get_current_bit` in the RTL viewer.

### H2 — TX path newly implemented or significantly expanded in FD

If the CC implementation only had a partial or stub TX path, and the FD implementation
has a fully realised TX path, the `is_transmitter`-gated logic block would be much
larger in FD regardless of protocol differences.

**Check:** verify whether CC TX logic is fully implemented or stubbed. Compare the
synthesized logic under the `is_transmitter = '1'` branch between CC and FD.

### H3 — Unoptimised `case` or `if` over wide signals

If any `case` statement in the MAC FSM switches on a wide signal (e.g. a concatenation
of `bit_count & state & is_transmitter`), the synthesizer may produce a very large
decode tree. A `case` on a 10-bit+ signal can generate hundreds of LUTs if not
encoded efficiently.

**Check:** look for `case` statements with large or concatenated select expressions
in the MAC FSM. Check Quartus synthesis messages for inferred priority encoders.

### H4 — CRC polynomial and fixed-stuff mux inline with datapath

The FD CRC requires the stuffer to be bypassed for fixed stuffing in the CRC field,
and the polynomial switches between 17-bit and 21-bit based on payload length. If
this is implemented as a wide inline mux in the CRC shift register feed rather than
a separate small state machine, it adds significant combinational logic directly in
the critical path.

**Check:** review CRC feed logic. Is the stuff-inject mux a small isolated block or
is it spread through the frame processing datapath?

### H5 — Synthesis not sharing logic between TX and RX paths

The `is_transmitter` flag is intended to gate output logic only. If the synthesizer
is not recognising opportunities to share the frame register read logic between TX
and RX paths (e.g. due to signal naming or `if/else` structure that prevents
resource sharing), it may be duplicating logic.

**Check:** in the Quartus RTL viewer, verify that the frame array and `get_current_bit`
are instantiated once and shared, not duplicated under each branch.

---

## Suggested Investigation Steps

1. **Run Quartus hierarchy resource report** — get per-entity LE counts to confirm
   the MAC FSM is truly the sole source, and check if any sub-function (CRC, stuffer)
   shows anomalous usage.

2. **RTL viewer on MAC FSM** — look at the elaborated schematic for the frame array
   write path and `get_current_bit` output mux. Flag any unexpectedly wide structures.

3. **Compare `frame_params_t` bit width CC vs FD** — count all fields and total bits.
   If FD record is >2× wider, H1 is likely dominant.

4. **Check TX implementation completeness in CC** — if CC TX is stubbed, the comparison
   is unfair and H2 explains a large portion.

5. **Inspect `case` select widths** — search source for `case` statements, note the
   width of the select expression in FD vs CC.

6. **Isolate CRC block** — temporarily stub out the CRC logic with a constant and
   re-synthesize to measure its isolated LE contribution.

---

## What a "Normal" Delta Would Look Like

For a clean implementation where FD adds only payload and necessary protocol logic,
a reasonable expected LE delta would be:

| Source                  | Expected LEs |
|-------------------------|--------------|
| Frame store decode      | ~75          |
| CRC + stuffing logic    | ~400–600     |
| FSM states + datapath   | ~100–200     |
| **Expected total delta**| **~575–875** |

The observed delta of **+2963** is approximately **3–5× the expected value**, which
strongly suggests at least one structural issue rather than purely protocol complexity.
