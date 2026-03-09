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

3. Use named local guard booleans in FSM control logic
- In the synchronous FSM process, evaluate guard conditions once at the top and store in process-level variables.
- Keep guard names close to RTL intent (for example `frame_active_v`, `rx_dominant_v`, `tdc_timeout_v`).
- Reuse these guard variables across state and output logic to reduce duplicated comparisons and improve reviewability.
- Example: evaluate `llc_valid_v := llc_i.valid = '1'` once, then use in multiple if/case branches.

## FSM Structure Guidance

**Preferred**: Single synchronous process with procedures for complex logic.

- Single `fsm_sequential` process (clocked on rising_edge)
- All state/output updates using local `v_*` variables initialized with current registered values
- Guard booleans evaluated once at cycle start, stored in process-level variables
- Extract complex state or output logic into local procedures to keep main FSM case statement clean
- Each procedure operates on and modifies `v_*` variables (closure scope)
- Register all outputs at end of process in the else branch (non-reset side)

**Benefits**:
- Removes boilerplate of 3-process architectures (next_state_logic, output_logic, state_update)
- Eliminates redundant signal declarations (`next_*` signals)
- Guard variables evaluated once per cycle, reused across state and output logic
- Procedures keep FSM case statement readable while handling complex transitions
- All updates atomic within single clock edge—no intermediate signal propagation

**Structure template**:
```vhdl
fsm_sequential : process (clk_i) is
  variable v_state : my_state_t;
  variable v_output : my_output_t;
  variable guard_v : boolean;
begin
  if rising_edge(clk_i) then
    if (rst_i = '1') then
      -- Reset logic
    else
      -- Evaluate guards once at top
      guard_v := condition_check;

      -- Initialize all v_* with current registered values
      v_state := state;
      v_output := output;

      -- Case statement for state transitions and output logic
      case state is
        when my_state =>
          if (guard_v) then
            v_state := next_state;
            -- Output updates
          end if;
      end case;

      -- Register all updates
      state <= v_state;
      output <= v_output;
    end if;
  end if;
end process;
```

Register module-boundary outputs by default unless the interface contract requires same-cycle combinational response.

## Verification Requirements

Any optimization/refactor under this guide must:
1. Preserve externally visible behavior.
2. Keep/reset semantics explicit.
3. Pass the relevant unit/integration testbenches.
4. Include test updates when timing contracts or edge cases change.

