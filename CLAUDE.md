# CLAUDE.md

B.Eng thesis: full CAN/CAN-FD node (TX+RX) in VHDL-2008 following ISO 11898-1:2015.
Pipeline: `can_llc -> can_mac (can_mac_ser, can_mac_fsm, can_mac_bs, can_mac_crc) -> can_pcs`. Wrapper `can_mac_pcs_fce` adds FCE. Top-level `can_fd_controller` adds LLC.
Standards ref: `docs/md_out/ISO_11898_1_CAN_bus_link/ISO_11898_1_CAN_bus_link.md`. Roadmap: `docs/roadmap_progress.md`.

---

## Interface Design Mandate

**All entity ports: `std_logic` / `std_logic_vector` only.** Company advisor mandate for synthesis.

- `c_dominant = '0'`, `c_recessive = '1'`
- FSM states: `std_logic_vector(2 downto 0)` constants (e.g. `c_st_bus_idle := "011"`)
- Transfer status: `c_ongoing/c_transmitted/c_aborted/c_lost_arb/c_disturbed` (`slv(2:0)`)
- Frame format: `c_llc_fmt_cb/ce/fb/fe` (`slv(2:0)`)
- Enums (`t_mac_frame_bit_name`) only internally and on simulation-only debug ports
- Types: `t_` prefix. Constants: `c_` prefix. Package name: `pk_can_types` (file is `can_types_pkg.vhd`)

---

## Build

**Preferred**: `make TB=src/<module>/hdl_tb/<tb> all` (compile + run + waveform)

Full compile order (packages first, then leaf modules, then wrappers):
```
can_types_p.vhd → can_tb_p.vhd → can_mac_bs → can_mac_crc → can_mac_ser
→ can_mac_fsm → can_fce → can_mac → can_pcs → can_mac_pcs_fce
→ can_llc → can_fd_controller → <testbench>.vhd
```
GHDL flags: `--std=08 -fpsl --warn-no-vital-generic --warn-no-hide -P./OsvvmLibraries/osvvm/VHDL_LIBS/GHDL-6.0.0-dev -P.`

**Stale units**: modifying `pk_can_types` requires re-analyzing the entire chain.

Waveforms: `gtkwave sim/<tb>.ghw src/<module>/test_case/<tb>.gtkw` (GHW preserves enum names and records; VCD cannot).

---

## Verification Plan

File: `verification_plan/verification_plan.toml`. 118 requirements, IDs `REQ-NNN`.
**Scope: CB, CE, FB, FE frames only. CAN XL is strictly out of scope.**

Fields per entry: `id`, `source_clause`, `original_wording`, `layer` (LLC/MAC/PCS/FCE/system),
`side` (transmitter/receiver/both), `format_applicability`, `observability` (black_box/white_box),
`verification_method` (simulation/code_inspection/coverage or combo), `priority` (P1/P2/P3),
`status` (not_started/in_progress/complete), `notes`, `label`, `file`.

- `black_box`: verified at module ports only, no reference model needed.
- `white_box`: requires internal FSM state, error counters, or non-trivial reference computation.
- `system` layer: jointly owned by multiple layers or requires two nodes (ACK, error coordination).
- `label`/`file` blank until linked to a TB assertion/procedure.

MCP server: `pip install -r mcp_tools/requirements.txt`. Tools: `query_requirements`, `get_requirement`, `update_requirement`, `bulk_update`, `insert_requirement`, `get_statistics`, `delete_requirement`, `renumber_requirements`.

---

## File Headers

**RTL** (`src/<module>/hdl_src/`):
```vhdl
--------------------------------------------------------------------------------
-- Title      : <title>
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : <filename>.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: <purpose; mention PSL assertions if present>
--------------------------------------------------------------------------------
```

**Testbench** (`src/<module>/hdl_tb/`):
```vhdl
--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for <dut_name>.
--                  p_<name>_vc       - <VC description>.
--                  p_<name>_checker  - <what it monitors>.
--                  p_test_ctrl       - Coverage-driven test sequencer.
--
-- Revision log:  Date:       Initial:  JIRA:
--                YYYY-MM-DD  XXXXX     [TRIT-NNNN] Description
--------------------------------------------------------------------------------------------------------------------------------------------------------------
```

Rules: never write `-- psl` in non-PSL comments (`-fpsl` treats it as a directive). Use `----` separators, never `====`.

---

## Testbench Structure

Golden reference template: `can_mac_ser_tb.vhd`.

**OSVVM clock/reset:**
```vhdl
CreateClock(clk_i, c_clk_period);          -- clk_i: no initializer
CreateReset(rst_i, '1', clk_i, c_clk_period * 3);  -- rst_i := '1' in declaration
wait until rst_i = '0'; WaitForClock(clk_i);
-- Use WaitForClock(clk_i[, N]) not "wait for". Use std.env.finish to end sim.
```

**Random stimulus:** `RandomPType` with `rnd.DistBool((false => W1, true => W2))`.

**PSL assertions:** white-box (uses internal signals) → keep in DUT. Black-box (ports only) → duplicate in TB for simulation. Use PSL temporal operators (`|=>`, `[*N]`, SERE) for sequences; do not rewrite as VHDL state machines.

**TB file layout order:** header+libs+entity → constants → DUT signals+OSVVM signals → procedures → CreateClock/CreateReset/p_timeout/p_init → DUT inst → VCs → monitors → p_test_ctrl → PSL assertions.

**LLC legacy frame format** (71 bytes, Avalon-ST):
- Bytes 0-3: ID (right-aligned 11-bit or full 29-bit)
- Byte 4: `[6:4]`=FMT, `[3:0]`=DLC
- Bytes 5-68: data (64 bytes, zero-padded)
- Byte 69: `[0]`=IDE; Byte 70: `[2]`=BRS, `[1]`=ESI, `[0]`=RTR
- Byte 0: `sop='1'`; byte 70: `eop='1'`. Reference: `submit_and_verify` in `can_mac_pcs_fce_tb.vhd`.

**ACK injection:** trigger on `debug_bit_name = ack_bit` (registered, one-cycle delay). Do NOT trigger on `crc_delimiter_bit` at sp - the sample point has already passed by then. ```vhdl if (inject_ack and debug_bit_name = ack_bit) then
  bus_override <= c_dominant; bus_override_en <= true;
  wait for nom_bit_time_clk_c * clk_period_c;
  bus_override_en <= false;
end if;
```

**Bus loopback:** `rx_bus_i <= bus_override when bus_override_en else tx_bus_o;` - zero delay. Do NOT add propagation delay unless it is shorter than the sample point offset; a delay longer than one bit time causes every bit to fail the bit error check.

---

## Mandatory RTL Optimization Rules

See `.claude/agent_guides/vhdl_rtl_optimization_style_v1.md`. Required:
- Gate counters/prescalers when inactive (no free-running).
- No `mod`/`%` in hot sequential datapath; use bounded compare/subtract.
- Named local guard predicates in FSM combinational logic.
- Persistent state → signals, not process variables (makes register intent explicit).

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
Config disables blank-line enforcement for types/subtypes/functions/case/loop and `length_001` (120-char limit).

---

## Writing Style

- No semicolons in prose or comments. Use periods instead. No em dashes (use `-`).
- Pandoc reports: heading IDs `{#sec:name}`, crossrefs `@sec:`, `@fig:`, `@tbl:`. Every figure/table referenced in body text.
- Mermaid `stateDiagram-v2`: use `classDef reset stroke:#000,stroke-width:3px` + `class s0 reset` for initial state. No `:::` inline on `state` lines. No `[*] -->`.
- `bibliography: references.bib`, `csl: ieee.csl`, `link-citations: true` in YAML front matter.
