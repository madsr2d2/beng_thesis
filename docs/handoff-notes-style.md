# Handoff: Defense Slides — Note Formatting Style

## Purpose

This document defines the speaker note formatting style established during the June 2026 slide polish session. Any agent or session working on `defense/slides.tex` notes should follow this style exactly.

---

## Constraints

- Notes render on the right half of a pdfpc dual-screen view (`show notes on second screen=right`).
- The available height is roughly half a portrait A4 page at `\footnotesize`.
- **Notes must fit on a single pdfpc note page.** Overflow is silent — content is cut off, not reflowed. When in doubt, cut a bullet rather than shrink font.
- Font is already `\footnotesize` — do not go smaller.

---

## LaTeX Template

```latex
\note{\footnotesize\begin{itemize}\setlength{\itemsep}{5pt}
    \item \textbf{Topic:} One tight sentence. Second sentence only if essential.
    \item \textbf{Topic:} ...
        \begin{itemize}\setlength{\itemsep}{1pt}
            \item Sub-point for a named item that needs elaboration.
            \item Sub-point for another named item.
        \end{itemize}
    \item \textbf{Q: Anticipated examiner question?} One-sentence answer.
    \item \textbf{Q: Second likely question?} One-sentence answer.
\end{itemize}}
```

Key parameters:
- Outer itemsep: `5pt`
- Inner (sub-bullet) itemsep: `1pt`
- Lead term always bolded: `\textbf{Term:}`
- Q lines always at the bottom, formatted `\textbf{Q: ...?} answer.`

---

## Rules

### 1. Bold lead term on every bullet

Every main bullet starts with `\textbf{Keyword:}` so the presenter can find their place at a glance without reading the full line.

Good: `\item \textbf{Error counters:} TEC $+8$ on TX error, $-1$ on successful TX.`
Bad: `\item TEC increments by 8 on TX errors and decrements by 1 on successful TX.`

### 2. Sub-bullets only for named lists

Use a nested `itemize` when a bullet enumerates specific signal names, states, or fields that the presenter may need to reference by name. Do not nest for prose elaboration — that belongs in the parent bullet.

Good use: listing 5 input signals from `can_mac_fsm` with brief explanations of the non-obvious ones.
Bad use: nesting a second sentence of prose under a bullet that is already clear.

### 3. Q lines at the bottom

End every note with one or two `\textbf{Q: ...?}` lines covering the examiner questions most likely to come from that slide. Keep the answer to one sentence. These are the last thing the presenter sees before the examiner speaks — make them punchy.

### 4. One fact per bullet

If a bullet contains two independent facts joined by a semicolon, split it. If it contains a subordinate clause longer than the main clause, trim the subordinate clause.

### 5. Fit test

After editing, build with `latexmk -pdf -interaction=nonstopmode -g slides.tex` and visually check the note page in the PDF. If the note overflows, cut the lowest-priority bullet first, then shorten sub-bullets, then condense main bullets.

---

## Reference Example — FCE Slide

This is the canonical example of the style in its final state (`f86845f1`):

```latex
\note{\footnotesize\begin{itemize}\setlength{\itemsep}{5pt}
    \item \textbf{Error counters:} TEC $+8$ on TX error, $-1$ on successful TX. REC $+1$ on RX error, $-1$ on successful RX.
    \item \textbf{State thresholds:} Error active: TEC and REC $<128$. Error passive: TEC or REC $\geq128$ --- passive flags are recessive, invisible on bus. Bus off: TEC $\geq256$ --- stops transmitting.
    \item \textbf{Error events:} \texttt{primary\_error}, \texttt{sending\_error\_flag}, \texttt{passive\_tx\_ack\_error}, \texttt{error\_delim\_to\_late}, \texttt{successful\_transfer}.
        \begin{itemize}\setlength{\itemsep}{1pt}
            \item \texttt{passive\_tx\_ack\_error}: ACK failure for an error-passive transmitter -- ISO exempts this from TEC increment to avoid stranding lone node at bus off.
            \item \texttt{error\_delim\_to\_late}: delimiter window expired with no recessive edge --- stuck-dominant fault. Hits both TEC and REC by 8 to fast-track bus off.
        \end{itemize}
    \item \textbf{Q: Why 128 sequences?} ISO mandates it -- extended quiet period prevents rapid re-entry after bus-off.
    \item \textbf{Q: In-flight frame on bus off?} \texttt{can\_mac\_fsm} receives \texttt{bus\_off} and aborts immediately.
\end{itemize}}
```

---

## Slide Note Status

| Slide | Title | Notes status |
|---|---|---|
| 1 | CAN Bus Topology and ECUs | Done (prose style, pre-dates this format) |
| 2-5 | Why CAN (4 benefit slides) | Done (prose style, pre-dates this format) |
| 6 | CAN Classic vs CAN FD | Done (bold-lead style) |
| 7 | Project Objectives and Rationale | Done |
| 8 | From ISO Reference Model to RTL Modules | Done |
| 9 | MAC: `can_mac_fsm` | Done |
| 10 | MAC: `can_mac_bs` | Done |
| 11 | MAC: `can_mac_crc` | Done |
| 12 | MAC: `can_mac_ser` | Done |
| 13 | FCE: `can_mac_pcs_fce` | Done — canonical style reference |
| 14 | PCS: `can_pcs` | Done |
| 15 | Verification Plan | Done |
| 16 | Verification Results | Done |
| 17 | Integration Testbench Architecture | Done |
| 18 | PCS Waveform Evidence | **Missing** |
| 19 | Bus-Off Recovery | **Missing** |
| 20 | Synthesis Results | **Missing** |
| 21 | Conclusion and Future Work | **Missing** |

---

## Next Session Scope

Add notes to the four missing slides following this style. Suggested Q lines per slide:

**PCS Waveform Evidence**
- Q: What does TDC actually measure? (transceiver loop delay: time from TX drive to RX echo on the reserved bit)
- Q: Why is SSP separate from SP? (transmitter uses SSP for bit-error monitoring in data phase — SP offset is wrong at high data rates due to loop delay)

**Bus-Off Recovery**
- Q: Why 128 sequences of 11 recessive bits? (ISO 11898-1 mandates it — extended quiet period before re-joining)
- Q: Can a node re-enter bus off immediately after recovery? (yes, if errors continue TEC climbs back to 256)

**Synthesis Results**
- Q: Why is `can_mac_fsm` 89% of LEs? (560-bit RX frame buffer implemented in logic — BRAM migration is listed as future work)
- Q: What is the minimum clock for 5 Mbit/s? (5 Mbit/s at 8 TQ/bit = 40 MHz; 127 MHz gives 3x margin)

**Conclusion**
- Q: What would LLC add? (acceptance filtering, retransmission on arbitration loss, transfer status reporting to application)
- Q: Why not implement LLC? (project timeline; MAC, PCS, FCE sufficient to demonstrate full frame TX/RX)

---

## Build Command

```
cd defense && latexmk -pdf -interaction=nonstopmode -g slides.tex
```
