---
title: "Implementation of a CAN/CAN-FD Bus Transmitter in VHDL"
author: "Mads Richardt (s224948)"
date: "February 28, 2026"
bibliography: references.bib
csl: ieee.csl
link-citations: true
---

# B.Eng Thesis: Implementation of a CAN/CAN-FD Bus Transmitter in VHDL

**Author**: Mads Richardt (s224948)
**Date**: February 28, 2026
**Advisors**: Edward Alexandru Todirica (DTU), Fredrik Kristensen (Everllence)

---

## Abstract

*This document is a work-in-progress draft for the B.Eng thesis. Currently, the project is in the **Verification Plan** phase (Phase 2), with architectural prototyping for the transmitter sub-system completed.*

This thesis describes the design, implementation, and verification of a CAN (Controller Area Network) and CAN-FD (Flexible Data rate) transmitter sub-system.
 The implementation is targeting high-reliability engine controller applications and is compliant with the ISO 11898-1:2024 standard. Key features include support for both Classic and FD frame formats, Transmitter Delay Compensation (TDC) for high-speed data phases, and a modular architecture separated into Link Layer Control (LLC), Media Access Control (MAC), and Physical Coding Sublayer (PCS).

---

## Table of Contents

<!-- mtoc-start -->

- [1. Introduction](#1-introduction)
  - [1.1 Motivation](#11-motivation)
  - [1.2 Problem Statement](#12-problem-statement)
  - [1.3 Objectives](#13-objectives)
- [2. Background](#2-background)
  - [2.1 CAN Protocol Evolution](#21-can-protocol-evolution)
  - [2.2 ISO 11898-1:2024 Standard](#22-iso-11898-12024-standard)
  - [2.3 VHDL and OSVVM](#23-vhdl-and-osvvm)
- [3. Verification Planning](#3-verification-planning)
  - [3.1 Overview and Scope](#31-overview-and-scope)
  - [3.2 Requirement Taxonomy](#32-requirement-taxonomy)
  - [3.3 Verification Plan Construction](#33-verification-plan-construction)
    - [3.3.1 AI-Assisted Extraction](#331-ai-assisted-extraction)
    - [3.3.2 Human-in-the-Loop Validation](#332-human-in-the-loop-validation)
  - [3.4 Storage Format and Tooling](#34-storage-format-and-tooling)
  - [3.5 Verification Strategy](#35-verification-strategy)
- [4. Design and Architecture](#4-design-and-architecture)
  - [4.1 System Overview](#41-system-overview)
  - [4.2 LLC Sub-layer (`tx_llc`)](#42-llc-sub-layer-tx_llc)
  - [4.3 MAC Sub-layer (`tx_mac`)](#43-mac-sub-layer-tx_mac)
  - [4.4 PCS Sub-layer (`tx_pcs`)](#44-pcs-sub-layer-tx_pcs)
- [5. Implementation](#5-implementation)
  - [5.1 Type Safety and Packages](#51-type-safety-and-packages)
  - [5.2 Bit Timing and TDC](#52-bit-timing-and-tdc)
  - [5.3 CRC and Bit Stuffing](#53-crc-and-bit-stuffing)
- [6. Verification and Results](#6-verification-and-results)
  - [6.1 Testbench Results Summary](#61-testbench-results-summary)
- [7. Discussion](#7-discussion)
- [8. Conclusion](#8-conclusion)
- [9. References](#9-references)

<!-- mtoc-end -->

---

## 1. Introduction

### 1.1 Motivation
The Controller Area Network (CAN) has been the workhorse of automotive and industrial communication for decades. However, the increasing bandwidth requirements of modern systems led to the development of CAN-FD (Flexible Data rate), which allows for larger payloads and higher bit rates. This project aims to provide a robust, hardware-independent VHDL implementation of a CAN-FD transmitter.

### 1.2 Problem Statement
Existing CAN implementations often lack flexibility or do not fully support the latest ISO 11898-1:2024 features, such as advanced Transmitter Delay Compensation (TDC). The challenge lies in creating a transmitter that can seamlessly switch between bit rates while maintaining strict protocol compliance and timing accuracy.

### 1.3 Objectives
- Implement a VHDL-2008 compliant CAN/CAN-FD transmitter.
- Support both Base (11-bit) and Extended (29-bit) identifiers.
- Implement TDC measurement and compensation logic.
- Ensure high verification coverage using OSVVM and GHDL.

---

## 2. Background

### 2.1 CAN Protocol Evolution
Brief history from CAN 2.0 to CAN-FD.

### 2.2 ISO 11898-1:2024 Standard
Overview of the data link layer and physical signaling requirements.

### 2.3 VHDL and OSVVM
The role of modern VHDL standards and verification frameworks in digital design.

---

## 3. Verification Planning

### 3.1 Overview and Scope

Protocol compliance is the central objective of this project. The CAN and CAN-FD standards (ISO 11898-1:2024) specify hundreds of normative requirements governing frame structure, bit timing, error handling, and fault confinement. To verify the transmitter against these requirements systematically, a structured **Verification Plan** was developed as the first major deliverable of the project — before any RTL implementation began.

The plan covers the four in-scope frame formats: Classic Basic (CB), Classic Extended (CE), FD Basic (FB), and FD Extended (FE). CAN XL frames are excluded. In total, the plan contains 168 requirements extracted from the standard, organized by architectural layer (LLC, MAC, PCS, FCE) and spanning the major functional areas:

- **Frame structure**: Field ordering, bit-level encoding, and format-specific control bits.
- **CRC generation**: CRC-15 (Classic), CRC-17, and CRC-21 (FD) polynomials.
- **Bit stuffing**: Dynamic stuffing during arbitration/data and fixed stuffing in the FD CRC region.
- **Error handling**: Bit error, ACK error, Form error, and Stuff error detection.
- **Fault confinement**: TEC/REC counter management and Error Active/Passive/Bus Off state transitions.

### 3.2 Requirement Taxonomy

A key design decision was the development of a two-axis taxonomy to classify each requirement by its **shape** and **scope**. This taxonomy determines both *how* a requirement is verified and *what environment* is needed.

**Shape** classifies the verification primitive. These categories draw on established concepts from formal verification theory:

- **Triggered**: A precondition/event/postcondition triplet that translates directly into a directed test procedure — establish the precondition, apply the event, assert the postcondition. This structure follows the Hoare triple formalism {P} S {Q} [@hoare1969].
- **Invariant**: A property that must hold at all times (e.g., "the SOF bit shall always be dominant"), mapping to concurrent assertions or monitors.
- **Liveness**: A property asserting that something eventually happens (e.g., "after detecting an error, the node shall eventually transmit an error flag"), requiring temporal reasoning [@alpern1985].
- **Reachability**: A property asserting that a state or condition *can* be reached (e.g., "the node shall be capable of entering Bus Off"), mapping to coverage points.

**Scope** defines the required verification environment:

- **Frame**: Verified by inspecting a single transmitted bit-stream in isolation.
- **Node**: Requires visibility into internal state such as error counters or FSM transitions.
- **Bus**: Requires a multi-node simulation with arbitration and acknowledge behavior.

Together, these two axes allow each requirement to be mapped to the appropriate testbench level and verification technique without ambiguity.

### 3.3 Verification Plan Construction

With the taxonomy defined, the next step was to extract and classify the normative requirements from the ISO standard text. This was a two-stage process combining AI-assisted extraction with manual engineering review.

#### 3.3.1 AI-Assisted Extraction

The initial extraction of normative "shall" and "should" statements was performed using a **Large Language Model (LLM)**. The ISO standard was provided as a searchable markdown document, and the LLM was prompted to identify normative clauses, extract their wording verbatim, assign a shape and scope classification, and format the result as TOML entries. This task is well-suited for LLMs because it involves processing large volumes of technical text, identifying structural patterns (normative vs. informative language), and reformatting unstructured prose into a consistent structured format. The use of AI significantly accelerated the initial drafting phase and reduced the risk of human oversight during the translation from standard text to a machine-readable plan.

#### 3.3.2 Human-in-the-Loop Validation

The AI-generated extraction served only as a first draft. Every requirement — its wording, assigned shape, scope, layer, and flags — underwent a comprehensive **manual review**. This step was critical to:

- Verify the technical accuracy of the AI's interpretation of protocol nuances (e.g., distinguishing between transmitter-side and receiver-side obligations).
- Refine the shape/scope classification where the standard's wording was ambiguous or where a single clause contained multiple independent requirements (flagged as `COMPOUND`).
- Identify requirements that depend on components outside the TX pipeline (flagged as `EXTERNAL_DEP`) or that are advisory rather than mandatory (flagged as `SHOULD`).
- Ensure that the resulting plan provides a reliable and authoritative basis for the subsequent VHDL implementation and testbench development.

### 3.4 Storage Format and Tooling

The Verification Plan is stored as a single TOML file (`verification_plan/verification_plan.toml`). TOML was selected for two practical reasons: (1) it is easy to read and edit by hand — each requirement is a self-contained `[[requirement]]` block with one key per line, making version-control diffs clean and merge conflicts rare; and (2) it can be parsed and manipulated programmatically by Python tools (specifically `tomlkit`, which preserves comments and formatting on round-trip). This second property was essential for building the automated tooling described below.

Each requirement entry carries metadata fields designed to drive the verification workflow:

| Field | Purpose |
| :--- | :--- |
| `shape` | Classification axis described in Section 3.2 — determines the verification primitive. |
| `scope` | Classification axis described in Section 3.2 — determines the test environment. |
| `layer` | Architectural sub-layer (LLC, MAC, PCS, or FCE), enabling a divide-and-conquer approach where each testbench targets one layer. |
| `precondition` / `event` / `postcondition` | For *triggered*-shape requirements, these three fields form a testable triplet that translates directly into a test procedure. |
| `coverage_target` | Describes how to verify the requirement (e.g., "assert CRC field matches polynomial output", "cover all four frame formats"). |
| `flags` | Marks special properties: `COMPOUND`, `AMBIGUOUS`, `EXTERNAL_DEP`, `SHOULD`, or `DOC_ONLY`. These flags inform review priority and test generation strategy. |
| `label` / `file` | Link the requirement to its implementing assertion label or testbench procedure, providing full traceability from standard clause to RTL. |

To maintain the integrity of the plan as it evolves, a **Model Context Protocol (MCP) server** (`mcp_tools/verification_plan_manager.py`) was developed. The server exposes query, update, insert, delete, and statistics operations as tool calls that the AI coding agent can invoke directly within the development environment. Each write operation creates an automatic backup and validates field values against the schema before committing changes. This design serves two purposes: first, the agent receives summarized query results rather than the entire raw file, avoiding context window bloat; and second, constraining the agent to narrow, validated operations minimizes the risk of data corruption and hallucination — rather than asking the LLM to rewrite a large structured file (where it may silently drop entries, fabricate field values, or break TOML syntax), each MCP call targets a single atomic change with schema-level validation, making such errors structurally impossible.

### 3.5 Verification Strategy

The verification plan drives a layered testing strategy, where each level targets a different scope of requirements:

- **Unit Testing**: Individual modules (Serializer, CRC, Bit Stuffer) are verified in isolation against *frame*-scope requirements.
- **Protocol Testing**: `tx_can_protocol_tb` verifies frame structure and field timing, covering *node*-scope requirements that involve FSM state and internal counters.
- **Integrated Testing**: `tx_can_tb` verifies end-to-end transmission, retries, and abort scenarios, targeting *bus*-scope requirements that involve multi-node arbitration and acknowledgment.

---

## 4. Design and Architecture

### 4.1 System Overview
A complete CAN node consists of two symmetrical pipelines: the Transmit (TX) pipeline and the Receive (RX) pipeline. These pipelines operate in parallel, sharing access to the Physical Coding Sublayer (PCS) to interact with the single-wire differential bus.

While this thesis focuses on the implementation of the **TX Pipeline**, the architecture is designed to integrate seamlessly into a full node. The transmitter is structured into three primary layers:

```mermaid
---
config:
  flowchart:
    defaultRenderer: elk
  elk:
    algorithm: layered
    mergeEdges: false
    nodePlacementStrategy: SIMPLE
  look: classic
  theme: dark
  curve: linear
---
flowchart TD
    User["User Application<br/>(Avalon-ST)"]
    FCE["Fault Confinement<br/>Entity (FCE)"]

    subgraph Node ["CAN Node"]
        subgraph TX_Pipeline ["TX Pipeline (Thesis Focus)"]
            TX_LLC["tx_llc<br/>(LLC Sub-layer)"]
            TX_MAC["tx_mac<br/>(MAC Sub-layer)"]
            TX_PCS["tx_pcs<br/>(PCS Sub-layer)"]

            TX_LLC <==> TX_MAC <==> TX_PCS
        end

        subgraph RX_Pipeline ["RX Pipeline"]
            RX_PCS["rx_pcs<br/>(PCS Sub-layer)"]
            RX_MAC["rx_mac<br/>(MAC Sub-layer)"]
            RX_LLC["rx_llc<br/>(LLC Sub-layer)"]

            RX_PCS <==> RX_MAC <==> RX_LLC
        end

        %% Control & Status paths
        FCE <==> TX_LLC & TX_MAC & TX_PCS
        FCE <==> RX_LLC & RX_MAC & RX_PCS
    end

    User <==> TX_LLC
    RX_LLC <==> User

    TX_PCS <==> Bus["CAN Bus"]
    Bus <==> RX_PCS
``````

### 4.2 LLC Sub-layer (`tx_llc`)
Responsible for frame buffering and retransmission management. It provides an Avalon-ST interface to the user application and communicates with the FCE to handle retransmission limits and error status reporting.

### 4.3 MAC Sub-layer (`tx_mac`)
The core of the protocol logic. It handles bit serialization, CRC calculation, and bit stuffing. It coordinates the overall frame state machine and interacts closely with the Fault Confinement Entity (FCE) to manage error counters (TEC/REC) and node state (Error Active/Passive/Bus Off) based on protocol violations.

### 4.4 PCS Sub-layer (`tx_pcs`)
Handles bit timing and synchronization. It generates the sample point (SP) and secondary sample point (SSP) strobes. It provides bit-level monitoring data to the FCE to detect synchronization and timing errors.

---

## 5. Implementation

### 5.1 Type Safety and Packages
The implementation uses custom record types (defined in `can_types_pkg.vhd`) to ensure clean interfaces between modules.

### 5.2 Bit Timing and TDC
Detailed description of how `tx_pcs` measures propagation delay and calculates the SSP.

### 5.3 CRC and Bit Stuffing
Implementation details of the flexible CRC generator and the hybrid bit stuffer.

---

## 6. Verification and Results

*Note: This section is currently being populated as the verification plan is executed.*

### 6.1 Testbench Results Summary
| Testbench | Status | Coverage |
| :--- | :--- | :--- |
| `tx_pcs_tb` | ✅ Pass | 95% |
| `tx_can_tb` | ✅ Pass | 88% |
| `tx_can_protocol_tb` | ✅ Pass | 92% |

---

## 7. Discussion
Comparison of the implemented architecture against theoretical models. Performance analysis in high-load scenarios.

---

## 8. Conclusion
Summary of work completed and how objectives were met.

---

## 9. References

<!-- Generated automatically by Pandoc from docs/references.bib -->
