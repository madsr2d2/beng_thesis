# Handoff: Defense Slides — Note Formatting Style

## Purpose

This document defines the speaker note formatting style established during the defense slide sessions. Any agent or session working on `defense/slides.tex` notes should follow this style exactly.

---

## Constraints

- Notes render on the right half of a pdfpc dual-screen view (`show notes on second screen=right`).
- The available height is roughly half a portrait A4 page at `\footnotesize`.
- **Notes must fit on a single pdfpc note page.** Overflow is silent — content is cut off, not reflowed. When in doubt, cut a bullet rather than shrink font.
- Font is already `\footnotesize` — do not go smaller.

---

## Format

Notes are verbatim speech in quotes with key terms bolded. One bullet per slide bullet. The purpose is to serve as a spoken delivery guide during the defense — not a compressed reference or Q&A prep sheet.

```latex
\note{\footnotesize\begin{itemize}\setlength{\itemsep}{5pt}
    \item ``Spoken sentence for first slide bullet, with \textbf{key terms} bolded.''
    \item ``Spoken sentence for second slide bullet, with \textbf{key terms} bolded.''
    \item ``Spoken sentence for third slide bullet, with \textbf{key terms} bolded.''
\end{itemize}}
```

Key parameters:
- Outer itemsep: `5pt`
- Speech in double quotes: ```` ``...'' ````
- Key terms bolded inline: `\textbf{term}`

---

## Rules

### 1. One bullet per slide bullet

The first bullet is always a **framing opener** — one sentence that orients the presenter before they start talking. It introduces the slide topic in spoken form, often as a rhetorical question or a "this slide covers..." statement. It does not correspond to any slide bullet.

Every subsequent bullet corresponds to one slide bullet. The note rephrases the slide content in natural spoken form and adds one piece of depth not visible on the slide — context, a number, a motivation, a consequence. It does not restate the slide verbatim.

Good: slide says "CAN Classic protocol", note says ``"The CAN controller currently runs as an \textbf{IP core on that FPGA}, operating at \textbf{500\,kbit/s} with a payload limit of \textbf{8 bytes per frame}."''

Bad: slide says "CAN Classic protocol", note says ``"The current CAN infrastructure builds on the CAN Classic protocol."''

### 2. Bold key terms inline

Bold the two or three terms per bullet the presenter must land clearly when speaking. These are the terms the examiner will latch onto. Do not bold whole phrases — just the noun or number that carries the meaning.

### 3. Do not restate the slide

The examiner can read the slide. Notes that repeat slide text verbatim waste airtime. Each bullet must add something the slide does not say.

### 4. No Q&A lines in notes

Examiner Q&A prep does not belong in the speaker notes. The notes are for delivery, not preparation. Q&A material goes in a separate document if needed.

### 5. Fit test

After editing, build with `latexmk -pdf -interaction=nonstopmode -g slides.tex` and visually check the note page in the PDF. If the note overflows, shorten the longest bullet first.

---

## Reference Example — CAN Bus Topology Slide

The first bullet is the framing opener. The remaining bullets each correspond to one slide bullet, anchored by the slide's bold lead term, adding depth not visible on the slide.

```latex
\note{\footnotesize\begin{itemize}\setlength{\itemsep}{5pt}
    \item ``So what is \textbf{CAN bus}? It is a \textbf{serial communication bus} developed by Bosch in the 1980s for connecting electronic control units in vehicles and industrial systems. The figure shows the physical setup of a two-node CAN bus --- each CAN node consists of a \textbf{CAN controller} handling the protocol logic and a \textbf{transceiver IC} driving the differential bus. All nodes share the same two wires, \textbf{CANH and CANL}, terminated at each end with a \textbf{120\,$\Omega$} resistor that matches the characteristic impedance of the twisted pair and prevents signal reflections.''
    \item \textbf{Simple and low cost:} ``Just \textbf{two wires} shared by all nodes, and every node can initiate a transfer --- no central master node required.''
    \item \textbf{Robust:} ``The bus uses \textbf{differential signaling} on CANH and CANL, which makes it inherently noise-resistant. Faulty nodes are automatically isolated through the \textbf{bus-off} mechanism.''
    \item \textbf{Priority-based access:} ``Arbitration is \textbf{non-destructive} --- the bus implements a \textbf{wired-AND} where dominant always beats recessive. A losing node backs off the moment it detects a stronger signal, leaving the winning frame \textbf{uninterrupted}.''
\end{itemize}}
```

---

## Slide Note Status

| Slide | Title | Notes status |
|---|---|---|
| 0 | Industrial Collaboration | Done — canonical style reference |
| 1 | CAN Bus Topology and ECUs | Done (prose style, pre-dates this format) |
| 2-5 | Why CAN (4 benefit slides) | Done (prose style, pre-dates this format) |
| 6 | CAN Classic vs CAN FD | Done (bold-lead style) |
| 7 | Project Objectives and Rationale | Done |
| 8 | From ISO Reference Model to RTL Modules | Done |
| 9 | MAC: `can_mac_fsm` | Done |
| 10 | MAC: `can_mac_bs` | Done |
| 11 | MAC: `can_mac_crc` | Done |
| 12 | MAC: `can_mac_ser` | Done |
| 13 | FCE: `can_mac_pcs_fce` | Done |
| 14 | PCS: `can_pcs` | Done |
| 15 | Verification Plan | Done |
| 16 | Verification Results | Done |
| 17 | Integration Testbench Architecture | Done |
| 18 | PCS Waveform Evidence | **Missing** |
| 19 | Bus-Off Recovery | **Missing** |
| 20 | Synthesis Results | **Missing** |
| 21 | Conclusion and Future Work | **Missing** |

---

## Build Command

```
cd defense && latexmk -pdf -interaction=nonstopmode -g slides.tex
```
