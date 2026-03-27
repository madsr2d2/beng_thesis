onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup TB \
	# ( -logic /can_mac_ser_tx_tb/clk ) \
	# ( -logic /can_mac_ser_tx_tb/reset ) \
	# ( -decimal /can_mac_ser_tx_tb/byte_count ) \
	# ( -literal /can_mac_ser_tx_tb/llc_frame )

add wave -vgroup "LLC Input" \
	# ( -logic   /can_mac_ser_tx_tb/llc_i/avalon_st_source/valid ) \
	# ( -logic   /can_mac_ser_tx_tb/llc_i/avalon_st_source/startofpacket ) \
	# ( -logic   /can_mac_ser_tx_tb/llc_i/avalon_st_source/endofpacket ) \
	# ( -literal /can_mac_ser_tx_tb/llc_i/avalon_st_source/data )

add wave -vgroup "LLC Output" \
	# ( -logic   /can_mac_ser_tx_tb/llc_o/avalon_st_sink/ready ) \
	# ( -literal /can_mac_ser_tx_tb/llc_o/transfer_status )

add wave -vgroup "MAC FSM Input" \
	# ( -logic   /can_mac_ser_tx_tb/tx_mac_fsm_i/ready ) \
	# ( -literal /can_mac_ser_tx_tb/tx_mac_fsm_i/transfer_status )

add wave -vgroup "MAC FSM Output" \
	# ( -logic   /can_mac_ser_tx_tb/tx_mac_fsm_o/valid ) \
	# ( -logic   /can_mac_ser_tx_tb/tx_mac_fsm_o/data ) \
	# ( -binary  /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/format ) \
	# ( -binary  /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/dlc_vector ) \
	# ( -logic   /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/is_fd_frame ) \
	# ( -logic   /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/is_remote_frame ) \
	# ( -logic   /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/has_brs ) \
	# ( -logic   /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/esi_enable ) \
	# ( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/base_id_start ) \
	# ( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/base_id_stop ) \
	# ( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/extended_id_start ) \
	# ( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/extended_id_stop ) \
	# ( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/dlc_start ) \
	# ( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/dlc_stop ) \
	# ( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/data_start ) \
	# ( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/data_stop ) \
	# ( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/crc_start ) \
	# ( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/crc_stop ) \
	# ( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/crc_delimiter ) \
	# ( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/sbc_start ) \
	# ( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/sbc_stop ) \
	# ( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/ack_slot ) \
	# ( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/ack_delimiter ) \
	# ( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/eof_start ) \
	# ( -decimal /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/eof_stop ) \
	# ( -binary  /can_mac_ser_tx_tb/tx_mac_fsm_o/frame_params/crc_poly_select )

add wave -vgroup "DUT Internals" \
wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 1000ns
wv.time.unit.auto.set
transcript $curr_transcript
