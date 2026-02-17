# Mermaid FSM Detail Levels: `fsm_detail_levels_v1`

## Purpose

This guide defines three standard detail levels for FSM diagrams so documentation can be scaled to audience and context.

- `L1` = simplest view
- `L2` = balanced engineering view
- `L3` = full code-trace view

Use this guide together with:
- `.claude/agent_guides/mermaid_fsm_detailed_trace_style_v1.md`

`L3` must follow that guide exactly.

## Level Definitions

## L1: High-Level Flow

Use when:
- introducing architecture
- non-specialist readers
- section overview before deep dive

Include:
1. Primary states only
2. Main happy-path transitions
3. Major error/recovery transitions (if important)

Exclude:
1. Choice nodes unless unavoidable
2. Internal counters/threshold guards
3. Detailed output bullet lists

Node format:
- short state names only

Edge labels:
- short intent labels (`start`, `complete`, `error`)

## L2: Design Review Level

Use when:
- module design discussion
- implementation review
- most report sections

Include:
1. All operational states
2. All real cross-state transitions
3. Key transition guards (symbolic constants allowed)
4. Brief state actions (1-3 bullets)

Exclude:
1. Noisy hold/self-loop transitions unless needed
2. Deep datapath details that do not affect state transitions

Node format:
- state name + separator + concise bullets

Edge labels:
- guard expressions with real signal names
- plain text labels only (no markdown backticks)

## L3: Code-Trace Detailed

Use when:
- proving RTL/document consistency
- final verification-oriented documentation
- debugging complex state behavior

Include:
1. All states in RTL type
2. All real cross-state transitions from `next_state_logic`
3. Choice nodes for true multi-branch decision points
4. Unlabeled edges into choice nodes; explicit guard labels on outgoing choice edges
5. Explicit guard labels with logic symbols (`∧`, `∨`, `¬`, `≥`, `≤`)
6. Plain text edge labels only (no markdown backticks / inline code formatting)
7. State output/action bullets tied to output logic
8. Notes for reserved/unreached states

Mandatory:
1. Run the verification checklist from:
   `.claude/agent_guides/mermaid_fsm_detailed_trace_style_v1.md`
2. Keep transition priority consistent with RTL condition ordering.

## Selection Rule

Default to `L2`.

Escalate to `L3` when:
1. asked to verify diagram against code
2. documenting nuanced error/ACK/retry behavior
3. preparing thesis/final technical sections

De-escalate to `L1` when:
1. audience needs concept-first explanation
2. detailed guards would reduce readability

## Naming Convention in Docs

When adding a diagram section, annotate level in nearby text:

- `Diagram level: L1`
- `Diagram level: L2`
- `Diagram level: L3`

This makes expected fidelity explicit for reviewers.
