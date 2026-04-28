onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup /can_mac_pcs_fce_tb/u_dut_1 \
	/can_mac_pcs_fce_tb/u_dut_1/clk \
	/can_mac_pcs_fce_tb/u_dut_1/rst \
	/can_mac_pcs_fce_tb/u_dut_1/tx_llc_i \
	/can_mac_pcs_fce_tb/u_dut_1/tx_llc_o \
	/can_mac_pcs_fce_tb/u_dut_1/rx_llc_i \
	/can_mac_pcs_fce_tb/u_dut_1/rx_llc_o \
	/can_mac_pcs_fce_tb/u_dut_1/llc_fce_i \
	/can_mac_pcs_fce_tb/u_dut_1/llc_fce_o \
	/can_mac_pcs_fce_tb/u_dut_1/tx_o \
	/can_mac_pcs_fce_tb/u_dut_1/rx_i \
	/can_mac_pcs_fce_tb/u_dut_1/mac_to_fce \
	/can_mac_pcs_fce_tb/u_dut_1/fce_to_mac \
	/can_mac_pcs_fce_tb/u_dut_1/pcs_to_fce \
	/can_mac_pcs_fce_tb/u_dut_1/fce_to_pcs \
	/can_mac_pcs_fce_tb/u_dut_1/mac_to_pcs \
	/can_mac_pcs_fce_tb/u_dut_1/pcs_to_mac
add wave -vgroup /can_mac_pcs_fce_tb/u_dut_2 \
	/can_mac_pcs_fce_tb/u_dut_2/rst \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/clk ) \
	/can_mac_pcs_fce_tb/u_dut_2/tx_llc_i \
	/can_mac_pcs_fce_tb/u_dut_2/tx_llc_o \
	/can_mac_pcs_fce_tb/u_dut_2/rx_llc_i \
	/can_mac_pcs_fce_tb/u_dut_2/rx_llc_o \
	/can_mac_pcs_fce_tb/u_dut_2/llc_fce_i \
	/can_mac_pcs_fce_tb/u_dut_2/llc_fce_o \
	/can_mac_pcs_fce_tb/u_dut_2/tx_o \
	/can_mac_pcs_fce_tb/u_dut_2/rx_i \
	/can_mac_pcs_fce_tb/u_dut_2/mac_to_fce \
	/can_mac_pcs_fce_tb/u_dut_2/fce_to_mac \
	/can_mac_pcs_fce_tb/u_dut_2/pcs_to_fce \
	/can_mac_pcs_fce_tb/u_dut_2/fce_to_pcs \
	/can_mac_pcs_fce_tb/u_dut_2/mac_to_pcs \
	/can_mac_pcs_fce_tb/u_dut_2/pcs_to_mac
add wave -vgroup /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/clk_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/rst_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/mac_ser_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/mac_ser_o \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/pcs_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/pcs_o \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/bs_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/bs_o \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/bs_rst \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/crc_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/crc_o \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/crc_rst \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/fce_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/fce_o \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/state \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/overload \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/bit_count \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/polarity_history \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/data_len \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/crc_length \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/was_previous_frame_tx \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/ack_success_seen \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/secondary_sample_point_error_pending \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/skip_sof \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/ack_error_caused_flag \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/saw_dominant_during_flag \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_tx/u_can_mac_fsm_tx/dominant_run_count
add wave -vgroup /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/clk_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/rst_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/llc_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/llc_o \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/pcs_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/pcs_o \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/bs_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/bs_o \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/bs_rst \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/crc_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/crc_o \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/crc_rst \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/fce_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/fce_o \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/transmitting_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/fsm_state \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/bit_count \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/byte_index \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/stream_index \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/bit_index \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/data_len \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/crc_length \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/llc_frame_len \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/llc_frame \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/crc_mismatch \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/llc_stream_start \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/llc_stream_done \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_mac_rx/u_can_mac_fsm_rx/overload
add wave -vgroup /can_mac_pcs_fce_tb/u_dut_2 \
	/can_mac_pcs_fce_tb/u_dut_2/clk \
	/can_mac_pcs_fce_tb/u_dut_2/rst \
	/can_mac_pcs_fce_tb/u_dut_2/tx_llc_i \
	/can_mac_pcs_fce_tb/u_dut_2/tx_llc_o \
	/can_mac_pcs_fce_tb/u_dut_2/rx_llc_i \
	/can_mac_pcs_fce_tb/u_dut_2/rx_llc_o \
	/can_mac_pcs_fce_tb/u_dut_2/llc_fce_i \
	/can_mac_pcs_fce_tb/u_dut_2/llc_fce_o \
	/can_mac_pcs_fce_tb/u_dut_2/tx_o \
	/can_mac_pcs_fce_tb/u_dut_2/rx_i \
	/can_mac_pcs_fce_tb/u_dut_2/mac_to_fce \
	/can_mac_pcs_fce_tb/u_dut_2/fce_to_mac \
	/can_mac_pcs_fce_tb/u_dut_2/pcs_to_fce \
	/can_mac_pcs_fce_tb/u_dut_2/fce_to_pcs \
	/can_mac_pcs_fce_tb/u_dut_2/mac_to_pcs \
	/can_mac_pcs_fce_tb/u_dut_2/pcs_to_mac
add wave -vgroup /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/clk_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/rst_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/mac_ser_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/mac_ser_o \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/pcs_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/pcs_o \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/bs_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/bs_o \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/bs_rst \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/crc_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/crc_o \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/crc_rst \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/fce_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/fce_o \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/state \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/overload \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/bit_count \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/polarity_history \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/data_len \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/crc_length \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/was_previous_frame_tx \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/ack_success_seen \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/secondary_sample_point_error_pending \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/skip_sof \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/ack_error_caused_flag \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/saw_dominant_during_flag \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_tx/u_can_mac_fsm_tx/dominant_run_count
add wave -expand -vgroup /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/clk_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/rst_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/llc_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/llc_o \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/pcs_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/pcs_o \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/bs_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/bs_o \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/bs_rst \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/crc_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/crc_o \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/crc_rst \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/fce_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/fce_o \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/transmitting_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/fsm_state \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/bit_count \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/byte_index \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/stream_index \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/bit_index \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/data_len \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/crc_length \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/llc_frame_len \
	( -bin /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/llc_frame ) \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/crc_mismatch \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/llc_stream_start \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/llc_stream_done \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_mac_rx/u_can_mac_fsm_rx/overload
wv.cursors.add -time 46460ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0fs -to 1472205022ps
wv.time.unit.auto.set
transcript $curr_transcript
