| id | description | iso_reference | format | status | priority | tests | acceptance_criteria | verification | dependencies | notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FRM001TX | SOF shall be 1 dominant bit marking frame start | 6.6.8 | CB/CE/FB/FE | Verified |  | T1, T4, T5 | SOF always dominant, exactly 1 bit | WAVE |  | Every frame starts with SOF |
| FRM002TX | Frame shall contain SOF, arbitration, control, data (optional), CRC, ACK, EOF | 6.6.9 | CB/CE/FB/FE | Verified | C | T1 | All fields present in correct order | ASSERT | FRM001TX | Field ordering critical |
| FRM003TX | DLC field shall match LLC DLC value | 6.6.10.3, Table 5 | CB/CE/FB/FE | Verified | C | T1 | DLC encoded correctly per table | CVRG |  | Maps to data length |
| FRM004TX | Data field byte order: byte 0 first, MSB first | 6.6.10.4 | CB/CE/FB/FE | Verified | C | T1 | Bytes transmitted sequentially | SIM |  | 8 bits per byte |
| FRM005TX | CRC field shall contain FCRC sequence + delimiter | 6.6.10.5, 6.6.11.5 | CB/CE/FB/FE | Implemented | H | None | CRC bits correct, delimiter recessive | WAVE | CRC001TX | Polynomial selection |
| FRM006TX | ACK field: ACK slot + ACK delimiter (8 bits total) | 6.6.10.6 | CB/CE/FB/FE | Verified | H | T1, T11 | TX sends recessive, monitors for dominant | WAVE |  | Part of frame completion |
| FRM007TX | EOF shall be 7 recessive bits | 6.6.10.7, 6.6.11.7 | CB/CE/FB/FE | Verified | C | T1 | EOF always recessive, 7 bits | WAVE |  | Marks frame end |
| FRM008TX | CBFF base ID: 11-bit identifier | 6.6.10.2 | CB | Verified | C | T1 | ID bits 10-0 transmitted MSB first | CVRG |  | CC Basic only |
| FRM009TX | CEFF extended ID: 29-bit identifier (11+18) | 6.6.10.2 | CE | Verified | C | T4 | Base ID (11-bit) + extended ID (18-bit) | CVRG |  | CC Extended only |
| FRM010TX | FBFF base ID: 11-bit identifier | 6.6.11.2 | FB | Verified | C | T5 | ID bits 10-0 transmitted MSB first | CVRG |  | FD Basic only |
| FRM011TX | FEFF extended ID: 29-bit identifier (11+18) | 6.6.11.2 | FE | Verified | C | T6 | Base ID (11-bit) + extended ID (18-bit) | CVRG |  | FD Extended only |
| FRM012TX | RTR bit: dominant in DF, recessive in RF (CC only) | 6.6.10.2 | CB/CE | Verified | H | T1 | Correct polarity based on frame type | CVRG |  | CAN Classic only |
| FRM013TX | RRS bit: dominant in FBFF/FEFF | 6.6.11.2 | FB/FE | Verified | H | T5, T6 | RRS always dominant | CVRG |  | CAN FD only |
| FRM014TX | SRR bit: transmitted recessive (CC extended only) | 6.6.10.2 | CE | Verified | M | T4 | SRR bit always recessive | CVRG |  | Arbitration helper bit |
| FRM015TX | IDE bit: dominant in CBFF/FBFF, recessive in CEFF/FEFF | 6.6.10.2, 6.6.11.2 | CB/CE/FB/FE | Verified | C | T1, T4, T5, T6 | Correct polarity based on format | CVRG |  | Format indicator |
| FRM016TX | Arbitration ends at RTR/RRS bit; loser becomes receiver | 6.6.10.2 | CB/CE/FB/FE | Verified | C | T12 | FSM transitions to receive on arbitration loss | SIM |  | Arbitration loss withdrawal |
| FRM017TX | IDE/r1 bit: dominant (CC r0, FD FDF) | 6.6.10.3, 6.6.11.3 | CB/CE/FB/FE | Verified | C | T1 | Control field bits correct polarity | CVRG |  | Format control bits |
| FRM018TX | r0 bit: dominant in CC frames | 6.6.10.3 | CB/CE | Verified | C | T1 | r0 always dominant | CVRG |  | CAN Classic only |
| FRM019TX | FDF bit: recessive for CC, dominant for FD | 6.6.11.3 | CB/CE/FB/FE | Verified | C | T1, T5 | Correct format indicator | CVRG |  | Differentiates CC/FD |
| FRM020TX | res bit: dominant (FD frames only, between FDF and BRS) | 6.6.11.3 | FB/FE | Verified | H | T5, T6, T14 | res bit always dominant | CVRG |  | FD format only |
| FRM021TX | BRS bit: recessive if data phase, dominant otherwise | 6.6.11.3 | FB/FE | Verified | C | T5, T6, T14 | Polarity matches config | CVRG |  | Enables bit rate switch |
| FRM022TX | ESI bit: polarity based on node error state | 6.6.11.3 | FB/FE | Implemented | M | None | ESI=dominant (error-active), recessive (error-passive) | CVRG |  | Error state indicator |
| FRM023TX | Dynamic stuff rule: no more than 4 consecutive bits of same polarity in arb/ctrl/data | 6.6.13.2 | CB/CE/FB/FE | Verified | C | T7 | Stuff bit inserted after 4 same bits | CVRG |  | 5-in-a-row rule |
| FRM024TX | Fixed stuff bits: CAN FD SBC field (Stuff Bit Count) | 6.6.13.3 | FB/FE | Verified | H | None | SBC field contains stuff count | CVRG |  | FD frames only |
| FRM025TX | Fixed stuff bit positions: every 5th bit in CRC field | 6.6.13.3.1 | FB/FE | Implemented | H | None | Positions calculated correctly | CVRG |  | FD CRC field |
| FRM026TX | Stuff bit polarity: opposite of preceding 4 bits | 6.6.13.2 | CB/CE/FB/FE | Verified | H | T7 | Stuff bit correct | CVRG | FRM023TX | Dynamic stuffing |
| FRM027TX | ACK handling: TX sends recessive, expects dominant from receivers | 6.6.10.6 | CB/CE/FB/FE | Verified | C | T1, T11 | ACK slot monitoring logic | SIM |  | Frame acknowledgement |
| FRM028TX | Frame transmitted status: reported after EOF completion | 6.4.5.5.5 | CB/CE/FB/FE | Verified | C | T1 | Transfer_status=transmitted signal | SIM |  | LLC notification |
| FRM029TX | Frame abort: on abort request, stop transmission | 6.4.5.5.3 | CB/CE/FB/FE | Verified | C | T2, T3 | FSM transitions to idle | SIM |  | Abort handling |
| FRM030TX | Intermission: 3 recessive bits after EOF | 6.6.7.2 | CB/CE/FB/FE | Implemented | M | None | Intermission state | SIM |  | Recovery phase |
| FRM031TX | Bus idle: recognized after 11 recessive bits in re-integration | 6.6.7.5 | CB/CE/FB/FE | Implemented | M | None | Re-integration counter | SIM |  | Idle detection |
| FRM032TX | Frame status transitions: idle to transmitting to intermission to idle | 6.6.7, 6.6.21 | CB/CE/FB/FE | Verified | C | T1 | FSM state machine flow | SIM |  | State management |
| TMG001TX | Nominal bit time: Sync_Seg + Prop_Seg + Phase_Seg1 + Phase_Seg2 | 7.2 | CB/CE/FB/FE | Implemented | H | None | Bit timing per Table 10/11 | SIM |  | Arbitration phase |
| TMG002TX | Data bit time (FD only): shorter data_bit_time when BRS recessive | 7.2, 7.3.3 | FB/FE | Implemented | H | T14 | Bit time switches at BRS SP | SIM | FRM021TX | FD frames only |
| TMG003TX | Sample Point (SP): configurable within bit time | 7.2 Table 10 | CB/CE/FB/FE | Implemented | H | None | SP pulse at correct position | SIM | TMG001TX | Per configuration |
| TMG004TX | Bit time quantization: measured in time quanta (tq) | 7.2 | CB/CE/FB/FE | Implemented | M | None | Prescaler sets tq length | SIM |  | Clock division |
| TMG005TX | Data phase entry: at SP of BRS bit when BRS recessive | 7.3.3 | FB/FE | Implemented | C | T14 | State transition to data phase | SIM | TMG002TX | FD frames, BRS=recessive |
| TMG006TX | Data phase exit: at SP of CRC delimiter | 6.6.21.3.1 | FB/FE | Implemented | C | None | State transition back to nominal | SIM |  | FD frames only |
| TMG007TX | TDC measurement: at res bit FDF to res edge (FD only) | 7.3.4 | FB/FE | Implemented | H | T14 | Delay measured at res bit SP | SIM |  | Recently fixed (Issue B) |
| TMG008TX | Secondary Sample Point (SSP): configured from TDC measurement | 7.3.4 | FB/FE | Implemented | H | None | SSP position calculated per config | SIM | TMG007TX | Within bit time |
| TMG009TX | TDC error at SSP: detect at following SP | 6.6.21.3.1 | FB/FE | Diagnostic | H | T5 | Error confirmed at SP after SSP | SIM |  | TDC error path - Test 5 diagnostic (waveform inspection) |
| TMG010TX | TDC error timing: SSP to SP to IPT to nominal rate back | 6.6.21.3.1 | FB/FE | Diagnostic | H | T6 | Bit timing sequence correct | WAVE | TMG009TX | Complex timing - Test 6 diagnostic (multi-signal analysis) |
| TMG011TX | SSP used for FD data phase bits (not control field) | 7.3.4 | FB/FE | Implemented | M | None | SSP only in data phase | SIM |  | ESI excluded from SSP |
| ERR001TX | Bit error: detected when TX bit != monitored bus bit | 6.6.21.2 | CB/CE/FB/FE | Verified | C | T2 | Comparison triggered at SP/SSP | SIM |  | Monitoring logic - VERIFIED (polarity mismatch detected) |
| ERR002TX | Bit error in arbitration: frame loss (not an error) | 6.6.21.3.1 | CB/CE/FB/FE | Verified | C | T12 | FSM withdraws to receiver mode | SIM |  | Arbitration loss handling |
| ERR003TX | Stuff error: violation of 5-consecutive-bit rule | 6.6.21.2 | CB/CE/FB/FE | Verified | H | T6 | Stuff rule check during TX | CVRG |  | Detected at bit level |
| ERR004TX | Form error: illegal bit sequence detected | 6.6.21.2 | CB/CE/FB/FE | Not Applicable | H | None | TX ignores form errors per 6.6.21.3.1; RX-side only | CVRG |  | TX ignores form errors (SOF to AH2); caught as bit errors |
| ERR005TX | PCRC error: CRC mismatch during arbitration phase (XL frames only) | 6.6.21.2 | XB/XL-E (Out of Scope) | Not Applicable | M | N/A | N/A - XL frames not in current scope | N/A |  | XL frame feature - Project scope: ISO 11898-1:2015 CC/FD only |
| ERR006TX | ACK error: no dominant in ACK slot when expected | 6.6.21.2 | CB/CE/FB/FE | Verified | H | T1 | ACK slot monitoring | SIM |  | TX monitors for ACK - VERIFIED |
| ERR007TX | Error flag: 6 consecutive dominant bits (active error) | 6.6.5.2 | CB/CE/FB/FE | Verified | C | T9 | EF format correct | WAVE |  | Error signalling |
| ERR008TX | Error flag start: next bit after error detection | 6.6.21.3.1 | CB/CE/FB/FE | Verified | C | T9 | FSM state transitions to transmitting_error_flag | SIM | ERR007TX | Timing critical |
| ERR009TX | Arbitration phase error: send EF immediately | 6.6.21.3.1 | CB/CE/FB/FE | Verified | C | T7 | EF triggered at arb error | SIM | ERR007TX | Stuff errors in arb |
| ERR010TX | Data phase error (FD): switch bit rate back to nominal before EF | 6.6.21.3.1 | FB/FE | Diagnostic | C | T3 | Bit time switches data to nominal | WAVE | TMG002TX | Test 3 implemented - requires waveform inspection for verification |
| ERR011TX | FD data phase error: complete phase after SP where error detected | 6.6.21.3.1 | FB/FE | Diagnostic | H | T4 | Data phase finishes at SP | SIM |  | FD only - Test 4 diagnostic (waveform inspection) |
| ERR012TX | FD data-phase error: defer first EF bit until nominal timing is active | 6.6.21.3.1 | FB/FE | Verified | H | T7 | First EF bit appears only after nominal-rate handover | SIM | ERR010TX | Explicit assertion-based check in tx_error_detection_tb |
| ERR013TX | Error delimiter: 8 recessive bits after error flag | 6.6.5.3 | CB/CE/FB/FE | Implemented | H | None | Delimiter format correct | SIM | ERR007TX | Follows error flag |
| ERR014TX | Intermission after error: 3 recessive bits before next frame | 6.6.7.2 | CB/CE/FB/FE | Implemented | M | None | Intermission timing | SIM |  | Recovery sequence |
| CRC001TX | CC frames use CRC-15 polynomial | 6.6.4.4 | CB/CE | Verified | C | T1 | CRC-15 (0xC599) applied | CVRG |  | Classic frames |
| CRC002TX | FD frames ≤16 bytes: use CRC-17 polynomial | 6.6.4.4 | FB/FE | Implemented | C | None | CRC-17 (0x3685B) for small payloads | CVRG |  | FD selection logic |
| CRC003TX | FD frames >16 bytes: use CRC-21 polynomial | 6.6.4.4 | FB/FE | Implemented | C | None | CRC-21 (0x302899) for large payloads | CVRG |  | FD selection logic |
| CRC004TX | CRC calculated over: SOF + arb + ctrl + data (no stuff bits) | 6.6.4.4 | CB/CE/FB/FE | Verified | H | None | Correct bit stream selected | CVRG |  | Excludes stuff bits |
| CRC005TX | CRC initialized: 0x0000 (CRC-15), 0x10000 (CRC-17/21) | 6.6.4.4 | CB/CE/FB/FE | Implemented | M | None | Init vector per polynomial | CVRG |  | Hamming distance 6 |
| CRC006TX | Provisional CRC (PCRC): calculated in arbitration phase (XL frames only) | 6.6.12.3 (XL ref) | XB/XL-E (Out of Scope) | Not Applicable | M | None | N/A - XL frames not in current scope | N/A |  | XL frame feature - Project scope: ISO 11898-1:2015 CC/FD only |