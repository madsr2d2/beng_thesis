# Handoff: Report Review Continuation

## Session Skill
Use `/grill-with-docs` - systematic prose review of `docs/report.md`, one question per turn, propose before applying, commit after each logical batch.

## What Was Done This Session

A full prose review pass from **`## AI-Assisted Extraction`** through **`## Error Detection and Fault Confinement`** (end of `# CAN and CAN FD Protocol Overview`). All changes are committed to `main`. See `git log --oneline -40` for the full list.

Key changes made:

**Requirements Engineering section:**
- MCP paragraph: removed redundant source-clause augmentation example; tightened sentence voice ("using the agent", "schema-validated MCP tool calls", removed "write" from "validated interface")
- Folded requirements bridge paragraph into protocol overview opener; rewrote opener to call back "those mechanisms" explicitly

**Layered Reference Model:**
- Fixed layer model description: two OSI layers (data link + physical), not one; added ISO Fig. 4 citation
- Aligned all four sub-layer bullets with ISO Fig. 4 responsibilities; added LLC acceptance filtering and overload notification with scope brackets; MAC: flat participial list including error signalling; PCS: "bit timing and bus sampling" + TX/RX interface; removed implementation-specific sentence
- Merged `@tbl:req-layer-map` into expanded `@tbl:vplan-distribution`; shortened column headers (n, FS, BB, WB); moved System row last; removed table from theory section

**Frame Types and Formats:**
- Rewrote Classic frame paragraph: IDE explanation, DLC, form bits (SRR/r0/r1), interframe space (INT/ST/IDLE), REQ refs anchored at opener
- Added FD DLC non-linear mapping sentence; added SBC field to FD frame paragraph; named reserved form bit (res)
- REQ-038 anchored once in section opener; field-level refs (REQ-032, REQ-008, REQ-031, REQ-015) on individual sentences
- Updated figure captions (frame format waveform notation, bit timing two-node layout)

**Bit Timing:**
- Fixed TQ definition (prescaler × system clock period)
- Rewrote PS bullet: arbitration constraint PS ≥ 2×(t_TRX+t_bus) with figure ref
- Fixed SS bullet: "when the node is synchronized"
- Added `### Synchronization {#sec:bit-sync}` subsection; rewrote sync paragraph with SS/PE/SJW anchoring, hard sync triggers (SOF + FDF→res), segment adjustment direction
- Removed redundant CAN FD flexible data rate paragraph from TDC section
- Rewrote TDC paragraph (5 sentences): SSP before SP, invalid SSPs during TDC delay, res bit measurement, offset; updated figure caption

**Bit Stuffing:**
- Accurate stuffing ranges (CC: SOF–CRC; FD: SOF–data field then fixed in CRC)
- Introduced SB and FSB abbreviations to match figure; Gray-coded SBC; dropped "absent in CAN Classic" (covered in FD frame section)

**CRC:**
- Tightened CRC-15 bullet; removed self-referential and implementation sentences; moved CRC mismatch error sentence to error section

**Error Detection and Fault Confinement:**
- Converted five error types to bullet points; moved REQ-014 to acknowledgment error bullet; pooled REQ-029 and REQ-030 (one ref each); added error-passive ACK error TEC exemption; spelled out TEC/REC; replaced `llc_i.normal_mode` with generic description; removed implementation commentary and fluff bridge paragraph

## Where We Left Off

At the start of `# Verification Plan {#sec:verification-plan}`, specifically **L438** of `docs/report.md`. The protocol overview chapter is complete and clean.

## Next Section to Review

`# Verification Plan {#sec:verification-plan}` starting at L438, covering:

```
## Layer {#sec:vplan-layer}           L445
## Side {#sec:vplan-side}             L451
## Format Applicability               L460
## Observability                      L464
## Priority                           L473
## Requirement Distribution           L481  ← expanded table already done this session
## Verification Plan Data Structure   L486
```

## Writing Style Rules (critical)

- **No semicolons (`;`) in prose. No exceptions.**
- **No em dashes** - use ` - ` (spaced hyphen).
- **Colons inside paragraphs are acceptable** (user confirmed this session - do NOT flag them).
- American English: "acknowledgment", "color", etc.
- No author attributions - state claims directly with citations.
- Pandoc crossrefs: `@sec:`, `@fig:`, `@tbl:`. Never "Figure @fig:X" (doubles the prefix).
- Always Read exact lines immediately before every Edit.

Full rules: `docs/writing_style_rules.md`

## Key Decisions Made This Session

- Colons inside paragraphs are acceptable - do not flag (user reverted all colon removals)
- Implementation details belong in design/architecture sections, not protocol theory sections
- REQ refs should be anchored once per topic (e.g. REQ-038 once for overall frame structure) with field-level refs for individual obligations
- Figure captions should describe what notation means (hatching = variable content, fixed-polarity = protocol-defined bits)
- `System` layer row goes last in the distribution table (it's not an ISO layer)

## Project Context

B.Eng thesis: full CAN/CAN FD node (TX+RX) in VHDL-93. See `CLAUDE.md` for full project context and `docs/writing_style_rules.md` for prose rules.
