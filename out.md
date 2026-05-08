| ID | ISO ref | Layer | Requirement | Method | Label | File |
| --- | --- | --- | --- | --- | --- | --- |
| REQ-040 | 8.1.3.2, Table 14 | FCE | Normal_mode_request resets TEC and REC to zero. | sim | test_reset, test_bus_off_recovery | can_fce_tb.vhd |
| REQ-041 | 8.1.4.2 rule a), rule b), rule e) | FCE | REC increments by 1 on RX error (except during error/overload flag) • by 8 on first dominant bit after an error flag • by 8 on bit error while sending an error or overload flag. | sim | test_rule_a, test_rule_b, test_rule_e | can_fce_tb.vhd |
| REQ-042 | 8.1.4.2 rule c), rule d) | FCE | TEC increments by 8 when sending an error flag (exemptions: passive ACK error, pre-arbitration stuff error) • by 8 on bit error while sending an active error or overload flag. | sim | test_rule_c, test_rule_c_exception, test_rule_d | can_fce_tb.vhd |
| REQ-043 | 8.1.4.2 rule f) | FCE | Error counters increment by 8 after 14 consecutive dominant bits following an active error or overload flag (8 after a passive error flag) • and after each further 8. | sim | test_rule_f_tx, test_rule_f_rx | can_fce_tb.vhd |
| REQ-044 | 8.1.4.2 rule g), rule h) | FCE | TEC decrements by 1 on successful TX (floor 0) • REC decrements by 1 on successful RX if in 1-127, stays at 0 if already 0, or is set to 119-127 if above 127. | sim | test_rule_g, test_rule_h | can_fce_tb.vhd |
| REQ-045 | 8.1.4.3, 8.1.4.4 | FCE | Either counter exceeding 127 causes error-passive • both at or below 127 restores error-active • TEC exceeding 255 causes bus-off • recovery requires 128 idle conditions with counters reset to zero. | sim | test_bus_off, test_bus_off_recovery | can_fce_tb.vhd |

: FCE requirements and verification mapping. {#tbl:fce-requirements}
