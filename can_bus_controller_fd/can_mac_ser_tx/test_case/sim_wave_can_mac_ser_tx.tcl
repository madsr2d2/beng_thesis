onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup "TB Signals" \
	( -logic /can_mac_ser_tx_tb/clk ) \
	( -logic /can_mac_ser_tx_tb/reset ) \
	( -decimal /can_mac_ser_tx_tb/llc_i ) \
	( -decimal /can_mac_ser_tx_tb/llc_o ) \
	( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_i ) \
	( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_o ) \
	( -decimal /can_mac_ser_tx_tb/test_id ) \
	( -logic /can_mac_ser_tx_tb/init_barrier )

add wave -vgroup "u_dut Internals" \
	( -logic /can_mac_ser_tx_tb/u_dut/clk_i ) \
	( -logic /can_mac_ser_tx_tb/u_dut/rst_i ) \
	( -decimal /can_mac_ser_tx_tb/u_dut/llc_i ) \
	( -decimal /can_mac_ser_tx_tb/u_dut/llc_o ) \
	( -decimal /can_mac_ser_tx_tb/u_dut/tx_mac_fsm_i ) \
	( -decimal /can_mac_ser_tx_tb/u_dut/tx_mac_fsm_o ) \
	( -decimal /can_mac_ser_tx_tb/u_dut/state ) \
	( -decimal /can_mac_ser_tx_tb/u_dut/count ) \
	( -literal /can_mac_ser_tx_tb/u_dut/llc_frame_buffer ) \
	( -literal /can_mac_ser_tx_tb/u_dut/config_byte_0 ) \
	( -decimal /can_mac_ser_tx_tb/u_dut/id_bits_remaining ) \
	( -decimal /can_mac_ser_tx_tb/u_dut/padding_bits_remaining )

wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 100000ns
wv.time.unit.auto.set
transcript $curr_transcript
