
::: {.landscape-tables}

| # | Milestone | Status | Progress | Est. Remaining | Notes |
|---|---|---|---|---|---|
| 1 | CAN MAC TX (no error handling) | Done (review pending) | 100% | - | TBs: `can_mac_tx_tb`, `can_mac_ser_tx_tb`, `can_mac_bs_tb`, `can_mac_crc_tb`. |
| 2 | CAN MAC RX (no error handling) | Done (review pending) | 100% | - | TB: `can_mac_rx_tb`. |
| 3 | TB CAN MAC RX-TX (no error handling) | Skipped | - | - | TX and RX share no state at the MAC level. The `can_mac` wrapper merges their FCE signals with a simple OR, which is verified structurally. Each path is fully exercised by its own TB. I don't think a combined TB would cover additional logic. |
| 4 | CAN FCE + MAC error handling | Done (review pending) | 100% | - | Integrated into `can_mac` wrapper. TB: `can_fce_tb` . |
| 5 | Extend TB with MAC error cases | Partial | 60% | 2 days | TX done (8 injection types in `can_mac_tx_tb`). RX error injection not yet implemented. |
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

: Milestone progress for the CAN-FD bus transceiver implementation. Milestones are form the implementation road map provided by FKRI. {#tbl:milestone-progress}


| Testbench | Affirmations | Coverage | Status |
|---|---|---|---|
| `can_fce_tb` | 227 | Counter updates, state transitions, bus-off recovery | Passing |
| `can_mac_bs_tb` | 11,561 | Reset (252), dynamic stuff (208), FSB directed (11), SBC (11,076), FSB (12) | Passing |
| `can_mac_crc_tb` | 54,084 | Reset (1,008), CRC check (1,002), output stable (52,074) | Passing |
| `can_mac_ser_tx_tb` | 793,708 | Coverage-driven: IDE, FDF, DLC 0-15 | Passing |
| `can_mac_tx_tb` | 268,903 | PCS VC (264,445), transfer status (2,222), FCE events (2,222), reset (14). Coverage: IDE, FDF, FTYP, ESI, BRS, DLC, error injection type/position, FCE state | Passing |
| `can_mac_rx_tb` | 14,704 | Frame check (14,701), reset (3). Coverage: IDE, FDF, DLC | Passing |

: Testbench execution status and affirmation counts. {#tbl:testbench-summary}

:::
