# Debug Signals Analysis for TX CAN Compliance Testing

**Document Version**: 1.0
**Date**: 2026-02-19
**Purpose**: Assess current debug signal availability and identify gaps needed for testing 7 critical requirements

---

## Current Debug Signals Available

### From MAC Transmitter (`tx_mac.vhd`)
```
debug_mac_to_pcs_o : out mac_to_pcs_if_t
  └─ data.bit_name (mac_frame_bit_name_t)  ✓ Current bit type (SOF, ID, CRC, etc.)
  └─ data.polarity (polarity_t)             ✓ Current bit polarity (dominant/recessive)
  └─ valid (boolean)                        ✓ Bit valid for transmission

debug_pcs_to_mac_o : out pcs_to_mac_if_t
  └─ bus_polarity (polarity_t)              ✓ What's currently on the bus
  └─ sample_strobe (std_logic)              ✓ Unified strobe (SP or SSP, not distinguished)
```

### From Testbench Direct Access
```
fsm_state <= << signal dut.mac_tx_inst.tx_mac_fsm_inst.state : tx_mac_fsm_state_t >>
  └─ Current FSM state in MAC                ✓ Available via VHDL 2008 force-accessible signals
```

### Not Currently Exposed
- **tx_pcs FSM state** (hidden inside tx_pcs module)
- **SSP vs SP distinction** (only unified `sample_strobe` available)
- **Current bit rate** (nominal vs data phase) - no explicit signal
- **Form error detection** - not captured anywhere
- **PCRC error detection** - hidden in CRC module
- **ACK error detection** - not captured
- **Data phase active flag** - derived from state only
- **TDC measurement state/delay** - hidden in tx_pcs

---

## Analysis: Debug Signals Needed for Each Critical Gap

### 1. REQ-TX-ERR004 - Form Error Detection
**Requirement**: Detect illegal bit patterns in control field

**Current Capability**: ⚠️ PARTIAL
- Can observe bit sequence via `debug_mac_to_pcs_o.data.bit_name`
- Cannot explicitly see form error detection

**Debug Signals Needed**:
1. **form_error_detected** (boolean) - Pulse when form error found
2. **form_error_bit_position** (bit_count_t) - Which bit triggered it
3. **form_error_type** (enumeration) - What rule was violated

**Source Module**: tx_mac_fsm
**Complexity**: Medium (requires form error detection logic to be implemented first)

---

### 2. REQ-TX-ERR005 - PCRC Error Detection
**Requirement**: Detect CRC mismatch during arbitration phase

**Current Capability**: ❌ NONE
- No visibility into PCRC calculation
- No PCRC comparison result exposed

**Debug Signals Needed**:
1. **pcrc_calculated** (std_logic_vector) - PCRC value computed
2. **pcrc_comparison_result** (boolean) - Does transmitted PCRC match?
3. **pcrc_error_detected** (boolean) - CRC mismatch found

**Source Module**: crc_fd (new debug port)
**Complexity**: High (requires instrumentation of CRC module and architectural integration)

---

### 3. REQ-TX-ERR006 - ACK Error Detection
**Requirement**: Monitor ACK slot - TX sends recessive, expects dominant from receivers

**Current Capability**: ⚠️ PARTIAL
- Can see `bus_polarity` during ACK slot
- Can see we're in ACK field (`bit_name = ack_slot_bit`)
- Cannot explicitly capture ACK error condition

**Debug Signals Needed**:
1. **ack_slot_active** (boolean) - Currently in ACK slot
2. **ack_error_detected** (boolean) - Pulse when ACK slot ends with no dominant seen
3. **ack_dominant_seen** (boolean) - Was dominant detected during ACK slot

**Source Module**: tx_mac_fsm
**Complexity**: Low (derived from existing monitoring, just needs explicit signals)

---

### 4. REQ-TX-EH004 - Data Phase Bit Rate Switching Verification
**Requirement**: Verify bit rate switches from data→nominal during error in FD data phase

**Current Capability**: ⚠️ PARTIAL
- FSM state transitions available (tx_mac_fsm.state)
- Can infer bit rate from FSM state (transmitting_data = data rate, else nominal)
- Cannot directly see which prescaler/bit-time is active

**Debug Signals Needed**:
1. **current_bit_rate** (enumeration: nominal, data) - Which rate is active now
2. **tx_pcs_state** (tx_pcs_fsm_state_t) - Direct visibility to PCS state
3. **active_prescaler** (integer) - Current prescaler value
4. **active_bit_time** (integer) - Current bit time in tq

**Source Module**: tx_pcs
**Complexity**: Medium (requires exposing internal PCS signals)

---

### 5. REQ-TX-EH005 - FD Data Phase Completion Verification
**Requirement**: Data phase completes after SP where error detected

**Current Capability**: ⚠️ PARTIAL
- Can see bit names transition from data phase to CRC delimiter
- Cannot explicitly capture "data phase exit at SP"

**Debug Signals Needed**:
1. **data_phase_active** (boolean) - Currently in data phase
2. **data_phase_exit_at_sp** (boolean) - Pulse when data phase transitions at sample point
3. **sp_within_data_phase** (boolean) - Is this SP within data phase

**Source Module**: tx_pcs
**Complexity**: Low-Medium (derived from existing state, needs explicit capture)

---

### 6. REQ-TX-TDC003 - TDC Error at SSP Detection
**Requirement**: Error detected at SSP, confirmed at following SP

**Current Capability**: ❌ CRITICAL GAP
- Only have unified `sample_strobe` (cannot distinguish SP from SSP)
- Cannot see TDC measurement state
- Cannot see when error is detected at SSP vs SP

**Debug Signals Needed**:
1. **sp_strobe** (std_logic) - Sample Point pulse (explicit)
2. **ssp_strobe** (std_logic) - Secondary Sample Point pulse (explicit)
3. **tdc_state** (tx_pcs_fsm_state_t or custom enum) - Current TDC mode
4. **tdc_delay_measured** (integer) - Current measured delay value
5. **error_detected_at_ssp** (boolean) - Pulse on error at SSP
6. **error_confirmed_at_sp** (boolean) - Pulse on error confirmation at next SP

**Source Module**: tx_pcs
**Complexity**: High (fundamental architectural change - must separate SSP/SP strobes)

---

### 7. REQ-TX-TDC004 - TDC Error Timing Sequence
**Requirement**: Verify SSP→SP→IPT→bit rate switch to nominal sequence

**Current Capability**: ❌ CRITICAL GAP
- Cannot distinguish SP from SSP
- Cannot track IPT (Inter-Phase Time)
- Cannot see TDC timing state transitions

**Debug Signals Needed**:
1. All signals from REQ-TX-TDC003 (SSP/SP separation, TDC state)
2. **ipt_active** (boolean) - Currently in Inter-Phase Time
3. **ipt_counter** (integer) - IPT time quanta counter
4. **phase_seg2_active** (boolean) - In Phase Segment 2
5. **tdc_error_path_active** (boolean) - Following TDC error recovery sequence

**Source Module**: tx_pcs
**Complexity**: Very High (requires TDC error path implementation + detailed timing visibility)

---

## Summary Matrix

| Requirement | Current | Gap | Priority | Source | Complexity | Effort |
|-------------|---------|-----|----------|--------|------------|--------|
| REQ-TX-ERR004 | Partial | Form error signal | P1 | tx_mac_fsm | Medium | 4h |
| REQ-TX-ERR005 | None | PCRC visibility | P1 | crc_fd | High | 6h |
| REQ-TX-ERR006 | Partial | ACK error signal | P1 | tx_mac_fsm | Low | 2h |
| REQ-TX-EH004 | Partial | Bit rate visibility | P1 | tx_pcs | Medium | 3h |
| REQ-TX-EH005 | Partial | Data phase exit flag | P1 | tx_pcs | Low-Med | 2h |
| REQ-TX-TDC003 | None | SSP/SP separation | P1 | tx_pcs | High | 8h |
| REQ-TX-TDC004 | None | TDC timing sequence | P1 | tx_pcs | Very High | 12h |

---

## Recommended Debug Interface Expansion

### Phase 1: Low Effort - Immediate Impact (7 hours)
Add these signals to `tx_mac.vhd` debug port:

1. **ack_error_detected** (boolean) - from tx_mac_fsm
2. **data_phase_active** (boolean) - from tx_mac_fsm state
3. **current_bit_rate** (enumeration) - inferred from tx_mac_fsm state
4. **form_error_detected** (boolean) - from tx_mac_fsm error detection
5. **data_phase_exit_at_sp** (boolean) - from tx_pcs timing

**Impact**: Enables testing of REQ-TX-ERR004, REQ-TX-ERR006, REQ-TX-EH004, REQ-TX-EH005 (80% of needs)

### Phase 2: Medium Effort - Architectural Requirement (10 hours)
**IMPORTANT**: Unified strobe is NOT ISO-compliant for TDC error handling

**Critical change**: Add `strobe_type` indicator to preserve clean separation

```vhdl
-- Current (unified, not ISO-compliant for TDC):
type pcs_to_mac_if_t is record
  bus_polarity : polarity_t;
  sample_strobe : std_logic;  -- Which one: SP or SSP?
end record;

-- Proposed (type-aware, ISO-compliant):
type strobe_type_t is (sp_strobe, ssp_strobe);

type pcs_to_mac_if_t is record
  bus_polarity : polarity_t;
  sample_strobe : std_logic;         -- Unified effective strobe
  strobe_type : strobe_type_t;       -- Indicates which: SP or SSP
end record;
```

**Why this approach**:
- ✅ Preserves clean separation: PCS calculates timing, FSM decides actions
- ✅ No duplicate strobes (clean vs. split strobes)
- ✅ **Required for ISO 6.6.21.3.1 TDC error compliance** (differentiate SSP vs SP)
- ✅ One signal added, minimal interface change

**Additional signals to add to debug port**:
- **tdc_state** (tx_pcs_fsm_state_t) - Current TDC mode (idle/measuring/transmitting_data)
- **tdc_delay_measured** (integer) - Measured propagation delay in tq
- **ipt_active** (boolean) - Information Processing Time active flag
- **phase_seg2_active** (boolean) - Phase Segment 2 active flag
- **error_detected_at_ssp** (boolean) - Error found at SSP (tentative)
- **error_confirmed_at_sp** (boolean) - Error confirmed at following SP

**Impact**: Enables complete ISO-compliant testing of REQ-TX-TDC003 and REQ-TX-TDC004

### Phase 3: High Effort - Architecture Implementation (6 hours)
1. Implement actual error detection logic:
   - Form error detection in tx_mac_fsm
   - ACK error detection logic
   - PCRC error detection in crc_fd

2. Implement TDC error path:
   - Error detection at SSP
   - Error confirmation at next SP
   - IPT handling for TDC error recovery

---

## Recommended Approach for Verification

### ⚠️ CRITICAL: ISO Compliance Requirement
Phase 2 (strobe_type indicator) is **NOT optional**. ISO 11898-1 Section 6.6.21.3.1 explicitly requires TDC error handling to distinguish SSP from SP. Without it, the implementation **cannot be ISO-compliant**.

**Two paths exist**:

**Option A: Minimal (Partial Compliance)**
- Add 5 Phase 1 debug signals
- Test 4 requirements (ERR004, ERR006, EH004, EH005)
- Cannot fully test TDC error handling (REQ-TX-TDC003/004)
- Effort: 7 hours, Coverage: 60%, **ISO Compliance: INCOMPLETE**

**Option B: Complete (Full ISO Compliance)** ✅ RECOMMENDED
- Execute Phase 1 + Phase 2 + Phase 3
- All 7 requirements testable
- Full ISO 11898-1 Section 6.6.21.3.1 compliance
- Effort: ~20 hours, Coverage: 100%, **ISO Compliance: COMPLETE**

**Recommendation**: **Proceed with Option B**
- Phase 2 (strobe_type) is a small change (~10 lines) with massive compliance benefit
- Architectural improvement aligns with protocol specification
- TDC is critical for high-speed FD frames; correctness is essential

---

## Risk Assessment

**No changes needed** to debug signals for:
- REQ-TX-ERR003 (Stuff error) - Already testable with current signals

**Minimal risk** for Phase 1 additions:
- Simple boolean/enumeration signals
- No impact on data path
- All derived from existing signals

**Architectural risk** for Phase 2 (SSP/SP separation):
- Changes interface between tx_pcs and tx_mac_fsm
- Requires updates to state machine logic in tx_mac_fsm
- Must verify error detection at correct strobes
- Mitigatable with careful incremental implementation

**Implementation risk** for Phase 3:
- Requires implementation of error detection logic itself
- Cannot test what isn't implemented
- Should be done in parallel with logic implementation

---

---

## Complete Debug Signal Implementation Checklist

### Interface Changes (can_types_pkg.vhd)

**Add new type**:
```vhdl
type strobe_type_t is (sp_strobe, ssp_strobe);
```

**Modify pcs_to_mac_if_t**:
```vhdl
type pcs_to_mac_if_t is record
  bus_polarity : polarity_t;
  sample_strobe : std_logic;
  strobe_type : strobe_type_t;  -- NEW: Indicates SP vs SSP
end record;
```

### Debug Port Expansion (tx_mac.vhd)

**New debug port signals**:

```vhdl
-- From pcs_to_mac interface (pass-through)
debug_strobe_type_o : out strobe_type_t;
debug_sp_strobe_o : out std_logic;
debug_ssp_strobe_o : out std_logic;

-- From tx_mac_fsm (error detection)
debug_ack_error_detected_o : out boolean;
debug_form_error_detected_o : out boolean;
debug_data_phase_active_o : out boolean;
debug_data_phase_exit_at_sp_o : out boolean;

-- From tx_pcs (TDC and timing)
debug_current_bit_rate_o : out bit_rate_type_t;  -- enum: nominal, data
debug_tdc_state_o : out tx_pcs_fsm_state_t;
debug_tdc_delay_measured_o : out integer;
debug_ipt_active_o : out boolean;
debug_ipt_counter_o : out integer;
debug_phase_seg2_active_o : out boolean;
debug_error_at_ssp_o : out boolean;
debug_error_confirmed_at_sp_o : out boolean;
```

### Implementation Map

| Signal | Source | Phase | Requirement | Priority |
|--------|--------|-------|-------------|----------|
| `strobe_type` | pcs_to_mac | 2 | **All TDC tests** | **CRITICAL** |
| `ack_error_detected` | tx_mac_fsm | 1 | REQ-TX-ERR006 | P1 |
| `form_error_detected` | tx_mac_fsm | 1 | REQ-TX-ERR004 | P1 |
| `current_bit_rate` | tx_mac_fsm | 1 | REQ-TX-EH004 | P1 |
| `data_phase_active` | tx_mac_fsm | 1 | REQ-TX-EH005 | P1 |
| `data_phase_exit_at_sp` | tx_pcs | 1 | REQ-TX-EH005 | P1 |
| `tdc_state` | tx_pcs | 2 | REQ-TX-TDC003/004 | P1 |
| `tdc_delay_measured` | tx_pcs | 2 | REQ-TX-TDC003/004 | P1 |
| `ipt_active` | tx_pcs | 2 | REQ-TX-TDC004 | P1 |
| `ipt_counter` | tx_pcs | 2 | REQ-TX-TDC004 | P1 |
| `phase_seg2_active` | tx_pcs | 2 | REQ-TX-TDC004 | P1 |
| `error_at_ssp` | tx_mac_fsm | 2 | REQ-TX-TDC003 | P1 |
| `error_confirmed_at_sp` | tx_mac_fsm | 2 | REQ-TX-TDC003 | P1 |

---

## Next Steps

1. ✅ **Confirm approach**: Option B (Full ISO Compliance)
2. **Phase 1** (7 hours): Add debug signals for ERR004/ERR006/EH004/EH005
3. **Phase 2** (3 hours): Add strobe_type to interface + debug outputs
4. **Phase 3** (10 hours): Implement error detection logic and TDC error path
5. **Parallel**: Start writing test cases for all 7 requirements
