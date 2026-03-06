---
title: "Implementation of a CAN/CAN-FD Bus Transmitter in VHDL"
author: "Mads Richardt (s224948)"
date: "February 28, 2026"
bibliography: references.bib
csl: ieee.csl
link-citations: true
---

# Abstract {-}

*This document is a work-in-progress draft for the B.Eng thesis. Currently, the project is in the **Verification Plan** phase (Phase 2), with architectural prototyping for the transmitter sub-system completed.*

This thesis describes the design, implementation, and verification of a CAN (Controller Area Network) and CAN-FD (Flexible Data rate) transmitter sub-system.
 The implementation is targeting high-reliability engine controller applications and is compliant with the ISO 11898-1:2024 standard. Key features include support for both Classic and FD frame formats, Transmitter Delay Compensation (TDC) for high-speed data phases, and a modular architecture separated into Link Layer Control (LLC), Media Access Control (MAC), and Physical Coding Sublayer (PCS).


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
Existing CAN implementations often lack flexibility or do not fully support the latest ISO 11898-1:2024 features, such as advanced Transmitter Delay Compensation (TDC). The challenge lies in creating a transmitter that can seamlessly switch between bit rates while maintaining strict protocol compliance and timing accuracy.

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
Overview of the data link layer and physical signaling requirements.

## VHDL and OSVVM {#sec:vhdl-osvvm}
The role of modern VHDL standards and verification frameworks in digital design.

---

# Verification Planning {#sec:verification-planning}

## Overview and Scope {#sec:overview-scope}

Protocol compliance is the central objective of this project. The CAN and CAN-FD standards (ISO 11898-1:2024) specify hundreds of normative requirements governing frame structure, bit timing, error handling, and fault confinement. To verify the transmitter against these requirements systematically, a structured **Verification Plan** was developed as the first major deliverable of the project - before any RTL implementation began.

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

To make observability judgments repeatable and independent of VHDL implementation choices, the classification is anchored in the **canonical service primitives** defined by ISO 11898-1:2015. The standard specifies inter-layer boundaries as abstract service access points with named primitives and parameters:

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
A complete CAN node is composed of a Transmit (TX) path and a Receive (RX) path coordinated by shared fault-confinement and physical-interface control. The paths operate in parallel at runtime, but they are not symmetric in behavior or responsibility.
The focus of this thesis is the complete node architecture and its standards-traceable interfaces. The TX path is responsible for frame submission, arbitration participation, and bitstream generation toward the bus, while the RX path is responsible for bus observation, frame reconstruction, and delivery/notification toward the user layer. As shown in @fig:can-node-architecture, this full-node decomposition spans LLC, MAC, PCS, FCE, and PMA boundaries.


```{.mermaid #fig:can-node-architecture caption="CAN node decomposition across LLC, MAC, PCS, FCE, and PMA boundaries. Interface definitions are provided for llc_tx_if (@tbl:llc-tx-if), llc_rx_if (@tbl:llc-rx-if), llc_mac_tx_if (@tbl:llc-mac-tx-if), mac_llc_rx_if (@tbl:mac-llc-rx-if), mac_pcs_tx_if (@tbl:mac-pcs-tx-if), pcs_mac_rx_if (@tbl:pcs-mac-rx-if), aui_if (@tbl:aui-if), fce_llc_tx_if and fce_llc_if (@tbl:fce-llc-if), fce_mac_if (@tbl:fce-mac-if), and fce_pcs_if (@tbl:fce-pcs-if)."}
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
    FCE["**can_fce**<br/>─────────<br/>Fault confinement<br/>(FCE, ISO ref.: 8.1.3-8.1.4)"]
    PMA["**PMA**<br/>─────────<br/>Physical medium attachment<br/>(ISO ref.: 7.4)"]
    subgraph Node ["**CAN Node**<br/>─────────<br/>DLL + PCS, ISO ref.: 6.1-6.3"]
        subgraph TX_Pipeline ["**TX Pipeline**"]
            LLC_TX["**can_llc_tx**<br/>─────────<br/>Frame buffering & retransmission<br/>(LLC Sub-layer,ISO ref.: 6.4-6.5)"]
            MAC_TX["**can_mac_tx**<br/>─────────<br/>Serialization, CRC & bit stuffing<br/>(MAC Sub-layer, ISO ref.: 6.6)"]
            PCS_TX["**can_pcs_tx**<br/>─────────<br/>Bit timing & TDC<br/>(PCS Sub-layer, ISO ref.: 7.2-7.4)"]

            LLC_TX <==>|llc_mac_tx_if| MAC_TX <==>|mac_pcs_tx_if| PCS_TX
        end

        subgraph RX_Pipeline ["**RX Pipeline**"]
            PCS_RX["**can_pcs_rx**<br/>─────────<br/>Bit timing & synchronization<br/>(PCS Sub-layer, ISO ref.: 7.2-7.4)"]
            MAC_RX["**can_mac_rx**<br/>─────────<br/>Deserialization, CRC & destuffing<br/>(MAC Sub-layer, ISO ref.: 6.6)"]
            LLC_RX["**can_llc_rx**<br/>─────────<br/>Frame delivery & filtering<br/>(LLC Sub-layer, ISO ref.: 6.4-6.5)"]

            PCS_RX <==>|pcs_mac_rx_if| MAC_RX <==>|mac_llc_rx_if| LLC_RX
        end

        %% Control & Status paths
        FCE <==>|fce_llc_tx_if| LLC_TX
        FCE <==>|fce_mac_if| MAC_TX
        FCE <==>|fce_pcs_if| PCS_TX
        FCE <==>|fce_llc_if| LLC_RX
        FCE <==>|fce_mac_if| MAC_RX
        FCE <==>|fce_pcs_if| PCS_RX
    end

    User <==>|llc_tx_if| LLC_TX
    User <==>|llc_rx_if| LLC_RX
    PCS_TX <==>|aui_if| PMA
    PMA <==>|aui_if| PCS_RX
```

### LLC Frame Format
The current `LLC Frame` format is depicted in @fig:llc-frame-current with the ID byte format depicted in @tbl:ID-bytes. The revised `LLC Frame` supporting FD is depicted in @fig:llc-frame-revised. The revised format adds a 3-bit `FMT` (ISO 6.4.3) field to the DLC byte, expands the data field to 64 bytes, and repurposes reserved bits in the last byte for BRS and ESI flags. The `FMT` encodes the supported frame formats as '`000`' = CB, '`100`' = CE, '`010`' = FB, '`110`' = FE. Accordingly, for the frame content to be self-consistent the IDE bit must be set to `0` for `FMT` = CB/FB and `1` for `FMT` = CE/FE. The revised format is designed to be backward compatible: an implementation that only supports Classic frames can simply ignore the `FMT` bits and treat all frames as Classic, while an implementation that supports FD can use the `FMT` field to distinguish frame types without affecting the existing ID and data field structure.

```{.mermaid #fig:llc-frame-current caption="Current 15 byte LLC Frame format."}
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


```{.mermaid #fig:llc-frame-revised caption="Maximum length revised LLC Frame format with FD support."}
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

: Four ID byts of the current `LLC frame` format. {#tbl:ID-bytes}

## Interface Definition Tables {#sec:interface-definition-tables}

The following tables define the interface bundles shown in @fig:can-node-architecture. ISO references are to ISO 11898-1:2024 clauses and tables.

Detailed interface definitions (normative source mapping):

::: {.landscape-tables}


| ISO symbol | ISO payload | Direction | Semantics | Timing | ISO ref. | Implementation mapping |
| --- | --- | --- | --- | --- | --- | --- |
| `L_Data.Request` (start) | `LLC Frame`, `Handle` | `User -> LLC` | Request data transfer of `LLC frame` | Issued when `User` wants to start `LLC frame` transfer | 6.4.5.5.2 | `valid && ready && sop && payload on data`|
| `L_Data.Request` (stream) | `LLC Frame`, `Handle` | `User -> LLC` | Stream `LLC frame` | Intermediate beats while `LLC frame` is streamed |  6.4.5.5.2 | `valid && ready && !sop && !eop && payload on data` |
| `L_Data.Request` (end) | `LLC Frame`, `Handle` | `User -> LLC` | End of current `LLC frame` transfer | Final beat of `LLC frame` transfer | 6.4.5.5.2  | `valid && ready && eop && payload on data`|
| `L_Data.AbortRequest` | `Handle` | `User -> LLC` | Abort pending `LLC frame` transfer | Issued when `User` wants to cancel `LLC frame` transfer | 6.4.5.5.3 | TBD |

: Interface definition for `llc_tx_if`. Uses the existing Avalon-ST interface (`pk_eth_st`) to implement `L_Data.Request`. Includes `L_Data.AbortRequest` for complete ISO-defined service coverage. `L_Data.AbortRequest` is not implemented in the current CAN bus controller. `TBD` = To Be Defined. {#tbl:llc-tx-if}


| ISO symbol | ISO payload | Direction | Semantics | Timing | ISO ref. | Implementation mapping |
| --- | --- | --- | --- | --- | --- | --- |
| `L_Data.Indication` (start) | `LLC Frame`, optional `Timestamp` | `LLC -> User` | Start received `LLC frame` transfer | Issued when `LLC` wants to start `LLC frame` transfer | 6.4.5.5.5 | `valid && ready && sop && payload on data`|
| `L_Data.Indication` (stream) | `LLC Frame`, optional `Timestamp` | `LLC -> User` | Stream received `LLC frame` | Intermediate beats while `LLC frame` is streamed | 6.4.5.5.5 | `valid && ready && !sop && !eop && payload on data` |
| `L_Data.Indication` (end) | `LLC Frame`, optional `Timestamp` | `LLC -> User` | End received `LLC frame` transfer | Final beat of `LLC frame` transfer | 6.4.5.5.5 | `valid && ready && eop && payload on data` |
| `L_Data.Confirm` | `Transfer_Status`, optional `Timestamp`, `Handle` | `LLC -> User` | Report result of prior `L_Data.Request` | Issued on completion/failure of prior `L_Data.Request` | 6.4.5.5.4 | TBD |

: Interface definition for `llc_rx_if`. Uses the existing Avalon-ST interface (`pk_eth_st`) to implement `L_Data.Indication`. Includes `L_Data.Confirm` and optional `Timestamp` for complete ISO service coverage. `L_Data.AbortRequest` is not implemented in the current CAN bus controller. `Transfer_Status: [Ongoing, Lost Arbitration, Transmitted, Aborted, Disturbed]`. `TBD` = To Be Defined. {#tbl:llc-rx-if}


| ISO symbol | ISO payload | Direction | Semantics | Timing | ISO ref. | Implementation mapping |
| --- | --- | --- | --- | --- | --- | --- |
| `DLL SDU` | `LLC Frame` | `LLC -> MAC` | Transfer `LLC Frame` content | Issued when LLC starts MAC handoff | 6.3, 6.6.4.2 | `TBD` |
| Interface control information | `Control context` | `LLC -> MAC` | Transfer control context for frame handling | Valid with `DLL SDU` handoff | 6.6.4.2 | `TBD` |

: Interface definition for `llc_mac_tx_if`. `TBD` = To Be Defined. {#tbl:llc-mac-tx-if}


| ISO symbol | ISO payload | Direction | Semantics | Timing | ISO ref. | Implementation mapping |
| --- | --- | --- | --- | --- | --- | --- |
| `DLL SDU` | Reconstructed `LLC Frame` | `MAC -> LLC` | Transfer reconstructed `LLC Frame` | Issued when MAC has reconstructed `LLC Frame` from received `MAC Frame` | 6.6.4.3, 6.6.9 | `TBD` |
| Time reference notification | `SOF/frame-valid indication` | `MAC -> LLC` | Provide timing reference for timestamping | Generated for transmitted/received DF/RF | 6.6.3 | `TBD` |

: Interface definition for `mac_llc_rx_if`. `TBD` = To Be Defined. {#tbl:mac-llc-rx-if}


| ISO symbol | ISO payload | Direction | Semantics | Timing | ISO ref. | Implementation mapping |
| --- | --- | --- | --- | --- | --- | --- |
| `PCS_Data.Request` | `Output_Unit` | `MAC -> PCS` | Request transmission of one `dominant/recessive` bit | Bit-by-bit during `MAC Frame` serialization | 7.2.1, 7.2.2 | `TBD` |
| `PCS_Status.Transmitter` | `D_Transmit` | `MAC -> PCS` | Indicate FD data-phase interval | Active during transmission in the FD data-phase | 7.2.1, 7.2.5 | `TBD` |

: Interface definition for `mac_pcs_tx_if`. `TBD` = To Be Defined. {#tbl:mac-pcs-tx-if}


| ISO symbol | ISO payload | Direction | Semantics | Timing | ISO ref. | Implementation mapping |
| --- | --- | --- | --- | --- | --- | --- |
| `PCS_Data.Indicate` | `Input_Unit` | `PCS -> MAC` | Indicate arrival of one `dominant/recessive` bit | Bit-by-bit during reception stream | 7.2.1, 7.2.3 | `TBD` |
| `PCS_Status.Receiver` | `D_Receive` | `MAC -> PCS` | Indicate FD data-phase interval | Active during reception in the FD data-phase | 7.2.1, 7.2.6 | `TBD` |

: Interface definition for `pcs_mac_rx_if`. `TBD` = To Be Defined. {#tbl:pcs-mac-rx-if}


| ISO symbol | ISO payload | Direction | Semantics | Timing | ISO ref. | Implementation mapping |
| --- | --- | --- | --- | --- | --- | --- |
| `output symbol` | `Dominant/recessive symbol` | `PCS -> PMA` | Drive physical output symbol | Issued on `Output_Unit` updates | 7.4.2.1 | `TBD` |
| `bus_off symbol` | `Bus-off control` | `PCS -> PMA` | Switch node off bus | Issued on `Bus_off_request` request from `FCE` | 7.4.2.2, 8.1.3.4 | `TBD` |
| `bus_off_release symbol` | `Bus-off release control` | `PCS -> PMA` | Release node from bus-off | Issued on `Bus_off_release` request from `FCE` | 7.4.2.3, 8.1.3.4 | `TBD` |
| `input symbol` | `Dominant/recessive symbol` | `PMA -> PCS` | Indicate physical input symbol | Continuous PMA-to-PCS indication | 7.4.3 | `TBD` |

: Interface definition for `aui_if`. `TBD` = To Be Defined. {#tbl:aui-if}


| ISO symbol | ISO payload | Direction | Semantics | Timing | ISO ref. | Implementation mapping |
| --- | --- | --- | --- | --- | --- | --- |
| `Normal_mode_request` | `Mode request` | `LLC -> FCE` | Request reset to normal mode | Issued on startup/restart | 8.1.3.2 | `TBD` |
| `Normal_mode_response` | `Mode response` | `FCE -> LLC` | Acknowledge normal-mode request | Returned after FCE processing | 8.1.3.2 | `TBD` |
| `Bus_off` | `Bus-off status` | `FCE -> LLC` | Indicate node is bus-off | Asserted on bus-off transition | 8.1.3.2 | `TBD` |

: Interface definition for `fce_llc_if`. `TBD` = To Be Defined. {#tbl:fce-llc-if}


| ISO symbol | ISO payload | Direction | Semantics | Timing | ISO ref. | Implementation mapping |
| --- | --- | --- | --- | --- | --- | --- |
| `Transmit/receive` | `Transfer mode context` | `MAC -> FCE` | Report current TX/RX context | Updated with MAC transfer context | 8.1.3.3 | `TBD` |
| `Error` | `Error event` | `MAC -> FCE` | Report detected protocol error | On bit/stuff/CRC/form/ACK error | 8.1.3.3 | `TBD` |
| `Primary_error` | `Primary error event` | `MAC -> FCE` | Report primary error condition | On primary error condition | 8.1.3.3 | `TBD` |
| `Error/overload flag` | `EF/OF state` | `MAC -> FCE` | Report EF/OF transmission state | During EF/OF transmission | 8.1.3.3 | `TBD` |
| `Counters_unchanged` | `Counter-update qualifier` | `MAC -> FCE` | Qualify counter exception path | On rule-c exception cases | 8.1.3.3 | `TBD` |
| `Error_delimiter_too_late` | `Late delimiter event` | `MAC -> FCE` | Report late error-delimiter condition | Set on late delimiter condition | 8.1.3.3 | `TBD` |
| `Successful_transfer` | `Transfer completion event` | `MAC -> FCE` | Report successful TX/RX completion | On successful frame transfer | 8.1.3.3 | `TBD` |
| `Error_passive_response` | `State response` | `MAC -> FCE` | Report entry into error-passive state | On state transition completion | 8.1.3.3 | `TBD` |
| `Error_active_response` | `State response` | `MAC -> FCE` | Report return to error-active state | On state transition completion | 8.1.3.3 | `TBD` |
| `Error_passive_request` | `State request` | `FCE -> MAC` | Request MAC enter error-passive state | On TEC/REC threshold crossing | 8.1.3.3 | `TBD` |
| `Error_active_request` | `State request` | `FCE -> MAC` | Request MAC return to error-active state | On TEC/REC recovery conditions | 8.1.3.3 | `TBD` |

: Interface definition for `fce_mac_if`. `TBD` = To Be Defined. {#tbl:fce-mac-if}


| ISO symbol | ISO payload | Direction | Semantics | Timing | ISO ref. | Implementation mapping |
| --- | --- | --- | --- | --- | --- | --- |
| `Bus_off_request` | `Bus-off request` | `FCE -> PCS` | Request node switch-off from bus | On bus-off transition condition | 8.1.3.4 | `TBD` |
| `Bus_off_release_request` | `Bus-off release request` | `FCE -> PCS` | Request node re-enable from bus-off | On restart/reintegration | 8.1.3.4 | `TBD` |
| `Bus_off_response` | `Bus-off response` | `PCS -> FCE` | Acknowledge bus-off request | Returned after bus-off action | 8.1.3.4 | `TBD` |
| `Bus_off_release_response` | `Bus-off release response` | `PCS -> FCE` | Acknowledge bus-off-release request | Returned after release action | 8.1.3.4 | `TBD` |

: Interface definition for `fce_pcs_if`. `TBD` = To Be Defined. {#tbl:fce-pcs-if}
:::

## Protocol-Driven Type System


```{.mermaid #fig:types-diagram caption="Type and constant hierarchy. Protocol constants derived from ISO 11898-1 form the root of the hierarchy, from which frame layout constants, type constraints, and composite record types are derived. The mac_frame_bit_name_t enumeration carries semantic protocol context across the MAC-PCS boundary and provides human-readable signal names in simulation waveforms."}
---
config:
  layout: elk
  elk:
    algorithm: layered
    mergeEdges: false
    nodePlacementStrategy: SIMPLE
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
    namespace `Protocol Primitives` {
        class polarity_t["type polarity_t"]
        class can_format_t["type can_format_t"]
        class mac_frame_bit_name_t["type mac_frame_bit_name_t"]
        class position_t["subtype position_t"]
    }

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

    position_t : integer range 0 to max_mac_frame_length_c

    polarity_t : dominant
    polarity_t : recessive

    can_format_t : cc_basic
    can_format_t : cc_extended
    can_format_t : fd_basic
    can_format_t : fd_extended

    mac_frame_bit_name_t : sof_bit
    mac_frame_bit_name_t : fdf_bit
    mac_frame_bit_name_t : brs_bit
    mac_frame_bit_name_t : ⋮

    class bit_t["record bit_t"]
    bit_t : position position_t
    bit_t : polarity polarity_t

    class mac_frame_bit_t["record mac_frame_bit_t"]
    mac_frame_bit_t : polarity polarity_t
    mac_frame_bit_t : bit_name mac_frame_bit_name_t

    class frame_params_t["record frame_params_t"]
    frame_params_t : is_fd_frame boolean
    frame_params_t : has_brs boolean
    frame_params_t : crc_start position_t
    frame_params_t : brs_bit bit_t
    frame_params_t : ⋮

    note for protocol_constants "Fundamental protocol constants derived directly from ISO 11898-1.<br/>All frame layout constants, field widths, and type constraints<br/>in the design are derived from these values.<br/>Serves as the single source of truth for protocol specification."
    note for frame_layout_constants "cb_, ce_, fb_, fe_ format constants.<br/>Used by serialiser to calculate frame_params_t at frame ingestion.<br/>See Table X for complete listing."
    note for common_frame_bits "Fixed polarity protocol bits shared across all frame formats.<br/>Returned directly by get_current_bit for known protocol bit positions.<br/>See Table X for complete listing."
    note for frame_params_t "Calculated once per frame by the serialiser from frame layout constants.<br/>Boolean fields are pre-computed predicates for get_current_bit if-guards,<br/>avoiding repeated condition evaluation on every bit clock cycle.<br/>Encapsulates all format-specific parameters allowing get_current_bit<br/>to resolve the correct mac_frame_bit_t for any bit counter value."

    position_t ..> protocol_constants : range from
    frame_layout_constants ..> protocol_constants : derives from
    common_frame_bits ..> protocol_constants : derives from
    bit_t *-- position_t : position
    bit_t *-- polarity_t : polarity
    mac_frame_bit_t *-- polarity_t : polarity
    mac_frame_bit_t *-- mac_frame_bit_name_t : bit_name
    frame_layout_constants ..> bit_t : uses
    common_frame_bits ..> mac_frame_bit_t : uses
    frame_params_t *-- can_format_t : format
    frame_params_t *-- position_t : field ranges
    frame_params_t *-- bit_t : format specific bits
    frame_params_t ..> frame_layout_constants : derived from
```

## LLC Sub-layer {#sec:llc-sub-layer}
Responsible for frame buffering and retransmission management. It provides an Avalon-ST interface to the user application and communicates with the FCE to handle retransmission limits and error status reporting.

### `can_llc_tx` {#sec:can-llc-tx}

### `can_llc_rx` {#sec:can-llc-rx}

## MAC Sub-layer {#sec:mac-sub-layer}
The core of the protocol logic. It handles bit serialization, CRC calculation, and bit stuffing. It coordinates the overall frame state machine and interacts closely with the Fault Confinement Entity (FCE) to manage error counters (TEC/REC) and node state (Error Active/Passive/Bus Off) based on protocol violations.

### `can_mac_tx` {#sec:can-mac-tx}

The MAC TX layer (@fig:mac-tx-architecture) is composed of four main components:

1. **tx_mac_ser** (Serializer): Converts LLC bytes into a serial bit stream with polarity information
2. **tx_mac_fsm** (Frame State Machine): Coordinates frame transmission, controls all submodules
3. **bit_stuffer_fd** (Bit Stuffer): Implements CAN/CAN-FD bit stuffing rules
4. **crc_fd** (CRC Engine): Generates CRC-15/CRC-17/CRC-21 based on frame type

```{.mermaid #fig:mac-tx-architecture caption="MAC TX layer architecture showing internal component interconnections and external interfaces (LLC, PCS, FCE)."}
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
    LLC["**can_llc_tx**<br/>─────────<br/>LLC Sub-layer, ISO ref.: 6.4-6.5"]
    PCS["**can_pcs_tx**<br/>─────────<br/>PCS Sub-layer, ISO ref.: 7.2-7.4"]
    FCE["**can_fce**<br/>─────────<br/>FCE, ISO ref.: 8.1.3-8.1.4"]

    subgraph MAC_TX ["**can_mac_tx**<br/>─────────<br/>MAC Sub-layer, ISO ref.: 6.6"]
        SER["**can_mac_ser_tx**<br/>─────────<br/>LLC frame Serializer"]
        FSM["**can_mac_fsm_tx**<br/>─────────<br/>Controlling FSM"]
        BS["**can_mac_bs_tx**<br/>─────────<br/>Bit Stuffer"]
        CRC["**can_mac_crc_tx**<br/>─────────<br/>CRC generator"]

        SER <==>|can_mac_fsm_ser_tx_if| FSM
        FSM <==>|can_mac_fsm_bs_tx_if| BS
        FSM <==>|can_mac_fsm_crc_tx_if| CRC
    end

    LLC <==>|llc_mac_tx_if| SER

    FSM <==>|mac_pcs_tx_if| PCS
    FSM <==>|fce_mac_if| FCE
```


```{.mermaid #fig:mac-tx-fsm caption="MAC TX FSM state transitions. Error-active and error-passive paths share the same flag+delimiter sequence but drive different polarities. Overload transitions (dominant in intermission bits 0-1, or dominant on last delimiter bit) are omitted for clarity."}
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

The `transmitting_frame` state is the most complex. On entry, `initialize_frame_transmission()` resets the Serializer (`can_mac_ser_tx`), the Bit Stuffer (`can_mac_bs_tx`, MAC Sub-layer, ISO ref.: 8.5), and the CRC engine (`can_mac_crc_tx`, MAC Sub-layer, ISO ref.: 8.5.4). Each sample-point strobe from the PCS Sub-layer (ISO ref.: 7.2-7.4) then drives the following sequence:

1. `get_observed_mac_frame_bit_info()` reads the bus polarity at the sample point and compares it against the transmitted bit, returning an event record with mismatch and stuff-bit flags.
2. If an SSP error was latched from the previous bit period (CAN-FD data phase TDC, PCS Sub-layer, ISO ref.: 7.3.4), that error is processed before the current event.
3. Based on the event, either `transmit_stuff_bit()` or `transmit_normal_bit()` drives the next bit and updates the CRC and stuff-bit counter.
4. A detected error or polarity mismatch triggers a transition to `transmitting_active_error_flag` or `transmitting_passive_error_flag` depending on the fault confinement state reported by the FCE (Fault Confinement Entity, ISO ref.: 8.1.3-8.1.4).

### `can_mac_rx` {#sec:can-mac-rx}

## PCS Sub-layer {#sec:pcs-sub-layer}
Handles bit timing and synchronization. It generates the sample point (SP) and secondary sample point (SSP) strobes. It provides bit-level monitoring data to the FCE to detect synchronization and timing errors.

### `can_pcs_tx` {#sec:can-pcs-tx}
### `can_pcs_rx` {#sec:can-pcs-rx}

---

# Implementation {#sec:implementation}

## Type Safety and Packages {#sec:type-safety-packages}
The implementation uses custom record types (defined in `can_types_pkg.vhd`) to ensure clean interfaces between modules.

## Bit Timing and TDC {#sec:bit-timing-tdc}
Detailed description of how `tx_pcs` measures propagation delay and calculates the SSP.

## CRC and Bit Stuffing {#sec:crc-bit-stuffing}
Implementation details of the flexible CRC generator and the hybrid bit stuffer.

---

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

---

# Conclusion {#sec:conclusion}
Summary of work completed and how objectives were met.

---

# References {#sec:references}

<!-- Generated automatically by Pandoc from docs/references.bib -->
