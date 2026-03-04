# CAN Bus Controller — Verification Analysis Notes

*Compiled from design review session, 2026-03-03*

---

## 1. The Observability Problem

The verification plan's 168 requirements were initially written in plain English. This created
a practical problem: many requirements gave no clear handle on *where* in the system to observe
the behaviour or *what signal* constituted a pass criterion. A statement like "the node
transmits a dominant bit" is normatively correct but not directly executable as a testbench
assertion.

**Resolution**: All 168 pre/event/post triplets were rewritten to reference the canonical
ISO 11898-1 service primitives at each layer boundary — PCS_Data.Request(Output_Unit),
PCS_Data.Indicate(Input_Unit), L_Data.Confirm(Transfer_Status), Error(type) at MAC↔FCE,
etc. Each postcondition now names a specific primitive and parameter value, or for timing
requirements, an explicit formula over configuration generics (e.g.
`m_nom × (1 + prop_seg_nom + phase_seg1_nom)` clock cycles for the nominal sample point).

---

## 2. Observability Classification

Using the canonical layer boundaries, every requirement was classified into one of three tiers:

| Tier | Count | Definition |
|---|---|---|
| **External** | 106 | Postcondition maps onto a named primitive parameter, or onto the timing of a primitive call fully determined by config generics and stimulus. Directly assertable by a black-box testbench. |
| **Derived** | 40 | Effect manifests at the layer boundary but verifying correctness requires a non-trivial algorithm — CRC polynomials, error counter arithmetic, multi-step protocol state tracking. Requires a reference model alongside the DUT. |
| **Internal** | 22 | Structural definitions or constraints on valid configuration inputs with no manifestation at any layer boundary. Not testable at the layer level; checked by design review or static analysis. |

The 106 external requirements are the primary testbench target. The derived requirements form
a defined second phase that is blocked on reference model availability.

---

## 3. Methodological Correctness vs. Practical Tension

Anchoring observability to the ISO layer interfaces is methodologically correct: the ISO
layer boundaries are the intended verification seams, and classifying against them keeps the
plan independent of any particular implementation. A requirement classified as external is
external regardless of how it is implemented.

However, this creates a practical tension when applying the plan to an implementation that
does not adhere strictly to the ISO layer structure. In that case the ISO primitives used
as observability anchors do not exist as named signals in the design. Verification then
requires:

1. Identifying a proxy signal in the implementation that is argued to be equivalent to the
   ISO primitive.
2. Separately documenting that mapping as an explicit step in the testbench plan — distinct
   from the requirement itself.

The plan keeps these two concerns separate by design: requirements stay anchored to ISO
interfaces; the mapping to implementation signals is a testbench-level concern.

---

## 4. Company Implementation Architecture: `can_bus_controller`

### Structure

The existing company CAN controller consists of seven modules:

| Module | Role |
|---|---|
| `can_bus_controller` | Top-level wrapper, instantiates all submodules |
| `can_fsm` | Core 16-state protocol FSM |
| `can_node_clock` | Bit timing and synchronisation (PCS-like) |
| `can_ast_to_serial` | TX path: Avalon-ST frame → serial bits (LLC-like) |
| `can_serial_to_ast` | RX path: serial bits → Avalon-ST frame (LLC-like) |
| `can_stuff_bit_gen` | Bit stuffing detector |
| `gen_crc` | CRC calculator (external module) |

### Key Architectural Observations

**Monolithic FSM collapses MAC, FCE, and both TX/RX pipelines.** `can_fsm` is a 16-state
machine that handles frame sequencing (SOF → arbitration → control → data → CRC → ACK → EOF),
error detection, error frame transmission, error counter management, and bus reintegration —
all in one module, for both the transmit and receive directions simultaneously. TX/RX behaviour
is selected by an internal flag rather than separated into distinct data paths.

**ISO describes TX and RX as independent pipelines.** The standard defines them as separate
data flows sharing only the physical bus and the synchronisation clock:
- TX: LLC SDU → MAC encapsulation → PCS serialisation → bus
- RX: bus → PCS sampling → MAC de-encapsulation → LLC delivery

The only coupling points the standard mandates are the physical bus and the shared FCE error
counters. Collapsing both into one FSM means TX-only and RX-only bugs manifest identically as
FSM state transition failures, making fault isolation significantly harder.

**No formal MAC↔PCS boundary.** `can_node_clock` generates `sample_rx_o` pulses (a reasonable
proxy for `PCS_Data.Indicate`) and `transmit_o`, but the boundary is informal — there is no
named interface contract, and the FSM consumes these signals directly alongside RX bus data.

**The ISO primitives used in the verification plan do not exist as signals.** Error(type) at
MAC↔FCE, Successful_transfer, Error_passive_request, and similar named services are all
internal to `can_fsm`. Testbench assertions against these requirements must use proxy signals:
FSM state transitions, the 3-bit `debug_error_flag_o`, the `ns_o` node-state output.

### Testable Seams That Do Exist

Despite the above, three testable module boundaries are present:

| Module | Testable boundary | Relevant requirements |
|---|---|---|
| `can_node_clock` | `sample_rx_o` timing as proxy for `PCS_Data.Indicate`; `transmit_o` for `PCS_Status.Transmitter` | PCS-008, 024–030 (synchronisation and sample point cluster) |
| `can_stuff_bit_gen` | `stuff_bit_o` / `stuff_bit_valid_o` against driven bit stream | MAC-062–068 (bit stuffing rules) |
| `gen_crc` | CRC output against known polynomial applied to known bit stream | MAC-002–004, 007–008 (CRC polynomial selection and init vectors) |
| `can_ast_to_serial` / `can_serial_to_ast` | Avalon-ST sink/source as proxy for LLC↔MAC boundary | LLC-layer requirements (frame structure, DLC, padding) |

These seams allow isolated verification of derived requirements (CRC, stuffing) without
needing to observe the MAC↔FCE boundary. The FSM-level behaviour must be verified at the
top-level `can_bus_controller` boundary using proxy signals.

---

## 5. Contrast: Thesis TX Pipeline (`src/`)

The thesis project implements the TX path only, but with explicit layer separation:

| Module | Role | Layer boundary |
|---|---|---|
| `can_pkg.vhd` | Frame structure as data — `get_next_mac_frame_bit()`, `frame_params_t` | Protocol definition, independent of hardware |
| `tx_mac_ser.vhd` | Pure TX serialiser: LLC byte stream → `polarity_t` bit stream | LLC↔MAC = Avalon-ST sink; MAC↔PCS = `polarity_t` output |
| `bit_stuffer.vhd` / `bit_stuffer_fd.vhd` | TX-only stuff bit insertion | Within MAC TX path |
| `tx_mac_fsm.vhd` | TX-only FSM (placeholder) | TX state management only |

**Key differences from the company implementation:**

- TX and RX are separate by construction — no module handles both directions.
- The MAC↔PCS boundary is a typed signal (`polarity_t` with `valid`/`ready`), directly
  corresponding to `PCS_Data.Request(Output_Unit=dominant/recessive)`.
- The frame structure is data-driven (`get_next_mac_frame_bit()` returns the correct bit
  for any frame position) rather than encoded in FSM state transitions — testable
  independently of any hardware module.
- Each module has a single-direction contract, making the ISO primitive classification
  map directly onto observable signals without proxy arguments.

---

## 6. Practical Implications for Testbench Development

| Concern | Company `can_bus_controller` | Thesis `src/` TX pipeline |
|---|---|---|
| External requirements | Require proxy signal mapping; one FSM covers multiple ISO boundaries | Map directly to module port signals |
| Derived requirements (CRC, stuffing) | Discrete `gen_crc` and `can_stuff_bit_gen` modules allow isolated testing | Discrete `bit_stuffer` modules; CRC in `crc_fd.vhd` |
| TX/RX isolation | Not possible at module level; only at top-level with stimulus control | Structural — TX modules have no RX logic |
| FCE boundary observability | Proxy only: `ns_o` (2-bit node state), `debug_error_flag_o` (3-bit) | Not yet implemented |
| Layer boundary signals | Implicit in FSM state and wire names | Explicit typed interfaces (`polarity_t`, Avalon-ST) |
