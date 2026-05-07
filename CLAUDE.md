# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a B.Eng thesis project implementing a **full CAN (Controller Area Network) node** with both TX and RX pipelines in VHDL-2008, following the **ISO 11898-1:2015 standard**. The project includes:

- Core CAN/CAN-FD types and constants (`can_types_pkg.vhd` - package `pk_can_types`)
- Bit timing utilities (`can_timing_pkg.vhd`)
- Complete TX pipeline: LLC -> MAC (serializer, FSM, bit stuffer, CRC) -> PCS
- Fault Confinement Entity (`can_fce.vhd`)
- Comprehensive testbenches (8 TBs, all passing)
- GHDL simulator integration with OSVVM library framework
- GTKWave waveform viewer integration
- Formal verification with PSL assertions (SymbiYosys + ghdl-yosys-plugin)

**Roadmap Progress**: `docs/roadmap_progress.md` tracks implementation status against the advisor roadmap. Keep this file updated as modules and TBs are completed.

**Key Dependencies**: GHDL compiler, OSVVM libraries, VSG linter

**Standards Reference**: `docs/md_out/ISO_11898_1_CAN_bus_link/ISO_11898_1_CAN_bus_link.md` (ISO 11898-1:2024, Third edition) - searchable markdown version

---

## Interface Design Mandate

**All module interfaces use `std_logic` and `std_logic_vector` only.** No custom enums, booleans, or integers on entity ports. This is a company advisor mandate for synthesis compatibility.

- Polarity: `c_dominant = '0'`, `c_recessive = '1'` (std_logic constants, not an enum)
- FSM states: `std_logic_vector(2 downto 0)` constants (e.g., `c_st_bus_idle := "011"`)
- Transfer status: `std_logic_vector(2 downto 0)` constants (`c_ongoing`, `c_transmitted`, `c_disturbed`, `c_lost_arb`, `c_aborted`)
- Frame format: `std_logic_vector(2 downto 0)` constants (`c_llc_fmt_cb`, `c_llc_fmt_ce`, `c_llc_fmt_fb`, `c_llc_fmt_fe`)
- Enums like `t_mac_frame_bit_name` are used only internally and on debug ports (simulation-only)

**Naming conventions:**
- Types: `t_` prefix (e.g., `t_can_mac_pcs_if_m2s`)
- Constants: `c_` prefix (e.g., `c_dominant`, `c_st_bus_idle`)
- Package: `pk_can_types` (not `can_types_pkg` - the package name differs from the filename)

---

## Directory Structure

```
src/                                  # Per-module folders (mirrors company layout)
├── can_types_p/
│   ├── hdl_src/can_types_pkg.vhd     # pk_can_types: core types, interface records, constants
│   └── hdl_tb/can_types_pkg_tb.vhd   # Package unit tests
├── can_timing_pkg/
│   └── hdl_src/can_timing_pkg.vhd    # Bit timing utilities, TDC calculation
├── can_mac_ser/
│   ├── hdl_src/can_mac_ser.vhd       # MAC serializer: LLC bytes -> serial bit stream
│   ├── hdl_tb/can_mac_ser_tb.vhd     # Serializer testbench
│   └── test_case/                    # GTKWave .gtkw save files (per-module)
├── can_mac_crc/
│   └── hdl_src/can_mac_crc.vhd       # CRC engine for CAN-FD (shared TX/RX, includes gen_crc)
├── can_mac_bs/
│   ├── hdl_src/can_mac_bs.vhd        # Bit stuffer with SBC generation (shared TX/RX)
│   └── hdl_tb/can_mac_bs_tb.vhd      # Bit stuffer testbench
├── can_llc/
│   └── hdl_src/can_llc.vhd           # LLC sub-layer (frame buffering, retransmission)
├── can_fce/
│   ├── hdl_src/can_fce.vhd           # Fault Confinement Entity
│   └── hdl_tb/can_fce_tb.vhd

can_bus_controller_fd/                # Company-format mirror (synced via scripts/sync_to_company.py)
├── can_types_p/                      # Same per-module layout with hdl_src/, hdl_tb/, test_case/
├── can_tb_p/                         # Testbench utility package
├── can_mac_bs/                       # Shared modules
├── can_mac_crc/                      # gen_crc stripped (company has it at ip_lib/gen_crc/)
├── can_mac_ser/
└── can_mac/                          # Unified MAC: can_mac_fsm.vhd + can_mac.vhd wrapper

scripts/                # Build and sync scripts
├── sync_to_company.py  # Local -> company format conversion
└── md_to_pdf.sh        # Report generation

mcp_tools/              # Model Context Protocol servers (extensible)
docs/                   # Documentation and standards reference
formal/                 # Formal verification .sby files and results
OsvvmLibraries/         # OSVVM simulation framework (external)
sim/                    # Generated simulation artifacts (gitignored)
verification_plan/      # Verification plan specification and tooling
```

---

## Build and Test Commands

### Prerequisites

Compile OSVVM libraries first:

```bash
cd OsvvmLibraries/osvvm && tclsh build.tcl
cd /path/to/beng_thesis
```

### Compilation

The full RTL chain must be compiled in dependency order. Packages first, then leaf modules, then wrappers:

```bash
ghdl -a --std=08 -fpsl --warn-no-vital-generic --warn-no-hide \
  -P./OsvvmLibraries/osvvm/VHDL_LIBS/GHDL-6.0.0-dev -P. \
  src/can_types_p/hdl_src/can_types_p.vhd \
  src/can_tb_p/hdl_src/can_tb_p.vhd \
  src/can_mac_bs/hdl_src/can_mac_bs.vhd \
  src/can_mac_crc/hdl_src/can_mac_crc.vhd \
  src/can_mac_ser/hdl_src/can_mac_ser.vhd \
  src/can_mac/hdl_src/can_mac_fsm.vhd \
  src/can_fce/hdl_src/can_fce.vhd \
  src/can_mac/hdl_src/can_mac.vhd \
  src/can_pcs/hdl_src/can_pcs.vhd \
  src/can_mac_pcs_fce/hdl_src/can_mac_pcs_fce.vhd \
  src/can_llc/hdl_src/can_llc.vhd \
  src/can_fd_controller/hdl_src/can_fd_controller.vhd \
  src/<module>/hdl_tb/<testbench>.vhd
```

After analysis, elaborate and run:

```bash
ghdl -e --std=08 -fpsl --warn-no-vital-generic --warn-no-hide \
  -P./OsvvmLibraries/osvvm/VHDL_LIBS/GHDL-6.0.0-dev -P. <entity_name>
ghdl -r --std=08 -fpsl --warn-no-vital-generic --warn-no-hide \
  -P./OsvvmLibraries/osvvm/VHDL_LIBS/GHDL-6.0.0-dev -P. <entity_name> \
  --stop-time=5ms
```

**Important**: If you modify `pk_can_types`, all previously compiled units become stale. You must re-analyze the entire chain before elaborating.

### Makefile (alternative)

```bash
make TB=src/can_types_p/hdl_tb/can_types_pkg_tb all          # Compile, run, open waveform
make TB=src/can_types_p/hdl_tb/can_types_pkg_tb compile run  # Compile and run (no waveform)
make clean                                                    # Remove artifacts
```

### Waveform Viewing

```bash
gtkwave sim/can_mac_pcs_fce_tb.ghw src/can_mac_pcs_fce/test_case/can_mac_pcs_fce_tb.gtkw
```

GHW format preserves record types and enum names for symbolic display.

---

## Verification Plan Management

ISO 11898-1:2015 CAN system requirements are tracked in `verification_plan/verification_plan.toml` - a structured TOML file with sequential numeric IDs organized by category and side. The file header documents all keys and valid values.

### Verification Plan File Format

**File**: `verification_plan/verification_plan.toml`
**Structure**: 118 requirements, sequential IDs (REQ-NNN), five layer values: LLC, MAC, PCS, FCE, system.
**Scope**: CAN Classic (CC) and CAN FD only - CB, CE, FB, and FE frames. CAN XL frames are strictly out of scope and must NOT be added to the verification plan.

Each entry has exactly these fields:

| Field | Values |
|-------|--------|
| `id` | `REQ-NNN` (sequential) |
| `source_clause` | ISO 11898-1 section (e.g. `§6.6.8`) |
| `original_wording` | Verbatim ISO text |
| `layer` | `LLC`, `MAC`, `PCS`, `FCE`, `system` |
| `side` | `transmitter`, `receiver`, `both` |
| `format_applicability` | `CB`, `CE`, `FB`, `FE` (comma-separated subset) |
| `observability` | `black_box`, `white_box` |
| `verification_method` | `simulation`, `code_inspection`, `coverage`, or comma-separated combination |
| `notes` | How it is verified; relevant caveats |
| `label` | PSL assertion label, TB procedure name, coverage ID, or RTL tag (blank until linked) |
| `file` | Target VHDL source file - TB for simulation/coverage, RTL for code_inspection (blank until linked) |

**Observability** is relative to the sub-module boundary named in `layer`:
- `black_box`: verified purely at the sub-module's ports from stimulus and config alone - no reference model needed.
- `white_box`: requires internal FSM state, FCE error state, bit-position counters, or a non-trivial reference computation (e.g. CRC polynomial, error counter arithmetic).

**Verification method**:
- `simulation`: verified by a TB assertion or check procedure; `label`/`file` point to the TB.
- `code_inspection`: verified by RTL code review; `label`/`file` point to the RTL source location.
- `coverage`: verified by coverage-driven stimulus sweeping a value range (e.g. DLC bins, data length threshold); `label`/`file` reference the coverage ID or bin set in the TB.
- Combinations (e.g. `simulation, coverage`) are valid when multiple methods apply to sub-claims within the same requirement.

**Layer `system`**: used for requirements whose behaviour is jointly owned by multiple sub-layers, or that inherently require two nodes on the shared bus (ACK overwrite, passive error flag coordination, bus re-integration). These are verified by the integration testbenches (`can_mac_pcs_fce_tb`, `can_llc_mac_pcs_fce_tb`).


### Verification Plan Management via MCP Server (Recommended)

Use the Verification Plan Manager MCP server for safe, atomic operations. The server handles validation, backup, and logging automatically.

**Setup (one-time):**

```bash
pip install -r mcp_tools/requirements.txt
```

**Available Tools** (use via Claude Code MCP integration):

```
query_requirements(layer, side, has_flags, observability, is_blank_label, is_blank_file)
get_requirement(req_id)
update_requirement(req_id, field, value)
bulk_update(field, value, layer, has_flags, observability, is_blank_label, is_blank_file)
delete_requirement(req_id)
renumber_requirements()
insert_requirement(layer, original_wording, side, source_clause, format_applicability, observability, notes)
get_statistics()
```

### Key Points

- **XL frames are out of scope** - do not add XL-related requirements
- **No internal observability** - all requirements must have a testable boundary effect
- All `label` and `file` fields are blank until linked to a TB assertion or procedure

---

## VHDL Source File Header

**RTL modules** use this header format:

```vhdl
--------------------------------------------------------------------------------
-- Title      : <Short descriptive title>
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : <filename>.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: <Concise description of the module's purpose and behavior.
--              Mention PSL assertions if the file contains them.>
--------------------------------------------------------------------------------
```

**Testbench files** use the company header format:

```vhdl
--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for <dut_name>.
--                  p_<name>_vc       - <Interface> <source|sink> VC (<short description>).
--                  p_<name>_checker  - <What it monitors>.
--                  p_test_ctrl       - Coverage-driven test sequencer.
--
-- Revision log:  Date:       Initial:  JIRA:
--                YYYY-MM-DD  XXXXX     [TRIT-NNNN] Description
--------------------------------------------------------------------------------------------------------------------------------------------------------------
```

Rules:
- RTL: Project line is always the report title, author is always `Mads Richardt`
- Testbench: Company copyright header, description lists processes with one-line summaries
- No ISO references in the header (those belong in PSL section comments or inline)
- Description should mention formal assertions if present
- Never write "PSL" after `--` in non-PSL comments (the `-fpsl` parser treats `-- psl` as a directive)
- Use `----` separators, never `====` (ghdl-yosys-plugin misinterprets `==` in comments)

---

## Code Style and Linting

**Tool**: VSG (VHDL Style Guide) v3.35.0

**Run linting:**
```bash
vsg -c vsg_config.yaml -f src/can_types_p/hdl_src/can_types_pkg.vhd
```

**VSG Configuration** (`vsg_config.yaml`):
- Disabled: Blank line enforcement for type/subtype/function/case/loop statements
- Disabled: `length_001` (allows lines up to 120 chars for long signal names)
- Otherwise: Standard VHDL-2008 conventions apply

## Testbench Structure

All testbenches follow a standard OSVVM-based structure. Use `can_mac_ser_tb.vhd` as the golden reference template.

### Infrastructure

Use OSVVM procedures for clock, reset, and timing:

```vhdl
-- Clock and reset (concurrent, non-terminating)
CreateClock(clk_i, c_clk_period);
CreateReset(rst_i, '1', clk_i, c_clk_period * 3);

-- In stimulus process: wait for reset, then drive
wait until rst_i = '0';
WaitForClock(clk_i);

-- Single and multi-cycle waits
WaitForClock(clk_i);
WaitForClock(clk_i, 5);
```

Rules:
- Declare `clk_i` without an initializer (let `CreateClock` handle it)
- Declare `rst_i` with `:= '1'` to cover the gap before `CreateReset` takes over
- Use `WaitForClock` instead of `wait for clk_period`
- Use `std.env.finish` to terminate simulation (required since `CreateClock` runs forever)

### Random Stimulus

Use OSVVM `RandomPType` with `DistBool` for weighted distributions:

```vhdl
variable rnd : RandomPType;
rnd.InitSeed(rnd'instance_name & to_string(now));

-- Weighted boolean distributions (both weights required)
rnd.DistBool((false => 95, true => 5))   -- 5% true
rnd.DistBool((false => 50, true => 50))  -- 50/50
rnd.DistBool((false => 25, true => 75))  -- 75% true
```

### PSL Assertions

- **White-box assertions** (using internal signals): keep in the DUT for formal verification
- **Black-box assertions** (using only port signals): duplicate in the TB for simulation verification
- PSL's temporal operators (SERE sequences, `|=>`, `[*N]`) are the right tool for sequence checking - don't rewrite them as VHDL state machines
- PSL in the TB follows the same formatting convention as in the DUT (see Formal Verification with PSL section)

### File Layout

1. Company header, libraries, entity (with `gc_TbTimeOut`, `gc_TbClkPeriod` generics)
2. Constants (coverage bins, check params)
3. DUT port signals and OSVVM signals (`test_id`, coverage IDs, `init_barrier`, `StreamRecType`)
4. Functions and procedures (declarative region)
5. `CreateClock` / `CreateReset`, `p_timeout`, `p_init` (with `WaitForBarrier`)
6. DUT instantiation
7. Verification Components (processes using `WaitForTransaction` / `StreamRecType`)
8. Continuous monitors (transfer status, error detection)
9. Test sequencer (`p_test_ctrl` - coverage-driven with `IsCovered` loop)
10. Black-box PSL assertions

### LLC Legacy Frame Format for Testbenches

The `can_llc` entity accepts a **71-byte legacy frame format** on the Avalon-ST user interface. All testbenches driving the top-level system must use this format:

- **Bytes 0-3**: ID bytes (right-aligned for 11-bit, full for 29-bit)
- **Byte 4**: `[6:4]` = FMT, `[3:0]` = DLC
- **Bytes 5-68**: Data (64 bytes, zero-padded)
- **Byte 69**: `[0]` = IDE
- **Byte 70**: `[2]` = BRS, `[1]` = ESI, `[0]` = RTR

Byte 0 has `sop = '1'`, byte 70 has `eop = '1'`. See `submit_and_verify` in `can_mac_pcs_fce_tb.vhd` for the reference implementation.

### ACK Injection Pattern

Testbenches that need to simulate a successful ACK must inject a dominant bit during the ACK slot. The correct pattern uses the `debug_bit_name_o` port:

```vhdl
-- Wait for FSM to reach ACK slot, then inject dominant
if (inject_ack and debug_bit_name = ack_bit) then
  bus_override    <= c_dominant;
  bus_override_en <= true;
  wait for nom_bit_time_clk_c * clk_period_c;
  bus_override_en <= false;
end if;
```

**Important**: `debug_bit_name` is a registered signal (one clock delay). Do NOT trigger on `crc_delimiter_bit` at `sp` - by the time the registered name equals `crc_delimiter_bit`, the sample point has already passed. Instead trigger on `ack_bit` which fires when the FSM has entered the ACK slot.

### Bus Loopback

For testbenches using `can_tx` as DUT, use zero-delay loopback:

```vhdl
rx_bus_i <= bus_override when bus_override_en else tx_bus_o;
```

Do NOT use propagation delay (`after Xns`) on the loopback unless the delay is shorter than the sample point offset within a bit time. A propagation delay longer than the bit time causes every transmitted bit to fail the bit error check.

---

## Mandatory RTL Optimization Rules

For HDL implementation and refactor work, the following guide is mandatory:
- `.claude/agent_guides/vhdl_rtl_optimization_style_v1.md`

Required patterns from this guide:
- Gate inactive counters/prescalers so they do not free-run when unused.
- Avoid `% mod` in hot sequential datapath logic; prefer bounded compare/subtract style.
- Use named local guard predicates in combinational FSM/control logic to reduce repeated conditions and improve traceability.
- Use signals (not process variables) for state that must persist across clock cycles. Process variables that retain values between rising edges will synthesize to registers anyway - using a signal makes the register intent explicit and readable.

---

## Architecture & Interfaces

### Pipeline Architecture

```
User -> can_llc -> can_mac -> can_pcs -> bus
                      |
               can_mac_ser   (LLC bytes -> serial bit stream)
               can_mac_fsm   (unified TX/RX FSM)
               can_mac_bs    (bit stuffer/destuffer)
               can_mac_crc   (CRC engine)
```

The `can_mac_pcs_fce` wrapper integrates `can_mac`, `can_pcs`, and `can_fce`.
The `can_fd_controller` top-level adds `can_llc` above that.

All inter-module interfaces use `std_logic`/`std_logic_vector` record types defined in `pk_can_types`.

### LLC Legacy Frame Format

The LLC user interface accepts the 71-byte legacy format described in the Testbench Structure section above. The `legacy_rtl` architecture of `can_llc_tx` converts this to the internal config_byte_0/config_byte_1/ID format consumed by the MAC serializer.

### Interface Direction Convention

Control/status interfaces (e.g., FCE) use **m2s/s2m** (master/slave) naming. Data-transfer interfaces that follow Avalon-ST source/sink semantics use **s2d/d2s** (source/destination) naming, where the source produces data and the destination consumes it.

### Key Interface Records

All defined in `pk_can_types` (`src/can_types_p/hdl_src/can_types_p.vhd`):

**MAC to PCS (`t_can_mac_pcs_if_m2s`):**
- `polarity: std_logic` - Bit polarity (c_dominant/c_recessive)
- `valid: std_logic` - Data valid
- `use_data_rate: std_logic` - Switch to data-phase bit rate
- `start_tdc: std_logic` - Begin TDC measurement

**PCS to MAC (`t_can_mac_pcs_if_s2m`):**
- `bus_polarity: std_logic` - Sampled bus polarity
- `sp: std_logic` - Sample Point strobe
- `ssp: std_logic` - Secondary Sample Point strobe
- `fifo_index: t_fifo_index_vec` - TDC FIFO read index

**MAC Serializer to FSM (`t_can_mac_ser_fsm_if_s2d`):**
- `data: std_logic` - Output polarity
- `valid: std_logic` - Data valid
- `llc_metadata: t_llc_metadata` - Cached frame metadata from LLC

**FSM to Serializer (`t_can_mac_ser_fsm_if_d2s`):**
- `transfer_status: std_logic_vector(2 downto 0)` - Frame status
- `ready: std_logic` - FSM ready for next bit

**FSM to/from Bit Stuffer (`t_can_mac_fsm_bs_if_m2s`, `t_can_mac_fsm_bs_if_s2m`):**
- Control and status signals between the TX FSM and the bit stuffer.

**FSM to/from CRC Engine (`t_can_mac_fsm_crc_if_m2s`, `t_can_mac_fsm_crc_if_s2m`):**
- Control and status signals between the TX FSM and the CRC engine.

**FSM to/from Deserializer (`t_can_mac_fsm_deser_if_s2d`, `t_can_mac_fsm_deser_if_d2s`):**
- Data-transfer interface between the RX FSM and the deserializer (s2d/d2s convention).

**FCE interface (`t_can_mac_fce_if_s2m`):**
- `error_passive_request: std_logic`
- `error_active_request: std_logic`
- `bus_off: std_logic`

### Polarity and Status Constants

```vhdl
-- Polarity (std_logic)
constant c_dominant  : std_logic := '0';
constant c_recessive : std_logic := '1';

-- Transfer status (std_logic_vector(2 downto 0))
constant c_ongoing     : std_logic_vector(2 downto 0) := "000";
constant c_transmitted : std_logic_vector(2 downto 0) := "010";
constant c_aborted     : std_logic_vector(2 downto 0) := "001";
constant c_lost_arb    : std_logic_vector(2 downto 0) := "100";
constant c_disturbed   : std_logic_vector(2 downto 0) := "110";

-- Frame format (std_logic_vector(2 downto 0))
constant c_llc_fmt_cb : std_logic_vector(2 downto 0) := "000"; -- Classic Basic
constant c_llc_fmt_ce : std_logic_vector(2 downto 0) := "100"; -- Classic Extended
constant c_llc_fmt_fb : std_logic_vector(2 downto 0) := "010"; -- FD Basic
constant c_llc_fmt_fe : std_logic_vector(2 downto 0) := "110"; -- FD Extended
```

### Debug Ports on can_tx

The top-level `can_tx` entity exposes debug ports for testbench observability:

```vhdl
debug_mac_to_pcs_o : out t_can_mac_pcs_if_m2s;
debug_pcs_to_mac_o : out t_can_mac_pcs_if_s2m;
debug_ack_error_o  : out std_logic;
debug_form_error_o : out std_logic;
debug_data_exit_o  : out std_logic;
debug_pcs_state_o  : out std_logic_vector(1 downto 0);
debug_fsm_state_o  : out std_logic_vector(2 downto 0);
debug_bit_name_o   : out t_mac_frame_bit_name  -- enum (simulation-only)
```

`debug_bit_name_o` uses the `t_mac_frame_bit_name` enum type. This is acceptable on a debug port since debug ports are simulation-only and optimized away in synthesis.

---

## Core Modules

### can_types_pkg.vhd (pk_can_types)

Central package defining all types, interface records, and constants. All interface records use std_logic/std_logic_vector only.

**Key contents:**
- Polarity constants (`c_dominant`, `c_recessive`)
- Transfer status constants
- Frame format constants
- Interface record types (20+ `t_can_*` records)
- Frame position record (`t_mac_frame_position_vec`) for frame parameter caching
- `t_mac_frame_bit_name` enum (internal use and debug ports only)
- `t_mac_frame_bit` record (internal frame bit representation)
- Reset constants for all interface records
- `c_llc_id_field_width` constant (ID field width)
- CRC vector represented as `std_logic_vector(c_crc_21_length - 1 downto 0)` (no `t_crc_vector` subtype)
- Section 10: TB Utility Functions - `f_calc_can_crc` and `extract_metadata` (testbench use only)

### can_timing_pkg.vhd

Bit timing utilities.

**Key functions:**
- `should_use_tdc()` - Determine if TDC needed based on bit timing
- `calculate_fifo_delay_index()` - TDC FIFO index calculation

### can_mac_fsm_tx.vhd (Frame Transmission FSM)

8-state FSM coordinating frame transmission. States encoded as `std_logic_vector(2 downto 0)`:

| Encoding | State | Description |
|----------|-------|-------------|
| `"000"` | bus_reintegration | Wait for 11 consecutive recessive bits |
| `"001"` | intermission | 3-bit inter-frame spacing |
| `"010"` | suspend_transmission | Error-passive extra wait |
| `"011"` | bus_idle | Ready for new frame |
| `"100"` | transmitting_frame | Active frame transmission |
| `"101"` | active_error_flag | 6 dominant + 8 recessive delimiter |
| `"110"` | passive_error_flag | 6 recessive + 8 recessive delimiter |
| `"111"` | overload_flag | Overload handling |

### can_llc.vhd (LLC Sub-layer)

Accepts the 71-byte legacy frame format from the user, converts it to the internal format, buffers it, and drives the MAC TX byte stream. Handles automatic retransmission on `c_lost_arb` / `c_disturbed` and hold-and-resume across bus-off recovery windows.

---

## Test Coverage

| Testbench | Tests | Description |
|-----------|-------|-------------|
| `can_types_pkg_tb` | 127 | Package utilities, frame structures, all 4 formats |
| `can_mac_ser_tb` | 5 | Serializer with ready/valid handshaking |
| `can_mac_bs_tb` | - | Bit stuffer with PSL assertions |
| `can_fce_tb` | - | Fault confinement entity |
| `can_mac_pcs_fce_tb` | 4 | Integrated MAC+PCS+FCE: normal TX/RX, delay sweep, lost arb, bus-off recovery |

---

## Important Code Patterns

### Bit Slice Constants (Critical)

Always use explicit `_start` and `_end` for multi-bit fields:

```vhdl
constant c_llc_frame_config_byte_0_format_start : integer := 7;   -- bit 7
constant c_llc_frame_config_byte_0_format_end   : integer := 5;   -- bit 5
-- Extract as: config_byte(format_start downto format_end)
```

**Why**: Prevents off-by-one errors and makes bit positions explicit.

### Avalon-ST Handshaking

Correct pattern for ready/valid:

```vhdl
-- State owns its ready signal
when my_state =>
  output_port.ready <= '1';  -- Set while in this state
  if (input_port.valid = '1') then
    -- Transfer happens when both ready and valid
    register <= input_port.data;
    state_reg <= next_state;
  end if;
-- Next cycle: new state's ready signal applies
```

### Strobed Sampling (PCS Interface)

SP/SSP strobes pulse once per sample point:

```vhdl
-- PCS continuously drives polarity
pcs_to_mac.bus_polarity <= current_bus_state;
-- Strobes are single-cycle pulses
pcs_to_mac.sp  <= '1' when sample_point_reached else '0';
pcs_to_mac.ssp <= '1' when secondary_sample_point_reached else '0';
```

MAC latches polarity on strobe pulses, handles TDC via SSP timing.

---

## Debugging Guide

1. **View waveforms**: Add `--wave=sim/name.ghw` to ghdl -r command, then `gtkwave sim/name.ghw`
2. **Check test results**: OSVVM reports all pass/fail to console (look for `DONE PASSED` or `DONE FAILED`)
3. **Record inspection**: GHW format shows record fields and enum names; VCD cannot
4. **FSM tracing**: Use `debug_fsm_state_o` (3-bit vector) and `debug_bit_name_o` (enum) for symbolic display
5. **Linting**: Run VSG before commits
6. **Stale compilation**: If you get "is obsoleted by package" errors, re-analyze the full chain starting from `can_types_pkg.vhd`

---

## Formal Verification with PSL

### Toolchain

Formal verification uses **SymbiYosys** with **ghdl-yosys-plugin** (synthesis backend) and **z3** SMT solver. PSL assertions are embedded in VHDL source files using `-- psl` comment syntax and picked up by `ghdl -fpsl`.

### GHDL PSL Operator Support

**Simulation-compatible FL operators:**
- `always`, `never`, `next`, `next[n]`, `until`, `before`, `eventually!`
- SERE sequences: `{...}`, `|=>`, `|->`, repetition

**Synthesis-only functions (formal flow via ghdl-yosys-plugin only, NOT available in simulation):**
- `prev()` - previous cycle value
- `rose()`, `fell()` - edge detection
- `stable()` - signal stability check
- `onehot()`, `onehot0()` - encoding validation

**Not supported in GHDL:**
- `once` - not implemented
- `ended` - not implemented
- `forall` / `for` - quantifiers not implemented
- PSL `vunit` - parses but crashes on code generation (not usable)
- Multi-clock properties - only one clock per directive

### PSL Syntax Rules

- Every PSL assertion must end with a semicolon: `-- psl name : assert always (...);`
- Labels use format: `-- psl label_name : assert always ...;`
- Do not duplicate the `assert` keyword: `-- psl assert foo : assert ...` is invalid
- Record field access works (e.g., `bs_o.sbc(3)`)
- String literal comparison with record fields may fail in SERE `{...}` context - use individual bit comparisons instead
- Integer signals compare to integer literals (`consecutive_count = 0`), vector signals compare to string literals (`stuff_count = "000"`)
- Multi-line PSL: only the first line needs `-- psl`, continuation lines use `--` only
- Every assertion must have a `report` string describing what went wrong

### PSL Formatting Convention

VSG cannot enforce PSL formatting (assertions are inside comments). Follow this convention manually:

```vhdl
--------------------------------------------------------------
-- psl psl_1 : assert always
-- { rst_i = '1' or bs_i.start }
-- |=>
-- { consecutive_count = 0 and
-- last_polarity = recessive and
-- stuff_count = "000" }
-- report "Reset did not clear all registers to default values";
--------------------------------------------------------------
-- psl psl_2 : assert always
-- { reset_done }
-- |->
-- { consecutive_count <= stuff_width_c and
-- bs_o.sbc(0) = ( bs_o.sbc(3) xor bs_o.sbc(2) xor bs_o.sbc(1) ) }
-- report "Invariant violated: count bounded or SBC parity";
--------------------------------------------------------------
```

Rules:
- **Naming**: `psl_N` (sequential per file). The verification plan links filename + `psl_N` to requirements. No descriptive label names needed.
- **Combine assertions** with the same antecedent into a single assertion using `and` in the consequent.
- `-- psl` declaration and `assert always` on the first line
- Always use SERE braces `{...}` around antecedent and consequent
- Use `|->` for same-cycle checks, `|=>` for next-cycle checks (never bare `->`)
- `|->` or `|=>` on its own line, no indent
- `and` at the **end** of each continuation line (trailing `and`, not leading)
- `report` on its own line, no indent
- Single `------` separator line between assertions (no blank lines between separators)
- Section header (`-- ===========================================================`) before default clock, assumptions, and assertions blocks

### Design Patterns

- **Use shadow signals instead of `prev()`** for comparing current vs previous values. Although `prev()` works in the formal flow (ghdl-yosys-plugin), it is synthesis-only and not available during GHDL simulation. Shadow signals ensure assertions are checked in both simulation and formal verification. Mark shadow signals with `-- PSL-only:` comments. Synthesis tools optimize them away since they drive no output.
- **PSL-only signals** used for assertions (all optimized away by synthesis):
  - `reset_done` - true one cycle after reset deasserts (guards assertions from firing before valid state)
  - `stuff_count_prev`, `consec_count_prev` - shadow registers for increment/hold checks
- **Same-cycle `|->` vs next-cycle `|=>`**: Use `{...} |-> {...}` for invariants (e.g., parity check) where antecedent and consequent are checked in the same cycle. Use `{...} |=> {...}` for cause-effect relationships where inputs at cycle N produce registered outputs at cycle N+1. Never use bare `->`.
- **Guard `|=>` assertions against reset/start**: If `rst_i` or `bs_i.start` can fire between antecedent and consequent, add `rst_i = '0' and not bs_i.start` to the antecedent.

### Running Formal Verification

```bash
sby formal/can_mac_bs.sby bmc      # Bounded model check (fast falsification)
sby formal/can_mac_bs.sby prove    # K-induction (exhaustive proof)
sby formal/can_mac_bs.sby          # Both tasks
sby -f formal/can_mac_bs.sby prove # Force re-run (overwrite previous results)
```

---

## ISO 11898-1 Standard Reference

Implementation strictly follows **ISO 11898-1:2015** (Road vehicles - CAN - Data link layer and physical signaling).

**Key Sections:**
- **8.1**: CAN frame overview
- **8.2**: Data frame format (CC basic/extended)
- **8.3**: Remote frame format
- **8.4**: CAN FD frame format
- **8.5**: Bit stuffing rules (5-in-a-row, fixed stuff bits)
- **8.5.4**: CRC field calculation
- **8.5.6**: ACK slot encoding
- **Table 13**: Bit timing configuration ranges

**TDC Reference**: Section 7.3.4 (Transmitter Delay Compensation)

---

## External Dependencies

- **OSVVM**: Open-Source VHDL Verification Methodology (alert/report framework)
- **GHDL**: Open-source VHDL compiler and simulator
- **GTKWave**: Waveform viewer
- **VSG**: VHDL Style Guide linter

See `OsvvmLibraries/README.md` for OSVVM build and usage.

---

## Markdown and Code Style

**VHDL Style:**
- Use `c_dominant`/`c_recessive` std_logic constants (not polarity_t enum)
- All entity ports use `std_logic`/`std_logic_vector` only
- Explicit bit slice constants with `_start`/`_end` suffixes
- Comments for non-obvious logic
- Shift register (not mux) for sequential bit output

**Documentation:**
- Max line length: 120 characters
- Code blocks: Always specify language (``` vhdl, ``` bash)
- Bold (`**text**`) for emphasis, not underscores

**Writing style (emails, reports, prose):**
- Limit the use of semicolons. Prefer periods where possible.
- Do not use em dashes. Use plain hyphens (-) instead.
- Use internal cross-references (`@sec:`, `@fig:`, `@tbl:`) to connect related concepts across sections. Cross-references integrate the narrative, avoid redundancy, and give the reader a clear path to supporting detail. Every figure and table must be referenced at least once in the main text, and introductory paragraphs should reference the diagrams or tables contained in their section.

### Markdown Report Format (for `scripts/md_to_pdf.sh`)

- Use Pandoc markdown with YAML front matter, including:
  - `bibliography: references.bib`
  - `csl: ieee.csl`
  - `link-citations: true`
- Use heading IDs for cross-references and section export:
  - Top-level sections: `# Title {#sec:topic-name}`
  - Do not hardcode numbering in headings. Pandoc applies numbering.
- Reference sections with Pandoc crossref syntax:
  - `@sec:topic-name`
- Figures:
  - Use figure IDs and captions so `pandoc-crossref` can label them:
    - Mermaid: ```` ```{.mermaid #fig:my-figure caption="My caption"} ``` ````
    - Image: `![My caption](img.png){#fig:my-figure}`
  - Reference figures as `@fig:my-figure`.
- Tables:
  - Add table caption lines with table IDs:
    - `: Caption text. {#tbl:my-table}`
  - Reference tables as `@tbl:my-table`.
- Wide tables:
  - Wrap wide table blocks in fenced div class `.landscape-tables`:
    - `::: {.landscape-tables}` ... `:::`
- TOC:
  - Prefer Pandoc-generated TOC (script handles TOC generation).
- Section selection (`--section`):
  - Best reliability comes from `sec:` IDs in headings.
  - Aliases like `design_and_architecture` are supported.
- Mermaid `stateDiagram-v2` styling:
  - Mark the reset/initial state with a thick outline using `classDef` and a separate `class` statement.
  - Do **not** use `:::` inline on the `state` definition line (it breaks label rendering).
  - Do **not** use `[*] -->` for the initial state arrow; the thick outline replaces it.
  - Example:
    ```
    stateDiagram-v2
      classDef reset stroke:#000,stroke-width:3px

      state "**my_initial_state**<br/>─────────<br/>• Description" as s0
      class s0 reset

      s0 --> s1 : event
    ```
