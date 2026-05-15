# Testbench Guide

Golden reference template: `can_mac_ser_tb.vhd`.

## File layout order

header+libs+entity → constants → DUT signals+OSVVM signals → procedures
→ CreateClock/CreateReset/p_timeout/p_init → DUT inst → VCs → monitors
→ p_test_ctrl → PSL assertions

## OSVVM clock/reset

```vhdl
CreateClock(clk_i, c_clk_period);          -- clk_i: no initializer
CreateReset(rst_i, '1', clk_i, c_clk_period * 3);  -- rst_i := '1' in declaration
wait until rst_i = '0'; WaitForClock(clk_i);
-- Use WaitForClock(clk_i[, N]) not "wait for". Use std.env.finish to end sim.
```

## Random stimulus

`RandomPType` with `rnd.DistBool((false => W1, true => W2))`.

## PSL assertions

- White-box (uses internal signals): keep in DUT.
- Black-box (ports only): duplicate in TB for simulation.
- Use PSL temporal operators (`|=>`, `[*N]`, SERE) for sequences. Do not rewrite as VHDL state machines.

## LLC legacy frame format (71 bytes, Avalon-ST)

- Bytes 0-3: ID (right-aligned 11-bit or full 29-bit)
- Byte 4: `[6:4]`=FMT, `[3:0]`=DLC
- Bytes 5-68: data (64 bytes, zero-padded)
- Byte 69: `[0]`=IDE. Byte 70: `[2]`=BRS, `[1]`=ESI, `[0]`=RTR
- Byte 0: `sop='1'`. Byte 70: `eop='1'`.

Reference implementation: `submit_and_verify` in `can_mac_pcs_fce_tb.vhd`.

## ACK injection

Trigger on `debug_bit_name = ack_bit` (registered, one-cycle delay). Do NOT trigger on `crc_delimiter_bit` at sp - the sample point has already passed by then.

```vhdl
if (inject_ack and debug_bit_name = ack_bit) then
  bus_override <= c_dominant; bus_override_en <= true;
  wait for nom_bit_time_clk_c * clk_period_c;
  bus_override_en <= false;
end if;
```

## Bus loopback

```vhdl
rx_bus_i <= bus_override when bus_override_en else tx_bus_o;
```

Zero delay. Do NOT add propagation delay unless it is shorter than the sample point offset. A delay longer than one bit time causes every bit to fail the bit error check.
