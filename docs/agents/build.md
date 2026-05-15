# Build Reference

## Command

```
make TB=src/<module>/hdl_tb/<tb> all
```

Runs compile + simulate + open waveform.

## Full compile order

```
can_types_p.vhd → can_tb_p.vhd → can_mac_bs → can_mac_crc → can_mac_ser
→ can_mac_fsm → can_fce → can_mac → can_pcs → can_mac_pcs_fce
→ can_llc → can_fd_controller → <testbench>.vhd
```

Packages first, then leaf modules, then wrappers.

## GHDL flags

```
--std=08 -fpsl --warn-no-vital-generic --warn-no-hide -P./OsvvmLibraries/osvvm/VHDL_LIBS/GHDL-6.0.0-dev -P.
```

## Waveforms

```
gtkwave sim/<tb>.ghw src/<module>/test_case/<tb>.gtkw
```

GHW preserves enum names and record fields. VCD cannot - use GHW always.

## Stale units

Modifying `pk_can_types` requires re-analyzing the entire chain from the top.
