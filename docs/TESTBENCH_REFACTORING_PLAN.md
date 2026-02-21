# Testbench Infrastructure Refactoring Plan

**Objective**: Create clean, maintainable, reusable testbench framework for error detection and future verification tests

**Template**: tx_error_detection_tb → master template for all subsequent error/handling testbenches

---

## Current Issues to Address

### 1. **Code Organization** ❌
- Procedures scattered throughout architecture
- No clear separation of concerns
- Monitoring processes mixed with test logic
- Helper functions not grouped

### 2. **Reusability** ❌
- Frame setup hardcoded (CC Basic, DLC=1, ID=0x555)
- No parametrizable frame builder
- No generic test procedure template
- send_frame() deeply embedded

### 3. **Test Management** ❌
- Single monolithic test process
- No clear test structure (setup/run/verify/report)
- No test result tracking per test
- Difficult to add more tests without code duplication

### 4. **Monitoring & Logging** ❌
- Multiple independent monitor processes
- No centralized logging/reporting framework
- Test state scattered across signals
- Difficult to track results

### 5. **Configuration Management** ❌
- Hardcoded frame parameters
- Bus override logic not generalized
- No injection mechanism framework
- Signal names inconsistent

---

## Target Architecture

### 1. **Section 1: Types & Constants (NEW)**
```vhdl
-- Custom types for test management
type test_status_t is (idle, setup, running, verifying, passed, failed);
type test_result_t is record
  test_id    : integer;
  test_name  : string;
  status     : test_status_t;
  duration   : time;
  errors     : integer;
  warnings   : integer;
end record;

-- Configuration records for frame building
type frame_config_t is record
  format       : can_format_t;
  dlc          : std_logic_vector(3 downto 0);
  id_11bit     : std_logic_vector(10 downto 0);
  id_29bit     : std_logic_vector(28 downto 0);
  data_bytes   : integer;
  ftyp, brs, esi : std_logic;
end record;

-- Test injection controls
type error_injection_t is record
  inject_ack   : boolean;  -- Inject dominant during ACK slot
  inject_form  : boolean;  -- Inject form error
  inject_bit   : boolean;  -- Inject bit error at position
  inject_pos   : integer;
end record;
```

### 2. **Section 2: Test Infrastructure Procedures**
```
procedure init_frame_config(...)
procedure init_error_injection(...)
procedure log_test_start(test_id, test_name, ...)
procedure log_test_result(test_result, ...)
procedure assert_signal_pulse(signal, expected_time, tolerance, ...)
procedure wait_for_fsm_state(state, timeout, ...)
```

### 3. **Section 3: Frame Building Procedures**
```
procedure build_cc_basic_frame(frame_config_t, data, ...)
procedure build_cc_extended_frame(...)
procedure build_fd_basic_frame(...)
procedure build_fd_extended_frame(...)
procedure send_frame_from_config(frame_config_t, ...)
```

### 4. **Section 4: Error Injection Procedures**
```
procedure setup_ack_injection(...)
procedure setup_form_error_injection(...)
procedure setup_bit_error_injection(position, ...)
procedure inject_bus_error_at(sample_point, polarity, duration, ...)
```

### 5. **Section 5: Monitoring & Verification**
```
procedure verify_frame_transmission(expected_bits, tolerance, ...)
procedure verify_error_detection(error_type, expected_sample, tolerance, ...)
procedure verify_fsm_sequence(expected_states, ...)
procedure collect_frame_statistics(...)
```

### 6. **Section 6: Unified Monitoring Processes**
```
- test_controller_proc (centralized test orchestration)
- fsm_state_monitor_proc (FSM transitions with logging)
- signal_pulse_monitor_proc (detects error pulses)
- frame_progression_monitor_proc (tracks bit_name sequence)
- test_result_reporter_proc (final reporting)
```

### 7. **Section 7: Main Test Process**
```
process
  variable test_result : test_result_t;
begin
  init_system();

  test_result := run_test_ack_error_detection();
  report_test_result(test_result);

  test_result := run_test_form_error_detection();
  report_test_result(test_result);

  test_result := run_test_bit_error_injection();
  report_test_result(test_result);

  final_report();
end process;
```

---

## Implementation Steps

### Step 1: Create Type Definitions & Constants
- [ ] Define test_status_t, test_result_t
- [ ] Define frame_config_t, error_injection_t
- [ ] Define frame configuration presets (cc_basic_default, fd_extended_default, etc.)
- [ ] Define expected bit sequences for verification

### Step 2: Create Core Procedures Library
- [ ] Frame configuration procedures (parametrizable)
- [ ] Frame transmission procedures (generic)
- [ ] Error injection procedures (systematic)
- [ ] Verification procedures (reusable assertions)

### Step 3: Refactor Monitoring Infrastructure
- [ ] Centralize FSM state tracking
- [ ] Create unified signal monitoring process
- [ ] Implement test result collection
- [ ] Create comprehensive reporting framework

### Step 4: Implement Test Templates
- [ ] Generic test procedure template with setup/run/verify/report
- [ ] ACK error detection test (refactored)
- [ ] Frame for form error detection (template ready)
- [ ] Frame for bit error detection (template ready)

### Step 5: Documentation & Examples
- [ ] Header comments documenting how to add new tests
- [ ] Example: Adding a new error detection test
- [ ] Signal monitoring guide
- [ ] Result interpretation guide

---

## Benefits of Refactoring

### For Current Work
✅ Cleaner, more readable code
✅ Easier to debug and maintain
✅ Obvious where to add new tests

### For Future Testbenches
✅ Can copy tx_error_detection_tb as template
✅ Extract procedures for reuse
✅ Consistent structure across all testbenches
✅ Proven patterns reduce errors

### For Verification Plan
✅ Standardized test methodology
✅ Consistent logging/reporting
✅ Easier to track coverage
✅ Professional documentation

---

## New Testbench Structure

```
tx_error_detection_tb.vhd (refactored)
├── Section 1: Header & Libraries
├── Section 2: Type Definitions & Constants
│   ├── test_status_t, test_result_t
│   ├── frame_config_t, error_injection_t
│   └── Configuration presets
├── Section 3: Configuration Procedures
│   ├── init_frame_config()
│   ├── init_error_injection()
│   └── Configure_* helpers
├── Section 4: Frame Building Procedures
│   ├── build_cc_basic_frame()
│   ├── build_cc_extended_frame()
│   ├── send_frame_from_config()
│   └── Frame construction helpers
├── Section 5: Error Injection Procedures
│   ├── setup_ack_injection()
│   ├── setup_form_error_injection()
│   ├── inject_at_position()
│   └── Bus manipulation helpers
├── Section 6: Verification Procedures
│   ├── verify_frame_transmission()
│   ├── verify_error_detection()
│   ├── verify_fsm_sequence()
│   └── Assertion helpers
├── Section 7: Test Procedures
│   ├── run_test_ack_error_detection()
│   ├── run_test_form_error_detection()
│   ├── run_test_bit_error_injection()
│   └── [template] run_test_[new_error]()
├── Section 8: Monitoring Processes
│   ├── test_controller_proc
│   ├── fsm_monitor_proc
│   ├── signal_monitor_proc
│   ├── frame_monitor_proc
│   └── reporter_proc
├── Section 9: Architecture Connections
│   ├── DUT instantiation
│   ├── Clock & reset
│   ├── Bus model (loopback)
│   └── Force-accessible signals
└── Section 10: Main Test Process
    └── Orchestrate all tests
```

---

## Refactoring Effort Estimate

| Task | Effort | Priority |
|------|--------|----------|
| Type definitions & constants | 0.5h | P0 |
| Configuration procedures | 1.5h | P0 |
| Frame building procedures | 1.5h | P0 |
| Error injection procedures | 1.5h | P0 |
| Monitoring infrastructure | 2h | P0 |
| Test templates & refactoring | 1.5h | P1 |
| Documentation & examples | 1h | P1 |
| **Total** | **~9.5h** | - |

**Benefit**: ~20-30h saved on future testbench implementations (4-5 additional testbenches)

---

## Success Criteria

- [ ] All 3 error detection tests pass with new structure
- [ ] Code is ≤400 lines (vs ~380 currently with better organization)
- [ ] Adding a new test takes <30 minutes
- [ ] FSM state monitoring fully automatic
- [ ] Test results clearly reported
- [ ] Can be used as template for future testbenches
- [ ] Comprehensive documentation in header
