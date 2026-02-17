# VHDL RTL Optimization Style Guide: `vhdl_rtl_optimization_style_v1`

## Purpose

Define mandatory low-risk RTL optimization patterns used in this project for timing clarity, lower switching activity, and synthesis-friendly arithmetic.

Apply these rules to new RTL and when refactoring existing modules.

## Mandatory Rules

1. Gate inactive counters and prescalers
- Clocked counters must only toggle in states/modes where their result is consumed.
- Outside active states, hold or reset counters deterministically (project preference: reset to `0` unless behavior requires hold).
- Do not free-run secondary timing counters when the datapath does not use them.

2. Avoid `% mod` in hot sequential datapath logic
- In clocked processes on frequently-active paths, prefer compare/subtract or bounded helper logic over `% mod`.
- Keep behavior equivalent and bounded by existing subtype/range constraints.
- If a package helper already exists for related arithmetic (for example FIFO index derivation), use it.

3. Use named local guard booleans in combinational control logic
- In `next_state_logic` and combinational output-select logic, extract repeated predicates into local variables.
- Keep guard names close to RTL intent (for example `frame_active_v`, `rx_dominant_v`, `tdc_timeout_v`).
- Reuse these names in condition branches to reduce duplicated comparisons and improve reviewability.

## FSM Structure Guidance

When practical, separate logic into:
- `State register` (clocked)
- `Next-state logic` (combinational)
- `Output logic` (combinational and/or clocked as required by interface timing)

Register module-boundary outputs by default unless the interface contract requires same-cycle combinational response.

## Verification Requirements

Any optimization/refactor under this guide must:
1. Preserve externally visible behavior.
2. Keep/reset semantics explicit.
3. Pass the relevant unit/integration testbenches.
4. Include test updates when timing contracts or edge cases change.

