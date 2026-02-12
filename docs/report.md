# CAN Bus Implementation Report

## Overview

This document outlines the architecture and implementation of a CAN (Controller Area Network)
bus transmitter following the ISO 11898-1:2015 standard. The implementation includes the
MAC layer serializer, bit stuffing logic, and CRC calculation for both CAN 2.0 and CAN-FD
protocols.

## CAN Stack Architecture

The CAN implementation is organized into distinct layers following the ISO/OSI model:

```mermaid
%%{init: {'flowchart': {'curve': 'linear'}, 'elk': {'algorithm': 'layered'}}}%%
graph TD
   subgraph APP["🔧 Application Layer"]
      AppLogic["Application<br/>Logic"]
   end

   subgraph LLC["📋 Logical Link Control"]
      LLCCtrl["LLC Controller"]
      FrameBuild["Frame Builder"]
      LLCCtrl --> FrameBuild
   end

   subgraph MAC["🏗️ MAC Layer"]
      TXMAC["TX MAC Serializer"]
      FSM["Finite State Machine"]
      BitShift["Bit Shifter Register"]
      TXMAC --> FSM
      FSM --> BitShift
   end

   subgraph ENC["🔐 Encoding & Protection"]
      BitStuff["Bit Stuffing<br/>5-in-a-row Rule"]
      CRC["CRC Calculator<br/>Polynomial"]
      ACKGen["ACK Generator"]
      BitStuff --> CRC
      CRC --> ACKGen
   end

   subgraph PHY["📡 Physical Layer"]
      PHYDriver["Physical Driver"]
      BusInterface["CAN Bus<br/>Interface"]
      PHYDriver --> BusInterface
   end

   AppLogic -->|Frame Data| LLCCtrl
   FrameBuild -->|Formatted Frame| TXMAC
   BitShift -->|Serial Bits| BitStuff
   ACKGen -->|Frame with ACK| PHYDriver
   BusInterface -->|Bit Stream| Network["CAN Bus"]

   style APP fill:#e3f2fd
   style LLC fill:#f3e5f5
   style MAC fill:#fff3e0
   style ENC fill:#e8f5e9
   style PHY fill:#fce4ec
```

## Layer Descriptions

### Application Layer

The application layer contains the business logic that generates CAN frames and processes
incoming messages. It interfaces with the LLC layer through well-defined frame structures.

### Logical Link Control (LLC)

The LLC layer is responsible for:
- Frame type selection (data/remote frames)
- Format selection (CAN 2.0 basic/extended, CAN-FD)
- Configuration of frame parameters (DLC, flags, identifiers)
- Passing formatted frames to the MAC layer

### MAC Layer (Media Access Control)

The MAC layer handles:
- **TX MAC Serializer** (`tx_mac_ser.vhd`): Converts 8-bit words into serial bit stream
- **FSM Controller** (`tx_mac_fsm.vhd`): Manages transmission state machine
- **Bit Shifter**: Implements shift register for bit-by-bit transmission

### Encoding & Protection Layer

This layer ensures data integrity through:
- **Bit Stuffing** (`bit_stuffer.vhd`, `bit_stuffer_fd.vhd`): Inserts stuff bits after 5
  consecutive bits of same polarity per ISO 11898-1 Section 8.5.2
- **CRC Calculation** (`crc_fd.vhd`): Computes polynomial-based CRC (15-bit for CAN 2.0,
  17/21-bit for CAN-FD)
- **ACK Generation**: Encodes acknowledgment slot (1 recessive bit expected from receivers)

### Physical Layer

The physical layer provides:
- Driver circuitry for CAN bus signaling
- Dominant (0V, high current) and recessive (pull-up, low current) states
- Interface to the actual CAN bus transmission medium

## Key Implementation Details

### Frame Structure (ISO 11898-1 Section 8.2)

- **SOF**: Start of Frame (1 bit, dominant)
- **Arbitration Field**: ID (11/29 bits) + RTR + IDE
- **Control Field**: Reserved bits + DLC + FD flags (CAN-FD only)
- **Data Field**: 0-64 bytes (0-512 bits)
- **CRC Field**: 15-21 bits + delimiter
- **ACK Field**: 1 bit slot + delimiter
- **EOF**: End of Frame (7 bits, recessive)

### Bit Stuffing Algorithm (ISO 11898-1 Section 8.5.4)

After 5 consecutive bits of the same polarity, a complementary stuff bit is inserted:
- **CAN 2.0**: Dynamic stuffing throughout frame (except CRC delimiter onwards)
- **CAN-FD**: Fixed stuff bits at predefined positions in payload

### CRC Polynomials

- **CAN 2.0**: x^15 + x^14 + x^10 + x^8 + x^7 + x^4 + x^3 + 1 (0xC599)
- **CAN-FD 17-bit**: High bandwidth CRC
- **CAN-FD 21-bit**: Maximum protection CRC

## Testing Strategy

Comprehensive testing includes:
- Unit tests for each layer component
- Integration tests for full frame transmission
- Edge case testing (min/max DLC, various frame types)
- Bit stuffing validation with various bit patterns
- CRC correctness verification against reference implementations

## Compliance

This implementation strictly adheres to:
- **ISO 11898-1:2015** - CAN Data Link Layer and Physical Signaling
- **CAN 2.0 Specification** - Classical CAN protocol
- **CAN-FD Protocol** - Flexible Data Rate extensions

For detailed protocol specifications, refer to `ISO_11898_1_CAN_bus_link.pdf`.

## MAC Frame Bit Generation (`get_next_mac_frame_bit`)

The core function responsible for generating each MAC frame bit follows a hierarchical decision flow:

```mermaid
---
title: "MAC Frame Bit Generation Flow"
---
%%{init: {'flowchart': {'curve': 'linear'}, 'elk': {'algorithm': 'layered'}}}%%
stateDiagram-v2
  state check_stuff_state <<choice>>
  state select_fmt <<choice>>
  state route_bit <<choice>>
  state check_crc <<choice>>

  state "Stuff Bit Valid?" as check_stuff
  state "Return Stuff Bit" as ret_stuff
  state "Get Frame Format" as extract
  state "Calculate CC Basic specific bit positions" as setup_ccb
  state "Calculate CC Extended specific bit positions" as setup_cce
  state "Calculate FD Basic specific bit positions" as setup_fdb
  state "Calculate FD Extended specific bit positions" as setup_fde
  state "Calculate next bit type" as calc_pos
  state "Return SOF bit" as ret_sof
  state "Return next arbitration bit" as ret_arb
  state "Return next control bit" as ret_ctrl
  state "Return next DLC bit" as ret_dlc
  state "Return next data bit" as ret_data
  state "Return next fixed ftuff bit" as ret_fixed
  state "Return next SBC bit" as ret_sbc
  state "Return next CRC bit" as ret_crc
  state "Return next delimiter bit" as ret_delim
  state "Return next EOF bit" as ret_eof

  [*] --> check_stuff

  check_stuff --> check_stuff_state

  check_stuff_state --> ret_stuff: valid
  check_stuff_state --> extract: invalid

  ret_stuff --> [*]

  extract --> select_fmt

  select_fmt --> setup_ccb: cc_basic
  select_fmt --> setup_cce: cc_extended
  select_fmt --> setup_fdb: fd_basic
  select_fmt --> setup_fde: fd_extended

  setup_ccb --> calc_pos
  setup_cce --> calc_pos
  setup_fdb --> calc_pos
  setup_fde --> calc_pos

  calc_pos --> route_bit

  route_bit --> ret_sof: sof
  route_bit --> ret_arb: arbitration
  route_bit --> ret_ctrl: control
  route_bit --> ret_dlc: dlc
  route_bit --> ret_data: data
  route_bit --> check_crc: crc
  route_bit --> ret_delim: delim
  route_bit --> ret_eof: eof

  check_crc --> ret_fixed: fixed
  check_crc --> ret_sbc: sbc
  check_crc --> ret_crc: crc

  ret_sof --> [*]
  ret_arb --> [*]
  ret_ctrl --> [*]
  ret_dlc --> [*]
  ret_data --> [*]
  ret_fixed --> [*]
  ret_sbc --> [*]
  ret_crc --> [*]
  ret_delim --> [*]
  ret_eof --> [*]
```

### Function Algorithm

The `get_next_mac_frame_bit` function generates the next bit in a CAN frame transmission. Key stages:

1. **Stuff Bit Priority** (Line 780-783): Checks if the bit stuffer has a valid stuff bit to insert.
   If yes, returns immediately with the complementary polarity.

2. **Frame Format Setup** (Line 797-891): Based on frame format (CAN Classic basic/extended or CAN FD
   basic/extended), loads format-specific bit positions and control field constants.

3. **Field Position Calculation** (Line 897-915): Calculates the position of each frame section:
   - Data field start/stop
   - CRC field start
   - SBC field (CAN FD only)
   - Fixed stuff bit positions (CAN FD only)
   - ACK and EOF positions

4. **Field Determination** (Line 920-996): Uses a cascading if-elsif chain to determine which field
   the current `bit_count` belongs to:
   - **SOF**: Always dominant (line 920-921)
   - **Arbitration**: Base ID bits + optional extended ID (line 923-939)
   - **Control**: Format flags (RTR, SRR, IDE, R0, R1, FDF, RES, BRS, ESI) with frame-dependent polarities
   - **DLC**: 4-bit data length code (line 954-957)
   - **Data**: 0-512 bits of user payload (line 960-962)
   - **CRC**: 15-21 bit CRC value with optional SBC and fixed stuff bits (line 965-982)
   - **Delimiters & ACK**: CRC/ACK delimiters and ACK slot (recessive) (line 983-990)
   - **EOF**: 7 recessive bits (line 993-994)

5. **Polarity Extraction**: Extracts actual bit polarity from:
   - **Input data**: Frame data for ID/data fields (via `mac_ser_to_fsm.data`)
   - **DLC vector**: DLC field bits
   - **CRC vector**: CRC field bits
   - **SBC vector**: Sequence Bit Count field (CAN FD)
   - **Previous polarity**: For fixed stuff bits (opposite of previous)
   - **Constants**: For fixed-polarity bits (SOF, delimiters, format flags)

## CAN Frame Structure Visualization

### CAN Classic Basic Frame (ISO 11898-1 Section 8.2)

```mermaid
---
title: "CAN Classic Basic Data Frame (max 8 bytes)"
---
packet
0: "SOF"
1-11: "Base ID (11 bits)"
12: "RTR"
13: "IDE"
14: "R0"
15-18: "DLC (4 bits)"
19-82: "Data Payload (0-8 bytes)"
83-97: "CRC (15 bits)"
98: "CRC Delim"
99: "ACK Slot"
100: "ACK Delim"
101-107: "EOF (7 bits)"
```

### CAN Classic Extended Frame (ISO 11898-1 Section 8.2)

```mermaid
---
title: "CAN Classic Extended Data Frame (max 8 bytes)"
---
packet
0: "SOF"
1-11: "Base ID (11 bits)"
12: "SRR"
13: "IDE"
14-31: "Extended ID (18 bits)"
32: "RTR"
33: "R1"
34: "R0"
35-38: "DLC (4 bits)"
39-102: "Data Payload (0-8 bytes)"
103-117: "CRC (15 bits)"
118: "CRC Delim"
119: "ACK Slot"
120: "ACK Delim"
121-127: "EOF (7 bits)"
```

### CAN FD Basic Frame (ISO 11898-1 Section 8.4)

```mermaid
---
title: "CAN FD Basic Data Frame (max 64 bytes)"
---
packet
0: "SOF"
1-11: "Base ID (11 bits)"
12: "RRS"
13: "IDE"
14: "FDF"
15: "RES"
16: "BRS"
17: "ESI"
18-21: "DLC (4 bits)"
22-533: "Data Payload (0-64 bytes)"
534-537: "SBC (4 bits)"
538-558: "CRC (17/21 bits)"
559: "CRC Delim"
560: "ACK Slot"
561: "ACK Delim"
562-568: "EOF (7 bits)"
```

## TX Monitoring and Error Detection (`get_observed_mac_frame_bit_info`)

The core monitoring function that detects transmission errors, ACK issues, and arbitration loss by comparing expected vs. observed bit polarities:

```mermaid
---
title: "TX Bit Monitoring and Error Detection"
---
%%{init: {'flowchart': {'curve': 'linear'}, 'elk': {'algorithm': 'layered'}}}%%
stateDiagram-v2
  state check_ack <<choice>>
  state check_polarity <<choice>>
  state resolve_error <<choice>>

  state "Initialize result" as init_result
  state "Get FIFO bit and monitored polarity" as get_fifo
  state "Return ACK error" as ret_ack_error
  state "Return ACK detected" as ret_ack_detected
  state "Return no event" as ret_no_event
  state "Set transfer status disturbed" as set_disturbed
  state "Determine arbitration bit by frame format" as determine_format
  state "Return bit error" as ret_bit_error
  state "Return lost arbitration error" as ret_lost_arb

  [*] --> init_result

  init_result --> get_fifo

  get_fifo --> check_ack

  check_ack --> ret_ack_error: monitored recessive
  check_ack --> ret_ack_detected: monitored not recessive
  check_ack --> check_polarity: not ACK bit

  ret_ack_error --> [*]
  ret_ack_detected --> [*]

  check_polarity --> ret_no_event: polarities match
  check_polarity --> set_disturbed: polarities mismatch

  ret_no_event --> [*]

  set_disturbed --> determine_format

  determine_format --> resolve_error

  resolve_error --> ret_bit_error: arbitration + dominant transmitted
  resolve_error --> ret_lost_arb: arbitration + recessive transmitted
  resolve_error --> ret_bit_error: non-arbitration + mismatch

  ret_bit_error --> [*]
  ret_lost_arb --> [*]
```

### Function Algorithm

The `get_observed_mac_frame_bit_info` function monitors transmitted bits for errors (ISO 11898-1: 6.6.21.2). Key stages:

1. **Initialization** (Line 448-449): Set event_type to `none` and transfer_status to `ongoing`.

2. **Get FIFO Entry** (Line 452-454): Extract the transmitted bit at the specified delay from FIFO and capture observed polarity.

3. **ACK Bit Detection** (Line 457-466): Highest priority check - if transmitted bit is ACK:
   - Monitored polarity = recessive? → ACK error, disturbed status, return
   - Monitored polarity ≠ recessive? → ACK detected, transmitted status, return

4. **Polarity Match Check** (Line 469-474): If polarities match → no event detected, return with ongoing status. Otherwise, set transfer_status to `disturbed` and continue.

5. **Arbitration Phase Determination** (Line 477-497): Based on frame format, determine if this bit is in arbitration phase:
   - **CC Basic**: Base ID bits or RTR bit
   - **CC Extended**: Base ID, SRR, IDE, Extended ID, or RTR bits
   - **FD Basic**: Base ID or RRS bits
   - **FD Extended**: Base ID, SRR, IDE, or Extended ID bits

6. **Event Type Resolution** (Line 500-512): With polarity mismatch confirmed:
   - If arbitration bit:
     - Transmitted dominant, observed recessive → bit_error
     - Transmitted recessive, observed dominant → lost_arbitration (transfer_status = lost_arbitration)
   - If non-arbitration bit:
     - Any mismatch → bit_error

## Future Work

- [ ] Remote frame transmission support (Section 8.3)
- [ ] Error frame handling (Section 8.6)
- [ ] Receiver implementation (RX path)
- [ ] Arbitration logic for multi-master scenarios
- [ ] Timing analysis and synchronization
