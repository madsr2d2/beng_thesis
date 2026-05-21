# Writing Style Rules

> **CRITICAL: No semicolons (`;`) in prose anywhere. Use periods. No exceptions.**

- American English: "acknowledgment", "color", etc.
- No em dashes (use `-`).
- Pandoc: `{#sec:name}` IDs, `@sec:/@fig:/@tbl:` crossrefs. Every figure/table referenced in body. Use `@sec:` not "the following/next section".
- **Terminology:** "CAN FD" (no hyphen), "CAN Classic" (not "Classic CAN"), "FSM" (not "state machine"), "hard synchronization" and "resynchronization" (no "soft sync").
- **Case:** Node states lower case in body text: "error active", "error passive", "bus off". Same for "error flag", "active error flag", "passive error flag". Title case in abbreviation table only.
- **Hyphenation:** "sub-layer", "stuff-bit insertion", "bit-error monitoring", "data-phase bit rate", "in-scope", "out-of-scope". No hyphen: "testbench", "submodule", "destuffed".
- **Numbers:** Spell out below 10 in prose. Digits for technical constants ("CRC-15", "by 8 on TX errors").
