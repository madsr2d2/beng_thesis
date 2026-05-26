---
title: "Implementation and Verification of a CAN/CAN FD Protocol Controller in VHDL"
author: "Mads Richardt (s224948)"
date: "May 18, 2026"
bibliography: references.bib
csl: ieee.csl
link-citations: true
abstract: |
  This thesis describes the design, implementation, and verification of a CAN/CAN FD protocol controller in VHDL, targeting high-reliability engine controller applications at Everllence. The controller complies with ISO 11898-1 and supports the CB, CE, FB, and FE frame formats with dual bit rate switching and Transmitter Delay Compensation (TDC) for the FD data phase. The design is structured around the ISO 11898-1 layered reference model, with the MAC, PCS, and FCE sub-layers implemented as independently testable modules and the LLC sub-layer specified but deferred. Of 37 derived requirements, 28 are verified against passing testbenches or code inspection. Of the remaining nine, six fall outside the current scope pending `can_llc` integration, one is not applicable to this architecture (REQ-034, P3: shared memory not used), one is an optional operational feature (REQ-035, P2), and one represents identified future work: REQ-021 (error-injection under passive error conditions). The design was synthesized on a Cyclone 10 LP FPGA target, using 4,608 logic elements (30% of device) with a worst-case fmax of approximately 127 MHz.
---

```{=latex}
\clearpage
```

# Approval {-}

This thesis was prepared at the Department of Applied Mathematics and Computer Science (DTU Compute), Technical University of Denmark, in partial fulfilment of the requirements for the degree of Bachelor of Science in Engineering. The work was carried out in collaboration with Everllence, where the controller is intended for use in high-reliability engine controller applications.

It is assumed that the reader has a working knowledge of digital logic design and binary communication protocols. Familiarity with VHDL or a similar hardware description language is an advantage but is not strictly required to follow the architectural and verification discussions.

```{=latex}
\vspace{2cm}
\begin{center}
\begin{minipage}{8cm}
\centering
\rule{7cm}{0.4pt}\\[4pt]
Mads Richardt (s224948)\\[2pt]
{\small Kgs.\ Lyngby, May 2026}
\end{minipage}
\end{center}
\clearpage
```

# Acknowledgements {-}

**Edward Alexandru Todirica**, Associate Professor, DTU Compute.
Thank you for supervision throughout the project and for valuable guidance and feedback.

**Fredrik Kristensen**, Everllence.
Thank you for guidance throughout the project, code and report review, and feedback on the design and implementation.

**Alex Fihl Hedegaard Nielsen**, Everllence.
Thank you for the sparring and advice, good company - and the many coffee machine trips that kept the work moving.

```{=latex}
\clearpage
\setcounter{tocdepth}{4}
\tableofcontents
\clearpage
```

# Abbreviations {-}

| Abbreviation | Meaning |
| :--- | ---: |
| ACK | Acknowledgment |
| AD | ACK Delimiter |
| AEF | Active Error Flag |
| AI | Artificial Intelligence |
| BRS | Bit Rate Switch |
| CAN | Controller Area Network |
| CANH | CAN High bus wire |
| CANL | CAN Low bus wire |
| CB | Classic Base (frame format) |
| CBFF | Classic Base Frame Format |
| CC | CAN Classic |
| CD | CRC Delimiter |
| CE | Classic Extended (frame format) |
| CEFF | Classic Extended Frame Format |
| CRC | Cyclic Redundancy Check |
| DF | Data Frame |
| DLC | Data Length Code |
| DMA | Direct Memory Access |
| DUT | Device Under Test |
| ED | Error Delimiter |
| EOF | End of Frame |
| ESI | Error State Indicator |
| FB | FD Base (frame format) |
| FBFF | FD Base Frame Format |
| FCE | Fault Confinement Entity |
| FD | Flexible Data Rate |
| FDF | FD Frame bit |
| FE | FD Extended (frame format) |
| FEFF | FD Extended Frame Format |
| FPGA | Field-Programmable Gate Array |
| FSB | Fixed Stuff Bit |
| FSM | Finite State Machine |
| FTYP | Frame Type |
| HDL | Hardware Description Language |
| IDB | Identifier Base field (11-bit base ID) |
| IDE | Identifier Extension bit |
| IEXT | Identifier Extension field (18-bit extended ID) |
| IFS | Inter Frame Space |
| INT | Intermission |
| IP | Intellectual Property |
| IPT | Information Processing Time |
| ISO | International Organization for Standardization |
| LE | Logic Element |
| LLC | Logical Link Control |
| LLM | Large Language Model |
| MAC | Medium Access Control |
| MIT | Massachusetts Institute of Technology (license) |
| MSB | Most Significant Bit |
| OD | Overload Delimiter |
| OF | Overload Flag |
| OSVVM | Open Source VHDL Verification Methodology |
| PCS | Physical Coding Sublayer |
| PE | Phase Error |
| PEF | Passive Error Flag |
| PS | Propagation Segment (PROP_SEG) |
| PS1 | Phase Segment 1 (PHASE_SEG1) |
| PS2 | Phase Segment 2 (PHASE_SEG2) |
| RF | Remote Frame |
| RRS | Reserved Remote Request Substitution bit (FD frames) |
| RTL | Register Transfer Level |
| RTR | Remote Transmission Request |
| RX | Receiver / Receive |
| SB | Stuff Bit |
| SBC | Stuff Bit Count |
| SJW | Synchronization Jump Width |
| SOF | Start of Frame |
| SP | Sample Point |
| SRR | Substitute Remote Request |
| SS | Sync Segment (SYNC_SEG) |
| SSP | Secondary Sample Point |
| ST | Suspend Transmission |
| TDC | Transmitter Delay Compensation |
| TEC/REC | Transmit Error Counter / Receive Error Counter |
| TQ | Time Quantum |
| TX | Transmitter / Transmit |

: Abbreviations used in this report. {#tbl:abbreviations}

```{=latex}
\clearpage
\listoffigures
\clearpage
```

# Reading Guide {-}

The report is structured in two parts. The first establishes context: the Introduction motivates the project and states the objectives; the Background (@sec:background) and Protocol Overview (@sec:can-protocol-overview) provide technical foundations on CAN and CAN FD. The second part is the technical contribution: Requirements, Verification Plan, Design and Architecture, Implementation, Verification and Results, and Synthesis form the core chapters, followed by Discussion and Conclusion.

Readers familiar with CAN and CAN FD may skip @sec:can-classic, @sec:can-fd-background, and @sec:can-protocol-overview.

Source files, testbenches, verification plan, and tooling accompanying this document are listed in @sec:appendix-artifacts.

\clearpage

# Introduction {#sec:introduction}

Industrial control systems for large marine engines demand communication protocols that combine fault tolerance, multi-master arbitration, and multi-decade service reliability. The Controller Area Network (CAN) meets these demands, but as control system data requirements grow the bandwidth and payload limits of CAN Classic have become a bottleneck.

## Motivation {#sec:motivation}

Everllence (formerly MAN Energy Solutions) is a provider of propulsion and decarbonization solutions for the marine and energy industries, designing large two-stroke and four-stroke combustion engines for ship propulsion and power generation. This thesis was written within the engine controller division, where FPGA-based control hardware is developed and maintained for integration into Everllence's engine platforms.

CAN, developed in the 1980s for automotive and industrial control, provides the fault-confinement properties that suit the reliability requirements of engine control applications [@bosch1991]. Everllence's existing CAN infrastructure is built around a CAN Classic protocol controller deployed on an IO-extender board forming part of the Triton motor controller system. As control systems grow more data-intensive, the eight-byte payload and 1 Mbit/s ceiling of CAN Classic has become a practical constraint. CAN FD (Flexible Data Rate) extends the maximum payload to 64 bytes and raises the data-phase bit rate beyond 8 Mbit/s while preserving the CAN Classic arbitration and fault-confinement architecture [@hartwich2012]. Thus, CAN FD is the natural migration path for Everllence's existing CAN infrastructure .

## Existing CAN Controller {#sec:existing-controller}

The starting point for this project is an existing CAN Classic controller developed internally at Everllence. The controller is implemented in VHDL and has been integrated into a production IO-extender FPGA design. It supports CAN Classic frames with both 11-bit (base) and 29-bit (extended) identifiers at bit rates up to 500 kbit/s, and has been verified through hardware bring-up on physical CAN buses. The initial version was developed by the author of the present document during an internship at Everllence and has since been extensively modified by other engineers at the company.

The top-level wrapper for the module instantiates a combined TX/RX frame FSM, a bit timing generator, a dynamic bit stuffer, a CRC-15 engine, and two Avalon-ST converters for frame serialization and deserialization.

The central component is the orchestrating FSM that handles both transmission and reception in a single process. It manages frame arbitration, bit-level TX and RX, stuff-bit error checking, CRC validation, ACK handling, and error flag generation. Fault confinement (error active, error passive, bus off node state transition) is handled in a separate process within the main FSM entity.

### Limitations {#sec:existing-limitations}

While the existing controller is functional for CAN Classic, several areas of the existing design would require significant rework to support CAN FD.

**Single bit rate domain.** CAN FD requires switching between a nominal bit rate (used during the arbitration phase) and a faster data bit rate (used during the data phase), with Transmitter Delay Compensation (TDC) to account for the transceiver loop delay at the higher rate (@sec:bit-timing). Adding dual bit rate support and TDC would require a fundamental redesign of the timing architecture.

**Dynamic bit stuffing only.** The bit stuffer implements the CAN Classic rule of inserting an inverse bit after five consecutive identical bits. CAN FD introduces a second stuffing mode - fixed bit stuffing - where a stuff bit is inserted at fixed intervals during the CRC field, and a Stuff Bit Count (SBC) field with Gray-coded parity is appended (@sec:bit-stuffing). The existing stuffer has no mechanism for mode switching or SBC generation.

**Single CRC engine.** The controller has a single CRC engine. CAN FD requires three polynomials - CRC-15 for Classic frames, CRC-17 for FD frames with payloads up to 16 bytes, and CRC-21 for larger payloads (@sec:crc-overview). A compliant receiver must run all three engines in parallel, since the correct polynomial depends on DLC and is not known until the control field is decoded. The data feed also differs between Classic and FD frames, requiring separate accumulation paths.

**Coupled fault confinement.** Error counting (TEC/REC) and node state transitions are implemented in the same source file as the frame FSM, with no clean sub-layer boundary between them (@sec:error-model). ISO 11898-1 defines fault confinement as a distinct cross-cutting entity, and separating it as an independently testable module both conforms closer to the standard's reference model (@sec:can-layered-model) and simplifies verification.

**Format-dependent frame structure.** CAN Classic and CAN FD frames diverge in the control and data phases, where FD introduces format-specific fields with no Classic equivalent (@sec:frame-types). The existing FSM has no clean mechanism to handle this divergence across four frame variants.

### Decision to Redesign {#sec:decision-to-redesign}

The rework required across bit timing, bit stuffing, CRC, and frame format complexity is large enough to justify a clean-slate redesign structured around the ISO 11898-1 layered architecture (LLC, MAC, PCS, FCE, @sec:can-layered-model) with independently testable subcomponents, rather than retrofitting FD support onto a design not originally built with those boundaries.

## Existing CAN FD IP Cores {#sec:existing-ip-cores}

Before committing to an in-house redesign, the available CAN FD controller IP cores were evaluated. @tbl:canfd-ip-survey summarizes the candidates, spanning both open-source and commercial offerings.

### Open-Source Implementations {#sec:open-source-implementations}

**CTU CAN FD** [@ctucanfd] is the only mature open-source CAN FD controller available as synthesizable HDL. Developed at the Czech Technical University in Prague, it is written in VHDL, licensed under MIT, and has been conformance-tested against ISO 16845-1 [@iso16845_1]. The controller includes a full TX and RX pipeline with up to four TX buffers, acceptance filtering, timestamping, and a register interface with DMA support.

### Commercial Implementations {#sec:commercial-implementations}

**Bosch M\_CAN** [@bosch_mcan] is the reference CAN FD controller developed by Bosh. M\_CAN is the IP core embedded in most automotive micro controllers. It is licensed under a non-disclosure agreement with per-design royalty fees.

**AMD/Xilinx CAN FD** [@xilinx_canfd] is a soft IP core included in the Vivado Design Suite. It provides an AXI4-Lite register interface with up to 32 acceptance filters, TX mailboxes, and RX FIFOs. It is device-locked to AMD/Xilinx FPGAs and cannot be ported to other targets.

**Technology-independent RTL cores.** CAST CAN FD [@cast_canfd] is a technology-independent CAN FD IP core licensed per-design with an upfront fee. Major EDA vendors including Synopsys (DesignWare) and Cadence offer similar ASIC-targeted cores under commercial licensing programs.

| Implementation | Source | License | Scope | Conformance Tested |
|---|---|---|---|---|
| CTU CAN FD [@ctucanfd] | VHDL (MIT) | MIT | Full node | Yes |
| Bosch M\_CAN [@bosch_mcan] | Closed | Per-design royalty | Full node | Yes (reference) |
| AMD CAN FD [@xilinx_canfd] | Closed | Vivado-included | Full node | Yes |
| CAST CAN FD [@cast_canfd] | Closed | Per-design fee | Full node | Yes |

: Survey of available CAN FD controller IP cores. {#tbl:canfd-ip-survey}

### Rationale for In-House Development {#sec:rationale-in-house}

None of these solutions satisfies Everllence's combined requirements for safety-critical marine engine control. The disqualifying factors span IP ownership, verification authority, architectural scope, integration with existing infrastructure, and platform independence - each addressed in turn below.

**IP ownership and supply chain independence.** Everllence's engine controllers carry service commitments of up to thirty years. Commercial IP cores introduce a licensing dependency on an external vendor over that full horizon - vendors may discontinue support, change licensing terms, or be acquired. Owning the RTL outright eliminates this exposure and ensures that the design can be maintained, ported, and modified without third-party approval for the full product lifetime. The open-source CTU CAN FD avoids the licensing risk, but using it still means adopting a codebase whose architecture, naming conventions, and design decisions were made for a different context.

**Verification authority.** In safety-critical domains, the verification evidence must be traceable from standard requirements to RTL assertions and testbench results. Adopting a third-party core means inheriting its verification artifacts rather than producing them. Everllence's verification methodology requires full control over the verification plan, the testbench architecture, and the assertion coverage.

**Architectural scope.** All available IP cores implement a complete CAN node - TX and RX pipelines, message memory, acceptance filtering, buffer management, register interfaces, and in some cases DMA controllers. Everllence's application requires only the protocol engine - the module that converts between byte-level frame data and the serial bus - which is exactly the scope of the existing CAN Classic controller. The higher-level buffering and filtering logic already exists in Everllence's FPGA infrastructure. Adopting a full-node IP core would introduce unnecessary complexity and area overhead, and stripping the unused subsystems to fit the existing architecture offsets the benefit of using a pre-built core.

**Integration with existing infrastructure.** Everllence's FPGA designs use a specific Avalon-ST streaming interface for inter-module communication and established conventions for signal naming and module boundaries. A third-party core would require an adaptation layer to bridge its native interface to the existing infrastructure. The in-house design uses Everllence's interface conventions natively, eliminating this integration overhead.

**Platform independence.** The AMD/Xilinx CAN FD core is locked to Xilinx devices. The Bosch M\_CAN and other commercial cores are delivered as technology-specific netlists or encrypted HDL for a particular target. The in-house design is written in portable VHDL-93, synthesizable on any FPGA platform ensuring that the IP remains usable if Everllence changes FPGA vendors.

## Problem Statement {#sec:problem-statement}

The architectural limitations of the existing controller (@sec:existing-limitations) and the unsuitability of available third-party IP cores (@sec:rationale-in-house) together motivate a clean-slate CAN FD protocol controller conforming to ISO 11898-1. No existing solution combines full IP ownership, a targeted data-link-layer scope matching Everllence's integration requirements, and native compatibility with Everllence's Avalon-ST interface conventions and VHDL Code Standard. The design described in this report addresses that gap directly.

## Objectives {#sec:objectives}

1. Implement a CAN/CAN FD protocol controller in VHDL, compliant with ISO 11898-1 [@iso11898_1].
2. Establish a structured requirements framework with traceability from ISO 11898-1 to testbench evidence, covering all implemented modules.
3. Produce an RTL design integrated via Avalon-ST interfaces into Everllence's existing FPGA infrastructure.

# Background {#sec:background}

This section covers the CAN and CAN FD protocol at the level of motivation and architecture - the bus model, fault-confinement properties, and the bandwidth extensions introduced by CAN FD.

## CAN Classic {#sec:can-classic}

CAN is a serial communication bus developed by Bosch in 1986 [@bosch1991] to connect electronic control units in automotive environments without a central host computer. CAN uses a shared two-wire differential bus on which all nodes broadcast simultaneously and arbitrate access without any designated bus master. Any node may initiate a transmission at any time. Contention is resolved by a non-destructive bitwise arbitration in which the transmitter with the lower-priority identifier detects the collision and silently withdraws, leaving the winner's frame intact. The bus uses two conductors, CANH and CANL, whose voltage difference encodes the bit value, see @fig:can_bus. Twisting the conductors ensures that external electromagnetic interference couples equally onto both wires. Because the receiver measures only the differential voltage, this common-mode noise cancels - a practical necessity in the electrically harsh environment.

![Four CAN nodes connected to a shared twisted-wire bus via CANH and CANL conductors. Each node comprises an application process, a CAN controller, and a transceiver IC. The bus is terminated with 120Ω resistors at each end.](figures/can_bus.png){#fig:can_bus width=60%}

CAN's error-handling architecture is a distinguishing feature relative to simpler serial protocols. Five complementary error detection mechanisms operate concurrently on every transmitted frame: transmitter bit monitoring, frame format checking, cyclic redundancy checking, acknowledgment checking, and bit stuffing violation detection. The residual error probability - the probability that a corrupted frame passes all detection mechanisms undetected - for an eight-byte frame in a ten-node network is on the order of $10^{-9}$ per frame, several orders of magnitude lower than contemporary automotive bus alternatives such as VAN and SCP [@charzinski1994]. A fault confinement mechanism tracks each node's error history and automatically escalates from error active through error passive to bus off, electrically isolating a persistently faulty node from the bus without disrupting communication between healthy nodes. Together these properties made CAN the protocol of choice for safety-relevant in-vehicle networks.

## CAN FD {#sec:can-fd-background}

The fault-confinement and multi-master properties that distinguished CAN from its contemporaries were deliberately preserved in CAN FD. The CAN FD protocol extension was introduced by Bosch in 2012 and incorporated in ISO 11898-1 in 2015. The design goal was to extend payload and bit rate while leaving the arbitration and fault-confinement architecture unchanged [@hartwich2012].

CAN's original data payload was capped at eight bytes per frame, limiting raw throughput to around 1 Mbit/s. As embedded control applications became more data-intensive, this ceiling became a practical constraint. CAN FD extends the maximum payload to 64 bytes and introduces a separate higher-speed data phase with bit rates of 8 Mbit/s or beyond, while preserving the CAN Classic arbitration phase and the fault-confinement architecture unchanged.

At high data-phase bit rates the transceiver's TX-to-RX loop delay (approximately 100 ns for a typical CAN FD transceiver such as the TCAN1042 [@tcan1042]) may exceed one bit time. Since the fault confinement mechanism in CAN relies on transmitter nodes monitoring their own transmitted bits, this necessitates the Transmitter Delay Compensation (TDC) mechanism introduced in CAN FD, see @sec:bit-timing. For data-phase to arbitration-phase bit rate ratios below approximately 9, CAN FD accepts the same oscillator tolerance as CAN Classic [@mutter2013].

CAN FD also strengthens the error detection architecture. A CRC polynomial's Hamming distance guarantee holds only up to a certain frame length, making the CAN Classic CRC-15 insufficient for CAN FD's longer payloads. A 17-bit polynomial covers frames up to 16 data bytes and a 21-bit polynomial covers frames up to 64 bytes, both maintaining a Hamming distance of 6 - meaning any combination of five or fewer bit errors within a frame is guaranteed to be detected [@hartwich2012]. In CAN Classic, dynamic stuff bits are excluded from the CRC calculation, allowing errors that create or destroy stuff conditions to escape detection. CAN FD addresses this by including dynamic stuff bits in the CRC data feed and introducing the Stuff Bit Count (SBC) field as an independent check on the number of dynamic stuff bits. Together, these changes significantly reduce the residual error probability compared to CAN Classic [@mutter2015].

# Requirements {#sec:requirements-engineering}

This section establishes the constraints that bound the design before any architectural decisions are made. Everllence's coding standard, tooling, and existing FPGA infrastructure set the implementation framework, while the protocol requirements derived from ISO 11898-1 define the functional obligations of the controller.

## Code Standard, Tooling, and Design Constraints {#sec:engineering-constraints}

These constraints fall into three categories: the tools and language dictated by Everllence's synthesis and simulation environment, the integration requirements specific to this project, and the coding rules from Everllence's VHDL Code Standard.

### Tools and Language {#sec:vhdl-osvvm}

The RTL source is implemented in VHDL-93. Everllence's synthesis toolchain uses Quartus Prime [@quartus], which does not fully support VHDL-2008 constructs in synthesis, making VHDL-93 the practical upper bound for synthesizable RTL. Testbenches are written in VHDL-2008 to support the OSVVM verification framework [@osvvm], which requires VHDL-2008 language features. SystemVerilog with UVM is the dominant industry alternative for RTL implementation and verification at this scale. The choice here follows company convention rather than a project-level technical comparison. Riviera-PRO [@riviera_pro] is used for simulation. Sigasi [@sigasi] is used for linting and language-aware editing. Waveform figures are captured in GTKWave [@gtkwave], timing diagrams are drawn in WaveDrom [@wavedrom], and architecture diagrams in Mermaid [@mermaid].

Claude Code [@claudecode] was used for prose editing and VHDL review. Technical content, design decisions, and all source files are the author's own work.

### Integration Requirements

1. **Avalon-ST user interface:** The CAN controller's external interface to the host system must use the Avalon-ST streaming protocol [@avalon_st] (data, valid, ready, sop, eop). The requirement applies specifically to the boundary between the CAN controller and its user.
2. **IP library CRC block:** Everllence maintains a reusable, parameterised CRC generator (`gen_crc`) in its IP library. This module must be used for all CRC computations.

### VHDL Code Standard

1. **Entity port types:** Entity ports are restricted to `std_logic`, `std_logic_vector`, and records or arrays of these types. Modes are restricted to `in` and `out`.
2. **Naming conventions:** A mandatory prefix/suffix scheme applies to all VHDL identifiers: types (`t_`), constants (`c_`), generics (`gc_`), processes (`p_`), functions (`f_`), packages (`pk_`), state variables (`s_`), entity inputs (`_i`), and entity outputs (`_o`).
3. **RTL design rules:** Synchronous processes must be sensitive to the clock only. Reset must be synchronous and initialize all control registers. FSMs are preferably implemented as single-process designs where all signal assignments are derived from the current state.
4. **Testbench requirements:** Testbenches must follow a black-box testing model and test cases must be ordered as: reset tests first, then a normal-usage test, then all remaining tests.

## From Specification to Structured Requirements {#sec:req-extraction}

The requirements engineering process addressed two key objectives [@bergeron2003ch3]:

1. Extracting a clear and actionable set of requirements that could serve as a starting point for the design phase.
2. Establishing a clear, traceable link between the ISO 11898-1 specification and the verification environment.

Both objectives are complicated by the source material: normative requirements are distributed across subsections, often restated from different perspectives, and interspersed with explanatory text. The standard compounds this by bundling multiple obligations into single clauses, interspersing normative `shall` statements with informative rationale prose, and repeating equivalent obligations from both transmitter and receiver perspectives.

The AI-augmented pipeline shown in @fig:ver_plan_pipeline was designed to address these extraction challenges systematically. The first step was converting the ISO 11898-1 PDF to Markdown - a format that can be efficiently searched and ingested by LLMs. The resulting Markdown file was then fed to a Claude Sonnet 4.6 LLM agent, which was prompted to extract all normative statements - sentences containing words like "shall", "should", "must", and their corresponding negations.

![Pipeline generating the `verification_plan.toml` artifact from the ISO 11898-1 standard.](figures/ver_plan_pipeline.png){#fig:ver_plan_pipeline width=100%}

This process yielded a raw set of 168 normative statements linked to the ISO standard sections from which they were extracted. The normative set was then manually reviewed, consolidated, and distilled into a final set of 37 requirements (reproduced in @sec:appendix-vplan).

The requirements set is stored as a TOML file, one entry per requirement. Direct LLM editing of large structured files is unreliable - prone to silent entry deletion, field hallucination, and syntax corruption. To make iterative AI-assisted refinement of the plan viable, a custom Model Context Protocol (MCP) server was developed alongside it. The server exposes query, insert, update, and delete operations, together with bulk update and statistics utilities, as structured tool calls. Each write operation targets a single requirement entry and validates field values against the schema before committing. This bounds any model error to one requirement and prevents malformed data from reaching the file. Each requirement entry contains the following fields:

- **`source_clause`**: Links every requirement back to the ISO 11898-1 clause from which it was distilled, enabling the requirements set to be audited against the standard.
- **`original_wording`**: Verbatim ISO text for the relevant clauses. Preserving the source wording prevents paraphrase drift and provides a fallback for resolving ambiguity during implementation.
- **`paraphrase`**: A concise, implementer-facing restatement of the requirement. Where the ISO prose bundles multiple obligations into a single clause, the paraphrase enumerates them as numbered sub-claims, each independently verifiable.
- **`priority`**: A three-level rating - P1 (need-to-have, derived from "shall" obligations and core correctness), P2 (verified in the normal cycle), or P3 (optional, derived from "should" clauses or implementation-dependent features). The priority drove the implementation sequence and scope decisions when the schedule was constrained.
- **`notes`**: Any residual clarifications not captured by the paraphrase - implementation constraints, out-of-scope markers, or known ambiguities. May be empty.

Of the 37 requirements, 30 are rated P1, four are P2, and three are P3. Each non-P1 rating reflects a deliberate scoping decision - the rationale for each is given in @tbl:priority-demotion.

| ID | Topic | Priority | Demotion rationale |
| :- | :---- | :- | :------------------------------------------------------------------------- |
| REQ-002 | LLC TX request and abort timing | P2 | The 2-SOF processing window is a responsiveness guarantee, not a correctness constraint. A node that transmits eventually but outside this window sends valid frames. |
| REQ-011 | Remote frame | P2 | A data-only node is a valid CAN implementation. Remote frame support is a distinct feature subset not required for basic interoperability. |
| REQ-015 | ESI bit transmission | P2 | ESI communicates the node's error state as an informational signal. Incorrect ESI does not abort a frame or trigger a protocol error at any receiver. |
| REQ-035 | Error signaling enable | P2 | Error signaling itself is covered by P1 requirements. This requirement concerns only the existence of a configurable disable mode, which is an optional operational feature. |
| REQ-004 | Frame acceptance filtering | P3 | ISO uses advisory "should" language. Also, acceptance filtering is absent from the existing controller, so no regression concerns. The only protocol-relevant filter - suppressing loopback of transmitted frames - is covered by the design. |
| REQ-034 | Shared memory consistency | P3 | The "may" language makes shared memory use optional. This implementation streams frames directly from LLC to MAC with no shared memory; the LLC is responsible for buffering and retransmission. Not applicable to this architecture. |
| REQ-036 | DLC padding | P3 | Padding with 0xCC applies only when the implementation exposes a configurable maximum-data-byte restriction. The feature may be waived entirely if that restriction is not implemented. |

: Priority demotion rationale for all requirements not rated P1. {#tbl:priority-demotion}

## AI-Assisted Extraction: Utility and Limitations {#sec:ai-extraction}

The AI-assisted workflow delivered value in two distinct phases of the project, with very different characteristics in each.

In the extraction phase, the LLM agent earned its keep by bootstrapping and linking the initial normative statement set. Having a fully populated and linked starting point - even one requiring substantial revision - gave the manual review process a concrete artifact to work from. The time saving from the extraction itself was, however, marginal. The agent's output had to be reviewed statement by statement, which is functionally similar to extracting requirements manually in the first place. The primary benefit of the AI-assisted approach in this phase was therefore not efficiency, but rather the increased consistency of an automated pass over the full standard text.

The distillation step that followed - consolidating 168 raw normative statements into 37 prioritized, independently verifiable requirements - required substantial manual effort that the AI could not replace. Deciding which statements address the same underlying obligation, how to bound each requirement so that it is independently verifiable, and how to assign priority in a way that is defensible against the standard text are judgment calls that depend on understanding the protocol at an implementation level. REQ-026 illustrates the challenge well - the corresponding extracted normative statements are:

1. *"Only one synchronization within one bit time (between two sample points) shall be allowed. After an edge is detected, synchronizations shall be disabled until the next time the bus state detected at the sample point is recessive."*
2. *"An edge shall cause synchronization only if the bus state detected at the previous sample point was recessive. If a transmitter uses transmitter delay compensation, also the first detected edge from recessive to dominant after the sample point of the CRC delimiter shall cause synchronization. An edge with a positive phase error shall not cause synchronization in a node sending a dominant bit."*
3. *"Hard synchronization shall be performed: on edges during inter-frame space (with the exception of the first bit of intermission); when a node is in bus-integration state; at the edge between the FDF bit and the following dominant res bit inside an FD frame; when a node is a receiver of an XL frame, at the edge between the XLF bit and the following dominant resXL bit; at the edge between the DH1 and DH2 bits and the DL1 bit; at the edge between the DAH or AH1 bit and the AL1 bit."*
4. *"All other recessive-to-dominant edges fulfilling rules a) and b) shall be used for resynchronization with one exception: a node transmitting an FD frame or an XL frame shall not synchronize while it transmits the data phase of that frame."*
5. *"After a hard synchronization, the bit time shall be restarted with Sync_Seg completed. Hard synchronization shall not be limited by the synchronization jump width."*
6. *"When the magnitude of the phase error is less than or equal to the synchronization jump width, the effect of a resynchronization shall be the same as a hard synchronization."*
7. *"When the magnitude of the phase error is larger than the synchronization jump width: if positive, Phase_Seg1 shall be lengthened by the synchronization jump width; if negative, Phase_Seg2 shall be shortened by the synchronization jump width."*

Statements 3 and 4 each embed CAN XL elements within otherwise in-scope obligations, which must be excluded without dropping the surrounding CB, CE, FB, and FE rules. The remaining statements interleave hard sync and resync rules across four sub-clauses, requiring the two mechanisms to be separated and their interaction made explicit. The resulting paraphrase is presented below, with the remaining requirement fields in @tbl:req026-example.

**Paraphrase:**

1. Phase error: the time interval between a recessive-to-dominant edge and the Sync_Seg boundary of the current bit time. Positive when the edge falls after Sync_Seg (late), negative when before (early).
2. SJW (Synchronization Jump Width): the maximum amount by which Phase_Seg1 or Phase_Seg2 may be adjusted per resynchronization.
3. One synchronization per bit time, re-enabled after the next recessive sample point.
4. An edge qualifies only if the previous sample point was recessive and no positive phase error exists while sending dominant. The first recessive-to-dominant edge after the CRC delimiter also qualifies when TDC is active.
5. Hard synchronization: IFS edges (except the first intermission bit), bus-integration state, and the FDF-to-res transition. Bit time restarts with Sync_Seg completed, unconstrained by SJW.
6. All other qualifying edges cause resynchronization, except for the FD data-phase transmitter. Positive error: Phase_Seg1 += SJW. Negative error: Phase_Seg2 -= SJW. Error ≤ SJW: same effect as hard synchronization.

| Field | Value |
| :--- | :----------------------------------------------- |
| ID | REQ-026 |
| Source | §7.3.5.1, §7.3.5.2, §7.3.5.3, §7.3.5.4, Figure 33 |
| Priority | P1 |
| Notes | RTL is stricter than ISO: `mac_i.transmitting` suppresses all sync unconditionally, not just resync on positive phase error. Safe since the transmitter is the timing source. |

: REQ-026 distilled from seven extracted normative statements. {#tbl:req026-example}

The MCP server interface proved genuinely useful throughout the design, implementation, and verification phases that followed extraction. As implementation decisions were made, requirements were refined - paraphrases sharpened, notes extended, observability classifications updated, and traceability fields populated. All updates were applied using the AI agent through dedicated schema-validated MCP tool calls, each targeting an individual requirement field. The narrow, validated interface made incremental AI-assisted maintenance of the verification plan safe and practical across all three project phases.

# CAN and CAN FD Protocol Overview {#sec:can-protocol-overview}

The 37 requirements distilled in @sec:requirements-engineering define what must be implemented and verified - but they also function as a structured map to the protocol, since every requirement points to a mechanism that must be understood before implementation can begin. Those mechanisms - the sub-layer model, frame formats, bit timing, stuffing, CRC, and error handling - are covered here, each cross-referenced to the relevant REQ-NNN entries. Readers familiar with ISO 11898-1 may skip to @sec:verification-plan.

## Layered Reference Model {#sec:can-layered-model}

![ISO 11898-1 CAN node reference model showing the LLC, MAC, PCS sub-layers and cross-cutting FCE.](figures/can_node.png){#fig:can-node width=100%}

ISO 11898-1 structures the CAN node reference model into three functional sub-layers - LLC and MAC in the data link layer, PCS in the physical layer - and a cross-cutting Fault Confinement Entity (FCE) [@iso11898_1, Fig. 4] (see @fig:can-node):

- **LLC (Logical Link Control)**: acceptance filtering, overload notification, and recovery management - retransmission on error or lost arbitration, and supplying frames to the MAC.
- **MAC (Medium Access Control)**: encodes and decodes the frame bit-by-bit, performing bit stuffing and destuffing, CRC generation and checking, error detection and signalling, acknowledgment handling, and medium access arbitration.
- **PCS (Physical Coding Sublayer)**: bit timing and bus sampling, clock synchronization, and the TX/RX interface to the physical transceiver.
- **FCE (Fault Confinement Entity)**: escalating the node's error state from error active through error passive to bus off as error counts accumulate.

## Frame Types and Formats {#sec:frame-types}

CAN defines two classes of frames: CAN Classic (CC) and CAN FD (FD). Within each class, frames may carry either an 11-bit base identifier or a 29-bit extended identifier, giving four frame formats: CB (Classic Base), CE (Classic Extended), FB (FD Base), and FE (FD Extended), as shown in @fig:can-frame-structure and specified in REQ-037. Classic frames (CB and CE) additionally support remote frame variants, giving six bus frame types in total.

![CAN frame formats (CB, CE, FB, FE) and the error and overload flags, with field widths annotated per ISO 11898-1. The bus waveform below each format indicates the level of fixed-polarity protocol bits. Hatched regions indicate variable-content fields.](figures/frame_format.png){#fig:can-frame-structure height=90%}

A CAN Classic frame opens with a dominant SOF bit that triggers hard synchronization (@sec:bit-timing) in all receiving nodes, followed by the arbitration, control, data, and CRC fields, an ACK slot, and a seven-bit EOF delimiter. The RTR bit is dominant for data frames and recessive for remote frames. The IDE bit distinguishes base frames (dominant, 11-bit ID) from extended frames (recessive, 29-bit ID). Fixed-polarity form bits (SRR, r0, r1) carry no protocol instruction. The DLC encodes the number of data bytes in the payload (REQ-031). The ACK slot carries a dominant bit driven by every receiver that has validated the CRC. Each frame is followed by the interframe space - intermission (INT), suspend transmission (ST, error passive transmitters only), and bus idle (REQ-008).

A CAN FD frame shares the same arbitration phase structure, with the FDF bit signalling the FD format when recessive. The FD control field contains a reserved form bit (res) alongside BRS and ESI. The DLC retains its 4-bit width but uses a non-linear mapping above 8 bytes, extending the maximum payload to 64 bytes (REQ-031). The BRS (Bit Rate Switch) bit controls the transition to the data-phase bit rate: when BRS is recessive the bus switches to the faster data rate immediately after the BRS sample point and returns to the nominal rate at the CRC delimiter (REQ-030). The ESI (Error State Indicator) bit reflects the transmitting node's fault-confinement state: a node in error passive state shall transmit ESI recessive (REQ-015). The FD CRC field is additionally prefixed by a Stuff Bit Count (SBC) - a Gray-coded count of dynamic stuff bits with a parity bit (REQ-016).

## Bit Timing {#sec:bit-timing}

![CAN bit time segments (SS, PS, PS1, PS2) and Sample Point (SP). The two-node layout illustrates the round-trip propagation delay (t_TRX + t_bus each way) that PS must cover for correct arbitration.](figures/bit_timing.png){#fig:can-bit-timing width=70%}

Every CAN bit period is divided into four non-overlapping time segments measured in Time Quanta (TQ), where one TQ equals the system clock period multiplied by a programmable integer prescaler, see @fig:can-bit-timing. CAN FD extends CAN Classic with an independently configured data-phase bit rate. A CAN FD node therefore maintains two independent sets of segment parameters, one for the nominal rate and one for the data rate (REQ-024):

- **Sync Segment (SS)**: one TQ. The segment at which a recessive-to-dominant edge is expected when the node is synchronized.
- **Propagation Segment (PS)**: guarantees that a bit driven by any node reaches all others before the sample point, enabling correct arbitration. PS shall be programmed to at least twice the one-way propagation delay: 2 × (t_TRX + t_bus), see @fig:can-bit-timing.
- **Phase Segment 1 (PS1)**: immediately precedes the sample point. Can be lengthened by the resynchronization mechanism to absorb positive phase errors.
- **Phase Segment 2 (PS2)**: follows the sample point to the end of the bit. Can be shortened to absorb negative phase errors.

The **sample point** falls at the PS1 / PS2 boundary. Every receiver samples the bus exactly once per bit at this point. The sample point position - expressed as a percentage of the total bit time - is a configuration parameter traded off against bus length, node count, and oscillator tolerance.

### Synchronization {#sec:bit-sync}

In a synchronized receiving node, edges arrive within SS. An edge outside SS carries Phase Error (PE) and triggers synchronization to realign the sample point at the PS1/PS2 boundary. During the frame, resynchronization on each qualifying recessive-to-dominant edge adjusts the bit time based on the PE relative to SS: a positive PE lengthens PS1 by up to the Synchronization Jump Width (SJW), and a negative PE shortens PS2 by up to SJW. Hard synchronization, triggered by the SOF dominant edge and the FDF-to-res dominant edge, restarts the bit time with SS completed. Only one synchronization is permitted per bit time (REQ-026). @fig:can-sync illustrates how two consecutive mid-frame synchronization events align an unsynchronized receiving node to the transmitter on the bus.

![Resynchronization over two successive sync edges. PE is the phase error relative to SS. SJW is the Synchronization Jump Width.](figures/sync.png){#fig:can-sync width=100%}


### Transmitter Delay Compensation {#sec:tdc}

When the FD data phase begins, the transceiver loopback delay may span multiple data-phase bit times, necessitating a delay before sampling to compensate for in-flight bits (REQ-025). TDC measures this delay in the nominal-rate control field: from when the res bit goes dominant on TX to when the edge arrives on RX. The Secondary Sample Point (SSP) is then placed at the measured delay plus a programmable offset, firing before the SP in each bit time so that errors can be reacted upon at the SP. For the initial bits where the loopback has not yet returned, the SSP is suppressed. From the first valid SSP onward, SSP monitoring replaces SP monitoring for the remainder of the data phase, see @fig:can-tdc.

![Transmitter Delay Compensation. Top: the first data-phase bits have no valid SSP while the loopback is still in transit. Once the loopback returns, the SSP is placed at the measured transceiver delay plus a programmable offset, firing before the SP in each bit time. Bottom: the transceiver delay is measured from when the res bit goes dominant on TX to when the edge arrives on RX.](figures/tdc.png){#fig:can-tdc width=100%}


## Bit Stuffing {#sec:bit-stuffing}

Bit stuffing ensures sufficient transitions on the bus for receiver clock synchronization. CAN Classic applies dynamic stuffing from SOF through the CRC field: after five consecutive bits of the same polarity, the transmitter inserts one complement Stuff Bit (SB) and the receiver discards it (REQ-018). CAN FD retains dynamic stuffing through the arbitration and data fields, then switches to fixed stuffing in the CRC field. Fixed Stuff Bits (FSB) are inserted before the SBC field and after every fourth CRC bit, regardless of the preceding bit pattern. FSBs are accompanied by a Gray-coded Stuff Bit Count (SBC) field that allows receivers to verify the number of dynamic stuff bits seen in the frame (REQ-016, @fig:can-bit-stuffing).

![Dynamic and fixed bit-stuffing examples showing stuff bit placement for both encoding modes. The waveform below each row shows the resulting bus signal.](figures/bit_stuffing.png){#fig:can-bit-stuffing width=100%}

## Cyclic Redundancy Check {#sec:crc-overview}

The CRC polynomial and field length depend on frame type and data payload length (REQ-006):

- **CRC-15**: used for all CAN Classic frames. The CRC accumulates over SOF, arbitration, control, and data fields with SBs excluded (REQ-013).
- **CRC-17**: used for FD frames with data payloads up to 16 bytes (DLC 0-10).
- **CRC-21**: used for FD frames with data payloads from 20 to 64 bytes (DLC 11-15).

The key asymmetry between CC and FD concerns the CRC data feed. For FD frames, dynamic stuff bits up to and including the data field are included in the CRC computation, along with the SBC field itself. Fixed stuff bits are excluded from the CRC computation in both CC and FD frames (REQ-013). The CRC field is terminated by a recessive CRC delimiter bit (REQ-017).

## Error Detection and Fault Confinement {#sec:error-model}

Every CAN node monitors the bus for five categories of error (REQ-021):

- **Bit error**: a transmitter reads back a polarity different from what it drove. Exceptions: a recessive non-stuff bit overridden during arbitration and a recessive bit in the ACK slot.
- **Stuff error**: six consecutive bits of the same polarity where the stuffing rule prohibits it.
- **CRC error**: received checksum does not match the locally recomputed value.
- **Form error**: a fixed-format field contains an illegal bit value.
- **Acknowledgment error**: a transmitter receives no dominant ACK bit from any receiver (REQ-014).

Detection of any error causes the detecting node to transmit an error flag, aborting the frame (REQ-022). An error active node transmits an active error flag of six consecutive dominant bits. An error passive node transmits a passive error flag of six consecutive recessive bits instead (REQ-007). Both are followed by an eight-bit recessive error delimiter.

The FCE tracks each node's error history through the Transmit Error Counter (TEC) and Receive Error Counter (REC). Counter increments and decrements follow the rules defined in REQ-028. A node begins in error active, transitions to error passive when either counter exceeds 127, and to bus off when TEC exceeds 255 (REQ-029). An error-passive transmitter is exempt from the TEC increment on an ACK error, preventing an isolated node from escalating to bus-off through failed acknowledgments alone. In bus off the node ceases all bus activity and shall not influence the bus (REQ-027) until 128 sequences of 11 consecutive recessive bits are observed, after which TEC and REC are reset and the node returns to error active. A host-initiated supervisory reset also returns the FCE to its initial state immediately (REQ-029). Whether error signaling is enabled at all is a run-time configuration parameter (REQ-035).

# Verification Plan {#sec:verification-plan}

The verification plan adds five classification dimensions to each of the 37 requirements, driving both the module architecture and the testbench design. The plan was populated using MCP introduced in @sec:requirements-engineering. The five classification dimensions fall into two groups. Design-facing dimensions inform the module architecture. Verification-facing dimensions inform the verification strategy and testbench design. Each field is summarized in the bullets below and described in detail in the following sections.

- **Design-facing**: `layer`, `side`, and `format_applicability` - determining module ownership, TX/RX path decomposition, and which frame formats each requirement applies to.
- **Verification-facing**: `observability` and `verification_method` - determining whether internal state is required and specifying the verification technique.

## Layer {#sec:vplan-layer}

The `layer` field assigns each requirement to the protocol sub-layer that owns it (LLC, MAC, PCS, or FCE), determining which module testbench must exercise it. A fifth label - `system` - classifies requirements that are inherently multi-layer or multi-node in nature. The `system` label flags requirements that need either an integrated multi-module testbench or a multi-node simulation environment. REQ-020 (arbitration loss) illustrates both: verifying arbitration requires a full node - MAC, PCS, and FCE cooperating - to drive and monitor the bus, and a second node simultaneously driving dominant while the DUT drives recessive. It is covered in the multi-node `can_mac_pcs_fce_tb.vhd`.

## Side {#sec:vplan-side}

The `side` field records whether a requirement pertains to the transmitter path, the receiver path, or both - reflecting the ISO standard's own framing, which frequently specifies transmitter and receiver obligations separately. It determines whether a testbench drives the DUT in transmitter mode, receiver mode, or both roles in succession within a single test scenario. REQ-025 (TDC) illustrates a TX-only classification: measuring the bus loop delay and positioning the SSP is a transmitter concern. Receivers sample at the nominal SP and have no delay compensation obligation, so `side=transmitter` confines the testbench to TX-mode stimulus.

## Format Applicability {#sec:vplan-format}

The `format_applicability` field records which of the in-scope frame formats (CB, CE, FB, FE) each requirement applies to. Because the formats differ in stuffing mode, CRC polynomial, and control field structure (@sec:can-protocol-overview), a requirement that applies only to FD frames implies stimulus with FDF=1 and DLC values covering both sides of the CRC-17/CRC-21 boundary, while one that applies to all four formats requires a configuration for each. REQ-015 (ESI bit generation) is a good example: it applies only to FB and FE frames, since the ESI field does not exist in CC frames and CB and CE stimulus configurations are therefore meaningless for this requirement.

## Observability {#sec:vplan-observability}

The `observability` field classifies each requirement as either black-box or white-box, relative to the module boundary of the owning layer:

- **Black-box**: Can be verified purely through the module's observable port signals.
- **White-box**: Verification requires direct observation of the module's internal state.

This classification drives the testbench architecture. Black-box requirements can be verified by driving the module inputs and checking the output signals. White-box requirements require a parallel reference model or direct observation of internal signals. REQ-006 (CRC polynomial selection) is representative: the polynomial in use - CRC_15, CRC_17, or CRC_21 - is configured inside `can_mac_crc` and never exposed at the module boundary. Verification uses a reference model that independently computes the expected CRC for each format and DLC combination and compares it against the transmitted sequence.

## Verification Method {#sec:vplan-method}

The `verification_method` field specifies how each requirement will be checked. Four methods are used:

- **`simulation`**: Assertion procedures in a testbench.
- **`code_inspection`**: RTL source review.
- **`waveform_inspection`**: Manual review of simulation output.
- **`coverage`**: A functional coverage bin confirming a specific condition was exercised.

Combinations are valid when multiple sub-claims within one requirement each call for a different method. REQ-018 (bit stuffing) illustrates this: `simulation` assertions verify that stuff bits are inserted and removed at the correct positions, while `coverage` bins confirm that the edge case of five consecutive identical bits landing at a field boundary was exercised at least once.

## Traceability: Label and File {#sec:vplan-traceability}

The `label` and `file` fields establish a direct, navigable link from each requirement to its verification artifact. `file` identifies the testbench or RTL source file responsible for covering the requirement. `label` identifies a specific named procedure, assertion, or coverage ID within that file.

## Status {#sec:vplan-status}

The `status` field (`not_started`, `in_progress`, `complete`) records requirement closure state explicitly, allowing partial progress to be tracked.

## Verification Plan Summary {#sec:vplan-summary}

@tbl:vplan-distribution shows the 37 requirements distributed across layer, side, format scope, and observability. MAC carries 20 of the 37, with 16 white-box, reflecting the breadth of frame-encoding logic that requires bit-level state access to verify. FCE is the opposite: both requirements are black-box, since fault-confinement state transitions are fully observable through the node's error-state output signals. The complete verification plan is reproduced in @sec:appendix-vplan as two separate tables linked by common IDs.

| Layer | Requirements | n | TX | RX | Both | FS | BB | WB |
| :---- | :----------- | -: | -: | -: | ---: | -: | -: | -: |
| MAC | REQ-006, REQ-008, REQ-010–013, REQ-015–019, REQ-021–023, REQ-030–032, REQ-034–035, REQ-037 | 20 | 3 | 0 | 17 | 5 | 4 | 16 |
| LLC | REQ-001–005, REQ-036 | 6 | 3 | 1 | 2 | 0 | 3 | 3 |
| PCS | REQ-024–027 | 4 | 1 | 0 | 3 | 1 | 1 | 3 |
| FCE | REQ-028–029 | 2 | 0 | 0 | 2 | 0 | 2 | 0 |
| System | REQ-007, REQ-009, REQ-014, REQ-020, REQ-033 | 5 | 1 | 0 | 4 | 0 | 2 | 3 |
| **Total** | | **37** | **8** | **1** | **28** | **6** | **12** | **25** |

: Requirement distribution by layer, side, format scope, and observability. n = total. FS = format-specific (not applicable to all four frame formats). BB = black-box. WB = white-box. {#tbl:vplan-distribution}

# Design and Architecture {#sec:design-architecture}

The design maps each ISO 11898-1 sub-layer to a dedicated module: `can_llc`, `can_mac`, `can_pcs`, and `can_fce`. `can_mac` is the top-level MAC sub-layer wrapper, containing the submodules `can_mac_fsm`, `can_mac_ser`, `can_mac_bs`, and `can_mac_crc`. The key architectural decisions that shaped this decomposition are described in the sections below.

## System Overview {#sec:system-overview}

@fig:can-node-architecture shows the complete module decomposition. The primary data path runs from `can_llc` through `can_mac` to `can_pcs`. The LLC receives frames from the host over an Avalon-ST interface and streams them byte-by-byte to the MAC serializer. The MAC FSM drives the serialized bit stream to the PCS, which applies bit timing and produces the sample-point and SSP strobes that the MAC uses to read and write the bus. `can_fce` sits outside the primary data path, receiving error and success events from the MAC and feeding node-state signals (error active, bus off) back to both the MAC and PCS. The PCS additionally pulses `can_fce` with idle conditions to drive bus-off recovery. A centralized types package (`pk_can_types`) defines all protocol constants, interface records, and reset values shared across modules.

![Implementation module decomposition showing the five entities and their inter-module connections.](figures/mac_overview.png){#fig:can-node-architecture height=45%}

## Adopting the ISO 11898-1 Sub-layer Model {#sec:monolithic-vs-layered}

Mapping each ISO 11898-1 sub-layer to a dedicated module is the natural decomposition. Module boundaries align directly with verification targets, each requirement points unambiguously to the responsible implementation unit, and each module can be exercised in isolation without driving frame-level stimulus through unrelated sub-layers.

## Combined vs. Separated TX/RX Paths {#sec:combined-vs-separated-fsm}

The `side` dimension classifies each requirement as TX-only, RX-only, or both - making separate TX and RX paths appear natural, since each could be verified independently. A split-path implementation was attempted first.

In practice, the split duplicated both code and hardware: each path required its own `can_mac_bs` and `can_mac_crc` instance, putting two of each on the device where one suffices. In addition, developing the two paths sequentially, shared protocol logic tended to diverge between implementations with no protocol justification. Debugging doubled the investigation surface - two independent FSMs, two sets of waveforms per bug.

The split path was replaced by a single `can_mac_fsm` with shared `can_mac_bs` and `can_mac_crc` instances, as shown in @fig:can-node-architecture. Shared protocol logic exists once, implementation drift is prevented, and debugging involves a single FSM and a single set of waveforms.

## Per-Field FSM Granularity {#sec:per-field-vs-per-phase}

The `format_applicability` dimension expresses requirements at the level of individual protocol fields. REQ-037 defines the complete MAC frame field sequence and fixed-polarity bits for all in-scope formats. With one FSM state per protocol field, the FSM naturally progresses through that structure: format-dependent transitions - such as the divergence between CC and FD at the FDF field - become state graph edges rather than counter conditionals inside a shared state, and each requirement maps directly to a named FSM state.

## LLC Frame Format {#sec:llc-frame-format}

The LLC layer defines two frame formats: a host-facing format that maintains compatibility with `can_bus_controller`, and a MAC-facing format designed to efficiently facilitate frame streaming.

### Host-LLC Interface Format {#sec:host-llc-frame-format}

The host-LLC format shown in @fig:llc-frame extends the `can_bus_controller` LLC frame format, expanding the data field from 8 to 64 bytes and adding FDF, BRS, and ESI to the existing trailing control bytes alongside IDE and RTR. The field layout and byte positions are otherwise unchanged, so host software requires no change to the fields it already uses.

![LLC frame format (71 bytes) at the host-LLC interface, with identifier byte mapping for base and extended IDs. Hatched regions indicate variable-value bits.](figures/llc_frame.png){#fig:llc-frame width=100%}

### LLC-MAC Interface Format {#sec:internal-llc-frame-format}

The host-LLC format places all control flags after the payload, requiring a full 71-byte frame buffer before serialization can begin. The LLC-MAC format (@fig:llc-frame-int) avoids this by packing all metadata into two leading config bytes: `can_mac_ser` receives these first, then streams the ID and data bytes immediately.

![Internal LLC frame format at the `can_mac_ser` input, with identifier byte mapping for base and extended IDs. Hatched regions indicate variable-value bits.](figures/llc_frame_int.png){#fig:llc-frame-int width=100%}

# Implementation {#sec:implementation}

All inter-module interfaces use typed records (e.g., `t_can_mac_pcs_if_m2s`, `t_can_mac_fsm_bs_if_s2m`), each paired with a reset constant (e.g., `c_can_mac_pcs_if_m2s_reset`) so every module can be reset without enumerating individual fields. Port direction follows `m2s`/`s2m` (master-to-slave/slave-to-master) for control interfaces and `s2d`/`d2s` (source-to-destination/destination-to-source) for Avalon-ST data interfaces. `pk_can_types` is the single shared package all modules depend on. It defines every interface record type, protocol constant, frame format byte layout, and utility function used across the design. `can_llc` was not implemented within the project schedule. Its interface contracts are fully specified in the verification plan (REQ-001 through REQ-005, REQ-031, REQ-034, REQ-036), and the implementation path is described in @sec:future-work.

## Module Overview {#sec:impl-module-overview}

`can_mac_pcs_fce` is the synthesis and integration boundary. It instantiates `can_mac`, `can_pcs`, and `can_fce`. `can_mac` in turn instantiates `can_mac_fsm`, `can_mac_ser`, `can_mac_bs`, and `can_mac_crc`, with `can_mac_fsm` being the central orchestrating FSM in the MAC layer.

## `can_mac_fsm` {#sec:impl-can-mac-fsm}

`can_mac_fsm` accumulates received frames into a 70-byte internal byte array (`llc_frame`), reusing `can_bus_controller`'s register-array approach as a proof-of-concept baseline. The resource overhead is negligible at 15 bytes but becomes the dominant logic element cost at 70 bytes (@sec:synthesis-resources). A block RAM migration is the identified upgrade path (@sec:future-work). Bus-off state is owned entirely by `can_fce`. `can_mac_fsm` treats `fce_i.bus_off` as a secondary reset alongside the hardware reset, suppressing all bus activity. The complete signal-level interface is reproduced in @sec:appendix-mac-arch.

### FSM Structure and Mode Flag

`can_mac_fsm` contains two synchronous processes (`p_fsm` and `p_stream_to_LLC`) and one `t_fsm_state` enum covering 19 states. An `is_transmitter` flag, latched when the FSM drives the SOF dominant bit at the start of a new frame transmission and cleared at arbitration loss (REQ-020) or at the end of the EOF field, partitions per-state logic into a TX branch and an RX branch. The error-frame states (`s_error_flag`, `s_error_delimiter`) are an exception: both transmitter and receiver errors enter the same two-state sequence, with flag polarity driven by `fce_i.error_active` (REQ-007, REQ-022).

`p_fsm` organizes each sample-point cycle as three phases:

- **Pre-case**: handles all conditions that preempt normal state progression - lost arbitration (REQ-020), bit errors (REQ-021), and ACK errors (REQ-014) on the TX branch, and stuff errors (REQ-018), form errors (REQ-021), overload conditions (REQ-023), and deferred SBC/CRC mismatch detection (REQ-016, REQ-021) on the RX branch. When any of these fire, `v_skip_case` is set and the case block is bypassed entirely.
- **Case**: handles only the error-free state transitions - `bit_count` advancing and state changing according to the protocol field sequence.
- **Post-case**: feeds the BS and CRC engines at the sample point and commits the drive polarity to the PCS output.

The structure trades per-state locality for non-duplication of cross-cutting logic. Placing stuff-bit handling inside each state would duplicate identical detection and feed logic across the seven dynamic-stuffing states (`s_arbitration` through `s_data`). Centralizing it in the pre-case handles it once, and `v_skip_case` provides a single auditable guarantee that the state machine does not advance when it should not. For logic that is genuinely per-state - DLC parsing, ACK success latching, EOF completion - the case block handles it directly. The locality cost is reasonable since the exception logic is cross-cutting.

`p_fsm` implements the per-field state granularity introduced in @sec:per-field-vs-per-phase. Each post-arbitration field has a dedicated state, with the arbitration region sharing `s_arbitration` across ID bits, RTR/SRR/RRS, and IDE via `bit_count`. The complete FSM is shown in @fig:mac-fsm.

![`can_mac_fsm` controlling TX and RX for all in-scope frame formats. In each state, TX indicate transmitter behavior and RX indicates receiver behavior.](figures/mac_fsm.png){#fig:mac-fsm height=90%}

### TX Mode: Frame Transmission

When `is_transmitter = true`, the FSM writes `pcs_o.tx_data` two clock cycles after each sample point, giving the BS and CRC engines time to present valid outputs. `bs_i.valid` must be stable before the TX branch decides whether a stuff bit is due (REQ-018), and `crc_i.crc` must hold the fully accumulated value before the first CRC bit is driven (REQ-006). The PCS latches `pcs_o.tx_data` at the bit boundary - the MAC simply needs valid data ready in time.

The FSM samples the bus at each sample point to detect bit errors (REQ-021), ACK (REQ-014), and arbitration loss (REQ-020). In the CAN FD data phase, the SSP strobe replaces the SP for bit-error monitoring (REQ-025). The MAC compares `pcs_i.rx_data` against `transmitted_bits_shift_reg(tdc_delay)` - where `tdc_delay` is supplied alongside the SSP strobe by the PCS - to check the bit that was transmitted `tdc_delay` bit times earlier. Arbitration loss clears `is_transmitter` in `s_arbitration` and the node continues as an receiver.

During `s_arbitration` multiple nodes may be transmitting, so both TX and RX feed `pcs_i.rx_data` into the CRC and BS engines - the bus is the only authoritative source (REQ-013, REQ-020). A transmitter that loses arbitration therefore needs no handoff: its accumulators already match a pure receiver's. From `s_fdf_r1_r0` onward the transmitter switches to `transmitted_bits_shift_reg(tdc_delay)`, enabling TDC in the data-phase.

### RX Mode: Frame Reception

When `is_transmitter = false`, the FSM observes `pcs_i.rx_data` at each sample point and stores received bits directly into the `llc_frame` byte array. The FSM drives the BS engine from `pcs_i.rx_data` to perform destuffing (REQ-018), and the CRC engine accumulates the received bit stream in parallel (REQ-013). The FSM validates the SBC field (FD frames, REQ-016), compares the received CRC against the locally accumulated result (REQ-006), and checks form bits (reserved bits, CRC delimiter, ACK delimiter, EOF) for required polarities (REQ-021). A mismatch in any of these fields triggers a transition to the error-frame sequence (REQ-022). During the ACK slot the FSM drives dominant for one bit (`bit_count = 0`) regardless of frame format (REQ-014). The FD ACK slot spans two bits but the receiver asserts dominant only during the first (REQ-014).

During `s_intermission`, the completed frame is streamed byte-by-byte to the LLC RX sink over the Avalon-ST interface by `p_stream_to_LLC`, a dedicated process running concurrently with `p_fsm`.

## `can_mac_ser` {#sec:impl-can-mac-ser}

`can_mac_ser` converts the LLC byte stream into a serial bit stream for the MAC FSM. Its four-state FSM manages the two-byte configuration handshake, byte fetching, and bit-by-bit serialization. The serializer extracts LLC metadata (IDE, FDF, DLC, FTYP, BRS, ESI) from the two config bytes and registers it in `t_llc_metadata`, which remains stable for the entire frame. The serializer forwards `transfer_status` from `can_mac_fsm` back to the LLC, returning to `s_load_config_byte_0` on any non-ongoing status so that errors and aborts terminate serialization immediately. The four-state serializer FSM is shown in @fig:mac-ser-fsm-tx.

The 32-bit ID field in the internal format is left-aligned: a base identifier (11 bits) occupies bits [31:21], leaving 21 unused padding bits at the LSB end. An extended identifier (29 bits) occupies bits [31:3], leaving 3 unused padding bits. The serializer tracks this with two counters initialized in `s_load_config_byte_1` from the `ide` flag: `id_bits_remaining` counts real ID bits still to be presented, and `padding_bits_remaining` counts trailing unused bits to be skipped. In `s_shift_out_bits`, padding bits are advanced without asserting `valid`, so the MAC FSM never observes them. 

![`can_mac_ser` FSM (four states) serializing the internal LLC frame to the MAC bit stream. Unused padding bits in the 32-bit ID field are skipped silently.](figures/mac_ser_fsm.png){#fig:mac-ser-fsm-tx width=100%}

## `can_mac_bs` {#sec:impl-can-mac-bs}

`can_mac_bs` implements both dynamic and fixed bit stuffing for CC and FD frames (REQ-018). The entity is instantiated inside `can_mac` and serves both TX stuffing and RX destuffing via the same logic: `can_mac_fsm` drives the `can_mac_bs` interface, and the stuffer's output is either inserted into the TX bit stream or used by `can_mac_fsm` to discard SBs and FSBs from the received stream.

In dynamic mode (`fixed_bit_stuffing_en` = '0'), the stuffer counts consecutive bits of identical polarity and emits an inverse-polarity SB after every five. A counter is incremented on each dynamic SB. Its value is Gray-coded and parity bit is added, generating the `stuff_bit_count` output. This value is read by `can_mac_fsm` when transmitting the SBC field (REQ-016).

In fixed mode (`fixed_bit_stuffing_en` = '1'), used for the FD CRC region, a FSB is emitted immediately on the rising edge of `fixed_bit_stuffing_en`, then one FSB every four real bits. If a dynamic SB is already pending when `fixed_bit_stuffing_en` rises, the initial FSB emission is skipped - preventing double stuffing.

![`can_mac_bs` bit stuffing logic.](figures/mac_bs_fsm.png){#fig:mac-bs-dataflow width=100%}

## `can_mac_crc` {#sec:impl-can-mac-crc}

`can_mac_crc` runs three parallel `gen_crc` instances on separate data feeds and selects the result with an output multiplexer, as shown in @fig:mac-crc: `data_cc` drives CRC-15 via `valid_cc`, while `data_fd` drives both CRC-17 and CRC-21 via `valid_fd`. The multiplexer selects the active engine's result based on `crc_poly_select` and left-aligns it to the common 21-bit output width: CRC-15 occupies bits [20:6], CRC-17 occupies bits [20:4], and CRC-21 occupies the full width. Transmitter nodes set `crc_poly_select` from the DLC field in `llc_metadata` before the first frame bit is driven. Receiving nodes set `crc_poly_select` after the DLC field has been received.

The output mux is kept combinatorial - each `gen_crc` instance registers its outputs, so the mux already selects over registered values, keeping IPT at 2 system clocks. A registered mux would require 3 system clocks, violating REQ-024 (IPT ≤ 2 t_q) at minimum prescaler (m=1, t_q = 1 system clock).

![`can_mac_crc` dataflow with three parallel CRC engines. The output mux is combinatorial to satisfy the ISO IPT ≤ 2 t_q constraint at minimum prescaler.](figures/mac_crc_fsm.png){#fig:mac-crc width=70%}

## `can_fce` {#sec:impl-can-fce}

`can_fce` implements the error state and counter management specified in REQ-029. It maintains TEC and REC and transitions between three states: `s_error_active`, `s_error_passive` (TEC or REC > 127), and `s_bus_off` (TEC > 255), as shown in @fig:fce-fsm.

Counter updates follow REQ-028. Bus-off recovery requires 128 separate `pcs_i.idle_condition` pulses, after which both counters reset to zero and the FSM returns to `s_error_active`. `llc_i.normal_mode` resets both counters and returns the FSM to `s_error_active` from any state (REQ-029).

`can_mac_fsm` asserts `mac_i.passive_tx_ack_error_exempt_1` when it detects an ACK error while the node is error passive and transmitting, signaling `can_fce` to suppress the TEC increment in accordance with REQ-028.

![`can_fce` FSM governing the error active, error passive, and bus off node states.](figures/fce_fsm.png){#fig:fce-fsm width=100%}

## `can_pcs` {#sec:impl-can-pcs}

`can_pcs` implements bit timing as a 4-state FSM and a concurrent TDC pipeline (REQ-026, REQ-027), see @fig:can-pcs. The FSM advances through `s_sync_seg` (1 TQ, fixed), `s_prop_seg`, `s_phase_seg1`, and `s_phase_seg2` as each segment's TQ count expires. The SP strobe and `rx_data` latch fire at the end of `s_phase_seg1`. The TX bit is driven at the end of `s_phase_seg2`. TDC measurement runs at TQ granularity above the segment case statement. When `fce_i.bus_off` is asserted, consecutive recessive bits are counted and `fce_o.idle_condition` is pulsed every 11 bits - enabling FCE bus-off recovery (REQ-029).

![`can_pcs` bit-time FSM with concurrent resynchronization and TDC pipelines per ISO 11898-1 sec. 7.2-7.4.](figures/pcs_fsm.png){#fig:can-pcs height=90%}

### Synchronization {#sec:impl-can-pcs-resync}

- **Hard synchronization**: Controlled by `can_mac_fsm` via `do_hard_sync`, which restarts the bit time at the sync segment boundary. Used at SOF and at the FDF-to-res transition.
- **Resynchronization**: The `sync_applied` flag enforces one sync per bit time. `rx_bus_prev` gates sync to recessive → dominant edges. The `transmitting` signal from `can_mac_fsm` suppresses sync during TX. Phase_Seg1 or Phase_Seg2 is adjusted by up to SJW. Phase errors not exceeding SJW produce the same result as a hard synchronization.

### Dual Bit Rate Switching {#sec:impl-can-pcs-dual-rate}

`can_pcs` holds no frame-format knowledge. Rate switching is entirely driven by `can_mac_fsm` through three dedicated control signals.

- `next_bit_is_brs`: At the BRS sample point, `can_pcs` reads BRS polarity and, if recessive, replaces the active segment lengths and SJW with their data-phase counterparts.
- `next_bit_is_res`: Arms TDC measurement at the FD res bit boundary.
- `data_phase_stop`: Asserted by the `can_mac_fsm` at the CRC delimiter SP or on error-frame entry. Restores nominal timing and clears all TDC state.

### Transmitter Delay Compensation {#sec:impl-can-pcs-tdc}

TDC is implemented as a three-stage pipeline:

1. **Measure**: From the FD res bit boundary, `delay_count_tq` increments each TQ until the TX-to-RX dominant edge arrives on RX.
2. **Count down**: At the first data-phase bit boundary, the measured delay is counted down each TQ until zero, setting `ssp_active`.
3. **Fire**: With `ssp_active` set, the SSP fires one TQ before the SP on every data-phase bit time. `can_mac_fsm` uses `tdc_delay` to index into the transmitted-bit shift register for bit error detection.

# Verification and Results {#sec:verification-results}

The implementation described in @sec:implementation was exercised against the 37-requirement verification plan (@sec:verification-plan) using five unit testbenches and one integration testbench, `can_mac_pcs_fce_tb`. @fig:tb-overview shows the integration testbench architecture.

![`can_mac_pcs_fce_tb` integration testbench. Two `can_mac_pcs_fce` instances connect through a dominant-wins bus model. Avalon-ST VCs drive and sample the MAC interfaces. `p_test_ctrl` sequences test stimuli, injects bit errors, reads transfer status, and monitors bus-off status.](figures/tb_overview.png){#fig:tb-overview width=100%}

## Code Inspection {#sec:code-inspection}

REQ-013 (CRC data feed differs by format: CC excludes stuff bits, FD includes dynamic stuff bits and the SBC field) is verified by code inspection against `can_mac_fsm.vhd` - the FSM controls which frame fields are gated into the CRC engines, and the per-field feed logic is directly readable from the state transitions. REQ-023 (overload frame conditions) requires triggering an overload frame by injecting a dominant bit at specific field boundaries (last EOF bit, first two intermission bits, last error/overload delimiter bit), which requires a frame-aware bit injector not present in the current testbench.

Code inspection also provides evidence for sub-claims in several requirements covered in @sec:integration-testbench:

- **Error detection paths not exercised by simulation**: REQ-021 sub-claims 2-5 (stuff, form, CRC, and ACK error detection) and REQ-022 sub-claims 2-3 (data-phase error rate switching and CRC error receiver behavior) are verified by code inspection only - frame-aware error injection is not available in the current testbench.
- **Receiver acceptance of non-standard bit values**: REQ-012 sub-claims 1-2 (receiver acceptance of dominant SRR and RRS bits without form error) and REQ-017 sub-claim 1 (two-bit CRC delimiter tolerance) are confirmed by inspecting the form-error logic in `can_mac_fsm.vhd`.
- **Conditions not covered by current testbench stimulus**: REQ-026 sub-claim 3 (one synchronization per bit time, enforced by `sync_applied`) and REQ-010 sub-claim 2 (third-intermission-bit skip-SOF transition) are confirmed by reading the guard conditions in `can_mac_fsm.vhd` and `can_pcs.vhd`.

## Unit Testbench Simulation {#sec:unit-testbenches}

The five unit testbenches target individual submodules with focused stimulus.

1. **`can_mac_crc_tb`**: closes REQ-006 via three coverage bins (CRC-15 for CB/CE, CRC-17 for FD ≤16 bytes, CRC-21 for FD >16 bytes). `f_calc_can_crc` computes expected CRC per polynomial and checks DUT output on every frame. Additional checkers verify init vector reset and output stability between frames.
2. **`can_mac_bs_tb`**: closes REQ-016 and REQ-018 via a two-phase stimulus: six directed FSB tests followed by random dynamic bits. Three concurrent reference models verify DUT output: `p_stuff_bit_checker` verifies a complement bit after every five same-polarity bits, `p_sbc_checker` verifies Gray-code parity and increments on dynamic stuff bits and holds on FSBs, and `p_fsb_checker` verifies initial and periodic FSB polarity. All coverage bins are hit.
3. **`can_pcs_tb`**: provides simulation evidence for REQ-024, REQ-025, REQ-026 (combined with code inspection), and REQ-027. Two `can_pcs` instances run on mismatched clocks through a physical bus model. Three tests cover reset, random FD frames with alternating clock leadership, and bus-off isolation. `p_check_tdc_delay` verifies at each SSP that `polarity_history(tdc_delay)` matches the sampled bus value. `p_rx_mac_vc` compares RX-sampled bits against the TX sequence bit by bit.
4. **`can_fce_tb`**: closes REQ-028, REQ-029, and REQ-033 (sub-claim 2) using directed stimulus only - counter rules are deterministic. Reset confirms outputs clear and `llc_i.normal_mode` restores error-active from any state. All REQ-028 counter rules are exercised at the error-active/error-passive boundary. REQ-033 sub-claim 2 confirms no bus-off entry when `passive_tx_ack_error_exempt_1` is set while error-passive. REQ-029 boundary check: 64 `idle_condition` strobes confirm no premature release, 128 confirm clearance and error-active restoration.
5. **`can_mac_ser_tb`**: closes REQ-031 (DLC encoding: linear for DLC 0-8, FD non-linear for DLC 9-15) and provides supporting evidence for higher-level requirements. Three coverage dimensions drive frame selection: IDE (base/extended), FDF (CC/FD), and DLC (0-15). `p_mac_fsm_vc` verifies all metadata fields against the LLC frame and compares the output bit stream byte by byte, accounting for ID width, padding, and DLC-derived data length. Random back pressure and a 2% mid-frame abort rate exercise pipeline stalls and the `c_disturbed` path. `p_transfer_status_checker` monitors `transfer_status` every cycle.

## Integration Testbench Simulation {#sec:integration-testbench}

`can_mac_pcs_fce_tb` is the primary integration testbench, exercising two `can_mac_pcs_fce` instances connected through a dominant-wins bus model and covering 17 requirements spanning MAC frame encoding, arbitration, and error handling. The following waveforms are selected excerpts from the test run. Many requirements are verified by waveform inspection across all test scenarios. Reproducing a dedicated figure for each requirement would be impractical, so only representative scenarios are shown.

- **Complete FD Frame Transmission** (@fig:full_fd_frame): a complete FD frame transmitted by DUT 1 and received by DUT 2, showing hard synchronization on SOF, TDC loopback delay measurement, dual bit rate switching at the BRS sample point, SSP pulses during the data phase, and ACK confirmation (REQ-010, REQ-012, REQ-014, REQ-015, REQ-017, REQ-026).
- **Bit Stuffing** (@fig:bs): dynamic and fixed mode behavior (REQ-016, REQ-018).
- **Bit Rate Switching and TDC** (@fig:pcs): the PCS switches to data-phase bit timing at the BRS sample point and positions the SSP once the transceiver loopback delay is measured (REQ-025, REQ-030).
- **Arbitration** (@fig:arb): the losing node clears `is_transmitter` in-place at `s_arbitration` and continues as receiver without a state transition (REQ-020).
- **Error Handling and Bus-off Recovery** (@fig:error_frame, @fig:bus_off_recovery): error frame escalation and bus-off recovery (REQ-007, REQ-008, REQ-009, REQ-021, REQ-022, REQ-028, REQ-029, REQ-033 sub-claim 1).

![Two-node simulation of a complete FD frame transmission in `can_mac_pcs_fce_tb`. DUT 2 hard-synchronizes on SOF at A. DUT 1 measures the TDC loopback delay between B and C. Both nodes switch to data-phase bit timing at the BRS sample point at D. DUT 1 switches back to nominal bit timing at the CRC delimiter sample point at E. DUT 2 drives the ACK slot dominant at F, DUT 1 samples the dominant ACK at G and latches `ack_success_seen`. Transmission ends at H.](figures/waveforms/full_fd_frame.pdf){#fig:full_fd_frame width=100%}

![Dynamic and fixed bit stuffing in `can_mac_pcs_fce_tb`. Dynamic stuff bits are inserted at A, B, and C in the `s_data` region. At D, `fixed_bit_stuffing_en` asserts and the stuffer switches to fixed mode for `s_sbc` and `s_crc`. Seven fixed stuff bits are inserted between D and E.](figures/waveforms/bs.pdf){#fig:bs width=100%}

![Dual bit rate switching and TDC measurement in `can_mac_pcs_fce_tb`. At A, the PCS begins counting the transceiver loopback delay in TQ increments. At B, the transmitted bit arrives on RX and the count stops at 19 TQ. At C, the first data-phase bit (ESI) is transmitted and the measured delay is counted down. When the countdown terminates at D, the SSP strobe activates and the TDC delay of 2 TQ is reported to the MAC. `next_bit_is_res` and `next_bit_is_brs` mark the measurement window boundaries. `data_phase_stop` signals the end of the data phase.](figures/waveforms/pcs.pdf){#fig:pcs width=100%}

![Arbitration loss in `can_mac_pcs_fce_tb`. Both nodes enter `s_arbitration` as transmitters at A. DUT 1 loses arbitration at B after transmitting recessive and sampling dominant, and continues as receiver with `is_transmitter` cleared.](figures/waveforms/arb.pdf){#fig:arb width=100%}

![Error frame escalation in `can_mac_pcs_fce_tb`. A bit error on the SOF bit triggers the first error flag at A, incrementing TEC to 8. Each dominant bit of the error flag is sampled as a bit error because the bus is held recessive, rapidly escalating TEC. At B, TEC reaches 128 and `fce_state` transitions to `s_error_passive`. At C, the node enters `s_suspend_transmission` after `s_intermission`.](figures/waveforms/error_flag.pdf){#fig:error_frame width=100%}

![Bus-off recovery in `can_mac_pcs_fce_tb`. DUT 1 transmits the first active error flag at A. At B, TEC reaches 128 and the node transitions to error passive. At C, TEC reaches 256 and the node enters bus off. The FCE counts 128 idle condition strobes from the PCS and restores `s_error_active` at D. At E and F, DUT 2 acknowledges the first two frames transmitted after recovery.](figures/waveforms/bus_off.pdf){#fig:bus_off_recovery width=100%}

## Testbench Results Summary {#sec:testbench-results-summary}

Of the 37 requirements, 28 are closed: 26 via testbench simulation (@tbl:testbench-results-summary) and two (REQ-013, REQ-023) via code inspection (@sec:code-inspection). Nine remain open: six are LLC requirements (REQ-001 through REQ-005, REQ-036) deferred pending `can_llc` implementation, REQ-034 (P3) and REQ-035 (P2) are non-blocking, and REQ-021 (P1) is partially covered - bit-error detection is verified in `test_bus_off`, while the remaining sub-claims (stuff, form, CRC, ACK) require frame-aware error injection not available in the current testbench (@sec:future-work).

| Testbench | Requirements covered | Status |
| :--- | :--- | :--- |
| `can_mac_crc_tb` | REQ-006 | Pass |
| `can_mac_bs_tb` | REQ-016, REQ-018 | Pass |
| `can_pcs_tb` | REQ-024, REQ-025, REQ-026, REQ-027 | Pass |
| `can_fce_tb` | REQ-028, REQ-029, REQ-033 (sub-claim 2) | Pass |
| `can_mac_ser_tb` | REQ-031 | Pass |
| `can_mac_pcs_fce_tb` | REQ-007, REQ-008, REQ-009, REQ-010, REQ-011, REQ-012, REQ-014, REQ-015, REQ-017, REQ-019, REQ-020, REQ-021 (bit error only), REQ-022, REQ-030, REQ-031, REQ-032, REQ-033 (sub-claim 1) | Pass |

: Testbench execution status and requirements coverage. {#tbl:testbench-results-summary}

# Synthesis {#sec:synthesis}

The implemented `can_mac_pcs_fce` stack was synthesized targeting the Cyclone 10 LP device used in Everllence's IO-extender board. The clock constraint was set to 6 ns (166 MHz), deliberately overconstraining relative to any realistic CAN FD system clock to expose worst-case timing paths.

## Resource Utilization {#sec:synthesis-resources}

The synthesized design (`can_mac_pcs_fce`) uses 4,608 Logic Elements (LE) (30% of the target device) and 869 dedicated registers. @tbl:synthesis-resources shows the per-module resource breakdown.

| Module | LEs | Registers | 
| :--- | ---: | ---: | :--- |
| `can_mac_fsm` | 4,109 | 684 |
| `can_pcs` | 190 | 49 |
| `can_fce` | 117 | 31 |
| `can_mac_crc` | 84 | 53 |
| `can_mac_ser` | 84 | 40 |
| `can_mac_bs` | 31 | 12 |
| **CAN FD total** (`can_mac_pcs_fce`) | **4,608** | **869** | |
| **CAN Classic** (`can_bus_controller`) | **1,146** | **334** | Existing controller, see @sec:existing-controller |

: Resource utilization on Cyclone 10 LP: `can_mac_pcs_fce` breakdown and `can_bus_controller` baseline. {#tbl:synthesis-resources}

`can_mac_fsm` dominates at 89% of total LEs, driven primarily by the RX frame buffer. `can_mac_fsm` accumulates received frames into a 70-byte (560-bit) internal byte array, and each buffer register drives combinatorial decode and mux logic. The five remaining modules together consume 506 LEs, modest overhead relative to the frame buffer.

## Timing Results {#sec:synthesis-timing}

Timing analysis covers four PVT corners: slow/fast transistor speeds, 1150 mV supply voltage, and -40°C to 100°C temperature range. @tbl:synthesis-timing shows the setup and hold slack at the overconstraining 166 MHz clock.

| Corner | Worst setup slack | fmax estimate | Hold slack |
| :--- | ---: | ---: | ---: |
| Slow 1150 mV 100°C | −1.858 ns | ~127 MHz | +0.236 ns |
| Slow 1150 mV −40°C | −1.550 ns | ~152 MHz | +0.021 ns |
| Fast 1150 mV 100°C | +0.230 ns | >166 MHz | +0.163 ns |
| Fast 1150 mV −40°C | +0.580 ns | >166 MHz | +0.145 ns |

: Timing results for `can_mac_pcs_fce` at 6 ns (166 MHz) on Cyclone 10 LP. Slow/Fast denotes process transistor speed. {#tbl:synthesis-timing}

The worst-case fmax is approximately 127 MHz on the slow 100°C corner. The negative setup slack on slow corners indicates timing violations at the 166 MHz constraint - a consequence of the deliberate overconstrain. Practical CAN FD implementations use system clocks of 20, 40, or 80 MHz [@mutter2013]. The 127 MHz fmax exceeds the highest of these by more than 1.5×, meeting timing on all corners at any realistic operating frequency. Hold slack is positive across all corners.

# Discussion {#sec:discussion}

The three design-facing verification plan dimensions - `layer`, `side`, and `format_applicability` - shaped the implementation in ways that were not uniformly constructive. `layer` and `format_applicability` motivated sound choices directly: the layered decomposition mapped each requirement to a testable module, and per-field FSM granularity with front-loaded config bytes followed naturally from format applicability analysis. The `side` dimension was a red herring: it made a split TX/RX architecture look well-motivated, but frame structure is the same regardless of which node is driving. Verification plan dimensions are inputs to testbench architecture - which stimulus configurations to exercise - not to RTL decomposition.

The unified FSM paid off most concretely at the arbitration loss boundary: `is_transmitter` clears in-place in `s_arbitration` and the shared CRC accumulator and bit stuffer carry over without any handoff. The split-path design required explicit state synchronization at exactly that point, and failed there first (@sec:combined-vs-separated-fsm). A fix to `can_mac_bs` or `can_mac_crc` propagated to both TX and RX paths automatically. Frame buffer continuity is a further payoff: the `llc_frame` byte array is already being populated from `pcs_i.rx_data` during the arbitration region, so when `is_transmitter` clears on arbitration loss, reception continues into the same buffer with no data to move. A split design would need an explicit transfer mechanism to move partially-accumulated frame data from the TX entity to the RX entity mid-frame.

The layered architecture made white-box requirements tractable. `can_fce_tb` exercised all counter-update rules in isolation. `can_mac_bs_tb` exhaustively covered stuffing mode transitions by driving the stuffer interface directly. `can_mac_pcs_fce_tb` then covered the multi-module scenarios - arbitration loss, error escalation, TDC - that cannot be observed at a single module boundary.

The AI-assisted extraction pipeline introduced a subtle bias that had direct architectural consequences. Classifying each requirement along the `side` dimension produced a requirements table organized along the TX/RX axis - a faithful representation of the ISO standard, which does frame many obligations in transmitter and receiver terms. But the artifact's structure became an implicit architectural suggestion: a table split along TX/RX lines made a split TX/RX RTL implementation look like the natural realization of the requirements model. The AI did not recommend a split architecture - it simply organized the requirements in a way that made the split appear structurally motivated. The split-path attempt was not the result of bad engineering judgment. It followed a coherent but misleading signal from the requirements artifact. This points to a broader risk in AI-assisted engineering workflows: the structure of an extracted artifact encodes implicit suggestions about downstream decisions, and those suggestions are not labeled as such. Validating the artifact's structure - not just its content - against protocol reality is a step the AI-assisted process does not perform automatically.

The 28/37 requirement closure rate warrants careful interpretation. The nine open requirements fall into three categories with different implications for production confidence. Six are LLC requirements deferred pending `can_llc` implementation - a known scope boundary, not a gap in the implemented protocol engine. REQ-034 (P3) is not applicable: this implementation streams frames from LLC to MAC with no shared memory, so the shared memory consistency requirement does not apply. REQ-035 (P2) is an optional operational feature - a node that always signals errors is a fully correct CAN FD participant.

The synthesis results provide a third lens on the design. The CAN FD stack uses 4,608 logic elements on the Cyclone 10 LP target - 4.0× the 1,146 elements of the existing CAN Classic controller (@sec:existing-controller). This growth is dominated by frame buffer scaling: the RX frame buffer grew from 120 bits (15 bytes, CAN Classic) to 560 bits (70 bytes, CAN FD), a 4.7× increase, driving the combinatorial decode and mux logic that represents the bulk of `can_mac_fsm`'s 4,109 LEs. Excluding the estimated buffer contribution, the protocol logic itself grew approximately 2.9× to deliver dual bit rate switching, TDC, three CRC polynomial variants, fixed bit stuffing with SBC, and full ISO 11898-1 fault confinement - a substantially larger feature set. Normalised for payload capacity, the FD design consumes 72 LEs per payload byte against 143 for CAN Classic, demonstrating better-than-linear scaling with respect to the 8× payload increase. The worst-case fmax of approximately 127 MHz on the slow corner exceeds the 40 MHz minimum required for a 5 Mbit/s data-phase clock at the ISO-minimum 8 TQ per bit by more than 3× (@sec:synthesis-timing). The register-based frame buffer is the straightforward RTL choice but not the efficient one. At 15 bytes (120 bits) in the CAN Classic controller the address decode and read mux overhead is modest - an acceptable side-effect of the implementation approach. At 70 bytes (560 bits) both overhead terms scale proportionally, making them the dominant cost rather than a side-effect: the write-address decoder (the LUT logic that routes a byte index to the correct flip-flop's load enable) and the read mux (the LUT tree that selects the correct byte from 70 parallel register outputs) both grow with buffer depth, and at 70 entries each is large enough to dominate the module's LE count. Mapping the 70-byte buffer to a single block RAM instance would eliminate both the storage flip-flops and the combinatorial decode logic they feed, reducing `can_mac_fsm`'s footprint substantially and leaving only protocol and control logic in the LUT fabric (@sec:future-work).

## Objectives Assessment {#sec:objectives-assessment}

The four objectives stated in @sec:objectives are assessed against the verification results.

**CAN/CAN FD protocol controller in VHDL compliant with ISO 11898-1, supporting CB, CE, FB, and FE frames.** The unified `can_mac_fsm` handles all four in-scope frame formats in both transmission and reception, including dual bit rate switching with Transmitter Delay Compensation in the FD data phase (REQ-024, REQ-025). 28 of 37 requirements are closed. The remaining nine are LLC-layer requirements deferred pending `can_llc` implementation, known non-blocking gaps, or requirements with partial simulation coverage, all documented in @sec:future-work.

**ISO 11898-1 sub-layer structure enabling independent module verification.** The layered decomposition was implemented as designed. Each module has a dedicated testbench and a disjoint requirement set. The five requirements labelled `system` correctly identified the scenarios requiring multi-module stimulus, confirming that the layer boundaries were drawn at the right points.

**Structured requirements with traceability from ISO 11898-1 to testbench results.** 37 requirements were derived from ISO 11898-1 normative clauses, each linked to its source section, verification method, testbench file, and assertion label. 28 are closed against passing testbenches or code inspection, establishing a direct traceable path from standard clause to verification artifact. The full plan is reproduced in @sec:appendix-vplan.

**RTL design integrated via Avalon-ST interfaces into Everllence's existing FPGA infrastructure.** The RTL source is written in portable VHDL-93 with no vendor primitives. Synthesis on a Cyclone 10 LP target confirmed timing closure at realistic system clock frequencies with 30% device utilization (@sec:synthesis). The Avalon-ST host interface is the responsibility of `can_llc`, which is not yet implemented. Its interface contracts are fully specified in the verification plan.

## Future Work {#sec:future-work}

1. **`can_llc` implementation.** The LLC sub-layer is the one unimplemented module. Its interface contracts are fully specified in REQ-001 through REQ-005 and REQ-036. Implementing it closes the Avalon-ST host interface and completes the full CAN node.

2. **Hardware integration and bring-up.** The implemented RTL has been verified in simulation only. Integration into Everllence's IO-extender FPGA design and bring-up on a physical CAN FD bus - including interoperability testing against a known-good CAN FD node - would validate timing closure, transceiver compatibility, and bit timing calibration under real bus conditions.

3. **CAN XL support.** CAN XL is explicitly out of scope for this project. The layered architecture and unified FSM are well-suited for extension: CAN XL adds a third bit rate phase and an XL-specific frame format, both of which map naturally onto additional PCS rate parameters and new `can_mac_fsm` states.

4. **Frame buffer block RAM migration.** The 70-byte RX frame buffer is implemented as a 560-bit flip-flop array, which is the primary driver of `can_mac_fsm`'s 4,109 LEs. A single M9K block RAM instance on the Cyclone 10 LP provides 9 Kbit of dedicated storage with negligible LUT overhead and is sufficient to hold the entire frame. The frame accumulation logic writes sequentially by byte index during reception, and `p_stream_to_LLC` reads sequentially during the post-EOF transfer - both access patterns map directly to single-port BRAM without any structural change to the surrounding FSM logic. This migration would reduce the LUT footprint to approximately the protocol-logic-only estimate, making the resource cost proportional to CAN FD's actual protocol complexity rather than its frame size.

5. **Error-type-specific simulation coverage (REQ-021).** The current testbench verifies bit-error detection through recessive injection at frame start. Sub-claims 2-5 (stuff, form, CRC, and ACK error detection) are covered by code inspection only. All four outstanding sub-claims require a frame-aware stimulus source. Stuff error must target a stuff bit, form error must target a fixed-format field, ACK error must target the ACK slot, and CRC error must target a non-fixed-form bit before the CRC field - an injection landing on a fixed-form bit would trigger a form error instead. Closing these sub-claims requires either the Everllence-internal CAN FD reference model with targeted error injection capability, or white-box FSM state signals exposed from `can_mac_fsm` to time the injection correctly.

# Conclusion {#sec:conclusion}

This thesis presented the design, implementation, and verification of a CAN/CAN FD protocol controller in VHDL-93, structured around the ISO 11898-1 layered reference model. The implemented design covers the MAC, PCS, and FCE sub-layers as independently testable modules, supports all four in-scope frame formats (CB, CE, FB, FE), implements dual bit rate switching with Transmitter Delay Compensation, and integrates into Everllence's existing FPGA infrastructure via Avalon-ST interfaces. Of the 37 requirements derived from ISO 11898-1, 28 are closed against passing testbenches or code inspection. Of the remaining nine, six fall outside the current scope pending `can_llc` integration, one is not applicable to this architecture (REQ-034, P3), one is an optional operational feature (REQ-035, P2), and one represents identified future work: REQ-021 (error-injection under passive error conditions). The design was synthesized on a Cyclone 10 LP FPGA target using 4,608 logic elements (30% of device) with a worst-case fmax of approximately 127 MHz, confirming timing closure at realistic system clock frequencies.

The project yielded three transferable lessons. First, the structure of a requirements model can inadvertently bias RTL architecture: the TX/RX side dimension of the verification plan made a split-path implementation appear well-motivated, but the frame structure of the CAN protocol is the same regardless of which node is driving, and cutting the natural code unit at an artificial seam added coordination complexity without reducing protocol complexity. Verification plan dimensions are inputs to testbench architecture, not to RTL decomposition. Second, the ISO 11898-1 layered architecture is not merely a documentary convenience - it is a practical partitioning of protocol complexity that, when followed in the implementation, enables each sub-layer to be implemented, verified, and debugged independently. The modular design produced here is maintainable over the long product lifecycles that motivate Everllence's decision to develop the protocol controller in-house. Third, targeted, schema-validated field updates to a structured artifact are safe for an LLM to perform incrementally. Full-file rewrites are not (@sec:ai-extraction). The narrow MCP write interface made AI-assisted maintenance of the verification plan safe and practical across all three project phases. The result is an IP core that Everllence owns outright - maintainable, verifiable, and extensible over the multi-decade service commitments that motivated the redesign.

```{=latex}
\clearpage
```

# References {#sec:references}

::: {#refs}
:::

```{=latex}
\clearpage
```

`\appendix`{=latex}

# Accompanying Digital Materials {#sec:appendix-artifacts}

The zip file accompanying this document contains the complete source tree developed during this project. The tables below identify the key files by category.

**RTL source files**

| File | Description |
| :----------------------------------------- | :--- |
| `src/can_types_p/hdl_src/can_types_p.vhd` | Shared types package |
| `src/can_mac/hdl_src/can_mac_fsm.vhd` | Unified MAC FSM |
| `src/can_mac/hdl_src/can_mac.vhd` | MAC wrapper |
| `src/can_mac_ser/hdl_src/can_mac_ser.vhd` | TX serializer |
| `src/can_mac_bs/hdl_src/can_mac_bs.vhd` | Bit stuffer/destuffer |
| `src/can_mac_crc/hdl_src/can_mac_crc.vhd` | CRC engine |
| `src/can_pcs/hdl_src/can_pcs.vhd` | PCS (bit timing, sync, TDC) |
| `src/can_fce/hdl_src/can_fce.vhd` | Fault Confinement Entity |
| `src/can_mac_pcs_fce/hdl_src/can_mac_pcs_fce.vhd` | Synthesized top-level wrapper |

**Testbench files**

| File | Description |
| :----------------------------------------- | :--- |
| `src/can_mac_ser/hdl_tb/can_mac_ser_tb.vhd` | Serializer |
| `src/can_mac_bs/hdl_tb/can_mac_bs_tb.vhd` | Bit stuffer |
| `src/can_mac_crc/hdl_tb/can_mac_crc_tb.vhd` | CRC engine |
| `src/can_pcs/hdl_tb/can_pcs_tb.vhd` | PCS |
| `src/can_fce/hdl_tb/can_fce_tb.vhd` | FCE |
| `src/can_mac_pcs_fce/hdl_tb/can_mac_pcs_fce_tb.vhd` | MAC + PCS + FCE integration |

**Verification plan and tooling**

| File | Description |
| :----------------------------------------- | :--- |
| `verification_plan/verification_plan.toml` | 37 requirements with traceability metadata |
| `mcp_tools/verification_plan_manager.py` | MCP server for verification plan maintenance |

# Complete CAN Node Signal Interface {#sec:appendix-mac-arch}

Complete signal-level connectivity of the implemented CAN node. The MAC sub-layer is expanded to show its four constituent entities (`can_mac_fsm`, `can_mac_bs`, `can_mac_ser`, `can_mac_crc`). PCS and FCE appear as external module boundaries. The LLC interface block represents the Avalon-ST boundary to the LLC sub-layer, which is not implemented in this project.

::: {.landscape-tables}

![Complete CAN node signal-level connectivity. The MAC sub-layer is expanded to show its four internal entities. The LLC interface block is the Avalon-ST boundary to the pending LLC implementation.](figures/mac_arch.png){#fig:mac-fsm-arch width=100%}

:::

# Verification Plan {#sec:appendix-vplan}

Both tables are regenerated automatically from `verification_plan/verification_plan.toml` on each PDF build. The ID field is the join key between them. See @sec:verification-plan-data-structure for the meaning of each field. The first table lists each requirement with its ISO source clause, priority, and paraphrase. The second table lists the verification metadata: layer, side, format applicability, observability, method, status, traceability label, file, and coverage criteria.

<!-- generated:requirements-table -->

<!-- generated:verification-plan-table -->
