onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup /can_mac_rx_tb/u_dut \
	/can_mac_rx_tb/u_dut/clk \
	/can_mac_rx_tb/u_dut/rst \
	/can_mac_rx_tb/u_dut/llc_i \
	/can_mac_rx_tb/u_dut/llc_o \
	/can_mac_rx_tb/u_dut/pcs_i \
	/can_mac_rx_tb/u_dut/pcs_o \
	/can_mac_rx_tb/u_dut/fce_i \
	/can_mac_rx_tb/u_dut/fce_o \
	/can_mac_rx_tb/u_dut/transmitting_i \
	/can_mac_rx_tb/u_dut/fsm_to_bs \
	/can_mac_rx_tb/u_dut/bs_to_fsm \
	/can_mac_rx_tb/u_dut/fsm_bs_rst \
	/can_mac_rx_tb/u_dut/fsm_to_crc \
	/can_mac_rx_tb/u_dut/crc_to_fsm \
	/can_mac_rx_tb/u_dut/fsm_crc_rst \
	/can_mac_rx_tb/u_dut/~ANONYMOUS~0 \
	/can_mac_rx_tb/u_dut/~ANONYMOUS~1
wv.cursors.add -time 160ns+0 -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0fs -to 168ns
wv.time.unit.auto.set
transcript $curr_transcript
