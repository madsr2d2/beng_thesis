onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup "TB Signals" \
	( -logic /can_mac_fsm_tx_tb/clk ) \
	( -logic /can_mac_fsm_tx_tb/reset ) \
	( -decimal /can_mac_fsm_tx_tb/mac_ser_i ) \
	( -decimal /can_mac_fsm_tx_tb/mac_ser_o ) \
	( -decimal /can_mac_fsm_tx_tb/pcs_i ) \
	( -decimal /can_mac_fsm_tx_tb/pcs_o ) \
	( -decimal /can_mac_fsm_tx_tb/bs_fd_i ) \
	( -decimal /can_mac_fsm_tx_tb/bs_fd_o ) \
	( -logic /can_mac_fsm_tx_tb/bs_fd_rst ) \
	( -decimal /can_mac_fsm_tx_tb/crc_i ) \
	( -decimal /can_mac_fsm_tx_tb/crc_o ) \
	( -logic /can_mac_fsm_tx_tb/crc_rst ) \
	( -decimal /can_mac_fsm_tx_tb/fce_i ) \
	( -decimal /can_mac_fsm_tx_tb/fce_o ) \
	( -logic /can_mac_fsm_tx_tb/pcs_sp_enable ) \
	( -logic /can_mac_fsm_tx_tb/pcs_bus_override ) \
	( -logic /can_mac_fsm_tx_tb/pcs_bus_override_en ) \
	( -logic /can_mac_fsm_tx_tb/sp_strobe ) \
	( -logic /can_mac_fsm_tx_tb/ser_frame_valid ) \
	( -decimal /can_mac_fsm_tx_tb/ser_metadata ) \
	( -logic /can_mac_fsm_tx_tb/ser_data_pattern ) \
	( -logic /can_mac_fsm_tx_tb/fce_error_passive ) \
	( -logic /can_mac_fsm_tx_tb/fce_error_active ) \
	( -logic /can_mac_fsm_tx_tb/fce_bus_off ) \
	( -decimal /can_mac_fsm_tx_tb/test_id ) \
	( -logic /can_mac_fsm_tx_tb/init_barrier )

add wave -vgroup "u_dut Internals" \
	( -logic /can_mac_fsm_tx_tb/u_dut/clk_i ) \
	( -logic /can_mac_fsm_tx_tb/u_dut/rst_i ) \
	( -decimal /can_mac_fsm_tx_tb/u_dut/mac_ser_i ) \
	( -decimal /can_mac_fsm_tx_tb/u_dut/mac_ser_o ) \
	( -decimal /can_mac_fsm_tx_tb/u_dut/pcs_i ) \
	( -decimal /can_mac_fsm_tx_tb/u_dut/pcs_o ) \
	( -decimal /can_mac_fsm_tx_tb/u_dut/bs_fd_i ) \
	( -decimal /can_mac_fsm_tx_tb/u_dut/bs_fd_o ) \
	( -logic /can_mac_fsm_tx_tb/u_dut/bs_fd_rst ) \
	( -decimal /can_mac_fsm_tx_tb/u_dut/crc_i ) \
	( -decimal /can_mac_fsm_tx_tb/u_dut/crc_o ) \
	( -logic /can_mac_fsm_tx_tb/u_dut/crc_rst ) \
	( -decimal /can_mac_fsm_tx_tb/u_dut/fce_i ) \
	( -decimal /can_mac_fsm_tx_tb/u_dut/fce_o ) \
	( -decimal /can_mac_fsm_tx_tb/u_dut/state ) \
	( -decimal /can_mac_fsm_tx_tb/u_dut/bit_count ) \
	( -literal /can_mac_fsm_tx_tb/u_dut/polarity_history ) \
	( -decimal /can_mac_fsm_tx_tb/u_dut/last_transmitted_bit ) \
	( -logic /can_mac_fsm_tx_tb/u_dut/last_transmitted_bit_polarity ) \
	( -decimal /can_mac_fsm_tx_tb/u_dut/monitored_bit_event ) \
	( -logic /can_mac_fsm_tx_tb/u_dut/was_previous_frame_tx ) \
	( -logic /can_mac_fsm_tx_tb/u_dut/ack_success_seen ) \
	( -logic /can_mac_fsm_tx_tb/u_dut/overload_condition ) \
	( -logic /can_mac_fsm_tx_tb/u_dut/ssp_error_pending ) \
	( -logic /can_mac_fsm_tx_tb/u_dut/in_data_phase ) \
	( -logic /can_mac_fsm_tx_tb/u_dut/ack_error_caused_flag ) \
	( -logic /can_mac_fsm_tx_tb/u_dut/dominant_seen_during_flag ) \
	( -decimal /can_mac_fsm_tx_tb/u_dut/dominant_run_count ) \
	( -logic /can_mac_fsm_tx_tb/u_dut/skip_sof ) \
	( -decimal /can_mac_fsm_tx_tb/u_dut/frame_params )

wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 100000ns
wv.time.unit.auto.set
transcript $curr_transcript
