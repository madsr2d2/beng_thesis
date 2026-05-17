# CLAUDE.md

B.Eng thesis: full CAN/CAN FD node (TX+RX) in VHDL-2008 following ISO 11898-1:2015.
Pipeline: `can_llc -> can_mac (can_mac_ser, can_mac_fsm, can_mac_bs, can_mac_crc) -> can_pcs`. Wrapper `can_mac_pcs_fce` adds FCE. Top-level `can_fd_controller` adds LLC.
Standards ref: `docs/md_out/ISO_11898_1_CAN_bus_link/ISO_11898_1_CAN_bus_link.md`.

---

## Interface Mandate

**All entity ports: `std_logic` / `std_logic_vector` only.** Company advisor mandate for synthesis.

- `c_dominant = '0'`, `c_recessive = '1'`
- FSM states: `std_logic_vector(2 downto 0)` constants
- Transfer status: `c_ongoing/c_transmitted/c_aborted/c_lost_arb/c_disturbed` (`slv(2:0)`)
- Frame format: `c_llc_fmt_cb/ce/fb/fe` (`slv(2:0)`)
- Enums only internally and on simulation-only debug ports
- Types: `t_` prefix. Constants: `c_` prefix. Package: `pk_can_types` (`can_types_pkg.vhd`)

---

## Build

`make TB=src/<module>/hdl_tb/<tb> all` - compile + run + waveform.
Modifying `pk_can_types` requires re-analyzing the entire chain. See `docs/agents/build.md`.

---

## Verification

Scope: CB, CE, FB, FE frames only. **CAN XL is strictly out of scope.**
Plan: `verification_plan/verification_plan.toml` (IDs `REQ-NNN`). See `docs/agents/verification-plan.md`.
MCP tools: `query_requirements`, `get_requirement`, `update_requirement`, `bulk_update`, `insert_requirement`, `get_statistics`, `delete_requirement`, `renumber_requirements`.

---

## File Headers

Templates in `docs/agents/file-headers.md`. Critical rules:
- Never write `-- psl` in non-PSL comments (`-fpsl` treats it as a directive).
- Use `----` separators, never `====`.

---

## Testbench

Golden reference: `can_mac_ser_tb.vhd`. Full patterns in `docs/agents/testbench-guide.md`.

---

## RTL Rules

See `.claude/agent_guides/vhdl_rtl_optimization_style_v1.md`. Required:
- Gate counters/prescalers when inactive (no free-running).
- No `mod`/`%` in hot sequential datapath; use bounded compare/subtract.
- Named local guard predicates in FSM combinational logic.
- Persistent state → signals, not process variables.

---

## Code Patterns

**Bit slice constants (critical):**
```vhdl
constant c_foo_start : integer := 7;  -- MSB
constant c_foo_end   : integer := 5;  -- LSB
-- use: signal(c_foo_start downto c_foo_end)
```

**Avalon-ST ready/valid:** state sets `ready='1'`; transfer happens when `valid='1'` in same cycle.
**SP/SSP strobes:** `bus_polarity` driven continuously; `sp`/`ssp` are single-cycle pulses. MAC latches polarity on strobe.

---

## Linting

`vsg -c vsg_config.yaml -f src/<module>/hdl_src/<file>.vhd`

---

## Writing Style

> **CRITICAL: No semicolons (`;`) in prose anywhere. Use periods. No exceptions.**

- American English: "acknowledgment", "color", etc.
- No em dashes (use `-`).
- Pandoc: `{#sec:name}` IDs, `@sec:/@fig:/@tbl:` crossrefs. Every figure/table referenced in body. Use `@sec:` not "the following/next section".
- Mermaid `stateDiagram-v2`: `classDef reset stroke:#000,stroke-width:3px` + `class s0 reset`. No `:::` on `state` lines. No `[*] -->`.
- `bibliography: references.bib`, `csl: ieee.csl`, `link-citations: true` in YAML front matter.
- **Terminology:** "CAN FD" (no hyphen), "CAN Classic" (not "Classic CAN"), "FSM" (not "state machine"), "hard synchronization" and "resynchronization" (no "soft sync").
- **Case:** Node states lower case in body text: "error active", "error passive", "bus off". Same for "error flag", "active error flag", "passive error flag". Title case in abbreviation table only.
- **Hyphenation:** "sub-layer", "stuff-bit insertion", "bit-error monitoring", "data-phase bit rate", "in-scope", "out-of-scope". No hyphen: "testbench", "submodule", "destuffed".
- **Numbers:** Spell out below 10 in prose. Digits for technical constants ("CRC-15", "by 8 on TX errors").

---

## Agent Skills

- **Issue tracker:** GitHub Issues `madsr2d2/beng_thesis`. See `docs/agents/issue-tracker.md`.
- **Triage labels:** needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix. See `docs/agents/triage-labels.md`.
- **Domain docs:** Single-context layout - one `CONTEXT.md` + `docs/adr/` at root. See `docs/agents/domain.md`.
