# Testbench Organization Plan

**Date**: 2026-02-19
**Purpose**: Organize tests by verification plan sections to maintain clarity and prevent bloat

---

## Current State

**tx_can_tb.vhd**: 14 tests (mixed across multiple verification aspects)
- Frame format tests
- Bit transmission tests
- Bit rate switching
- Error detection
- Arbitration
- Remote frames
- ACK handling
- Overload flags

**Problem**: As we add 7 new requirements tests, a single testbench becomes unmaintainable (would be ~40+ tests in one file)

---

## Proposed Testbench Structure

### Primary Testbenches (by Verification Aspect)

```
src/
├── tx_can_tb.vhd                    [KEEP - Frame Format & Transmission Basics]
│   └── 14 tests: Frame structure, serialization, basic bit timing, arbitration
│   └── Covers: Sections 1-4 of verification plan
│
├── tx_error_detection_tb.vhd        [NEW - Error Detection Tests]
│   ├── Test 1: Form Error Detection (REQ-TX-ERR004)
│   │   - Illegal bit patterns in control field
│   │   - Detect violation and report
│   │
│   └── Test 2: ACK Error Detection (REQ-TX-ERR006)
│       - Transmit recessive, monitor for dominant
│       - Detect missing ACK
│
├── tx_error_handling_tb.vhd         [NEW - Error Handling & Recovery]
│   ├── Test 1: Data Phase Bit Rate Switching (REQ-TX-EH004)
│   │   - Inject error in FD data phase
│   │   - Verify bit rate switches from data→nominal
│   │   - Verify error flag follows
│   │
│   └── Test 2: FD Data Phase Completion (REQ-TX-EH005)
│       - Inject error in data phase
│       - Verify data phase completes at sample point
│       - Before error flag transmission
│
└── tx_tdc_tb.vhd                    [NEW - Transmitter Delay Compensation]
    ├── Test 1: TDC Error at SSP (REQ-TX-TDC003)
    │   - Inject error at secondary sample point
    │   - Verify detected at SSP
    │   - Verify confirmed at next SP
    │   - Verify error flag timing correct
    │
    └── Test 2: TDC Error Timing (REQ-TX-TDC004)
        - Full TDC error sequence: SSP→SP→IPT→nominal
        - Verify bit time switch occurs after IPT
        - Verify Phase_Seg2 timing respected
```

---

## Benefits of This Organization

### 1. **Maintainability**
- Each testbench ≤ 4 focused tests
- Easy to locate test for specific requirement
- Clear purpose and acceptance criteria per file

### 2. **Independence**
- Run error detection tests without frame format noise
- Run TDC tests separately from basic error handling
- Test specific aspects without rebuilding everything

### 3. **Scalability**
- If new error types added later, simple to extend
- New section can add new testbench without touching existing
- Easy to parallel-develop multiple testbench sections

### 4. **Traceability**
- Testbench name directly correlates to requirement section
- Clear mapping: file → verification aspect → ISO section

### 5. **CI/CD Integration**
- Run error detection suite, error handling suite, TDC suite independently
- Quick regression on core functionality (keep tx_can_tb fast)
- Full suite for complete compliance validation

---

## Test Organization Within Each Testbench

### Template Structure (applies to all new testbenches)

```vhdl
-- Unified testbench entity and architecture
-- All tests within procedures, selected by generic or parameter
-- Consistent OSVVM alert framework
-- Shared helper procedures for common operations

architecture testbench of tx_error_detection_tb is

  procedure test_form_error_detection is
    -- Stimulate: Inject invalid bit pattern
    -- Verify: Form error detected, logged
    -- Check: Debug signal pulses
  end procedure;

  procedure test_ack_error_detection is
    -- Stimulate: Send ACK slot, suppress dominant on bus
    -- Verify: ACK error detected
    -- Check: Error flag generation triggered
  end procedure;

begin

  test_process : process
  begin
    test_form_error_detection;
    test_ack_error_detection;
    wait;
  end process;

end architecture;
```

---

## Makefile Integration

### New Make Targets

```bash
# Run individual verification aspects
make TB=src/tx_can_tb test                          # Basic frame transmission (14 tests)
make TB=src/tx_error_detection_tb test              # Error detection (2 tests)
make TB=src/tx_error_handling_tb test               # Error handling (2 tests)
make TB=src/tx_tdc_tb test                          # TDC (2 tests)

# Run full error verification suite
make TB=src/tx_error_detection_tb \
     TB=src/tx_error_handling_tb \
     TB=src/tx_tdc_tb test

# Run all testbenches
make TB=all test                                     # All tests (28+ total)
```

---

## Implementation Sequence (Phase 3)

### Step 1: Create Error Detection Testbench (3h)
```bash
src/tx_error_detection_tb.vhd
├── test_form_error_detection
│   ├── Stimulate: Invalid control field bits
│   ├── Verify: debug_form_error_o signal
│   └── Check: Correct error identification
│
└── test_ack_error_detection
    ├── Stimulate: Send frame, suppress ACK
    ├── Verify: debug_ack_error_o signal
    └── Check: Error state transition
```

### Step 2: Create Error Handling Testbench (4h)
```bash
src/tx_error_handling_tb.vhd
├── test_data_phase_bit_rate_switch
│   ├── Stimulate: Send FD frame, inject error in data phase
│   ├── Verify: debug_current_bit_rate_o switches to nominal
│   └── Check: Error flag follows bit rate switch
│
└── test_fd_data_phase_completion
    ├── Stimulate: Inject error in data phase
    ├── Verify: Data phase completes at SP
    └── Check: Error flag timing correct
```

### Step 3: Create TDC Testbench (8h)
```bash
src/tx_tdc_tb.vhd
├── test_tdc_error_at_ssp
│   ├── Stimulate: Inject error at SSP in data phase
│   ├── Verify: debug_error_at_ssp_o pulses
│   ├── Verify: Confirmed at next SP (debug_error_at_sp_o)
│   └── Check: Error flag generated with correct timing
│
└── test_tdc_error_timing_sequence
    ├── Stimulate: TDC error during data phase
    ├── Verify: SSP→SP→IPT→nominal rate sequence
    ├── Check: Phase_Seg2 timing respected
    └── Check: Error flag starts at correct bit
```

---

## Shared Helper Procedures

All testbenches will use common utilities (in separate pkg or procedures):

```vhdl
procedure reset_and_prepare_frame(
  signal clk : in std_logic;
  signal fifo : inout frame_fifo_t;
  frame_config : in test_frame_config_t;
  -- parameters...
);

procedure wait_for_sample_strobe(
  signal clk : in std_logic;
  signal sp : in std_logic;
  bit_count : inout integer;
);

procedure inject_bus_error(
  signal clk : in std_logic;
  signal rx_bus_i : out std_logic;
  error_polarity : in polarity_t;
  at_bit_count : in integer;
);

procedure verify_error_flag_generated(
  signal debug_mac_to_pcs : in mac_to_pcs_if_t;
  signal sp : in std_logic;
  -- parameters...
);
```

---

## File Size Comparison

### Before (Single Testbench Bloat)
```
tx_can_tb.vhd: ~900 lines (14 tests mixed together)
                + Error detection tests: +200 lines
                + Error handling tests: +300 lines
                + TDC tests: +500 lines
                = 1900 lines total (unmaintainable)
```

### After (Organized by Aspect)
```
tx_can_tb.vhd:                 ~600 lines (14 frame tests, focused)
tx_error_detection_tb.vhd:     ~300 lines (2 focused tests)
tx_error_handling_tb.vhd:      ~400 lines (2 focused tests)
tx_tdc_tb.vhd:                 ~500 lines (2 focused tests)
Shared helpers (optional):     ~200 lines (common procedures)
                               = 2000 lines total (organized, maintainable)
```

---

## Advantages for Your Thesis

1. **Clear Requirements Traceability**: Each testbench maps to verification section
2. **Modular Quality**: Can present each section as focused verification
3. **Academic Presentation**: Shows disciplined test organization
4. **Scalability**: Easy to extend with future CAN protocol features
5. **CI/CD Ready**: Professional test automation structure

---

## Recommendation

✅ **YES - Separate testbenches by verification aspect**

This prevents the single-file bloat problem and aligns with professional verification practices. Each testbench is small, focused, and maintainable - much better for a thesis project.

**Structure**:
- Keep `tx_can_tb.vhd` as-is (frame format + basics)
- Add `tx_error_detection_tb.vhd`
- Add `tx_error_handling_tb.vhd`
- Add `tx_tdc_tb.vhd`
- Optional: shared helper package if procedures repeat

Would you like me to implement this structure for Phase 3?
