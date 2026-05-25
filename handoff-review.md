# Handoff: Report Review Continuation

## Session Skill
Use `/grill-with-docs` - systematic prose review of `docs/report.md`, one question per turn, propose before applying, commit after each logical batch.

## What Was Done This Session

Full prose review pass of **`# Implementation`** up to and including `## can_mac_ser`. All changes committed to `main`. See `git log --oneline -20` for the full list.

**Implementation chapter opener (L542-548):**
- Folded Interface Conventions section content into chapter opener; deleted the section
- Added Module Overview subsection listing `can_mac_pcs_fce` hierarchy
- Added `pk_can_types` (`can_types_pkg.vhd`) description: single shared package for all interface records, protocol constants, frame format byte layouts, and utility functions
- Added `can_llc` scope note: not implemented within project schedule, interface contracts in verification plan, implementation path in future-work section

**`## can_mac_fsm` (L550-582):**
- Expanded opener: `llc_frame` byte array reframed as deliberate proof-of-concept baseline (reusing `can_bus_controller` approach); block RAM migration as identified upgrade path; bus-off owned by `can_fce`, `fce_i.bus_off` treated as secondary reset
- FSM Structure: merged `is_transmitter` sentences; added pre-case/case/post-case three-phase decomposition as bullet points with tradeoff discussion (locality cost vs. cross-cutting logic); added error-frame role-independence note (`s_error_flag`/`s_error_delimiter` driven by `fce_i.error_active` not `is_transmitter`); cut state enumeration list (diagram covers it); cut incorrect "only `s_ack` and `s_eof` carry role-specific logic" claim
- TX Mode: added `drive_bit` two-cycle pipeline explanation (BS and CRC take two clocks to present valid outputs); split paragraph; replaced "bus echo" with "samples the bus"; reframed arbitration CRC/BS source paragraph (multi-node bus is the reason, not just arbitration-loss handoff)
- RX Mode: named `p_stream_to_LLC`; cut "eliminates the need for deserializer" sentence; fixed passive voice and notation issues
- Cut `### Error-Frame States` subsection entirely; role-independence note folded into FSM Structure
- Added REQ-NNN traceability throughout: REQ-006, REQ-007, REQ-013, REQ-014, REQ-016, REQ-018, REQ-020, REQ-021, REQ-022, REQ-023, REQ-025

**`## can_mac_ser` (L584-590):**
- Section reviewed and accepted as-is (user prefers the cleaner existing version)
- No changes made

## Where We Left Off

At `## can_mac_bs` starting at **L592** of `docs/report.md`. The `can_mac_ser` section is complete.

## Next Section to Review

`## can_mac_bs` starting at L592, then continuing through:

```
## can_mac_bs     L592
## can_mac_crc    L604
## can_fce        L616
## can_pcs        L626
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

- `can_llc` not implemented due to schedule constraints - mention this in Implementation opener, not D&A
- `pk_can_types` is the single shared package all modules depend on - describe it as such
- `llc_frame` byte array is a deliberate proof-of-concept choice, not a mistake - block RAM is the upgrade path
- Pre-case/case/post-case FSM cycle structure is worth the locality cost because the exception logic is cross-cutting
- Error-frame states are role-independent (driven by `fce_i.error_active`) - this is worth calling out explicitly
- During `s_arbitration` both TX and RX feed `pcs_i.rx_data` because multiple nodes may be transmitting simultaneously - the bus is the authoritative source; the clean arbitration-loss handoff is a consequence, not the cause
- `drive_bit` two-cycle delay is about BS and CRC needing two clocks to present valid outputs - not about state/bit_count settling
- The PCS owns the bit-boundary timing; the MAC simply needs valid data in `pcs_o.tx_data` ready in time
- Add REQ-NNN references to implementation details to make requirement traceability explicit
- Do not over-explain what the FSM diagram already shows; reference the figure instead

## Key Decisions Carried Over from Previous Session

- `can_bus_controller` is the name for the existing CAN Classic controller - use it consistently
- D&A sections should not forward-reference implementation details
- Narrative style for "tried and rejected" decisions: "tried X, observed Y, concluded Z"

## Project Context

B.Eng thesis: full CAN/CAN FD node (TX+RX) in VHDL-93. See `CLAUDE.md` for full project context and `docs/writing_style_rules.md` for prose rules.
