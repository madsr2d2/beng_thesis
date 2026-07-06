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

Notes are spoken delivery cues with key terms bolded. One bullet per slide bullet. The purpose is to serve as a spoken delivery guide during the defense — not a compressed reference or Q&A prep sheet.

```latex
\note{\footnotesize\begin{itemize}\setlength{\itemsep}{5pt}
    \item Spoken sentence for first slide bullet, with \textbf{key terms} bolded.
    \item Spoken sentence for second slide bullet, with \textbf{key terms} bolded.
    \item Spoken sentence for third slide bullet, with \textbf{key terms} bolded.
\end{itemize}}
```

Key parameters:
- Outer itemsep: `5pt`
- No quote marks — the notes are already understood to be spoken words
- Key terms bolded inline: `\textbf{term}`

---

## Rules

### 1. One bullet per slide bullet

The first bullet is always a **framing opener** — one sentence that orients the presenter before they start talking. It introduces the slide topic in spoken form, often as a rhetorical question or a "this slide covers..." statement. It does not correspond to any slide bullet.

Every subsequent bullet corresponds to one slide bullet. The note rephrases the slide content in natural spoken form and adds one piece of depth not visible on the slide — context, a number, a motivation, a consequence. It does not restate the slide verbatim.

Good: slide says "CAN Classic protocol", note says `The CAN controller runs as an \textbf{IP core on that FPGA} --- \textbf{500\,kbit/s}, 8 bytes per frame.`

Bad: slide says "CAN Classic protocol", note says `The current CAN infrastructure builds on the CAN Classic protocol.`

### 2. Bold key terms inline

Bold the two or three terms per bullet the presenter must land clearly when speaking. These are the terms the examiner will latch onto. Do not bold whole phrases — just the noun or number that carries the meaning.

### 3. Do not restate the slide

The examiner can read the slide. Notes that repeat slide text verbatim waste airtime. Each bullet must add something the slide does not say.

### 4. Conversational tone

Write how you would actually say it, not how you would write it. Use short sentences. Contractions are fine. Natural connectors like "So", "Now", "The thing is" work well as openers. Avoid long compound sentences — if a sentence needs a semicolon, split it. Avoid passive voice and nominalisations ("the implementation of" → "implementing"). Read each bullet aloud: if it sounds like you are reading a document, rewrite it.

Bad: `The bus uses differential signaling on CANH and CANL, which makes it inherently noise-resistant.`
Good: `It uses \textbf{differential signaling} --- CANH and CANL --- so noise hits both wires equally and cancels out.`

### 5. No Q&A lines in notes

Examiner Q&A prep does not belong in the speaker notes. The notes are for delivery, not preparation. Q&A material goes in a separate document if needed.

### 6. Fit test

After editing, build with `latexmk -pdf -interaction=nonstopmode -g slides.tex` and visually check the note page in the PDF. If the note overflows, shorten the longest bullet first.

---

## Reference Example — CAN Bus Topology Slide

The first bullet is the framing opener. The remaining bullets each correspond to one slide bullet, anchored by the slide's bold lead term, adding depth not visible on the slide.

```latex
\note{\footnotesize\begin{itemize}\setlength{\itemsep}{5pt}
    \item So --- what is \textbf{CAN}? It's a \textbf{serial bus} Bosch developed in the 1980s for connecting ECUs in vehicles. The figure shows a two-node setup --- each node is a \textbf{CAN controller} plus a \textbf{transceiver IC}. Both nodes share the same two wires, \textbf{CANH and CANL}, terminated at each end with \textbf{120\,$\Omega$} to kill reflections.
    \item \textbf{Simple and low cost:} Just \textbf{two wires}, shared by everyone. There's no master node --- any node can start a transfer.
    \item \textbf{Robust:} It uses \textbf{differential signaling} on CANH and CANL, so noise hits both wires equally and cancels out. And if a node goes faulty, the \textbf{bus-off} mechanism isolates it automatically.
    \item \textbf{Priority-based access:} Arbitration is \textbf{non-destructive}. The bus is a \textbf{wired-AND} --- dominant beats recessive. A losing node backs off the moment it sees a stronger signal, so the winning frame goes through uninterrupted.
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
| 18 | Synthesis Results | Done |
| 19 | Conclusion and Future Work | Done |

---

## Build Command

```
cd defense && latexmk -pdf -interaction=nonstopmode -g slides.tex
```
