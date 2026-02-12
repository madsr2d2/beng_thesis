# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a B.Eng thesis project implementing a **CAN (Controller Area Network) bus transmitter** in VHDL-2008, following the **ISO 11898-1:2015 standard**. The project includes:

- Core CAN/CAN-FD frame structure and utilities (`can_pkg.vhd`)
- MAC layer transmit serializer (`tx_mac_ser.vhd`)
- Bit stuffing logic for CAN protocol (`bit_stuffer.vhd`, `bit_stuffer_fd.vhd`)
- Comprehensive unit tests for all modules
- GHDL simulator integration with OSVVM library framework
- GTKWave waveform viewer integration for debugging

**Key Dependencies**: GHDL compiler, OSVVM libraries (located in `OsvvmLibraries/`), VSG linter

**Standards Reference**: See `doc/ISO_11898_1_CAN_bus_link.pdf` for the CAN protocol specification that guides frame structure and bit sequencing.

## Directory Structure

```
src/                    # Design and testbench VHDL files
├── can_pkg.vhd         # Core CAN frame definitions, types, and utility functions
├── can_pkg_tb.vhd      # Unit tests for can_pkg functions
├── tx_mac_ser.vhd      # MAC layer serializer (DUT)
├── tx_mac_ser_tb.vhd   # Testbench for tx_mac_ser with Avalon-ST interface
├── tx_mac.vhd          # Top-level MAC transmitter wrapper
├── tx_mac_err.vhd      # Error handling module
├── tx_mac_fsm.vhd      # FSM state machine (placeholder)
├── bit_stuffer.vhd     # Bit stuffing for CAN 2.0
├── bit_stuffer_fd.vhd  # Bit stuffing for CAN-FD
├── shift_reg.vhd       # Shift register utility
└── crc_fd.vhd          # CRC calculation for CAN-FD

gtk_wave/               # GTKWave configuration files (.gtkw)
doc/                    # Documentation (ISO 11898-1 CAN spec reference)
OsvvmLibraries/         # OSVVM simulation framework (external dependency)
sim/                    # Generated simulation artifacts (created by Makefile)
```

## Build and Test Commands

### Prerequisites

Ensure OSVVM libraries are compiled first:

```bash
cd OsvvmLibraries/osvvm && tclsh build.tcl
cd /path/to/beng_thesis
```

### Common Commands

**Run all tests for a specific testbench:**

```bash
make TB=src/can_pkg_tb all
make TB=src/tx_mac_ser_tb all
```

**Build only (without simulation):**

```bash
make TB=src/can_pkg_tb compile
```

**Run simulation without viewing waveforms:**

```bash
make TB=src/can_pkg_tb compile run
```

**View waveforms directly (after simulation):**

```bash
gtkwave sim/can_pkg_tb.ghw gtk_wave/can_pkg_tb.gtkw
```

**Clean generated files:**

```bash
make clean
```

### Makefile Details

- **SRCFILES**: Automatically discovers and orders compilation: packages → leaf modules → dependent modules → mac_tx (compiled last due to dependencies)
- **GHDL_FLAGS**: `--std=08` (VHDL-2008), includes OSVVM library path
- **Simulation time**: Default 2µs (configurable via `STOP_TIME`)
- **Waveform format**: GHW (GHDL format - preserves record types and enums better than VCD)

## Code Style and Linting

**Tool**: VSG (VHDL Style Guide) v3.35.0

**Run linting:**

```bash
vsg -c vsg_config.yaml -f src/can_pkg.vhd
```

**Configuration**: `vsg_config.yaml` disables most blank-line enforcement rules (type_010, subtype_201, case_*, loop_*, etc.) to maintain compact code style.

**Key Style Rules to Follow**:

- Disabled: Blank line insertion above type/subtype/function/procedure declarations
- Disabled: Blank line insertion around case/loop statements
- Otherwise: Standard VHDL-2008 conventions apply

## Core Architecture

### can_pkg.vhd - Central Package (1028 lines)

**Types and Constants**:

- `mac_frame_bit_t`: Record containing frame bit info (position, name, polarity, CRC involvement)
- `bit_t`: Simple record with position (integer) and polarity (dominant/recessive/unknown)
- `polarity_t`: Enum for bit polarity (dominant='0', recessive='1')
- `can_format_t`: Frame format (cc_basic, cc_extended, fd_basic, fd_extended)
- Byte layout constants with explicit `_start` and `_end` positions for bit slicing

**Key Functions**:

- `get_frame_info()`: Extracts format, DLC, flags from config bytes
- `get_next_frame_bit()`: Returns next MAC frame bit given current position and frame info
- `get_data_start_position()`: Calculates data field start position
- `polarity_to_bit()`: Converts polarity enum to std_logic
- `frame_bit_to_string()`: Debug utility for printing frame bits

**Frame Bit Structure** (per ISO 11898-1):

- **SOF** (1 bit): Start of Frame
- **Arbitration Field**: Base ID (11), IDE (1), SRR (1), Extended ID (18 for FD), RTR (1)
- **Control Field**: R0/R1 (2), DLC (4), FDF/BRS/ESI (CAN-FD specific)
- **Data Field**: 0-512 bits (0-64 bytes)
- **CRC Field**: CRC value + delimiter
- **ACK Field**: ACK slot + delimiter
- **EOF**: End of Frame (7 bits)

For detailed bit layout and encoding, refer to `doc/ISO_11898_1_CAN_bus_link.pdf` sections 8.2-8.4.

### tx_mac_ser.vhd - Serializer (135 lines)

**Purpose**: Converts 8-bit data words into serial CAN bit stream
**Interface**: Avalon-ST protocol with ready/valid handshaking

- **Inputs**: clk, rst, LLC interface (data valid/sop/eop), FSM interface (shift controls)
- **Outputs**: Serialized bits to FSM, status signals
**States**: idle → load_llc_frame_byte → shift_out_bits

### tx_mac_ser_tb.vhd - Testbench (472 lines)

**Tests**: Ready/valid handshaking, bit shifting timing, SOP/EOP framing
**Notable**: Uses OSVVM alert/report infrastructure for test tracking
**Waveforms**: GTKWave config shows FSM states, valid/ready signals, output bits

### can_pkg_tb.vhd - Package Tests (421 lines)

**Tests**:

- Frame format detection
- DLC and configuration byte parsing
- CRC vector generation
- Next frame bit generation for all CAN formats
**Pattern**: Standalone testbench (no entity ports), uses report/assertion for pass/fail

## Important Code Patterns

### Bit Slice Constants (Critical)

Use explicit `_start` and `_end` constants for all multi-bit fields:

```vhdl
constant format_start_c : integer := 7;
constant format_end_c   : integer := format_start_c - (format_width_c - 1);
-- Extract as: config_byte(format_start_c downto format_end_c)
```

**Why**: Prevents off-by-one errors in bit indexing.

### Ready/Valid Handshaking in Tests

Correct pattern:

```vhdl
llc_i.valid <= '1';
llc_i.data <= x"12";
wait for clk_period;  -- Capture values
assert llc_o.ready = '1' report "Ready not asserted" severity failure;
llc_i.valid <= '0';   -- Clear before next wait
wait for clk_period;
```

**Why**: Signals take effect at end of delta cycle; check must occur WHILE conditions are true.

### Waveform Format

- **GHW** (GHDL Wave): Native support for records and enums - shows FSM states directly
- **VCD** (Value Change Dump): Generic format, cannot display record fields
- **GTKWave**: Use `.gtkw` config files to define signal groups and bus unpacking

### Bit Stuffing (Whitening)

CAN requires bit stuffing to ensure transitions for clock recovery (per ISO 11898-1 section 8.5.4). After 5 consecutive bits of the same polarity, an opposite polarity bit is inserted. Implemented in `bit_stuffer.vhd` (CAN 2.0) and `bit_stuffer_fd.vhd` (CAN-FD with fixed stuff bits at predefined positions).

### Testing Methodology

Tests follow two patterns:

1. **Process-based** (can_pkg_tb): Run-once verification with assertions, automatic completion
2. **Stimulus-response** (tx_mac_ser_tb): Clock-driven with elaborate handshaking, requires timeout control

## Git and Version Control

**Recent commits** (see `git log --oneline`):

- Refactored unified `bit_t` constants replacing static form bit tables
- Implemented shift register FIFO for transmitted bits history
- Standardized range checks to use exclusive upper bounds
- Added blank line and case statement handling

**Branches**: Main development on `main` branch. PR-friendly approach preferred.

## Debugging Tips

1. **View waveforms**: `make TB=src/tx_mac_ser_tb all` automatically opens GTKWave
2. **Check assertions**: OSVVM report infrastructure shows all test pass/fail messages
3. **Inspect record contents**: GHW waveforms show record fields; VCD cannot
4. **Trace FSM states**: Use `mac_frame_bit_name_t` enum in waveform for symbolic state display
5. **Run linter**: `vsg -c vsg_config.yaml -f src/file.vhd` before commits

## Known Limitations and TODOs

- `max_mac_frame_length_c = 1024`: Comment suggests possible optimization to 512
- `transmitted_bits_fifo_depth_c = 32`: Placeholder value, may need tuning
- `tx_mac_fsm.vhd`: Empty placeholder, FSM implementation pending
- CRC calculation: Basic implementation, polynomial verification recommended for CAN-FD

## ISO 11898-1 Standard Reference

This implementation strictly follows **ISO 11898-1:2015 (Road vehicles - Controller area network (CAN) - Part 1: Data link layer and physical signaling)**.

The standard document is provided in `doc/ISO_11898_1_CAN_bus_link.pdf` (20 pages). Key sections relevant to this implementation:

- **Section 8.1**: Overview of CAN frame structure
- **Section 8.2**: CAN data frame format (SOF, arbitration, control, data, CRC, ACK, EOF)
- **Section 8.3**: CAN remote frame format
- **Section 8.4**: CAN FD extended frame format
- **Section 8.5**: Bit stuffing and destuffing rules
- **Section 8.5.2**: 5-in-a-row bit stuffing requirement
- **Section 8.5.4**: CRC field calculation and delimiter
- **Section 8.5.6**: ACK slot and delimiter encoding

When implementing new functionality, always cross-reference the ISO standard to ensure protocol compliance.

## Markdown and Mermaid Style Guide

### Markdown Formatting

**Line length**: Max 120 characters

**Code blocks**: Always specify language (e.g., ` ```bash `, ` ```vhdl `, ` ```mermaid `)

**Indentation**: Use spaces (not tabs)

**Emphasis**: Use bold (`**text**`) for strong emphasis, not underscores

**Lists**: Separate major sections with blank lines

### Mermaid Diagram Guidelines

**Common shapes**:
- Rounded rectangles: `(text)` - standard processes/operations
- Diamonds: `{text}` - decisions/conditionals
- Stadium/pills: `([text])` - start/end nodes
- Rectangles: `[text]` - standard boxes
- Cylinders: `[(text)]` - data storage (use sparingly)

**Diagram Titles (REQUIRED)**: Every mermaid diagram must include a descriptive title using YAML front-matter:
```
---
title: "Descriptive Title"
---
```

**ELK Algorithm (REQUIRED for flowcharts and state diagrams)**: Include the title first, then this initialization block for consistent layered rendering:
```
---
title: "Descriptive Title"
---
%%{init: {'flowchart': {'curve': 'linear'}, 'elk': {'algorithm': 'layered'}}}%%
diagram_type
```
Apply to: flowcharts, state diagrams. **Note**: Packet diagrams use title only (no init block).

**State Diagram (`stateDiagram-v2`) Formatting**:
- **Choice nodes**: Use `state name <<choice>>` (no display text) for decision points
- **Decision labels**: Place conditional logic on transitions (arrows), not in nodes
- **Action states**: Use descriptive names like "Calculate X specific bit positions" or "Return next Y bit"
- **Pattern example**:
  ```
  state check_condition <<choice>>
  state "Perform Action A" as action_a
  check_condition --> action_a: condition_true
  check_condition --> other_state: condition_false
  ```

**Best practices**:
- Keep diagrams focused on a single concept
- Use subgraphs to organize complex diagrams
- Label edges clearly
- Avoid deep nesting (max 3-4 levels)

## External Dependencies

- **OSVVM** (Open-Source VHDL Verification Methodology): Provides alert/report logging framework
- **GHDL**: Open-source VHDL compiler and simulator
- **GTKWave**: Waveform viewer for analyzing simulation results
- **mermaid-cli**: CLI tool for rendering mermaid diagrams to PNG
- **markdown-preview.nvim**: Browser-based markdown preview in neovim

See `OsvvmLibraries/README.md` for OSVVM-specific build and usage instructions.
