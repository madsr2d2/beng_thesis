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
A complete CAN node decomposes into a TX path and an RX path, coordinated by a shared Fault Confinement Entity (FCE) and Physical Medium Attachment (PMA) control, as shown in @fig:can-node-architecture. Each path spans three sub-layers - LLC (@sec:llc-sub-layer), MAC (@sec:mac-sub-layer), and PCS (@sec:pcs-sub-layer) - with the LLC frame format defined in @sec:llc-frame-format and interface bundles defined in @sec:interface-definition-tables. A centralized types package (@sec:protocol-driven-type-system) defines all protocol constants and interface records. Within the MAC sub-layer, a unified `can_mac` wrapper (@sec:can-mac-wrapper) instantiates `can_mac_tx`, `can_mac_rx`, and `can_fce`, merging their error signals internally so that the wrapper exposes only LLC and PCS interfaces for each path plus the FCE's LLC and PCS interfaces.

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

All module interfaces use `std_logic` and `std_logic_vector` exclusively, as mandated for synthesis compatibility. Protocol semantics such as polarity, frame format, and transfer status are encoded as named `std_logic`/`std_logic_vector` constants defined in `pk_can_types` (@sec:protocol-driven-type-system). The LLC-User interface (`llc_tx_if`, `llc_rx_if`) is implemented as an Avalon-ST byte stream to maintain backward compatibility with the existing CAN bus controller, which uses the same `valid`/`ready`/`startofpacket` handshake convention.

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
| 6.4.5.5.4 | `L_Data.Confirm` | `Transfer_Status`, `Timestamp`, `Handle` | Report outcome of prior `L_Data.Request` | `LLC -> User` | `llc_rx_if.transfer_status` (`std_logic_vector(2:0)`) | Issued on frame completion, loss, or error |

: Interface definition for `llc_rx_if`. Implements `L_Data.Indication` as an Avalon-ST byte stream. `Timestamp` is included for complete ISO service coverage but is not yet implemented. {#tbl:llc-rx-if}


| ISO ref. | ISO symbol | ISO payload | ISO semantics | Direction | Implementation mapping | Implementation notes |
| --- | --- | --- | --- | --- | --- | --- |
| 6.3, 6.6.4.2 | `DLL SDU` | `LLC Frame` | Transfer LLC frame to MAC for serialization | `LLC -> MAC` | `llc_mac_tx_if.data` (`byte_t`), `llc_mac_tx_if.valid` (`std_logic`), `llc_mac_tx_if.sop` (`std_logic`) | `valid` high with byte on data; `sop` marks first byte of new frame |
| 6.3, 6.6.4.2 | `DLL SDU` | | Flow control | `MAC -> LLC` | `llc_mac_tx_if.ready` (`std_logic`) | Asserted by MAC serializer when able to consume next byte |
| 6.6.4.2 | Interface control information | `Transfer_Status` | Report frame transmission outcome | `MAC -> LLC` | `llc_mac_tx_if.transfer_status` (`std_logic_vector(2:0)`) | Updated by MAC on completion, loss, or error |

: Interface definition for `llc_mac_tx_if`. Frame length is self-describing from the DLC config bytes; the MAC serializer does not consume `eop`. {#tbl:llc-mac-tx-if}


| ISO ref. | ISO symbol | ISO payload | ISO semantics | Direction | Implementation mapping | Implementation notes |
| --- | --- | --- | --- | --- | --- | --- |
| 6.6.4.3, 6.6.9 | `DLL SDU` | Reconstructed `LLC Frame` | Transfer reconstructed LLC frame to LLC | `MAC -> LLC` | `llc_mac_rx_if.data` (`byte_t`), `llc_mac_rx_if.valid` (`std_logic`), `llc_mac_rx_if.sop` (`std_logic`), `llc_mac_rx_if.eop` (`std_logic`) | Avalon-ST byte stream; the RX FSM streams the stored `llc_frame` array during the quiet phase |
| 6.6.4.3, 6.6.9 | `DLL SDU` | | Flow control | `LLC -> MAC` | `llc_mac_rx_if.ready` (`std_logic`) | Asserted by LLC when able to consume next byte |

: Interface definition for `llc_mac_rx_if`. Carries the reconstructed LLC frame from `can_mac_rx` to `can_llc_rx` (@sec:can-mac-rx) as an Avalon-ST byte stream. The RX FSM stores received bits in an internal frame array during reception and streams the completed frame after EOF. {#tbl:llc-mac-rx-if}


| ISO ref. | ISO symbol | ISO payload | ISO semantics | Direction | Implementation mapping | Implementation notes |
| --- | --- | --- | --- | --- | --- | --- |
| 7.2.1, 7.2.2 | `PCS_Data.Request` | `Output_Unit` | Present next bit for transmission | `MAC -> PCS` | `mac_pcs_if.polarity` (`std_logic`), `mac_pcs_if.valid` (`std_logic`) | MAC holds polarity stable; PCS samples at each bit boundary autonomously |
| 7.2.1, 7.2.5 | `PCS_Status.Transmitter` | `D_Transmit` | Indicate FD data-phase interval to PCS | `MAC -> PCS` | `mac_pcs_if.use_data_rate` (`std_logic`), `mac_pcs_if.start_tdc` (`std_logic`) | `use_data_rate` asserted during FD data phase; `start_tdc` pulsed at BRS to begin delay measurement |
| 7.2.1, 7.2.3 | `PCS_Data.Indicate` | `Input_Unit` | Indicate bus polarity at sample point | `PCS -> MAC` | `mac_pcs_if.bus_polarity` (`std_logic`), `mac_pcs_if.sp` (`std_logic`), `mac_pcs_if.ssp` (`std_logic`), `mac_pcs_if.fifo_index` (`t_fifo_index_vec`) | `sp` pulses once per nominal sample point; `ssp` pulses once per secondary sample point for TDC |
| 7.2.1, 7.2.6 | `PCS_Status.Receiver` | `D_Receive` | Indicate FD data-phase interval to PCS | `MAC -> PCS` | not yet implemented | Asserted during FD data-phase reception |

: Interface definition for `mac_pcs_if`. The `D_Transmit` status is signalled via a dedicated `use_data_rate` flag rather than encoding it in a semantic bit name. The PCS switches between nominal and data-phase bit timing based on this flag, keeping the interface to plain `std_logic` signals. {#tbl:mac-pcs-if}


| ISO ref. | ISO symbol | ISO payload | ISO semantics | Direction | Implementation mapping | Implementation notes |
| --- | --- | --- | --- | --- | --- | --- |
| 7.4.2.1 | `output symbol` | `Dominant/recessive symbol` | Drive physical output symbol | `PCS -> PMA` | `aui_if.tx` (`std_logic`) | Updated on each `Output_Unit` request |
| 7.4.2.2, 8.1.3.4 | `bus_off symbol` | `Bus-off control` | Switch node off bus | `PCS -> PMA` | `aui_if.bus_off` (`std_logic`) | On `Bus_off_request` from FCE |
| 7.4.2.3, 8.1.3.4 | `bus_off_release symbol` | `Bus-off release control` | Release node from bus-off | `PCS -> PMA` | `aui_if.bus_off_release` (`std_logic`) | On `Bus_off_release_request` from FCE |
| 7.4.3 | `input symbol` | `Dominant/recessive symbol` | Indicate physical input symbol | `PMA -> PCS` | `aui_if.rx` (`std_logic`) | Continuously driven by PMA |

: Interface definition for `aui_if`. All signals are `std_logic`, as this interface crosses from the ISO protocol domain into the physical medium. {#tbl:aui-if}


| ISO ref. | ISO symbol | ISO payload | ISO semantics | Direction | Implementation mapping | Implementation notes |
| --- | --- | --- | --- | --- | --- | --- |
| 8.1.3.2 | `Normal_mode_request` | `Mode request` | Request reset to normal mode | `LLC -> FCE` | `fce_llc_if.normal_mode_request` (`std_logic`) | Issued on startup/restart |
| 8.1.3.2 | `Normal_mode_response` | `Mode response` | Acknowledge normal-mode request | `FCE -> LLC` | `fce_llc_if.normal_mode_response` (`std_logic`) | Returned after FCE processing |
| 8.1.3.2 | `Bus_off` | `Bus-off status` | Indicate node is bus-off | `FCE -> LLC` | `fce_llc_if.bus_off` (`std_logic`) | Asserted on bus-off transition |

: Interface definition for `fce_llc_if`. Carries bus-off status and mode-request handshake between the FCE and LLC layers [@iso11898_1, sec. 8.1.3.2]. {#tbl:fce-llc-if}


| ISO ref. | ISO symbol | ISO payload | ISO semantics | Direction | Implementation mapping | Implementation notes |
| --- | --- | --- | --- | --- | --- | --- |
| 8.1.3.3 | `Transmit/receive` | `Transfer mode context` | Report current TX/RX context | `MAC -> FCE` | `fce_mac_if.transmitting` (`std_logic`) | Updated with MAC transfer context |
| 8.1.3.3 | `Error` | `Error event` | Report detected protocol error | `MAC -> FCE` | `fce_mac_if.error` (`std_logic`) | Pulse on bit/stuff/CRC/form/ACK error |
| 8.1.3.3 | `Primary_error` | `Primary error event` | Report primary error condition | `MAC -> FCE` | `fce_mac_if.primary_error` (`std_logic`) | Pulse on primary error condition |
| 8.1.3.3 | `Error/overload flag` | `EF/OF state` | Report EF/OF transmission state | `MAC -> FCE` | `fce_mac_if.sending_error_overload_flag` (`std_logic`) | Asserted during EF/OF transmission |
| 8.1.3.3 | `Counters_unchanged` | `Counter-update qualifier` | Qualify counter exception path | `MAC -> FCE` | `fce_mac_if.counters_unchanged` (`std_logic`) | Asserted on rule-c exception cases |
| 8.1.3.3 | `Error_delimiter_too_late` | `Late delimiter event` | Report late error-delimiter condition | `MAC -> FCE` | `fce_mac_if.error_delimiter_too_late` (`std_logic`) | Asserted on late delimiter condition |
| 8.1.3.3 | `Successful_transfer` | `Transfer completion event` | Report successful TX/RX completion | `MAC -> FCE` | `fce_mac_if.successful_transfer` (`std_logic`) | Pulse on successful frame transfer |
| 8.1.3.3 | `Error_passive_response` | `State response` | Report entry into error-passive state | `MAC -> FCE` | `fce_mac_if.error_passive_response` (`std_logic`) | On state transition completion |
| 8.1.3.3 | `Error_active_response` | `State response` | Report return to error-active state | `MAC -> FCE` | `fce_mac_if.error_active_response` (`std_logic`) | On state transition completion |
| 8.1.3.3 | `Error_passive_request` | `State request` | Request MAC enter error-passive state | `FCE -> MAC` | `fce_mac_if.error_passive_request` (`std_logic`) | On TEC/REC threshold crossing |
| 8.1.3.3 | `Error_active_request` | `State request` | Request MAC return to error-active state | `FCE -> MAC` | `fce_mac_if.error_active_request` (`std_logic`) | On TEC/REC recovery |

: Interface definition for `fce_mac_if`. The MAC reports error events and frame outcomes to the FCE; the FCE returns the current error-active/passive state to the MAC [@iso11898_1, sec. 8.1.3.3]. {#tbl:fce-mac-if}


| ISO ref. | ISO symbol | ISO payload | ISO semantics | Direction | Implementation mapping | Implementation notes |
| --- | --- | --- | --- | --- | --- | --- |
| 8.1.3.4 | `Bus_off_request` | `Bus-off request` | Request node switch-off from bus | `FCE -> PCS` | `fce_pcs_if.bus_off_request` (`std_logic`) | On bus-off transition condition |
| 8.1.3.4 | `Bus_off_release_request` | `Bus-off release request` | Request node re-enable from bus-off | `FCE -> PCS` | `fce_pcs_if.bus_off_release_request` (`std_logic`) | On restart/reintegration |
| 8.1.3.4 | `Bus_off_response` | `Bus-off response` | Acknowledge bus-off request | `PCS -> FCE` | `fce_pcs_if.bus_off_response` (`std_logic`) | Returned after bus-off action |
| 8.1.3.4 | `Bus_off_release_response` | `Bus-off release response` | Acknowledge bus-off-release request | `PCS -> FCE` | `fce_pcs_if.bus_off_release_response` (`std_logic`) | Returned after release action |

: Interface definition for `fce_pcs_if`. Carries bus-off and bus-off-release request/response handshakes between the FCE and PCS layers [@iso11898_1, sec. 8.1.3.4]. {#tbl:fce-pcs-if}
:::

## Protocol-Driven Type System {#sec:protocol-driven-type-system}

Two VHDL packages centralize the shared definitions used across the design. All module interfaces use `std_logic` and `std_logic_vector` exclusively - protocol concepts such as polarity, frame format, and transfer status are encoded as named constants. Enumeration types such as FSM state types are declared locally within each module's architecture, keeping the packages free of module-specific types.

**`pk_can_types`** (`can_types_p.vhd`) is the primary design package, organized into the following sections:

1. **Protocol constants** - bus polarity (`c_dominant` = '`0`', `c_recessive` = '`1`'), frame field widths (base ID 11 bits, extended ID 18 bits, DLC 4 bits, EOF 7 bits), bit stuffing parameters (`c_stuff_width` = 5), CRC polynomial vectors and selector constants (CRC-15, CRC-17, CRC-21), transfer status encodings (`c_ongoing`, `c_transmitted`, `c_aborted`, `c_lost_arb`, `c_disturbed`), error signalling widths, inter-frame spacing widths, and FCE counter thresholds.
2. **Bit timing subtypes** - constrained natural ranges matching ISO Table 12 [@iso11898_1, sec. 7.3.2]: prescaler (1-32), propagation segments, phase segments, and SSP offset (1-63).
3. **Composite types** - the sole composite type is `t_llc_metadata`, a record capturing the six LLC config byte fields (IDE, FDF, DLC, FTYP, BRS, ESI) extracted by the serializer and held stable for the duration of a frame.
4. **Interface records** - typed bundles for each inter-module boundary (serializer-FSM, LLC-MAC TX/RX, MAC-PCS, FSM-bit stuffer, FSM-CRC, MAC-FCE, LLC-FCE, FCE-PCS), each paired with a reset constant. These are defined in full in @sec:interface-definition-tables.
5. **LLC frame format** - array types and config byte bit-position constants for both the internal LLC frame format (variable length, streamed to the serializer) and the legacy 71-byte user-facing format.
6. **Utility functions** - `dlc_to_data_length` (ISO Table 5 DLC-to-byte-count conversion), `f_to_gray` (binary-to-Gray encoding for the SBC field), and `f_calc_parity` (XOR parity for SBC).

**`can_tb_p`** (`can_tb_p.vhd`) is the testbench utility package, extracted from `pk_can_types` to separate simulation-only code from synthesizable definitions. It provides CRC reference calculation, metadata extraction, and bus stream reference model functions used by the testbenches for expected-value computation.

## LLC Sub-layer {#sec:llc-sub-layer}
Responsible for frame buffering and retransmission management. It provides an Avalon-ST interface to the user application and communicates with the FCE to handle retransmission limits and error status reporting.

### `can_llc_tx` {#sec:can-llc-tx}

`can_llc_tx` buffers an incoming LLC frame from the user, streams it byte-by-byte to the MAC serializer, and manages retransmission on bus disturbance up to the ISO-mandated limit [@iso11898_1, sec. 6.4.5 and 6.5].

### `can_llc_rx` {#sec:can-llc-rx}

`can_llc_rx` receives a reconstructed LLC frame from the MAC layer, applies acceptance filtering, and delivers accepted frames to the user over the `llc_rx_if` Avalon-ST stream [@iso11898_1, sec. 6.4.5].

## MAC Sub-layer {#sec:mac-sub-layer}
The MAC sub-layer is the core of the protocol logic, responsible for bit serialization, CRC generation, bit stuffing, and frame-level error detection. It coordinates closely with the FCE (@sec:fce-sub-layer) for error counter management and node-state transitions (Error Active/Passive/Bus Off), and with the PCS (@sec:pcs-sub-layer) for sample-point-driven bit output.

The earlier CAN bus controller concentrated TX, RX, MAC, and FCE logic in a single monolithic FSM (`can_fsm`), with the sub-functions - serialization (`can_ast_to_serial`), bit stuffing (`can_stuff_bit_gen`), and CRC (`gen_crc`) - implemented in satellite modules driven directly by it. PCS timing logic was implemented in `can_node_clock`, which fed sample-point and transmit pulses into `can_fsm` - a strategy retained in the current design.

The current design restructures these modules around the ISO 11898-1 [@iso11898_1] layer boundaries. On the TX side the mapping is direct: `can_ast_to_serial` becomes `can_mac_ser_tx` (@sec:can-mac-ser-tx), `can_stuff_bit_gen` becomes `can_mac_bs` (@sec:can-mac-bs), `gen_crc` becomes `can_mac_crc` (@sec:can-mac-crc), and `can_node_clock` becomes `can_pcs_tx` (@sec:can-pcs-tx). The bit stuffer and CRC engine are shared between the TX and RX paths - each path instantiates its own copy of the same `can_mac_bs` and `can_mac_crc` entities, reusing the bit stuffer for destuffing and the CRC engine for CRC checking on the RX side. The RX FSM (`can_mac_fsm_rx`) stores received bits directly in an internal frame array and streams the completed frame to the LLC during the quiet phase, eliminating the need for a separate deserializer module. Fault confinement, previously embedded in `can_fsm`, is separated into its own entity (`can_fce`) and wired through the unified `can_mac` wrapper (@sec:can-mac-wrapper).

### `can_mac_tx` {#sec:can-mac-tx}

The `can_mac_tx` (@fig:mac-tx-architecture) is composed of four main components:

1. **can_mac_ser_tx**: Converts LLC bytes into a serial bit stream, extracts LLC metadata from config bytes
2. **can_mac_fsm_tx**: Coordinates frame transmission with per-field state granularity, controls all submodules
3. **can_mac_bs**: Shared bit stuffer implementing both dynamic and fixed bit stuffing modes
4. **can_mac_crc**: CRC engine with three parallel generators (CRC-15, CRC-17, CRC-21) and dual data feeds for CC/FD

```{.mermaid #fig:mac-tx-architecture fig-width=0.5 caption="can_mac_tx architecture showing internal component interconnections and external interfaces. Internal interface definitions are provided for can_mac_ser_fsm_if (@tbl:mac-fsm-ser-if), can_mac_fsm_bs_if (@tbl:mac-fsm-bs-if), and can_mac_fsm_crc_if (@tbl:mac-fsm-crc-if). The bit stuffer and CRC engine are the same entities reused in can_mac_rx."}
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
        BS["**can_mac_bs**<br/>─────────<br/>Bit Stuffer"]
        CRC["**can_mac_crc**<br/>─────────<br/>CRC Engine"]

        SER <==>|can_mac_ser_fsm_if| FSM
        FSM <==>|can_mac_fsm_bs_if| BS
        FSM <==>|can_mac_fsm_crc_if| CRC
    end

    LLC <==>|llc_mac_tx_if| SER

    FSM <==>|mac_pcs_if| PCS
    FSM <==>|fce_mac_if| FCE
```

#### `can_mac_tx` Internal Interfaces {#sec:mac-internal-interfaces}

The interfaces between MAC sub-components are implementation-defined and carry no direct ISO service primitive mapping. @tbl:mac-fsm-ser-if, @tbl:mac-fsm-bs-if, and @tbl:mac-fsm-crc-if define each bidirectional bundle; the Direction column identifies the driving component for each field. The bit stuffer and CRC engine interfaces are shared between the TX and RX paths - each path instantiates its own copy wired through identical record types.


| field | type | direction | description |
| --- | --- | --- | --- |
| `data` | `std_logic` | `ser -> fsm` | current bit polarity; FSM reads this when `valid` is asserted |
| `valid` | `std_logic` | `ser -> fsm` | asserted while a bit is available for the FSM to consume |
| `llc_metadata` | `t_llc_metadata` | `ser -> fsm` | LLC config byte fields (IDE, FDF, DLC, FTYP, BRS, ESI) extracted by the serializer; valid for the lifetime of the frame |
| `ready` | `std_logic` | `fsm -> ser` | pulsed when the FSM has consumed the current bit; advances the serializer to the next bit |
| `transfer_status` | `std_logic_vector(2:0)` | `fsm -> ser` | frame outcome; any non-`c_ongoing` value terminates serialization |

: Interface definition for `can_mac_ser_fsm_if`, connecting `can_mac_ser_tx` and `can_mac_fsm_tx` (see @fig:mac-tx-architecture). {#tbl:mac-fsm-ser-if}


| field | type | direction | description |
| --- | --- | --- | --- |
| `data` | `std_logic` | `fsm -> bs` | bit polarity fed into the bit stuffer |
| `valid` | `std_logic` | `fsm -> bs` | pulsed when a new bit is presented to the stuffer |
| `fixed_bit_stuffing_en` | `std_logic` | `fsm -> bs` | when high, the bit stuffer operates in fixed bit stuffing mode (FD CRC region) |
| `data` | `std_logic` | `bs -> fsm` | polarity of the required stuff bit |
| `valid` | `std_logic` | `bs -> fsm` | asserted when a stuff bit insertion is required |
| `stuff_bit_count` | `std_logic_vector(3:0)` | `bs -> fsm` | gray-coded stuff bit count with parity for the FD SBC field |

: Interface definition for `can_mac_fsm_bs_if`, connecting `can_mac_fsm_tx`/`can_mac_fsm_rx` and `can_mac_bs` (see @fig:mac-tx-architecture). The bit stuffer is reset by a dedicated `bs_rst` signal from the FSM rather than a field in this record. {#tbl:mac-fsm-bs-if}


| field | type | direction | description |
| --- | --- | --- | --- |
| `crc_poly_select` | `std_logic_vector(1:0)` | `fsm -> crc` | selects the active CRC polynomial: CRC-15, CRC-17, or CRC-21 |
| `valid_cc` | `std_logic` | `fsm -> crc` | pulsed when `data_cc` should be accumulated into the CRC-15 engine |
| `valid_fd` | `std_logic` | `fsm -> crc` | pulsed when `data_fd` should be accumulated into the CRC-17/CRC-21 engines |
| `data_cc` | `std_logic` | `fsm -> crc` | bit value fed to the CRC-15 engine (CC frames: data bits only, no stuff bits) |
| `data_fd` | `std_logic` | `fsm -> crc` | bit value fed to the CRC-17/CRC-21 engines (FD frames: dynamic stuff bits + data bits) |
| `crc` | `std_logic_vector(20:0)` | `crc -> fsm` | current CRC register value, left-aligned and zero-padded to 21 bits |

: Interface definition for `can_mac_fsm_crc_if`, connecting `can_mac_fsm_tx`/`can_mac_fsm_rx` and `can_mac_crc` (see @fig:mac-tx-architecture). Separate data feeds for CC and FD are required because CC and FD frames compute CRC over different bit streams: CC excludes stuff bits while FD includes them [@iso11898_1, sec. 10.4.2.6]. This dual-feed design also allows the RX path to run both CRC engines in parallel until the frame type is known. The CRC engine is reset by a dedicated `crc_rst` signal from the FSM. {#tbl:mac-fsm-crc-if}

#### `can_mac_fsm_tx` {#sec:can-mac-fsm-tx}

`can_mac_fsm_tx` (@fig:mac-tx-fsm) orchestrates frame transmission, coordinating the serializer (@sec:can-mac-ser-tx), bit stuffer (@sec:can-mac-bs), and CRC engine (@sec:can-mac-crc). The FSM uses per-field state granularity: rather than a single `s_transmitting_frame` state with function-dispatched field logic, each protocol field (SOF, ID, DLC, data, CRC, ACK, EOF, etc.) has its own dedicated FSM state. This design makes the field boundaries explicit in the state encoding and eliminates the need for frame parameter precomputation functions. The FSM derives `data_len` and `crc_length` from `t_llc_metadata` on frame entry and tracks `bit_count` within each field state.

On each sample-point strobe from `can_pcs_tx` (@sec:can-pcs-tx), each frame-field state executes the following sequence:

1. **Monitor the bus.** The sampled bus polarity is compared against the previously transmitted bit to detect errors, ACK, and arbitration loss. In the CAN-FD data phase, the FSM maintains a 32-bit polarity history shift register for Transmitter Delay Compensation (TDC). Any pending secondary sample point (SSP) observation from the previous bit period is evaluated against this history before the current bit is checked [@iso11898_1, sec. 7.3.4]. A detected error triggers a transition to `s_error_overload` with the appropriate flag type based on the FCE fault confinement status [@iso11898_1, sec. 8.1.3-8.1.4]. Arbitration loss during the ID or control fields causes the FSM to stop driving and return to `s_intermission`.

2. **Determine the next bit.** If the bit stuffer has a pending stuff bit (`bs_i.valid`), that takes priority. Otherwise, the polarity is determined by the current state: form bits (SOF, IDE, FDF, reserved, delimiters, EOF) have fixed polarities, while ID, DLC, data, SBC, and CRC bits are sourced from the serializer, metadata, bit stuffer count, or CRC register respectively.

3. **Feed the CRC engine and bit stuffer.** The output polarity is forwarded to the CRC engine (for bits within the CRC-protected region) via separate `data_cc` and `data_fd` feeds, and to the bit stuffer (for bits within the stuffing region). The FSM asserts `fixed_bit_stuffing_en` when entering the SBC/CRC field region of FD frames to switch the bit stuffer from dynamic to fixed mode.

4. **Present the bit at the PCS interface.** The resolved polarity is driven onto the `t_can_mac_pcs_if_m2s` interface. The `use_data_rate` signal is asserted during the CAN-FD data phase to switch the PCS to faster bit timing, and `start_tdc` is pulsed at the FDF bit to initiate transmitter delay compensation [@iso11898_1, sec. 7.3.4].

```{.mermaid #fig:mac-tx-fsm caption="can_mac_fsm_tx FSM with per-field state granularity. Frame-field states (s_sof through s_eof) each handle one protocol field, with bit_count tracking position within the field. After a successful frame or arbitration loss the FSM passes through s_intermission before returning to s_bus_idle. Detected errors branch to s_error_overload, which drives either an active (dominant) or passive (recessive) error flag depending on FCE status. The dashed box groups the frame-field states for clarity."}
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

  classDef reset stroke:#000,stroke-width:3px

  state "**s_bus_reintegration**<br/>─────────<br/>• Bus not driving<br/>• Await 11 recessive bits, or<br/>  128 x 11 recessive bits if bus-off" as s_bus_reintegration
  class s_bus_reintegration reset
  state "**s_bus_idle**<br/>─────────<br/>• Bus not driving<br/>• Await frame request" as s_bus_idle
  state "**s_intermission**<br/>─────────<br/>• Bus not driving<br/>• 3-bit inter-frame spacing<br/>• Monitoring for overload" as s_intermission
  state "**s_suspend_transmission**<br/>─────────<br/>• Bus not driving<br/>• Error-passive 8-bit hold-off" as s_suspend_transmission
  state "**s_error_overload**<br/>─────────<br/>• Active: 6 dominant + 8 recessive<br/>• Passive: 6 recessive + 8 recessive<br/>• Overload: 6 dominant + 8 recessive<br/>• Signals error to FCE" as s_error_overload

  state frame_fields {
    state "**s_sof**" as s_sof
    state "**s_id**" as s_id
    state "**s_rtr_srr_rrs**" as s_rtr
    state "**s_ide**" as s_ide
    state "**s_fdf_r1_r0**" as s_fdf
    state "**s_res_r0**" as s_res
    state "**s_brs**" as s_brs
    state "**s_esi**" as s_esi
    state "**s_dlc**" as s_dlc
    state "**s_data**" as s_data
    state "**s_sbc**" as s_sbc
    state "**s_crc**" as s_crc
    state "**s_ack**" as s_ack
    state "**s_eof**" as s_eof

    s_sof --> s_id
    s_id --> s_rtr
    s_id --> s_ide : extended
    s_rtr --> s_ide
    s_ide --> s_fdf
    s_fdf --> s_res : FD
    s_fdf --> s_dlc : CC
    s_res --> s_brs
    s_brs --> s_esi
    s_esi --> s_dlc
    s_dlc --> s_data
    s_data --> s_sbc : FD
    s_data --> s_crc : CC
    s_sbc --> s_crc
    s_crc --> s_ack
    s_ack --> s_eof
  }

s_bus_reintegration --> s_bus_idle : 11 recessive bits

s_bus_idle --> s_sof : frame pending

s_eof --> s_intermission : frame complete
frame_fields --> s_intermission : lost arbitration
frame_fields --> s_error_overload : error detected

s_error_overload --> s_intermission : sequence complete
s_error_overload --> s_error_overload : overload detected

s_intermission --> s_bus_idle : intermission complete
s_intermission --> s_suspend_transmission : error-passive transmitter
s_intermission --> s_error_overload : overload detected

s_suspend_transmission --> s_bus_idle : suspend complete
s_suspend_transmission --> s_error_overload : overload detected
```

#### `can_mac_ser_tx` {#sec:can-mac-ser-tx}

`can_mac_ser_tx` converts the LLC byte stream into a serial polarity bit stream for the MAC FSM. Its four-state FSM (@fig:mac-ser-fsm-tx) manages the two-byte configuration handshake, byte fetching, and bit-by-bit serialization. The serializer extracts LLC metadata (IDE, FDF, DLC, FTYP, BRS, ESI) from the two config bytes and registers it in `t_llc_metadata`, which remains stable for the entire frame. The serializer also handles ID field padding - skipping unused bits in the 32-bit ID field for 11-bit base identifiers - and forwards `transfer_status` from the FSM back to the LLC to terminate serialization on error or completion.

```{.mermaid #fig:mac-ser-fsm-tx fig-width=0.6 caption="can_mac_ser_tx FSM. The serializer accepts LLC frame bytes over a ready/valid handshake and shifts them out MSB-first to the MAC FSM one bit per ready pulse. LLC metadata is extracted from the two config bytes and registered in t_llc_metadata for use by the FSM throughout the frame."}
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

  classDef reset stroke:#000,stroke-width:3px

  state "**load_config_byte_0**<br/>─────────<br/>• Idle, awaiting new frame" as s0
  class s0 reset
  state "**load_config_byte_1**<br/>─────────<br/>• Awaiting config byte 1" as s1
  state "**load_llc_frame_byte**<br/>─────────<br/>• Fetching next byte from LLC stream" as s2
  state "**shift_out_bits**<br/>─────────<br/>• Shift out MSB on MAC FSM ready pulse" as s3

  s0 --> s1 : config byte 0 received from LLC

  s1 --> s2 : config byte 1 received from LLC, llc_metadata extracted

  s2 --> s3 : data byte received from LLC

  s3 --> s0 : transmission complete
  s3 --> s2 : byte serialized
```

#### `can_mac_bs` {#sec:can-mac-bs}

`can_mac_bs` implements both dynamic and fixed bit stuffing for CAN Classic and CAN-FD frames [@iso11898_1, sec. 10.6]. The same entity is instantiated in both `can_mac_tx` and `can_mac_rx` - on the TX side it inserts stuff bits, while on the RX side the FSM uses its output to detect and remove stuff bits from the received stream.

In **dynamic mode** (`fixed_bit_stuffing_en` = '0'), the stuffer monitors the polarity stream and inserts an inverse-polarity stuff bit after every five consecutive identical bits (ISO 6.6.13.2). In **fixed mode** (`fixed_bit_stuffing_en` = '1'), used for the FD CRC region, one fixed stuff bit (FSB) is inserted on the rising edge of `fixed_bit_stuffing_en`, then one every four real bits (ISO 6.6.13.3.1). Any dynamic stuff bit pending at the mode boundary is suppressed. The stuffer maintains a Gray-coded stuff bit count with parity for the SBC field via `f_to_gray()` and `f_calc_parity()`. The data path diagram is shown in @fig:mac-bs-dataflow.

```{.mermaid #fig:mac-bs-dataflow fig-width=0.8 caption="can_mac_bs data path diagram. When valid and data = last_polarity, consecutive_count increments. Otherwise it restarts at 1 with last_polarity updated to data. When consecutive_count reaches stuff_width (5 in dynamic mode, 4 in fixed mode), valid and inverted data are driven and stuff_count increments. The to_gray() + calc_parity() block encodes stuff_count into the stuff_bit_count output. The external rst signal resets consecutive_count and stuff_count to zero. The fixed_bit_stuffing_en signal selects between dynamic and fixed modes. All outputs are registered."}
---
config:
  layout: elk
  look: classic
  theme: neutral
  themeVariables:
    fontFamily: "Libertinus Serif, Noto Serif, serif"
    fontSize: "14px"
    primaryTextColor: "#000"
---
stateDiagram-v2
  classDef reset stroke:#000,stroke-width:3px

  state "consecutive_count <= 0<br/>stuff_count <= 0" as reset
  class reset reset

  state "Wait for valid_i" as wait

  state "count ≠ stuff_width<br/>and data_i = last_polarity?" as compare
  state "consecutive_count += 1" as inc
  state "consecutive_count <= 1<br/>last_polarity <= data_i" as restart

  state "consecutive_count ≥ stuff_width?" as thresh

  state "valid_o <= true<br/>data_o <= ¬last_polarity<br/>stuff_count += 1<br/>sbc_o <= encode(stuff_count)" as stuff


  reset --> wait
  wait --> compare : valid

  compare --> inc : yes
  compare --> restart : no
  restart --> wait

  inc --> thresh

  thresh --> stuff : yes
  thresh --> wait : no

  stuff --> wait
```

#### `can_mac_crc` {#sec:can-mac-crc}

`can_mac_crc` provides CRC generation and checking for both CAN Classic and CAN-FD frames. CAN Classic frames use CRC-15, while CAN-FD frames use CRC-17 (data payloads up to 16 bytes) or CRC-21 (data payloads above 16 bytes) [@iso11898_1, sec. 10.4.2.6]. The same entity is instantiated in both `can_mac_tx` (for generation) and `can_mac_rx` (for checking). The FSM selects the appropriate polynomial via the `crc_poly_select` field (@tbl:mac-fsm-crc-if). The data path diagram is shown in @fig:mac-crc.

Three parallel `gen_crc` instances run continuously on separate data feeds: `data_cc` drives CRC-15 via `valid_cc`, while `data_fd` drives both CRC-17 and CRC-21 via `valid_fd`. This dual-feed architecture is necessary because CC and FD frames compute CRC over different bit streams (CC excludes stuff bits; FD includes them), and the RX path does not know which CRC engine to use until after the frame type has been determined. The output multiplexer selects the active engine's result based on `crc_poly_select` and left-aligns it to the common 21-bit output width.

```{.mermaid #fig:mac-crc fig-width=0.8 caption="can_mac_crc data path diagram. Three parallel gen_crc instances accumulate continuously: data_cc drives CRC-15 via valid_cc, while data_fd drives both CRC-17 and CRC-21 via valid_fd. The output register selects the active engine result based on crc_poly_select and left-aligns it to 21 bits. The external rst signal reinitializes all three engines and the output register."}
---
config:
  layout: elk
  look: classic
  theme: neutral
  themeVariables:
    fontFamily: "Libertinus Serif, Noto Serif, serif"
    fontSize: "14px"
    primaryTextColor: "#000"
---
stateDiagram-v2
  classDef reset stroke:#000,stroke-width:3px

  state "crc15 <= init_15<br/>crc17 <= init_17<br/>crc21 <= init_21<br/>crc_o <= (others => '0')" as reset
  class reset reset

  state "Wait for valid_cc or valid_fd" as wait

  state "valid_cc?" as check_cc
  state "u_crc15: accumulate data_cc<br/>(CRC-15, CAN Classic)" as acc_cc

  state "valid_fd?" as check_fd
  state "u_crc17: accumulate data_fd<br/>(CRC-17, FD ≤ 16B)<br/>u_crc21: accumulate data_fd<br/>(CRC-21, FD > 16B)" as acc_fd

  state "crc_poly_select?" as sel

  state "crc_o <= crc15 & 000000" as out15
  state "crc_o <= crc17 & 0000" as out17
  state "crc_o <= crc21" as out21

  reset --> wait

  wait --> check_cc : valid_cc
  wait --> check_fd : valid_fd

  check_cc --> acc_cc : yes
  acc_cc --> sel

  check_fd --> acc_fd : yes
  acc_fd --> sel

  sel --> out15 : "00" (CRC-15)
  sel --> out17 : "01" (CRC-17)
  sel --> out21 : "10" (CRC-21)

  out15 --> wait
  out17 --> wait
  out21 --> wait
```

### `can_mac_rx` {#sec:can-mac-rx}

`can_mac_rx` receives the bit stream from the PCS, performs bit destuffing and CRC verification, and reconstructs the LLC frame for delivery to `can_llc_rx` [@iso11898_1, sec. 6.6]. Unlike the TX path, the RX path has no separate deserializer module. The RX FSM (`can_mac_fsm_rx`) stores received bits directly into an internal `llc_frame` array during reception and streams the completed frame byte-by-byte to the LLC during the quiet phase (after EOF and intermission) using a dedicated Avalon-ST streaming process.

The `can_mac_rx` wrapper instantiates three components:

1. **can_mac_fsm_rx**: Frame reception FSM with 17 per-field states mirroring the TX FSM structure
2. **can_mac_bs**: Shared bit stuffer entity, reused for destuffing
3. **can_mac_crc**: Shared CRC engine entity, reused for CRC checking

The RX FSM (@fig:mac-rx-fsm) validates SBC and CRC fields during reception, detects form errors (reserved bits, CRC mismatch, delimiter errors), and drives ACK dominant during the ACK slot (1 bit for CC, 2 bits for FD). It reports errors to the FCE through the same `t_can_mac_fce_if_m2s` interface used by the TX FSM.

```{.mermaid #fig:mac-rx-fsm caption="can_mac_fsm_rx FSM with per-field state granularity. The RX FSM mirrors the TX FSM structure (@fig:mac-tx-fsm) but replaces transmission logic with reception, storage, and validation. On detecting a dominant SOF in s_idle, the FSM enters s_id and stores received bits into an internal llc_frame array. After EOF, the FSM transitions through s_intermission and a dedicated streaming process transfers the stored frame to the LLC. Form errors (reserved bit violations, CRC mismatch, delimiter errors) and SBC mismatches trigger s_error_overload. The dashed box groups the frame-field states for clarity."}
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

  classDef reset stroke:#000,stroke-width:3px

  state "**s_bus_reintegration**<br/>─────────<br/>• Not driving bus<br/>• Await 11 recessive bits" as s_bus_reintegration
  class s_bus_reintegration reset
  state "**s_idle**<br/>─────────<br/>• Not driving bus<br/>• Await dominant SOF" as s_idle
  state "**s_intermission**<br/>─────────<br/>• 3-bit inter-frame spacing<br/>• Stream llc_frame to LLC<br/>• Signal successful_transfer to FCE" as s_intermission
  state "**s_error_overload**<br/>─────────<br/>• Active: 6 dominant + 8 recessive<br/>• Passive: 6 recessive + 8 recessive<br/>• Overload: 6 dominant + 8 recessive<br/>• Signal error to FCE" as s_error_overload

  state frame_fields {
    state "**s_id**" as s_id
    state "**s_rtr_srr_rrs**" as s_rtr
    state "**s_ide**" as s_ide
    state "**s_fdf_r1_r0**" as s_fdf
    state "**s_res_r0**" as s_res
    state "**s_brs**" as s_brs
    state "**s_esi**" as s_esi
    state "**s_dlc**" as s_dlc
    state "**s_data**" as s_data
    state "**s_sbc**" as s_sbc
    state "**s_crc**" as s_crc
    state "**s_ack**" as s_ack
    state "**s_eof**" as s_eof

    s_id --> s_rtr
    s_id --> s_ide : base ID complete
    s_rtr --> s_ide
    s_rtr --> s_fdf : extended
    s_ide --> s_id : extended (IDE=1)
    s_ide --> s_fdf : base (IDE=0)
    s_fdf --> s_res : FD or CC extended
    s_fdf --> s_dlc : CC base
    s_res --> s_brs : FD
    s_res --> s_dlc : CC extended
    s_brs --> s_esi
    s_esi --> s_dlc
    s_dlc --> s_data
    s_data --> s_sbc : FD
    s_data --> s_crc : CC
    s_sbc --> s_crc
    s_crc --> s_ack : CRC delimiter OK
    s_ack --> s_eof
  }

s_bus_reintegration --> s_idle : 11 recessive bits

s_idle --> s_id : dominant SOF detected

s_eof --> s_intermission : frame complete
frame_fields --> s_error_overload : form/CRC/SBC error

s_error_overload --> s_intermission : sequence complete
s_error_overload --> s_error_overload : overload detected

s_intermission --> s_idle : intermission complete
s_intermission --> s_error_overload : overload detected
```

### `can_mac` Unified Wrapper {#sec:can-mac-wrapper}

`can_mac` is a structural wrapper that instantiates `can_mac_tx`, `can_mac_rx`, and `can_fce` (@sec:fce-sub-layer), wiring the FCE internally so that the wrapper exposes only LLC and PCS interfaces for each path plus the FCE's LLC and PCS interfaces. TX and RX have separate PCS interfaces (half-duplex; only one path drives the bus at a time). The TX and RX FCE output records (`t_can_mac_fce_if_m2s`) are merged by OR-ing all fields before feeding the FCE input - the half-duplex guarantee ensures no simultaneous assertions from both paths. The FCE's response (`t_can_mac_fce_if_s2m`, carrying `error_passive_request` and `error_active_request`) is fanned back to both TX and RX paths.

## FCE Sub-layer {#sec:fce-sub-layer}

The Fault Confinement Entity (`can_fce`) implements the error state machine and counter management specified in [@iso11898_1, sec. 8.1.3-8.1.4]. It maintains two error counters - TEC (Transmitter Error Counter, 0-511) and REC (Receiver Error Counter, 0-255) - and transitions between three states: `s_error_active` (normal operation), `s_error_passive` (TEC or REC > 127), and `s_bus_off` (TEC > 255).

Counter updates follow the ISO 8.1.4.2 rules: TEC increments by 8 on TX errors (unless `counters_unchanged` is asserted), decrements by 1 on successful TX. REC increments by 1 on RX errors during non-error-flag phases, by 8 on primary errors or error-flag-phase errors, and decrements by 1 or clamps to 127 on successful RX. The FCE state machine (@fig:fce-fsm) transitions between error-active, error-passive, and bus-off based on counter thresholds. Bus-off recovery requires counting 128 idle conditions (11 consecutive recessive bits each) from the PCS via the `idle_condition` signal, or a `normal_mode_request` from the LLC.

```{.mermaid #fig:fce-fsm fig-width=0.6 caption="can_fce FSM (ISO 8.1.4.1, Figure 43). The s_error_active state is the normal operating mode. When either TEC or REC exceeds 127, the FCE transitions to s_error_passive and asserts error_passive_request to both MAC paths. If TEC exceeds 255, the node enters s_bus_off: the FCE issues bus_off_request to the PCS and bus_off to the LLC. Recovery from bus-off requires 128 idle conditions (each 11 consecutive recessive bits) counted from the PCS, or a normal_mode_request from the LLC, after which the counters are reset and the FCE returns to s_error_active."}
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

  classDef reset stroke:#000,stroke-width:3px

  state "**s_error_active**<br/>─────────<br/>• Normal operation<br/>• error_active_request = 1<br/>• TEC/REC updated per ISO 8.1.4.2" as s_error_active
  class s_error_active reset
  state "**s_error_passive**<br/>─────────<br/>• error_passive_request = 1<br/>• TEC/REC updated per ISO 8.1.4.2" as s_error_passive
  state "**s_bus_off**<br/>─────────<br/>• bus_off = 1, bus_off_request = 1<br/>• Count idle_condition pulses<br/>• Await 128 idle conditions or<br/>  normal_mode_request" as s_bus_off

s_error_active --> s_error_passive : TEC > 127 or REC > 127
s_error_active --> s_bus_off : TEC > 255

s_error_passive --> s_error_active : TEC ≤ 127 and REC ≤ 127
s_error_passive --> s_bus_off : TEC > 255

s_bus_off --> s_error_active : 128 idle conditions or normal_mode_request<br/>(TEC/REC reset to 0)
```

## PCS Sub-layer {#sec:pcs-sub-layer}
Handles bit timing and synchronization. It generates the sample point (SP) and secondary sample point (SSP) strobes. It provides bit-level monitoring data to the FCE to detect synchronization and timing errors.

### `can_pcs_tx` {#sec:can-pcs-tx}

`can_pcs_tx` handles bit timing and Transmitter Delay Compensation (TDC) for the TX path [@iso11898_1, sec. 7.2-7.3]. It generates the sample point (SP) strobe used by the MAC FSM to advance frame state, and - when TDC is configured - a secondary sample point (SSP) strobe for data-phase bit monitoring. The FSM (@fig:can-pcs-tx) has four states reflecting the two bit rates and the TDC measurement window. The `measuring_delay` state determines the Transmitter Delay Compensation Value (TDCV, [@iso11898_1, sec. 7.3.4]) by observing the TX-to-RX propagation delay, which together with the configured TDCO offset defines the SSP position for subsequent data-phase bits.

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

  classDef reset stroke:#000,stroke-width:3px

  state "**idle**<br/>─────────<br/>• Awaiting frame activation<br/>• Nominal timing<br/>• Latch first bit on frame activation" as idle_s
  class idle_s reset
  state "**transmitting_nominal**<br/>─────────<br/>• Nominal bit timing<br/>• Latch next bit at nominal bit boundary<br/>• SP strobe at end of Phase_Seg1" as nom_s
  state "**measuring_delay**<br/>─────────<br/>• Nominal bit timing<br/>• Measure TDCV<br/>• Latch SSP position and FIFO index on RX edge" as meas_s
  state "**transmitting_data**<br/>─────────<br/>• Data-phase bit timing<br/>• Latch next bit at data bit boundary<br/>• SP or SSP strobe per TDC configuration" as data_s

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
