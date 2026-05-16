# LLC Avalon-ST Handshake Bug in can_mac_ser_tx

**File**: `src/can_mac_ser_tx.vhd`
**Date discovered**: 2026-03-27
**Symptom**: Bytes skipped in the serializer output stream when the downstream MAC FSM ready signal toggles randomly.

---

## 1. Background

The `can_mac_ser_tx` module serializes LLC frame bytes into a bit stream for
the MAC FSM. Internally it has four states:

```
s_load_config_byte_0 -> s_load_config_byte_1 -> s_load_llc_frame_byte -> s_shift_out_bits
                                                         ^                      |
                                                         |______________________|
                                                        (byte boundary reached)
```

The LLC source delivers bytes over an Avalon-ST interface using a ready/valid
handshake. A transfer occurs on a clock edge where both `valid = '1'` and
`ready = '1'`. The serializer (as an Avalon-ST sink) drives the `ready` signal.

The bug was first observed on a company testbench where waveforms showed data
bits being lost in the output stream. The company TB had random ready
commented out (line 204), which masked the bug in normal testing.

---

## 2. Bug 1 - Stale ready after state transition

### What the code did

The `ready` signal was driven inside the clocked process as a default output
at the top of the `else` (non-reset) branch:

```vhdl
-- Default outputs (executes every clock edge)
llc_o.avalon_st_sink.ready <= '0' when (state = s_shift_out_bits) else '1';
```

This is a *registered* assignment. A signal read inside `if rising_edge(clk)`
returns the value that was scheduled on the *previous* clock edge. The `state`
signal used in the condition is also registered. This creates a one-cycle
pipeline delay:

- **Edge N**: DUT is in `s_load_llc_frame_byte`. The default evaluates
  `state /= s_shift_out_bits`, so it schedules `ready <= '1'`.
- **Edge N**: The latch condition in `s_load_llc_frame_byte` is also true.
  The DUT latches the byte and schedules `state <= s_shift_out_bits`.
- **After edge N**: `ready = '1'` and `state = s_shift_out_bits` both take
  effect simultaneously. The DUT is now in `s_shift_out_bits`, but `ready`
  is still `'1'`.
- **Edge N+1**: The default now evaluates `state = s_shift_out_bits` and
  schedules `ready <= '0'`. But between edge N and edge N+1, `ready` was
  `'1'` for one full clock cycle while the DUT was in `s_shift_out_bits` -
  a state where it cannot accept new bytes.

### How this caused byte skipping

The LLC source's `avalon_st_send` procedure waits for `ready = '1'`, then
drives `valid = '1'` and waits one clock edge. On that edge the source
considers the byte transferred and moves on to the next byte.

The DUT, however, is now in `s_shift_out_bits` and does not latch anything
from the LLC interface. The byte that the LLC source thought it delivered
is silently lost. When the DUT finishes shifting out and returns to
`s_load_llc_frame_byte`, it requests the *next* byte, permanently skipping
one byte in the stream.

### Timing diagram (before fix)

```
Edge:     N-1          N             N+1          N+2
state:    load_byte    load_byte     shift_out    shift_out
ready:    '1'          '1'(*)        '0'          '0'
valid:    '1'          '1'           '1'          '0'
          DUT latches  LLC sends     LLC thinks   byte lost
          byte K       byte K+1     K+1 done     forever
                       (stale ready!)
```

`(*)` - This is the stale ready. The DUT latched byte K on edge N and
transitioned to `s_shift_out_bits`, but `ready` does not reflect the new
state until edge N+1.

---

## 3. Bug 2 - Missing ready check in latch condition

### What the code did

The original latch condition in `s_load_llc_frame_byte` only checked the
LLC source's `valid` signal:

```vhdl
when s_load_llc_frame_byte =>
  if (llc_i.avalon_st_source.valid = '1') then   -- BUG: no ready check
    llc_frame_buffer <= llc_i.avalon_st_source.data;
    state            <= s_shift_out_bits;
  end if;
```

In a correct Avalon-ST sink, a transfer only occurs when *both* `valid` and
`ready` are `'1'` on the same clock edge. By omitting the ready check, the
DUT accepted data on the very first clock edge in `s_load_llc_frame_byte`,
even though `ready` had not yet been registered as `'1'`. This meant the LLC
source had not yet observed `ready = '1'` and did not know a transfer had
occurred.

### Why this matters

This bug interacts with the stale-ready fix. Once a pre-emptive deassert of
`ready` was added to prevent the stale-ready problem, the missing ready check
caused a new failure mode:

1. DUT enters `s_load_llc_frame_byte`. Default schedules `ready <= '1'`.
2. LLC source sees `ready = '0'` (still the old registered value from
   `s_shift_out_bits`). It waits.
3. Next edge: `ready = '1'` takes effect. LLC source now drives `valid = '1'`.
4. Same edge: DUT reads `valid = '1'`. Without the ready check, it latches
   immediately. Pre-emptive deassert sets `ready <= '0'`.
5. After this edge: `ready = '0'`. The LLC source's `wait until ready = '1'`
   triggered on step 3 - but the source also does `WaitForClock` after that.
   On the WaitForClock edge, `ready = '0'` again (pre-emptive). The source
   never sees `ready = '1'` *and* gets a clock edge together, so it considers
   the byte not yet transferred. Meanwhile the DUT has already moved on.

The result is a desynchronization where the DUT and the LLC source disagree
about which byte is current.

---

## 4. The fix

Two changes to `s_load_llc_frame_byte`, both on the latch condition:

```vhdl
when s_load_llc_frame_byte =>
  if ((llc_i.avalon_st_source.valid = '1') and
      (llc_o.avalon_st_sink.ready = '1')) then    -- (A) ready check added
    llc_o.avalon_st_sink.ready <= '0';            -- (B) pre-emptive deassert
    count                      <= 0;
    llc_frame_buffer           <= llc_i.avalon_st_source.data;
    state                      <= s_shift_out_bits;
  end if;
```

### (A) Ready check: `llc_o.avalon_st_sink.ready = '1'`

Reading `llc_o.avalon_st_sink.ready` inside the clocked process returns the
*registered* value from the previous clock edge. This guarantees that `ready`
was externally visible as `'1'` for at least one full clock cycle before the
DUT accepts data. The LLC source has had one clock edge to observe `ready = '1'`
and respond with `valid = '1'`.

The cycle-by-cycle behavior becomes:

- **Edge A**: DUT enters `s_load_llc_frame_byte` (from `s_shift_out_bits`).
  Default schedules `ready <= '1'`. But the *registered* ready (from the
  previous edge in `s_shift_out_bits`) is `'0'`. Latch condition is false.
  No latch.
- **Edge B**: Registered `ready = '1'` (scheduled on edge A). If the LLC
  source has driven `valid = '1'`, the latch condition is now true. DUT
  latches the byte.

This one-cycle delay is the correct Avalon-ST behavior. It ensures the source
has observed `ready = '1'` before any transfer occurs.

### (B) Pre-emptive deassert: `llc_o.avalon_st_sink.ready <= '0'`

On the same edge where the DUT latches a byte, it explicitly overrides the
default and schedules `ready <= '0'`. This means:

- After the latch edge: `ready = '0'`. The DUT is now in `s_shift_out_bits`.
- The LLC source sees `ready` drop from `'1'` to `'0'` on the next delta
  cycle. It knows the transfer completed and the sink is no longer accepting.

Without this deassert, the default would schedule `ready <= '1'` (because at
the moment the defaults execute, `state` still reads the old value
`s_load_llc_frame_byte`, not `s_shift_out_bits`). That `'1'` would persist
for one extra cycle, exactly reproducing bug 1.

### Timing diagram (after fix)

```
Edge:     A            B             C             D
state:    shift_out    load_byte     load_byte     shift_out
ready:    '0'          '1'           '0'           '0'
                       (default)     (pre-emptive)
valid:    '0'          '0'           '1'           '0'
                                     DUT latches
                                     LLC sees ready
                                     drop -> done
```

The LLC source drives `valid = '1'` on edge C (after having observed
`ready = '1'` on edge B). The DUT latches on edge C because both
`valid = '1'` and the registered `ready = '1'` (from edge B). The
pre-emptive deassert ensures `ready = '0'` from edge C onwards, preventing
any stale-ready window.

---

## 5. The FSM-side handshake (V_old gating and lookahead)

A related but separate fix was applied to the `s_shift_out_bits` state for the
MAC FSM ready/valid handshake (the downstream interface, not the LLC upstream
interface).

### V_old gating

The advance condition reads the DUT's own registered `valid` output:

```vhdl
if ((tx_mac_fsm_o.valid = '1') and (tx_mac_fsm_i.ready = '1')) then
```

Since `tx_mac_fsm_o.valid` is read inside `rising_edge(clk)`, it returns the
value from the previous clock edge. This means the DUT only advances when the
MAC FSM has had at least one clock edge to observe `valid = '1'`. On the first
edge in `s_shift_out_bits`, the registered valid is `'0'` (cleared by the
default on the previous edge), so no advance occurs. This prevents the DUT
from advancing before the MAC FSM has captured the current bit.

### Lookahead

When the DUT does advance, it immediately outputs the *next* bit's data:

```vhdl
tx_mac_fsm_o.data <= llc_frame_buffer(c_byte_width - 2 - count);
count             <= count + 1;
```

This keeps the output data aligned with what the MAC FSM will capture on the
next valid+ready handshake. Without lookahead, the MAC FSM would see stale
data for one cycle after each advance.

### Valid deassert at boundaries

When the next bit position is a byte boundary (requiring a new byte load) or
a padding region (no data to present), the DUT deasserts valid:

```vhdl
if (count = (c_byte_width - 1)) then
  tx_mac_fsm_o.valid <= '0';
  state              <= s_load_llc_frame_byte;
elsif ((id_bits_remaining = 1) and (padding_bits_remaining > 0)) then
  tx_mac_fsm_o.valid <= '0';
  count              <= count + 1;
```

This prevents the MAC FSM from capturing a "ghost" bit during the transition.

---

## 6. Verification

The fix was verified with `can_mac_ser_tx_tb_with_fsm_model.vhd`, a testbench
that:

1. Generates random LLC frames.
2. Builds the expected bit stream independently from the input bytes.
3. Drives `tx_mac_fsm_i.ready` randomly (50/50 per cycle).
4. Captures every bit on the valid+ready handshake.
5. Compares captured bits against expected bits.

Results:

| Test                              | Frames | Bits/frame | Bit errors |
|-----------------------------------|--------|------------|------------|
| `can_mac_ser_tx_tb_with_fsm_model`| 50     | 523        | 0          |
| `can_tx_tb` (full TX pipeline)    | -      | -          | 0 (38 affirmations PASSED) |
| `can_mac_tx_tb` (MAC wrapper)     | -      | -          | 0 (2200 affirmations PASSED) |

---

## 7. Key VHDL insight

The core of both bugs comes down to one property of clocked VHDL processes:

> A signal read inside `if rising_edge(clk)` returns the value that was
> scheduled on the **previous** clock edge, not the value being scheduled
> on the current edge.

This is because signal assignments in VHDL are non-blocking. The new value
is scheduled but does not take effect until the end of the current simulation
cycle. When the process reads the signal on the same edge, it sees the old
value.

This property is what makes the ready check work (it reads the registered
ready from the previous edge, confirming the source had time to see it) and
what makes the pre-emptive deassert necessary (without it, the default
assignment based on the old state value would schedule an incorrect ready).

The same property is exploited by the V_old gating on the FSM side: reading
`tx_mac_fsm_o.valid` returns the previous edge's value, ensuring the external
observer has already seen the current bit before the DUT advances.
