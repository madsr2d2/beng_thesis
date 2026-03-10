---
title: "Implementation and Verification of a CAN-FD Bus Transceiver in VHDL"
author: "Mads Richardt (s224948)"
date: "February 28, 2026"
bibliography: references.bib
csl: ieee.csl
link-citations: true
---

# Abstract {-}

*This document is a work-in-progress draft for the B.Eng thesis. Currently, the project is in the **Verification Plan** phase (Phase 2), with architectural prototyping for the transmitter sub-system completed.*

This thesis describes the design, implementation, and verification of a CAN (Controller Area Network) and CAN-FD (Flexible Data rate) transmitter sub-system.
 The implementation is targeting high-reliability engine controller applications and is compliant with the ISO 11898-1:2024 standard [@iso11898_1]. Key features include support for both Classic and FD frame formats, Transmitter Delay Compensation (TDC) for high-speed data phases, and a modular architecture separated into Link Layer Control (LLC), Media Access Control (MAC), and Physical Coding Sublayer (PCS).

# Abbreviations {-}

| Abbreviation | Meaning |
| --- | --- |
| ACK | Acknowledgement |
| AF | Acceptance Field |
| AUI | Attachment Unit Interface |
| CAN | Controller Area Network |
| CBFF | Classical Base Frame Format |
| CEFF | Classical Extended Frame Format |
| DF | Data Frame |
| DLL | Data Link Layer |
| EF | Error Frame |
| FBFF | FD Base Frame Format |
| FCE | Fault Confinement Entity |
| FEFF | FD Extended Frame Format |
| FTYP | Frame Type |
| LLC | Logical Link Control |
| LSDU | LLC Service Data Unit |
| MAC | Medium Access Control |
| OF | Overload Frame |
| OSI | Open Systems Interconnection |
| PCS | Physical Coding Sublayer |
| PDU | Protocol Data Unit |
| PMA | Physical Medium Attachment |
| RF | Remote Frame |
| SAP | Service Access Point |
| SDU | Service Data Unit |
| SOF | Start of Frame |
| TEC/REC | Transmit Error Counter / Receive Error Counter |
| VCID | Virtual CAN Channel Identifier |

: Abbreviations used in this report. {#tbl:abbreviations}

---

# Introduction {#sec:introduction}

## Motivation {#sec:motivation}
The Controller Area Network (CAN) has been the workhorse of automotive and industrial communication for decades. However, the increasing bandwidth requirements of modern systems led to the development of CAN-FD (Flexible Data rate), which allows for larger payloads and higher bit rates. This project aims to provide a robust, hardware-independent VHDL implementation of a CAN-FD transmitter.

## Problem Statement {#sec:problem-statement}
Existing CAN implementations often lack flexibility or do not fully support the latest ISO 11898-1:2024 [@iso11898_1] features, such as advanced Transmitter Delay Compensation (TDC). The challenge lies in creating a transmitter that can seamlessly switch between bit rates while maintaining strict protocol compliance and timing accuracy.

## Objectives {#sec:objectives}
- Implement a VHDL-2008 compliant CAN/CAN-FD transmitter.
- Support both Base (11-bit) and Extended (29-bit) identifiers.
- Implement TDC measurement and compensation logic.
- Ensure high verification coverage using OSVVM and GHDL.

---

# Background {#sec:background}

## CAN Protocol Evolution {#sec:can-protocol-evolution}
Brief history from CAN 2.0 to CAN-FD.

## ISO 11898-1:2024 Standard {#sec:iso-standard}
Overview of the data link layer and physical signaling requirements [@iso11898_1].

## VHDL and OSVVM {#sec:vhdl-osvvm}
The role of modern VHDL standards and verification frameworks in digital design.

---

# Verification Planning {#sec:verification-planning}

## Overview and Scope {#sec:overview-scope}

Protocol compliance is the central objective of this project. The CAN and CAN-FD standards [@iso11898_1] specify hundreds of normative requirements governing frame structure, bit timing, error handling, and fault confinement. To verify the transmitter against these requirements systematically, a structured **Verification Plan** was developed as the first major deliverable of the project - before any RTL implementation began.

The plan covers the four in-scope frame formats: Classic Basic (CB), Classic Extended (CE), FD Basic (FB), and FD Extended (FE). CAN XL frames are excluded. In total, the plan contains 168 requirements extracted from the standard, organized by architectural layer (LLC, MAC, PCS, FCE) and spanning the major functional areas:

- **Frame structure**: Field ordering, bit-level encoding, and format-specific control bits.
- **CRC generation**: CRC-15 (Classic), CRC-17, and CRC-21 (FD) polynomials.
- **Bit stuffing**: Dynamic stuffing during arbitration/data and fixed stuffing in the FD CRC region.
- **Error handling**: Bit error, ACK error, Form error, and Stuff error detection.
- **Fault confinement**: TEC/REC counter management and Error Active/Passive/Bus Off state transitions.

## Requirement Taxonomy {#sec:requirement-taxonomy}

A key design decision was the development of a two-axis taxonomy to classify each requirement by its **shape** and **scope**. This taxonomy determines both *how* a requirement is verified and *what environment* is needed.

**Shape** classifies the verification primitive. These categories draw on established concepts from formal verification theory:

- **Triggered**: A precondition/event/postcondition triplet that translates directly into a directed test procedure - establish the precondition, apply the event, assert the postcondition. This structure follows the Hoare triple formalism {P} S {Q} [@hoare1969].
- **Invariant**: A property that must hold at all times (e.g., "the SOF bit shall always be dominant"), mapping to concurrent assertions or monitors.
- **Liveness**: A property asserting that something eventually happens (e.g., "after detecting an error, the node shall eventually transmit an error flag"), requiring temporal reasoning [@alpern1985].
- **Reachability**: A property asserting that a state or condition *can* be reached (e.g., "the node shall be capable of entering Bus Off"), mapping to coverage points.

**Scope** defines the required verification environment:

- **Frame**: Verified by inspecting a single transmitted bit-stream in isolation.
- **Node**: Requires visibility into internal state such as error counters or FSM transitions.
- **Bus**: Requires a multi-node simulation with arbitration and acknowledge behavior.

Together, these two axes allow each requirement to be mapped to the appropriate testbench level and verification technique without ambiguity.

## Observability Classification {#sec:observability-classification}

The shape and scope taxonomy determines *how* and *where* a requirement is tested, but it does not answer a more fundamental question: *can* the requirement be tested at all from outside the design under test? Not every normative requirement produces a visible effect at the module's ports. Some requirements constrain internal counter thresholds, define structural concepts, or restrict valid configurations - none of which produce a unique, externally distinguishable output. To distinguish these cases systematically, a third classification axis - **observability** - was introduced.

Observability is assessed **per layer**, not per top-level CAN node. The design under test for a PCS requirement is the PCS module in isolation; for a MAC requirement it is the MAC module. This layer-relative framing is essential because a signal that is internal within a full node may be perfectly visible at a sub-layer boundary. For example, the sample point strobe is internal to the CAN node as a whole, but it is the defining output of the PCS module - it determines *when* `PCS_Data.Indicate` fires at the MAC↔PCS boundary and is therefore directly observable in a PCS-level testbench.

### Canonical Layer Interfaces {#sec:canonical-layer-interfaces}

To make observability judgments repeatable and independent of VHDL implementation choices, the classification is anchored in the **canonical service primitives** defined by ISO 11898-1 [@iso11898_1]. The standard specifies inter-layer boundaries as abstract service access points with named primitives and parameters:

- **LLC ↔ User**: `L_Data.Request`, `L_Data.Confirm`, `L_Data.Indication` - carrying frame content, transfer status, and timestamps (§6.4.5).
- **MAC ↔ PCS**: `PCS_Data.Request(Output_Unit)`, `PCS_Data.Indicate(Input_Unit)` - the bit-level transmission and reception interface; `PCS_Status.Transmitter(D_Transmit)` and `PCS_Status.Receiver(D_Receive)` - signalling the FD data phase (§7.2).
- **MAC ↔ FCE**: Error notifications (`Error(type)`, `Successful_transfer`), state transition requests (`Error_passive_request`, `Error_active_request`), and responses (`Error_passive_response`, `Error_active_response`) (§8.1.3, Tables 16-17).
- **PCS ↔ FCE**: `Bus_off_request`, `Bus_off_release_request` and their responses (§8.1.3, Tables 18-19).

These canonical interfaces serve as the reference frame for observability: a requirement is classified based on whether its postcondition manifests at the relevant layer's canonical boundary, regardless of how the VHDL implementation names its ports or structures its handshaking.

In addition to the interface primitives, each layer has a set of **configurable values** that the testbench knows at instantiation time - entity generics, constants, or driven stimulus. For the PCS, these include the nominal and FD data bit timing parameters from ISO Table 12 (prescaler, propagation segment, phase segments, SJW) and TDC settings (enable flag, SSP offset). For the MAC, the relevant configurations are error signalling enable and protocol exception enable. For the FCE, there are no user-configurable parameters; its behaviour is entirely determined by fixed counting rules and thresholds defined in §8.1.4.

The combination of canonical interfaces and known configurables provides a complete decision framework: if a postcondition is fully determined by boundary primitives, configuration generics, and driven stimulus, it is externally verifiable; if it additionally requires knowledge of an internal algorithm, it is derived; if it has no boundary manifestation at all, it is internal.

### Classification Rules {#sec:classification-rules}

From this framework, three classification rules were defined:

**Rule 1 - External.** A requirement is `external` if its postcondition is fully observable at the layer's own canonical boundary, in one of two forms. *Rule 1a*: the postcondition maps directly onto a named parameter of a canonical service primitive (e.g., "MAC shall present `dominant` Output_Unit when transmitting SOF" - `Output_Unit` is a parameter of `PCS_Data.Request`). *Rule 1b*: the postcondition manifests as the *timing* of a primitive call, and that timing is completely determined by configuration generics and stimulus inputs known to the testbench (e.g., the sample point position equals `brp × (sync_seg + prop_seg + phase_seg1)`, all configuration generics, so the testbench can predict and verify exactly when `PCS_Data.Indicate` fires).

**Rule 2 - Derived.** A requirement is `derived` if its effect manifests at the layer boundary, but verifying correctness requires knowledge of a **non-trivial internal algorithm** beyond reading configuration generics and measuring timing. The distinction between trivial and non-trivial is important: counting stimulus bits or applying fixed positional offsets is trivial (Rule 1b), while polynomial computation (CRC), state-dependent counter arithmetic (FCE error counters), or multi-step protocol state tracking is non-trivial (Rule 2). For example, CRC bits appear in `Output_Unit` calls at the MAC↔PCS boundary, but verifying their correctness requires applying the CRC-15, CRC-17, or CRC-21 polynomial to the preceding data - a non-trivial computation that goes beyond what is directly visible at the interface.

**Rule 3 - Internal.** A requirement is `internal` if its postcondition is a structural definition with no behavioural output (e.g., "the bit time consists of four segments"), a constraint on valid configuration inputs rather than on observable output behaviour (e.g., "Phase_Seg2 shall be ≥ IPT + SJW"), or has no manifestation at any layer boundary even indirectly (e.g., oscillator tolerance specifications that are physical constraints not testable in digital simulation).

Applying these rules to the 168 requirements yielded the following distribution: 106 external (63%), 40 derived (24%), and 22 internal (13%). The high proportion of externally observable requirements reflects the standard's emphasis on bit-level protocol behaviour, which by definition crosses layer boundaries. The internal requirements are concentrated in the PCS layer (configuration constraints and oscillator tolerances) and the FCE (structural definitions of counting concepts). Each requirement's rationale field records which rule was applied and which canonical interface primitive or configurable value justifies the classification, providing a fully auditable trail from ISO clause to testability assessment.

## Verification Plan Construction {#sec:verification-plan-construction}

With the taxonomy and observability framework defined, the next step was to extract and classify the normative requirements from the ISO standard text. This was a two-stage process combining AI-assisted extraction with manual engineering review.

### AI-Assisted Extraction {#sec:ai-assisted-extraction}

The initial extraction of normative "shall" and "should" statements was performed using a **Large Language Model (LLM)**. The ISO standard was provided as a searchable markdown document, and the LLM was prompted to identify normative clauses, extract their wording verbatim, assign a shape and scope classification, and format the result as TOML entries. This task is well-suited for LLMs because it involves processing large volumes of technical text, identifying structural patterns (normative vs. informative language), and reformatting unstructured prose into a consistent structured format. The use of AI significantly accelerated the initial drafting phase and reduced the risk of human oversight during the translation from standard text to a machine-readable plan.

### Human-in-the-Loop Validation {#sec:human-in-the-loop-validation}

The AI-generated extraction served only as a first draft. Every requirement - its wording, assigned shape, scope, layer, and flags - underwent a comprehensive **manual review**. This step was critical to:

- Verify the technical accuracy of the AI's interpretation of protocol nuances (e.g., distinguishing between transmitter-side and receiver-side obligations).
- Refine the shape/scope classification where the standard's wording was ambiguous or where a single clause contained multiple independent requirements (flagged as `COMPOUND`).
- Identify requirements that depend on components outside the TX pipeline (flagged as `EXTERNAL_DEP`) or that are advisory rather than mandatory (flagged as `SHOULD`).
- Ensure that the resulting plan provides a reliable and authoritative basis for the subsequent VHDL implementation and testbench development.

## Storage Format and Tooling {#sec:storage-format-tooling}

The Verification Plan is stored as a single TOML file (`verification_plan/verification_plan.toml`). TOML was selected for two practical reasons: (1) it is easy to read and edit by hand - each requirement is a self-contained `[[requirement]]` block with one key per line, making version-control diffs clean and merge conflicts rare; and (2) it can be parsed and manipulated programmatically by Python tools (specifically `tomlkit`, which preserves comments and formatting on round-trip). This second property was essential for building the automated tooling described below.

Each requirement entry carries metadata fields designed to drive the verification workflow:

| Field | Purpose |
| :--- | :--- |
| `shape` | Classification axis described in @sec:requirement-taxonomy - determines the verification primitive. |
| `scope` | Classification axis described in @sec:requirement-taxonomy - determines the test environment. |
| `layer` | Architectural sub-layer (LLC, MAC, PCS, or FCE), enabling a divide-and-conquer approach where each testbench targets one layer. |
| `precondition` / `event` / `postcondition` | For *triggered*-shape requirements, these three fields form a testable triplet that translates directly into a test procedure. |
| `coverage_target` | Describes how to verify the requirement (e.g., "assert CRC field matches polynomial output", "cover all four frame formats"). |
| `observability` | Layer-relative testability classification (`external`, `derived`, `internal`) as defined in @sec:observability-classification. |
| `observability_rationale` | Auditable justification citing the specific classification rule and canonical interface primitive. |
| `flags` | Marks special properties: `COMPOUND`, `AMBIGUOUS`, `EXTERNAL_DEP`, `SHOULD`, or `DOC_ONLY`. These flags inform review priority and test generation strategy. |
| `label` / `file` | Link the requirement to its implementing assertion label or testbench procedure, providing full traceability from standard clause to RTL. |

: Verification-plan metadata fields and their intended use in workflow automation. {#tbl:vplan-metadata-fields}

To maintain the integrity of the plan as it evolves, a **Model Context Protocol (MCP) server** (`mcp_tools/verification_plan_manager.py`) was developed. The server exposes query, update, insert, delete, and statistics operations as tool calls that the AI coding agent can invoke directly within the development environment. Each write operation creates an automatic backup and validates field values against the schema before committing changes. This design serves two purposes: first, the agent receives summarized query results rather than the entire raw file, avoiding context window bloat; and second, constraining the agent to narrow, validated operations minimizes the risk of data corruption and hallucination - rather than asking the LLM to rewrite a large structured file (where it may silently drop entries, fabricate field values, or break TOML syntax), each MCP call targets a single atomic change with schema-level validation, making such errors structurally impossible.

## Verification Strategy {#sec:verification-strategy}

The verification plan drives a layered testing strategy, where each level targets a different scope of requirements. The observability classification directly informs this strategy: *external* requirements can be verified through port-level stimulus and observation alone, *derived* requirements additionally need a reference model (e.g., a software CRC or error counter model) to compute the expected result, and *internal* requirements are verified through design review or configuration validation rather than simulation.

- **Unit Testing**: Individual modules (Serializer, CRC, Bit Stuffer) are verified in isolation against *frame*-scope requirements. External requirements at this level are verified by driving stimulus and checking output bits; derived requirements (e.g., CRC correctness) use a software reference model for comparison.
- **Protocol Testing**: `tx_can_protocol_tb` verifies frame structure and field timing, covering *node*-scope requirements that involve FSM state and internal counters. Derived FCE requirements (error counter thresholds) are tested by injecting controlled error sequences and observing the resulting state transitions at the MAC↔FCE boundary.
- **Integrated Testing**: `tx_can_tb` verifies end-to-end transmission, retries, and abort scenarios, targeting *bus*-scope requirements that involve multi-node arbitration and acknowledgment.

---

# Design and Architecture {#sec:design-architecture}

## System Overview {#sec:system-overview}
A complete CAN node decomposes into a TX path and an RX path, coordinated by shared Fault Confinement Entity (FCE) and Physical Medium Attachment (PMA) control, as shown in @fig:can-node-architecture. Each path spans three sub-layers - LLC (@sec:llc-sub-layer), MAC (@sec:mac-sub-layer), and PCS (@sec:pcs-sub-layer) - with the LLC frame format defined in @sec:llc-frame-format and interface bundles defined in @sec:interface-definition-tables. A protocol-driven type system (@sec:protocol-driven-type-system) underpins all inter-module interfaces, encoding ISO semantics directly into the VHDL type hierarchy.

```{.mermaid #fig:can-node-architecture caption="CAN node decomposition across LLC, MAC, PCS, FCE, and PMA boundaries. Interface definitions are provided for llc_tx_if (@tbl:llc-tx-if), llc_rx_if (@tbl:llc-rx-if), llc_mac_tx_if (@tbl:llc-mac-tx-if), llc_mac_rx_if (@tbl:llc-mac-rx-if), mac_pcs_if (@tbl:mac-pcs-if), aui_if (@tbl:aui-if), fce_llc_if (@tbl:fce-llc-if), fce_mac_if (@tbl:fce-mac-if), and fce_pcs_if (@tbl:fce-pcs-if)."}
---
config:
  flowchart:
    defaultRenderer: elk
  elk:
    algorithm: layered
    mergeEdges: false
    nodePlacementStrategy: SIMPLE
  look: classic
  theme: neutral
  themeVariables:
    fontFamily: "Libertinus Serif, Noto Serif, serif"
    fontSize: "14px"
---
flowchart TD
    User["**User**"]
    FCE["**can_fce**<br/>─────────<br/>Fault confinement<br/>(FCE, §8.1.3-8.1.4)"]
    PMA["**PMA**<br/>─────────<br/>Physical medium attachment<br/>(§7.4)"]
    subgraph Node ["**CAN Node**<br/>─────────<br/>DLL + PCS, §6.1-6.3"]
        subgraph TX_Pipeline ["**TX Pipeline**"]
            LLC_TX["**can_llc_tx**<br/>─────────<br/>Frame buffering & retransmission<br/>(LLC Sub-layer, §6.4-6.5)"]
            MAC_TX["**can_mac_tx**<br/>─────────<br/>Serialization, CRC & bit stuffing<br/>(MAC Sub-layer, §6.6)"]
            PCS_TX["**can_pcs_tx**<br/>─────────<br/>Bit timing & TDC<br/>(PCS Sub-layer, §7.2-7.4)"]

            LLC_TX <==>|llc_mac_tx_if| MAC_TX <==>|mac_pcs_if| PCS_TX
        end

        subgraph RX_Pipeline ["**RX Pipeline**"]
            LLC_RX["**can_llc_rx**<br/>─────────<br/>Frame delivery & filtering<br/>(LLC Sub-layer, §6.4-6.5)"]
            MAC_RX["**can_mac_rx**<br/>─────────<br/>Deserialization, CRC & destuffing<br/>(MAC Sub-layer, §6.6)"]
            PCS_RX["**can_pcs_rx**<br/>─────────<br/>Bit timing & synchronization<br/>(PCS Sub-layer, §7.2-7.4)"]

            LLC_RX <==>|llc_mac_rx_if| MAC_RX <==>|mac_pcs_if| PCS_RX
        end

        %% Control & Status paths
        FCE <==>|fce_llc_if| LLC_TX
        FCE <==>|fce_mac_if| MAC_TX
        FCE <==>|fce_pcs_if| PCS_TX
        FCE <==>|fce_llc_if| LLC_RX
        FCE <==>|fce_mac_if| MAC_RX
        FCE <==>|fce_pcs_if| PCS_RX
    end

    User <==>|llc_tx_if| LLC_TX
    User <==>|llc_rx_if| LLC_RX
    PCS_TX <==>|aui_if| PMA
    PCS_RX <==>|aui_if| PMA
```

## LLC Frame Format {#sec:llc-frame-format}
The `LLC Frame` format used by the existing CAN-bus implementation (`can_bus_controller`) is depicted in @fig:llc-frame-current with the ID byte format depicted in @tbl:ID-bytes. A revised `LLC Frame` supporting FD is depicted in @fig:llc-frame-revised. The revised format adds a 3-bit `FMT` [@iso11898_1 Sec. 6.4.3] field to the DLC byte (`LLC Frame` byte 4), expands the data field to 64 bytes, and repurposes reserved bits in the last byte for BRS and ESI flags.

The `FMT` encodes the supported frame formats as '`000`' = CB, '`100`' = CE, '`010`' = FB, '`110`' = FE. Accordingly, for the frame content to be self-consistent the IDE bit must be set to `0` for `FMT` = CB/FB and `1` for `FMT` = CE/FE. The revised format is designed to be backward compatible. An implementation that only supports Classic frames can simply ignore the `FMT` bits and treat all frames as Classic, while an implementation that supports FD can use the `FMT` field and the additional control bits (BRS and ESI) to distinguish frame types without affecting the existing ID and data field structure.

```{.mermaid #fig:llc-frame-current caption="Current LLC frame format (15 bytes). ID byte encoding is defined in @tbl:ID-bytes."}
---
look: classic
config:
  theme: neutral
  themeVariables:
    fontFamily: "Libertinus Serif, Noto Serif, serif"
    fontSize: "14px"
  packet:
    bitsPerRow: 8
    bitWidth: 100
    rowHeight: 42
    showBits: true
    paddingX: 0
    paddingY: 1
---
packet
+1: "ID0"
+1: "ID1"
+1: "ID2"
+1: "ID3"
+1: "0000,DLC(3:0)"
+8: "Data(0-7)"
+1: "0000000,IDE"
+1: "0000000,RTR"
```


```{.mermaid #fig:llc-frame-revised caption="Revised LLC frame format with FD support, shown at maximum length (71 bytes). The FMT field selects frame type; BRS and ESI repurpose reserved bits in the final byte. ID byte encoding is defined in @tbl:ID-bytes."}
---
look: classic
config:
  theme: neutral
  themeVariables:
    fontFamily: "Libertinus Serif, Noto Serif, serif"
    fontSize: "14px"
  packet:
    bitsPerRow: 8
    bitWidth: 100
    rowHeight: 42
    showBits: true
    paddingX: 0
    paddingY: 1
---
packet
+1: "ID0"
+1: "ID1"
+1: "ID2"
+1: "ID3"
+1: "0,FMT(2:0),DLC(3:0)"
+64: "Data(0-63)"
+1: "0000000,IDE"
+1: "00000,BRS,ESI,RTR"
```


| Format     | Byte ID0 | Byte ID1 | Byte ID2 | Byte ID3 |
| --- | --- | --- | --- | --- | 
| Basic | '`00000000`' | '`00000000`' | '`00000`' `&` '`ID(10-8)`' | '`ID(7-0)`' | 
| Extended | '`000`' `&` '`ID(28:24)`' | '`ID(23-16)`' | '`ID(15-8)`' | '`ID(7-0)`' | 

: ID byte encoding for the LLC frame formats shown in @fig:llc-frame-current and @fig:llc-frame-revised. {#tbl:ID-bytes}

## Interface Definition Tables {#sec:interface-definition-tables}

The interface bundles shown in @fig:can-node-architecture are defined in full below, with each signal mapped to its corresponding ISO 11898-1 service primitive, [@iso11898_1]. This normative anchoring provides a direct traceability path from protocol clauses to VHDL ports. The types used in these interfaces are defined in @sec:protocol-driven-type-system.

The semantic protocol types described in @sec:protocol-driven-type-system are used internally within the MAC layer and at the MAC-PCS boundary, where frame context must be carried alongside each bit. The LLC layer operates purely on bytes - the LLC frame format (@sec:llc-frame-format) is defined in terms of plain data fields with no protocol-semantic typing. The AUI interface (`aui_if`) uses `std_logic` throughout, as it crosses outside the ISO protocol domain into the physical medium. The one exception is `transfer_status_t`, which propagates a frame outcome from the MAC layer back through the LLC to the user. The LLC-User interface (`llc_tx_if`, `llc_rx_if`) is implemented as an Avalon-ST byte stream to maintain backward compatibility with the existing CAN bus controller, which uses the same `valid`/`ready`/`startofpacket` handshake convention.

::: {.landscape-tables}


| ISO ref. | ISO symbol | ISO payload | ISO semantics | Direction | Implementation mapping | Implementation notes |
| --- | --- | --- | --- | --- | --- | --- |
| 6.4.5.5.2 | `L_Data.Request` | `LLC Frame`, `Handle` | Submit LLC frame for transmission | `User -> LLC` | `llc_tx_if.data` (`byte_t`), `llc_tx_if.valid` (`std_logic`), `llc_tx_if.sop` (`std_logic`) | `valid` high with byte on data; `sop` asserted on first byte |
| 6.4.5.5.2 | `L_Data.Request` | `LLC Frame`, `Handle` | Submit LLC frame for transmission | `User -> LLC` | `llc_tx_if.data` (`byte_t`), `llc_tx_if.valid` (`std_logic`) | `valid` high; `sop` and `eop` deasserted on intermediate bytes |
| 6.4.5.5.2 | `L_Data.Request` | `LLC Frame`, `Handle` | Submit LLC frame for transmission | `User -> LLC` | `llc_tx_if.data` (`byte_t`), `llc_tx_if.valid` (`std_logic`), `llc_tx_if.eop` (`std_logic`) | `valid` high with byte on data; `eop` asserted on last byte |
| 6.4.5.5.2 | `L_Data.Request` | | Flow control | `LLC -> User` | `llc_tx_if.ready` (`std_logic`) | Asserted by LLC when able to consume next byte |
| 6.4.5.5.3 | `L_Data.AbortRequest` | `Handle` | Abort pending frame transfer | `User -> LLC` | `llc_tx_if.abort_request` (`std_logic`) | Pulse when user wants to cancel an in-progress transfer |

: Interface definition for `llc_tx_if`. Implements `L_Data.Request` as an Avalon-ST byte stream. `L_Data.AbortRequest` is included for complete ISO service coverage but is not yet implemented. {#tbl:llc-tx-if}


| ISO ref. | ISO symbol | ISO payload | ISO semantics | Direction | Implementation mapping | Implementation notes |
| --- | --- | --- | --- | --- | --- | --- |
| 6.4.5.5.5 | `L_Data.Indication` | `LLC Frame`, `Timestamp` | Deliver received LLC frame to user | `LLC -> User` | `llc_rx_if.data` (`byte_t`), `llc_rx_if.valid` (`std_logic`), `llc_rx_if.sop` (`std_logic`) | `valid` high with byte on data; `sop` asserted on first byte |
| 6.4.5.5.5 | `L_Data.Indication` | `LLC Frame`, `Timestamp` | Deliver received LLC frame to user | `LLC -> User` | `llc_rx_if.data` (`byte_t`), `llc_rx_if.valid` (`std_logic`) | `valid` high; `sop` and `eop` deasserted on intermediate bytes |
| 6.4.5.5.5 | `L_Data.Indication` | `LLC Frame`, `Timestamp` | Deliver received LLC frame to user | `LLC -> User` | `llc_rx_if.data` (`byte_t`), `llc_rx_if.valid` (`std_logic`), `llc_rx_if.eop` (`std_logic`) | `valid` high with byte on data; `eop` asserted on last byte |
| 6.4.5.5.5 | `L_Data.Indication` | | Flow control | `User -> LLC` | `llc_rx_if.ready` (`std_logic`) | Asserted by user when able to consume next byte |
| 6.4.5.5.4 | `L_Data.Confirm` | `Transfer_Status`, `Timestamp`, `Handle` | Report outcome of prior `L_Data.Request` | `LLC -> User` | `llc_rx_if.transfer_status` (`transfer_status_t`) | Issued on frame completion, loss, or error |

: Interface definition for `llc_rx_if`. Implements `L_Data.Indication` as an Avalon-ST byte stream. `Timestamp` is included for complete ISO service coverage but is not yet implemented. {#tbl:llc-rx-if}


| ISO ref. | ISO symbol | ISO payload | ISO semantics | Direction | Implementation mapping | Implementation notes |
| --- | --- | --- | --- | --- | --- | --- |
| 6.3, 6.6.4.2 | `DLL SDU` | `LLC Frame` | Transfer LLC frame to MAC for serialization | `LLC -> MAC` | `llc_mac_tx_if.data` (`byte_t`), `llc_mac_tx_if.valid` (`std_logic`), `llc_mac_tx_if.sop` (`std_logic`) | `valid` high with byte on data; `sop` marks first byte of new frame |
| 6.3, 6.6.4.2 | `DLL SDU` | | Flow control | `MAC -> LLC` | `llc_mac_tx_if.ready` (`std_logic`) | Asserted by MAC serializer when able to consume next byte |
| 6.6.4.2 | Interface control information | `Transfer_Status` | Report frame transmission outcome | `MAC -> LLC` | `llc_mac_tx_if.transfer_status` (`transfer_status_t`) | Updated by MAC on completion, loss, or error |

: Interface definition for `llc_mac_tx_if`. Frame length is self-describing from the DLC config bytes; the MAC serializer does not consume `eop`. {#tbl:llc-mac-tx-if}


| ISO ref. | ISO symbol | ISO payload | ISO semantics | Direction | Implementation mapping | Implementation notes |
| --- | --- | --- | --- | --- | --- | --- |
| 6.6.4.3, 6.6.9 | `DLL SDU` | Reconstructed `LLC Frame` | Transfer reconstructed LLC frame to LLC | `MAC -> LLC` | | Issued when MAC has reconstructed a frame from the received bitstream |
| 6.6.3 | Time reference notification | `SOF/frame-valid indication` | Provide timing reference for timestamping | `MAC -> LLC` | | Generated for transmitted/received DF/RF |

: Interface definition for `llc_mac_rx_if`. Carries the reconstructed LLC frame from `can_mac_rx` to `can_llc_rx` (@sec:can-mac-rx). Full decomposition of RX sub-module interfaces is deferred to future work. {#tbl:llc-mac-rx-if}


| ISO ref. | ISO symbol | ISO payload | ISO semantics | Direction | Implementation mapping | Implementation notes |
| --- | --- | --- | --- | --- | --- | --- |
| 7.2.1, 7.2.2 | `PCS_Data.Request` | `Output_Unit` | Present next bit for transmission | `MAC -> PCS` | `mac_pcs_if.data` (`mac_frame_bit_t`) | MAC holds bit stable; PCS samples `data` at each bit boundary autonomously |
| 7.2.1, 7.2.5 | `PCS_Status.Transmitter` | `D_Transmit` | Indicate FD data-phase interval to PCS | `MAC -> PCS` | `mac_pcs_if.data.bit_name` (`mac_frame_bit_name_t`) | PCS enters data phase at `fdf_bit` SP, exits at `crc_delimiter_bit` or error flag boundary |
| 7.2.1, 7.2.3 | `PCS_Data.Indicate` | `Input_Unit` | Indicate bus polarity at sample point | `PCS -> MAC` | `mac_pcs_if.bus_polarity` (`polarity_t`), `mac_pcs_if.sample_strobe` (`std_logic`), `mac_pcs_if.strobe_type` (`strobe_type_t`), `mac_pcs_if.fifo_index` (`integer`) | `sample_strobe` pulses once per SP/SSP; `strobe_type` distinguishes SP from SSP for TDC |
| 7.2.1, 7.2.6 | `PCS_Status.Receiver` | `D_Receive` | Indicate FD data-phase interval to PCS | `MAC -> PCS` | not yet implemented | Asserted during FD data-phase reception |

: Interface definition for `mac_pcs_if`. The `D_Transmit` status is encoded directly in `mac_pcs_if.data.bit_name` rather than as a separate signal - the PCS derives data-phase entry and exit from the protocol-semantic bit name, eliminating the need for a redundant boolean flag. {#tbl:mac-pcs-if}


| ISO ref. | ISO symbol | ISO payload | ISO semantics | Direction | Implementation mapping | Implementation notes |
| --- | --- | --- | --- | --- | --- | --- |
| 7.4.2.1 | `output symbol` | `Dominant/recessive symbol` | Drive physical output symbol | `PCS -> PMA` | `aui_if.tx` (`std_logic`) | Updated on each `Output_Unit` request |
| 7.4.2.2, 8.1.3.4 | `bus_off symbol` | `Bus-off control` | Switch node off bus | `PCS -> PMA` | `aui_if.bus_off` (`std_logic`) | On `Bus_off_request` from FCE |
| 7.4.2.3, 8.1.3.4 | `bus_off_release symbol` | `Bus-off release control` | Release node from bus-off | `PCS -> PMA` | `aui_if.bus_off_release` (`std_logic`) | On `Bus_off_release_request` from FCE |
| 7.4.3 | `input symbol` | `Dominant/recessive symbol` | Indicate physical input symbol | `PMA -> PCS` | `aui_if.rx` (`std_logic`) | Continuously driven by PMA |

: Interface definition for `aui_if`. All signals are `std_logic`, as this interface crosses from the ISO protocol domain into the physical medium. {#tbl:aui-if}


| ISO ref. | ISO symbol | ISO payload | ISO semantics | Direction | Implementation mapping | Implementation notes |
| --- | --- | --- | --- | --- | --- | --- |
| 8.1.3.2 | `Normal_mode_request` | `Mode request` | Request reset to normal mode | `LLC -> FCE` | `fce_llc_if.normal_mode_request` (`boolean`) | Issued on startup/restart |
| 8.1.3.2 | `Normal_mode_response` | `Mode response` | Acknowledge normal-mode request | `FCE -> LLC` | `fce_llc_if.normal_mode_response` (`boolean`) | Returned after FCE processing |
| 8.1.3.2 | `Bus_off` | `Bus-off status` | Indicate node is bus-off | `FCE -> LLC` | `fce_llc_if.bus_off` (`boolean`) | Asserted on bus-off transition |

: Interface definition for `fce_llc_if`. Carries bus-off status and mode-request handshake between the FCE and LLC layers [@iso11898_1, sec. 8.1.3.2]. {#tbl:fce-llc-if}


| ISO ref. | ISO symbol | ISO payload | ISO semantics | Direction | Implementation mapping | Implementation notes |
| --- | --- | --- | --- | --- | --- | --- |
| 8.1.3.3 | `Transmit/receive` | `Transfer mode context` | Report current TX/RX context | `MAC -> FCE` | `fce_mac_if.transmitting` (`boolean`) | Updated with MAC transfer context |
| 8.1.3.3 | `Error` | `Error event` | Report detected protocol error | `MAC -> FCE` | `fce_mac_if.error` (`boolean`) | Pulse on bit/stuff/CRC/form/ACK error |
| 8.1.3.3 | `Primary_error` | `Primary error event` | Report primary error condition | `MAC -> FCE` | `fce_mac_if.primary_error` (`boolean`) | Pulse on primary error condition |
| 8.1.3.3 | `Error/overload flag` | `EF/OF state` | Report EF/OF transmission state | `MAC -> FCE` | `fce_mac_if.sending_error_flag` (`boolean`) | Asserted during EF/OF transmission |
| 8.1.3.3 | `Counters_unchanged` | `Counter-update qualifier` | Qualify counter exception path | `MAC -> FCE` | `fce_mac_if.counters_unchanged` (`boolean`) | Asserted on rule-c exception cases |
| 8.1.3.3 | `Error_delimiter_too_late` | `Late delimiter event` | Report late error-delimiter condition | `MAC -> FCE` | `fce_mac_if.error_delimiter_too_late` (`boolean`) | Asserted on late delimiter condition |
| 8.1.3.3 | `Successful_transfer` | `Transfer completion event` | Report successful TX/RX completion | `MAC -> FCE` | `fce_mac_if.successful_transfer` (`boolean`) | Pulse on successful frame transfer |
| 8.1.3.3 | `Error_passive_response` | `State response` | Report entry into error-passive state | `MAC -> FCE` | `fce_mac_if.error_passive_response` (`boolean`) | On state transition completion |
| 8.1.3.3 | `Error_active_response` | `State response` | Report return to error-active state | `MAC -> FCE` | `fce_mac_if.error_active_response` (`boolean`) | On state transition completion |
| 8.1.3.3 | `Error_passive_request` | `State request` | Request MAC enter error-passive state | `FCE -> MAC` | `fce_mac_if.error_passive` (`boolean`) | On TEC/REC threshold crossing |
| 8.1.3.3 | `Error_active_request` | `State request` | Request MAC return to error-active state | `FCE -> MAC` | `fce_mac_if.error_active` (`boolean`) | On TEC/REC recovery |

: Interface definition for `fce_mac_if`. The MAC reports error events and frame outcomes to the FCE; the FCE returns the current error-active/passive state to the MAC [@iso11898_1, sec. 8.1.3.3]. {#tbl:fce-mac-if}


| ISO ref. | ISO symbol | ISO payload | ISO semantics | Direction | Implementation mapping | Implementation notes |
| --- | --- | --- | --- | --- | --- | --- |
| 8.1.3.4 | `Bus_off_request` | `Bus-off request` | Request node switch-off from bus | `FCE -> PCS` | `fce_pcs_if.bus_off_request` (`boolean`) | On bus-off transition condition |
| 8.1.3.4 | `Bus_off_release_request` | `Bus-off release request` | Request node re-enable from bus-off | `FCE -> PCS` | `fce_pcs_if.bus_off_release_request` (`boolean`) | On restart/reintegration |
| 8.1.3.4 | `Bus_off_response` | `Bus-off response` | Acknowledge bus-off request | `PCS -> FCE` | `fce_pcs_if.bus_off_response` (`boolean`) | Returned after bus-off action |
| 8.1.3.4 | `Bus_off_release_response` | `Bus-off release response` | Acknowledge bus-off-release request | `PCS -> FCE` | `fce_pcs_if.bus_off_release_response` (`boolean`) | Returned after release action |

: Interface definition for `fce_pcs_if`. Carries bus-off and bus-off-release request/response handshakes between the FCE and PCS layers [@iso11898_1, sec. 8.1.3.4]. {#tbl:fce-pcs-if}
:::

## Protocol-Driven Type System {#sec:protocol-driven-type-system}

The type system encodes protocol semantics directly into the interface bundles defined in @sec:interface-definition-tables. This makes the protocol semantics visible in the implementation and in simulation waveforms. As shown in @fig:types-diagram, the hierarchy is rooted in ISO-derived protocol constants, from which frame layout constants, semantic enumeration types, and composite record types are derived.

```{.mermaid #fig:types-diagram caption="Type and constant hierarchy. The Semantic Protocol Primitives namespace groups the enumeration types and subtypes that comprise the protocol semantic primitives. Compound record types compose these primitives: bit_t pairs a bit position with a polarity and underpins the frame layout constants. mac_frame_bit_t carries semantic context by combining a polarity with a protocol bit name, so each transmitted bit remains identifiable throughout the design. frame_params_t aggregates format flags, field boundary positions, and format-specific control bit positions, computed once per frame (@sec:can-mac-ser-tx). observed_mac_frame_bit_info_t and transmitted_bits_fifo_t support bus monitoring and TDC-delayed bit comparison (@sec:can-mac-fsm-tx). Constant groups derive from the root protocol constants."}
---
config:
  layout: elk
  elk:
    algorithm: layered
    mergeEdges: false
    nodePlacementStrategy: SIMPLE
    edgeRouting: ORTHOGONAL
  look: classic
  theme: neutral
  themeVariables:
    fontFamily: "Libertinus Serif, Noto Serif, serif"
    fontSize: "14px"
    primaryTextColor: "#000"
  class:
    hideEmptyMembersBox: true
---
classDiagram

    %% 1. Semantic Protocol Primitives ========================================

    namespace `**Semantic Protocol Primitives**` {
        class polarity_t["type polarity_t"]
        class can_format_t["type can_format_t"]
        class mac_frame_bit_name_t["type mac_frame_bit_name_t"]
        class position_t["subtype position_t"]
        class strobe_type_t["type strobe_type_t"]
        class transfer_status_t["type transfer_status_t"]
        class tx_mac_monitor_event_t["type tx_mac_monitor_event_t"]
    }

    polarity_t : dominant
    polarity_t : recessive

    can_format_t : cc_basic
    can_format_t : cc_extended
    can_format_t : fd_basic
    can_format_t : fd_extended

    mac_frame_bit_name_t : active_error_flag_bit
    mac_frame_bit_name_t : passive_error_flag_bit
    mac_frame_bit_name_t : overload_flag_bit
    mac_frame_bit_name_t : bus_integration_bit
    mac_frame_bit_name_t : intermission_bit
    mac_frame_bit_name_t : suspend_transmission_bit
    mac_frame_bit_name_t : idle_bit
    mac_frame_bit_name_t : stuff_bit
    mac_frame_bit_name_t : fixed_stuff_bit
    mac_frame_bit_name_t : sof_bit
    mac_frame_bit_name_t : base_id_bit
    mac_frame_bit_name_t : extended_id_bit
    mac_frame_bit_name_t : rtr_bit
    mac_frame_bit_name_t : srr_bit
    mac_frame_bit_name_t : rrs_bit
    mac_frame_bit_name_t : ide_bit
    mac_frame_bit_name_t : r0_bit
    mac_frame_bit_name_t : r1_bit
    mac_frame_bit_name_t : fdf_bit
    mac_frame_bit_name_t : res_bit
    mac_frame_bit_name_t : brs_bit
    mac_frame_bit_name_t : esi_bit
    mac_frame_bit_name_t : dlc_bit
    mac_frame_bit_name_t : data_bit
    mac_frame_bit_name_t : sbs_bit
    mac_frame_bit_name_t : crc_bit
    mac_frame_bit_name_t : crc_delimiter_bit
    mac_frame_bit_name_t : ack_bit
    mac_frame_bit_name_t : ack_delimiter_bit
    mac_frame_bit_name_t : eof_bit
    mac_frame_bit_name_t : error_delimiter_bit

    position_t : integer range 0 to max_mac_frame_length_c

    strobe_type_t : sp_strobe
    strobe_type_t : ssp_strobe

    transfer_status_t : ongoing
    transfer_status_t : lost_arbitration
    transfer_status_t : transmitted
    transfer_status_t : aborted
    transfer_status_t : disturbed

    tx_mac_monitor_event_t : none
    tx_mac_monitor_event_t : ack_detected
    tx_mac_monitor_event_t : ack_error
    tx_mac_monitor_event_t : bit_error
    tx_mac_monitor_event_t : lost_arbitration

    %% 2. Compound Record Types =====================================

    class bit_t["record bit_t"]
    bit_t : position position_t
    bit_t : polarity polarity_t

    class mac_frame_bit_t["record mac_frame_bit_t"]
    mac_frame_bit_t : polarity polarity_t
    mac_frame_bit_t : bit_name mac_frame_bit_name_t

    class frame_params_t["record frame_params_t"]
    frame_params_t : format can_format_t
    frame_params_t : is_fd_frame boolean
    frame_params_t : ⋮
    frame_params_t : data_start position_t
    frame_params_t : crc_start position_t
    frame_params_t : ⋮
    frame_params_t : fdf_bit bit_t
    frame_params_t : brs_bit bit_t
    frame_params_t : ⋮

    class observed_mac_frame_bit_info_t["record observed_mac_frame_bit_info_t"]
    observed_mac_frame_bit_info_t : event_type tx_mac_monitor_event_t
    observed_mac_frame_bit_info_t : transfer_status transfer_status_t
    observed_mac_frame_bit_info_t : expected_bit mac_frame_bit_t
    observed_mac_frame_bit_info_t : observed_polarity polarity_t

    class transmitted_bits_fifo_t["type transmitted_bits_fifo_t"]
    transmitted_bits_fifo_t : array of mac_frame_bit_t

    %% 3. Constant Groups ==============================================

    class protocol_constants["Protocol Constants"]
    protocol_constants : constant sof_c integer = 0
    protocol_constants : constant max_mac_frame_length_c integer = 640
    protocol_constants : constant base_id_width_c integer = 11
    protocol_constants : ⋮

    class frame_layout_constants["Frame Layout Constants"]
    frame_layout_constants : constant cb_ide_c bit_t
    frame_layout_constants : constant fb_fdf_c bit_t
    frame_layout_constants : constant fe_brs_c bit_t
    frame_layout_constants : ⋮

    class common_frame_bits["Common Frame Bits"]
    common_frame_bits : constant sof_bit_c mac_frame_bit_t
    common_frame_bits : constant active_error_flag_bit_c mac_frame_bit_t
    common_frame_bits : constant eof_bit_c mac_frame_bit_t
    common_frame_bits : ⋮

    %% 4. Relationships ===============================================

    position_t ..> protocol_constants
    frame_layout_constants ..> protocol_constants
    common_frame_bits ..> protocol_constants
    bit_t *-- position_t
    bit_t *-- polarity_t
    mac_frame_bit_t *-- polarity_t
    mac_frame_bit_t *-- mac_frame_bit_name_t
    frame_layout_constants ..> bit_t
    common_frame_bits ..> mac_frame_bit_t
    frame_params_t *-- can_format_t
    frame_params_t *-- position_t
    frame_params_t *-- bit_t
    frame_params_t ..> frame_layout_constants
    observed_mac_frame_bit_info_t *-- tx_mac_monitor_event_t
    observed_mac_frame_bit_info_t *-- transfer_status_t
    observed_mac_frame_bit_info_t *-- mac_frame_bit_t
    observed_mac_frame_bit_info_t *-- polarity_t
    transmitted_bits_fifo_t ..> mac_frame_bit_t
```

## LLC Sub-layer {#sec:llc-sub-layer}
Responsible for frame buffering and retransmission management. It provides an Avalon-ST interface to the user application and communicates with the FCE to handle retransmission limits and error status reporting.

### `can_llc_tx` {#sec:can-llc-tx}

`can_llc_tx` buffers an incoming LLC frame from the user, streams it byte-by-byte to the MAC serializer, and manages retransmission on bus disturbance up to the ISO-mandated limit [@iso11898_1, sec. 6.4.5 and 6.5].

### `can_llc_rx` {#sec:can-llc-rx}

`can_llc_rx` receives a reconstructed LLC frame from the MAC layer, applies acceptance filtering, and delivers accepted frames to the user over the `llc_rx_if` Avalon-ST stream [@iso11898_1, sec. 6.4.5].

## MAC Sub-layer {#sec:mac-sub-layer}
The MAC sub-layer is the core of the protocol logic, responsible for bit serialization, CRC generation, bit stuffing, and frame-level error detection. It coordinates closely with the FCE (@sec:fce-sub-layer) for error counter management and node-state transitions (Error Active/Passive/Bus Off), and with the PCS (@sec:pcs-sub-layer) for sample-point-driven bit output.

The earlier CAN bus controller concentrated TX, RX, MAC, and FCE logic in a single monolithic FSM (`can_fsm`), with the sub-functions - serialization (`can_ast_to_serial`), bit stuffing (`can_stuff_bit_gen`), and CRC (`gen_crc`) - implemented in satellite modules driven directly by it. PCS timing logic was implemented in `can_node_clock`, which fed sample-point and transmit pulses into `can_fsm` - a strategy retained in the current design.

The current design restructures these modules around the ISO 11898-1 [@iso11898_1] layer boundaries. On the TX side the mapping is direct: `can_ast_to_serial` becomes `can_mac_ser_tx` (@sec:can-mac-ser-tx), `can_stuff_bit_gen` becomes `can_mac_bs_tx` (@sec:can-mac-bs-tx), `gen_crc` becomes `can_mac_crc_tx` (@sec:can-mac-crc-tx), and `can_node_clock` becomes `can_pcs_tx` (@sec:can-pcs-tx). The RX-side counterparts - deserialization (`can_serial_to_ast`), bit destuffing, and CRC checking - will map to submodules within `can_mac_rx` (@sec:can-mac-rx). Fault confinement, previously embedded in `can_fsm`, is separated into its own layer.

### `can_mac_tx` {#sec:can-mac-tx}

The `can_mac_tx` (@fig:mac-tx-architecture) is composed of four main components:

1. **can_mac_ser_tx**: Converts LLC bytes into a serial bit stream with polarity information
2. **can_mac_fsm_tx**: Coordinates frame transmission, controls all submodules
3. **can_mac_bs_tx**: Implements CAN/CAN-FD bit stuffing rules
4. **can_mac_crc_tx**: Generates CRC-15/CRC-17/CRC-21 based on frame type

```{.mermaid #fig:mac-tx-architecture fig-width=0.5 caption="can_mac_tx architecture showing internal component interconnections and external interfaces. Internal interface definitions are provided for can_mac_fsm_ser_tx_if (@tbl:mac-fsm-ser-if), can_mac_fsm_bs_tx_if (@tbl:mac-fsm-bs-if), and can_mac_fsm_crc_tx_if (@tbl:mac-fsm-crc-if)."}
---
config:
  flowchart:
    defaultRenderer: elk
  elk:
    algorithm: layered
    mergeEdges: false
    nodePlacementStrategy: SIMPLE
  look: classic
  theme: neutral
  themeVariables:
    fontFamily: "Libertinus Serif, Noto Serif, serif"
    fontSize: "14px"
---
flowchart TD
    LLC["**can_llc_tx**<br/>─────────<br/>LLC Sub-layer, §6.4-6.5"]
    PCS["**can_pcs_tx**<br/>─────────<br/>PCS Sub-layer, §7.2-7.4"]
    FCE["**can_fce**<br/>─────────<br/>FCE, §8.1.3-8.1.4"]

    subgraph MAC_TX ["**can_mac_tx**<br/>─────────<br/>MAC Sub-layer, §6.6"]
        SER["**can_mac_ser_tx**<br/>─────────<br/>LLC Frame Serializer"]
        FSM["**can_mac_fsm_tx**<br/>─────────<br/>Controlling FSM"]
        BS["**can_mac_bs_tx**<br/>─────────<br/>Bit Stuffer"]
        CRC["**can_mac_crc_tx**<br/>─────────<br/>CRC Generator"]

        SER <==>|can_mac_fsm_ser_tx_if| FSM
        FSM <==>|can_mac_fsm_bs_tx_if| BS
        FSM <==>|can_mac_fsm_crc_tx_if| CRC
    end

    LLC <==>|llc_mac_tx_if| SER

    FSM <==>|mac_pcs_if| PCS
    FSM <==>|fce_mac_if| FCE
```

#### `can_mac_tx` Internal Interfaces {#sec:mac-internal-interfaces}

The interfaces between MAC sub-components are implementation-defined and carry no direct ISO service primitive mapping. @tbl:mac-fsm-ser-if, @tbl:mac-fsm-bs-if, and @tbl:mac-fsm-crc-if define each bidirectional bundle; the Direction column identifies the driving component for each field.


| field | type | direction | description |
| --- | --- | --- | --- |
| `data` | `polarity_t` | `ser → fsm` | current bit polarity; fsm reads this when `valid` is asserted |
| `valid` | `boolean` | `ser → fsm` | asserted while a bit is available for the fsm to consume |
| `frame_params` | `frame_params_t` | `ser → fsm` | frame parameters computed from the two config bytes; valid for the lifetime of the frame |
| `ready` | `boolean` | `fsm → ser` | pulsed when the fsm has consumed the current bit; advances the serializer to the next bit |
| `transfer_status` | `transfer_status_t` | `fsm → ser` | frame outcome; any non-`ongoing` value terminates serialization |

: interface definition for `can_mac_fsm_ser_tx_if`, connecting `can_mac_ser_tx` and `can_mac_fsm_tx` (see @fig:mac-tx-architecture). {#tbl:mac-fsm-ser-if}


| field | type | direction | description |
| --- | --- | --- | --- |
| `data` | `polarity_t` | `fsm → bs` | bit polarity fed into the bit stuffer |
| `valid` | `boolean` | `fsm → bs` | pulsed when a new bit is presented to the stuffer |
| `start` | `boolean` | `fsm → bs` | pulsed at frame start to reinitialize the stuffer state |
| `data` | `polarity_t` | `bs → fsm` | polarity of the required stuff bit |
| `valid` | `boolean` | `bs → fsm` | asserted when a stuff bit insertion is required |
| `sbc` | `std_logic_vector(3:0)` | `bs → fsm` | gray-coded stuff bit count with parity, used in the fd fixed-stuffing region |

: interface definition for `can_mac_fsm_bs_tx_if`, connecting `can_mac_fsm_tx` and `can_mac_bs_tx` (see @fig:mac-tx-architecture). {#tbl:mac-fsm-bs-if}


| field | type | direction | description |
| --- | --- | --- | --- |
| `crc_poly_select` | `std_logic_vector(1:0)` | `fsm → crc` | selects the active crc polynomial: crc-15, crc-17, or crc-21 |
| `valid` | `boolean` | `fsm → crc` | pulsed when `data` should be included in the crc accumulation |
| `data` | `std_logic` | `fsm → crc` | bit value to feed into the crc engine |
| `crc` | `crc_vector_t` | `crc → fsm` | current crc register value; fsm reads this when serializing the crc field |

: interface definition for `can_mac_fsm_crc_tx_if`, connecting `can_mac_fsm_tx` and `can_mac_crc_tx` (see @fig:mac-tx-architecture). {#tbl:mac-fsm-crc-if}

#### `can_mac_fsm_tx` {#sec:can-mac-fsm-tx}

`can_mac_fsm_tx` (@fig:mac-tx-fsm) orchestrates frame transmission, coordinating the serializer (@sec:can-mac-ser-tx), bit stuffer (@sec:can-mac-bs-tx), and CRC engine (@sec:can-mac-crc-tx). On each sample-point strobe from `can_pcs_tx` (@sec:can-pcs-tx), the `transmitting_frame` state executes the following sequence:

1. The observed bus polarity is compared against the transmitted bit to detect errors and arbitration loss.
2. In the CAN-FD data phase, any pending SSP observation from the previous bit period is evaluated first [@iso11898_1, sec. 7.3.4].
3. The next output bit is determined - stuff bit or next frame bit - and the CRC is updated.
4. Any detected error triggers a transition to the appropriate error flag state based on the FCE fault confinement status [@iso11898_1, sec. 8.1.3-8.1.4].

```{.mermaid #fig:mac-tx-fsm caption="can_mac_fsm_tx FSM. After a successful frame or arbitration loss the FSM passes through intermission before returning to idle. Detected errors branch to either the active (dominant) or passive (recessive) error flag state depending on FCE fault confinement status. Both paths then rejoin the common intermission sequence. Overload frames can be injected from intermission or from either error flag state."}
---
config:
  layout: elk
  elk:
    algorithm: layered
    mergeEdges: false
    nodePlacementStrategy: LINEAR_SEGMENTS
  look: classic
  theme: neutral
  themeVariables:
    fontFamily: "Libertinus Serif, Noto Serif, serif"
    fontSize: "14px"
    primaryTextColor: "#000"
---
stateDiagram-v2

  state "**bus_reintegration**<br/>─────────<br/>• Bus not driving<br/>• Await idle condition" as bus_reintegration
  state "**bus_idle**<br/>─────────<br/>• Bus not driving<br/>• Await frame request" as bus_idle
  state "**transmitting_frame**<br/>─────────<br/>• Driving frame bits<br/>• Monitoring bus" as transmitting_frame
  state "**transmitting_active_error_flag**<br/>─────────<br/>• Driving dominant error flag<br/>• Signalling error to FCE" as transmitting_active_error_flag
  state "**transmitting_passive_error_flag**<br/>─────────<br/>• Driving recessive error flag<br/>• Signalling error to FCE" as transmitting_passive_error_flag
  state "**transmitting_overload_flag**<br/>─────────<br/>• Driving dominant overload flag<br/>• Signalling error to FCE" as transmitting_overload_flag
  state "**intermission**<br/>─────────<br/>• Bus not driving<br/>• Monitoring for overload" as intermission
  state "**suspend_transmission**<br/>─────────<br/>• Bus not driving<br/>• Error-passive hold-off" as suspend_transmission


[*] --> bus_reintegration : reset
bus_reintegration --> bus_idle : bus idle

bus_idle --> transmitting_frame : frame pending

transmitting_frame --> intermission : frame complete
transmitting_frame --> intermission : lost arbitration
transmitting_frame --> transmitting_active_error_flag : error detected
transmitting_frame --> transmitting_passive_error_flag : error detected

transmitting_active_error_flag --> intermission : sequence complete
transmitting_active_error_flag --> transmitting_overload_flag : overload detected

transmitting_passive_error_flag --> intermission : sequence complete
transmitting_passive_error_flag --> transmitting_overload_flag : overload detected

transmitting_overload_flag --> intermission : sequence complete
transmitting_overload_flag --> transmitting_overload_flag : overload detected

intermission --> bus_idle : intermission complete
intermission --> suspend_transmission : error-passive transmitter
intermission --> transmitting_overload_flag : overload detected

suspend_transmission --> bus_idle : suspend complete
suspend_transmission --> transmitting_overload_flag : overload detected
```

#### `can_mac_ser_tx` {#sec:can-mac-ser-tx}

`can_mac_ser_tx` converts the LLC byte stream into a serial polarity bit stream for the MAC FSM. Its four-state FSM (@fig:mac-ser-fsm-tx) manages the two-byte configuration handshake, byte fetching, and bit-by-bit serialization.

```{.mermaid #fig:mac-ser-fsm-tx fig-width=0.6 caption="can_mac_ser_tx FSM. The serializer accepts LLC frame bytes over a ready/valid handshake and shifts them out MSB-first to the MAC FSM one bit per ready pulse. Frame parameters are computed once from the two config bytes and cached in frame_params_t for use by the FSM throughout the frame."}
---
config:
  layout: elk
  elk:
    algorithm: layered
    mergeEdges: false
    nodePlacementStrategy: LINEAR_SEGMENTS
  look: classic
  theme: neutral
  themeVariables:
    fontFamily: "Libertinus Serif, Noto Serif, serif"
    fontSize: "14px"
    primaryTextColor: "#000"
---
stateDiagram-v2

  state "**load_config_byte_0**<br/>─────────<br/>• Idle, awaiting new frame" as s0
  state "**load_config_byte_1**<br/>─────────<br/>• Awaiting config byte 1" as s1
  state "**load_llc_frame_byte**<br/>─────────<br/>• Fetching next byte from LLC stream" as s2
  state "**shift_out_bits**<br/>─────────<br/>• Shift out MSB on MAC FSM ready pulse" as s3

  [*] --> s0 : reset

  s0 --> s1 : config byte 0 received from LLC

  s1 --> s2 : config byte 1 received from LLC, frame_params_t computed

  s2 --> s3 : data byte received from LLC

  s3 --> s0 : transmission complete
  s3 --> s2 : byte serialized
```

#### `can_mac_bs_tx` {#sec:can-mac-bs-tx}

`can_mac_bs_tx` implements dynamic bit stuffing for both CAN Classic and CAN-FD frames [@iso11898_1, sec. 10.6]. It monitors the polarity stream from the FSM (@sec:can-mac-fsm-tx) and inserts an inverse-polarity stuff bit after every five consecutive identical bits. The module is not a state machine but a single clocked process built around two procedures: `manage_bit_counting` tracks consecutive identical polarities in a bounded counter and asserts a stuff-required flag with the inverse polarity when the count reaches the threshold, while `manage_sbc_encoding` detects each new stuff event and increments a 3-bit Gray-coded Stuff Bit Count with parity for the CAN-FD CRC field. A `start` pulse from the FSM resets all internal state at the beginning of each new frame. The dataflow through these two stages is shown in @fig:mac-bs-tx-dataflow. Six PSL properties (P1-P6) embedded in the source provide exhaustive formal verification of the stuffing invariants via SymbiYosys.

```{.mermaid #fig:mac-bs-tx-dataflow caption="can_mac_bs_tx dataflow. The FSM presents each frame bit with a valid pulse. manage_bit_counting tracks consecutive identical polarities and, on reaching the stuff threshold, asserts valid with the inverse polarity. manage_sbc_encoding detects each new stuff event and updates the Gray-coded counter with parity for the CAN-FD CRC field. A start pulse or reset clears all registered state."}
---
config:
  layout: elk
  elk:
    algorithm: layered
    mergeEdges: false
    nodePlacementStrategy: LINEAR_SEGMENTS
  look: classic
  theme: neutral
  themeVariables:
    fontFamily: "Libertinus Serif, Noto Serif, serif"
    fontSize: "14px"
    primaryTextColor: "#000"
---
flowchart TD
  subgraph fsm_in ["can_mac_fsm_bs_tx_if_s2d_t"]
    data_in["data<br/>(polarity_t)"]
    valid_in["valid<br/>(boolean)"]
    start_in["start<br/>(boolean)"]
  end

  regs1["consecutive_count (0..5)<br/>last_polarity (polarity_t)"]
  logic1{"count ≥<br/>stuff_width?"}
  regs2["stuff_count (3-bit unsigned)<br/>stuff_valid_prev (boolean)"]
  logic2["to_gray() +<br/>calc_parity()"]

  regs1 --> logic1
  regs2 --> logic2

  subgraph fsm_out ["can_mac_fsm_bs_tx_if_d2s_t"]
    stuff_valid["valid<br/>(boolean)"]
    stuff_data["data<br/>(polarity_t)"]
    sbc_out["sbc<br/>(3-bit Gray + parity)"]
  end

  data_in --> regs1
  valid_in --> regs1
  logic1 -->|"count < 5:<br/>valid = false"| stuff_valid
  logic1 -->|"count = 5:<br/>valid = true"| stuff_valid
  logic1 -->|"count = 5:<br/>invert last_polarity"| stuff_data
  logic1 -->|"count = 5:<br/>increment stuff_count"| regs2
  logic2 --> sbc_out
  start_in -->|clear| regs1
  start_in -->|clear| regs2
```

#### `can_mac_crc_tx` {#sec:can-mac-crc-tx}

`can_mac_crc_tx` wraps three dedicated CRC engines - CRC-15, CRC-17, and CRC-21 - and selects the appropriate output based on the frame format communicated by the FSM via the `crc_poly_select` field (@tbl:mac-fsm-crc-if). CAN Classic frames use CRC-15, while CAN-FD frames use CRC-17 (data payloads up to 16 bytes) or CRC-21 (data payloads above 16 bytes) [@iso11898_1, sec. 10.4.2.6]. Each engine receives the serial bit stream gated by its selection signal, and the wrapper zero-pads the selected result into a common `crc_vector_t` output. The current implementation uses a placeholder CRC architecture (`can_mac_crc_dummy_tx`) that returns a fixed polynomial constant. This will be replaced with a serial-input polynomial division engine.

```{.mermaid #fig:mac-crc-tx caption="can_mac_crc_tx selection architecture. Three CRC engine instances run in parallel. The FSM drives crc_poly_select to gate valid and start per engine so that only the selected polynomial accumulates data. A registered output mux selects the active engine result and zero-pads it into the common crc_vector_t format."}
---
config:
  layout: elk
  elk:
    algorithm: layered
    mergeEdges: false
    nodePlacementStrategy: LINEAR_SEGMENTS
  look: classic
  theme: neutral
  themeVariables:
    fontFamily: "Libertinus Serif, Noto Serif, serif"
    fontSize: "14px"
    primaryTextColor: "#000"
---
flowchart TD
  subgraph inputs ["Inputs"]
    subgraph clk_rst ["Clock / Reset"]
      clk["clk_i<br/>(std_logic)"]
      rst["rst_i<br/>(std_logic)"]
    end

    subgraph fsm_in ["can_mac_fsm_crc_tx_if_s2d_t"]
      data_crc["data<br/>(std_logic)"]
      valid_crc["valid<br/>(std_logic)"]
      start_crc["start<br/>(std_logic)"]
      sel["crc_poly_select<br/>(2-bit)"]
    end
  end

  join["join"]
  demux[/"demux"\]
  crc15["**u_crc15**<br/>CRC-15<br/>(CAN Classic)"]
  crc17["**u_crc17**<br/>CRC-17<br/>(CAN-FD ≤ 16 Byte)"]
  crc21["**u_crc21**<br/>CRC-21<br/>(CAN-FD > 16 Byte)"]
  mux[\"mux"/]
  pad["zero-pad to crc_vector_t<br/>(registered)"]

  subgraph fsm_out ["can_mac_fsm_crc_tx_if_d2s_t"]
    crc_out["crc<br/>(crc_vector_t)"]
  end

  clk --> crc15
  clk --> crc17
  clk --> crc21
  clk --> pad
  rst --> crc15
  rst --> crc17
  rst --> crc21
  rst --> pad
  valid_crc --> join
  start_crc --> join
  data_crc --> join
  join ==> demux
  sel ==>|select| demux
  demux ==> crc15
  demux ==> crc17
  demux ==> crc21
  crc15 ==> mux
  crc17 ==> mux
  crc21 ==> mux
  sel ==>|select| mux
  mux ==> pad
  pad ==> crc_out
```

### `can_mac_rx` {#sec:can-mac-rx}

`can_mac_rx` deserializes the bit stream received from the PCS, performs bit destuffing and CRC verification, and reconstructs the LLC frame for delivery to `can_llc_rx` [@iso11898_1, sec. 6.6].

## PCS Sub-layer {#sec:pcs-sub-layer}
Handles bit timing and synchronization. It generates the sample point (SP) and secondary sample point (SSP) strobes. It provides bit-level monitoring data to the FCE to detect synchronization and timing errors.

### `can_pcs_tx` {#sec:can-pcs-tx}

`can_pcs_tx` implements bit timing and Transmitter Delay Compensation for the TX path. It generates the sample point (SP) strobe used by the MAC FSM to advance frame state, and - when TDC is configured - a secondary sample point (SSP) strobe for data-phase bit monitoring. The FSM (@fig:can-pcs-tx) has four states reflecting the two bit rates and the TDC measurement window. In the `measuring_delay` state, the module counts the physical TX-to-RX propagation delay (TDCV, [@iso11898_1, sec. 7.3.4]) by timing the dominant edge on the looped-back RX input relative to the TX output edge, then adds the configured TDCO offset to derive the SSP position for subsequent data-phase bits.

```{.mermaid #fig:can-pcs-tx fig-width=0.6 caption="can_pcs_tx FSM. The measuring_delay state is entered on the FDF sample point to measure TDCV (Transmitter Delay Compensation Value, [@iso11898_1, sec. 7.3.4]). The BRS bit boundary determines whether data-phase timing is used. All non-idle states return to idle when the frame becomes inactive."}
---
config:
  layout: elk
  elk:
    algorithm: layered
    mergeEdges: false
    nodePlacementStrategy: LINEAR_SEGMENTS
  look: classic
  theme: neutral
  themeVariables:
    fontFamily: "Libertinus Serif, Noto Serif, serif"
    fontSize: "14px"
    primaryTextColor: "#000"
---
stateDiagram-v2

  state "**idle**<br/>─────────<br/>• Awaiting frame activation<br/>• Nominal timing<br/>• Latch first bit on frame activation" as idle_s
  state "**transmitting_nominal**<br/>─────────<br/>• Nominal bit timing<br/>• Latch next bit at nominal bit boundary<br/>• SP strobe at end of Phase_Seg1" as nom_s
  state "**measuring_delay**<br/>─────────<br/>• Nominal bit timing<br/>• Measure TDCV<br/>• Latch SSP position and FIFO index on RX edge" as meas_s
  state "**transmitting_data**<br/>─────────<br/>• Data-phase bit timing<br/>• Latch next bit at data bit boundary<br/>• SP or SSP strobe per TDC configuration" as data_s

  [*] --> idle_s : reset
  idle_s --> nom_s : frame active

  nom_s --> idle_s : frame inactive
  nom_s --> meas_s : FDF bit at SP

  meas_s --> idle_s : frame inactive
  meas_s --> data_s : BRS bit recessive
  meas_s --> nom_s : BRS bit dominant

  data_s --> idle_s : frame inactive
  data_s --> nom_s : CRC delimiter
  data_s --> nom_s : error flag
```

### `can_pcs_rx` {#sec:can-pcs-rx}

`can_pcs_rx` implements bit timing and synchronization for the RX path. It performs hard and soft synchronization on the incoming bus signal and generates the sample point strobe used by the MAC RX layer to latch each received bit [@iso11898_1, sec. 7.2-7.3].

---

# Implementation {#sec:implementation}

## Type Safety and Packages {#sec:type-safety-packages}
The implementation uses custom record types (defined in `can_types_pkg.vhd`) to ensure clean interfaces between modules.

## Bit Timing and TDC {#sec:bit-timing-tdc}
Detailed description of how `tx_pcs` measures propagation delay and calculates the SSP.

## CRC and Bit Stuffing {#sec:crc-bit-stuffing}
Implementation details of the flexible CRC generator and the hybrid bit stuffer.

# Verification and Results {#sec:verification-results}

*Note: This section is currently being populated as the verification plan is executed.*

## Testbench Results Summary {#sec:testbench-results-summary}
| Testbench | Status | Coverage |
| :--- | :--- | :--- |
| `tx_pcs_tb` | Pass | 95% |
| `tx_can_tb` | Pass | 88% |
| `tx_can_protocol_tb` | Pass | 92% |

: Testbench execution status and functional coverage summary. {#tbl:testbench-results-summary}

---

# Discussion {#sec:discussion}
Comparison of the implemented architecture against theoretical models. Performance analysis in high-load scenarios.

# Conclusion {#sec:conclusion}
Summary of work completed and how objectives were met.

# References {#sec:references}

<!-- Generated automatically by Pandoc from docs/references.bib -->
