Hi Fredrik,

I have pushed my branch for review. A few notes on what you will find:

**Merged TX/RX MAC FSM**

I ended up merging the TX and RX MAC paths into a single FSM (`can_mac_fsm.vhd`). The original plan was a split-path design, but in practice the shared frame structure meant the two paths were largely mirror images of each other and share the obvioud FSM states. The merged design was actually also alot easier to debug - one FSM, one state space, one waveform to follow. It also saves area since both paths now share a single bit stuffer and a single CRC engine instance.

The merged FSM actually ended up looking quite similar to the can_fsm from the CAN CC implementation, so the split-path detour was mostly useful as a way to think through the requirements - it looked good on paper. :D

**Test coverage**

The complete MAC + PCS + FCE stack is tested in `can_mac_pcs_fce_tb`. I have removed the old split-path files from the folder to keep the source tree clean.

**What is not included**


Best regards,
Mads
