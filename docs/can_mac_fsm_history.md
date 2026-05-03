# MAC FSM Refactor History

This file documents the design rationale and refactor history of
`src/can_mac/hdl_src/can_mac_fsm.vhd`.

## Starting point

The MAC was split into two independent FSM entities,
`can_mac_fsm_tx` (~700 lines, 21 states) and `can_mac_fsm_rx` (~640
lines, 19 states), wired together at the `can_mac` top via a
`transmitting_i` flag from TX to RX and dominant-wins OR-merging of
their PCS outputs. Most states were duplicated and the two FSMs
re-derived frame position independently. Debugging cross-FSM behaviour
was painful (the trigger was `can_mac_pcs_fce_tb` reporting
`c_disturbed` instead of `c_transmitted` on a node that had
successfully transmitted), and any new feature had to be added in two
places at once.

`can_mac_fsm.vhd` is the unified replacement: a single synchronous
process with one `t_fsm_state` enum, one `is_transmitter` mode flag
latched at SOF, one shared bit stuffer, one shared CRC engine, and the
existing TX byte serializer. RX path produces a byte stream to the
LLC RX sink; TX path consumes bytes from the LLC TX serializer. FCE
stays external.

## How the unification was done

The first attempt put both TX drive and RX state advance at the PCS
sample point (SP), which seemed natural ("everything happens at SP")
but was wrong for several reasons. The bugs we hit and the fixes that
accumulated are listed below; each one nudged the design toward what
the legacy CC-only `can_fsm` had been doing all along, and the final
shape is essentially the same model -- TX-drive at `bit_boundary`, RX
at SP, BS/CRC fed from the bus -- extended with FD support and an
external FCE.

### 1. TX drive at SP arrived too late

PCS latches `mac_i.tx_data` into `tx_o` at `bit_boundary_d` (one clock
after the bit boundary). Driving at SP meant `tx_data` updated
mid-bit; PCS missed the latch window and `tx_o` was stale by a whole
bit period. Fix: TX drive moved to a `bit_boundary` branch per state.
Each drive site sets `v_drive_polarity` / `v_drive_now`, committed in
a single block at the end of the process that writes
`pcs_o.tx_data`, asserts `pcs_o.transmitting` / `fce_o.transmitting`
and shifts the polarity history. Mirrors the `transmit_i` pattern of
the legacy `can_fsm`.

### 2. polarity_history was shifted at SP

`transmitted_bits_shift_reg(0)` is consumed by the TX bit-error
monitor and the SSP/TDC compare. With drive moving to `bit_boundary`,
the shift had to move too -- otherwise the monitor compared the wrong
bit. Fix: the drive-commit block shifts the history at the moment of
the drive.

### 3. PCS hard-sync was firing on TX nodes too

Hard-sync re-aligns the PCS to a bus edge it observes during
quiet/arbitration. On a TX node the bus edge is our own drive, and
re-syncing throws our bit timing off. Fix: PCS gates hard-sync on
`mac_i.transmitting = '0'`. The MAC FSM only needs to assert
`pcs_o.do_hard_sync`; the role guard happens one level down.

### 4. Lost-arb and TX bit error fought over the same SP

In `s_arbitration`, "we drove recessive and bus came back dominant"
is *lost arbitration*, not a bit error. The original check fired
both. Fix: the TX bit-error monitor explicitly excludes
`s_arbitration`; lost-arb is detected first, flips `is_transmitter`
to false in-place, and the `s_arbitration` case then runs in RX mode
for the remaining bits.

### 5. BS/CRC source

Initial design: TX feeds BS/CRC from its own drive (lookahead); RX
feeds them from `rx_data` (the bus). After losing arbitration the
previously-TX node had to continue as RX with BS/CRC state matching
the *winner*, but its BS/CRC had been fed lookahead bits from its own
(losing) frame.

First fix: feed BS/CRC from `pcs_i.rx_data` at SP for *both* modes.
Loopback guarantees `rx_data == drive` for the winner in nominal
phase, so this is correct for winning TX and naturally correct after
a lost-arb flip.

Second fix (FD): in the data phase the TDC delay can exceed the data
bit time, so `rx_data` lags TX's drive by `k` bits and feeding BS
from the echo would insert stuff bits `k` bits late. Post-arbitration
TX now feeds BS/CRC from `transmitted_bits_shift_reg(0)` (the bit
just driven). RX and the arbitration field still feed from the bus.

### 6. SOF drive in s_bus_idle

The bit_boundary branch latches `is_transmitter <= true` and sets the
drive polarity on the same clock, so PCS sees `pcs_o.transmitting =
'1'` and `pcs_o.tx_data = c_dominant` at the next `bit_boundary_d`.

### 7. fce_o.transmitting in s_ack contradicted ISO 8.1.4.2.b

An earlier centralised `v_transmitting` derivation forced
`fce_o.transmitting <= '0'` for TX in `s_ack` ("TX listens"), but
ISO 8.1.4.2.b says ACK-slot bit errors must count as TX-side.
Replacement: the drive-commit block sets `transmitting = '1'` on
every TX drive, NBA holds the level across `s_ack`, and the `s_ack`
RX branch explicitly clears `pcs_o.transmitting` (so the receiver
releases the bus) without touching `fce_o.transmitting`.

### 8. Process variables hiding state

An early cut had a `v_is_tx` variable as a delayed copy of
`is_transmitter`. Redundant -- `bit_boundary` and SP are different
strobes that never fire in the same cycle. Dropped.

### 9. Per-state TX/RX branching mostly redundant

Once BS/CRC are fed from the bus and TX drive lives at `bit_boundary`,
the SP-time case body for most states does not need to know who is
driving. For TX winning, `rx_data == drive` everywhere except
`s_ack`, so:

- `llc_frame` is captured from `rx_data` unconditionally (TX
  self-receives so the LLC RX byte stream is also populated on the
  transmitter).
- State-exit decisions use `rx_data` and previously captured
  `llc_frame` fields rather than `mac_ser_i.llc_metadata`.
- SBC and CRC compares are RX-only (TX never trips them; in the FD
  data phase TX's delayed self-echo would falsely trip them).

States that genuinely diverge -- `s_ack`, `s_ack_delimiter`, `s_eof`
-- keep an explicit `if is_transmitter` branch.

### 10. Big nested if/elsif chains for bit_count

`s_arbitration` originally had two if/elsif chains over `bit_count`
(capture and state-exit). Both became a single `case bit_count is`
with one branch per sub-field (ID-A/ID-B share a branch via VHDL-2008
range/choice syntax).

### 11. SP block and bit_boundary block were 500 lines apart

Reading e.g. `s_arbitration` meant flipping between two case
statements. Folded the `bit_boundary` case body into each per-state
branch, so each state owns its `bit_boundary` TX drive AND its SP
capture/advance in one place (matches the legacy `can_fsm`
`if transmit_i / elsif sample_rx_i` shape). BS/CRC feed is inlined
per state too.

### 12. TX path re-derived data_len from delayed echo

In the FD data phase the TX self-echo is TDC-delayed (`rx_data` at
SP of bit N reflects what TX drove ~k bits earlier). Two TX paths
were re-deriving frame state from `rx_data` and tripping on
themselves: `s_dlc` end-of-state and `s_sbc` mismatch compare. Fix:
TX keeps the metadata-derived `data_len` / `crc_length` /
`crc_poly_select` from SOF; the SBC mismatch is RX-only.

### 13. next_bit_is_res / next_bit_is_brs timing

These are hints to the PCS about the bit *following* the SP they
fire on. Earlier code asserted them at the named bit's own SP,
which was a one-bit error. Now `next_bit_is_res` fires at SP of
FDF (TX-only, FDF=recessive); `next_bit_is_brs` fires at SP of res
(both roles).

### 14. Per-state RX stuff-error blocks lifted

The "if not is_transmitter and `bs_i.data /= rx_data` then enter
error frame" check appeared verbatim in seven states. Lifted to a
single global SP-time monitor next to the TX bit-error monitor,
gated on the relevant states.

## Net result

A single FSM that occupies roughly the same conceptual space as the
legacy CC-only `can_fsm`, with FD support folded in via the
FDF/BRS/ESI/SBC states and the data-phase / TDC machinery, and with
FCE pulled out as a separate entity instead of being intertwined with
the FSM. The structure (TX-drive at `bit_boundary`, RX at SP, BS/CRC
from the bus in nominal / from the drive in the FD data phase, mode
flag latched at SOF) is the same. Most of the bugs above were the
cost of rediscovering why the legacy code looked the way it did.

## Single-strobe PCS-MAC interface

The original design carried `bit_boundary` as a second strobe on the
`t_can_mac_pcs_if_s2m` record. PCS drove `bit_boundary` at the end of
phase_seg2, then latched `tx_o <= mac_i.tx_data` one clock later via a
`bit_boundary_d` register. This created a 3-clock pipeline from SP:

```
SP(K) -> MAC drives pcs_o.tx_data (NBA) at K+1 -> bit_boundary fires at K+2
      -> bit_boundary_d fires at K+3 -> tx_o latches = mac_i.tx_data
```

With FD data-phase minimum timing (phase_seg2 = 1 TQ = 2 system clocks,
sync_seg = 1 TQ = 2 system clocks), `tx_o` was updating 1 clock into the
new bit's sync_seg -- a marginal timing hazard that worsens as prescaler
shrinks.

### Fix: drop bit_boundary, register SP in the MAC

`bit_boundary` was removed from `t_can_mac_pcs_if_s2m` entirely. The MAC
FSM generates an internal `drive_bit` strobe by registering
`pcs_i.sample_point` twice:

```vhdl
drive_bit_d <= pcs_i.sample_point;   -- SP+1
drive_bit   <= drive_bit_d;           -- SP+2
```

All TX drive branches that previously tested `pcs_i.bit_boundary = '1'`
now test `drive_bit = '1'`. The conceptual model -- "drive at
bit_boundary, capture at sample_point" -- is unchanged; the strobe is
now generated inside the MAC rather than routed from the PCS.

PCS latches `tx_o` unconditionally inside the bit_boundary branch itself
(no `bit_boundary_d` register, no `transmitting` gate):

```vhdl
elsif seg_count >= ((active_phase_seg2 - 1) - phase2_shortening) then
  tx_o              <= mac_i.tx_data;   -- latch at bit_boundary itself
  bit_boundary      <= '1';
  ...
```

The updated pipeline:

```
SP(K) -> drive_bit_d='1' at K+1 -> drive_bit='1' at K+2
      -> MAC drives pcs_o.tx_data (NBA) at K+2
      -> pcs_o.tx_data visible as mac_i.tx_data at K+3 (rising edge K+3 start)
      -> bit_boundary fires at K+BB_offset
      -> tx_o latches mac_i.tx_data at same clock
```

Because BB is further from SP than 2 clocks (phase_seg2 >= 2 system
clocks), `mac_i.tx_data` is always stable when the latch fires. `tx_o`
updates at the bit boundary itself, not one clock after it -- no timing
hazard at any FD data-phase configuration.

### TX loopback independence for state transitions

Three bugs were found when the `test_bus_off` testbench procedure forced
DUT 1's loopback to always-recessive (`s_dut_1_rx_recessive`).  The MAC
FSM used `pcs_i.rx_data` for several TX-side state-transition decisions,
assuming loopback gives `rx_data == drive`.  That assumption is correct
for normal operation and tests 1-3, but breaks when the testbench
overrides the loopback.

**1. `s_bus_idle` SOF transition**

The SP branch that enters `s_arbitration` checked `pcs_i.rx_data =
c_dominant` (SOF echo).  With forced-recessive loopback the echo never
appeared, so the TX node could never leave `s_bus_idle`.

Fix: the condition is now `is_transmitter or pcs_i.rx_data = c_dominant`.
`is_transmitter` is false at `s_bus_idle` entry (cleared by both the
`s_intermission → s_bus_idle` and `s_suspend_transmission → s_bus_idle`
transitions) and becomes true only at the `drive_bit` SOF drive, so using
it here cannot fire prematurely.

**2. `s_arbitration` IDE detection**

At `c_arb_ide_pos`, the transition to `s_fdf_r1_r0` checked
`pcs_i.rx_data = c_dominant`.  With forced-recessive loopback the TX node
stayed in `s_arbitration` forever (bit_count kept incrementing past the
IDE position).

Fix: for TX (`is_transmitter`), use `transmitted_bits_shift_reg(0)` (the
bit that was actually driven) instead of `pcs_i.rx_data`.  In normal
operation these are equal, so tests 1-3 are unaffected.

**3. `s_suspend_transmission` did not clear `was_previous_frame_tx`**

After an error-passive TX node completes its 8-bit suspend-transmission
wait and re-enters `s_bus_idle`, the `s_bus_idle` TX gate checks
`fce_i.error_active = '1' or not was_previous_frame_tx`.  The flag
`was_previous_frame_tx` is set to `true` in `s_error_flag` (disturbed
frame) and is only cleared at reset or on lost-arbitration.  After suspend
the flag was still `true`, so the gate evaluated to `'0' or false = false`
and the node could never retransmit: TEC stalled at 128.

Fix: add `was_previous_frame_tx <= false` to the
`s_suspend_transmission → s_bus_idle` transition.  Tests 1-3 never reach
`s_suspend_transmission` (they are in error-active throughout), so this
change is invisible to them.

### Testbench note

The 37-clock shift from BB to drive_bit (drive_bit fires earlier in the
bit period) exposed a timing coincidence in `test_lost_arb`: with
prescaler=2 (200 system clocks per nominal bit), the 3000-clock settle
wait always ended at the same phase within a bit, and the interleaved
Send loop of exactly 142 clocks put DUT1's serializer valid at the exact
clock drive_bit fired. DUT1 would fire SOF alone, defeating the
lost-arbitration scenario. Fix: a `WaitForClock(clk, 3 * c_bit_time)`
guard before the Send loop shifts the send window so drive_bit fires
before either serializer is valid.
