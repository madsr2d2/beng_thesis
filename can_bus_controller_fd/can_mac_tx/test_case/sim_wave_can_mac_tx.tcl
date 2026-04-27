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
	( -logic /can_mac_tx_tb/p_pcs_vc/v_expected_bit) \
	( -logic /can_mac_tx_tb/p_pcs_vc/v_tq_count) \

add wave -vgroup "u_dut Internals" \
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

add wave -vgroup u_can_mac_ser_tx \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/clk_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/rst_i ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/llc_i ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/llc_o ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/tx_mac_fsm_i ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/tx_mac_fsm_o ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/state ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/count ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/llc_frame_buffer ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/id_bits_remaining ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/padding_bits_remaining )

add wave -vgroup u_can_mac_fsm_tx \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/clk_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/rst_i ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/mac_ser_i ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/mac_ser_o ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/pcs_i ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/pcs_o ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/bs_i ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/bs_o ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/bs_rst ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/crc_i ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/crc_o ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/crc_rst ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/fce_i ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/fce_o ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/state ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/flag_type ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/bit_count ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/polarity_history ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/last_transmitted_bit ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/was_previous_frame_tx ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/ack_success_seen ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/ssp_error_pending ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/ack_error_caused_flag ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/dominant_seen_during_flag ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/dominant_run_count ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/primary_error_sent ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/skip_sof ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/fsb_active ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/frame_params ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/bit_info )

add wave -vgroup u_can_mac_bs \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_bs/clk_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_bs/rst_i ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_bs/bs_i ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_bs/bs_o ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_bs/count ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_bs/last_polarity ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_bs/stuff_count ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_bs/fsb_en_latch )

add wave -vgroup u_can_mac_crc \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/clk_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/rst_i ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_crc/crc_i ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_crc/crc_o ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_crc/crc15_out ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_crc/crc17_out ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_crc/crc21_out )

wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 100000ns
wv.time.unit.auto.set
transcript $curr_transcript
