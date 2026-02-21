# ACK Error Detection Testbench - Root Cause & Solution

**Date**: 2026-02-19
**Status**: ✅ SOLVED & VERIFIED
**Issue**: Debug `ack_error` signal never went high in waveform
**Root Cause**: Conflicting signal drivers on `rx_bus`
**Solution**: Remove process-based assignment that was overriding the loopback

---

## Problem Statement

User reported that the `debug_ack_error_o` signal never pulsed in the waveform, indicating ACK error detection wasn't working.

---

## Investigation Summary (Phases A, B, C)

### Phase A: Test Setup Comparison
Found differences between our testbench and `tx_can_tb`:
- **Frame format**: DLC=8 vs. DLC=1 (corrected)
- **Frame ID**: 0x000 vs. 0x555 (corrected)
- **Missing loopback**: No rx_bus ← tx_bus mapping (added)

### Phase B: Detailed Event Logging
Tracked FSM state transitions and discovered:
- FSM immediately transitioning to `transmitting_error_flag` after SOF
- Monitored event showing as `none` even during transitions
- Root cause: **Polarity mismatch being detected**

### Phase C: Internal Signal Analysis
Used force-accessible signals to access:
- FSM state transitions
- Monitored bit event types
- Revealed mismatch was due to RX always reading recessive

---

## Root Cause: Conflicting Signal Assignments

### The Bug

In `tx_error_detection_tb.vhd`, there were TWO assignments to `rx_bus`:

**Inside test_proc (line ~200):**
```vhdl
process
begin
  -- ...initialization...
  fce_i.error_passive <= false;
  llc_user_i.avalon_st_source.valid <= '0';
  rx_bus <= '1';  -- ← CONFLICTING ASSIGNMENT!
```

**Concurrent (line ~265):**
```vhdl
-- Bus model: loopback
rx_bus <= tx_bus;  -- ← This should be the only driver
```

### Why This Caused the Problem

1. Process assignment `rx_bus <= '1'` (recessive) held during entire test
2. Concurrent assignment `rx_bus <= tx_bus;` was **completely ineffective**
3. Result: RX bus always saw recessive, regardless of what TX transmitted
4. Every transmitted bit appeared as a mismatch:
   - TX sent dominant (SOF) → RX saw recessive → bit_error detected
   - FSM immediately went to error_flag state
   - Frame never reached ACK phase

### Why It Wasn't Obvious

- The conflicting assignments didn't cause a compilation error (both are valid concurrent drivers)
- The error manifested as immediate frame corruption, which was hard to trace without signal monitoring
- Only visible after implementing detailed FSM state tracking

---

## Solution

**Remove the conflicting assignment inside test_proc:**

```diff
- rx_bus <= '1';  -- Keep recessive by default
+ -- Removed: loopback handled by concurrent assignment
```

**Result after fix:**
- Loopback now properly mirrors TX to RX
- Bus polarity mismatches eliminated
- Frame transmission proceeds normally
- Frame reaches ACK phase
- ACK error correctly detected when no dominant ACK received

---

## Verification

After removing the conflicting assignment:

```
Sample 11: sof_bit (dominant)           ✓
Sample 12-15: base_id_bit               ✓
Sample 16: stuff_bit                    ✓
Sample 24: rtr_bit                      ✓
...
Sample 58: ack_bit (recessive)          ✓
Sample 59: [PULSE] ACK ERROR DETECTED   ✓✓✓
Sample 59: ack_delimiter_bit            ✓
Sample 60: FSM → transmitting_error_flag ✓
```

**Total test duration**: ~37μs (from SOF to idle)
**ACK error detection**: Sample 59 (perfectly positioned at ACK delimiter)
**Frame status**: Normal completion with error flag response

---

## Lessons Learned

### 1. Signal Driver Conflicts Can Be Invisible
- VHDL allows multiple concurrent drivers without compile error
- Last driver in precedence wins
- Process-based drivers may override concurrent assignments depending on simulation semantics

### 2. FSM State Monitoring Reveals Hidden Issues
- Watching state transitions and triggering events exposed the root cause
- Would have been difficult to find with binary signal analysis alone

### 3. Test Setup Comparison is Essential
- Line-by-line comparison with known-working testbench (`tx_can_tb`) revealed setup differences
- Frame format, ID encoding, and signal initialization all matter

### 4. Loopback Implementation is Critical
- CAN testbenches require proper bus loopback with correct timing
- Concurrent assignment `signal <= driver;` is the correct pattern for stable loopback
- Process-based drivers are meant for stimulus, not loopback

---

## Files Modified

| File | Change | Impact |
|------|--------|--------|
| src/tx_error_detection_tb.vhd | Removed `rx_bus <= '1';` from test_proc | ✅ Fixed |
| src/tx_error_detection_tb.vhd | Changed frame DLC from 8 to 1 | ✅ Matches tx_can_tb |
| src/tx_error_detection_tb.vhd | Updated frame ID to 0x555 | ✅ Matches tx_can_tb |
| src/tx_error_detection_tb.vhd | Added FSM state monitoring | ✅ Debug aid |
| src/tx_error_detection_tb.vhd | Added monitored_bit_event tracking | ✅ Debug aid |

---

## What's Now Working

✅ Frame transmission initiates correctly
✅ Frame progresses through all phases (arbitration, control, data, CRC)
✅ Stuff bits inserted at correct positions
✅ ACK slot transmitted as recessive (waiting for receiver ACK)
✅ ACK error detected when no dominant received
✅ `debug_ack_error_o` pulses at ACK delimiter
✅ Error flag generated and transmitted
✅ Frame recovery sequence (intermission → bus_idle)

---

## Test Output Summary

```
Total bits transmitted: 75 samples (~37.5 μs)
Frame completion: Normal transmission + ACK error response
Debug signal: ACK error pulse at sample 59
FSM transitions: 5 (bus_reintegration → idle → frame → error_flag → intermission → idle)
Status: ACK error detected during simulation ✓
```

---

## Actionable Takeaways

1. **Always initialize process signals outside the process** when they're meant to be default states
2. **Concurrent assignments are for stable drivers** (like bus loopback)
3. **Process assignments are for stimulation** (like test vector generation)
4. **When debugging testbenches, mirror working ones line-by-line** to catch initialization differences
5. **Add FSM state and event monitoring early** to catch state machine issues quickly

---

## Next Steps

The testbench is now ready for expanding to test other error conditions:

- **Form Error Detection** (Phase 3B)
- **Data Phase Completion** (Phase 3C)
- **TDC Error Path** (Phase 3D)

All will use the same corrected testbench framework with proper signal initialization.
