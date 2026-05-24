# Handoff: Report Review Continuation

## Session Skill
Use `/grill-with-docs` - systematic prose review of `docs/report.md`, one question per turn, propose before applying, commit after each logical batch.

## What Was Done This Session

Full prose review pass of **`# Verification Plan`** and **`# Design and Architecture`**. All changes committed to `main`. See `git log --oneline -30` for the full list.

**Verification Plan chapter (major restructure):**
- Opener rewritten: direct statement of five dimensions driving architecture and testbench design; two bullet points (design-facing / verification-facing) with bridge sentence to field sections
- Deleted Verification Plan Data Structure section and table; promoted Verification Method, Traceability, Status from `###` to `##`
- Deleted Priority section (already covered in Requirements section); removed priority content from Summary
- Moved Requirement Distribution to last position; renamed to "Verification Plan Summary"; expanded with priority/status breakdown; later trimmed to two substantive observations (MAC white-box density, FCE all-black-box)
- All field section openers: added backtick formatting to field names
- Each field section: added illustrative requirement example (Layer: REQ-020 system label; Side: REQ-025 TDC TX-only; Format Applicability: REQ-015 FB/FE only; Observability: REQ-006 CRC polynomial; Verification Method: REQ-018 simulation+coverage combo)
- Observability: bullets for black-box/white-box values; replaced "stimulus-and-observe" with direct language
- Verification Method: bullets for all four method values
- Layer: cut redundant middle sentence; REQ-020 example clarified as both multi-module and multi-node
- Closing bridge sentence cut from Summary (D&A opener covers the same ground)

**Design and Architecture chapter:**
- System Overview moved to first subsection (introduces all module names before they are used)
- Chapter opener rewritten: introduces module hierarchy (`can_llc`, `can_mac` wrapper, submodules); `can_bus_controller` introduced here as the existing controller
- "Internal LLC Frame Format" renamed to "LLC-MAC Interface Format"
- Consistent naming: replaced all "existing CAN Classic controller", "existing controller", "prior implementation" with `can_bus_controller`
- Adopting ISO sub-layer model: dropped VP `layer`-dimension reference; states rationale directly
- Combined vs. Separated TX/RX: rewritten as narrative ("tried X, observed Y, concluded Z")
- Per-Field FSM Granularity: reframed around REQ-038 defining the frame field sequence; FSM naturally progresses through that structure; removed forward-ref to implementation section
- LLC Frame Format: added intro paragraph naming purpose of each sub-format; Host-LLC simplified (extends `can_bus_controller`, 8→64 bytes, FD flags added to existing control bytes); LLC-MAC simplified (full 71-byte buffer vs. 2-byte config prefix)

## Where We Left Off

At the start of `# Implementation {#sec:implementation}`, specifically **L542** of `docs/report.md`. Design and Architecture chapter is complete and clean.

## Next Section to Review

`# Implementation {#sec:implementation}` starting at L542, covering:

```
## Interface Conventions        L546
## can_mac_fsm                  L556
   ### FSM Structure and Mode Flag
   ### TX Mode: Frame Transmission
   ### RX Mode: Frame Reception
   ### Error-Frame States
## can_mac_ser
## can_mac_bs
## can_mac_crc
## can_fce
## can_pcs
```

## Writing Style Rules (critical)

- **No semicolons (`;`) in prose. No exceptions.**
- **No em dashes** - use ` - ` (spaced hyphen).
- **Colons inside paragraphs are acceptable** - do NOT flag them.
- American English: "acknowledgment", "color", etc.
- No author attributions - state claims directly with citations.
- Pandoc crossrefs: `@sec:`, `@fig:`, `@tbl:`. Never "Figure @fig:X" (doubles the prefix).
- Always Read exact lines immediately before every Edit.

Full rules: `docs/writing_style_rules.md`

## Key Decisions Made This Session

- Priority belongs in the Requirements section, not the Verification Plan section - do not re-introduce it there
- `format_applicability` is design-facing (not verification-facing) because it informed per-field FSM granularity; describe it as such, not as "testbench stimulus scope"
- `can_bus_controller` is the name for the existing CAN Classic controller - use it consistently; do NOT use "existing controller", "prior implementation", "old implementation"
- Design and Architecture sections should not forward-reference implementation details (no refs to `@sec:impl-*` from D&A)
- System Overview belongs first in D&A so module names are established before they are used
- LLC is not yet implemented - do NOT mention this in the Design section; it belongs in the Implementation section only
- Narrative style for "tried and rejected" architectural decisions: "tried X, observed Y, concluded Z"

## Project Context

B.Eng thesis: full CAN/CAN FD node (TX+RX) in VHDL-93. See `CLAUDE.md` for full project context and `docs/writing_style_rules.md` for prose rules.
