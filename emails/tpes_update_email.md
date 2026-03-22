Morning Fredrik,

Very sorry if it came across as a "demand". It really was not my intention to dictate document format - it was just meant as a question. I noticed some of the documentation is in AsciiDoc - would it be acceptable if I did it in AsciiDoc as well? For now, I have just added the compiled PDF and the Markdown source to the can_controller_fd folder.

Regarding the can_mac_fsm_tx design:
The envisioned FSM for this module is depicted in Figure 6 in the documentation PDF. The idea is that `s_transmitting_frame` is the major worker state. On the first entry to this state, it would compute all format-dependent field boundaries up front:

```
get_frame_params(metadata : t_llc_metadata) -> t_frame_params
```

This derives positions like `dlc_start`, `data_stop`, `crc_start`, `crc_delimiter`, and `crc_poly_select` from the LLC metadata, so the per-bit loop would never need to recalculate.

On each following sample point from the PCS, I envision the state executing three steps:

1. Monitor the bus by comparing the sampled bus polarity against the previously transmitted bit and take appropriate action (error flag, arbitration loss, or continue). The `polarity_history` and `tdc_delay` arguments support TDC - during the FD data phase, the comparison uses a delayed version of the transmitted polarity to account for transceiver round-trip delay (ISO 7.3.4):

```
get_bit_info(bit_name               : t_mac_frame_bit_name,
             polarity_history       : t_tdc_polarity_history,
             tdc_delay              : integer,
             monitored_bit_polarity : std_logic,
             metadata               : t_llc_metadata) -> t_bit_info
```

2. Determine the next bit to transmit. If the bit stuffer has a pending stuff bit, that takes precedence and the function is not called. Otherwise, the function sources the polarity from the serializer (ID and data fields), the CRC engine (CRC field), or the protocol constants (form bits, delimiters, EOF), resolved from the current `bit_count` and the cached frame parameters:

```
get_mac_frame_bit(bit_count         : t_position,
                  ser_data          : std_logic,
                  metadata          : t_llc_metadata,
                  frame_params      : t_frame_params,
                  previous_polarity : std_logic,
                  sbc               : t_sbc,
                  crc               : t_crc_vector) -> t_mac_frame_bit
```

3. Present the resolved polarity at the PCS interface and feed it to the bit stuffer and CRC engine and increment the bit_count.

I have implemented these three functions and placed them in the types package for now. My thinking is that they could be useful beyond the FSM itself - specifically for testbenches and potentially for the RX path as well. I also added a testbench for the types package to verify that the functions return the correct bit names and polarities for all four frame formats (CB, CE, FB, FE).

Best regards,
Mads
