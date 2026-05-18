# Waveform Capture Specification

Six waveform figures are pending. Each section below specifies the testbench, test procedure, signals to show (top to bottom), key events that must be visible in the capture, and the output filename.

Run all simulations with:

```
make TB=src/<module>/hdl_tb/<tb> all
```

Then open the `.ghw` file from `sim/` in GTKWave using the corresponding `.gtkw` save file as a starting point.

Export each figure as PDF at 1920x1080, cropped to the time window specified.

---

## Figure 1 - Dynamic bit stuffing

**Output file:** `figures/waveforms/bs_dynamic.pdf`
**Report label:** `fig:bs_dynamic`
**Testbench:** `src/can_mac_bs/hdl_tb/can_mac_bs_tb.vhd`
**Make:** `make TB=src/can_mac_bs/hdl_tb/can_mac_bs_tb all`
**GTKWave starting point:** `src/can_mac_bs/test_case/can_mac_bs_tb.gtkw`

### Signals (top to bottom)

```
top.can_mac_bs_tb.clk_i
top.can_mac_bs_tb.bs_i          -- record: show bs_i.data and bs_i.valid
top.can_mac_bs_tb.bs_o          -- record: show bs_o.data and bs_o.valid
top.can_mac_bs_tb.u_dut.stuff_count
top.can_mac_bs_tb.u_dut.last_polarity
```

### Time window

Find the dynamic stuffing test section. Zoom to show two stuffing events back to back:

1. **Dominant run:** five consecutive dominant bits on `bs_i.data` → one recessive stuff bit inserted on `bs_o.data` (`bs_o.valid` pulses high for the stuff bit, `bs_i.valid` is held off for one cycle). `stuff_count` counts 0→5 then resets.
2. **Recessive run:** five consecutive recessive bits → one dominant stuff bit inserted. Same handshake pattern.

The two events should both be visible in the same capture without zooming between them. The `stuff_count` counter incrementing and resetting to zero is the key diagnostic signal - make sure it is readable.

---

## Figure 2 - Fixed bit stuffing mode transition

**Output file:** `figures/waveforms/bs_fixed.pdf`
**Report label:** `fig:bs_fixed`
**Testbench:** `src/can_mac_bs/hdl_tb/can_mac_bs_tb.vhd`
**Make:** `make TB=src/can_mac_bs/hdl_tb/can_mac_bs_tb all`
**GTKWave starting point:** `src/can_mac_bs/test_case/can_mac_bs_tb.gtkw`

### Signals (top to bottom)

```
top.can_mac_bs_tb.clk_i
top.can_mac_bs_tb.bs_i                    -- bs_i.data, bs_i.valid, bs_i.fixed_bit_stuffing_en
top.can_mac_bs_tb.bs_o                    -- bs_o.data, bs_o.valid
top.can_mac_bs_tb.u_dut.stuff_count
top.can_mac_bs_tb.u_dut.fsb_en_latch
top.can_mac_bs_tb.u_dut.last_polarity
```

### Time window

Find the mode-transition case where a dynamic stuff bit is pending at the moment `bs_i.fixed_bit_stuffing_en` rises. The key event sequence is:

1. Dynamic stuffing active - `stuff_count` has reached 5 (or is about to), meaning a stuff bit is due.
2. `bs_i.fixed_bit_stuffing_en` rises on the same cycle (or one cycle before the stuff bit would fire).
3. The pending dynamic stuff bit is **promoted** to become the initial fixed stuff bit (FSB) rather than being suppressed. This is visible as: `bs_o.valid` fires with the stuff bit polarity, `fsb_en_latch` asserts, and fixed-interval stuffing continues from that point.
4. Subsequent fixed stuff bits appear at regular intervals (every 4 data bits) on `bs_o`.

This is the mode-boundary promotion rule. The caption in the report calls it out explicitly - the waveform must make it unambiguous that the stuff bit fires at the transition, not after it.

---

## Figure 3 - Dual bit rate switching and TDC

**Output file:** `figures/waveforms/pcs_tdc.pdf`
**Report label:** `fig:pcs_tdc`
**Testbench:** `src/can_pcs/hdl_tb/can_pcs_tb.vhd`
**Make:** `make TB=src/can_pcs/hdl_tb/can_pcs_tb all`
**GTKWave starting point:** `src/can_pcs/test_case/can_pcs_tb.gtkw`
**Test procedure:** `test_normal` (`test_num = 2`)

### Signals (top to bottom)

```
-- TX PCS node
top.can_pcs_tb.u_pcs_tx.mac_i.next_bit_is_brs
top.can_pcs_tb.u_pcs_tx.mac_i.next_bit_is_res
top.can_pcs_tb.u_pcs_tx.mac_i.data_phase_stop
top.can_pcs_tb.bus_level                           -- wired-AND bus
top.can_pcs_tb.u_pcs_tx.mac_o.sample_point
top.can_pcs_tb.u_pcs_tx.mac_o.secondary_sample_point
top.can_pcs_tb.u_pcs_tx.data_phase_active
top.can_pcs_tb.u_pcs_tx.tdc_count_active
top.can_pcs_tb.u_pcs_tx.delay_count_tq
top.can_pcs_tb.u_pcs_tx.ssp_active
top.can_pcs_tb.u_pcs_tx.mac_o.tdc_delay
top.can_pcs_tb.u_pcs_tx.active_phase_seg1         -- shows segment length change at BRS
```

### Time window

Find a frame in `test_normal` where BRS is recessive (data phase enabled). Zoom to the region from two arbitration-phase bits before BRS through the first three data-phase bits. The following sequence must be visible:

1. `next_bit_is_brs` asserts one SP before the BRS bit.
2. At the BRS SP, `data_phase_active` asserts and `active_phase_seg1` (and prop/phase_seg2) switch to data-phase values - the bit period visibly shortens on `bus_level`.
3. `next_bit_is_res` asserts. At the res bit boundary, `tdc_count_active` sets and `delay_count_tq` begins incrementing.
4. The TX-to-RX echo (dominant edge returning on `bus_level`) clears `tdc_count_active`, freezing `delay_count_tq` at the measured delay.
5. `ssp_active` asserts. `secondary_sample_point` fires once per data-phase bit at the measured SSP offset. `mac_o.tdc_delay` is stable.
6. `data_phase_stop` arrives (CRC delimiter). `data_phase_active` and `ssp_active` clear.

---

## Figure 4 - Arbitration loss

**Output file:** `figures/waveforms/lost_arb.pdf`
**Report label:** `fig:lost_arb`
**Testbench:** `src/can_mac_pcs_fce/hdl_tb/can_mac_pcs_fce_tb.vhd`
**Make:** `make TB=src/can_mac_pcs_fce/hdl_tb/can_mac_pcs_fce_tb all`
**GTKWave starting point:** `src/can_mac_pcs_fce/test_case/can_mac_pcs_fce_tb.gtkw`
**Test procedure:** `test_lost_arb` (`test_num = 4`)

### Signals (top to bottom)

```
top.can_mac_pcs_fce_tb.bus_level
-- DUT 1 (losing node)
top.can_mac_pcs_fce_tb.u_dut_1.u_mac.u_can_mac_fsm.state
top.can_mac_pcs_fce_tb.u_dut_1.u_mac.u_can_mac_fsm.is_transmitter
top.can_mac_pcs_fce_tb.u_dut_1.u_pcs.mac_o.sample_point
top.can_mac_pcs_fce_tb.u_dut_1.u_pcs.mac_o.rx_data
-- DUT 2 (winning node)
top.can_mac_pcs_fce_tb.u_dut_2.u_mac.u_can_mac_fsm.state
top.can_mac_pcs_fce_tb.u_dut_2.u_mac.u_can_mac_fsm.is_transmitter
```

### Time window

Find `test_lost_arb`. Zoom to the arbitration field region where the two nodes transmit different ID bits. The key event is:

1. Both `state` signals are in `s_arbitration`. Both `is_transmitter` flags are `'1'`.
2. DUT 1 drives recessive, DUT 2 drives dominant. `bus_level` is dominant (wired-AND).
3. At the SP strobe, DUT 1 samples dominant while having transmitted recessive - arbitration loss detected.
4. DUT 1 `is_transmitter` flips to `'0'`. DUT 1 `state` **stays in `s_arbitration`** - no state transition. This is the key point: the state name does not change, only `is_transmitter`.
5. DUT 2 continues transmitting (both `state` and `is_transmitter` unchanged).

The waveform must make it clear that DUT 1's state signal does not change at the loss event - only `is_transmitter` changes. That is the whole point of the unified FSM at this boundary.

---

## Figure 5 - Active error frame

**Output file:** `figures/waveforms/error_frame.pdf`
**Report label:** `fig:error_frame`
**Testbench:** `src/can_mac_pcs_fce/hdl_tb/can_mac_pcs_fce_tb.vhd`
**Make:** `make TB=src/can_mac_pcs_fce/hdl_tb/can_mac_pcs_fce_tb all`
**GTKWave starting point:** `src/can_mac_pcs_fce/test_case/can_mac_pcs_fce_tb.gtkw`
**Test procedure:** `test_bus_off` (`test_num = 5`) - error frames are generated during the TEC escalation sequence

### Signals (top to bottom)

```
top.can_mac_pcs_fce_tb.bus_level
top.can_mac_pcs_fce_tb.u_dut_1.u_mac.u_can_mac_fsm.state
top.can_mac_pcs_fce_tb.u_dut_1.u_pcs.mac_o.sample_point
top.can_mac_pcs_fce_tb.u_dut_1.u_mac.u_can_mac_fsm.fce_o.error
top.can_mac_pcs_fce_tb.u_dut_1.u_fce.tec
top.can_mac_pcs_fce_tb.u_dut_1.u_fce.error_active
```

### Time window

Find the first error frame in `test_bus_off`. Zoom to show from two bits before the error detection through the end of the error delimiter. The sequence must be visible:

1. DUT 1 is transmitting in the data field. `state = s_data`.
2. A recessive bit is injected on `bus_level` while DUT 1 is driving dominant (or vice versa). At the SP, bit error is detected.
3. `state` transitions to `s_error_flag`. DUT 1 drives six dominant bits on `bus_level` (active error flag - visible as a sustained dominant run).
4. `fce_o.error` pulses for one cycle at the transition from `s_error_flag` to `s_error_delimiter`. This is the FCE increment trigger - it must be clearly visible.
5. `tec` increments by 8.
6. `state` steps through `s_error_delimiter` (eight recessive bits on `bus_level`).
7. `state` transitions to `s_intermission` and then back toward `s_arbitration`.

---

## Figure 6 - Bus-off recovery

**Output file:** `figures/waveforms/bus_off_recovery.pdf`
**Report label:** `fig:bus_off_recovery`
**Testbench:** `src/can_fce/hdl_tb/can_fce_tb.vhd`
**Make:** `make TB=src/can_fce/hdl_tb/can_fce_tb all`
**GTKWave starting point:** `src/can_fce/test_case/can_fce_tb.gtkw`
**Test procedure:** `test_bus_off_recovery`

### Signals (top to bottom)

```
top.can_fce_tb.clk_i
top.can_fce_tb.fce_i.error           -- MAC error pulses driving TEC up
top.can_fce_tb.fce_o.bus_off
top.can_fce_tb.fce_o.error_passive
top.can_fce_tb.fce_o.error_active
top.can_fce_tb.pcs_i.idle_condition  -- 128 pulses required for recovery
top.can_fce_tb.u_dut.tec
top.can_fce_tb.u_dut.rec
top.can_fce_tb.u_dut.idle_count      -- internal counter toward 128
```

### Time window

The full `test_bus_off_recovery` procedure has two distinct phases. Capture each as a separate zoom level if they do not fit together readably; otherwise show both:

**Phase A - TEC escalation to bus-off:** Error pulses drive TEC from 0 to 256. Show `error_passive` asserting at TEC=128 and `bus_off` asserting at TEC=256. `error_active` deasserts at TEC=128.

**Phase B - Recovery:** `bus_off` is asserted. `pcs_i.idle_condition` pulses 128 times (each pulse represents 11 consecutive recessive bits). `idle_count` increments 0→128. At the 128th pulse, `tec` and `rec` reset to zero, `bus_off` deasserts, and `error_active` reasserts.

Phase B is the primary figure content - it directly corresponds to the report caption. The `idle_count` counter is the clearest diagnostic: it must be visible incrementing to 128 and then the state flags flipping.

---

## Naming convention

Final filenames must match the report references exactly:

| Figure | Output path |
|---|---|
| `fig:bs_dynamic` | `figures/waveforms/bs_dynamic.pdf` |
| `fig:bs_fixed` | `figures/waveforms/bs_fixed.pdf` |
| `fig:pcs_tdc` | `figures/waveforms/pcs_tdc.pdf` |
| `fig:lost_arb` | `figures/waveforms/lost_arb.pdf` |
| `fig:error_frame` | `figures/waveforms/error_frame.pdf` |
| `fig:bus_off_recovery` | `figures/waveforms/bus_off_recovery.pdf` |

The report references these without the `pending_` prefix - update the report figure filenames once images are captured (or rename the files to match the current report references).

> Note: the report currently references `pending_bs_dynamic.pdf`, `pending_bs_fixed.pdf`, etc. Either rename the captured files to match, or do a find-and-replace removing the `pending_` prefix from all six figure paths in `docs/report.md`.
