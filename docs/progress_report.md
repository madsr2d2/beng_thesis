# Progress Report - CAN-FD Bus Transceiver

**Date**: 2026-04-12

## Milestone Progress

| # | Milestone | Status | Progress | Est. Remaining | Notes |
|---|---|---|---|---|---|
| 1 | CAN MAC TX (no error handling) | Done (review pending) | 100% | - | TB: ~1M affirmations. |
| 2 | CAN MAC RX (no error handling) | Done (review pending) | 100% | - | TB: 14.7k affirmations, coverage-driven. |
| 3 | TB CAN MAC RX-TX (no error handling) | Skipped | - | - | Separate paths, individual TBs suffice. |
| 4 | CAN FCE + MAC error handling | Done (review pending) | 100% | - | 3-state FSM, integrated into `can_mac` wrapper. TB: 227 affirmations. |
| 5 | Extend TB with MAC error cases | Partial | 60% | 2 days | TX done (8 injection types). RX error injection not yet implemented. |
| 6 | CAN PCS RX TX (no error handling) | Not started | 0% | 5 days | TX and RX PCS modules needed. |
| 7 | Extend TB with PCS timing | Not started | 0% | 3 days | Depends on milestone 6. |
| 8 | CAN FCE PCS error handling | Done (review pending) | 100% | - | Bus-off entry/recovery tested in `can_fce_tb`. |
| 9 | Extend TB with PCS functionality | Not started | 0% | 3 days | Bit timing, TDC, SP/SSP verification. Depends on 6 and 7. |
| 10 | CAN LLC RX TX (no error handling) | Not started | 0% | 5 days | TX and RX LLC modules needed. |
| 11 | Extend TB with LLC | Not started | 0% | 3 days | Depends on milestone 10. |
| 12 | CAN FCE LLC error handling | Done (review pending) | 100% | - | Bus-off indication and recovery tested in `can_fce_tb`. |
| 13 | Extend TB with LLC error cases | Not started | 0% | 5 days | Depends on milestones 11 and 12. |
| - | Documentation (report, verification plan) | Ongoing | - | Continuous |  |
| **Sum** | | | | **16 days** | |

## Test Summary

| Testbench | Affirmations | Coverage | Status |
|---|---|---|---|
| `can_fce_tb` | 227 | Reset, normal usage, random stress | Passing |
| `can_mac_bs_tb` | 11,561 | Dynamic/fixed stuff bits (Reset, normal usage, random bit streams) | Passing |
| `can_mac_crc_tb` | 54,084 | CRC-15, CRC-17, CRC-21 (Reset, normal usage, random frames) | Passing |
| `can_mac_ser_tx_tb` | 793,708 | IDE, FDF, DLC 0-15 (Reset, normal usage, random frames) | Passing |
| `can_mac_tx_tb` | 268,903 | All formats, 8 error injection types (Reset, normal usage, random frames and injections) | Passing |
| `can_mac_rx_tb` | 14,704 | IDE, FDF, DLC 0-15 (Reset, normal usage, random frames) | Passing |
