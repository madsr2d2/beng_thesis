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

**TODO**: Add a section on the IO extender board (The board is on the test wall, get the name from Alex)

## Motivation {#sec:motivation}

The Controller Area Network (CAN) has been the workhorse of automotive and industrial communication for decades. However, the increasing bandwidth requirements of modern systems led to the development of CAN-FD (Flexible Data rate), which allows for larger payloads and higher bit rates. This project aims to provide a robust, hardware-independent VHDL implementation of a CAN-FD transmitter.

## Existing CAN Controller {#sec:existing-controller}

The starting point for this project is an existing CAN Classic controller developed internally at the company. The controller is implemented in VHDL and has been integrated into a production IO-extender FPGA design. It supports CAN Classic frames with both 11-bit (base) and 29-bit (extended) identifiers at bit rates up to 500 kbit/s, and has been verified through hardware bring-up on physical CAN buses.

The controller follows a monolithic architecture where a single top-level wrapper (`can_bus_controller`) instantiates six sub-modules: a combined TX/RX frame FSM (`can_fsm`), a bit timing generator (`can_node_clock`), a dynamic bit stuffer (`can_stuff_bit_gen`), a CRC-15 engine (`gen_crc`), and two Avalon-ST converters for frame serialization and deserialization (`can_ast_to_serial`, `can_serial_to_ast`). The entire design totals roughly 2,000 lines of VHDL across seven source files.

The central component is `can_fsm`, an 810-line state machine with 18 states that handles both transmission and reception in a single process. The FSM manages frame arbitration, bit-level transmission and reception, stuff bit error checking, CRC validation, ACK handling, and error flag generation. Error counting (TEC/REC) and node state transitions (Error Active, Error Passive, Bus Off) are handled in separate processes within the same file but are tightly coupled to the main FSM through shared signals.

### Limitations {#sec:existing-limitations}

While the existing controller is functional for CAN Classic, several architectural limitations prevent it from being extended to support CAN FD:

**Single bit rate domain.** The `can_node_clock` module generates a single pair of timing strobes - one sample pulse and one transmit pulse - derived from a fixed set of bit timing parameters. CAN FD requires switching between a nominal bit rate (used during arbitration) and a faster data bit rate (used during the data phase), with Transmitter Delay Compensation (TDC) to account for the transceiver round-trip delay at the higher rate. Adding dual bit rate support and TDC to the existing clock module would require a fundamental redesign of the timing architecture.

**Dynamic bit stuffing only.** The `can_stuff_bit_gen` module implements the CAN Classic rule of inserting an inverse bit after five consecutive identical bits. CAN FD introduces a second stuffing mode - fixed bit stuffing - where a stuff bit is inserted at fixed intervals during the CRC field, and a Stuff Bit Count (SBC) field with Gray-coded parity is appended. The existing stuffer has no mechanism for mode switching or SBC generation.

**Single CRC polynomial.** The controller uses a single CRC-15 instance. CAN FD requires three CRC polynomials: CRC-15 for Classic frames, CRC-17 for FD frames with payloads up to 16 bytes, and CRC-21 for larger FD payloads. Furthermore, the CRC data feed differs between Classic and FD - in FD frames, dynamic stuff bits in the arbitration region are included in the CRC computation, requiring a dual data feed to the CRC engine.

**Combined TX/RX FSM.** The monolithic FSM interleaves transmission and reception logic in every state, with the `is_transmitter` flag selecting the active code path. This coupling makes it difficult to add FD-specific states (such as BRS, ESI, and the SBC field) without increasing the already high cyclomatic complexity. A CAN FD frame has more control fields than a Classic frame, and handling both TX and RX paths for all four frame formats (Classic Base, Classic Extended, FD Base, FD Extended) in a single process would result in an unwieldy state machine.

**Embedded error handling.** Error detection, error flag transmission, and error counter management are distributed across the main FSM process and its auxiliary processes. The ISO 11898-1 standard defines the Fault Confinement Entity (FCE) as a logically separate component with well-defined interfaces to the MAC and PCS sub-layers. Extracting the error handling into a reusable, independently testable FCE module - as required by the standard's layered architecture - would require significant refactoring of the existing FSM.

### Decision to Redesign {#sec:decision-to-redesign}

Given these limitations, extending the existing controller to CAN FD would require modifying nearly every sub-module and fundamentally restructuring the FSM. The resulting design would carry the constraints of the original monolithic architecture while trying to support a significantly more complex protocol. Instead, a clean-sheet redesign was chosen, structured around the ISO 11898-1 layered architecture (LLC, MAC, PCS, FCE) with separated TX and RX paths, reusable sub-components (bit stuffer, CRC engine), and typed record interfaces. This approach allows each sub-layer to be implemented and verified independently, supports both Classic and FD frame formats from the outset, and produces a modular design that can be maintained and extended without cross-cutting changes.

## Existing CAN FD IP Cores {#sec:existing-ip-cores}

Before committing to an in-house redesign, the available CAN FD controller IP cores were evaluated. @tbl:canfd-ip-survey summarizes the candidates, spanning both open-source and commercial offerings.

### Open-Source Implementations {#sec:open-source-implementations}

**CTU CAN FD** [@ctucanfd; @jerabek2019] is the only mature open-source CAN FD controller available as synthesizable HDL. Developed at the Czech Technical University in Prague, it is written in VHDL, licensed under MIT, and has been conformance-tested against ISO 16845-1 [@iso16845_1]. The controller includes a full TX and RX pipeline with up to four TX buffers, acceptance filtering, timestamping, and a register interface with DMA support. A mainline Linux kernel driver has been available since kernel version 5.12. CTU CAN FD represents a complete, production-oriented CAN node - a significantly broader scope than what is needed in this project.

**OpenCores CAN** [@opencores_can] is a Verilog controller modeled after the Philips SJA1000 register interface. It is one of the earliest open-source CAN cores and is widely cited in academic work. However, it supports only CAN 2.0B (Classic CAN) and has seen no active development since approximately 2010. It cannot serve as a starting point for CAN FD.

**Canola** [@canola] is a VHDL CAN 2.0B controller with a clean VHDL-2008 codebase and a cocotb-based testbench. It includes a Triple Modular Redundancy (TMR) wrapper for radiation-tolerant applications. Like the OpenCores core, it does not support CAN FD.

### Commercial Implementations {#sec:commercial-implementations}

**Bosch M\_CAN** [@bosch_mcan; @hartwich2012] is the reference CAN FD controller, developed by the inventor of both CAN and CAN FD. M\_CAN is the IP core embedded in virtually every automotive microcontroller (NXP S32, Infineon AURIX, STM32, TI Jacinto, Renesas RH850). It is licensed under NDA with per-design royalty fees.

**AMD/Xilinx CAN FD** [@xilinx_canfd] is a soft IP core included in the Vivado Design Suite. It provides an AXI4-Lite register interface with up to 32 acceptance filters, TX mailboxes, and RX FIFOs. It is device-locked to AMD/Xilinx FPGAs and cannot be ported to other targets.

**CAST CAN FD** [@cast_canfd] is a technology-independent RTL core with AMBA APB/AHB bus interface options. It is licensed per-design with an upfront fee. Synopsys (DesignWare) and Cadence offer similar ASIC-targeted CAN FD cores under their respective IP licensing programs.

| Implementation | Language | CAN FD | License | Scope | Conformance Tested |
|---|---|---|---|---|---|
| CTU CAN FD [@ctucanfd] | VHDL | Yes | MIT | Full node (TX+RX, buffers, DMA) | ISO 16845-1 |
| OpenCores CAN [@opencores_can] | Verilog | No | LGPL | Full node (CAN 2.0B only) | No |
| Canola [@canola] | VHDL | No | MIT | Full node (CAN 2.0B, TMR) | No |
| Bosch M\_CAN [@bosch_mcan] | HDL (NDA) | Yes | Per-design royalty | Full node | Yes (reference) |
| AMD/Xilinx CAN FD [@xilinx_canfd] | HDL | Yes | Vivado-included | Full node | Yes |
| CAST CAN FD [@cast_canfd] | RTL | Yes | Per-design fee | Full node | Yes |

: Survey of available CAN FD controller IP cores. {#tbl:canfd-ip-survey}

### Rationale for In-House Development {#sec:rationale-in-house}

Despite the availability of these solutions, none satisfies the combined requirements of a large engine design company developing safety-critical control systems. The decision to develop the CAN FD transceiver in-house was driven by five considerations.

**TODO**: Add something about the 30 year maintenance requirements that the company is responsible for (hard to rely on 3rd party products for this long).
**IP ownership and supply chain independence.** Commercial IP cores introduce a licensing dependency on an external vendor. For a product with a multi-decade lifecycle - typical in heavy-duty engine applications - this dependency carries risk: vendors may discontinue support, change licensing terms, or be acquired. Owning the RTL outright eliminates this exposure and ensures that the design can be maintained, ported, and modified without third-party approval for the full product lifetime. The open-source CTU CAN FD avoids the licensing risk, but using it still means adopting a codebase whose architecture, naming conventions, and design decisions were made for a different context.

**Verification authority.** In safety-critical domains, the verification evidence must be traceable from standard requirements to RTL assertions and testbench results. Adopting a third-party core - even one conformance-tested against ISO 16845-1 - means inheriting its verification artifacts rather than producing them. The company's verification methodology requires full control over the verification plan, the testbench architecture, and the assertion coverage. Building the RTL in-house allows the verification plan (described in @sec:verification-planning) to drive the implementation, ensuring that every module is verified against the specific requirements extracted from the standard, using the company's own toolchain and conventions.

**Architectural scope.** All available IP cores implement a complete CAN node: TX and RX pipelines, message RAM, acceptance filtering, buffer management, register interfaces, and in some cases DMA controllers. The company's application requires only the data link layer (LLC, MAC, FCE) and physical coding sublayer (PCS) - the protocol engine that converts between byte-level frame data and the serial bus. The higher-level buffering and filtering logic already exists in the company's FPGA infrastructure. Adopting a full-node IP core would introduce unnecessary complexity and area overhead, and the integration effort to bypass or disable the unused subsystems may approach the effort of a targeted implementation.

**Integration with existing infrastructure.** The company's FPGA designs use a specific Avalon-ST streaming interface for inter-module communication, a particular clock and reset architecture, and established conventions for signal naming and module boundaries. A third-party core would require an adaptation layer to bridge its native interface (AXI, APB, or custom register map) to the existing infrastructure. The in-house design uses the company's interface conventions natively, eliminating this integration overhead.

**Platform independence.** The AMD/Xilinx CAN FD core is locked to Xilinx devices. The Bosch M\_CAN and other commercial cores are delivered as technology-specific netlists or encrypted RTL for a particular target. The in-house design is written in portable VHDL-2008, synthesizable on any FPGA platform or ASIC flow, ensuring that the IP remains usable if the company changes FPGA vendors.

## Problem Statement {#sec:problem-statement}

The need for CAN FD support in the company's engine controller platform, combined with the architectural limitations of the existing CAN Classic controller (@sec:existing-limitations) and the unsuitability of available third-party IP cores for the company's specific requirements (@sec:rationale-in-house), motivates the development of a new CAN FD transceiver from the ground up. The challenge lies in creating a modular, independently verifiable implementation that supports both Classic and FD frame formats, handles dual bit rate switching with Transmitter Delay Compensation (TDC), and maintains strict compliance with ISO 11898-1 [@iso11898_1] - all while fitting into the company's existing FPGA infrastructure and verification methodology.

## Objectives {#sec:objectives}

- Implement a VHDL-2008 compliant CAN/CAN-FD transmitter.
- Support both Base (11-bit) and Extended (29-bit) identifiers.
- Implement TDC measurement and compensation logic.
- Ensure high verification coverage using OSVVM and GHDL.

# Background {#sec:background}

## CAN Protocol Evolution {#sec:can-protocol-evolution}

Brief history from CAN 2.0 to CAN-FD.

## ISO 11898-1:2024 Standard {#sec:iso-standard}

Overview of the data link layer and physical signaling requirements [@iso11898_1].

![CAN-Bus consisting of three CAN nodes.](figures/can_bus.png){#fig:can_bus width=50%}

## VHDL and OSVVM {#sec:vhdl-osvvm}

The role of modern VHDL standards and verification frameworks in digital design.

# Requirements Engineering & Verification Planning {#sec:requirements-engineering}

Bridging the gap between a normative specification document and a traceable verification plan is a pivotal task in any protocol implementation project. The present section describes the process of distilling a coherent set of verifiable requirements and associated verification plan from the ISO 11898-1 standard. In addition, the constraints imposed by general company practices and standards are described along with project-specific requirements related to the larger system in which the module is intended to integrate.

## VHDL Code Standard and Design Constraints {#sec:engineering-constraints}

The constraints on this project come from two distinct sources. Two requirements are specific to this project's place within the company's existing CAN infrastructure while the remaining constraints come from the company's VHDL Code Standard and apply uniformly to all FPGA IP modules developed in-house.

### Project-specific Infrastructure Requirements

1. **Avalon-ST user interface:** The CAN controller's external interface to the host system must use the Avalon-ST streaming protocol [@avalon_st] (data, valid, ready, sop, eop). The requirement applies specifically to the boundary between the CAN controller and its user.
2. **IP library CRC block:** The company maintains a reusable, parameterised CRC generator (`gen_crc`) in its IP library. This module must be used for all CRC computations.

### File Structure and Naming

1. **Per-module file structure:** Each module must be organized into a fixed directory layout: `hdl_src/` for RTL source files, `hdl_tb/` for test bench files, and `test_case/` for waveform configuration. One entity per VHDL file, with the filename matching the entity name. Every entity requires a dedicated test bench, unless it is instantiated exclusively as a sub-module of a fully tested parent.
2. **Entity port types:** Entity ports are restricted to `std_logic`, `std_logic_vector`, and records or arrays of these types. Modes are restricted to `in` and `out`.
3. **Naming conventions:** A mandatory prefix/suffix scheme applies to all VHDL identifiers: types (`t_`), constants (`c_`), generics (`gc_`), processes (`p_`), functions (`f_`), packages (`pk_`), state variables (`s_`), entity inputs (`_i`), and entity outputs (`_o`).

### RTL Coding Style and Verification

1. **RTL design rules:** Synchronous processes must be sensitive to the clock only. Reset must be synchronous and initialize all control registers. FSMs are preferably implemented as single-process designs where all signal assignments are derived from the current state, with an explicit other-state that returns to a known safe state.
2. **Test bench requirements:** Test benches must follow a black-box testing model and test cases must be ordered as: reset tests first, then a normal-usage test, then all remaining tests.

## From Specification to Structured Requirements {#sec:req-extraction}

The requirements engineering process was aimed at tackling two key objectives:

1. Extracting a clear and actionable set of requirements that could serve as a starting point for the design phase.
2. Establishing a clear, traceable link between the ISO 11898-1 specification and the verification environment.

Both objectives are complicated by the nature of the source material. Normative requirements are distributed across subsections, often restated from different perspectives, and interspersed with explanatory and descriptive text. Accordingly, extracting a precise unambiguous set of requirements from such prose is non-trivial and inherently prone to oversights and misinterpretations. Nonetheless, a structured and precise requirements set is absolutely essential. It serves as both the starting point for the system design phase and as the target of verification effort. [@bergeron2003ch3]

The requirements set was constructed using the AI-assisted pipeline shown in @fig:ver_plan_pipeline. The first step was converting the ISO 11898-1 pdf to Markdown - a format which can be efficiently searched and ingested by LLM models. The resulting Markdown file was then fed to a Claude Sonnet 4.6 LLM agent, which was prompted to extract all normative statements - sentences containing words like "shall", "should", "must", and their corresponding negations.

![Pipeline generating the `verification_plan.toml` artifact. 1) LLM agent extraction of normative statements from the ISO 11898-1 standard. 2) Manual grouping of related normative statements and requirement distillation. 3) Argumentation with additional requirement labels and verification specific fields.](figures/ver_plan_pipeline.png){#fig:ver_plan_pipeline width=100%}

This process yielded a raw set of 168 normative statements linked to the ISO standard sections from which they were extracted. The normative set was then manually reviewed, consolidated, and distilled into a final set of 45 requirements. In addition to the ISO standard section links provided by the initial LLM agent extraction, each requirement was classified along the following set of dimensions:

- layer, @sec:vplan-layer
- side, @sec:vplan-side
- format, @sec:vplan-format
- priority, @sec:vplan-priority
- observability, @sec:vplan-observability

These dimensions, described in the following subsections, should serve to focus the design phase by carving out the natural sub-module boundaries and guide the verification effort by highlighting the relevant layer of abstraction associated with a given requirement.


### Layer {#sec:vplan-layer}

The ISO 11898-1 structures the CAN protocol into three functional sub-layers and a layer-spanning Fault Confinement Entity (FCE):

- Logic Link Control (LLC).
- Medium Access Control (MAC).
- Physical Coding Sub-layer (PCS).

Each of these have a dedicated section in the ISO 11898-1 standard and the layer field assigns each requirement to the protocol sub-layer that owns it. This classification determines the verification boundary at which each requirement must be exercised. A fifth label - **system** - was introduced alongside the four protocol layers to classify requirements that are inherently multi-layer or multi-node in character. Some CAN behaviors cannot be attributed to a single layer of a single node. They emerge from interactions between multiple nodes on the bus, or span the layer boundary within a single node. The system label flags these requirements as ones that require either an integrated multi-module test bench or a multi-node simulation environment.

### Side {#sec:vplan-side}

The side field records whether a requirement pertains to the transmitter path, the receiver path, or both roles simultaneously. This dimension reflects the ISO standard's own framing, which frequently specifies transmitter and receiver obligations separately.

### Format Applicability {#sec:vplan-format}

The format_applicability field records which of the four in-scope frame formats (CB, CE, FB, FE) each requirement applies to. This field determines which testbench stimulus configurations are required to exercise a given requirement.

### Observability {#sec:vplan-observability}

The observability field resolves each requirement as either black-box or white-box, relative to the module boundary of the owning layer:

- **Black-box**: Can be verified purely through the module's observable port signals.
- **White-box**: Verification requires direct observation of the module's internal state.

### Priority {#sec:vplan-priority}

The priority field classifies each requirement into one of three levels:  

- P1 requirements are need-to-have - they must be verified before the design can be considered complete.
- P2 requirements are nice-to-have - they are verified in the normal verification cycle but do not block closure.
- P3 requirements are optional - addressed only if schedule permits.

## Verification Plan Data Structure {#sec:verification-plan-data-structure}

The verification plan data structure (@tbl:vplan-metadata-fields) augments each requirement with the dimensions needed to answer not just *what* must be true, but *how* it will be verified, *where* the evidence lives, and *when* verification is complete. The verification plan was a very lively document throughout the project and it was continuously updated as implementation and verification work progressed. The following sub-sections detail the rationale and allowed values for each field in the verification plan. The complete verification plan is reproduced in @sec:appendix-vplan as two separate tables (linked by common ID's).


| Field | Purpose |
| :--- | :--- |
| `id` | Sequential identifier REQ-NNN. |
| `source_clause` | ISO 11898-1:2024 section reference. |
| `original_wording` | Verbatim normative text excerpets from the ISO standard.|
| `paraphrase` | Concise paraphrase of the `original_wording` field (this is the actual requerment) |
| `layer` | Sub-layer owner: LLC, MAC, PCS, FCE, or system (@sec:vplan-layer). |
| `side` |  transmitter, receiver, or both (@sec:vplan-side). |
| `format_applicability` | Applicable frame formats: CB, CE, FB, FE (@sec:vplan-format). |
| `observability` | `black_box` or `white_box` (@sec:vplan-observability). |
| `verification_method` | Method(s) used to verify the requirement (@sec:vplan-method). |
| `priority` | P1 (need-to-have), P2 (nice-to-have), or P3 (optional) (@sec:vplan-priority). |
| `status` | `not_started`, `in_progress` or `complete` (@sec:vplan-status). |
| `notes` | The field is intended to celrify residual ambiguity left over form the other fields |
| `label` | Assertion label, TB procedure name, coverage ID, or RTL tag. Comma-separated when multiple procedures cover distinct sub-claims (@sec:vplan-traceability). |
| `file` | Target file: TB for simulation/coverage, RTL for code inspection. Comma-separated when sub-claims span multiple files (@sec:vplan-traceability). |

: Verification-plan data structure fields. {#tbl:vplan-metadata-fields}

### Verification Method {#sec:vplan-method}

The verification_method field makes the path from requirement to verification artifact explicit and actionable. Four methods are used: `simulation` (automated assertion procedures in a test bench), `code_inspection`  (RTL source review), `waveform_inspection` (manual review of simulation output), and `coverage` (coverage bins a value range). Combinations are valid when multiple sub-claims within one requirement each call for a different method.


### Traceability: Label and File {#sec:vplan-traceability}

Each requirement entry carries two dedicated traceability fields: a `file` field identifying the test bench or RTL source file responsible for covering the requirement, and a `label` field identifying a specific named procedure, assertion, or coverage ID within that file. Together they establish a direct, navigable link from each requirement to its verification artifact.

### Status {#sec:vplan-status}

The status field (`not_started`, `in_progress`, `complete`) records requirement closure state explicitly, allowing partial progress to be tracked.

## AI-Assisted Extraction: Utility and Limitations {#sec:ai-extraction}

The LLM agent definitely earned its keep by bootstrapping and linking the initial normative statement set. Having a fully populated and liked starting point - even one requiring substantial revision - gave the manual review process a concrete artifact to work from. That said, the overall time saving was likely marginal. The agent's output had to be reviewed statement by statement, which is functionally similar to extracting requirements manually in the first place. The primary benefit of the AI-assisted approach was therefore not efficiency, but rather the increased consistency associated with an automated extraction process.

# Design and Architecture {#sec:design-architecture}

## Ramifications of the Requirements Model on Initial Design Strategy {#sec:req-design-ramifications}

The structure of the requirements model had direct consequences for the initial design strategy, in ways that were not fully anticipated at the outset.

The **layer dimension** mapped naturally onto the ISO standard's own layered reference model, making a layered module architecture look like the obvious and well-motivated implementation strategy. A dedicated hardware module for each layer - MAC, LLC, fault confinement, and PCS - would allow requirements pertaining to a given layer to be verified in isolation against that layer's module, rather than through the surface of a fully integrated system where internal behavior is obscured by surrounding logic. The observability dimension reinforced this directly: black-box requirements mapped cleanly onto port-level stimulus and observation, while white-box requirements pointed toward the need for reference models or PSL assertions on internal signals, both of which are most tractable in a per-module testbench. In retrospect, this was a sound conclusion. The modular architecture proved to be the right design choice, and the requirements table provided a well-motivated rationale for it from the start.

The **TX/RX side dimension** had a subtler and more consequential effect. Organizing requirements along the transmitter/receiver axis made intuitive sense from a specification perspective - the ISO standard itself frames many requirements in terms of transmitter behavior and receiver behavior - and it was genuinely useful for thinking through which requirements belonged where. However, it also made a split-path implementation architecture look like the natural design strategy, simply because the requirements were literally organized along that split. The implication appeared to be: implement a TX module, implement an RX module, and map the TX requirements to the former and the RX requirements to the latter.

This turned out to be a red herring. The pitfalls of the split-path approach were not at all apparent from the requirements table alone. The table made the split architecture look clean and well-motivated. The problems - design drift between separately implemented FSMs, integration complexity, and unnecessary hardware duplication - only surfaced later, during integration. This is an important general lesson: the structure of a requirements model can inadvertently bias architectural decisions in ways that are not immediately obvious, and the apparent naturalness of a design strategy that mirrors the requirements structure is not in itself a reliable signal that the strategy is sound.

## Architectural Design Decisions {#sec:architectural-design-decisions}

Before settling on the final architecture, several design alternatives were evaluated. The exploration drew on three sources: the existing in-house CAN Classic controller (@sec:existing-controller), the open-source CTU CAN FD core [@ctucanfd; @jerabek2019], and the ISO 11898-1 standard's own layered reference model [@iso11898_1]. The protocol requirements and engineering constraints documented in @sec:requirements bound the feasible design space; this section documents the key decisions made within it.

### Monolithic vs. Layered Architecture {#sec:monolithic-vs-layered}

The most fundamental architectural decision was whether to extend the existing monolithic controller or adopt a layered decomposition.

The existing controller uses a flat architecture: a single FSM (`can_fsm`, 810 lines) directly drives the bus output, reads the bus input, manages bit counting, handles stuff bit insertion, coordinates CRC computation, and updates error counters - all in one clocked process. This approach minimizes inter-module latency and signal fanout, since every decision is made in a single combinational cone. For CAN Classic, where the frame has at most two format variants (base and extended) and a single bit rate, the complexity is manageable.

CAN FD, however, introduces four frame formats, dual bit rates, fixed bit stuffing with SBC encoding, three CRC polynomials, and a richer error model. Extending the monolithic FSM to cover these features would require nested conditionals on the format type in nearly every state, increasing the cyclomatic complexity well beyond what is practical to verify or maintain. The existing controller's `s_arbitration` state already contains 70 lines of interleaved TX/RX logic for two frame formats; scaling this to four formats with additional control fields (BRS, ESI, SBC) would roughly triple the state's complexity.

The alternative - and the approach adopted - is to follow the ISO 11898-1 reference model, which decomposes the data link layer into LLC, MAC, and PCS sub-layers with a separate FCE. Each sub-layer has a well-defined service interface (described in @sec:canonical-layer-interfaces), and each can be implemented and verified independently. This decomposition introduces inter-module interfaces and pipeline latency, but it confines format-specific complexity to the module where it belongs: the MAC FSM handles frame field sequencing, the bit stuffer handles stuff bit insertion and SBC generation, and the CRC engine handles polynomial computation. No module needs to know about all three concerns simultaneously.

CTU CAN FD [@ctucanfd] takes a middle path: it separates protocol processing (in a `CAN Core` block) from buffer management and register access, but the protocol core itself remains a large monolithic unit. This is a reasonable trade-off for a general-purpose IP core that must support message filtering, multiple TX buffers, and DMA - features that require tight coupling between the protocol engine and the buffer subsystem. For the narrower scope of this project (protocol engine only, no message RAM or filtering), the full ISO layered decomposition is feasible and preferred because it directly maps each module to a testable subset of the standard's requirements.

### Combined vs. Separated TX/RX FSMs {#sec:combined-vs-separated-fsm}

The existing controller uses a single FSM for both transmission and reception, switching between roles via an `is_transmitter` flag. Every state contains parallel `if transmit_i` and `elsif sample_rx_i` branches, one for the transmitter path and one for the receiver path. This approach has two advantages: it avoids duplicating shared state (bit counters, format detection) and it naturally handles the transmitter-to-receiver role switch that occurs when a node loses arbitration.

The disadvantage is that TX and RX logic evolve together. Adding a TX-only feature (such as the data-phase bit rate switch) requires modifying states that also contain RX logic, and vice versa. In CAN FD, the TX and RX paths diverge more than in CAN Classic: the transmitter drives BRS and ESI based on local state, while the receiver samples and validates them. The transmitter feeds the CRC engine with transmitted bits, while the receiver feeds it with received bits (including dynamic stuff bits in the arbitration region, per ISO 6.6.13.3). Encoding both paths in every state produces deeply nested conditionals that are difficult to review and difficult to cover in verification.

The chosen design uses separate TX and RX FSMs (`can_mac_fsm_tx` with 19 states, `can_mac_fsm_rx` with 17 states), each with its own bit stuffer and CRC interface. The two FSMs share no state. Arbitration loss in the TX FSM triggers a `transfer_status` change, but the actual reception of the frame is handled by the RX FSM operating independently on the same bus. This separation means that the TX FSM can be verified exhaustively against TX-side requirements without any RX stimulus beyond bus-level loopback, and conversely for the RX FSM.

The cost of separation is that sub-components used by both paths - the bit stuffer (`can_mac_bs`) and CRC engine (`can_mac_crc`) - must be either shared with multiplexing logic or duplicated. The chosen design duplicates both: `can_mac_tx` instantiates its own `can_mac_bs` and `can_mac_crc`, and `can_mac_rx` does the same. This trades a modest increase in area for complete independence between the two paths - each FSM drives its bit stuffer and CRC engine through its own interface signals without any arbitration or routing logic. The duplication is justified because the bit stuffer and CRC engine are small combinational-plus-register modules (under 120 and 80 lines respectively), while a shared-resource approach would require multiplexing logic in the `can_mac` wrapper and careful coordination to prevent one path's state from corrupting the other's. The `can_mac` wrapper (@sec:can-mac-wrapper) therefore contains no datapath logic at all - it is purely structural, instantiating `can_mac_tx`, `can_mac_rx`, and `can_fce`, and merging only the FCE error signals.

### Per-Field vs. Per-Phase FSM Granularity {#sec:per-field-vs-per-phase}

A second FSM design decision was the granularity of states. The existing controller uses per-phase states: `s_arbitration` covers all ID bits, SRR, IDE, and RTR; `s_control` covers reserved bits and DLC; `s_data` covers all data bytes. Within each state, a bit counter and conditional logic dispatch the correct action for each bit position.

This per-phase approach keeps the state count low (18 states in the existing controller) but pushes complexity into the bit-counting logic. The `s_arbitration` state must distinguish between base and extended formats using the bit counter, handle the SRR/IDE branching point at bit 12/13, and detect arbitration loss - all in a single state with a single counter.

The alternative is per-field states, where each protocol field (SOF, ID, SRR/RRS, IDE, FDF, RES, BRS, ESI, DLC, Data, SBC, CRC, ACK, EOF) has its own state. This increases the state count (19 TX states, 17 RX states) but eliminates most bit-counter conditionals: when the FSM is in `s_brs`, it knows exactly which bit it is processing without consulting a counter. Format-dependent transitions are handled by the state graph itself - for example, the FSM transitions from `s_ide` to `s_fdf_r1_r0` for all formats, but from `s_fdf_r1_r0` it may go to `s_dlc` (Classic) or `s_res_r0` then `s_brs` (FD). Each state contains only the logic relevant to its specific field, and named guard predicates (`v_in_arbitration_field`, `v_in_dynamic_stuff_field`, `v_in_fixed_stuff_field`) replace repeated bit-range comparisons.

The per-field approach was chosen because it aligns with the verification plan: each field in the frame structure corresponds to a set of requirements in the verification plan, and each FSM state can be traced directly to those requirements. It also simplifies formal verification, since PSL assertions can reference state names rather than counter ranges.

### Interface Record Design {#sec:interface-record-design}

The company's `std_logic`-only port constraint does not preclude the use of VHDL record types on entity ports - records of `std_logic` and `std_logic_vector` fields satisfy the constraint. The design uses typed record interfaces (e.g., `t_can_mac_pcs_if_m2s`, `t_can_mac_fsm_bs_if_s2m`) to bundle related signals into a single port. Each record type has a corresponding reset constant (e.g., `c_can_mac_pcs_if_m2s_reset`), ensuring that every module can be reset to a known state without manually enumerating each field.

The alternative - flat port lists with individual `std_logic` signals - was used in the existing controller, where the FSM entity has 20 individual ports for its various sub-module interfaces. This approach becomes unwieldy as the number of inter-module signals grows: the new design has over 60 inter-module signals across its interfaces, and bundling them into records reduces the port list from dozens of lines to six record-typed ports per FSM entity.

The naming convention follows the data-flow direction: `m2s`/`s2m` (master-to-slave/slave-to-master) for control interfaces, and `s2d`/`d2s` (source-to-destination/destination-to-source) for Avalon-ST data-transfer interfaces. This convention is consistent with the company's existing interface naming and makes the direction of data flow explicit at every port.

### Dual CRC Data Feeds {#sec:dual-crc-data-feeds}

A non-obvious design decision concerns the CRC engine's data input. In CAN Classic, the CRC is computed over the raw bit stream excluding stuff bits. In CAN FD, the CRC is computed over the raw bit stream in most of the frame, but in the arbitration region the computation includes dynamic stuff bits - a difference from Classic that exists because the FD CRC must protect the stuff bit count as well as the data. This means that a single data feed to the CRC engine is insufficient: the Classic CRC needs the de-stuffed stream, while the FD CRC needs the stuffed stream during arbitration and the de-stuffed stream elsewhere.

The chosen solution exposes two data inputs on the CRC interface: `data_cc` (Classic CAN data, always de-stuffed) and `data_fd` (FD data, which includes dynamic stuff bits during the arbitration region). The FSM drives both feeds, and the CRC wrapper routes `data_cc` to the CRC-15 engine and `data_fd` to the CRC-17 and CRC-21 engines. This avoids multiplexing logic inside the CRC module and keeps the CRC wrapper purely structural - it instantiates three `gen_crc` blocks and an output mux, with no protocol knowledge.

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

## LLC Sub-layer {#sec:llc-sub-layer}

Responsible for frame buffering and retransmission management. It provides an Avalon-ST interface to the user application and communicates with the FCE to handle retransmission limits and error status reporting.

### `can_llc_tx` {#sec:can-llc-tx}

`can_llc_tx` buffers an incoming LLC frame from the user, streams it byte-by-byte to the MAC serializer, and manages retransmission on bus disturbance up to the ISO-mandated limit [@iso11898_1, sec. 6.4.5 and 6.5].

### `can_llc_rx` {#sec:can-llc-rx}

`can_llc_rx` receives a reconstructed LLC frame from the MAC layer, applies acceptance filtering, and delivers accepted frames to the user over the `llc_rx_if` Avalon-ST stream [@iso11898_1, sec. 6.4.5].

## MAC Sub-layer {#sec:mac-sub-layer}

The MAC sub-layer is the core of the protocol logic, responsible for bit serialization, CRC generation, bit stuffing, and frame-level error detection. It coordinates closely with the FCE (@sec:fce-sub-layer) for error counter management and node-state transitions (Error Active/Passive/Bus Off), and with the PCS (@sec:pcs-sub-layer) for sample-point-driven bit output.

The earlier CAN bus controller concentrated TX, RX, MAC, and FCE logic in a single monolithic FSM (`can_fsm`), with the sub-functions - serialization (`can_ast_to_serial`), bit stuffing (`can_stuff_bit_gen`), and CRC (`gen_crc`) - implemented in satellite modules driven directly by it. PCS timing logic was implemented in `can_node_clock`, which fed sample-point and transmit pulses into `can_fsm` - a strategy retained in the current design.

The current design restructures these modules around the ISO 11898-1 [@iso11898_1] layer boundaries. On the TX side the mapping is direct: `can_ast_to_serial` becomes `can_mac_ser_tx` (@sec:can-mac-ser-tx), `can_stuff_bit_gen` becomes `can_mac_bs` (@sec:can-mac-bs), `gen_crc` becomes `can_mac_crc` (@sec:can-mac-crc), and `can_node_clock` becomes `can_pcs_tx` (@sec:can-pcs-tx). The bit stuffer and CRC engine are reused across both paths - each of `can_mac_tx` and `can_mac_rx` instantiates its own copy of the same `can_mac_bs` and `can_mac_crc` entities, with the RX path reusing the bit stuffer for destuffing and the CRC engine for CRC checking. The RX FSM (`can_mac_fsm_rx`) stores received bits directly in an internal frame array and streams the completed frame to the LLC during the quiet phase, eliminating the need for a separate deserializer module. Fault confinement, previously embedded in `can_fsm`, is separated into its own entity (`can_fce`) and wired through the unified `can_mac` wrapper (@sec:can-mac-wrapper).

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

![REQ-009.](figures/waveforms/full_fd_frame.pdf){#fig:full_fd_frame width=100%}

![REQ-010.](figures/waveforms/req_10_11.pdf){#fig:req_10 width=100%}

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

## Future Work {#sec:future-work}

1. Make the the CRC and BS modules to save area on the FPGA.
2. CAN XL implementation...

# Conclusion {#sec:conclusion}

Summary of work completed and how objectives were met.

# References {#sec:references}

<!-- Generated automatically by Pandoc from docs/references.bib -->

`\appendix`{=latex}

# Verification Plan {#sec:appendix-vplan}

Both tables are regenerated automatically from `verification_plan/verification_plan.toml` on each PDF build. The ID field is the join key between them. See @sec:verification-plan-data-structure for the meaning of each field.

## Extracted Requirements {#sec:appendix-requirements}

The requirements table contains four fields: the identifier, the ISO 11898-1 source clause, the priority assignment, and the paraphrase. Placing priority here allows each assignment to be evaluated directly against the requirement text. The table corresponds to the requirements extraction and prioritisation phases described in @sec:req-extraction and @sec:vplan-priority.

<!-- generated:requirements-table -->

## Verification Plan Fields {#sec:appendix-vplan-fields}

The verification plan table contains the verification metadata fields added during the planning phase. Cross-reference to the requirements table above via the shared ID field.

<!-- generated:verification-plan-table -->
