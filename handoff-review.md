# Handoff: Report Review Continuation

## Session Skill
Use `/grill-with-docs` - the current session was a prose review pass through `docs/report.md`, working section by section, one question per turn, proposing before applying, committing after each logical batch.

## What Was Done This Session

A systematic prose review pass through `docs/report.md` from the Reading Guide through the AI-Assisted Extraction section. All changes are committed to `main`. See `git log --oneline` for the full list - the last 15 commits cover this session's work.

Key changes made:
- Reading Guide: moved Tools and Language subsection into Requirements > Code Standard section
- Background (CAN Classic, CAN FD): improved prose, citations, terminology, figure caption
- IP survey table: Language → Source column, standardised Scope/Conformance columns
- Requirements opening paragraph: rewritten, removed premature requirement count
- Code Standard section: restructured into three subsections (Tools, Integration Requirements, VHDL Code Standard); tool citations added; Claude Code disclosure moved here
- AI Extraction section: MCP paragraph restructured (problem-first), REQ-026 walkthrough tightened, paraphrase and table corrected to match TOML exactly

## Where We Left Off

In `## AI-Assisted Extraction: Utility and Limitations` (`{#sec:ai-extraction}`), around **L318–L355** of `docs/report.md`.

### Immediately pending: figure link issue

**The problem:** The initial AI extraction was text-only - it captured prose sentences but missed technical content encoded in ISO figures. 16 of 38 requirements have figure references in their `source_clause` field (e.g. REQ-026 has `Figure 33`, REQ-008 has `Figure 6, Figure 7`). These were added manually during the iterative refinement phase, not by the initial extraction.

**What to add:** A sentence or two in the AI extraction section noting this limitation and framing it as part of the iterative refinement story - source clauses were extended with figure links after the initial text-only extraction pass. The REQ-026 table already shows `Figure 33` in the Source row, which provides a natural hook.

Good place to insert: at the end of the extraction phase paragraph (L322) or as a dedicated sentence in the limitations framing.

To verify which requirements have figure references:
```python
python3 -c "
import tomllib
with open('verification_plan/verification_plan.toml', 'rb') as f:
    data = tomllib.load(f)
for r in data['requirement']:
    sc = r.get('source_clause', '')
    if 'fig' in sc.lower() or 'Figure' in sc:
        print(r['id'], '|', sc[:120])
"
```

### Also pending (do after figure issue):

**Anchor typo:** The table at L352 has `{#tbl:req027-example}` but the requirement is REQ-026. Should be `{#tbl:req026-example}`. Check if the anchor is cross-referenced anywhere before changing it.

```bash
grep -n "req027-example\|req026-example" docs/report.md
```

## Writing Style Rules (critical)

- **No semicolons (`;`) in prose. No exceptions.**
- **No colons (`:`) inside paragraphs.** Only before enumerations/bullet lists.
- No em dashes - use ` - ` (spaced hyphen).
- American English: "acknowledgment", "color", etc.
- No author attributions ("X showed that") - state claims directly with citations.
- Always Read the exact lines immediately before every Edit - never use cached reads.

Full rules: `docs/writing_style_rules.md`

## Section Structure Context

The section being reviewed is:
```
## AI-Assisted Extraction: Utility and Limitations {#sec:ai-extraction}
  [extraction phase paragraph - L322]
  [distillation paragraph + REQ-026 intro - L324]
  [7 extracted statements - L326-333]
  [analysis paragraph - L334]
  [paraphrase - L336-343]
  [table - L345-352]
  [MCP server paragraph - L354]
  [bridge to protocol overview - L356]
```

After this section, the next chapter is `# CAN and CAN FD Protocol Overview {#sec:can-protocol-overview}` which has not yet been reviewed this session.

## Project Context

B.Eng thesis: full CAN/CAN FD node (TX+RX) in VHDL-93. See `CLAUDE.md` for full project context and `docs/writing_style_rules.md` for prose rules.
