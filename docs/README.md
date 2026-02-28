# Documentation

Reference documentation for the CAN bus implementation thesis project.

## Project Documents

- **Progress Report**: [`report.md`](report.md) - Tracks the project timeline and status.
- **Architecture & Design**: [`architecture_and_design.md`](architecture_and_design.md) - Detailed technical documentation of the implementation.
- **Project Plan**: [`time_plan.md`](time_plan.md) - Overall schedule and milestones.

## ISO 11898-1:2015 Standard

**File**: `ISO_11898_1_CAN_bus_link.pdf`

This is the authoritative specification for the CAN (Controller Area Network)
data link layer and physical signaling. The implementation strictly adheres to
this standard.

### Key Sections Reference

| Section | Topic | Relevance |
| ------- | ----- | --------- |
| 8.1 | CAN Frame Structure Overview | Foundation for frame format design |
| 8.2 | CAN Data Frame Format | SOF, arbitration, control, data, CRC, ACK, EOF |
| 8.3 | CAN Remote Frame Format | Remote transmission request (not implemented) |
| 8.4 | CAN FD Extended Frame Format | CAN-FD extensions (FDF, BRS, ESI bits) |
| 8.5 | Bit Stuffing and Destuffing | 5-in-a-row rule and fixed stuff bits |
| 8.5.2 | Stuff Bit Rules | Definition of when bit stuffing is applied |
| 8.5.4 | CRC Delimiter and ACK Slot | CRC field encoding and acknowledgment |
| 8.5.6 | ACK Slot Encoding | How transmitters detect acknowledgment |
| 8.6 | Error Detection and Handling | Error frame format and conditions |
| 11 | Physical Layer Specification | Bus electrical characteristics (not in HDL) |

### Implementation Mappings

#### CAN Frame Structure (Section 8.2)

Implementation in `src/can_pkg.vhd`:

```text
SOF (1 bit)
  ↓
Arbitration Field (53 bits for basic, 80 bits for extended)
  ├─ Identifier (11 or 29 bits)
  ├─ RTR (1 bit)
  └─ IDE (1 bit)
  ↓
Control Field (6 bits minimum)
  ├─ r0/r1 (2 bits)
  └─ DLC (4 bits)
  ↓
Data Field (0-512 bits, 0-64 bytes)
  ↓
CRC Field (15 or 17 bits + delimiter)
  ↓
ACK Field (2 bits)
  ↓
EOF Field (7 bits)
```

#### Bit Stuffing Rules (Section 8.5.2)

As implemented in `src/bit_stuffer.vhd`:

- **CAN 2.0**: After 5 consecutive bits of same polarity, insert opposite
  polarity bit
- **CAN-FD**: Fixed stuff bits at predefined positions in payload
  (Section 8.5.3)

The `stuff_bit` type in `mac_frame_bit_name_t` enum tracks insertions.

#### CRC Calculation (Section 8.5.4)

CAN uses polynomial-based CRC:

- **CAN 2.0**: 15-bit CRC with polynomial 0xC599
- **CAN-FD**: 17-bit or 21-bit CRC (implementation in `src/crc_fd.vhd`)

Implemented in `can_pkg.vhd` functions:

- `get_crc_vector()`: Computes CRC bits for data
- `get_sbc_vector()`: Computes Sequence Bit Count for CAN-FD stuff bits

### How to Use This Reference

1. **When implementing new modules**: Always consult the relevant ISO 11898-1
   section to understand bit-level requirements
2. **When debugging testbenches**: Cross-check signal sequences against the
   frame format diagrams in Section 8.2
3. **For protocol clarification**: Refer to specific sections cited in code
   comments (e.g., "per ISO 11898-1 Section 8.5.2")
4. **For CAN-FD extensions**: Sections 8.4 and 8.5.3 define CAN-FD specific
   behavior (FDF, BRS, ESI bits, fixed stuffing)

### Compliance Checklist

- [x] Basic CAN frame format (Section 8.2)
- [x] CAN-FD frame format (Section 8.4)
- [x] Bit stuffing rules (Section 8.5.2)
- [x] CRC calculation (Section 8.5.4)
- [x] ACK slot encoding (Section 8.5.6)
- [ ] Remote frame support (Section 8.3) - not implemented
- [ ] Error frame format (Section 8.6) - partially implemented in `tx_mac_err.vhd`
- [ ] Physical layer timing (Section 11) - simulation-only, no electrical constraints

## Building and Compiling

See the main project **CLAUDE.md** for build instructions. The ISO standard
should be referenced whenever:

- Modifying frame structure definitions in `can_pkg.vhd`
- Implementing bit stuffing in `bit_stuffer.vhd` or `bit_stuffer_fd.vhd`
- Creating test vectors in testbenches

## Notes

- The PDF is a 20-page excerpt of the full ISO 11898-1 standard
- Page numbers in code comments refer to this PDF, not the full standard
- For detailed electrical specifications (Section 11), consult the full
  standard or CAN controller datasheets
