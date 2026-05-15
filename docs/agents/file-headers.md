# File Header Templates

## RTL (`src/<module>/hdl_src/`)

```vhdl
--------------------------------------------------------------------------------
-- Title      : <title>
-- Project    : Implementation and Verification of a CAN-FD Bus Transceiver in VHDL
--------------------------------------------------------------------------------
-- File       : <filename>.vhd
-- Author     : Mads Richardt
-- Standard   : VHDL-2008
--------------------------------------------------------------------------------
-- Description: <purpose; mention PSL assertions if present>
--------------------------------------------------------------------------------
```

## Testbench (`src/<module>/hdl_tb/`)

```vhdl
--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Copyright 2026 Everllence, Teglholmsgade 41, 2450 Copenhagen SV, Denmark
--------------------------------------------------------------------------------------------------------------------------------------------------------------
--
-- Requirements:
--
-- Description:   Testbench for <dut_name>.
--                  p_<name>_vc       - <VC description>.
--                  p_<name>_checker  - <what it monitors>.
--                  p_test_ctrl       - Coverage-driven test sequencer.
--
-- Revision log:  Date:       Initial:  JIRA:
--                YYYY-MM-DD  XXXXX     [TRIT-NNNN] Description
--------------------------------------------------------------------------------------------------------------------------------------------------------------
```

## Rules

- Never write `-- psl` in non-PSL comments. `-fpsl` treats any `-- psl` as a directive.
- Use `----` separators only. Never `====`.
