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
- [3. Requirements and Verification Planning](#3-requirements-and-verification-planning)
  - [3.1 Functional Requirements](#31-functional-requirements)
  - [3.2 Verification Plan Construction](#32-verification-plan-construction)
    - [3.2.1 Extraction and Reformatting Process](#321-extraction-and-reformatting-process)
    - [3.2.2 Human-in-the-Loop Validation](#322-human-in-the-loop-validation)
    - [3.2.3 Design Rationale and Tooling](#323-design-rationale-and-tooling)
  - [3.3 Verification Strategy](#33-verification-strategy)
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

## 3. Requirements and Verification Planning

### 3.1 Functional Requirements
The system must meet the specific requirements identified from the ISO standard. These are documented in detail in `requirements/requirements.toml` and summarized in the generated verification plan. Key categories include:
- **CRC Generation**: Support for CRC-15 (Classic), CRC-17, and CRC-21 (FD).
- **Bit Stuffing**: Dynamic stuffing for arbitration/data and fixed stuffing for FD CRC.
- **Error Handling**: Bit error, ACK error, and Form error detection.

### 3.2 Verification Plan Construction
The foundation of the project's verification effort is a structured **Verification Plan** derived directly from the normative text of ISO 11898-1:2024. This plan was constructed through a multi-stage process of requirement extraction and categorization to ensure 100% protocol compliance.

#### 3.2.1 Extraction and Reformatting Process
To manage the volume and complexity of the ISO standard, a specialized taxonomy was developed to classify requirements based on their verification "shape" (Triggered, Invariant, Liveness, or Reachability) and "scope" (Frame, Node, or Bus). This approach allowed for a more accurate representation of protocol behaviors compared to traditional simplified models.

The initial extraction of normative "shall" and "should" statements was performed using **Generative AI**. This particular task is well-suited for Large Language Models (LLMs), as they excel at processing large volumes of technical text, identifying structural patterns, and reformatting unstructured documentation into structured data formats (in this case, TOML). The use of AI significantly accelerated the initial drafting phase and reduced the risk of manual oversight during the translation from PDF to a machine-readable plan.

#### 3.2.2 Human-in-the-Loop Validation
It is important to note that the AI-generated content served only as a first draft. Every extracted requirement, its assigned shape, and its categorized scope underwent a comprehensive **manual review**. This step was critical to:
- Verify the technical accuracy of the AI's interpretation of protocol nuances.
- Refine the categorization where the standard's wording was ambiguous.
- Ensure that the resulting Verification Plan provides a reliable and authoritative basis for subsequent VHDL implementation and testbench development.

#### 3.2.3 Design Rationale and Tooling
NOTE: Not quite right. TOML was selected as a format because its eazy to read and edit manually can also be parsed by python tools (tomlkit) so MCP tools could be written to handle the manipulation on behalf of the AI agent, preventing "context window bloat" and ensuring consistency. The specific metadata fields (columns) in the TOML schema were designed to drive the verification workflow.

The choice of **TOML (Tom's Obvious Minimal Language)** as the storage format for the Verification Plan was deliberate. TOML is a structured data format that is exceptionally easy for both humans and LLMs to read and write. Its line-based structure for table keys minimizes merge conflicts and allows the AI agent to perform surgical updates without corrupting the file structure.

The specific metadata fields (columns) in the TOML schema were designed to drive the verification workflow:
- **Shape**: Directly maps the requirement to a verification primitive (e.g., `invariant` maps to a concurrent assertion, `reachability` maps to a coverage point).
- **Scope**: Defines the required verification environment (e.g., `frame`-scope requirements are verified at the bit-stream interface, while `bus`-scope requirements require a multi-node simulation).
- **Layer**: Aligns the requirement with the architectural sub-layer (LLC, MAC, PCS), facilitating a "divide and conquer" approach to implementation.

To maintain the integrity of this plan over time, a suite of **Model Context Protocol (MCP) tools** was developed. These tools allow for automated renumbering, consistency checking, and statistics generation directly within the developer's environment. By offloading these mechanical tasks to specialized tools, we ensure that the Verification Plan remains consistent and prevent "context window bloat" by providing the AI agent with summarized views rather than the entire raw file for every operation.

### 3.3 Verification Strategy
We employ a layered verification approach:
- **Unit Testing**: Individual modules (Serializer, CRC, Bit Stuffer) are verified in isolation.
- **Protocol Testing**: `tx_can_protocol_tb` verifies frame structure and field timing.
- **Integrated Testing**: `tx_can_tb` verifies end-to-end transmission, retries, and abort scenarios.

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
flowchart LR
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
        FCE -.-> TX_LLC & TX_MAC & TX_PCS
        FCE -.-> RX_LLC & RX_MAC & RX_PCS
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
- ISO 11898-1:2024 Standard
- OSVVM Documentation
- GHDL Documentation
