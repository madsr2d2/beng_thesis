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

## Why two strobes (SP and bit_boundary), not just SP

A natural follow-up question once the FSM was stable: do we need
`pcs_i.bit_boundary` at all, or could the MAC drive TX exclusively at
`pcs_i.sample_point`? Several earlier CAN implementations (including
an older `can_mac_fsm_tx.vhd` in this repo's history at commit
`9ed88885`) drove TX from SP only.

We investigated and chose to **keep both strobes**. The reasoning:

The legacy SP-only TX worked by adopting a one-bit naming offset
between the FSM `state` and the bus. In that convention, "`state` at
this SP" means "the field whose bit MAC is *driving* this cycle for
the *next* bus bit", not "the field whose bit is on the bus right
now". With this convention each state's body uses only its own
`state` and `bit_count` to compute the drive -- no lookahead, no
cross-state coupling at transitions.

The hidden cost is that this convention only fits a TX-only FSM. In
our combined TX+RX FSM, RX captures bus bits in their natural,
bus-bit-aligned timing. If TX drive logic uses the "next-bit" naming
while RX capture uses the "current-bus-bit" naming, every per-state
SP elsif has to mix two mental models.

The two-strobe model side-steps this by having TX drive at
`bit_boundary` (under the natural "state = current bus bit" reading)
and RX capture at `sample_point` (also under the same reading). The
extra wire is a cheap price for keeping TX and RX aligned to the same
indexing of bus bits.

A piecemeal SP-only migration was attempted in early 2026-05; the
first three states (`s_eof`, `s_ack_delimiter`, `s_crc_delimiter`)
migrated cleanly because they all drive `c_recessive`. Going further
backward into the active-frame chain (`s_crc`, `s_sbc`, `s_data`,
`s_dlc`, `s_arbitration`) required either a per-state lookahead at
each transition boundary, or a centralised "next-state first-bit
drive" lookup that essentially re-encodes the bus-bit-alignment of
every drive site. Neither alternative was clearly better than the
two-strobe baseline, so the migration was reverted and we kept BB.
