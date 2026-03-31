onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup "Test Control" \
	( -logic /can_mac_tx_tb/clk ) \
	( -logic /can_mac_tx_tb/reset )

add wave -vgroup "Bus & Error Injection" \
	( -logic /can_mac_tx_tb/bus_override ) \
	( -logic /can_mac_tx_tb/bus_override_en )

add wave -vgroup "FSM State" \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/state ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/bit_count ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/last_transmitted_bit/bit_name ) \
	( -logic /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/last_transmitted_bit/polarity ) \
	( -logic /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/in_data_phase ) \
	( -logic /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/ack_success_seen ) \
	( -logic /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/overload_condition ) \
	( -logic /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/ssp_error_pending ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/monitored_bit_event ) \
	( -literal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/polarity_history[0] )

add wave -vgroup "LLC Interface (TB side)" \
	( -logic /can_mac_tx_tb/llc_i/avalon_st_source/valid ) \
	( -logic /can_mac_tx_tb/llc_i/avalon_st_source/startofpacket ) \
	( -logic /can_mac_tx_tb/llc_i/avalon_st_source/endofpacket ) \
	( -logic /can_mac_tx_tb/llc_o/avalon_st_sink/ready ) \
	( -decimal /can_mac_tx_tb/llc_o/transfer_status[0] )

add wave -vgroup "PCS Interface (TB side)" \
	( -logic /can_mac_tx_tb/pcs_o/polarity ) \
	( -logic /can_mac_tx_tb/pcs_o/valid ) \
	( -logic /can_mac_tx_tb/pcs_o/use_data_rate ) \
	( -logic /can_mac_tx_tb/pcs_o/start_tdc ) \
	( -logic /can_mac_tx_tb/pcs_i/sp ) \
	( -logic /can_mac_tx_tb/pcs_i/ssp ) \
	( -logic /can_mac_tx_tb/pcs_i/bus_polarity )

add wave -vgroup "FCE Interface" \
	( -logic /can_mac_tx_tb/fce_o/sending_error_overload_flag ) \
	( -logic /can_mac_tx_tb/fce_o/transmitting ) \
	( -logic /can_mac_tx_tb/fce_o/error ) \
	( -logic /can_mac_tx_tb/fce_o/primary_error ) \
	( -logic /can_mac_tx_tb/fce_o/successful_transfer ) \
	( -logic /can_mac_tx_tb/fce_o/counters_unchanged ) \
	( -logic /can_mac_tx_tb/fce_o/error_active_response ) \
	( -logic /can_mac_tx_tb/fce_o/error_passive_response ) \
	( -logic /can_mac_tx_tb/fce_o/error_delimiter_too_late ) \
	( -logic /can_mac_tx_tb/fce_i/error_active_request ) \
	( -logic /can_mac_tx_tb/fce_i/error_passive_request ) \
	( -logic /can_mac_tx_tb/fce_i/bus_off )

add wave -vgroup Serializer \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_ser_inst/state ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_ser_inst/count ) \
	( -logic /can_mac_tx_tb/u_dut/ser_to_fsm/data ) \
	( -logic /can_mac_tx_tb/u_dut/ser_to_fsm/valid ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_to_ser/ready ) \
	( -decimal /can_mac_tx_tb/u_dut/fsm_to_ser/transfer_status[0] )

add wave -vgroup "Bit Stuffer to FSM" \
	( -logic /can_mac_tx_tb/u_dut/bs_fd_to_fsm/data ) \
	( -logic /can_mac_tx_tb/u_dut/bs_fd_to_fsm/valid ) \
	( -literal /can_mac_tx_tb/u_dut/bs_fd_to_fsm/sbc[0] ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_to_bs_fd/data ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_to_bs_fd/valid ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_bs_fd_rst )

add wave -vgroup "CRC to FSM" \
	( -literal /can_mac_tx_tb/u_dut/crc_to_fsm/crc[0] ) \
	( -literal /can_mac_tx_tb/u_dut/fsm_to_crc/crc_poly_select[0] ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_to_crc/data ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_to_crc/valid ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_crc_rst )

add wave -vgroup "Bit Stuffer Internals" \
	( -decimal /can_mac_tx_tb/u_dut/bit_stuffer_fd_inst/count ) \
	( -literal /can_mac_tx_tb/u_dut/bit_stuffer_fd_inst/stuff_count[0] ) \
	( -logic /can_mac_tx_tb/u_dut/bit_stuffer_fd_inst/last_polarity ) \
	( -logic /can_mac_tx_tb/u_dut/bit_stuffer_fd_inst/stuff_pending )

add wave -vgroup "CRC Engine Internals" \
	( -literal /can_mac_tx_tb/u_dut/crc_fd_inst/crc15_out[0] ) \
	( -literal /can_mac_tx_tb/u_dut/crc_fd_inst/crc17_out[0] ) \
	( -literal /can_mac_tx_tb/u_dut/crc_fd_inst/crc21_out[0] ) \
	( -logic /can_mac_tx_tb/u_dut/crc_fd_inst/sel_crc15 ) \
	( -logic /can_mac_tx_tb/u_dut/crc_fd_inst/sel_crc17 ) \
	( -logic /can_mac_tx_tb/u_dut/crc_fd_inst/sel_crc21 ) \
	( -logic /can_mac_tx_tb/u_dut/crc_fd_inst/valid )

wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 100000ns
wv.time.unit.auto.set
transcript $curr_transcript
