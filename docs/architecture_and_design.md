# CAN Bus Implementation Report

<!-- mtoc-start -->

- [1. Overview](#1-overview)
- [2. Current TX Architecture](#2-current-tx-architecture)
- [3. Interface Summary](#3-interface-summary)
  - [3.1 LLC User <-> LLC](#31-llc-user---llc)
  - [3.2 LLC <-> MAC](#32-llc---mac)
  - [3.3 MAC <-> PCS](#33-mac---pcs)
- [4. LLC Frame Format (User Stream and LLC->MAC Stream)](#4-llc-frame-format-user-stream-and-llc-mac-stream)
- [5. MAC Frame Format (Logical CAN Bitstream)](#5-mac-frame-format-logical-can-bitstream)
  - [5.1 CAN Classic Base (logical bit fields)](#51-can-classic-base-logical-bit-fields)
  - [5.2 CAN Classic Extended (logical bit fields)](#52-can-classic-extended-logical-bit-fields)
  - [5.3 CAN FD Base (logical bit fields)](#53-can-fd-base-logical-bit-fields)
  - [5.4 CAN FD Extended (logical bit fields)](#54-can-fd-extended-logical-bit-fields)
- [6. State Diagrams](#6-state-diagrams)
  - [6.1 `tx_llc` FSM](#61-tx_llc-fsm)
  - [6.2 `tx_mac_ser` FSM](#62-tx_mac_ser-fsm)
  - [6.3 `tx_mac_fsm` FSM](#63-tx_mac_fsm-fsm)
  - [6.4 `tx_pcs` FSM](#64-tx_pcs-fsm)
- [7. Verification Status](#7-verification-status)
- [8. Known Gaps / Next Steps](#8-known-gaps--next-steps)

<!-- mtoc-end -->

## 1. Overview

This report summarizes the current TX-side CAN/CAN-FD implementation status in this repository.
The design targets ISO 11898-1 behavior for the transmitter pipeline:

`LLC user -> tx_llc -> tx_mac (serializer + FSM + CRC + stuffer) -> tx_pcs -> bus`

The codebase is VHDL-2008 and uses GHDL + OSVVM for simulation.

## 2. Current TX Architecture

Diagram level: `L3`

```mermaid
flowchart LR
  U["LLC User (Avalon-ST Source)"]
  L["tx_llc<br/>(frame capture + replay)"]
  S["tx_mac_ser<br/>(byte->bit serializer + frame_params decode)"]
  F["tx_mac_fsm<br/>arbitration/monitoring/error signaling"]
  P["tx_pcs<br/>bit timing + TDC + sample_strobe"]
  B["CAN Bus"]

  U --> L
  L --> S
  S --> F
  F --> P
  P --> B
  B --> P
```

## 3. Interface Summary

### 3.1 LLC User <-> LLC

- `llc_user_to_llc_if_t` now uses:
  - `avalon_st_source` (`data`, `valid`, `sop`, `eop`)
  - `abort_request`
- `llc_to_llc_user_if_t` now uses:
  - `avalon_st_sink.ready`
  - `transfer_status`

This aligns the external user boundary with the same stream concept used inside LLC->MAC.

### 3.2 LLC <-> MAC

- Avalon-ST stream: bytes buffered by `tx_llc`, replayed to `tx_mac_ser`.
- MAC returns:
  - backpressure (`ready`)
  - transfer result (`ongoing`, `transmitted`, `disturbed`, `lost_arbitration`, `aborted`)

### 3.3 MAC <-> PCS

- MAC drives bit intent (`mac_frame_bit_t`) and `valid`.
- PCS returns:
  - observed `bus_polarity`
  - effective `sample_strobe`
  - effective `fifo_index` for delayed comparison.

## 4. LLC Frame Format (User Stream and LLC->MAC Stream)

The canonical LLC stream format is byte oriented with:

- mandatory 6-byte header (`CFG0`, `CFG1`, `ID3`, `ID2`, `ID1`, `ID0`)
- optional payload (`0..64` data bytes)

LLC frame packet layout (fixed byte chunks, max FD envelope):

```mermaid
packet
+1: "C0"
+1: "C1"
+1: "ID0"
+1: "ID1"
+1: "ID2"
+1: "ID3"
+64: "D(0), ... D(63)"
```

Legend: base-ID formats use `ID1:ID0`; extended-ID formats use `ID3:ID0`.

<a id="cfg0"></a>

| b7        | b6        | b5        | b4   | b3  | b2  | b1       | b0       |
| --------- | --------- | --------- | ---- | --- | --- | -------- | -------- |
| FORMAT[2] | FORMAT[1] | FORMAT[0] | FTYP | ESI | BRS | Reserved | Reserved |

**Table 1**: Config Byte 0 bit layout (MSB-left, b7 to b0)

<a id="cfg1"></a>

`Config Byte 1` bit layout (MSB-left, `b7` to `b0`):

| b7     | b6     | b5     | b4     | b3       | b2       | b1       | b0       |
| ------ | ------ | ------ | ------ | -------- | -------- | -------- | -------- |
| DLC[3] | DLC[2] | DLC[1] | DLC[0] | Reserved | Reserved | Reserved | Reserved |

**Table 2**: Config Byte 1 bit layout (MSB-left, b7 to b0)

Notes:

- `sop='1'` on Config Byte 0.
- The first 6 bytes are always present in every LLC frame.
- `eop='1'` on final data byte, or on `ID0` when `DLC=0`.
- `tx_llc` captures the full stream, then replays the same bytes for retries/re-arbitration.

## 5. MAC Frame Format (Logical CAN Bitstream)

The MAC/FSM emits the logical CAN frame using `frame_params` computed from the two config bytes.

Bit-name polarity table (TX intent, shared across diagrams):

| Bit Class                                        | Polarity  | Notes                                                   |
| :----------------------------------------------- | :-------- | :------------------------------------------------------ |
| EOF, CRCD, ACKD, SRR, FDF, ACK                   | Recessive | Protocol fixed recessive bits and the TX-side ACK slot. |
| SOF, RES, R0, R1                                 | Dominant  | Protocol fixed dominant bits (includes reserved bits).  |
| IDE, RTR/RRS, BRS, ESI, BID, DLC, DATA, CRC, SBC | Dependent | Determined by frame format, configuration, or payload.  |

Use the table above for polarity semantics; packet diagrams below show field order and width only.

### 5.1 CAN Classic Base (logical bit fields)

Diagram level: `L3`

```mermaid
packet
0: "SOF"
1-11: "BID11"
12: "RTR"
13: "IDE"
14: "R0"
15-18: "DLC"
19-82: "DATA (max span)"
83-97: "CRC15"
98: "CRCD"
99: "ACK"
100: "ACKD"
101-107: "EOF"
```

Legend: `BID11` = 11-bit base identifier, `CRCD` = CRC delimiter, `ACKD` = ACK delimiter.

### 5.2 CAN Classic Extended (logical bit fields)

Diagram level: `L3`

```mermaid
packet
0: "SOF"
1-11: "BID11"
12: "SRR"
13: "IDE"
14-31: "EID18"
32: "RTR"
33: "R1"
34: "R0"
35-38: "DLC"
39-102: "DATA (max span)"
103-117: "CRC15"
118: "CRCD"
119: "ACK"
120: "ACKD"
121-127: "EOF"
```

Legend: `BID11` = 11-bit base identifier, `EID18` = 18-bit extended identifier, `SRR` = substitute remote request, `CRCD` = CRC delimiter, `ACKD` = ACK delimiter.

### 5.3 CAN FD Base (logical bit fields)

Diagram level: `L3`

```mermaid
packet
0: "SOF"
1-11: "BID11"
12: "RRS"
13: "IDE"
14: "FDF"
15: "RES"
16: "BRS"
17: "ESI"
18-21: "DLC"
22-533: "DATA (max span)"
534-554: "SBC+CRC (span)"
555: "CRCD"
556: "ACK"
557: "ACKD"
558-564: "EOF"
```

Legend: `BID11` = 11-bit base identifier, `SBC` = stuff-bit counter sequence, `CRCD` = CRC delimiter, `ACKD` = ACK delimiter.

### 5.4 CAN FD Extended (logical bit fields)

Diagram level: `L3`

```mermaid
packet
0: "SOF"
1-11: "BID11"
12: "SRR"
13: "IDE"
14-31: "EID18"
32: "RRS"
33: "FDF"
34: "RES"
35: "BRS"
36: "ESI"
37-40: "DLC"
41-552: "DATA (max span)"
553-573: "SBC+CRC (span)"
574: "CRCD"
575: "ACK"
576: "ACKD"
577-583: "EOF"
```

Legend: `BID11` = 11-bit base identifier, `EID18` = 18-bit extended identifier, `SRR` = substitute remote request, `SBC` = stuff-bit counter sequence, `CRCD` = CRC delimiter, `ACKD` = ACK delimiter.

## 6. State Diagrams

### 6.1 `tx_llc` FSM

Diagram level: `L3`

```mermaid
---
title: "tx_llc FSM"
---
%%{init: {'flowchart': {'curve': 'linear'}, 'elk': {'algorithm': 'layered'}}}%%
stateDiagram-v2
  state idle_start <<choice>>
  state capture_decision <<choice>>
  state result_decision <<choice>>

  state "**Idle**<br/>─────────<br/>• llc_user ready = 1<br/>• Reset capture/tx indices<br/>• Wait for SOP byte" as idle_s
  state "**Capture Frame**<br/>─────────<br/>• llc_user ready = 1<br/>• Buffer incoming bytes<br/>• Abort allowed before MAC start" as capture_s
  state "**Send Frame**<br/>─────────<br/>• Drive buffered Avalon-ST to MAC<br/>• Assert SOP/EOP at first/last byte<br/>• Arm MAC status when ongoing seen" as send_s
  state "**Wait For Result**<br/>─────────<br/>• Wait for terminal MAC status<br/>• Retry or complete based on status<br/>• Enforce retransmission limit" as result_s
  state "**Wait For Idle**<br/>─────────<br/>• Between retry attempts<br/>• Wait for MAC ready<br/>• Abort allowed" as wait_idle_s

  [*] --> idle_s: reset

  idle_s --> idle_start
  idle_start --> capture_s: valid ∧ sop ∧ ¬eop
  idle_start --> send_s: valid ∧ sop ∧ eop

  capture_s --> capture_decision
  capture_decision --> send_s: valid ∧ eop accepted
  capture_decision --> idle_s: abort_request
  capture_decision --> idle_s: capture_index overflow

  send_s --> result_s: last byte accepted by MAC

  result_s --> result_decision
  result_decision --> idle_s: transfer_status = transmitted
  result_decision --> idle_s: transfer_status = aborted
  result_decision --> send_s: transfer_status = lost_arbitration
  result_decision --> wait_idle_s: transfer_status = disturbed ∧ retx_count < retransmission_limit_c
  result_decision --> idle_s: transfer_status = disturbed ∧ retx_count ≥ retransmission_limit_c

  wait_idle_s --> send_s: MAC ready for retry
  wait_idle_s --> idle_s: abort_request
```

### 6.2 `tx_mac_ser` FSM

Diagram level: `L3`

```mermaid
---
title: "tx_mac_ser FSM"
---
%%{init: {'flowchart': {'curve': 'linear'}, 'elk': {'algorithm': 'layered'}}}%%
stateDiagram-v2
  state cfg1_guard <<choice>>
  state shift_guard <<choice>>

  state "**Load Config Byte 0**<br/>─────────<br/>• llc ready = 1<br/>• Wait for valid ∧ sop<br/>• Latch cfg0" as cfg0_s
  state "**Load Config Byte 1**<br/>─────────<br/>• llc ready = 1<br/>• Wait for valid ∧ ¬sop<br/>• Compute frame_params(cfg0,cfg1)" as cfg1_s
  state "**Load LLC Frame Byte**<br/>─────────<br/>• llc ready = 1<br/>• Latch byte into shifter<br/>• Emit MSB immediately (valid=true)" as data_s
  state "**Shift Out Bits**<br/>─────────<br/>• valid = true<br/>• data = shifter MSB<br/>• Shift on fsm.ready" as shift_s

  [*] --> cfg0_s

  cfg0_s --> cfg1_s: valid ∧ sop

  cfg1_s --> cfg1_guard
  cfg1_guard --> data_s: valid ∧ ¬sop
  cfg1_guard --> cfg1_s: valid ∧ sop (resync)

  data_s --> shift_s: valid ∧ ¬sop

  shift_s --> shift_guard
  shift_guard --> data_s: fsm.ready ∧ count = 0
  shift_guard --> cfg0_s: ¬(transfer_status = ongoing)
```

### 6.3 `tx_mac_fsm` FSM

Diagram level: `L3`

```mermaid
---
title: "tx_mac_fsm FSM"
---
%%{init: {'flowchart': {'curve': 'linear'}, 'elk': {'algorithm': 'layered'}}}%%
stateDiagram-v2
  state tx_decision <<choice>>

  state "**Bus Reintegration**<br/>─────────<br/>• pcs_o.valid = false<br/>• Monitor sampled bus recessive run<br/>• transfer_status = ongoing" as reintegration_s
  state "**Bus Idle**<br/>─────────<br/>• pcs_o.valid = false<br/>• Wait for serializer valid<br/>• transfer_status = ongoing" as idle_s
  state "**Intermission**<br/>─────────<br/>• pcs_o.valid = false<br/>• Count intermission samples<br/>• transfer_status = ongoing" as intermission_s
  state "**Suspend Transmission**<br/>─────────<br/>• pcs_o.valid = false<br/>• Hold for suspend window<br/>• transfer_status = ongoing" as suspend_s
  state "**Transmitting Frame**<br/>─────────<br/>• pcs_o.valid = true<br/>• Select CRC polynomial from frame_params<br/>• Emit next frame/stuff bit on sample_strobe<br/>• Monitor ACK/bit/arbitration events" as tx_s
  state "**Transmitting Error Flag**<br/>─────────<br/>• pcs_o.valid = true<br/>• Send active error flag then delimiter<br/>• transfer_status = disturbed" as err_s
  state "**Transmitting Overload Flag**<br/>─────────<br/>• pcs_o.valid = true<br/>• Reserved overload path (kept in type)<br/>• transfer_status = disturbed" as ovl_s

  [*] --> reintegration_s: reset

  reintegration_s --> idle_s: bit_count = bus_idle_condition_width - 1

  idle_s --> tx_s: serializer valid

  tx_s --> tx_decision
  tx_decision --> intermission_s: monitored event = lost_arbitration
  tx_decision --> err_s: monitored event = bit_error
  tx_decision --> err_s: monitored event = ack_error ∧ ¬ack_success_seen
  tx_decision --> intermission_s: bit_count ≥ frame_params.eof_stop ∧ ack_success_seen
  tx_decision --> err_s: bit_count ≥ frame_params.eof_stop ∧ ¬ack_result_known

  err_s --> intermission_s: bit_count ≥ error_flag_width + error_delimiter_width - 1

  ovl_s --> intermission_s: bit_count ≥ error_flag_width + error_delimiter_width - 1
  note right of ovl_s
    No active transition into overload in current RTL.
    State is retained as reserved/placeholder.
  end note

  intermission_s --> suspend_s: bit_count = intermission_width - 1 ∧ fce_i.error_passive ∧ was_previous_frame_tx
  intermission_s --> idle_s: bit_count = intermission_width - 1 ∧ ¬(fce_i.error_passive ∧ was_previous_frame_tx)

  suspend_s --> idle_s: bit_count = suspend_transmission_width - 1
```

### 6.4 `tx_pcs` FSM

Diagram level: `L3`

```mermaid
---
title: "tx_pcs FSM"
---
%%{init: {'flowchart': {'curve': 'linear'}, 'elk': {'algorithm': 'layered'}}}%%
stateDiagram-v2
  state nom_tdc_gate <<choice>>
  state meas_outcome <<choice>>

  state "**Idle**<br/>─────────<br/>• tx path inactive<br/>• Advance nominal timing and wait for frame_active_v<br/>• Latch first bit when frame starts" as idle_s
  state "**Transmitting Nominal**<br/>─────────<br/>• Latch on nominal_bit_boundary_v<br/>• Advance nominal timing each nom_tq_tick<br/>• Monitor contract defaults to SP, fifo_index = 0" as nom_s
  state "**Measuring Delay**<br/>─────────<br/>• Continue nominal timing and nominal-bit latching<br/>• Count TX→RX delay on data_tq_tick<br/>• On rx_dominant_v: latch ssp_position and fifo_index" as meas_s
  state "**Transmitting Data**<br/>─────────<br/>• Latch on data_bit_boundary_v<br/>• Advance data timing each data_tq_tick<br/>• use_tdc_c selects SSP+fifo_index vs SP+0" as data_s

  [*] --> idle_s: reset

  idle_s --> nom_s: frame_active_v

  nom_s --> idle_s: ¬frame_active_v
  nom_s --> nom_tdc_gate
  nom_tdc_gate --> meas_s: is_res_bit_v ∧ use_tdc_c
  nom_tdc_gate --> data_s: is_res_bit_v ∧ ¬use_tdc_c

  meas_s --> idle_s: ¬frame_active_v
  meas_s --> meas_outcome
  meas_outcome --> data_s: rx_dominant_v
  meas_outcome --> nom_s: tdc_timeout_v ∧ ¬rx_dominant_v

  data_s --> idle_s: ¬frame_active_v
  data_s --> nom_s: is_crc_delim_v
```

Guard naming map (from `tx_pcs.next_state_logic`):

- `frame_active_v`: `mac_to_pcs_i.valid`
- `is_res_bit_v`: `current_bit.bit_name = res_bit`
- `rx_dominant_v`: `rx_bus_i = dominant_bit_c`
  ( `tdc_timeout_v`: `delay_count ≥ max_transmitter_delay_c`

- `is_crc_delim_v`: `current_bit.bit_name = crc_delimiter_bit`
  Sequential guard map (from `tx_pcs.pcs_fsm`):

- `entering_measuring_delay_v`: `state /= measuring_delay ∧ next_state = measuring_delay`
- `returning_to_idle_v`: `next_state = idle ∧ state /= idle`
- `nominal_bit_boundary_v`: `nom_tq_tick = '1' ∧ tq_count ≥ nom_bit_time - 1`
- `data_bit_boundary_v`: `data_tq_tick = '1' ∧ tq_count ≥ data_bit_time - 1`

Output register note:

- `sample_strobe` and `fifo_index` are registered in `monitor_output_reg` before driving `pcs_to_mac_o`.

## 7. Verification Status

Current regression status for key benches:

- `tx_pcs_tb`: detailed PCS/TDC checks pass.
- `tx_can_tb`: integrated transmit-path and retry/abort smoke tests pass.
- `tx_can_protocol_tb`: protocol-structure checks (SOF, delimiters, EOF, frame length for CC base/extended) pass.

## 8. Known Gaps / Next Steps

1. Stream payload/content contract should be fully specified in one normative table (including ID carriage policy).
2. `tx_can_protocol_tb` can be extended from structure checks to strict per-field bit-value scoreboarding.
3. If ID carriage is moved into the canonical LLC stream, update serializer/model docs and diagrams accordingly.
