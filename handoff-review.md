# Handoff: Report Review Continuation

## Session Skill
Use `/grill-with-docs` - systematic prose review of `docs/report.md`, one question per turn, propose before applying, commit after each logical batch.

**IMPORTANT for next session:** The user will start by listing the issues they found in `## can_pcs`. Wait for that list before beginning the review. Do not pre-empt with your own observations.

## What Was Done This Session

Prose review of `## can_mac_bs`, `## can_mac_crc`, and `## can_fce`. Verification plan corrections and consolidation. All committed to `main`.

**`## can_mac_bs` (now ~L592):**
- Rewrote double-stuffing paragraph: replaced incorrect TX/RX `stuff_count` divergence explanation with correct ISO "no double stuffing" rule (REQ-018)
- Fixed "cancelled" → "canceled" (American English)
- Fixed "SB/FSB's" → "SBs and FSBs"
- Cut redundant `stuff_bit_count` sentence after figure caption
- User tightened and restructured the section directly; final prose reviewed and accepted

**`## can_mac_crc` (now ~L602):**
- Restructured: architecture opener with figure ref, engine details upfront, poly selection second, IPT constraint last
- Merged opener sentences; restored bit-position alignment; cut "zero-extending" verbose phrase
- Replaced "the FSM" with `can_mac_fsm`
- Simplified IPT paragraph: cut SP+1/SP+2 detail, replaced ISO section ref with REQ-024, framed as full prescaler range compliance
- User added TX/RX `crc_poly_select` timing distinction

**`## can_fce` (now ~L611):**
- Cut verbose TEC/REC rule enumeration; replaced with REQ-028 reference
- Fixed broken "follow the rules in:" sentence
- Rewrote passive ACK exemption paragraph: removed incorrect explanation (was about recessive error flag); correct explanation is that FCE has no frame visibility so MAC must signal it; theory already in `@sec:error-model` so implementation section focuses on the signal only
- User tightened section directly

**Verification plan corrections:**
- REQ-028 (old numbering): fixed Exception 1 paraphrase - added "passive error flag uncontested" condition then simplified further to just "error-passive ACK error is exempt"; dropped Exception 2 (pre-arbitration stuff error) as redundant with normal arbitration behavior
- Folded old REQ-028 (`normal_mode` reset) into old REQ-030 (state transitions) as sub-claim 5; deleted REQ-028
- Renumbered plan: old REQ-029–038 → new REQ-028–037 (10 IDs shifted)
- Updated all REQ references in report atomically; fixed two en-dash range suffixes missed by regex
- Tightened new REQ-029 paraphrase; removed implementation-specific `normal_mode` label

## Where We Left Off

`## can_fce` is complete. Next section is `## can_pcs` starting at approximately **L621** of `docs/report.md`.

## Current can_pcs Section State

```
## `can_pcs` {#sec:impl-can-pcs}          ~L621

### Resynchronization                      ~L627
### Dual Bit Rate Switching                ~L631
### Transmitter Delay Compensation         ~L639
```

The user will provide their issue list before the review begins.

## REQ Renumbering Reference (new numbers)

Key FCE/PCS requirements after renumbering:
- REQ-024: PCS bit timing configuration (IPT ≤ 2 t_q)
- REQ-025: Transmitter delay compensation
- REQ-026: PCS synchronization (4 sub-claims)
- REQ-027: PCS bus-off isolation
- REQ-028: FCE error counter update rules (was REQ-029)
- REQ-029: FCE state transitions + bus-off recovery + LLC reset (was REQ-030)
- REQ-030: BRS bit rate switching (was REQ-031)

## Writing Style Rules (critical)

- **No semicolons (`;`) in prose. No exceptions.**
- **No em dashes** - use ` - ` (spaced hyphen).
- **Colons inside paragraphs are acceptable** - do NOT flag them.
- American English: "acknowledgment", "synchronization" (not "synchronisation"), "canceled".
- No author attributions - state claims directly with citations.
- Pandoc crossrefs: `@sec:`, `@fig:`, `@tbl:`. Never "Figure @fig:X" (doubles the prefix).
- Always Read exact lines immediately before every Edit.

Full rules: `docs/writing_style_rules.md`

## Key Decisions This Session

- Double stuffing at dynamic-to-fixed boundary: pending dynamic SB serves as initial FSB; implementation skips FSB emission - ISO prohibits two consecutive stuff bits (REQ-018)
- Passive ACK error exemption: FCE has no frame visibility, MAC must explicitly signal via `passive_tx_ack_error_exempt_1`; purpose (preventing lone-node bus-off) already explained in `@sec:error-model` - implementation section only covers the signal
- REQ-028 (normal_mode reset) folded into REQ-029 (state transitions) - thin standalone requirement, same behavior as bus-off recovery
- Verification plan paraphrase style: no implementation-specific signal names; concise numbered bullets

## Key Decisions Carried Over

- `can_bus_controller` is the name for the existing CAN Classic controller - use it consistently
- D&A sections should not forward-reference implementation details
- Narrative style for "tried and rejected" decisions: "tried X, observed Y, concluded Z"
- Do not over-explain what FSM diagrams already show; reference the figure instead
- Replace ISO section citations in prose with REQ-NNN references where possible

## Project Context

B.Eng thesis: full CAN/CAN FD node (TX+RX) in VHDL-93. See `CLAUDE.md` for full project context and `docs/writing_style_rules.md` for prose rules.
