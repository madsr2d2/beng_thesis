# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a B.Eng thesis project implementing a **full CAN (Controller Area Network) node** with both TX and RX pipelines in VHDL-2008, following the **ISO 11898-1:2015 standard**. The project includes:

- Core CAN/CAN-FD frame structure and utilities (`can_pkg.vhd`)
- MAC layer transmit serializer (`tx_mac_ser.vhd`)
- MAC layer receive deserializer and processing
- Bit stuffing logic for CAN protocol (`bit_stuffer.vhd`, `bit_stuffer_fd.vhd`)
- Comprehensive unit tests (29 tests in can_pkg_tb, 5 in tx_mac_ser_tb)
- GHDL simulator integration with OSVVM library framework
- GTKWave waveform viewer integration

**Key Dependencies**: GHDL compiler, OSVVM libraries, VSG linter

**Standards Reference**: `docs/md_out/ISO_11898_1_CAN_bus_link/ISO_11898_1_CAN_bus_link.md` (ISO 11898-1:2015) - searchable markdown version

---

## Directory Structure

```
src/                    # Design and testbench VHDL files
├── can_pkg.vhd         # Core CAN definitions, types, utility functions
├── can_pkg_tb.vhd      # Unit tests (29 tests, all passing)
├── tx_mac_ser.vhd      # MAC serializer - converts LLC bytes to CAN bits
├── tx_mac_ser_tb.vhd   # Serializer testbench (5 tests, all passing)
├── tx_mac.vhd          # Top-level MAC transmitter wrapper
├── tx_mac_err.vhd      # Error handling module (placeholder)
├── tx_mac_fsm.vhd      # FSM state machine (placeholder)
├── bit_stuffer.vhd     # Bit stuffing for CAN 2.0
├── bit_stuffer_fd.vhd  # Bit stuffing for CAN-FD
├── shift_reg.vhd       # Shift register utility
└── crc_fd.vhd          # CRC calculation for CAN-FD

mcp_tools/              # Model Context Protocol servers (extensible)
├── __init__.py         # Package initialization
├── requirements.txt    # MCP tools dependencies (mcp, tomlkit)
├── verification_plan_manager.py  # Verification plan TOML management server
└── [future tools]      # Additional MCP servers (analysis, simulation, etc.)

gtk_wave/               # GTKWave configuration files
docs/                   # Documentation and standards reference
├── md_out/              # Searchable markdown versions of standards (ISO 11898-1, etc.)
OsvvmLibraries/         # OSVVM simulation framework (external)
sim/                    # Generated simulation artifacts
verification_plan/      # Verification plan specification and tooling
├── verification_plan.toml   # 122 ISO 11898-1:2015 requirements (CC/FD)
└── verification_plan_table.py # Export to HTML/Markdown tables
```

---

## Build and Test Commands

### Prerequisites

Compile OSVVM libraries first:

```bash
cd OsvvmLibraries/osvvm && tclsh build.tcl
cd /path/to/beng_thesis
```

### Common Commands

**Run all tests for a testbench:**
```bash
make TB=src/can_pkg_tb all          # Run can_pkg tests
make TB=src/tx_mac_ser_tb all       # Run tx_mac_ser tests
```

**Build only (no simulation):**
```bash
make TB=src/can_pkg_tb compile
```

**Run simulation without waveforms:**
```bash
make TB=src/can_pkg_tb compile run
```

**View waveforms after simulation:**
```bash
gtkwave sim/can_pkg_tb.ghw gtk_wave/can_pkg_tb.gtkw
```

**Clean generated files:**
```bash
make clean
```

---

## Verification Plan Management

ISO 11898-1:2015 CAN system requirements are tracked in `verification_plan/verification_plan.toml` — a structured TOML file with sequential numeric IDs organized by category and side. The file header documents all keys and valid values.

### Verification Plan File Format

**File**: `verification_plan/verification_plan.toml`
**Structure**: 123 requirements (IDs 001–123), sequential with no gaps
**Scope**: CAN Classic (CC) and CAN FD only — CB, CE, FB, and FE frames. CAN XL frames are strictly out of scope and must NOT be added to the verification plan.

**Categories**: FRM (frame), ERR (error), TMG (timing), CRC (checksum)
**Sides**: TX (transmitter), RX (receiver)
**Formats**: CB (Classic Basic), CE (Classic Extended), FB (FD Basic), FE (FD Extended)
**Priorities**: critical, high, medium, low
**Verification**: simulation, coverage, waveform, assertion
**Status**: verified, implemented, unverified, diagnostic
**Observability**: external, derived, internal (layer-level black-box testability axis)

  Observability is defined **relative to the layer's own canonical interface boundary**
  (not the top-level CAN node). The canonical interfaces are defined in
  `docs/canonical_layer_interfaces.md` (ISO 11898-1:2015 service primitives).

  - `external`: postcondition is fully observable at the layer's own boundary, either as
    a named primitive parameter, or as the *timing* of a primitive call where that timing
    is fully determined by configuration generics and stimulus inputs known to the testbench.
    *Example: sample point timing — when PCS_Data.Indicate fires equals brp×(sync_seg +
    prop_seg + phase_seg1), all config generics, so testbench can predict and verify it.*
  - `derived`: effect manifests at the layer boundary but verifying it requires knowledge
    of a non-trivial internal algorithm beyond reading config generics and measuring timing.
    *Example: CRC content — bits appear in Output_Unit calls but correctness requires
    applying the specific polynomial to the data.*
  - `internal`: postcondition is a structural definition, a constraint on valid config
    inputs, or has no manifestation at any layer boundary even indirectly.
    *Example: "Phase_Seg2 shall be ≥ IPT + SJW" — constrains what configurations are
    valid, not what the layer outputs for a given valid configuration.*

### Verification Plan Management via MCP Server (Recommended)

Use the Verification Plan Manager MCP server for safe, atomic operations. The server handles validation, backup, and logging automatically.

**Setup (one-time):**

```bash
pip install -r mcp_tools/requirements.txt
```

**Start the MCP server:**

```bash
python -m mcp_tools.verification_plan_manager
```

**Available Tools** (use via Claude Code MCP integration):

```
query_requirements(category, side, status, priority, verification)
  → Returns matching requirements with IDs
  Example: Query all unverified CRC requirements
    category="CRC" status="unverified"

update_requirement(req_id, field, value)
  → Update single requirement field atomically
  Example: Set requirement 012 status to verified
    req_id="012" field="status" value="verified"

bulk_update(field, value, category, side, status, priority, verification)
  → Update multiple requirements matching filters
  Example: Set all critical requirements target_module to tx_mac_ser.vhd
    field="target_module" value="tx_mac_ser.vhd" priority="critical"

delete_requirement(req_id)
  → Delete requirement and auto-renumber remaining IDs
  Example: Delete requirement 011
    req_id="011"
  Result: Requirements renumbered 012→011, 013→012, etc.

renumber_requirements()
  → Renumber all requirements sequentially (fix ID gaps)

get_statistics()
  → Get counts by category, side, status, priority
```

**Key Benefits:**

✅ **Atomic operations** — backup created, changes validated before write
✅ **Auto-renumbering** — delete/renumber combined, no manual steps
✅ **Logging** — all changes logged with timestamp and details
✅ **Type safety** — field validation, prevents corruption
✅ **No ad-hoc scripts** — consistent, versioned operations

### Legacy: Command-line Tools

For direct CLI access without MCP:

**Query requirements** (Python + tomllib):
```python
import tomllib
with open('verification_plan/verification_plan.toml', 'rb') as f:
    data = tomllib.load(f)
frm = {k: v for k, v in data['requirements'].items() if v['category'] == 'FRM'}
```

**Delete via script:**
```bash
python verification_plan/verification_plan_table.py --delete 011
```

**Renumber via script:**
```bash
python verification_plan/verification_plan_table.py --renumber
```

### Exporting Verification Plan as Tables

```bash
# HTML table with sorting and color-coded status/priority (default)
python verification_plan/verification_plan_table.py --toml verification_plan/verification_plan.toml

# HTML to specific file
python verification_plan/verification_plan_table.py --toml verification_plan/verification_plan.toml --html table.html

# Markdown table
python verification_plan/verification_plan_table.py --toml verification_plan/verification_plan.toml --markdown table.md
```

### Key Points

- **Use Python (`tomllib`) for reading**, regex for bulk field updates
- **Use `--delete` to remove requirements** — never delete by hand
- **Use `--renumber` to fix ID gaps** after manual edits
- **IDs are sequential** (001–NNN) with no gaps; the script maintains this invariant
- **XL frames are out of scope** — do not add XL-related requirements
- **All keys and valid values** are documented in the `verification_plan.toml` header comment

---

## MCP Tool Configuration

### Overview

MCP servers are located in `mcp_tools/` for easy discovery and extensibility. Each tool is a standalone Python server that handles a specific domain (verification plan, simulation analysis, coverage reporting, etc.).

### Setup

**Install dependencies (one-time):**

```bash
pip install -r mcp_tools/requirements.txt
```

### Claude Code Integration

**Auto-discovery (Recommended):**

Claude Code automatically loads `.mcp.json` from the project root. The configuration is in `.mcp.json`:

```json
{
  "mcpServers": {
    "verification_plan": {
      "type": "stdio",
      "command": "python",
      "args": ["-m", "mcp_tools.verification_plan_manager"],
      "env": {
        "PYTHONPATH": "${PWD}"
      }
    }
  }
}
```

Claude Code discovers and loads this automatically when opening the project — no manual setup required. Once loaded, the MCP tools appear as callable tools alongside Bash, Read, Write, etc.

### Available Tools

#### verification_plan_manager

**Purpose**: Safe, atomic operations on verification_plan.toml

**Tools provided**:
- `query_requirements` — Filter by category, side, status, priority, verification
- `update_requirement` — Update single field with validation
- `bulk_update` — Update multiple requirements matching filters
- `delete_requirement` — Delete and auto-renumber
- `renumber_requirements` — Fix ID gaps
- `get_statistics` — Count by category/side/status/priority

**Example usage**:
```
Query all unverified CRC requirements
Call: query_requirements(category="CRC", status="unverified")

Set all critical requirements to target_module = "tx_mac_ser.vhd"
Call: bulk_update(field="target_module", value="tx_mac_ser.vhd", priority="critical")

Delete requirement 011 and renumber
Call: delete_requirement(req_id="011")
```

### Adding New MCP Tools

**Pattern** (add to `mcp_tools/`):

1. Create `mcp_tools/my_tool.py`
2. Implement using Claude MCP SDK
3. Add to settings.json mcpServers
4. Update `mcp_tools/__init__.py` documentation

**Example**:
```python
# mcp_tools/analysis_server.py
from mcp.server import Server
import logging

logger = logging.getLogger(__name__)
server = Server("analysis")

@server.list_tools()
async def list_tools():
    return [Tool(...)]

@server.call_tool()
async def call_tool(name: str, arguments: dict):
    # Implementation
    pass

if __name__ == "__main__":
    import asyncio
    asyncio.run(server.main())
```

### Benefits

✅ **Centralized** — All tools in one folder, easy to discover
✅ **Extensible** — Add new tools without modifying core code
✅ **Safe** — MCP servers enforce type safety, validation, logging
✅ **Auditable** — All changes logged with timestamps
✅ **Isolated** — Each tool has its own dependencies and scope

### Makefile Details

- **Compilation order**: Packages → leaf modules → dependent modules → mac_tx (last)
- **GHDL flags**: `--std=08` (VHDL-2008), includes OSVVM library path
- **Simulation time**: Default 2µs (configurable via `STOP_TIME`)
- **Waveform format**: GHW (preserves record types and enums)

---

## VHDL Source File Header

All VHDL source files must use this header format:

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

Rules:
- `=====` separator lines (not `-----`)
- Project line is always the report title
- Author is always `Mads Richardt`
- No ISO references in the header (those belong in PSL section comments or inline)
- Description should mention formal assertions if present
- Never write "PSL" after `--` in non-PSL comments (the `-fpsl` parser treats `-- psl` as a directive)
- Use `----` separators, never `====` (ghdl-yosys-plugin misinterprets `==` in comments)

---

## Code Style and Linting

**Tool**: VSG (VHDL Style Guide) v3.35.0

**Run linting:**
```bash
vsg -c vsg_config.yaml -f src/can_pkg.vhd
```

**VSG Configuration** (`vsg_config.yaml`):
- Disabled: Blank line enforcement for type/subtype/function/case/loop statements
- Disabled: `length_001` (allows lines up to 120 chars for long signal names)
- Otherwise: Standard VHDL-2008 conventions apply

## Mandatory RTL Optimization Rules

For HDL implementation and refactor work, the following guide is mandatory:
- `.claude/agent_guides/vhdl_rtl_optimization_style_v1.md`

Required patterns from this guide:
- Gate inactive counters/prescalers so they do not free-run when unused.
- Avoid `% mod` in hot sequential datapath logic; prefer bounded compare/subtract style.
- Use named local guard predicates in combinational FSM/control logic to reduce repeated conditions and improve traceability.
- Use signals (not process variables) for state that must persist across clock cycles. Process variables that retain values between rising edges will synthesize to registers anyway — using a signal makes the register intent explicit and readable.

---

## Architecture & Interfaces

### LLC Frame Format

The **LLC (Logical Link Control) Frame** is the interface between the User layer and the MAC layer. This project supports both Classic CAN and CAN-FD using a unified frame format that is **backward compatible**.

**Frame Structure** (per `docs/report.md`):

- **Bytes 0–3**: Identifier bytes (11-bit base ID for Classic, 29-bit extended ID for Extended format)
- **Byte 4**: Format and DLC byte:
  - `[7]`: Reserved (0)
  - `[6:4]`: **FMT** field (3-bit frame format indicator)
  - `[3:0]`: **DLC** (Data Length Code, 0–15)
- **Bytes 5–68**: Data field (0–64 bytes, maximum 64 for CAN-FD)
- **Byte 69**: Control flags:
  - `[7:1]`: Reserved (0)
  - `[0]`: **IDE** (Identifier Extension) — must match format (0 for CB/FB, 1 for CE/FE)
- **Byte 70**: Additional flags:
  - `[7:3]`: Reserved (0)
  - `[2]`: **BRS** (Bit Rate Switch, CAN-FD only)
  - `[1]`: **ESI** (Error State Indicator, CAN-FD only)
  - `[0]`: **RTR** (Remote Transmission Request)

**FMT Encoding**:

| FMT Code | Format | IDE | Max Bytes |
|----------|--------|-----|-----------|
| `000` | Classic Basic (CB) | 0 | 8 |
| `100` | Classic Extended (CE) | 1 | 8 |
| `010` | FD Basic (FB) | 0 | 64 |
| `110` | FD Extended (FE) | 1 | 64 |

**Backward Compatibility**:
- Implementations that only support Classic frames can ignore the FMT bits and treat all frames as Classic.
- Implementations supporting CAN-FD use the FMT field to distinguish frame types without affecting the existing ID and data field structure.

**ID Byte Mapping** (reference `src/can_pkg.vhd` for detailed extraction):

- **Classic Basic (CB)**: Base 11-bit ID in Bytes 2–3
  - Byte 2: `00000` + `ID[10:8]`
  - Byte 3: `ID[7:0]`
- **Classic Extended (CE)**: Extended 29-bit ID in Bytes 0–3
  - Byte 0: `000` + `ID[28:24]`
  - Byte 1: `ID[23:16]`
  - Byte 2: `ID[15:8]`
  - Byte 3: `ID[7:0]`

### Layer Boundary: LLC → MAC Domain

**Key Design Decision:**
- **LLC layer** (Logical Link Control): Operates with `std_logic` (0/1 bits)
- **MAC layer** (Media Access Control): Operates with `polarity_t` (dominant/recessive)

This provides **type safety** and **semantic clarity** - MAC code explicitly reasons about CAN polarities.

### Core Data Types

**`polarity_t` enum** (CAN domain):
```vhdl
type polarity_t is (dominant, recessive, unknown);
```

**`bit_t` record** (position + polarity):
```vhdl
type bit_t is record
  position : integer;
  polarity : polarity_t;
end record bit_t;
```

**`mac_frame_bit_t` record** (complete frame bit):
```vhdl
type mac_frame_bit_t is record
  polarity : polarity_t;       -- Dominant/recessive
  bit_name : mac_frame_bit_name_t;  -- SOF, base_id, fdf, crc, etc.
end record mac_frame_bit_t;
```

### Interface Definitions

**MAC to PCS (`mac_to_pcs_if_t`):**
- `frame_bit: mac_frame_bit_t` - Bit with context (name, polarity)
- `valid: std_logic` - Data valid
- `ready: std_logic` - PCS ready to accept

*Purpose*: PCS uses bit context for delay calculations (TDC compensation).

**PCS to MAC (`pcs_to_mac_if_t`):**
- `polarity: polarity_t` - Current bus polarity (continuously driven)
- `sp: std_logic` - Sample Point strobe (pulse when MAC should sample for SP)
- `ssp: std_logic` - Secondary Sample Point strobe (pulse for SSP)

*Purpose*: PCS drives bus signal; strobes tell MAC when to sample.

**MAC Serializer to FSM (`tx_mac_ser_to_fsm_if_t`):**
- `data: polarity_t` - Output polarity (MAC domain)
- `valid: std_logic` - Data valid
- `frame_info: llc_frame_info_t` - Frame configuration

**FSM to Serializer (`tx_mac_fsm_to_ser_if_t`):**
- `transfer_status: transfer_status_t` - Frame transmission status
- `ready: std_logic` - FSM ready for next bit

---

## Core Modules

### can_pkg.vhd (Central Package)

**Responsibilities:**
- Type definitions (polarity_t, bit_t, can_format_t, etc.)
- CAN FD bit timing constants (per ISO Table 13)
- Frame structure utilities
- TDC (Transmitter Delay Compensation) determination

**Key Functions:**
- `get_frame_info()` - Extract format, DLC, flags from config bytes
- `get_next_mac_frame_bit()` - Return next frame bit for serialization
- `should_use_tdc()` - Determine if TDC needed based on bit timing
- `bit_to_polarity()` - Convert std_logic to polarity_t
- `polarity_to_bit()` - Convert polarity_t to std_logic

**CAN Wire Frame Structure** (per ISO 11898-1:2015 — the format transmitted on the bus):

The serializer (`tx_mac_ser`) converts LLC frame bytes into this wire format:
- **SOF** (1 bit) - Start of Frame
- **Arbitration** (11-bit or 29-bit ID based on format, plus IDE/RTR flags)
- **Control** (DLC, FDF/BRS/ESI for CAN-FD)
- **Data** (0–64 bytes)
- **CRC** + Delimiter (Cyclic Redundancy Check)
- **ACK** + Delimiter (Acknowledgment slot)
- **EOF** (7 bits) - End of Frame

See `docs/report.md` sections 6.2–6.4 for detailed LLC frame format and the mapping between LLC interface bytes and wire frame fields.

### tx_mac_ser.vhd (MAC Serializer)

**Purpose**: Convert LLC bytes to serial CAN bit stream

**Architecture**: 3-state FSM
- `load_config_byte_0`: Accept frame format/flags
- `load_config_byte_1`: Accept DLC
- `load_llc_frame_byte`: Accept data bytes, output MSB immediately
- `shift_out_bits`: Shift remaining 7 bits, then fetch next byte

**Interfaces:**
- LLC (Avalon-ST source): Receives config + data bytes
- FSM (ready/transfer_status): Bidirectional control
- Output: Serial bits (polarity_t) with valid signal

**Key Design:**
- Each state owns its `ready` signal
- Transition defaults handle state changes cleanly
- Shift register for serial extraction

### can_pkg_tb.vhd (Unit Tests)

**Test Coverage** (29 tests):
1. CAN Classic Basic format (SOF, arbitration, control, data, CRC, ACK, EOF)
2. CAN Classic Extended format (with extended ID)
3. CAN FD Basic format (FDF, BRS bits)
4. CAN FD Extended format
5. Stuff bit handling (fixed stuff bits)
6. SBC bit extraction
7. CRC bit extraction
8. Arbitration lost detection
9. TDC determination (5 tests)

**Test Pattern**: Process-based, run-once with assertions

### tx_mac_ser_tb.vhd (Serializer Tests)

**Test Coverage** (5 tests):
1. Config byte loading (Avalon-ST handshake)
2. Data byte shifting (8 bits per byte)
3. Multiple byte transmission
4. Frame termination on status change
5. Ready/Valid handshaking

**Test Pattern**: Clock-driven stimulus/response with OSVVM alerts

---

## Important Code Patterns

### Bit Slice Constants (Critical)

Always use explicit `_start` and `_end` for multi-bit fields:

```vhdl
constant format_start_c : integer := 7;
constant format_end_c   : integer := format_start_c - (format_width_c - 1);
-- Extract as: config_byte(format_start_c downto format_end_c)
```

**Why**: Prevents off-by-one errors and makes bit positions explicit.

### Layer Conversion Pattern

Convert from LLC (std_logic) to MAC (polarity_t) using helper:

```vhdl
-- In tx_mac_ser: read from LLC byte
tx_mac_fsm_o.data <= bit_to_polarity(llc_i.avalon_st_source.data(...));

-- In tests: set LLC test data
llc_i.data := dominant;  -- Use polarity_t in MAC domain
```

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
ps_to_mac.polarity <= current_bus_state;
-- Strobes are single-cycle pulses
ps_to_mac.sp <= '1' when sample_point_reached else '0';
ps_to_mac.ssp <= '1' when secondary_sample_point_reached else '0';
```

MAC latches polarity on strobe pulses, handles TDC via SSP timing.

---

## Debugging Guide

1. **View waveforms**: `make TB=src/tx_mac_ser_tb all` opens GTKWave
2. **Check test results**: OSVVM reports all pass/fail to console
3. **Record inspection**: GHW format shows record fields; VCD cannot
4. **FSM tracing**: Use `mac_frame_bit_name_t` enum for symbolic display
5. **Linting**: Run VSG before commits

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
sby formal/can_mac_bs_tx.sby bmc      # Bounded model check (fast falsification)
sby formal/can_mac_bs_tx.sby prove    # K-induction (exhaustive proof)
sby formal/can_mac_bs_tx.sby          # Both tasks
sby -f formal/can_mac_bs_tx.sby prove # Force re-run (overwrite previous results)
```

---

## Recent Architecture Improvements

### 1. MAC-PS Interface Redesign
- **Old**: Exchanged numeric sample point offsets and measured polarity
- **New**: PCS drives continuous polarity with strobed sampling (sp/ssp)
- **Benefit**: More aligned with real transceiver behavior, explicit timing

### 2. Unified Polarity Type in MAC Domain
- **Old**: tx_mac_ser mixed std_logic and polarity_t
- **New**: Consistent polarity_t throughout MAC layer
- **Benefit**: Type safety, clear layer boundary (LLC=std_logic, MAC=polarity_t)

### 3. Simplified Serializer FSM
- **Old**: tx_mac_ser checked FSM state directly
- **New**: Relies only on ready/transfer_status handshake signals
- **Benefit**: Better encapsulation, FSM manages state via signals

### 4. Clean Avalon-ST Ready Management
- **Old**: Redundant ready assignments in state transitions
- **New**: Each state owns its ready signal; defaults handle transitions
- **Benefit**: Simpler logic, clear state ownership

---

## Known Limitations & TODOs

- `tx_mac_fsm.vhd`: Empty placeholder, FSM implementation pending
- `tx_mac_err.vhd`: Error handling module not implemented
- `bit_stuffer.vhd`, `bit_stuffer_fd.vhd`: Placeholder implementations
- CRC calculation: Basic implementation, polynomial verification needed for CAN-FD
- `max_mac_frame_length_c = 1024`: Could optimize to 512

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
- Use `polarity_t` in MAC domain, `std_logic` at system boundaries
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
<!-- mtoc-start -->

<!-- mtoc-end -->
- Section selection (`--section`):
  - Best reliability comes from `sec:` IDs in headings.
  - Aliases like `design_and_architecture` are supported.
