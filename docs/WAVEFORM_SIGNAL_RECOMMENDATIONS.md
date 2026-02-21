# Waveform Viewer Signal Recommendations

**Purpose**: Optimize GTKWave display for error detection debugging
**Target**: Phase 3 testbenches (error detection, error handling, TDC)

---

## Recommended Signal Groups for tx_error_detection_tb

### Group 1: Clock & Synchronization (Timing Reference)
```
├─ clk                                      [Binary]
├─ debug_pcs_to_mac.sample_strobe          [Binary] - When sampling occurs
├─ debug_strobe_type_o                      [Enum: sp_strobe/ssp_strobe]
└─ rst                                      [Binary]
```

**Why**: Sample strobe shows exact sampling moments. Strobe type distinguishes SP from SSP (critical for TDC).

---

### Group 2: Frame Structure & Bit Transmission (What's Being Sent)
```
├─ debug_mac_to_pcs.data.bit_name          [Enum: bit type names]
│  └─ Shows: SOF, base_id, ack_slot, ack_delimiter, eof, etc.
├─ debug_mac_to_pcs.valid                  [Binary]
├─ debug_mac_to_pcs.data.polarity          [Enum: dominant/recessive]
└─ debug_current_bit_rate_o                [Binary] - 0=nominal, 1=data
```

**Why**:
- Bit name tells you exactly which frame field is being transmitted
- Valid shows when MAC is sending
- Polarity shows dominant/recessive being transmitted
- Bit rate shows if in nominal or data phase

**Critical for ACK detection**: Watch when `bit_name = ack_slot_bit` or `ack_delimiter_bit`

---

### Group 3: Bus Monitoring (Physical Layer)
```
├─ rx_bus_i                                 [Binary] - Injected monitored value
├─ tx_bus_o                                 [Binary] - Transmitted value
├─ debug_pcs_to_mac.bus_polarity           [Enum: dominant/recessive]
└─ test_cycle_counter (if added)           [Integer]
```

**Why**:
- tx_bus shows what transmitter is driving
- rx_bus shows what's being injected (for error injection testing)
- bus_polarity shows PCS interpretation
- Cycle counter helps identify test timing

**Critical pattern for ACK error**:
```
During ACK slot:
  tx_bus = recessive (transmitter sends recessive)
  rx_bus = recessive (no receiver dominant - ACK error!)
  debug_ack_error_o should pulse at ACK delimiter
```

---

### Group 4: Error Detection Signals (The Test Subject)
```
├─ debug_ack_error_o                       [Binary] ⭐ PRIMARY
├─ debug_form_error_o                      [Binary]
├─ debug_data_phase_exit_o                 [Binary]
├─ debug_error_at_ssp_o                    [Binary]
└─ debug_error_at_sp_o                     [Binary]
```

**Why**: These are what you're testing. Watch for:
- Single-cycle pulses (not held high)
- Correlation with bit_name and sample_strobe
- Timing relative to error conditions

**Expected behavior for ACK error**:
- `debug_ack_error_o` pulses HIGH for 1 clock cycle
- Occurs when `bit_name = ack_delimiter_bit` AND `sample_strobe = '1'`
- Timing: After ACK slot, at or near delimiter

---

### Group 5: Transfer Status (Frame Outcome)
```
├─ llc_user_o.avalon_st_sink.valid         [Binary] - Frame accepted by LLC
├─ llc_user_o.avalon_st_sink.ready         [Binary] - LLC ready for frame
├─ debug_mac_to_pcs.valid (from mac_ser)   [Binary] - Serializer has data
└─ fce_o.transmitting                      [Boolean] - Currently transmitting
```

**Why**: Shows frame lifecycle. For error tests:
- Frame starts: ready & valid both high
- Frame transmitting: valid high, ready = '0'
- Frame ends: transfer_status indicates outcome (transmitted/disturbed/lost_arb)

---

### Group 6: State Machines (Debug Navigation)
```
├─ debug_tdc_state_o                       [Enum: PCS states]
│  └─ Shows: idle, measuring_delay, transmitting_nominal, transmitting_data
└─ FSM state (if accessible via force-signal)
   └─ Shows: transmitting_frame, transmitting_error_flag, intermission, etc.
```

**Why**: Helps navigate where you are in frame transmission flow

---

## Signal Organization in GTKWave

### Suggested Hierarchy:
```
tx_error_detection_tb
├─ [TIMING] Clock & Strobes
│  ├─ clk
│  ├─ debug_pcs_to_mac.sample_strobe
│  ├─ debug_strobe_type_o
│  └─ rst
├─ [FRAME] Transmission Status
│  ├─ debug_mac_to_pcs.data.bit_name
│  ├─ debug_mac_to_pcs.valid
│  └─ debug_current_bit_rate_o
├─ [BUS] Physical Layer
│  ├─ tx_bus_o
│  ├─ rx_bus_i
│  └─ debug_pcs_to_mac.bus_polarity
├─ [ERROR] Error Detection ⭐ PRIMARY GROUP
│  ├─ debug_ack_error_o           ← Watch this!
│  ├─ debug_form_error_o
│  ├─ debug_data_phase_exit_o
│  ├─ debug_error_at_ssp_o
│  └─ debug_error_at_sp_o
├─ [STATUS] Frame Outcome
│  ├─ llc_user_o.avalon_st_sink.valid
│  ├─ llc_user_o.avalon_st_sink.ready
│  └─ fce_o.transmitting
└─ [STATE] Machine States
   ├─ debug_tdc_state_o
   └─ FSM state (if accessible)
```

---

## Signal Value Formatting Recommendations

### Enumerations (Most Important - Use Default Display)
```
bit_name              → Shows enum: sof_bit, base_id_bit, ack_slot_bit, etc.
strobe_type_o         → Shows enum: sp_strobe, ssp_strobe
tdc_state_o           → Shows enum: idle, measuring_delay, transmitting_nominal, etc.
bus_polarity          → Shows enum: dominant, recessive, unknown
```

**In GTKWave**: Right-click signal → Properties → Format: "Values"

### Binary (Good for Timing)
```
clk                   → Shows 0/1
sample_strobe         → Shows pulse timing
debug_ack_error_o     → Shows pulse as narrow spike (1 clock wide)
```

**In GTKWave**: Analog wave view for strobes, Digital wave for clk/rst

### Radix: Unsigned Integer (for Counters)
```
test_cycle_counter    → Shows numeric count
sample_point_counter  → Shows count progression
```

---

## Critical Signal Combinations for Test Verification

### ACK Error Detection Verification
```
Watch together:
1. bit_name = ack_slot_bit           (where in frame)
2. debug_pcs_to_mac.bus_polarity     (what's on bus)
3. sample_strobe = '1'               (when sampling)
4. debug_ack_error_o = '1'           (error detected)
5. Then: rx_bus_i should still be recessive (no receiver ACK)
```

**Expected waveform pattern**:
```
bit_name:       ... ack_slot_bit ... ack_delimiter_bit ...
bus_polarity:   ... recessive   ... recessive (ERROR) ...
sample_strobe:  _____/ \________/ \________/ \_______
debug_ack_error: ___________________/ \__________  (pulse here)
```

### Form Error Detection Verification (Future)
```
Watch:
1. bit_name in control field (fdf_bit, res_bit, brs_bit, esi_bit)
2. debug_mac_to_pcs.polarity shows illegal pattern
3. debug_form_error_o pulses
```

### TDC Error Detection Verification (Future)
```
Watch:
1. strobe_type = ssp_strobe (in data phase)
2. bus_polarity mismatches transmitted polarity
3. debug_error_at_ssp_o pulses
4. Next SP (strobe_type = sp_strobe): debug_error_at_sp_o pulses
```

---

## GTKWave Configuration (.gtkw File) Template

```tcl
@28
clk
debug_pcs_to_mac.sample_strobe
debug_strobe_type_o
rst

@28
debug_mac_to_pcs.data.bit_name
debug_mac_to_pcs.valid
debug_mac_to_pcs.data.polarity
debug_current_bit_rate_o

@28
tx_bus_o
rx_bus_i
debug_pcs_to_mac.bus_polarity

@28
debug_ack_error_o
debug_form_error_o
debug_data_phase_exit_o
debug_error_at_ssp_o
debug_error_at_sp_o

@28
llc_user_o.avalon_st_sink.valid
llc_user_o.avalon_st_sink.ready
debug_mac_to_pcs.valid
fce_o.transmitting

@28
debug_tdc_state_o
```

---

## Pro Tips for Waveform Analysis

### 1. Use Color Coding
- **Red**: Error signals (debug_ack_error_o, debug_form_error_o)
- **Green**: Strobes (sample_strobe, pulses)
- **Blue**: Clock (clk)
- **Gray**: Status signals

In GTKWave: Right-click signal → Trace Color

### 2. Zoom to Region of Interest
- Set timeline markers at:
  - Frame start (SOF)
  - ACK slot start
  - ACK slot end
  - Error pulse

Command: Click on signal spike, then zoom in

### 3. Enable Grid
- View → Show Grid
- Set grid size to 10 time units
- Helps count cycles between strobes

### 4. Use Bookmarks
GTKWave: Edit → Add Bookmark at key moments
- Frame transmission start
- ACK slot detected
- Error pulse moment
- Recovery sequence

### 5. Compare Multiple Traces
For Phase 3D (TDC), open side-by-side:
- One trace at SP (normal sampling)
- One trace at SSP (TDC sampling)
- Watch for error detection timing differences

---

## Recommended Display Settings

| Setting | Value | Reason |
|---------|-------|--------|
| Time scale | 1 ns (or per your clk_period) | Fine-grain timing visibility |
| Initial zoom | Fit all | See full frame structure |
| Wave height | Medium (3-4 pixels) | Balance detail with vertical space |
| Unnamed group collapse | Yes | Reduce clutter initially |
| Trace search | Case-insensitive | Easier finding signals |

---

## Signals by Test Phase

### Phase 3A: ACK Error Detection
**Essential**:
- debug_ack_error_o ⭐
- debug_mac_to_pcs.data.bit_name
- debug_pcs_to_mac.sample_strobe
- tx_bus_o / rx_bus_i

**Nice to have**:
- debug_tdc_state_o (context)
- fce_o.transmitting (frame progress)

### Phase 3B: Form Error Detection
**Essential**:
- debug_form_error_o ⭐
- debug_mac_to_pcs.data.bit_name
- debug_mac_to_pcs.data.polarity
- debug_pcs_to_mac.sample_strobe

### Phase 3C: Data Phase Completion
**Essential**:
- debug_data_phase_exit_o ⭐
- debug_current_bit_rate_o
- debug_mac_to_pcs.data.bit_name
- debug_pcs_to_mac.sample_strobe

### Phase 3D: TDC Error Path
**Essential**:
- debug_strobe_type_o ⭐ (distinguish SP vs SSP!)
- debug_error_at_ssp_o ⭐
- debug_error_at_sp_o ⭐
- debug_pcs_to_mac.sample_strobe
- debug_current_bit_rate_o
- debug_mac_to_pcs.data.bit_name

**Critical for TDC**: Must see SP and SSP strobes separately!

---

## Summary: The "Golden Set" for Error Testing

If you only have room for essential signals, use this core set:

```
═══ TIMING ═══
├─ clk
├─ debug_pcs_to_mac.sample_strobe
└─ debug_strobe_type_o

═══ FRAME ═══
├─ debug_mac_to_pcs.data.bit_name
└─ debug_current_bit_rate_o

═══ BUS ═══
├─ tx_bus_o
├─ rx_bus_i
└─ debug_pcs_to_mac.bus_polarity

═══ ERRORS ⭐ ═══
├─ debug_ack_error_o
├─ debug_form_error_o
├─ debug_error_at_ssp_o
└─ debug_error_at_sp_o
```

This set gives you:
✓ Frame position (bit_name)
✓ Sampling timing (strobes)
✓ Bus behavior (tx/rx/polarity)
✓ Error events (all debug signals)
✓ Phase tracking (bit rate, strobe type)

**That's ~13 signals for complete visibility of error detection**

