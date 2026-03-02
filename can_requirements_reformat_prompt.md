# CAN FD Controller — Requirements Reformatting Prompt

## Context

You are assisting with formal and simulation-based verification of a CAN FD bus controller
implemented in VHDL. The design implements ISO 11898-1:2024 and contains approximately 130
extracted requirements currently stored in a structured table. All requirements have been forced
into a PRE/EVT/POST triple format, which is insufficient — this task is to reformat them into a
more accurate taxonomy that correctly reflects the verification intent of each requirement.

Requirements are processed one ISO section at a time. See the **Workflow** section at the end of
this prompt for the step-by-step procedure.

---

## The Problem With Universal PRE/EVT/POST

PRE/EVT/POST assumes every requirement is a triggered response: some precondition holds, an event
fires, and a postcondition must follow within a bounded number of cycles. This is appropriate for
many requirements but distorts others in ways that produce incorrect assertions. The goal is to
assign each requirement the shape that most accurately reflects what needs to be verified and how.

---

## The Four Requirement Shapes

### 1. Triggered Response

A specific observable event — a signal transition or a counter reaching a threshold, not a
persistent condition — fires while a precondition holds, and a postcondition must hold within a
bounded number of cycles after.

- **PSL form:** `always (pre and evt -> next[N] post)`
- **Use when:** the postcondition is caused by a discrete, single-cycle transition. Apply the
  one-cycle test: a genuine event is true for exactly one clock cycle. If you can substitute
  "while" for "when" without changing the meaning of the requirement, what was labelled an event
  is actually a precondition — and the shape is invariant, not triggered.
- **Examples:** error counter increment on a detected bit error; stuff bit insertion after fifth
  consecutive identical bit; node state transition when TEC crosses a threshold.

### 2. Invariant / Structural

A condition that must hold continuously whenever some context is true. There is no meaningful
triggering event — the rule applies every cycle the context holds. Also used for prohibitions.

- **PSL form:** `always (condition -> value)` or `assert never (violation)`
- **Use when:** the requirement describes frame field values, structural constraints, or a
  prohibition. Ask: does this requirement fire once in response to something, or must it simply
  always be true in a given context? If always, it is an invariant.
- **Examples:** "The CRC delimiter shall be a recessive bit"; "DLC shall not exceed 15";
  "A node in Bus Off shall not transmit."

### 3. Liveness

Something must *eventually* become true, but the standard does not specify exactly when in bounded
terms. Cannot be correctly expressed as a fixed-step postcondition.

- **PSL form:** `always (condition -> eventually! post)`
- **Use when:** the requirement says a node "shall recover", "shall complete", or "shall
  eventually" achieve some state without specifying a deadline in TQ counts or frame counts.
- **Distinguishing liveness from reachability:** liveness is a *universal* claim — "for **every**
  occurrence of the triggering condition, the outcome shall eventually follow." Reachability is an
  *existential* claim — "there **exists** a scenario where this outcome is demonstrated." If the
  requirement uses "shall" and applies to all cases, it is liveness. If it describes a capability
  or scenario that must be exercisable, it is reachability.
- **Verification note:** liveness is difficult for most open-source formal toolchains. These
  requirements are pragmatic simulation targets — the testbench imposes a practical timeout
  (e.g. within 10 frame periods) which is sufficient for confidence without requiring a formal
  liveness proof.
- **Examples:** "The node shall eventually recover from Bus Off after 128 × 11 recessive bits";
  "A pending transmission shall eventually be attempted."

### 4. Reachability / Coverage

The requirement asserts that a certain state, mode, or scenario is *possible* — a witness must
exist demonstrating the path is exercisable. This is not a universal proof but a demonstration
that the behaviour can occur.

- **PSL form:** `cover {sequence}` — fires when a simulation scenario reaches the target state.
- **Use when:** the requirement describes a capability, a mode that must be reachable, or an
  interaction between multiple nodes that cannot be verified on a single module in isolation.
- **Examples:** Bus Off recovery completing; arbitration loss followed by successful
  retransmission; BRS bit rate switch occurring in an FD frame; all valid FD DLC values (9–15)
  mapping correctly to payload lengths.

---

## Scope: What the Requirement Makes a Claim About

Every requirement must be assigned one of three scope values. Scope determines where the assertion
lives and what the verification environment must provide. It is also a sanity check: a `bus`-scope
requirement assigned a `triggered` or `invariant` shape is almost certainly a simulation target
and should be flagged for review.

### `frame`

The requirement is a claim about the **bit sequence structure**, independent of which node
produced it or what state that node is in. It says something about the content, ordering, or
encoding of fields within a valid CAN frame. These assertions live on the output or input bit
stream of the serialiser/deserialiser. No knowledge of internal node state is needed.

- **Examples:** "The CRC delimiter shall be a recessive bit"; "Fixed stuff bits in FD shall
  alternate polarity"; "The DLC field shall be 4 bits wide."

### `node`

The requirement is a claim about **what a specific controller instance must do** — its internal
state transitions, counter behaviour, or output decisions in response to bus events. The same bit
sequence on the bus might be legal or illegal depending on the node's current internal state, so
frame-level inspection is insufficient. These assertions reference internal signals such as TEC,
REC, and the error state FSM.

- **Examples:** "When TEC exceeds 127 the node shall transition to Error Passive"; "A transmitter
  shall monitor the bus during its own transmission"; "The node shall not restart transmission
  while in Bus Off state."

### `bus`

The requirement only makes sense in the context of **multiple nodes interacting** on a shared
medium. It describes a relationship or protocol outcome that emerges from the interaction —
something no single node can guarantee unilaterally. These requirements cannot be formally verified
on a single module in isolation. They require a simulated bus environment with at least two
controller instances and a shared bus model.

- **Examples:** "The node with the lower ID shall win arbitration"; "At least one receiver shall
  acknowledge a valid frame"; "An error flag from one node shall be detectable by all other nodes
  on the bus."

---

## Layer: Which Conceptual Entity the Requirement Belongs To

The `layer` field identifies which conceptual entity defined in ISO 11898-1:2015 the requirement
makes a claim about. This is not necessarily the module where the assertion lives — it is the
entity whose specified behaviour is being constrained. Assigning this correctly is a primary aid
for implementation: the ISO standard is organised around these entities, and each one has its own
dedicated section.

Valid values and their ISO sections:

| Value | Entity | ISO 11898-1:2015 Section | Governs |
|-------|--------|--------------------------|---------|
| `LLC` | Logical Link Control | §6.4 | Frame acceptance filtering, overload signalling, recovery notification |
| `MAC` | Medium Access Control | §6.6 | Frame construction and serialisation, bit stuffing, CRC generation and checking, ACK handling, error signalling |
| `PCS` | Physical Coding Sublayer | §7.2–7.3 | Bit timing, synchronisation, TDC, sample point, NRZ encoding |
| `FCE` | Fault Confinement Entity | §8 | TEC/REC counters, Error Active / Error Passive / Bus Off state machine, error counter rules |

**Assignment guidance for this project:**

- Frame field structure, field ordering, DLC-to-payload mapping → `MAC`
- Bit stuffing rules (both classical and fixed) → `MAC`
- CRC polynomial, CRC field calculation, CRC delimiter → `MAC`
- ACK slot encoding and ACK error detection → `MAC`
- Bit timing parameters, synchronisation jump width, sample point location → `PCS`
- Transmitter Delay Compensation (TDC) → `PCS`
- TEC and REC counter increment/decrement rules → `FCE`
- Error Active, Error Passive, Bus Off state transitions → `FCE`
- Error flag and error delimiter transmission → `FCE`
- Frame acceptance, remote frame handling → `LLC`

If a requirement spans two entities (e.g. an FCE counter threshold that triggers a MAC-layer
output change), assign the entity that *owns the primary state being constrained* and note the
dependency in the `notes` field.

---

## Output Format

Produce one TOML block per requirement using the schema below.

**Field inclusion rules by shape:**

| Field | triggered | invariant | liveness | reachability |
|-------|-----------|-----------|----------|--------------|
| `precondition` | required | required | optional | omit |
| `event` | required | omit | omit | omit |
| `postcondition` | required | required | required | omit |
| `coverage_target` | omit | omit | omit | required |

**For `scope = "frame"` requirements**, `side` should be set to `"both"` if the
structural rule applies regardless of transmit or receive role.

**For COMPOUND requirements**, output one block using the shape and scope of the first distinct
sub-claim. The `notes` field must enumerate each sub-claim and explain how the requirement should
be split. Do not attempt the split — that is a human decision.

```toml
[[requirement]]
id = "REQ-xxx"
source_clause = "ISO 11898-1:2015 §x.x.x"

# Verbatim text from the ISO document. Include all relevant sentences even if
# non-contiguous; separate segments with " ; ". This is the authoritative text —
# all other fields are interpretation and metadata.
original_wording = "..."

# One of: triggered | invariant | liveness | reachability
shape = "..."

# One of: frame | node | bus
scope = "..."

# One of: transmitter | receiver | both
# Omit for frame-scope requirements where the rule is role-independent.
side = "..."

# One of: LLC | MAC | PCS | FCE
# Assign to the entity whose specified behaviour this requirement constrains,
# per ISO 11898-1:2015 section structure (see Layer section above).
layer = "..."

# Comma-separated subset of: CB, CE, FB, FE
# CB = Classic Basic, CE = Classic Extended, FB = FD Basic, FE = FD Extended
# CAN XL is out of scope — do not include XL frames.
# If all four formats apply, state why in notes rather than defaulting silently.
format_applicability = "..."

# Required for shape = triggered or invariant
precondition = "..."

# Required for shape = triggered only
event = "..."

# Required for shape = triggered, invariant, or liveness
postcondition = "..."

# Required for shape = reachability only
coverage_target = "..."

# One or more of: COMPOUND, AMBIGUOUS, EXTERNAL_DEP, SHOULD, DOC_ONLY
# COMPOUND     — postcondition contains more than one distinct claim
# AMBIGUOUS    — shape or scope assignment is uncertain; explain in notes
# EXTERNAL_DEP — precondition references state not defined in this requirement set
# SHOULD       — wording uses "should" (recommendation) rather than "shall" (mandatory)
# DOC_ONLY     — requirement is a documentation, traceability, or configuration obligation,
#                not an RTL-assertable behaviour; no simulation or formal assertion is possible
# Empty list if none apply.
flags = []

# Reasoning for shape, scope, layer, and side assignment.
# Explain any non-obvious decisions. For COMPOUND, enumerate the sub-claims.
# For AMBIGUOUS, explain the uncertainty and the alternatives considered.
# For format_applicability, explain why all four formats apply if that is the assignment.
# For DOC_ONLY, explain why no RTL assertion is possible.
# If this requirement substantively duplicates an earlier one, note: "Substantively
# duplicates REQ-xxx from §y.y.y" and explain how the wording differs.
notes = "..."

# Label that will identify this requirement's assertion or coverage point in the
# implementation (PSL label in VHDL source, or testbench procedure name).
# Used for bidirectional traceability between requirements and code.
# Leave blank at this stage — assigned during implementation.
label = ""

# Target VHDL source file where this requirement's assertion will be implemented.
# Leave blank at this stage — assigned during implementation once the module
# structure is finalised.
file = ""
```

---

## Worked Examples

### Example A — Invariant, frame scope

**Original PRE/EVT/POST entry:**
- PRE: CAN frame is being transmitted
- EVT: CRC delimiter bit is reached
- POST: CRC delimiter bit is recessive

**Analysis:** "CRC delimiter bit is reached" is not a one-cycle transition — it is a persistent
condition (the delimiter field occupies one bit position and that position is either the delimiter
or it is not). The postcondition is a structural property that must hold every time a CRC delimiter
is present. Shape is invariant. No node-internal state is needed to verify this; it is a claim
about the bit stream. Scope is frame. The CRC delimiter is defined in the MAC sublayer. All four
in-scope formats include a CRC delimiter, so format_applicability is CB, CE, FB, FE — noted in
notes.

```toml
[[requirement]]
id = "REQ-MAC-001"
source_clause = "ISO 11898-1:2015 §6.6.10.5"
original_wording = "The CRC delimiter shall be a recessive bit."
shape = "invariant"
scope = "frame"
side = "both"
layer = "MAC"
format_applicability = "CB, CE, FB, FE"
precondition = "The CRC delimiter bit position is present on the bus"
postcondition = "The bit at the CRC delimiter position is recessive"
flags = []
notes = "Structural frame constraint with no triggering event. All four in-scope formats include a CRC field with a delimiter bit, so format_applicability is CB, CE, FB, FE."
label = ""
file = ""
```

### Example B — Triggered, node scope, FCE layer

**Original PRE/EVT/POST entry:**
- PRE: Node is Error Active
- EVT: Transmit Error Counter exceeds 127
- POST: Node transitions to Error Passive

**Analysis:** TEC crossing 127 is a genuine one-cycle event — the counter transitions from ≤127
to >127 on a specific clock edge. This is not a persistent condition. The postcondition is a
single state transition. Shape is triggered. This is a claim about a specific controller's
internal state machine, not a frame structural property. Scope is node. The error state machine
and TEC counter are owned by the Fault Confinement Entity.

```toml
[[requirement]]
id = "REQ-FCE-001"
source_clause = "ISO 11898-1:2015 §8.3"
original_wording = "A node shall be Error Passive when the Transmit Error Count exceeds 127."
shape = "triggered"
scope = "node"
side = "transmitter"
layer = "FCE"
format_applicability = "CB, CE, FB, FE"
precondition = "Node is in Error Active state"
event = "TEC transitions from a value ≤ 127 to a value > 127"
postcondition = "Node enters Error Passive state within 1 clock cycle"
flags = []
notes = "TEC increment is synchronous; the state transition should be registered on the same or following clock edge. All four formats share the same error confinement rules, so format_applicability is CB, CE, FB, FE."
label = ""
file = ""
```

### Example C — DOC_ONLY

**ISO text:** "If there are internal conditions of a CAN node that cause an overload frame to be
initiated, these conditions shall be documented for that CAN node."

**Analysis:** This is a documentation obligation directed at the implementer, not a hardware
behaviour that can be observed in simulation or formal verification. There is no signal to assert
against. Flag DOC_ONLY.

```toml
[[requirement]]
id = "REQ-LLC-030"
source_clause = "ISO 11898-1:2015 §6.5.5"
original_wording = "If there are internal conditions of a CAN node that cause a OF to be initiated, these conditions shall be documented for that CAN node."
shape = "invariant"
scope = "node"
side = "receiver"
layer = "LLC"
format_applicability = "CB, CE, FB, FE"
precondition = "The CAN node implementation supports overload frame generation"
postcondition = "The internal conditions that can cause an overload frame are documented in the node specification"
flags = ["DOC_ONLY"]
notes = "Documentation/traceability obligation — no RTL signal can be asserted against 'conditions are documented'. Retained for completeness and requirements traceability."
label = ""
file = ""
```

---

## Key Distinction Rules

**One-cycle test for events.** A genuine event is true for exactly one clock cycle. If you can
substitute "while" for "when" without changing the meaning, the condition is persistent and the
shape is invariant, not triggered.

**Liveness vs. reachability.** Liveness is universal ("for every occurrence, the outcome shall
eventually follow"). Reachability is existential ("there exists a scenario where this outcome is
demonstrated"). Universal + "shall" → liveness. Capability / scenario → reachability.

**Single postcondition rule.** If the postcondition contains more than one distinct claim, flag
COMPOUND. Output one block for the first sub-claim and enumerate the rest in `notes`. Do not split
— that is a human decision.

**Multi-node requirements and AMBIGUOUS scope.** Any requirement whose verification requires two
controller instances interacting on a shared bus is bus-scope. If you flag AMBIGUOUS on `scope`,
assign the *more conservative* value — the one that requires more verification infrastructure
(i.e. prefer `bus` over `node`, `node` over `frame`). Explain the downgrade and the alternative
in `notes`. Do not silently assign the lower-infrastructure scope without flagging it.

**Shall vs. should.** ISO 11898 uses "shall" for mandatory requirements and "should" for
recommendations. Flag all "should" requirements with SHOULD. These are not hard assertions.

**Service interface definitions.** Statements of the form "service X shall be passed from A to B"
define the direction and existence of an interface primitive. They are typically not independently
assertable — the direction is implicit in the protocol handshake. Flag these DOC_ONLY unless the
*content* or *timing* of the primitive is also constrained in the same sentence, in which case
extract the content/timing claim as the assertable postcondition.

**Documentation and traceability obligations.** Requirements whose postcondition is "X shall be
documented", "X shall be configurable", or "conditions shall be specified" are implementation
obligations on the designer, not observable RTL behaviours. Flag these DOC_ONLY and leave both
`label` and `file` blank.

**Near-duplicate requirements.** If a normative statement is substantively identical to one
already output (same claim, different section), still produce a TOML block — do not skip it.
Set `original_wording` to the new location's text and add to `notes`:
"Substantively duplicates REQ-xxx from §y.y.y — wording differs as follows: [explain]."

**Uncertainty over silent judgment.** If the correct shape, scope, or layer is unclear, flag
AMBIGUOUS and explain the alternatives considered. Do not make silent judgment calls on ambiguous
cases — those are exactly the ones requiring human review.

---

## Sanity Checks Before Finalising Each Entry

1. `shape = "triggered"` — is the `event` field a discrete one-cycle transition?
2. `shape = "invariant"` — does the postcondition hold every cycle in context, not just once?
3. `scope = "bus"` with `shape = "triggered"` or `"invariant"` — flag AMBIGUOUS; explain.
4. Postcondition contains more than one distinct claim — flag COMPOUND.
5. Wording uses "should" not "shall" — flag SHOULD.
6. Precondition references state not defined in this requirement set — flag EXTERNAL_DEP.
7. `layer` assignment — does it match the ISO 11898-1:2015 section that defines the constrained
   behaviour (LLC §6.4, MAC §6.6, PCS §7.2–7.3, FCE §8)?
8. `format_applicability` — does it include only CB, CE, FB, FE? CAN XL is out of scope. If all
   four formats are assigned, confirm in `notes` why all four apply — do not default silently.
9. Is the postcondition an observable RTL behaviour, or a documentation / configuration
   obligation? If the latter, flag DOC_ONLY and leave `label` and `file` blank.
10. Is this requirement substantively identical to one already output? If so, note the duplicate
    in `notes` rather than silently omitting or replacing.
11. AMBIGUOUS scope — if flagged, is the assigned `scope` the more conservative (higher
    infrastructure) option? Confirm in `notes`.

---

## Workflow

Requirements are extracted and reformatted one ISO section at a time, in the order below. This
keeps the `layer` field nearly deterministic within each section and produces output that a human
reviewer can check against the standard section-by-section.

### Sections to process, in order

| Step | ISO Section | Entity | Default `layer` |
|------|-------------|--------|-----------------|
| 1 | 6.4 LLC sub-layer | LLC | `LLC` |
| 2 | 6.6 MAC sub-layer | MAC | `MAC` |
| 3 | 7.2 Services of the PCS interface and 7.3 PCS | PCS | `PCS` |
| 4 | 8 Description of supervisor FCE | FCE | `FCE` |

Within §6.6 (MAC), work through subsections in document order. §6.6 is the largest section and
contains the most requirements; do not skip subsections. For step 3, process both §7.2 and §7.3
as a single section pass — produce one inventory block and one summary block covering both.

### Output file

All requirements from all four sections are written to a **single file**:

```
requirements/requirements_reformatted.toml
```

The file is created before processing begins and appended to as each section completes. It is
the definitive production output of the reformatting run — not a draft. Section inventory and
summary blocks appear as TOML comments interleaved between the `[[requirement]]` entries, serving
as an in-file audit trail.

The overall file structure is:

```toml
# CAN Requirements — ISO 11898-1:2015
# Reformatted from PRE/EVT/POST into ISO-aligned shape/scope/layer taxonomy.
# Generated by reformatting agent.

# ============================================================
# SECTION: §6.4 + §6.5 — LLC sub-layer
# ============================================================
# === SECTION INVENTORY ... ===
# ...
# ===

[[requirement]]
id = "REQ-LLC-001"
...

# === SECTION SUMMARY ... ===
# ...
# ===

# ============================================================
# SECTION: §6.6 — MAC sub-layer
# ============================================================
# === SECTION INVENTORY ... ===
...
```

IDs use the layer prefix for the section: `REQ-LLC-NNN`, `REQ-MAC-NNN`, `REQ-PCS-NNN`,
`REQ-FCE-NNN`. Numbering restarts from 001 for each layer prefix.

### MCP tool usage

After completing each section, use the `requirements-reformatter` MCP tool to validate the
accumulated state of the output file before presenting the section summary to the human reviewer:

```
get_statistics_reformatted(toml_path="requirements/requirements_reformatted.toml")
```

Confirm that:
- `total_count` equals the cumulative count of all sections completed so far
- `by_layer` shows the correct count for the just-completed section
- `blank_label_count` equals `total_count` (all labels must be blank at this stage)
- `blank_file_count` equals `total_count` (all files must be blank at this stage)

If any discrepancy is found, report it in the section summary before stopping.

### Tally discipline

As you process each requirement, maintain a running tally of the following lists. Do not attempt
to reconstruct these by re-reading your output at summary time — populate them as you go:

```
running_triggered    = [list of IDs]
running_invariant    = [list of IDs]
running_liveness     = [list of IDs]
running_reachability = [list of IDs]
running_COMPOUND     = [list of IDs]
running_AMBIGUOUS    = [list of IDs]
running_EXTERNAL_DEP = [list of IDs]
running_SHOULD       = [list of IDs]
running_DOC_ONLY     = [list of IDs]
```

The section summary is written directly from these lists. Counts are derived from list lengths,
not from re-counting. This eliminates arithmetic errors in the summary.

### Procedure for each section

**Step 1 — Inventory.**
Before outputting any TOML, read the entire section. Then output a plain-text inventory block:

```
=== SECTION INVENTORY: §N — <Section Title> (layer = <LAYER>) ===
Subsections covered: §N.1, §N.2, ... (list all)
Requirement count lower bound: N  (actual count will be ≥ this; overrun is expected and correct)
Cross-section dependencies noted: <list any requirements in this section that
  reference state owned by a different entity, or "none">
===
```

This inventory is not TOML — it is a human-readable audit trail. Output it before the first
`[[requirement]]` block for the section.

**Step 2 — Extract and reformat.**
Working through the section subsection by subsection, identify every normative statement — every
sentence containing "shall" or "shall not", and every "should" recommendation. For each, produce
one TOML block per the output format defined above. Update the running tally lists after each
block.

Do not skip requirements because they seem obvious, redundant, or already captured elsewhere.
If a subsection contains no normative statements, note it in a single comment line:
`# §N.x — no normative requirements`

**Step 3 — Section summary.**
After the last TOML block for the section, write the summary directly from your running tally
lists:

```
=== SECTION SUMMARY: §N — <Section Title> ===
Requirements output: N
  triggered:    N  (REQ-xxx, REQ-xxx, ...)
  invariant:    N  (REQ-xxx, ...)
  liveness:     N  (REQ-xxx, ...)
  reachability: N  (REQ-xxx, ...)
  DOC_ONLY:     N  (REQ-xxx, ...)
Flags raised:
  COMPOUND:      N  (REQ-xxx, ...)
  AMBIGUOUS:     N  (REQ-xxx, ...)
  EXTERNAL_DEP:  N  (REQ-xxx, ...)
  SHOULD:        N  (REQ-xxx, ...)
  DOC_ONLY:      N  (REQ-xxx, ...)
Cross-section dependencies:
  <list requirements whose precondition or event references state from a different
   entity layer, e.g. "REQ-042 precondition references TEC (FCE state) from within
   MAC section">
===
```

Then stop and wait for human confirmation before proceeding to the next section.

### Cross-section dependency policy

When processing a section, you will sometimes encounter requirements that reference state owned
by a different entity. Apply the following rule:

> Assign `layer` to the entity that owns the **primary behaviour being constrained**, not the
> entity that owns the precondition state.

Examples:
- §6.6 rule: "A transmitter in Error Passive state shall send a passive error flag." — The
  constrained behaviour is what the transmitter sends (MAC output). Layer = `MAC`. The Error
  Passive state is an FCE precondition; mark EXTERNAL_DEP and note it.
- §8 rule: "After entering Bus Off, the node shall not transmit." — The constrained behaviour
  is bus access (MAC/FCE boundary). Layer = `FCE` because Bus Off is the FCE's primary output
  state. Note the MAC dependency.

List all cross-section dependencies in the section summary so the human reviewer can verify
nothing was miscategorised.

### After all four sections

Output a final cross-reference block:

```
=== FINAL CROSS-REFERENCE ===
Total requirements: N
  (of which DOC_ONLY: N — no assertions to write)
EXTERNAL_DEP requirements and their dependency targets:
  REQ-xxx (layer=MAC) → depends on FCE state: TEC > 127
  ...
Requirements that may need to be duplicated across layers:
  REQ-xxx: appears in §6.6 but also constrains FCE behaviour — review for split
  ...
Recommended human review items:
  - All AMBIGUOUS flags (N total) — scope or shape assignments need confirmation
  - All COMPOUND flags (N total) — require splitting before assertion writing
  - All SHOULD flags (N total) — confirm whether to treat as assertions or comments
  - All DOC_ONLY flags (N total) — confirm documentation deliverable is tracked elsewhere
===
```
