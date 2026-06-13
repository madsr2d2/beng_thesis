# Handoff: Defense Slides — Polish Pass

## Context

This handoff is for a `/grill-with-docs` session to continue improving Mads Richardt's B.Eng defense presentation: "Implementation and Verification of a CAN/CAN FD Protocol Controller in VHDL."

The previous session (`docs/handoff-slide.md`) resolved all open content questions and produced a working compiled PDF. This session should grill the existing slides against the domain model and push for presentation quality — layout, visual hierarchy, spoken-delivery readiness, and examiner Q&A prep.

---

## What Was Accomplished This Session

1. **All four open questions from `docs/handoff-slide.md` resolved** — slide 5 timing (2 min, no trim), slide 4 body (six modules named, testbench mapping verbal), slides 6+7 (compact TikZ pipeline diagram, A/B/C/D callouts on pcs.pdf, full_fd_frame.pdf as-is), slide 1 (one-sentence hook + `can_bus.png`).

2. **Working compiled PDF produced** — 11 content slides + 2 DTU title pages = 13 pages. DTU Beamer template (red, 16:9, `dtured`). All layout issues resolved (title hyphenation, FSM slide overflow, PCS TikZ clipping, conclusion overflow).

3. **Committed to git** — commit `08dea680`. Files:
   - `defense/slides.tex` — the presentation source
   - `defense/latexmkrc` — sets `TEXINPUTS` to locate DTU template
   - `defense/.gitignore` — ignores `dtutemplates/` (external repo) and LaTeX artifacts
   - `Makefile` — `make slides` and `make slides-clean` targets added

4. **Build command:** `make slides` from repo root. PDF output: `defense/slides.pdf`.

---

## Current Slide State

| # | Title | Section | Status |
|---|---|---|---|
| 1 | Everllence and the CAN FD Migration | Motivation | Working; hook is spoken, `can_bus.png` on right |
| 2 | Why Clean-Slate | Problem | Working; two-column layout |
| 3 | CAN FD: Four Mechanisms, Four Architectural Consequences | Protocol | Working; `\footnotesize` table |
| 4 | Layered Architecture Enables Module-by-Module Verification | Architecture | Working; `mac_overview.png` + six module names |
| 5 | Unified FSM: Split Path Tried and Abandoned | Architecture | Working but uses `\fontsize{8}{9.5}` — very dense |
| 6 | PCS: Dual Bit Rate Switching and TDC | PCS | Working; full-width TikZ pipeline |
| 7 | PCS Waveform Evidence | PCS | Working; two waveforms stacked, caption-only callouts |
| 8 | Bus-Off Recovery | Verification | Working; `bus_off.pdf` full-width |
| 9 | Verification: 28 of 37 Requirements Closed | Verification | Working; large "28/37" number |
| 10 | Synthesis Results: Cyclone 10 LP | Synthesis | Working; table + bullets |
| 11 | Conclusion and Future Work | Conclusion | Working; `\small` to fit content |

---

## Known Issues and Areas Needing Work

### High priority

**Slide 5 (FSM) — font too small.** The entire slide uses `\fontsize{8}{9.5}` with bug items at `\fontsize{7}{8.5}`. This is readable on a monitor but may be hard to follow on a projector. Options: split into two slides (one per argument), use a more visual layout (timeline or bug table), or accept the density and rely on spoken narration. This is the most important slide in the deck and its visual quality matters.

**Slide 7 (Waveforms) — annotations are caption-only.** The A/B/C/D callouts for `pcs.pdf` are implemented as a text line below the figure, not as actual callout marks on the waveform. A TikZ overlay with labeled arrows pointing to positions on the waveform would be significantly clearer. The `pcs.pdf` waveform currently renders at about 36% of frame height — quite small.

**Slide 11 (Conclusion) — "delivered" section trimmed.** "MAC, PCS, FCE verified" was dropped to fit the slide. Consider whether this loss of specificity matters for the examiner's assessment.

### Medium priority

**No speaker notes.** No `\note{}` commands have been added. The examiner Q&A prep documented in `docs/handoff-splitpath-content.md` (bug evidence table, commit hashes) should be in speaker notes, not memorized.

**Section labels may be suboptimal.** Slides 4 and 5 both sit under the "Architecture" section breadcrumb. Slide 5 is as much a verification story as an architecture story. Worth reviewing whether the section grouping helps or distracts.

**Slide 3 (Protocol table) — no visual differentiation.** The four rows carry equal visual weight. The TDC row (which motivates slide 6) and the FSM row (which motivates slide 5) could be visually emphasized using DTU color cells or bold rows.

### Low priority

**No progressive disclosure.** No `\pause` or `\only` overlays anywhere. The FSM slide in particular might benefit from revealing the two arguments sequentially. Adds slides to the PDF but can improve live delivery.

**Synthesis slide has no CC vs FD visual.** The 4.0× comparison is text-only. A simple bar chart (using `pgfplots` already loaded) would make the comparison land faster for the examiner.

---

## Key Artifacts

| Artifact | Purpose |
|---|---|
| `defense/slides.tex` | The presentation source — edit this |
| `docs/handoff-slide.md` | All content decisions from prior sessions (fully resolved) |
| `docs/handoff-splitpath-content.md` | Slide 5 content brief: language constraints, bug details, examiner Q&A evidence table, spoken backup material |
| `CONTEXT.md` | Domain glossary and narrative arc — check terminology before editing slide text |
| `docs/figures/mac_overview.png` | Slide 4 figure |
| `docs/figures/can_bus.png` | Slide 1 figure |
| `docs/figures/waveforms/pcs.pdf` | Slide 7 top waveform (TDC evidence) |
| `docs/figures/waveforms/full_fd_frame.pdf` | Slide 7 bottom waveform (full frame context) |
| `docs/figures/waveforms/bus_off.pdf` | Slide 8 figure |
| `docs/synthesis_resource_comparison.md` | Source data for slide 10 numbers |
| `defense/dtutemplates/templates/Beamer/template/` | DTU Beamer theme files (do not edit; external repo) |

---

## Constraints That Must Be Respected

These were established in prior sessions and are non-negotiable:

- **Do NOT cite FSM state count** ("19 states") on any slide — invites optimization questions with no payoff. See `MEMORY.md`: `feedback_slide_state_counts.md`.
- **Slide 5 language constraints** from `docs/handoff-splitpath-content.md`: do not say "the reference model was fundamentally flawed"; do not say "frame in = frame out is the protocol definition"; do not put `is_transmitter` mechanism on slide 5.
- **Terminology**: follow `CONTEXT.md` glossary exactly. "CAN FD" (no hyphen), "CAN Classic" (not "Classic CAN"), "FSM" (not "state machine"), `can_mac_fsm` (not "TX FSM" or "RX FSM").
- **Three-lesson conclusion** in the report has a third lesson (narrow MCP write interface makes AI-assisted artifact maintenance safe) — this was deliberately dropped from the slide for time. Do not re-add it without reconsidering timing.

---

## Time Budget (agreed)

20-25 minutes total. DTU Compute examiner, digital design background.

| Block | Slides | Budget |
|---|---|---|
| Motivation | 1-2 | 3 min |
| Protocol essentials | 3 | 2 min |
| Design + verification | 4-9 | 10 min (slide 5 = 2 min) |
| Synthesis + conclusion | 10-11 | 5 min |

---

## Suggested Skill

`/grill-with-docs` — use it to challenge each slide against the domain model, identify where slide content drifts from `CONTEXT.md` terminology, and drive decisions on the open issues above (especially slide 5 density and slide 7 annotation quality). Update `CONTEXT.md` if any new canonical terms emerge.
