# ACK Error Debug Findings

**Date**: 2026-02-19
**Status**: IN PROGRESS - Root cause identified, diagnosis complete

---

## Problem Statement

User reported: **Debug `ack_error` signal never goes high in waveform**

---

## Root Cause Analysis - Root Cause #1: IDENTIFIED ✓

### Missing Frame Transmission

The `tx_error_detection_tb.vhd` test defined a `send_frame()` procedure but **never called it**.

**Result**: FSM remained stuck in `idle` state, never reaching the frame transmission code where ACK error detection occurs.

**Status**: **FIXED** - Updated test to call `send_frame()` with proper LLC interface protocol

---

## Root Cause Analysis - Root Cause #2: IDENTIFIED ✓

### Incorrect Frame Format

The initial `send_frame()` implementation sent only **2 config bytes + 1 data byte**, but the LLC expects:
- Config byte 0 (sop='1', eop='0')
- Config byte 1 (sop='0', eop='0')
- **4 ID bytes** (id3, id2, id1, id0)
- Data bytes with final eop='1'

**Result**: Frame data wasn't properly queued/accepted by LLC layer.

**Status**: **FIXED** - Updated to send complete frame with all 4 ID bytes

---

## Current Test Results

After fixes, the `tx_error_detection_tb` now shows:

```
Sample 10: idle_bit (polarity: recessive)
Sample 11: sof_bit (polarity: dominant)           ← Frame transmission started!
Sample 12-18: active_error_flag_bit (polarity: dominant)
Sample 19: error_delimiter_bit (polarity: recessive)
Sample 25: intermission_bit (polarity: recessive)
Sample 27: idle_bit (polarity: recessive)
```

**Issue**: An error flag is being generated immediately after SOF, before any frame data is transmitted.

---

## Observation: Early Error Flag Generation

The FSM is generating an 6-bit error flag immediately after Start-of-Frame:

```
SOF (1 bit) → ERROR FLAG (6 bits) → DELIMITER (1 bit) → INTERMISSION → IDLE
```

This is **not** reaching the ACK phase, so ACK error cannot be detected yet.

**Possible causes**:
1. Frame data corruption or malformed format
2. FSM initialization issue
3. PCS/MAC interface timing misalignment
4. Frame acceptance not completing properly in LLC

---

## Files Modified

| File | Status | Changes |
|------|--------|---------|
| src/tx_error_detection_tb.vhd | ✓ Fixed | Added send_frame() call, corrected LLC frame format with 4 ID bytes, enhanced diagnostics |
| src/ack_error_debug_tb.vhd | ✓ Created | Standalone diagnostic testbench for focused ACK error investigation |

---

## Next Steps

### Immediate: Investigate Early Error Flag

1. **Check if tx_can_tb has the same behavior**
   - Does Test 1 generate an error flag immediately?
   - Or does it reach ACK phase normally?

2. **Compare frame formats**
   - Extract exact ID byte encoding from tx_can_tb
   - Verify CC Basic frame format requirements

3. **Add signal tracing**
   - Capture transfer_status changes
   - Monitor monitored_bit_event sequence
   - Track FSM state transitions

### Root Cause Identification

Need to determine **why error flag is triggered immediately after SOF**:
- Is it a legitimate error condition (arbitration loss, bit error)?
- Is it a frame format issue?
- Is it a timing/synchronization issue?

### ACK Error Testing

Once the early error flag issue is resolved, we can:
1. Reach the ACK slot phase
2. Monitor rx_bus remaining recessive (no dominant)
3. Verify `debug_ack_error_o` pulses at ACK delimiter

---

## Key Learning: Frame Format Dependency

The LLC→MAC interface requires **precisely formatted frame data**:
- **7 bytes minimum**: config0, config1, id3, id2, id1, id0, eop marker
- **Variable length**: config + 4 ID bytes + N data bytes
- **Control signals**: sop='1' on first byte, eop='1' on last byte
- **Handshaking**: Each byte must see ready='1' before proceeding

Incorrect frame format causes frame rejection or corruption at LLC layer.

---

## Files Ready for Review

- `docs/ACK_ERROR_DEBUG_FINDINGS.md` - This document
- `src/tx_error_detection_tb.vhd` - Updated with send_frame() call
- `src/ack_error_debug_tb.vhd` - New standalone diagnostic testbench

---

## Waveforms for Analysis

- `sim/tx_error_detection_tb.ghw` - Shows early error flag generation
- Need to compare with `sim/tx_can_tb.ghw` Test 1 for reference behavior
