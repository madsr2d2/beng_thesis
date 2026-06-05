onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup /can_mac_tb/u_mac_tx \
	/can_mac_tb/u_mac_tx/clk \
	/can_mac_tb/u_mac_tx/rst \
	/can_mac_tb/u_mac_tx/llc_i \
	/can_mac_tb/u_mac_tx/llc_o \
	/can_mac_tb/u_mac_tx/pcs_i \
	/can_mac_tb/u_mac_tx/pcs_o \
	/can_mac_tb/u_mac_tx/fce_i \
	/can_mac_tb/u_mac_tx/fce_o \
	/can_mac_tb/u_mac_tx/ser_to_fsm \
	/can_mac_tb/u_mac_tx/fsm_to_ser \
	/can_mac_tb/u_mac_tx/fsm_to_bs_fd \
	/can_mac_tb/u_mac_tx/bs_fd_to_fsm \
	/can_mac_tb/u_mac_tx/fsm_bs_fd_rst \
	/can_mac_tb/u_mac_tx/fsm_to_crc \
	/can_mac_tb/u_mac_tx/crc_to_fsm \
	/can_mac_tb/u_mac_tx/fsm_crc_rst \
	/can_mac_tb/u_mac_tx/~ANONYMOUS~0 \
	/can_mac_tb/u_mac_tx/~ANONYMOUS~1
add wave -vgroup /can_mac_tb/u_mac_rx \
	/can_mac_tb/u_mac_rx/clk \
	/can_mac_tb/u_mac_rx/rst \
	/can_mac_tb/u_mac_rx/llc_i \
	/can_mac_tb/u_mac_rx/llc_o \
	/can_mac_tb/u_mac_rx/pcs_i \
	/can_mac_tb/u_mac_rx/pcs_o \
	/can_mac_tb/u_mac_rx/fce_i \
	/can_mac_tb/u_mac_rx/fce_o \
	/can_mac_tb/u_mac_rx/transmitting_i \
	/can_mac_tb/u_mac_rx/fsm_to_bs \
	/can_mac_tb/u_mac_rx/bs_to_fsm \
	/can_mac_tb/u_mac_rx/fsm_bs_rst \
	/can_mac_tb/u_mac_rx/fsm_to_crc \
	/can_mac_tb/u_mac_rx/crc_to_fsm \
	/can_mac_tb/u_mac_rx/fsm_crc_rst \
	/can_mac_tb/u_mac_rx/~ANONYMOUS~0 \
	/can_mac_tb/u_mac_rx/~ANONYMOUS~1
wv.cursors.add -time 96709040ns+0 -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 96684244608ps -to 96709040ns
wv.time.unit.auto.set
transcript $curr_transcript
