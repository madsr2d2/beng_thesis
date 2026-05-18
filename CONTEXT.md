# CONTEXT.md

Prime context for agents editing `docs/report.md`. Read this before making any changes to the report.

---

## Glossary

Use these terms exactly. Do not drift to synonyms.

| Term | Meaning | Avoid |
|---|---|---|
| CAN protocol controller | The digital logic block implemented in this project - sits between the host application and the physical transceiver IC, connected via CAN_TX/CAN_RX signals from the PCS | "CAN transceiver" (that is the physical layer IC, e.g. NXP TJA1040, which drives CANL/CANH) |
| CAN transceiver | The physical layer IC driving CANL/CANH on the bus wire (e.g. NXP TJA1040). A separate component from the protocol controller | "transceiver" to mean the protocol controller |
| CB, CE, FB, FE | Classic Base, Classic Extended, FD Base, FD Extended frame formats | "CAN Classic frame", "FD frame" without the letter code |
| LLC, MAC, PCS, FCE | The four sub-layers per ISO 11898-1 | "link layer", "physical layer" (ambiguous) |
| `can_mac_fsm` | The unified single-FSM MAC entity | "TX FSM", "RX FSM" (the split-path design was rejected) |
| `is_transmitter` | The boolean flag that partitions TX/RX logic inside `can_mac_fsm` | "TX mode signal", "transmitter flag" |
| `can_mac_ser` | TX-only serializer: converts LLC byte stream to serial bit stream | "deserializer" (it is TX-only) |
| `can_mac_bs` | Bit stuffer/destuffer - single instance shared by TX and RX | "TX stuffer", "RX stuffer" |
| `can_mac_crc` | CRC engine - single instance, three parallel `gen_crc` instances | "CRC module", "CRC generator" |
| `can_fce` | Fault Confinement Entity | "error counter module" |
| `can_pcs` | Physical Coding Sublayer - bit timing, sync, TDC | "clock module", `can_node_clock` (the prior implementation) |
| internal LLC frame format | The 2-config-byte + ID + data layout on the MAC-facing stream | "MAC frame", "internal format" |
| `data_cc` / `data_fd` | The two CRC data feeds: CC (de-stuffed) and FD (includes dynamic stuff bits in arbitration region) | "CRC input A/B" |
| dynamic stuffing | Insert inverse bit after five consecutive identical bits | "bit stuffing" alone (ambiguous - there is also fixed stuffing) |
| fixed stuffing | Insert stuff bit at fixed intervals in FD CRC region, with SBC field | "static stuffing" |
| SBC | Stuff Bit Count - Gray-coded, with parity, transmitted in FD CRC region | "stuff count" |
| TDC | Transmitter Delay Compensation - PCS measures TX-to-RX echo delay, positions SSP | "delay compensation" |
| SSP | Secondary Sample Point - used instead of SP for bit-error monitoring in FD data phase | "secondary sample" |
| SP | Sample point - fires at end of PHASE_SEG1 | "sample strobe" |
| REQ-NNN | Requirement identifier in `verification_plan/verification_plan.toml` | "requirement N", "req N" |
| P1 / P2 / P3 | Requirement priority levels (need-to-have / nice-to-have / optional) | "high/medium/low priority" |
| Error Active / Error Passive / Bus Off | FCE node states | "error state 1/2/3" |
| `can_node_clock` | The prior CAN Classic PCS implementation (do not confuse with `can_pcs`) | - |
| split-path design | The rejected architecture with separate `can_mac_fsm_tx` and `can_mac_fsm_rx` | "dual FSM", "TX/RX split" |

---

## Narrative Arc

The report tells a single continuous story. Each section picks up from the previous one's closing promise. Do not break this continuity when editing.

### Introduction

**What it establishes:** The company needs CAN-FD. The existing in-house CAN Classic controller (`can_node_clock`, `can_fsm`) cannot be extended to CAN-FD due to five architectural limitations (single bit rate, dynamic-only stuffing, single CRC, combined TX/RX FSM, embedded error handling). Available third-party IP cores do not fit for five reasons (IP ownership, verification authority, architectural scope, integration conventions, platform independence). Therefore: clean-sheet redesign.

**Closes with:** The Problem Statement and Objectives.

### Background

**What it establishes:** Two things in order:

1. **Top-view story of the CAN protocol:** History and multi-master arbitration `[@bosch1991]`. Error detection performance: Charzinski 1994 showed residual error probability of $3.5 \times 10^{-9} \cdot q_\text{bad}$ per frame (10-node network), substantially better than VAN/SCP; FCE and fault confinement as the distinguishing feature vs. competing protocols. Protocol comparison table (LIN, CAN Classic, CAN FD, FlexRay, Automotive Ethernet) - none of the alternatives combine CAN's speed, fault confinement, and multi-master arbitration. CAN FD introduction `[@hartwich2012]`: 64-byte payload, dual bit rate, Hartwich's 2.5 Mbit/s measurement. Oscillator tolerance `[@mutter2013]`: data/arbitration ratio < ~9 keeps same tolerance as Classic CAN. CAN FD error detection improvements `[@mutter2015]`: CRC-17/21, dynamic-stuff-bit CRC weakness fixed via SBC field.

2. **VHDL-93 (RTL) and VHDL-2008/OSVVM (testbenches) as the implementation and verification toolchain.** RTL source is VHDL-93 - Quartus Prime does not fully support VHDL-2008 for synthesis, making VHDL-93 the practical upper bound for synthesizable RTL. Testbenches are VHDL-2008 (required by OSVVM). GHDL supports both. SystemVerilog/UVM acknowledged as the dominant alternative. PSL is NOT used in this project - do not mention PSL or formal verification anywhere in the report.

**Key citations:** `[@bosch1991]`, `[@charzinski1994]`, `[@hartwich2012]`, `[@mutter2013]`, `[@mutter2015]`.

### Requirements

**What it establishes:** 38 structured requirements extracted from ISO 11898-1 via AI-assisted extraction + manual review. The AI bootstrapped the initial normative statement set (168 statements); the manual distillation step - consolidating to 38 prioritised, independently verifiable requirements - was substantial and irreplaceable. The primary benefit of AI assistance in extraction was consistency, not speed. The MCP server interface was genuinely useful throughout design, implementation, and verification phases for safe incremental updates to the plan.

**Key artifact:** `verification_plan.toml`, managed via MCP server to prevent silent data corruption. Current state: 28 complete, 10 open (7 LLC deferred: REQ-001, REQ-003, REQ-005, REQ-033, REQ-038 not_started; REQ-022 in_progress - bit error only; REQ-036 P2 not_started; REQ-037 P2 not_started). REQ-011 (remote frames) closed via FTYP coverage bin in `can_mac_pcs_fce_tb`. REQ-035 (lone-node ACK exemption) fully closed - both sub-claims verified.

**Closes with:** "@sec:can-protocol-overview provides that understanding - covering the sub-layer model, frame formats, bit timing, bit stuffing, CRC, and error handling."

### CAN and CAN-FD Protocol Overview

**What it establishes:** The protocol mechanisms the requirements refer to: sub-layer model, frame formats (CB/CE/FB/FE), bit timing and dual rate, bit stuffing (dynamic + fixed), CRC (CRC-15/17/21, dual data feed), error detection and fault confinement. Every mechanism is cross-referenced to REQ-NNN.

**Closes with:** "With those mechanisms established... the following section introduces the five classification dimensions of the verification plan and shows how each one connects back to the protocol concepts described here."

### Verification Plan

**What it establishes:** Five classification dimensions for the 38 requirements, split into two groups:

- Design-facing (determine module decomposition and stimulus configuration): `layer`, `side`, `format_applicability`
- Verification-facing (determine testbench architecture): `observability`, `verification_method`

Priority spans both groups.

**Closes with:** "How the design-facing dimensions shaped the module decomposition - and where the apparent mapping from requirements structure to design structure broke down - is the subject of @sec:design-architecture."

### Design and Architecture

**What it establishes:** How the three design-facing dimensions shaped the architecture, and where the mapping broke down.

- `layer` → layered architecture (LLC, MAC, PCS, FCE). Sound conclusion. The observability dimension reinforced it.
- `side` → appeared to motivate a split TX/RX FSM. **This was a red herring.** The split was attempted (separate `can_mac_fsm_tx` and `can_mac_fsm_rx`), caused code duplication, debugging complexity, and a concrete `c_disturbed` bug in `can_mac_pcs_fce_tb`. **General lesson: requirements structure can bias architectural decisions in ways that are not immediately obvious. Verification plan dimensions are inputs to testbench architecture, not RTL architecture.**
- `format_applicability` → per-field FSM states (not per-phase), and front-loaded internal LLC frame format (2 config bytes before ID/data so the FSM knows format before the first ID bit).

Final architecture: one unified `can_mac_fsm`, one `can_mac_bs`, one `can_mac_crc`, one `can_mac_ser` (TX only), plus `can_fce` and `can_pcs`.

**Closes with:** "The decomposition described above yields six implemented entities... The following section covers the implementation of each entity in turn, ordered MAC-first."

### Implementation

**What it establishes:** The implementation of the six entities. Two narrative threads run through the section:

1. **Non-obvious decisions forced by protocol structure** (not derivable from the requirements table alone):
   - `can_mac_fsm` TX feed source: `pcs_i.rx_data` in `s_arbitration`, `transmitted_bits_shift_reg(0)` everywhere else. Keeps feed independent of TDC echo latency.
   - `can_mac_bs` mode-boundary promotion: a pending dynamic stuff bit at the rising edge of `fixed_bit_stuffing_en` is promoted to the initial FSB rather than suppressed, to prevent TX/RX SBC divergence.
   - `can_mac_crc` combinatorial output mux: a registered mux would add one cycle of latency, causing the FSM to read a stale CRC digest on the cycle it drives the first CRC bit.
   - `can_fce` passive ACK exemption: ISO 8.1.4.2.c Exception 1 - an Error Passive transmitter that receives no ACK shall not increment TEC. FCE has no frame-level visibility, so the MAC must signal this via `mac_i.passive_tx_ack_error_exempt_1`.
   - `can_pcs` sync rules: the prior implementation (`can_node_clock`) missed three of the four ISO 7.3.5.1 rules (no sync-inhibit guard, no sampled-polarity check, Phase_Seg2 shortening skipped Sync_Seg). None caused observable failures on the deployed bus, but all are protocol obligations.

2. **Unified FSM pays off in concrete ways (all 19 states shared - duplication applies to entire FSM, not just error states):**
   - Arbitration loss is handled in-place: `is_transmitter` flips to `false` inside `s_arbitration`, CRC accumulator and bit stuffer carry over without any inter-module handoff. The split-path design would have required explicit coordination at this boundary.
   - Frame buffer continuity: `llc_frame` byte array is already populated from `pcs_i.rx_data` during arbitration, so arbitration-loss reception continues into the same buffer with no data to move.
   - A single fix to a shared submodule (`can_mac_bs`, `can_mac_crc`) propagates to both TX and RX paths automatically.
   - Single `can_mac_bs` instance (TX stuffing and RX destuffing share logic); single `can_mac_crc` (3 engines instead of 6 in a split design).
   - Single FCE interface - no arbitration logic needed between duplicate error/success signals.
   - TX bus monitoring (bit error, arbitration loss) shares the same bus-observation loop as RX reception - no duplicate path needed.

**Closes with:** "With the implementation complete, the remaining question is whether the 38 requirements in the verification plan are in fact satisfied by what was built - the subject of @sec:verification-results."

### Verification and Results

**What it establishes:** Evidence that the 38 verification plan requirements are satisfied, organised by testbench. `can_mac_pcs_fce_tb` covers 16 requirements (including REQ-011 via FTYP coverage). Five testbenches total; REQ-013 and REQ-024 are code inspection only. 28 of 38 requirements are closed. Ten remain open: 7 LLC deferred, REQ-022 in_progress, REQ-036 and REQ-037 P2 non-blocking.

**Key figures:** Two waveform figures exist (`full_fd_frame.pdf`, `req_30_31.pdf` - covers REQ-030/REQ-031 error escalation). Six additional waveform figures are pending placeholders (`pending_bs_dynamic.pdf`, `pending_bs_fixed.pdf`, `pending_pcs_tdc.pdf`, `pending_lost_arb.pdf`, `pending_error_frame.pdf`, `pending_bus_off_recovery.pdf`).

**Closes with:** Reference to the full verification plan in @sec:appendix-vplan.

### Synthesis

**What it establishes:** Synthesis results for `can_mac_pcs_fce` on Cyclone 10 LP (10CL016YU256I7G) using Quartus Prime 21.1.1. Two RTL constructs required substitution for Quartus compatibility before synthesis (conditional signal assignments and `sll` operator). Resource utilization: 4,608 LEs (30% of device), 869 registers, no memory or DSP blocks. Per-module breakdown: `can_mac_fsm` dominates at 4,109 LEs (89%) driven by the 560-bit RX frame buffer. Timing: worst-case fmax ~127 MHz on slow 100°C corner at 166 MHz overconstrain - passes at any realistic system clock (50-80 MHz range). Source: `docs/synthesis_resource_comparison.md`.

**Closes with:** Feeds the CC vs FD comparison in @sec:discussion.

### Discussion and Conclusion

**Discussion establishes:** Four main points: (1) requirements structure can inadvertently bias RTL architecture - the TX/RX side dimension made the split-path look natural but it was a red herring; (2) the unified FSM paid off most concretely at the arbitration loss boundary; (3) the layered architecture enabled module-by-module verification; (4) synthesis comparison - CAN FD is 4.0× CAN CC in LEs, dominated by frame buffer scaling (4.7×), protocol logic itself only 2.9×, payload-normalised 72 vs 143 LEs/byte. Objectives Assessment (@sec:objectives-assessment) assesses each of the four objectives. Future Work (@sec:future-work) has four items: `can_llc` implementation, hardware bring-up (including PCAN interoperability), CAN XL support, REQ-022 error-type-specific simulation coverage.

**Conclusion establishes:** Two-paragraph close - what was delivered (28/38, MAC/PCS/FCE, 4608 LEs / ~127 MHz on Cyclone 10 LP), three transferable lessons (requirements model structure is not RTL structure; layered architecture is a practical partitioning; narrow MCP write interface makes AI-assisted artifact maintenance safe).

---

## Key Design Decisions (cross-reference to docs/adr/ if ADRs are created)

| Decision | Chosen | Rejected | Reason |
|---|---|---|---|
| Architecture | Layered (LLC, MAC, PCS, FCE) | Monolithic extension of existing controller | CAN-FD complexity requires independent, verifiable sub-layers |
| MAC FSM | Unified `can_mac_fsm` | Split `can_mac_fsm_tx` / `can_mac_fsm_rx` | Split caused code duplication and inter-FSM coordination problems; frame structure is the same regardless of role |
| FSM granularity | Per-field states (19 states) | Per-phase states (fewer states, more counter logic) | Per-field aligns with verification plan; format-specific transitions become state graph edges rather than counter conditionals |
| LLC-to-MAC stream | Front-loaded internal format (2 config bytes first) | Direct LLC frame order (flags at end) | MAC FSM needs format flags before first ID bit; front-loading enables pure pipeline operation |
| CRC data feeds | Dual (`data_cc`, `data_fd`) | Single feed with mux | CC and FD compute CRC over different bit streams; single feed requires protocol knowledge in CRC module |
| CRC output mux | Combinatorial | Registered | Registered mux adds one cycle latency; FSM reads CRC on the same cycle as last data bit |
