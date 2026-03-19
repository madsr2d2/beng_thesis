# VHDL RTL Optimization Style Guide: `vhdl_rtl_optimization_style_v1`

## Purpose

Define mandatory RTL style patterns used in this project for clarity, minimal complexity, and synthesis-friendly design.

Apply these rules to new RTL and when refactoring existing modules.

## Mandatory Rules

1. Gate inactive counters and prescalers
- Clocked counters must only toggle in states/modes where their result is consumed.
- Outside active states, hold or reset counters deterministically (project preference: reset to `0` unless behavior requires hold).
- Do not free-run secondary timing counters when the datapath does not use them.

2. Avoid `% mod` in hot sequential datapath logic
- In clocked processes on frequently-active paths, prefer compare/subtract or bounded helper logic over `% mod`.
- Keep behavior equivalent and bounded by existing subtype/range constraints.

3. Prefer direct signal assignments over variables
- Use signal assignments (`<=`) directly in the clocked process. Avoid the `v_*` variable-then-register pattern unless a variable is genuinely needed (e.g. a value read-back within the same cycle, or a function return value used in multiple places).
- This eliminates variable declarations, default-copy blocks, and end-of-process register-copy blocks.
- Procedures within the process can assign signals directly.

4. Use top-level guards for global conditions
- Conditions that apply across all states (e.g. transfer completion, abort) should wrap the case statement as a single if-else, not be repeated in every state.
- Example: `if (transfer_status /= c_ongoing) then reset; else case state is ...`

5. Keep defaults minimal and visible
- Set pulse-type output defaults (e.g. `valid <= '0'`) once before the case statement, not in a separate procedure.
- Combinational defaults that depend on state can use conditional expressions: `ready <= '0' when (state = busy) else '1'`.

6. Use named constants from `pk_can_types` for all magic numbers
- Never hardcode field widths, offsets, or positions. Use the constants defined in the types package.
- Example: use `c_stuff_width` not `5`, use `c_ack_delimiter_offset` not `2`.

## FSM Structure

**Preferred**: Single synchronous process with procedures for complex logic and direct signal assignments.

- Single process, clocked on `rising_edge`
- Direct signal assignments (`<=`) throughout, no `v_*` variable pattern
- Extract reusable logic into procedures that assign signals directly
- Top-level guard wrapping the case statement for global conditions (reset, abort, completion)
- Pulse defaults cleared before the case statement

**Structure template**:
```vhdl
p_fsm : process (clk_i) is

  procedure do_complex_thing is
  begin
    output_signal <= computed_value;
  end procedure do_complex_thing;

begin
  if rising_edge(clk_i) then
    if (rst_i = '1') then
      -- Reset all signals
    else
      -- Pulse defaults
      valid_o <= '0';

      if (global_abort_condition) then
        state <= idle;
      else
        case state is
          when idle =>
            ...
          when active =>
            do_complex_thing;
            ...
        end case;
      end if;
    end if;
  end if;
end process p_fsm;
```

## Comment Style

1. **File header**: Use company header format with Description listing numbered responsibilities.

2. **State descriptions**: Each state in a case statement gets a short description between `-----` separator lines:
```vhdl
case state is
  -----------------------------------------------------------------
  -- Wait for valid SOP from LLC.
  -----------------------------------------------------------------
  when idle =>
    ...

  -----------------------------------------------------------------
  -- Shift out remaining bits of current byte to MAC FSM.
  -----------------------------------------------------------------
  when shift_out =>
    ...
end case;
```

3. **Procedure comments**: One-line summary above the procedure declaration describing *what* it does, not *how*.

4. **Inline comments**: Only where the logic is non-obvious. No comments on self-explanatory assignments. Keep inline comments short and specific.

5. **No trailing summaries or section markers** for signal registration blocks - the code is self-documenting.

## Verification Requirements

Any optimization/refactor under this guide must:
1. Preserve externally visible behavior.
2. Keep reset semantics explicit.
3. Pass the relevant unit/integration testbenches.
4. Include test updates when timing contracts or edge cases change.
