# Canonical CAN Layer Interfaces (ISO 11898-1:2015)

> **Important**: These interfaces are the **canonical, ISO-defined** service boundaries.
> The actual VHDL implementation may use different signal names, encodings, or handshaking
> mechanisms. Observability classifications in the verification plan are defined **relative
> to these canonical interfaces**, not the implementation.

---

## Layer Model Overview

```
┌─────────────────────────────────────────────┐
│             LLC User (Application)          │
└──────────────┬──────────────────────────────┘
               │  L_Data.Request / .AbortRequest
               │  L_Data.Confirm / .Indication
┌──────────────▼──────────────────────────────┐
│           LLC Sub-layer                     │◄──── FCE (Normal_mode)
└──────────────┬──────────────────────────────┘
               │  LLC frame (SDU) + Handle
               │  Transfer_Status + Timestamp
┌──────────────▼──────────────────────────────┐
│           MAC Sub-layer                     │◄──── FCE (Error_passive/active)
└──────────────┬──────────────────────────────┘
               │  PCS_Data.Request(Output_Unit)
               │  PCS_Data.Indicate(Input_Unit)
               │  PCS_Status.Transmitter(D_Transmit)
               │  PCS_Status.Receiver(D_Receive)
               │  PCS_Mode.Request(XL_Mode)  [XL only]
┌──────────────▼──────────────────────────────┐
│           PCS Sub-layer                     │◄──── FCE (Bus_off/release)
└──────────────┬──────────────────────────────┘
               │  Output/Input/Mode/D_Transmit/D_Receive/Bus_off Symbols
┌──────────────▼──────────────────────────────┐
│           PMA Sub-layer                     │
└──────────────┬──────────────────────────────┘
               │  Physical medium (bus wire)
```

---

## Interface Definitions

### 1. LLC ↔ LLC User (Application Boundary)

**Reference**: ISO 11898-1:2015 §6.4.5

| Primitive | Direction | Parameters | Description |
|---|---|---|---|
| `L_Data.Request` | User → LLC | `Frame`, `Handle` | Initiate frame transmission |
| `L_Data.AbortRequest` | User → LLC | `Handle` | Abort pending transmission |
| `L_Data.Confirm` | LLC → User | `Transfer_Status`, `Timestamp`, `Handle` | Result of transmission request |
| `L_Data.Indication` | LLC → User | `Frame`, `Timestamp` | Notify received frame |

**Parameters:**

| Parameter | Values | Description |
|---|---|---|
| `Frame` | struct | ID, Format, FTYP, BRS, ESI, DLC, data payload |
| `Transfer_Status` | `Ongoing`, `Lost_Arbitration`, `Transmitted`, `Aborted`, `Disturbed` | Outcome of transmission |
| `Timestamp` | 64-bit value | Captured at SOF sample point for both TX and RX frames |
| `Handle` | identifier | Identifies the LLC storage unit (buffer) |

---

### 2. LLC ↔ MAC (DLL Internal Boundary)

**Reference**: ISO 11898-1:2015 §6.3, §6.6

> **Note**: ISO does not define explicit named service primitives for the LLC↔MAC
> internal boundary. The interface is described functionally:

| Direction | Content | Description |
|---|---|---|
| LLC → MAC | LLC frame (SDU) + `Handle` | Frame handed down for encapsulation and transmission |
| MAC → LLC | `Transfer_Status` + `Timestamp` + `Handle` | Result of MAC-level transmission |
| MAC → LLC | Received LLC frame + `Timestamp` | Delivered after successful reception and de-capsulation |

The MAC layer adds all MAC-specific fields (SOF, stuffing, CRC, ACK, EOF) and strips them on reception before returning the LLC frame upward.

---

### 3. MAC ↔ PCS (Physical Layer Boundary)

**Reference**: ISO 11898-1:2015 §7.2

This is the primary layer boundary for physical coding verification. All bit-level
transmission and reception crosses this interface as discrete symbols.

| Primitive | Direction | Parameters | Description |
|---|---|---|---|
| `PCS_Data.Request` | MAC → PCS | `Output_Unit` | Request transmission of one bit |
| `PCS_Data.Indicate` | PCS → MAC | `Input_Unit` | Deliver one received bit to MAC |
| `PCS_Status.Transmitter` | MAC → PCS | `D_Transmit` | Signal FD/XL data phase transmit active |
| `PCS_Status.Receiver` | MAC → PCS | `D_Receive` | Signal FD/XL data phase receive active |
| `PCS_Mode.Request` | MAC → PCS | `XL_Mode` | Enable XL transceiver mode (XL only) |

**Parameters:**

| Parameter | Values | Description |
|---|---|---|
| `Output_Unit` | `dominant`, `recessive` | Bit to transmit |
| `Input_Unit` | `dominant`, `recessive` | Bit received from bus |
| `D_Transmit` | `active`, `passive` | Whether FD/XL data phase is being transmitted |
| `D_Receive` | `active`, `passive` | Whether FD/XL data phase is being received |
| `XL_Mode` | `active`, `passive` | XL transceiver mode selection |

> **Key observability note**: The *timing* of `PCS_Data.Indicate` — i.e., *when* within
> the bit time it fires — is the sample point. Although this timing is not a named
> parameter of the primitive, it is fully determined by the PCS configuration generics
> (see "PCS Configurable Values" below) and is therefore externally observable and
> verifiable by a testbench that knows those generics.
>
> **Information Processing Time (IPT)**: IPT is the time from `PCS_Data.Indicate` firing
> (end of Phase_Seg1) to MAC issuing `PCS_Data.Request(Output_Unit)` for the next bit.
> It is the MAC's computation latency — not a PCS-internal quantity. Both events are
> named primitives at this boundary, so IPT is directly measurable as the delta between
> them (Rule 1a). The ISO constraint "IPT ≤ 2 t_q" is therefore an **external**
> observable at the MAC↔PCS boundary, not a PCS-internal structural constraint.

> **D_Transmit / D_Receive**: ISO notes these are not mandatory for CC/FD nodes, but
> both are **in scope** for this project's FD implementation. `D_Transmit` signals when
> the FD data phase bit rate is active (BRS = recessive), which the PCS needs for bit
> timing switching and TDC activation.

---

### 4. PCS ↔ PMA (Physical Medium Attachment Boundary)

**Reference**: ISO 11898-1:2015 §7.4

| Symbol | Direction | Triggered by | Effect |
|---|---|---|---|
| `Output` | PCS → PMA | `PCS_Data.Request` from MAC | Transmit `level_0` (dominant) or `level_1` (recessive) on medium |
| `Input` | PMA → PCS | Bus level change | Deliver `level_0`/`level_1` received from medium to PCS |
| `Bus_off` | PCS → PMA | `bus_off_request` from FCE | Switch node off from bus |
| `Bus_off_release` | PCS → PMA | `bus_off_release_request` from FCE | Return node to normal operation |
| `Mode` | PCS → PMA | `XL_Mode` from MAC | Select CAN transceiver mode switching enabled/disabled |
| `D_Transmit` | PCS → PMA | `D_Transmit` from MAC | Signal data TX mode to transceiver |
| `D_Receive` | PCS → PMA | `D_Receive` from MAC | Signal data RX mode to transceiver |

> **Note**: ISO notes `D_Transmit` and `D_Receive` symbols to PMA are not mandatory for
> CC/FD nodes, but both are **in scope** for this project.

---

### 5. MAC ↔ FCE (Fault Confinement Entity)

**Reference**: ISO 11898-1:2015 §8.1.3, Table 16–17

| Direction | Service | Description |
|---|---|---|
| MAC → FCE | `Transmit/Receive` | Current transfer mode |
| MAC → FCE | `Error(type)` | Error detected: `bit`, `stuff`, `CRC`, `form`, or `ACK` |
| MAC → FCE | `Primary_error` | Dominant bit after error flag (not an echo) |
| MAC → FCE | `Error/Overload_flag` | Currently transmitting error or overload flag |
| MAC → FCE | `Counters_unchanged` | Special case: FCE counters must not change |
| MAC → FCE | `Error_delimiter_too_late` | 8+ consecutive dominant bits after error flag |
| MAC → FCE | `Successful_transfer` | Transmission or reception completed successfully |
| MAC → FCE | `Error_passive_response` | Node has entered error-passive state |
| MAC → FCE | `Error_active_response` | Node has returned to error-active state |
| FCE → MAC | `Error_passive_request` | Node shall enter error-passive state |
| FCE → MAC | `Error_active_request` | Node shall return to error-active state |

---

### 6. LLC ↔ FCE

**Reference**: ISO 11898-1:2015 §8.1.3, Table 14–15

| Direction | Service | Description |
|---|---|---|
| LLC → FCE | `Normal_mode_request` | Reset FCE to initial state (clear TX/RX error counters) |
| FCE → LLC | `Normal_mode_response` | Acknowledgement of reset |
| FCE → LLC | `Bus_off` | Node has entered bus-off state |

---

### 7. PCS ↔ FCE

**Reference**: ISO 11898-1:2015 §8.1.3, Table 18–19

| Direction | Service | Description |
|---|---|---|
| PCS → FCE | `Bus_off_request` | Request to disconnect node from bus |
| PCS → FCE | `Bus_off_release_request` | Request to reconnect node to bus |
| FCE → PCS | `Bus_off_response` | Acknowledgement of bus-off |
| FCE → PCS | `Bus_off_release_response` | Acknowledgement of bus-off release |

---

## Configurable Values by Layer

> **Scope**: CC and FD frames only (CB, CE, FB, FE). XL parameters are listed where
> they appear in ISO tables but are **out of scope** for this project.
>
> These are the values a testbench knows at instantiation time — either as entity
> generics, constants, or stimulus it drives. A requirement whose postcondition is
> fully determined by these values plus the driven stimulus is **externally verifiable**.

### LLC Configurable Values

**Reference**: ISO 11898-1:2015 §6.4.5, §6.5

These are the parameters the LLC user sets per-frame or per-node.

| Parameter | Description | Notes |
|---|---|---|
| `frame.id` | 11-bit base ID (+ 18-bit extension for CE/FE) | Part of LLC frame SDU |
| `frame.format` | CBFF, CEFF, FBFF, FEFF | Determines MAC frame structure |
| `frame.ftyp` | Frame type: data frame or remote frame | |
| `frame.brs` | Bit Rate Switch flag (FD only) | |
| `frame.esi` | Error State Indicator (FD only) | |
| `frame.dlc` | Data Length Code (0–15; 0–64 bytes for FD) | |
| `frame.data` | Payload bytes | Up to 8 bytes (CC) or 64 bytes (FD) |
| `retransmission_limit` | Max retransmit attempts: 0 to unlimited | Per §6.5.3 |
| `timestamp_capture_point` | SOF or frame-valid sample point | Per §6.5.7 |

---

### MAC Configurable Values

**Reference**: ISO 11898-1:2015 §6.6

The MAC sub-layer has no independently configurable bit-timing parameters; it consumes
the LLC frame SDU and the PCS service interface. Its only node-level settings are:

| Parameter | Description | Notes |
|---|---|---|
| `error_signalling_enable` | Whether the node transmits error frames | Boolean, per §8.1.1 |
| `retransmission_limit` | Shared with LLC; caps automatic retransmit | Per §6.5.3 |
| `protocol_exception_enable` | Whether FD frames trigger protocol exception handling | Boolean, per §6.6.21 |

---

### PCS Configurable Values

**Reference**: ISO 11898-1:2015 §7.3.3–7.3.4, **Table 12** (FD, no XL — separate prescalers)

> **Table choice**: This project targets CAN FD without XL support. ISO Table 12
> (separate prescaler column) defines the configurable ranges for FD-capable, non-XL
> nodes. Table 13 gives wider ranges for XL-capable nodes and is out of scope.

All time values are in time quanta (t_q = m × t_q,min) unless stated otherwise.
Separate nominal and data bit time configurations exist for FD nodes.

#### Nominal Bit Time (all nodes)

| Parameter | Symbol | Range | Description |
|---|---|---|---|
| Prescaler | `m_nom` | 1 to 32 | Scales t_q,min to t_q |
| Propagation segment | `prop_seg_nom` | 1 to 48 t_q | Compensates bus + node propagation delay |
| Phase buffer segment 1 | `phase_seg1_nom` | 1 to 16 t_q | Lengthened by resynchronisation |
| Phase buffer segment 2 | `phase_seg2_nom` | 2 to 16 t_q | Shortened by resynchronisation |
| Synchronisation jump width | `sjw_nom` | 1 to 16 t_q | Max resync adjustment per bit |

> `sync_seg` is fixed at 1 t_q and is not configurable.

#### FD Data Bit Time (FD nodes only)

| Parameter | Symbol | Range | Description |
|---|---|---|---|
| Prescaler | `m_data` | 1 to 32 (or 1–2 if TDC active) | May equal `m_nom` or be independent |
| Propagation segment | `prop_seg_data` | 0 to 8 t_q | Can be 0 in data phase |
| Phase buffer segment 1 | `phase_seg1_data` | 1 to 8 t_q | |
| Phase buffer segment 2 | `phase_seg2_data` | 2 to 8 t_q | |
| Synchronisation jump width | `sjw_data` | 1 to 8 t_q | |

#### TDC (Transmitter Delay Compensation) — FD nodes

| Parameter | Symbol | Range | Description |
|---|---|---|---|
| TDC enable | `tdc_enable` | Boolean | Whether TDC mechanism is active |
| SSP offset (FD) | `ssp_offset` | 1 to 63 t_q,min | Configurable offset added to measured TX delay |

**SSP position** = measured transmitter delay + `ssp_offset`

The measured delay is hardware-measured (not a generic), but `ssp_offset` is a
known configuration. Together they determine when `PCS_Data.Indicate` fires for
the transmitter's own bit during the FD data phase.

> **Prescaler constraint**: when `tdc_enable = true`, prescaler is restricted to
> `m_data ∈ {1, 2}`.

---

### FCE Configurable Values

**Reference**: ISO 11898-1:2015 §8.1.4

The FCE has no user-configurable parameters in the ISO model. Its behaviour is
entirely determined by the fixed counting rules in §8.1.4.2 and the fixed thresholds:

| Threshold | Value | Effect |
|---|---|---|
| Error-passive limit | 127 | TEC or REC > 127 → node enters error-passive state |
| Bus-off limit | 255 | TEC > 255 → node enters bus-off state |
| Recovery count | 11 recessive bits × 128 sequences | Bus-off → error-active recovery |

> These thresholds are **fixed by the standard**, not configurable. The FCE counting
> rules (increment/decrement amounts) are likewise fixed. There are no generics the
> testbench can set to change FCE behaviour.

---

## Observability Classification Rules

These rules derive observability from the canonical interfaces above. They apply
**per layer** — the DUT is the individual layer module, not the top-level CAN node.

### Rule 1 — External
A requirement is `external` if its postcondition is **fully observable at the layer's
own boundary** in either of these two forms:

**1a — Named parameter**: the postcondition maps directly onto a named parameter of a
canonical service primitive.

*Example*: "MAC shall present `dominant` Output_Unit when transmitting a dominant bit"
→ `Output_Unit` is a named parameter of `PCS_Data.Request` → **external**

**1b — Predictable timing**: the postcondition manifests as the *timing* of a primitive
call, and that timing is completely determined by configuration generics and stimulus
inputs that are both known to the testbench.

*Example*: "Sample point shall be at end of Phase_Seg1" — the sample point is *when*
PCS calls `PCS_Data.Indicate`, and that moment equals `brp × (sync_seg + prop_seg +
phase_seg1)`, all of which are configuration generics → **external**

*Example*: "SSP position is TDC_offset + measured_delay" — TDC_offset is a
configuration generic; timing of `PCS_Data.Indicate` is directly verifiable → **external**

*Example*: "Hard synchronization shall adjust bit timing by the phase error" — edge
position is known from stimulus; SJW is a configuration generic; resulting shift in
`PCS_Data.Indicate` timing is fully computable → **external**

### Rule 2 — Derived
A requirement is `derived` if its effect **does** manifest at the layer boundary, but
verifying it requires knowledge of a **non-trivial internal algorithm** — one that goes
beyond reading configuration generics and measuring timing.

> **Trivial vs. non-trivial**: Rules that require only counting stimulus bits or applying
> fixed positional offsets from configuration are considered trivial (→ Rule 1b). Rules
> requiring polynomial computation, state-dependent counter arithmetic, or multi-step
> protocol state tracking are non-trivial (→ Rule 2).

*Example*: CRC correctness — the CRC bits appear in `Output_Unit` calls but you must
know the specific polynomial and apply it to the data to verify the content → **derived**

*Example*: FCE error counter rules — counter values are internal, but each rule drives
when `Error_passive_request` / `Error_active_request` fires at the FCE→MAC boundary.
Verifying requires constructing a specific error sequence and cross-referencing the
counting rules → **derived**

### Rule 3 — Internal
A requirement is `internal` if its postcondition:
- Describes a **structural definition** or **naming of a concept** with no behavioral
  output (e.g., "the bit time consists of four segments"), **or**
- Is a **constraint on valid configuration inputs** rather than on observable output
  behaviour (e.g., "Phase_Seg2 shall be ≥ IPT + SJW"), **or**
- Has **no manifestation at any layer boundary**, even indirectly.

*Example*: "There shall be one prescaler for the three bit time configurations"
→ internal hardware architecture decision, no observable boundary effect → **internal**

*Example*: "Phase_Seg2 shall be ≥ IPT + SJW in data bit time"
→ constrains what constitutes a *valid* configuration, not what the layer outputs
for a given valid configuration → **internal**

---

## Scope Note

CAN XL is **out of scope** for this project. `XL_Mode`, `PCS_Mode.Request`, and all
XL-specific services are listed here for completeness only and shall not appear in
the verification plan.
