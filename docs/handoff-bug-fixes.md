# Handoff: Two RTL Bug Fixes to Apply to Work Repo

These two bug fixes exist in the local laptop repo (commit `e335ea8b`, 2026-05-19) but have not been applied to the official work repo. Apply them manually as described below. Both are small, surgical insertions.

---

## Fix 1 - TDC Delay Reset Bug (`can_pcs.vhd`)

**File:** `src/can_pcs/hdl_src/can_pcs.vhd`

**Problem:** `mac_o.tdc_delay` was never reset to zero when the SSP/TDC block was reset, so stale TDC delay values could persist into the next frame.

**Where to insert:** Find the reset block that already sets `ssp_active <= '0'`, `delay_count_tq <= 0`, and `tdc_count_active <= '0'`. In the current file this is around line 317-320. Add the new line immediately after `tdc_count_active <= '0';`.

**Before:**
```vhdl
                      ssp_active                   <= '0';
                      delay_count_tq               <= 0;
                      tdc_count_active             <= '0';
                    end if;
```

**After:**
```vhdl
                      ssp_active                   <= '0';
                      delay_count_tq               <= 0;
                      tdc_count_active             <= '0';
                      mac_o.tdc_delay <= std_logic_vector(to_unsigned(0, mac_o.tdc_delay'length));
                    end if;
```

---

## Fix 2 - Error Flag Bit Error (ISO 8.1.3.3 Rule c) Bug (`can_mac_fsm.vhd`)

**File:** `src/can_mac/hdl_src/can_mac_fsm.vhd`

**Problem:** During active error flag transmission or overload flag transmission, a recessive bit sampled on the bus should immediately trigger a new error (ISO 11898-1:2024 clause 8.1.3.3 rule c). This check was missing, so the node would silently continue instead of extending the error flag.

**Where to insert:** Find the `s_error_flag` (or equivalent) state, inside the `pcs_i.sample_point = '1'` branch, after the block that sets `mac_ser_o.transfer_status <= c_disturbed` and `was_previous_frame_tx <= true`. In the current file this is around line 879. Add the new block immediately after the closing `end if;` of the `is_transmitter` / `not overload` guard.

**Before:**
```vhdl
              elsif pcs_i.sample_point = '1' then
                if is_transmitter then
                  if not overload then
                    mac_ser_o.transfer_status <= c_disturbed;
                    was_previous_frame_tx     <= true;
                  end if;
                  if bit_count < c_error_flag_width - 1 then
```

**After:**
```vhdl
              elsif pcs_i.sample_point = '1' then
                if is_transmitter then
                  if not overload then
                    mac_ser_o.transfer_status <= c_disturbed;
                    was_previous_frame_tx     <= true;
                  end if;
                  -- ISO 8.1.3.3 rule (c): bit error during active error flag or overload flag.
                  if (overload or fce_i.error_active = '1') and pcs_i.rx_data /= c_dominant then
                    fce_o.error <= '1';
                  end if;
                  if bit_count < c_error_flag_width - 1 then
```

---

## Verification

After applying both changes, run the relevant testbenches:

```
make TB=src/can_mac/hdl_tb/can_mac_pcs_fce_tb all
make TB=src/can_pcs/hdl_tb/can_pcs_tb all
```

Both suites passed on the laptop repo after these fixes were applied.
