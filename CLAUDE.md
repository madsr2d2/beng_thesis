# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a B.Eng thesis project implementing a **CAN (Controller Area Network) bus transmitter** in VHDL-2008, following the **ISO 11898-1:2015 standard**. The project includes:

- Core CAN/CAN-FD frame structure and utilities (`can_pkg.vhd`)
- MAC layer transmit serializer (`tx_mac_ser.vhd`)
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

gtk_wave/               # GTKWave configuration files
docs/                   # Documentation and standards reference
├── md_out/              # Searchable markdown versions of standards (ISO 11898-1, etc.)
OsvvmLibraries/         # OSVVM simulation framework (external)
sim/                    # Generated simulation artifacts
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

## Requirements Management

ISO 11898-1:2015 CAN system requirements are tracked in `requirements/requirements.toml` — a structured TOML file with numeric IDs (001–123) organized by category and side.

### Requirements File Format

**File**: `requirements/requirements.toml`
**Structure**: 123 requirements
- **TX Side**: 83 requirements (IDs 001–063, 064–123)
  - FRM (Frame): 27 TX requirements
  - ERR (Error): 18 TX requirements
  - TMG (Timing): 11 TX requirements
  - CRC (Checksum): 6 TX requirements

- **RX Side**: 40 requirements (IDs 064–123)
  - FRM (Frame): 13 RX requirements (SOF detection, format detection, destuffing, ACK)
  - ERR (Error): 15 RX requirements (error detection, signalling, fault confinement)
  - TMG (Timing): 6 RX requirements (sync, sample points, bit integration)
  - CRC (Checksum): 5 RX requirements (CRC verification)

**Categories**:
- **FRM** : Frame structure, fields, arbitration, control, stuffing, completion, ACK
- **ERR** : Error detection & handling (bit, stuff, form, CRC errors), fault confinement
- **TMG** : Bit timing, sample points, TDC compensation, synchronization
- **CRC** : CRC polynomial selection, generation, verification

**Each requirement contains**:
- **Classification Metadata**: category, side (TX/RX), format (CB/CE/FB/FE), priority
- **Core Specification**: description, ISO reference, acceptance criteria, notes, target_module
- **Verification Strategy & Status**: verification method (WAVE/CVRG/SIM/ASSERT), status (verified/implemented/unverified/diagnostic)
- **Simulation/Formal subsections**: test coverage tracking (empty by default)

### ⚠️ IMPORTANT: Use Python for ALL TOML Manipulation

**NEVER edit `requirements.toml` directly.** Use Python with `tomllib` for all queries and updates. This ensures consistent structure and prevents corruption.

### Querying Requirements

Use **Python with `tomllib`** for all queries:

**Filter by category:**
```python
import tomllib
with open('requirements/requirements.toml', 'rb') as f:
    data = tomllib.load(f)
frm_reqs = {k: v for k, v in data['requirements'].items() if v.get('category') == 'FRM'}
for req_id, req in frm_reqs.items():
    print(f"{req_id}: {req['description']}")
```

**Filter by side (TX or RX):**
```python
import tomllib
with open('requirements/requirements.toml', 'rb') as f:
    data = tomllib.load(f)
rx_reqs = {k: v for k, v in data['requirements'].items() if v.get('side') == 'RX'}
print(f"Found {len(rx_reqs)} RX requirements")
```

**Find by ID:**
```python
import tomllib
with open('requirements/requirements.toml', 'rb') as f:
    data = tomllib.load(f)
req = data['requirements'].get('001')
if req:
    print(f"ID 001: {req['description']}")
```

**Search by description:**
```python
import tomllib
with open('requirements/requirements.toml', 'rb') as f:
    data = tomllib.load(f)
matches = {k: v for k, v in data['requirements'].items()
           if 'CRC' in v.get('description', '')}
for req_id, req in matches.items():
    print(f"{req_id}: {req['description']}")
```

**Filter by status:**
```python
import tomllib
with open('requirements/requirements.toml', 'rb') as f:
    data = tomllib.load(f)
verified = {k: v for k, v in data['requirements'].items()
            if v.get('status') == 'verified'}
print(f"{len(verified)} verified requirements")
```

**Get high-priority unverified requirements:**
```python
import tomllib
with open('requirements/requirements.toml', 'rb') as f:
    data = tomllib.load(f)
unverified_critical = {k: v for k, v in data['requirements'].items()
                       if v.get('priority') == 'C' and v.get('status') != 'verified'}
for req_id, req in unverified_critical.items():
    print(f"{req_id} ({req['category']}): {req['description']}")
```

**Count by category and side:**
```python
import tomllib
from collections import defaultdict
with open('requirements/requirements.toml', 'rb') as f:
    data = tomllib.load(f)
counts = defaultdict(int)
for req in data['requirements'].values():
    counts[(req.get('category'), req.get('side'))] += 1
for (cat, side), count in sorted(counts.items()):
    print(f"{cat}/{side}: {count}")
```

**Filter by format (CB, CE, FB, FE):**
```python
import tomllib
with open('requirements/requirements.toml', 'rb') as f:
    data = tomllib.load(f)
fb_reqs = {k: v for k, v in data['requirements'].items()
           if 'FB' in v.get('format', [])}
print(f"Found {len(fb_reqs)} FB (FD Basic) requirements")
```

### Updating Requirements

Use Python to read, modify, and write back:

**Change status of a single requirement:**
```python
import tomllib

# Read
with open('requirements/requirements.toml', 'rb') as f:
    data = tomllib.load(f)

# Modify
data['requirements']['001']['status'] = 'implemented'

# Write back
import json
with open('requirements/requirements.toml', 'w') as f:
    # Convert back to TOML format (or use custom serializer)
    # For now, use inline TOML editing or consider tomli_w package
```

**Bulk update all FRM requirements:**
```python
import tomllib

with open('requirements/requirements.toml', 'rb') as f:
    data = tomllib.load(f)

# Update all FRM requirements
for req in data['requirements'].values():
    if req.get('category') == 'FRM':
        req['priority'] = 'H'

# Write back (use regex or tomli_w)
```

**Mark requirements as verified by category:**
```python
import tomllib
import re

with open('requirements/requirements.toml', 'r') as f:
    content = f.read()

# Use regex to find and update status values for specific category
# Example: Mark all CRC requirements as verified
pattern = r'(\[requirements\.\d+\].*?category = "CRC".*?status = )"[^"]*"'
updated = re.sub(pattern, r'\1"verified"', content, flags=re.DOTALL)

with open('requirements/requirements.toml', 'w') as f:
    f.write(updated)
```

### Exporting Requirements as Tables

Use `python requirements/requirements_table.py` to generate nicely formatted tables:

```bash
# Export all requirements to HTML (default)
python requirements/requirements_table.py --toml requirements/requirements.toml --html table.html

# Export to Markdown
python requirements/requirements_table.py --toml requirements/requirements.toml --markdown table.md
```

### Key Points

- **NEVER edit requirements.toml directly** — use Python (`tomllib`) exclusively
- **Python is reliable**: Built-in library available in Python 3.11+, works reliably with TOML
- **Use tomllib for reading**: `tomllib.load()` for queries and analysis
- **Use regex for bulk updates**: For simple bulk modifications, regex with file I/O is faster
- **Consider tomli_w for complex writes**: For complex updates, use `tomli_w` package to serialize back to TOML
- **ID format**: Strictly numeric (001–123), with metadata in TOML fields (category, side, status, etc.)
- **Table export**: Use `requirements_table.py` for formatted HTML/Markdown output

### Makefile Details

- **Compilation order**: Packages → leaf modules → dependent modules → mac_tx (last)
- **GHDL flags**: `--std=08` (VHDL-2008), includes OSVVM library path
- **Simulation time**: Default 2µs (configurable via `STOP_TIME`)
- **Waveform format**: GHW (preserves record types and enums)

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

**Frame Structure** (per ISO 11898-1):
- SOF (1 bit)
- Arbitration (base_id 11-bit, ide, extended_id 18-bit, rtr)
- Control (dlc, fdf/brs/esi for CAN-FD)
- Data (0-64 bytes)
- CRC + delimiter
- ACK + delimiter
- EOF (7 bits)

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
