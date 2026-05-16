# CLAUDE.md

B.Eng thesis: full CAN/CAN-FD node (TX+RX) in VHDL-2008 following ISO 11898-1:2015.
Pipeline: `can_llc -> can_mac (can_mac_ser, can_mac_fsm, can_mac_bs, can_mac_crc) -> can_pcs`. Wrapper `can_mac_pcs_fce` adds FCE. Top-level `can_fd_controller` adds LLC.
Standards ref: `docs/md_out/ISO_11898_1_CAN_bus_link/ISO_11898_1_CAN_bus_link.md`. Roadmap: `docs/roadmap_progress.md`.

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
Plan: `verification_plan/verification_plan.toml` (118 reqs, IDs `REQ-NNN`). See `docs/agents/verification-plan.md`.
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

> **CRITICAL: Never use semicolons (`;`) in prose or report comments. Use periods instead. This applies everywhere: report body text, figure captions, table captions, inline comments, and any other written English. Violations break the writing style consistency of the entire document. There are no exceptions.**

- No em dashes (use `-`).
- Pandoc: heading IDs `{#sec:name}`, crossrefs `@sec:`, `@fig:`, `@tbl:`. Every figure/table referenced in body text.
- Mermaid `stateDiagram-v2`: `classDef reset stroke:#000,stroke-width:3px` + `class s0 reset`. No `:::` on `state` lines. No `[*] -->`.
- `bibliography: references.bib`, `csl: ieee.csl`, `link-citations: true` in YAML front matter.

---

## Agent Skills

### Issue tracker
Issues live in GitHub Issues for `madsr2d2/beng_thesis`. See `docs/agents/issue-tracker.md`.

### Triage labels
Default five-role vocabulary (needs-triage, needs-info, ready-for-agent, ready-for-human, wontfix). See `docs/agents/triage-labels.md`.

### Domain docs
Single-context layout - one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
