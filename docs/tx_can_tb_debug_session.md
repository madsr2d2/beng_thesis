# tx_can_tb Integration Testbench - Debug Session Notes

## Overview

This document records the bugs found and fixed during a debug session on `src/tx_can_tb.vhd`, the top-level integration testbench for the CAN transmit pipeline. The initial symptom was a hard crash at the simulation run step with exit code 255 and no output. After seven rounds of diagnosis and fixes, all 40 affirmations pass and the simulation completes cleanly at 2.4 ms.

The sections below document each bug in order of discovery, covering root cause, location, and the fix applied.

---

## Bug 1 - GHDL Exit 255 Crash (SIGABRT) from External Names

### Symptom

Running `make TB=src/tx_can_tb.vhd STOP_TIME=10ms` produced exit code 255 with no output. No error message, no traceback, no VHDL assertion output.

### Root Cause

GHDL's LLVM backend crashes internally in `grt-signals.adb:2403` (`ghdl_process_add_sensitivity`) when VHDL-2008 external names (`<< signal path.to.internal : type >>`) appear on the right-hand side of concurrent signal assignments that drive output ports. The crash is silent.

### Location

`src/tx_mac.vhd` and `src/tx_can.vhd`

### Broken Code (`tx_mac.vhd`)

```vhdl
debug_ack_error_o  <= << signal tx_mac_fsm_inst.ack_error_detected : boolean >>;
debug_form_error_o <= << signal tx_mac_fsm_inst.form_error_detected : boolean >>;
debug_data_exit_o  <= << signal tx_mac_fsm_inst.data_phase_exit_strobe : boolean >>;
```

### Fix

Expose the internal signals as proper output ports at each hierarchy level rather than using external names.

- Added `debug_ack_error_o`, `debug_form_error_o`, `debug_data_exit_o`, and `debug_fsm_state_o` ports to the `tx_mac_fsm` entity, with concurrent assignments at the bottom of its architecture.
- Added `debug_fsm_state_o` port to the `tx_mac` entity and wired it through the port map.
- Added `debug_state_o` port to the `tx_pcs` entity and assigned it from the `state` signal.
- In `tx_can.vhd`: removed all external name references and connected debug signals through proper port maps.
- In `tx_can_tb.vhd`: replaced the external name reference with a port connection in the DUT port map.

---

## Bug 2 - `submit_frame` Sending Internal Format Instead of Legacy Format

### Symptom

All frame-related tests failed. The adapter never saw a valid EOP at byte 70 and never forwarded a frame to the MAC.

### Root Cause

The testbench `submit_frame` procedure was streaming the internal variable-length format (config_0 byte, config_1 byte, 4 ID bytes, N data bytes). The DUT top-level `tx_can` includes an `llc_frame_adapter` that expects the 71-byte legacy LLC frame format defined in `docs/report.md`. The adapter was receiving malformed input and stalling indefinitely.

### Fix

Rewrote `submit_frame` to construct and stream the correct 71-byte layout:

| Byte(s) | Content |
|---------|---------|
| 0-3 | Right-aligned ID (11-bit in bytes 2-3 for basic; 29-bit in bytes 0-3 for extended) |
| 4 | `[7]=0, [6:4]=FMT, [3:0]=DLC` |
| 5-68 | Data bytes, zero-padded to fill the field |
| 69 | `[7:1]=0, [0]=IDE` (derived from the MSB of FMT) |
| 70 | `[7:3]=0, [2]=BRS, [1]=ESI, [0]=RTR` - EOP asserted on this byte |

---

## Bug 3 - Bound Check Failure from Wrong Bit Width in ID Byte Construction

### Symptom

GHDL raised a runtime bounds check failure during Classic Basic frame submission.

### Root Cause

For an 11-bit ID, byte 2 was constructed as:

```vhdl
byte2_v := "000" & frame_v.id(10 downto 8);
```

The concatenation produces 6 bits (`"000"` is 3 bits, `id(10 downto 8)` is 3 bits). Assigning a 6-bit vector to `byte_t` (8 bits) triggers a GHDL bounds check failure at runtime.

### Fix

```vhdl
byte2_v := "00000" & frame_v.id(10 downto 8);
```

The prefix is extended to 5 bits so the total width is exactly 8.

---

## Bug 4 - Test 2 Abort Timing: Status Visible for Only One Registered Cycle

### Symptom

Test 2 (abort during receive) failed intermittently. The `transfer_status = aborted` check was landing on the wrong rising edge and seeing `ongoing` instead.

### Root Cause

After the fix to `llc_frame_adapter`, the adapter signals `aborted` status for exactly one registered clock cycle when abort occurs during the receive phase. The testbench was sampling the status on the wrong edge.

The correct sequence on rising edges is:

1. Send partial byte (SOP, valid, data) - cycle T
2. Assert `abort_request` - cycle T or T+1
3. Cycle T+1: adapter samples abort, registers `transfer_status = aborted`
4. Cycle T+2: testbench reads `transfer_status = aborted` (correct check point)
5. Cycle T+3: check `ready = '1'` (adapter has returned to `receive_frame`)

### Fix

Adjusted the wait counts and check positions in the Test 2 procedure in `tx_can_tb.vhd` to match the correct cycle offsets above.

---

## Bug 5 - Abort During `llc_frame_adapter` Receive Phase: Not Handled

### Symptom

When `abort_request` arrived while `llc_frame_adapter` was buffering the 71-byte legacy frame, the adapter continued buffering and ignored the abort entirely. No `aborted` status was ever produced.

### Root Cause

The `receive_frame` state in `llc_frame_adapter` had no abort handling. The abort input was simply not checked during receive.

### Fix

Added abort handling in the `receive_frame` state:

```vhdl
if (abort_v and rx_index > 0) then
  v_rx_index                     := 0;
  v_legacy_llc_o.transfer_status := aborted;
  status_override_v              := true;
else
  v_legacy_llc_o.avalon_st_sink.ready := '1';
end if;
```

The guard `rx_index > 0` ensures abort is only acknowledged when a frame is actually in progress. When the adapter is idle, abort is silently ignored, which is the correct behavior.

---

## Bug 6 - Test 3 Abort-Ignored Check: Wait Too Short for MAC to Start

### Symptom

Test 3 (abort ignored once frame is handed to MAC) was asserting abort before the MAC had begun transmitting. The abort was landing during the adapter's emit phase, not the MAC's active transmission phase, making the "abort ignored" check meaningless.

### Root Cause

The test submitted a full 71-byte legacy frame and then waited 10 clock cycles before asserting abort. The 71-byte buffering in `llc_frame_adapter`, plus latency through `tx_llc` and `tx_mac_ser`, meant the MAC had not yet started transmitting after only 10 clocks.

### Fix

Changed the test to wait for the SOF bit to appear on the bus before asserting abort:

```vhdl
wait_for_sof(200 us, "Test 3 SOF");
llc_user_i.abort_request <= '1';
```

This guarantees the MAC is actively transmitting when the abort arrives, so the "abort ignored" verification is meaningful.

---

## Bug 7 - Transfer Status Residual Leak Between Frames (Test 4 False Positive)

### Symptom

Test 4 saw `transfer_status = transmitted` briefly at the start of a new frame submission, causing a false positive or spurious status check failure.

### Root Cause

After Test 3 completed a successful transmission, `tx_llc` held `transfer_status = transmitted`. When Test 4 submitted the next frame, `llc_frame_adapter` had this default assignment running before the state machine:

```vhdl
v_legacy_llc_o.transfer_status := llc_i.transfer_status;  -- picks up "transmitted"
```

The state machine then advanced `v_state` to `emit_config_0`, but the default had already captured `transfer_status = transmitted` using the OLD `state` value (`receive_frame`). The previous frame's `transmitted` status leaked into the user-facing output at the start of the new frame's emission phase.

### Fix

Two changes to `llc_frame_adapter`:

**1. Change the default to `ongoing`:**

```vhdl
v_legacy_llc_o.transfer_status := ongoing;
```

**2. Move the pass-through to after the state machine, using `v_state` (next state):**

```vhdl
if (v_state = receive_frame and not status_override_v) then
  v_legacy_llc_o.transfer_status := llc_i.transfer_status;
end if;
```

Using `v_state` (the next-cycle state computed by the state machine) instead of `state` (the current registered state) ensures the pass-through only activates when the adapter is actually idle in the next cycle. The `status_override_v` flag, set by the abort handler in Bug 5, prevents this pass-through from overwriting an `aborted` status.

---

## Final Result

| Metric | Value |
|--------|-------|
| Affirmations passing | 40 / 40 |
| Simulation end time | 2.4 ms |
| Exit code | 0 |

Test coverage after all fixes:

- Classic Basic and Extended frame transmission
- FD Basic and Extended frame transmission
- Abort handling during receive phase
- Abort handling after MAC handoff (abort ignored)
- Transfer status reporting (`transmitted`, `aborted`)
- ACK error detection and recovery
- Bit error detection and recovery
- Overload flag transmission
- Arbitration loss withdrawal
- Remote frame (RTR) support
- Bit rate switching timing (BRS)
