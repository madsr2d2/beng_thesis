# GEMINI.md - CAN Bus Transmitter Project

This file provides a comprehensive instructional context for Gemini regarding the B.Eng thesis project: a CAN Bus Transmitter implemented in VHDL-2008.

## Project Overview

- **Goal**: Implement a CAN/CAN-FD Bus Transmitter compliant with ISO 11898-1:2015/2024.
- **Key Features**: Classic CAN & CAN-FD support, TDC (Transmitter Delay Compensation), Avalon-ST interface for LLC data.
- **Layers**:
    - **LLC (Link Layer Control)**: `tx_llc.vhd` - Frame buffering, retransmissions, `std_logic` domain.
    - **MAC (Media Access Control)**: Serializer (`tx_mac_ser`), FSM coordinator (`tx_mac_fsm`), Bit Stuffing, `polarity_t` domain.
    - **PCS (Physical Coding Sublayer)**: `tx_pcs.vhd` - Bit timing, SP/SSP strobe generation, TDC measurement.

## Core Design Principles

### 1. Type Safety & Domain Separation
- **LLC Domain**: Uses `std_logic` (0/1) for data.
- **MAC Domain**: Uses `polarity_t` (`dominant`, `recessive`) for semantic clarity.
- **Interface Types**: Always use the record types in `can_pkg.vhd` (e.g., `mac_to_pcs_if_t`).

### 2. Naming Conventions
- **Ports**: `_i` (input), `_o` (output).
- **Constants**: `_c` suffix.
- **Types**: `_t` suffix.
- **Registers**: `_reg` suffix.
- **Bit Slices**: Always use `_start` and `_end` suffixes for multi-bit fields (e.g., `format_start_c`, `format_end_c`).

### 3. VHDL Style
- **Standard**: VHDL-2008.
- **Serializer**: Prefer **Shift registers** over multiplexers for sequential bit output (as per established style).
- **Handshaking**: Use Avalon-ST ready/valid patterns. Each FSM state should "own" its `ready` signal.

## Building and Verification

### Commands
- **Run Testbench**: `make TB=src/<tb_name> all` (e.g., `make TB=src/can_pkg_tb all`)
- **Compile Only**: `make TB=src/<tb_name> compile`
- **Clean**: `make clean`
- **Linting**: `vsg -c vsg_config.yaml -f src/<file>.vhd`

### Tools
- **GHDL**: Simulator.
- **OSVVM**: Verification framework (used for Alerts, Logging, and TB structure).
- **GTKWave**: Waveform viewer (`.ghw` format).

## Implementation Details

### Frame Structure
Refer to `can_pkg.vhd` and the ISO 11898-1 standard (searchable markdown in `docs/md_out/`).
- **SOF** -> **Arbitration** (ID, IDE, RTR/RRS) -> **Control** (FDF, BRS, ESI, DLC) -> **Data** -> **CRC** -> **ACK** -> **EOF**.

### TDC (Transmitter Delay Compensation)
Implemented in `tx_pcs.vhd`. PCS drives continuous polarity and provides `sp` (Sample Point) and `ssp` (Secondary Sample Point) strobes to the MAC.

## Recent Improvements
- Refactored MAC-PCS interface to use strobed sampling.
- Unified `polarity_t` throughout the MAC layer.
- Simplified Serializer FSM for better encapsulation.
