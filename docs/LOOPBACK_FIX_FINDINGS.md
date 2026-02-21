# Loopback Fix - Findings and Status

**Date**: 2026-02-19
**Status**: PARTIALLY RESOLVED - Loopback added, but new issue discovered

---

## Root Cause Identified ✅

**User's Observation**: "The tx bus is not being looped back to the rx with a configurable delay like we do in tx_can_tb."

**Root Cause**: The testbench was NOT feeding `tx_bus_o` back to `rx_bus_i`. Without the loopback:
- TX bus sends dominant (0) during SOF
- RX bus stays recessive (1)
- FSM detects bit mismatch → **BIT ERROR** → generates error flag immediately

**Fix Applied**: Added loopback assignment:
```vhdl
rx_bus <= tx_bus;  -- Bus model loopback
```

Matches `tx_can_tb` lines 144-146 exactly.

---

## Status After Fix

### What's Now Working ✅
1. Frame transmission initiates (SOF bit appears at sample 11)
2. Frame data format is correct (cfg0=0x00, cfg1=0x80)
3. Frame is accepted by LLC (transfer_status = ongoing)
4. Loopback is connected (tx_bus → rx_bus)

### What's Still Wrong ✗
After the loopback fix, frame now transmits but **immediately generates an error flag** after SOF:

```
Sample 11: sof_bit (dominant)
Sample 12-18: active_error_flag_bit (dominant)  ← Generated immediately!
Sample 19: error_delimiter_bit (recessive)
```

This means the FSM detected an error condition **right after SOF** and is transmitting an error response.

---

## Remaining Mystery

**Problem**: Frame can't proceed past SOF to reach the ACK phase where ACK error detection would occur.

**Current Behavior**:
- SOF successfully transmitted
- But FSM immediately transitions to transmitting_error_flag state
- Sends 6-bit error flag
- Then goes to intermission and idle

**Not Reaching**:
- Arbitration phase (Base ID bits)
- Data phase
- ACK phase (where we need to test ACK error detection)

---

## Hypothesis: Frame Format or Initialization Issue

The immediate error generation suggests:

1. **Possible**: Frame data format is still not fully correct despite cfg0=0x00, cfg1=0x80
2. **Possible**: MAC layer FSM initialization or state not ready for frame reception
3. **Possible**: Frame is being accepted but with parsing error that causes immediate error response
4. **Possible**: There's another signal or condition that needs to be set for proper frame transmission

---

## What We Know Works

From `tx_can_tb` Test 1:
- Frame transmission lasts ~28 microseconds (not microseconds!)
- Frame progresses through all fields normally
- No immediate error flag after SOF
- Eventually completes with proper intermission sequence

---

## Next Steps for Investigation

1. **Compare exact frame setup** between our testbench and tx_can_tb:
   - How does tx_can_tb initialize fce_i (Fault Confinement Entity)?
   - Are there other signal requirements we're missing?
   - What's different in timing or initialization?

2. **Check frame acceptance in LLC layer**:
   - Is the frame being parsed correctly?
   - Are the config bytes being interpreted as expected?

3. **Examine error trigger condition**:
   - What specific event causes the error flag generation?
   - Is it a bit error, arbitration loss, or something else?
   - Can we trace the monitored_bit_event sequence?

4. **Verify PCS/MAC synchronization**:
   - Are the strobes (sample_strobe, ssp) firing correctly?
   - Is the PCS ready when MAC transmits?

---

## Files Modified

- `src/tx_error_detection_tb.vhd`:
  - Added `rx_bus <= tx_bus;` loopback assignment
  - Added send_frame() function call
  - Corrected frame format with all 4 ID bytes
  - Enhanced diagnostics for frame progression

---

## Critical Realization

The **loopback was the immediate problem**, but fixing it revealed a **deeper issue** with either:
1. Frame format/parsing
2. FSM initialization or readiness
3. MAC→PCS interface synchronization

The next debugging phase needs to focus on **why the error flag is generated immediately after SOF** rather than on the loopback itself.
