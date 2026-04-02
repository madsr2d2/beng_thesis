onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup "TB Signals" \
	( -literal /can_mac_tx_tb/inj_type ) \
	( -logic /can_mac_tx_tb/clk ) \
	( -logic /can_mac_tx_tb/reset ) \
	( -decimal /can_mac_tx_tb/llc_i ) \
	( -decimal /can_mac_tx_tb/llc_o ) \
	( -decimal /can_mac_tx_tb/pcs_i ) \
	( -decimal /can_mac_tx_tb/pcs_o ) \
	( -decimal /can_mac_tx_tb/fce_i ) \
	( -decimal /can_mac_tx_tb/fce_o ) \
	( -logic /can_mac_tx_tb/bus_override ) \
	( -logic /can_mac_tx_tb/bus_override_en ) \
	( -literal /can_mac_tx_tb/status_latch ) \
	( -literal /can_mac_tx_tb/fce_latch ) \
	( -decimal /can_mac_tx_tb/pcs_fdf_pos ) \
	( -decimal /can_mac_tx_tb/pcs_data_phase_start ) \
	( -decimal /can_mac_tx_tb/pcs_data_phase_end ) \
	( -decimal /can_mac_tx_tb/test_id ) \
	( -decimal /can_mac_tx_tb/reset_check_id ) \
	( -decimal /can_mac_tx_tb/status_check_id ) \
	( -decimal /can_mac_tx_tb/stream_check_id ) \
	( -decimal /can_mac_tx_tb/fce_check_id ) \
	( -logic /can_mac_tx_tb/init_barrier )

add wave -vgroup "u_dut Internals" \
	( -logic /can_mac_tx_tb/u_dut/clk ) \
	( -logic /can_mac_tx_tb/u_dut/rst ) \
	( -decimal /can_mac_tx_tb/u_dut/llc_i ) \
	( -decimal /can_mac_tx_tb/u_dut/llc_o ) \
	( -decimal /can_mac_tx_tb/u_dut/pcs_i ) \
	( -decimal /can_mac_tx_tb/u_dut/pcs_o ) \
	( -decimal /can_mac_tx_tb/u_dut/fce_i ) \
	( -decimal /can_mac_tx_tb/u_dut/fce_o ) \
	( -decimal /can_mac_tx_tb/u_dut/ser_to_fsm ) \
	( -decimal /can_mac_tx_tb/u_dut/fsm_to_ser ) \
	( -decimal /can_mac_tx_tb/u_dut/fsm_to_bs_fd ) \
	( -decimal /can_mac_tx_tb/u_dut/bs_fd_to_fsm ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_bs_fd_rst ) \
	( -decimal /can_mac_tx_tb/u_dut/fsm_to_crc ) \
	( -decimal /can_mac_tx_tb/u_dut/crc_to_fsm ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_crc_rst )

add wave -vgroup tx_mac_ser_inst \
	( -logic /can_mac_tx_tb/u_dut/tx_mac_ser_inst/clk_i ) \
	( -logic /can_mac_tx_tb/u_dut/tx_mac_ser_inst/rst_i ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_ser_inst/llc_i ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_ser_inst/llc_o ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_ser_inst/tx_mac_fsm_i ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_ser_inst/tx_mac_fsm_o ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_ser_inst/state ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_ser_inst/count ) \
	( -literal /can_mac_tx_tb/u_dut/tx_mac_ser_inst/llc_frame_buffer ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_ser_inst/id_bits_remaining ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_ser_inst/padding_bits_remaining )

add wave -vgroup tx_mac_fsm_inst \
	( -logic /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/clk_i ) \
	( -logic /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/rst_i ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/mac_ser_i ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/mac_ser_o ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/pcs_i ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/pcs_o ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/bs_fd_i ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/bs_fd_o ) \
	( -logic /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/bs_fd_rst ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/crc_i ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/crc_o ) \
	( -logic /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/crc_rst ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/fce_i ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/fce_o ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/state ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/flag_type ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/bit_count ) \
	( -literal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/polarity_history ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/last_transmitted_bit ) \
	( -logic /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/was_previous_frame_tx ) \
	( -logic /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/ack_success_seen ) \
	( -logic /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/ssp_error_pending ) \
	( -logic /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/ack_error_caused_flag ) \
	( -logic /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/dominant_seen_during_flag ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/dominant_run_count ) \
	( -logic /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/primary_error_sent ) \
	( -logic /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/skip_sof ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/frame_params ) \
	( -decimal /can_mac_tx_tb/u_dut/tx_mac_fsm_inst/bit_info )

add wave -vgroup bit_stuffer_fd_inst \
	( -logic /can_mac_tx_tb/u_dut/bit_stuffer_fd_inst/clk_i ) \
	( -logic /can_mac_tx_tb/u_dut/bit_stuffer_fd_inst/rst_i ) \
	( -decimal /can_mac_tx_tb/u_dut/bit_stuffer_fd_inst/bs_i ) \
	( -decimal /can_mac_tx_tb/u_dut/bit_stuffer_fd_inst/bs_o ) \
	( -decimal /can_mac_tx_tb/u_dut/bit_stuffer_fd_inst/count ) \
	( -logic /can_mac_tx_tb/u_dut/bit_stuffer_fd_inst/last_polarity ) \
	( -literal /can_mac_tx_tb/u_dut/bit_stuffer_fd_inst/stuff_count ) \
	( -logic /can_mac_tx_tb/u_dut/bit_stuffer_fd_inst/stuff_pending )

add wave -vgroup crc_fd_inst \
	( -logic /can_mac_tx_tb/u_dut/crc_fd_inst/clk_i ) \
	( -logic /can_mac_tx_tb/u_dut/crc_fd_inst/rst_i ) \
	( -decimal /can_mac_tx_tb/u_dut/crc_fd_inst/crc_i ) \
	( -decimal /can_mac_tx_tb/u_dut/crc_fd_inst/crc_o ) \
	( -literal /can_mac_tx_tb/u_dut/crc_fd_inst/crc15_out ) \
	( -literal /can_mac_tx_tb/u_dut/crc_fd_inst/crc17_out ) \
	( -literal /can_mac_tx_tb/u_dut/crc_fd_inst/crc21_out )

wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 100000ns
wv.time.unit.auto.set
transcript $curr_transcript
