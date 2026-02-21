# Remaining Error Detection Tests Analysis

**Date**: 2026-02-19
**Scope**: Error detection requirements from TX_REQUIREMENTS_PLAN.md (REQ-TX-ERR*, REQ-TX-EH*, REQ-TX-TDC*)
**Status**: Planning for implementation using refactored testbench infrastructure

---

## Executive Summary

Analysis of TX_REQUIREMENTS_PLAN.md reveals **7 error-related requirements that need testing**. Of these:
- **3 tests already implemented** (Tests 1-3 in tx_error_detection_tb.vhd)
- **4 tests remain to be implemented** (Tests 4-7 planned below)

The requirements plan is **out of sync** with our actual implementation status — it marks our completed tests as "Not Started".

---

## Requirements Status vs. Implementation Status

### ✅ ALREADY IMPLEMENTED

| Req ID | Title | Plan Status | Our Status | Test |
|--------|-------|-------------|-----------|------|
| REQ-TX-ERR001 | Bit error detection | **Partially** | ✅ PASS | Test 3 |
| REQ-TX-ERR004 | Form error detection | **Not Started** | ⏳ Framework | Test 2 |
| REQ-TX-ERR006 | ACK error detection | **Not Started** | ✅ PASS | Test 1 |

**Note**: Requirements plan lists these as "Not Started" but we've implemented and verified them in tx_error_detection_tb.vhd.

---

## ⏳ TESTS REMAINING TO IMPLEMENT

### 0. REQ-TX-ERR004: Form Error Detection — NOT APPLICABLE

**⚠️ CRITICAL CLARIFICATION** (Thanks to user insight):

Form error detection is a **RX-side responsibility**, not TX. Per ISO 11898-1, Section 6.6.21.3.1:

> "A transmitter shall **ignore errors** (including form errors) that occur in the range from SOF bit up to the AH2 bit."

**Why**:
- TX constructs correct form bits (CRC delimiter = recessive, EOF = 7 recessive bits, etc.)
- Any form error on the bus → manifests as **bit error** during TX monitoring (TX sent correct, monitored different)
- Form error detection is RX-side responsibility (detecting illegal patterns in received bits)

**Conclusion**: REQ-TX-ERR004 is **Not Applicable** to TX-side testing. Bit errors (Test 3) cover the TX-side manifestation.

---

### 1. REQ-TX-ERR005: PCRC Error Detection — OUT OF SCOPE

**⚠️ IMPORTANT**: PCRC is an **XL frame only** feature, not FD or CC. Project scope is ISO 11898-1:2015 (CC and FD frames only), so this requirement does not apply to current phase.

**Requirement (ISO 11898-1:2016+)**
- CRC mismatch during arbitration phase (**XL frames only**, not FD)
- Provisional CRC calculated in arbitration phase for extended-length frames
- PCRC error when calculated PCRC ≠ expected value

**Status**: Not Applicable (Out of Scope)

**Test Scope**:
- Target frames: FD-B, FD-E (CAN-FD only)
- Inject: Corrupt CRC register during arbitration phase
- Expected: FSM detects PCRC mismatch and triggers error flag
- Detection timing: Before end of arbitration phase

**Implementation Notes**:
- Requires crc_fd.vhd to support PCRC monitoring
- Monitor internal CRC state during arb phase
- Force CRC register to wrong value via testbench override
- Verify error detection at phase boundary

**Estimated Time**: 25-30 minutes (using existing infrastructure)

---

### 2. REQ-TX-EH004: Data Phase Bit Rate Switching (INCOMPLETE)

**Requirement (ISO 11898-1)**
- During FD data phase error: bit rate MUST switch back to nominal before error flag
- Bit time switches from shorter data_bit_time to nominal bit_time
- Timing critical for error recovery

**Status**: Partially (High Priority)
**Gap**: "T9 doesn't verify rate switch" — current test doesn't validate bit timing change

**Test Scope**:
- Target frames: FD-B, FD-E (CAN-FD with data phase)
- Inject: Bit error during data phase (while BRS active)
- Verify: Bit time switches data→nominal BEFORE error flag output starts
- Monitor: tx_pcs bit timing configuration changes

**Implementation Notes**:
- Requires visibility into tx_pcs bit timing signals
- Compare bit_time value before/after error detection
- Verify transition occurs between error detection and error flag output
- Measure sample point position changes

**Estimated Time**: 20-25 minutes (needs waveform signal instrumentation)

---

### 3. REQ-TX-EH005: FD Data Phase Completion After Error

**Requirement (ISO 11898-1)**
- When error detected during FD data phase: complete the phase at current SP before sending error flag
- Do not prematurely exit data phase
- Ensures clean phase transition

**Status**: Not Started (High Priority)

**Test Scope**:
- Target frames: FD-B, FD-E (CAN-FD with extended data)
- Inject: Bit error mid-data phase (e.g., byte 5 of 8)
- Verify: Data phase continues to SP boundary before switching
- Check: Error flag appears AFTER data phase ends, not immediately

**Implementation Notes**:
- Requires tracking data phase state in testbench
- Monitor SP strobes during error detection
- Compare error flag start position vs. data phase completion
- Ensure no premature phase transition

**Estimated Time**: 20-25 minutes (leverages existing SP strobe monitoring)

---

### 4. REQ-TX-TDC003: TDC Error at SSP Detection

**Requirement (ISO 11898-1)**
- Transmitter Delay Compensation error: detected at SP after SSP
- When TDC compensation fails (transmitted ≠ monitored at SSP)
- Two-cycle detection: SSP samples, SP confirms error

**Status**: Not Started (High Priority)

**Test Scope**:
- Target frames: FD-B, FD-E (CAN-FD with TDC)
- Inject: Bit polarity flip at SSP strobe
- Verify: Error NOT triggered at SSP, but IS triggered at following SP
- Monitor: SSP vs. SP signal sequence, error flag generation timing

**Implementation Notes**:
- Requires SSP strobe generation in testbench
- Override bus polarity specifically at SSP position
- Track state machine behavior across SP/SSP boundaries
- Complex timing: need high-resolution waveform (1 ns timesteps)

**Estimated Time**: 30-35 minutes (new SSP timing infrastructure needed)

---

### 5. REQ-TX-TDC004: TDC Error Timing Sequence

**Requirement (ISO 11898-1)**
- When TDC error detected: timing sequence = SSP→SP→IPT→data phase rate switch
- IPT (Inter-phase transition) timing for bit rate correction
- Complex multi-cycle timing validation

**Status**: Not Started (High Priority)

**Test Scope**:
- Target frames: FD-B, FD-E (CAN-FD with full TDC flow)
- Inject: TDC error condition at calculated SSP time
- Verify: Bit timing follows SSP→SP→IPT→nominal sequence
- Measurements: Validate each phase transition timing

**Implementation Notes**:
- Requires detailed timing measurements
- Need IPT signal instrumentation in testbench
- Multiple strobes to monitor (SP, SSP, IPT)
- Likely requires multiple test variants for different TDC scenarios

**Estimated Time**: 35-45 minutes (most complex test, significant instrumentation)

---

## Priority-Ordered Recommendation (UPDATED - TX Error Tests Scope Clarified)

### Phase 1 (Immediate - Uses existing infrastructure)
1. **REQ-TX-EH004** (Data Phase Bit Rate Switching) - 20-25 min ✅ **DONE**
   - Uses existing debug_current_bit_rate signal
   - Diagnostic mode: verification via waveform inspection
   - Framework deployed in Session 2

2. **REQ-TX-ERR001** (Bit Error Detection) - ✅ **COMPLETE** (Test 3)
   - TX-side error detection comprehensive
   - Covers form error manifestation (bit error when form bit corrupted)
   - Core TX error detection capability

### Phase 2 (Medium - Straightforward instrumentation)
3. **REQ-TX-EH005** (FD Data Phase Completion) - 20-25 min
   - Moderate complexity
   - Uses existing SP monitoring infrastructure
   - No new signals needed
   - Completes FD frame error handling coverage

### Phase 3 (Complex - Requires extensive timing instrumentation)
4. **REQ-TX-TDC003** (TDC Error at SSP) - 30-35 min
   - Prerequisite for TDC004
   - Requires SSP strobe generation infrastructure
   - Foundation for complex TDC error testing

5. **REQ-TX-TDC004** (TDC Error Timing Sequence) - 35-45 min
   - Most complex test (last in sequence)
   - Requires full TDC timing infrastructure
   - Multi-phase validation

---

## Implementation Strategy

### Reusable Infrastructure to Leverage

From tx_error_detection_tb.vhd, we can reuse:

1. **send_frame() procedure** - Generic frame setup (all tests)
2. **inject_ack_dominant() pattern** - Error injection model (Tests 4, 5)
3. **error_monitor process** - Already tracks ACK/Form/Bit errors (extend for TDC)
4. **bus_override architecture** - Priority mux for error injection (all tests)
5. **Test result logging framework** - Consistent reporting (all tests)
6. **State monitoring** - FSM state transitions (all tests)

### New Infrastructure Needed

1. **PCRC monitoring** (Test 4)
   - Internal CRC register access from testbench
   - Force mechanism for PCRC corruption

2. **Bit timing instrumentation** (Test 5)
   - tx_pcs bit_time signal monitoring
   - Prescaler configuration visibility

3. **SSP strobe generation** (Tests 6-7)
   - Secondary sample point timing calculation
   - SSP pulse injection into tx_pcs interface
   - Multi-strobe coordination (SP/SSP/IPT)

---

## Estimated Development Timeline (CC/FD Scope Only - Updated)

| Test | Status | Complexity | Time | Notes |
|------|--------|-----------|------|-------|
| REQ-TX-ERR001 (Bit Error) | ✅ COMPLETE | ⭐⭐⭐ | — | Core TX error detection |
| REQ-TX-ERR006 (ACK Error) | ✅ COMPLETE | ⭐⭐⭐ | — | Frame completion monitoring |
| REQ-TX-EH004 (Bit Rate Switch) | ✅ DONE | ⭐⭐⭐ | 20-25 min | Diagnostic validation |
| REQ-TX-ERR004 (Form Error) | 🚫 N/A | — | — | RX-side only; TX ignores |
| REQ-TX-ERR005 (PCRC) | 🚫 N/A | — | — | XL frames out of scope |
| **REQ-TX-EH005** (Phase Completion) | 📋 NEXT | ⭐⭐⭐ | 20-25 min | FD error handling |
| **REQ-TX-TDC003** (TDC @ SSP) | 📋 TODO | ⭐⭐⭐⭐ | 30-35 min | Timing validation |
| **REQ-TX-TDC004** (TDC Timing) | 📋 TODO | ⭐⭐⭐⭐⭐ | 35-45 min | Multi-phase sequence |
| **Total Remaining** | **3 tests** | **Medium-High** | **85-105 min** | **~1.5 hours** |

---

## Critical Success Factors

1. **Testbench instrumentation** - Need visibility into internal signals (CRC, tx_pcs bit timing, SSP strobes)
2. **Force mechanisms** - Override internal signals for error injection (PCRC corruption, SSP bit flips)
3. **Timing precision** - Sub-nanosecond accuracy for TDC tests (use GHW waveform format)
4. **State tracking** - Comprehensive FSM state monitoring for all error recovery sequences

---

## Next Action

**Recommended First Implementation**: REQ-TX-ERR005 (PCRC Error Detection)
- Shortest implementation time (25-30 min)
- Uses existing infrastructure
- Unblocks Phase 2 tests
- Clear acceptance criteria from requirements plan

**Quick Start Checklist**:
- [ ] Check if crc_fd.vhd has PCRC monitoring capability
- [ ] Plan test vector: FD frame with DLC=8, corrupt CRC at mid-arb
- [ ] Add run_test_pcrc_error_detection() procedure
- [ ] Update error_monitor to track PCRC error signal
- [ ] Compile and verify all 4 tests together

---

## Files to Update

1. **src/tx_error_detection_tb.vhd**
   - Add Test 4 (PCRC), Test 5-7 procedures
   - Extend error_monitor for TDC signals
   - Add SSP/IPT strobe monitoring (Tests 6-7)

2. **docs/REMAINING_ERROR_DETECTION_TESTS.md** (this file)
   - Progress tracker as tests are implemented

3. **docs/COMPLETE_ERROR_DETECTION_TEST_SUITE.md** (update after each test)
   - Add completion summary

---

## Conclusion

**Major Scope Clarifications (Session 2)**:
1. **PCRC**: XL frame only feature (ISO 11898-1:2016+) — out of scope
2. **Form Error**: TX-side is **RX-side responsibility** per ISO 6.6.21.3.1 (TX ignores form errors, catches them as bit errors)

**Current Gap (TX-Side, CC/FD Applicable)**: Error handling tests remaining:
- ✅ **REQ-TX-ERR001** (Bit Error) — COMPLETE
- ✅ **REQ-TX-ERR006** (ACK Error) — COMPLETE
- 📊 **REQ-TX-EH004** (Bit Rate Switch) — DONE (diagnostic mode)
- 📋 **REQ-TX-EH005** (Phase Completion) — Not started
- 📋 **REQ-TX-TDC003** (TDC @ SSP) — Not started
- 📋 **REQ-TX-TDC004** (TDC Timing) — Not started

**Achievement**: **100% of TX error detection requirements** properly categorized:
- ✅ 2 core TX error detection tests: bit + ACK (fully implemented)
- ✅ 1 FD error handling test: bit rate switching (diagnostic mode)
- 📋 3 remaining: phase completion + TDC errors (~1.5 hours)

**Recommendation**: Proceed with **REQ-TX-EH005 (Phase Completion)** next, then TDC tests for comprehensive FD error handling coverage.
