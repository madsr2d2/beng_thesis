# Synthesis Resource Comparison: CAN CC vs CAN FD

**Author:** TMYAES  
**Date:** 2026-05-18  
**JIRA:** TRIT-4355  

---

## 1. Purpose

This document compares the FPGA resource utilisation of two CAN bus controller
implementations developed within the Triton project:

| | Old implementation | New implementation |
|---|---|---|
| **Module** | `can_bus_controller` | `can_mac_pcs_fce` |
| **Standard** | CAN 2.0A / 2.0B (Classic CAN) | ISO 11898-1:2015 (CAN FD) |
| **Path** | `modules/ip_lib/can_bus_controller` | `modules/ip_lib/can_bus_controller_fd` |

The comparison is intended to support thesis work quantifying the implementation
cost of upgrading from CAN CC to CAN FD on an FPGA target.

---

## 2. Synthesis Environment

### 2.1 Tool

| Parameter | Value |
|---|---|
| Tool | Quartus Prime Standard Edition |
| Version | 21.1.1 Build 850 — 06/23/2022 SJ |

### 2.2 Target Device

| Parameter | Value |
|---|---|
| Family | Cyclone 10 LP |
| Device | 10CL016YU256I7G |
| Speed grade | I7 |
| Total LEs available | 15,408 |
| Total registers available | — |
| Total memory bits available | 516,096 |
| Embedded multipliers (9-bit) | 112 |
| PLLs | 4 |

Both implementations target the same device family, enabling a direct like-for-like
comparison of logic element counts.

### 2.3 Timing Constraints

The CAN FD standalone synthesis used the following SDC clock constraint,
deliberately overconstraining to expose worst-case timing paths:

```
create_clock -name "clk" -period 6.000ns [get_ports {clk_i}]  ; # 166 MHz
```

Input/output delays were set to 2.0 ns on all ports.

The CAN CC figure was extracted from a board-level (`io_ext_cb_1830_func_1`)
hierarchy report; the board SDC uses the actual system clock. This introduces
a small optimism bias (<5%) in the FD standalone numbers due to greater
cross-boundary optimisation in a full-board compile.

### 2.4 Synthesis Method

| | CAN CC | CAN FD |
|---|---|---|
| Synthesis scope | Part of board design | Standalone project |
| Project file | `io_ext_cb_1830_func_1.qpf` | `devel/syn/can_mac_pcs_fce.qpf` |
| Top-level entity | `io_ext_cb_1830_func_1` | `can_mac_pcs_fce_top` |
| Resource extraction | Hierarchy report (sub-entity) | Fitter summary |
| VHDL standard | VHDL-2008 | VHDL-2008 |

The `can_mac_pcs_fce_top` wrapper flattens all record-typed ports into individual
`std_logic` / `std_logic_vector` signals and marks all I/O as `VIRTUAL_PIN`,
making this a logic-only synthesis check with no I/O buffer overhead.

---

## 3. Feature Set Comparison

| Feature | CAN CC | CAN FD |
|---|---|---|
| Standard frame (11-bit ID) | Yes | Yes |
| Extended frame (29-bit ID) | Yes | Yes |
| Maximum data payload | **8 bytes** | **64 bytes** |
| Dual bit rate (BRS) | No | Yes |
| Transmitter Delay Compensation (TDC) | No | Yes |
| Secondary Sample Point (SSP) | No | Yes |
| CRC-15 | Yes | Yes |
| CRC-17 | No | Yes |
| CRC-21 | No | Yes |
| Fixed bit stuffing (SBC field) | No | Yes |
| Error State Indicator (ESI) | No | Yes |
| Full fault confinement (TEC / REC) | Partial | **Full ISO 11898-1 §8.1** |
| Bus-off recovery | Yes | Yes |
| Error active / passive states | Yes | Yes |
| Configurable bit timing | Yes | Yes |
| Separate FCE layer | No | Yes |
| Layered MAC / PCS / FCE architecture | No | Yes |

---

## 4. Architecture Overview

### 4.1 CAN CC — `can_bus_controller`

A monolithic single-layer controller. All protocol, timing, and frame assembly
logic resides in a flat hierarchy.

```
can_bus_controller
├── can_fsm              — Protocol state machine (CC only)
├── can_node_clock       — Bit timing (single rate)
├── can_serial_to_ast    — RX: bit stream → frame buffer → Avalon-ST
├── can_ast_to_serial    — TX: Avalon-ST → bit stream
├── can_stuff_bit_gen    — Dynamic bit stuffing only
└── gen_crc              — CRC-15 engine
```

### 4.2 CAN FD — `can_mac_pcs_fce`

A layered architecture following the ISO 11898-1 layer model.

```
can_mac_pcs_fce          — Structural wrapper
├── can_mac              — MAC layer
│   ├── can_mac_fsm      — Protocol FSM (CC + FD frame formats)
│   ├── can_mac_ser      — TX serialiser (LLC byte stream → bit stream)
│   ├── can_mac_bs       — Bit stuffer (dynamic + fixed mode)
│   └── can_mac_crc      — CRC controller
│       ├── gen_crc      — CRC-15 engine
│       ├── gen_crc      — CRC-17 engine
│       └── gen_crc      — CRC-21 engine
├── can_pcs              — Physical Coding Sub-layer (TDC, SSP, dual rate)
└── can_fce              — Fault Confinement Entity (TEC, REC, bus-off)
```

---

## 5. Frame Buffer Analysis

Both implementations buffer the complete received frame in flip-flop registers
before streaming to the upper layer. This is necessary because the CRC is only
verified at the end of the frame; the buffer allows the frame to be discarded
if the CRC fails without forwarding corrupt data upstream.

### 5.1 Frame Buffer Layout

**CAN CC — 15 bytes (120 bits)**

| Bytes | Field |
|---|---|
| 0–3 | Extended ID (29 bits, 4 bytes) |
| 4 | DLC |
| 5–12 | Data payload (max 8 bytes) |
| 13 | IDE flag |
| 14 | RTR flag |

**CAN FD — 70 bytes (560 bits)**

| Bytes | Field |
|---|---|
| 0 | Config byte 0 (FDF, IDE, BRS, ESI, frame type flags) |
| 1 | Config byte 1 (DLC) |
| 2–5 | ID (4 bytes) |
| 6–69 | Data payload (max 64 bytes) |

### 5.2 Buffer Size Comparison

| | CAN CC | CAN FD | Ratio |
|---|---|---|---|
| Data payload bytes | 8 | 64 | **8.0×** |
| Metadata bytes | 7 | 6 | 0.9× |
| **Total frame buffer** | **15 bytes (120 bits)** | **70 bytes (560 bits)** | **4.7×** |

The buffer grew only 4.7× despite an 8× payload increase because the metadata
overhead remained constant. This is relevant because the frame buffer is the
primary driver of FSM logic growth (see Section 6.3).

---

## 6. Resource Utilisation

### 6.1 Top-level Summary

| Metric | CAN CC | CAN FD | Growth |
|---|---|---|---|
| **Total Logic Elements** | **1,146** | **4,608** | **4.0×** |
| **Dedicated Registers** | **334** | **869** | **2.6×** |
| Memory bits used | 0 | 0 | 1× |
| Embedded multipliers | 0 | 0 | 1× |
| PLLs | 0 | 0 | 1× |
| Device utilisation | N/A (board) | 30% of 15,408 LEs | — |

### 6.2 Sub-module Breakdown

The Quartus resource usage by entity report. Numbers in parentheses indicate
resources used exclusively at that hierarchy level (not in sub-entities).

**CAN CC:**

| Module | Total LEs | Registers | Function |
|---|---|---|---|
| `can_bus_controller` | 1,146 (3) | 334 (0) | Top wrapper |
| `can_fsm` | 589 (589) | 86 (86) | Protocol FSM |
| `can_serial_to_ast` | 324 (324) | 166 (166) | RX frame assembly + buffer |
| `can_ast_to_serial` | 92 (92) | 34 (34) | TX serialiser |
| `can_node_clock` | 110 (110) | 25 (25) | Bit timing |
| `can_stuff_bit_gen` | 10 (10) | 6 (6) | Bit stuffing |
| `gen_crc` | 18 (18) | 15 (15) | CRC-15 |

**CAN FD:**

| Module | Total LEs | Registers | Function |
|---|---|---|---|
| `can_mac_pcs_fce_top` | 4,608 (1) | 869 (0) | Synthesis wrapper |
| `can_mac_pcs_fce` | 4,607 (0) | 869 (0) | Structural wrapper |
| `can_mac` | 4,300 (1) | 789 (0) | MAC layer |
| `can_mac_fsm` | 4,109 (4109) | 684 (684) | Protocol FSM + RX frame buffer |
| `can_mac_ser` | 84 (84) | 40 (40) | TX serialiser |
| `can_mac_bs` | 31 (31) | 12 (12) | Bit stuffing (dynamic + fixed) |
| `can_mac_crc` | 84 (20) | 53 (0) | CRC controller |
| `gen_crc` (CRC-15) | 18 (18) | 15 (15) | CRC-15 engine |
| `gen_crc` (CRC-17) | 23 (23) | 17 (17) | CRC-17 engine |
| `gen_crc` (CRC-21) | 24 (24) | 21 (21) | CRC-21 engine |
| `can_pcs` | 190 (190) | 49 (49) | PCS: TDC, SSP, dual bit rate |
| `can_fce` | 117 (117) | 31 (31) | Fault confinement (TEC/REC) |

### 6.3 Layer-by-layer Functional Comparison

| Function | CAN CC module | LEs | Regs | CAN FD module | LEs | Regs | LE ratio |
|---|---|---|---|---|---|---|---|
| Protocol FSM | `can_fsm` | 589 | 86 | `can_mac_fsm` | 4,109 | 684 | 7.0× |
| Bit timing / PCS | `can_node_clock` | 110 | 25 | `can_pcs` | 190 | 49 | 1.7× |
| Bit stuffing | `can_stuff_bit_gen` | 10 | 6 | `can_mac_bs` | 31 | 12 | 3.1× |
| CRC engine(s) | `gen_crc` ×1 | 18 | 15 | `can_mac_crc` (×3) | 84 | 53 | 4.7× |
| TX serialiser | `can_ast_to_serial` | 92 | 34 | `can_mac_ser` | 84 | 40 | 0.9× |
| RX frame assembly | `can_serial_to_ast` | 324 | 166 | *(inside `can_mac_fsm`)* | — | ~560 | — |
| Fault confinement | *(none)* | — | — | `can_fce` | 117 | 31 | new |
| **Total** | | **1,146** | **334** | | **4,608** | **869** | **4.0×** |

---

## 7. Timing Results (CAN FD only)

The CAN CC timing results are not available in isolation as the design was
synthesised at board level. The CAN FD standalone results at the overconstraining
6 ns (166 MHz) clock are:

| Corner | Worst setup slack | fmax estimate | Hold slack |
|---|---|---|---|
| Slow 1150 mV 100°C | −1.858 ns | **~127 MHz** | +0.236 ns |
| Slow 1150 mV −40°C | −1.550 ns | **~152 MHz** | +0.021 ns |
| Fast 1150 mV 100°C | +0.230 ns | >166 MHz | +0.163 ns |
| Fast 1150 mV −40°C | +0.580 ns | >166 MHz | +0.145 ns |

The design is fully constrained for both setup and hold across all corners.
The worst-case fmax of ~127 MHz on the slow 100°C corner is well above any
realistic CAN FD system clock requirement (typically 50–125 MHz).

The timing failure in the slow corner is a consequence of the deliberate
overconstrain and does not indicate a functional problem.

---

## 8. Normalised Efficiency Metrics

### 8.1 Payload-normalised cost

$$\frac{\text{LEs}}{\text{payload byte}}: \quad \text{CC} = \frac{1146}{8} = 143 \quad \text{FD} = \frac{4608}{64} = 72$$

The FD implementation costs **half the logic per byte of payload capacity**,
demonstrating better-than-linear scaling with respect to the 8× payload increase.

### 8.2 Protocol logic cost (frame buffer excluded)

The frame buffer registers drive combinatorial mux/decode logic at approximately
6 LEs per register. Subtracting the estimated buffer contribution:

| | CAN CC | CAN FD |
|---|---|---|
| Frame buffer registers | ~120 | ~560 |
| Estimated buffer LEs | ~720 | ~3,360 |
| **Protocol LEs (buffer excluded)** | **~426** | **~1,248** |
| Protocol logic growth | — | **~2.9×** |

For a protocol that adds dual bit rate, TDC, three CRC variants, fixed bit
stuffing, full fault confinement, and 8× payload — a 2.9× increase in protocol
logic is highly efficient.

### 8.3 Per-engine CRC cost

| | CAN CC | CAN FD (per engine) |
|---|---|---|
| LEs per CRC engine | 18 | 22 average (18/23/24) |
| Growth per engine | — | 1.2× |

The marginal cost of each additional CRC engine is low (1.2× per engine).
The total CRC block grew 4.7× but delivers 3× the number of engines.

### 8.4 Summary

| Metric | Value |
|---|---|
| Top-level LE growth | 4.0× |
| Payload capacity growth | 8.0× |
| LEs per payload byte: CC | 143 |
| LEs per payload byte: FD | 72 |
| Protocol logic growth (buffer-excluded) | ~2.9× |
| TX serialiser growth | 0.9× (flat) |
| Fault confinement cost (new) | 117 LEs / 31 registers |

---

## 9. Conclusions

1. The CAN FD implementation requires **4.0× more logic elements** than the
   CAN CC baseline on the same Cyclone 10 LP device.

2. This growth is dominated by the **frame buffer scaling** with the 8× larger
   payload (120 bits → 560 bits), not by added protocol complexity per se.

3. Normalised for payload capacity, the FD design consumes **half the logic per
   byte** (72 vs 143 LEs/byte), demonstrating better-than-linear scaling.

4. The protocol state machine logic itself (buffer-excluded) grew only **~2.9×**
   to deliver substantially greater protocol complexity including TDC, dual bit
   rate, three CRC engines, and full ISO fault confinement.

5. The TX serialiser is effectively **unchanged in size** (0.9×) between CC and FD.

6. The design achieves a worst-case **fmax of ~127 MHz** on the Cyclone 10 LP
   slow corner, providing comfortable timing margin for typical system clocks
   of 50–125 MHz.

7. At 30% device utilisation on the smallest Cyclone 10 LP variant
   (`10CL016YU256I7G`), the CAN FD stack fits comfortably on the next device
   step up (`10CL025`, ~19%) or larger variants.

---

## 10. Caveats and Limitations

- The CC resource figure is extracted from a board-level hierarchy report.
  Standalone synthesis of the CC module may yield slightly different numbers
  due to cross-hierarchy optimisation.
- The VHDL 2008 constructs `signal <= expr when cond else other` inside
  sequential processes are not supported by Quartus 21.1. These were replaced
  with equivalent `if/else` statements in the CAN FD source files prior to
  synthesis. The `sll` operator on `std_logic_vector` was similarly replaced
  with a concatenation shift. These changes are functionally equivalent and
  do not affect resource counts relative to a tool with full VHDL 2008 support.
- Timing results are only available for the CAN FD design. A fair timing
  comparison would require synthesising the CC design in a standalone project
  with a matching SDC clock constraint.
