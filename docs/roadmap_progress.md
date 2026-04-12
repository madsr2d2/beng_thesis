# Implementation Roadmap Progress

**Last updated**: 2026-04-12

This document tracks progress against the advisor-recommended implementation roadmap. The strategy is to start at the center of the design (MAC layer) and work outwards, ensuring something runnable at every stage.

## Roadmap

| # | Step | Status | Notes |
|---|------|--------|-------|
| 1 | CAN MAC TX without error handling | Done | `can_mac_tx` wrapper + `can_mac_fsm_tx` + `can_mac_ser_tx` |
| 2 | CAN MAC RX without error handling | Done | `can_mac_rx` wrapper + `can_mac_fsm_rx` |
| 3 | TB CAN MAC RX-TX without error handling | Skipped | Paths are fully separate with own PCS/LLC interfaces. Individual TBs provide full coverage. |
| 4 | Add CAN FCE MAC error handling | Done | `can_fce` implemented with explicit FSM. Integrated into `can_mac` wrapper. TX FSM handles all error/overload states. RX FSM handles error detection and error flag transmission. |
| 5 | Extend TB with MAC error cases | TX done, RX not started | TX: `can_mac_tx_tb` covers 8 injection types (~209k affirmations). RX: `can_mac_rx_tb` is happy-path only. |
| 6 | Make CAN PCS RX TX no error handling | TX done, RX not started | `can_pcs_tx` implemented with bit timing and TDC. No `can_pcs_rx` yet. |
| 7 | Extend TB with timing | TX done | `can_pcs_tx_tb` covers nominal/data-phase cadence, TDC measurement, SSP. |
| 8 | Add CAN FCE PCS error handling | Not started | |
| 9 | Extend TB with PCS error cases | Not started | |
| 10 | Make CAN LLC RX TX no error handling | TX done, RX not started | `can_llc_tx` implemented (legacy_rtl architecture). No `can_llc_rx` yet. |
| 11 | Extend TB with LLC | Partial | Top-level `can_tx` integrates LLC+MAC+PCS. `can_tx_tb` exists in company format. |
| 12 | Add CAN FCE LLC error handling | Not started | |
| 13 | Extend TB with LLC error cases | Not started | |

## Current Position

The TX pipeline is complete top-to-bottom (LLC -> MAC -> PCS) with comprehensive testing including error injection. The RX pipeline has the MAC layer implemented and happy-path tested. The FCE has been refactored into an explicit 3-state FSM (`s_error_active`, `s_error_passive`, `s_bus_off`) with a single merged MAC interface and PCS-based bus-off recovery via `idle_condition` pulses. The `can_mac` wrapper now integrates `can_mac_tx`, `can_mac_rx`, and `can_fce` as a single structural unit. Next steps are completing the RX side: MAC error TB, then PCS_RX, then LLC_RX.

## Module Inventory

| Module | Path | TB | TB Status |
|--------|------|----|----|
| `can_types_p` | `src/can_types_p/hdl_src/can_types_p.vhd` | `can_types_p_tb` (company) | 127 tests passing |
| `can_mac_ser_tx` | `src/can_mac_ser_tx/hdl_src/can_mac_ser_tx.vhd` | `can_mac_ser_tx_tb` | 5 tests passing |
| `can_mac_bs` | `src/can_mac_bs/hdl_src/can_mac_bs.vhd` | `can_mac_bs_tb` | Passing (PSL assertions) |
| `can_mac_crc` | `src/can_mac_crc/hdl_src/can_mac_crc.vhd` | `can_mac_crc_tb` | Passing |
| `can_mac_fsm_tx` | `src/can_mac_tx/hdl_src/can_mac_fsm_tx.vhd` | Via `can_mac_tx_tb` | ~209k affirmations |
| `can_mac_tx` | `src/can_mac_tx/hdl_src/can_mac_tx.vhd` | `can_mac_tx_tb` | ~209k affirmations |
| `can_mac_fsm_rx` | `src/can_mac_rx/hdl_src/can_mac_fsm_rx.vhd` | Via `can_mac_rx_tb` | Happy-path passing |
| `can_mac_rx` | `src/can_mac_rx/hdl_src/can_mac_rx.vhd` | `can_mac_rx_tb` | Happy-path passing |
| `can_fce` | `src/can_fce/hdl_src/can_fce.vhd` | `can_fce_tb` | 25 checks passing |
| `can_mac` | `src/can_mac/hdl_src/can_mac.vhd` | None (structural) | Compile-verified |
| `can_pcs_tx` | `src/can_pcs_tx/hdl_src/can_pcs_tx.vhd` | `can_pcs_tx_tb` | Passing |
| `can_llc_tx` | `src/can_llc_tx/hdl_src/can_llc_tx.vhd` | Via `can_tx_tb` | - |
| `can_tx` | `src/can_tx/hdl_src/can_tx.vhd` | `can_tx_tb` (company) | 35 tests passing |
