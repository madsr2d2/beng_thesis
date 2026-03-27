onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup TB \
	( -logic /can_mac_ser_tx_tb/clk ) \
	( -logic /can_mac_ser_tx_tb/reset ) \
	( -decimal /can_mac_ser_tx_tb/byte_count ) \
	( -logic /can_mac_ser_tx_tb/ser_stream ) \
	( -literal /can_mac_ser_tx_tb/llc_metadata ) \
	( -literal /can_mac_ser_tx_tb/llc_frame )

add wave -vgroup "LLC Input" \
	( -logic   /can_mac_ser_tx_tb/llc_i/avalon_st_source/valid ) \
	( -logic   /can_mac_ser_tx_tb/llc_i/avalon_st_source/startofpacket ) \
	( -logic   /can_mac_ser_tx_tb/llc_i/avalon_st_source/endofpacket ) \
	( -literal /can_mac_ser_tx_tb/llc_i/avalon_st_source/data )

add wave -vgroup "LLC Output" \
	( -logic   /can_mac_ser_tx_tb/llc_o/avalon_st_sink/ready ) \
	( -literal /can_mac_ser_tx_tb/llc_o/transfer_status )

add wave -vgroup "MAC FSM Input" \
	( -logic   /can_mac_ser_tx_tb/mac_fsm_tx_i/ready ) \
	( -literal /can_mac_ser_tx_tb/mac_fsm_tx_i/transfer_status )

add wave -vgroup "MAC FSM Output" \
	( -logic   /can_mac_ser_tx_tb/mac_fsm_tx_o/valid ) \
	( -logic   /can_mac_ser_tx_tb/mac_fsm_tx_o/data ) \
	( -binary  /can_mac_ser_tx_tb/mac_fsm_tx_o/llc_metadata/format ) \
	( -decimal  /can_mac_ser_tx_tb/mac_fsm_tx_o/llc_metadata/dlc) \
	( -binary  /can_mac_ser_tx_tb/mac_fsm_tx_o/llc_metadata/ftyp ) \
	( -binary  /can_mac_ser_tx_tb/mac_fsm_tx_o/llc_metadata/brs) \
	( -binary  /can_mac_ser_tx_tb/mac_fsm_tx_o/llc_metadata/esi)

add wave -vgroup "DUT Internals" \
	( -literal /can_mac_ser_tx_tb/u_dut/llc_frame_buffer ) \
	( -literal /can_mac_ser_tx_tb/u_dut/state ) \
	( -decimal /can_mac_ser_tx_tb/u_dut/count ) \
	( -literal /can_mac_ser_tx_tb/u_dut/config_byte_0 ) \
	( -decimal /can_mac_ser_tx_tb/u_dut/id_bits_remaining ) \
	( -decimal /can_mac_ser_tx_tb/u_dut/padding_bits_remaining )

wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 1000ns
wv.time.unit.auto.set
transcript $curr_transcript
