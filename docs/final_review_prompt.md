# Final Review Prompt

Prompt for a frontier LLM (e.g. Gemini 2.5 Pro, GPT-4o, Claude Opus) to do a final editorial review of `docs/report.md`. Attach `docs/report.md`, `docs/writing_style_rules.md`, `CONTEXT.md`, and the full `src/` tree alongside this prompt.

---

You are doing a final editorial review of a B.Eng thesis (`docs/report.md`, Pandoc markdown). Two attached files give you the full domain context you need:

- `docs/writing_style_rules.md` - writing style rules (American English, hyphenation, case, terminology, no semicolons in prose, etc.)
- `CONTEXT.md` - glossary of required terms, the intended narrative arc chapter-by-chapter, and key design decisions

Read both files before starting. Your review covers five areas:

**1. Redundancy.** Flag any paragraph or sentence that repeats information already stated clearly elsewhere. Note both locations. Do not flag intentional cross-references (e.g. "as described in @sec:X"). Flag only content that adds nothing new.

**2. AI-prose patterns.** Flag sentences that sound formulaic or like filler. Specific patterns: hollow transition sentences ("Having established X, the following section describes Y"), meta-commentary about document structure, unnecessary hedging ("it is worth noting that"), vague superlatives, adjective stacking. Propose a tighter rewrite or recommend cutting.

**3. Figure and caption correctness.** For every figure referenced in body text, check that the caption and prose description are consistent. Flag any mismatch, any figure referenced but not defined, any figure defined but not referenced, and any caption too vague to stand alone.

**4. Narrative flow.** Using the chapter arc in `CONTEXT.md` as the intended structure, flag any chapter or section opening that fails to orient the reader, any weak chapter transition, and any section where the central argument is buried or ambiguous.

**5. RTL and testbench accuracy.** For every factual claim about module behavior, port names, signal names, FSM states, bit widths, or protocol mechanics in Chapter 6 (Design and Architecture), Chapter 7 (Implementation), and the Verification and Results chapter, cross-check against the relevant source files in `src/`. Flag any claim that contradicts the actual VHDL - wrong signal names, incorrect bit indices, misattributed behavior, or descriptions of logic that no longer matches the implementation. Treat the VHDL as ground truth.

**Output format:** grouped by chapter. Within each chapter, number the issues sequentially. For each issue: (a) quote the offending text, (b) cite the section heading, (c) name the category (Redundancy / AI prose / Figure / Narrative / RTL accuracy), (d) give a concrete recommendation. Do not summarize the thesis. Do not praise. Flag only problems worth fixing.
