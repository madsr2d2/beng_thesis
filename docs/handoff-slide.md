# Handoff: Presentation Slide Content Grilling (continued)

## Context

This handoff continues a `/grill-with-docs` session on presentation slide content for Mads Richardt's B.Eng thesis: "Implementation and Verification of a CAN/CAN FD Protocol Controller in VHDL."

The grilling session is ongoing. A full slide outline has been agreed, with one slide (Slide 5) substantially updated from a separate deep-dive agent session. The next agent should continue grilling on remaining open questions about slide content before the presentation is built.

---

## Current State: Agreed Slide Outline

**11 slides, 20-25 minutes, DTU Compute examiner (digital design background), primary contribution: design and verification.**

Time split: 3 min motivation / 2 min protocol essentials / 10 min design+verification / 5 min synthesis+conclusion.

| # | Slide | Notes |
|---|---|---|
| 1 | Everllence context and CAN FD motivation | Marine engines, IO-extender FPGA, CAN FD as migration path |
| 2 | Why clean-slate: 4 `can_bus_controller` limitations + one-sentence IP rejection | Single bit rate, dynamic stuffing only, single CRC, coupled fault confinement |
| 3 | Protocol essentials table (4 rows) | See table below |
| 4 | Layered architecture enables module-by-module verification | `mac_overview.png`; each ISO sub-layer = one module = one testbench |
| 5 | Unified FSM: split tried and abandoned | See detailed spec below - substantially updated from deep dive |
| 6 | PCS: dual bit rate switching and TDC pipeline (concept) | 3-stage TDC: measure (res bit to RX edge), count down, fire SSP |
| 7 | PCS waveform evidence | `pcs.pdf` top half, `full_fd_frame.pdf` bottom half |
| 8 | Bus-off recovery | `bus_off.pdf`; error active → passive (TEC=128) → bus off (TEC=256) → 128 idle → error active |
| 9 | Verification summary | 28/37 closed; 9 open grouped by reason (see below) |
| 10 | Synthesis results | 4,608 LEs (30%), 127 MHz fmax; CC vs FD 4.0×; frame buffer dominates |
| 11 | Conclusion and future work | Two lessons + 4 future work items (see below) |

**Protocol essentials table (Slide 3):**

| CAN FD / format feature | Architectural consequence |
|---|---|
| Dual bit rate + TDC | `can_pcs` redesign with 3-stage TDC pipeline |
| Fixed stuffing + SBC | `can_mac_bs` mode switching |
| CRC-17/21, dual data feed | Three parallel CRC engines in `can_mac_crc` |
| Four formats (CB/CE/FB/FE) with diverging fields | Per-field FSM states; format transitions become state graph edges |

**Slide 5 - Unified FSM (updated from deep-dive, see `docs/handoff-splitpath-content.md` for full detail):**

Two distinct arguments, both required:

- **Point 1 - Implementation drift**: `side` dimension misread as implementation-facing; TX FSM stable Feb 2026, RX stubs Mar 31, two weeks parallel development produced 8 timing divergences; two BS instances, two CRC instances; each SP-granularity boundary defined twice independently; three named bugs on slide (A+C SOF divergence, E in_data_phase off by 1 SP, D ACK window too narrow); debugging required two waveform sets per bug.
- **Point 2 - Verification methodology weakness**: split-path tests verified RTL agreed with reference model; unified-path tests verify a second independent CAN implementation agreed with the first.

Spoken backup only (not on slide): arbitration-loss continuity, `is_transmitter` mechanism, `can_bus_controller` precedent, FSM state count.

**Verification summary grouping (Slide 9):**
- 6 LLC deferred (scope boundary)
- 2 non-blocking (REQ-034 P3 not applicable, REQ-035 P2 optional)
- 1 in progress - REQ-021: bit-error detection verified; sub-claims 2-5 require frame-aware error injection

**Conclusion lessons (Slide 11):**
1. Requirements structure is not RTL structure (split FSM is the example)
2. Layered architecture is a practical partitioning

**Future work (Slide 11):**
1. `can_llc` implementation
2. Hardware bring-up
3. BRAM migration for frame buffer
4. REQ-021 frame-aware error injection

---

## Open Questions for the Next Grilling Session

The following questions were not resolved before this handoff. The next agent should address them in order of priority.

### 1. Slide 5 timing (unresolved - last thing discussed)

Slide 5 is now substantially denser than originally scoped (two arguments, three named bugs). The previous time budget was 90 seconds. The question posed but not answered:

> "The slide is now denser - does 90 seconds still feel right for this, or should we push it to 2 minutes and trim something elsewhere?"

This needs resolution before building. If 2 minutes, something in the 10-minute design+verification block must shrink.

### 2. Slides 6+7 content detail not yet drilled

The PCS concept slide (Slide 6) and waveform slide (Slide 7) have only a rough spec. Key questions not yet asked:
- Should Slide 6 include a diagram of the 3-stage TDC pipeline, or is it verbal only?
- The `pcs.pdf` waveform is complex (TDC count-up A→B, countdown C→D, SSP fires at D). Does it need annotation callouts on the slide, or will the presenter narrate?
- Does `full_fd_frame.pdf` on Slide 7 need any annotation, or is it shown as-is?

### 3. Slide 4 (layered architecture) content not yet drilled

`mac_overview.png` is agreed as the figure, but the slide body text has not been specified. Key questions:
- Does the slide explicitly name all five modules (`can_mac_fsm`, `can_mac_bs`, `can_mac_crc`, `can_mac_ser`, `can_pcs`, `can_fce`), or just the sub-layer groupings (MAC, PCS, FCE)?
- Should the slide show the testbench-to-module mapping explicitly (e.g. arrows from each module to its testbench name), or is that too much detail?

### 4. Opening slide (Slide 1) not yet drilled

The opening slide has only been specified as "Everllence context and CAN FD motivation." No decision on:
- Whether there is an opening hook before the motivation, or whether the first slide is straight context
- What figure, if any, appears on Slide 1 (the `can_bus.png` figure from the report is a candidate)

---

## Key Artifacts to Read Before Continuing

- Full slide deep-dive content for Slide 5: `docs/handoff-splitpath-content.md`
- Report narrative arc and glossary: `CONTEXT.md`
- Report full text: `docs/report.md`
- Module overview figure: `docs/figures/mac_overview.png`
- Waveform figures: `docs/figures/waveforms/pcs.pdf`, `full_fd_frame.pdf`, `bus_off.pdf`

---

## Suggested Skills

- `/grill-with-docs` to continue the presentation grilling session.
