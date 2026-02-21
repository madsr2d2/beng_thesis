✦ Focusing strictly on the TX side, excluding the un-implemented FCE, Hard Sync,
and CAN XL, here is the refined list of ISO 11898-1:2015 requirements that are
currently not covered by our test suite:

1. Arbitration & Bit Monitoring (ISO 6.6.17.4)

- Arbitration Loss Withdrawal: A test where the node sends a recessive ID bit
  but monitors a dominant one. We must verify that the FSM immediately
  withdraws (stops driving tx_bus_o) and transitions to Receiver mode without
  triggering a bit error.
- Arbitration Boundary: Verify that arbitration is performed correctly up to
  the IDE bit (Classic) or the bit following FDF (FD), and that bit errors
  are suppressed during this specific window for dominant monitors.

1. Physical Structural Variations (ISO 6.6.10 / 6.6.11)

- Remote Frame (Classic CAN): Verify that when the RTR bit is recessive
  (Remote Frame request), the transmitter omits the Data Field entirely,
  jumping directly from the Control Field to the CRC Field, regardless of the
  DLC value.
- Classic CAN Over-length DLC: Verify that if the LLC provides a DLC $> 8$
  for a Classic frame, the transmitter correctly sends only 8 data bytes
  while still transmitting the original DLC value in the Control Field.

1. Bit Rate Switching Timing (ISO 7.3.3)

- Data Phase Entry (BRS Bit): While we have FD tests, we haven't explicitly
  verified that the switch from nominal to data bit rate occurs exactly at
  the Sample Point of the BRS bit.
- Data Phase Exit (CRC Delimiter): We implemented the logic for this, but we
  need a test that verifies the switch back to nominal rate happens precisely
  at the Sample Point of the CRC Delimiter, not at its start.

1. Detailed Form Error Detection (ISO 6.6.21.2)

- CRC Delimiter Violation: Transmitting recessive but monitoring dominant
  during the CRC Delimiter bit must trigger an Active Error Flag.
- ACK Delimiter Violation (Classic): For Classic frames, monitoring a
  dominant bit during the ACK Delimiter must trigger an Error Flag.
- EOF Violations: Monitoring a dominant bit during EOF bits 0 through 5 must
  trigger an Error Flag.

1. Advanced Overload & Stuffing Rules

- EOF Overload Condition: ISO specifies that if a transmitter samples a
  dominant bit at the last bit of EOF, it must not detect a Form Error but
  instead must initiate an Overload Flag immediately after the Intermission.
- TX-Side Stuff Error: Verify that the transmitter triggers an Error Flag if
  it monitors 6 consecutive bits of the same polarity on the bus (indicating
  a bus-level violation), even if its own internal serialization is correct.

1. Inter-frame Spacing (ISO 6.6.7)

- Intermission Enforcement: Verify that the transmitter strictly waits for
  the 3-bit Intermission period after a successful EOF or Error/Overload
  Delimiter before it is allowed to start a new SOF.

Would you like to select one of these for our next implementation phase? I
recommend starting with Arbitration Loss Withdrawal, as it is a fundamental
requirement for the "Multi-Master" nature of CAN.
