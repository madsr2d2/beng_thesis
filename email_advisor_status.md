Hi Fredrik,

Here is a brief status update on the thesis project.

A main architectural decision has been to develop a protocol-derived type system. This type hierarchy encodes ISO 11898-1 semantics directly into the inter-module interfaces, keeping the implementation closely aligned with the standard.

The current design covers the **MAC and PCS TX layers**: serializer (`can_mac_ser_tx`), controlling FSM (`can_mac_fsm_tx`), bit stuffer (`can_mac_bs_tx`), CRC generator (`can_mac_crc_tx`), and bit timing with TDC (`can_pcs_tx`).

Still missing are the **LLC layer** and the full **RX path**.

Best regards,
Mads
