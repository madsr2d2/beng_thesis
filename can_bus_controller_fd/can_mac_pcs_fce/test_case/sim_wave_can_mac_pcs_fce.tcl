onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/clk_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/rst_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/mac_ser_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/mac_ser_o \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/llc_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/llc_o \
	( -expand /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/pcs_i ) \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/pcs_o \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/bs_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/bs_o \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/bs_rst \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/crc_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/crc_o \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/crc_rst \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/fce_i \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/fce_o \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/state \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/is_transmitter \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/bit_count \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/data_len \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/crc_length \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/overload \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/in_data_phase \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/transmitted_bits_shift_reg \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/was_previous_frame_tx \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/ack_success_seen \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/bit_error_at_ssp \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/ack_error_caused_flag \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/saw_dominant_during_flag \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/drive_bit_delay \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/drive_bit \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/byte_index \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/bit_index \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/stream_index \
	( -bin /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/llc_frame ) \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/llc_stream_start \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/llc_stream_active \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/crc_error_detected \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/delim_found_first_recessive \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/llc_frame_len
add wave -vgroup /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/clk_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/rst_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/mac_ser_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/mac_ser_o \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/llc_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/llc_o \
	( -expand /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/pcs_i ) \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/pcs_o \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/bs_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/bs_o \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/bs_rst \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/crc_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/crc_o \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/crc_rst \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/fce_i \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/fce_o \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/state \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/is_transmitter \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/bit_count \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/data_len \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/crc_length \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/overload \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/in_data_phase \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/transmitted_bits_shift_reg \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/was_previous_frame_tx \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/ack_success_seen \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/bit_error_at_ssp \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/ack_error_caused_flag \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/saw_dominant_during_flag \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/drive_bit_delay \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/drive_bit \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/byte_index \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/bit_index \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/stream_index \
	( -bin /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/llc_frame ) \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/llc_stream_start \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/llc_stream_active \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/crc_error_detected \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/delim_found_first_recessive \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/llc_frame_len
add wave -vgroup /can_mac_pcs_fce_tb \
	/can_mac_pcs_fce_tb/clk \
	/can_mac_pcs_fce_tb/reset \
	/can_mac_pcs_fce_tb/test_rst \
	/can_mac_pcs_fce_tb/bus_delay \
	/can_mac_pcs_fce_tb/transceiver_d \
	/can_mac_pcs_fce_tb/dut1_tx \
	/can_mac_pcs_fce_tb/dut2_tx \
	/can_mac_pcs_fce_tb/dut1_rx \
	/can_mac_pcs_fce_tb/dut2_rx \
	/can_mac_pcs_fce_tb/dut1_wire \
	/can_mac_pcs_fce_tb/dut2_wire \
	/can_mac_pcs_fce_tb/dut1_wire_far \
	/can_mac_pcs_fce_tb/dut2_wire_far \
	/can_mac_pcs_fce_tb/bus_dut1 \
	/can_mac_pcs_fce_tb/bus_dut2 \
	/can_mac_pcs_fce_tb/dut_1_rx_recessive \
	/can_mac_pcs_fce_tb/bus_off_seen \
	/can_mac_pcs_fce_tb/bus_off_clear \
	/can_mac_pcs_fce_tb/llc_to_mac_tx_s2d_dut_1 \
	/can_mac_pcs_fce_tb/llc_to_mac_tx_d2s_dut_1 \
	/can_mac_pcs_fce_tb/mac_to_llc_tx_s2d_dut_1 \
	/can_mac_pcs_fce_tb/mac_to_llc_tx_d2s_dut_1 \
	/can_mac_pcs_fce_tb/llc_to_mac_tx_s2d_dut_2 \
	/can_mac_pcs_fce_tb/llc_to_mac_tx_d2s_dut_2 \
	/can_mac_pcs_fce_tb/mac_to_llc_tx_s2d_dut_2 \
	/can_mac_pcs_fce_tb/mac_to_llc_tx_d2s_dut_2 \
	/can_mac_pcs_fce_tb/llc_fce_i_dut_1 \
	/can_mac_pcs_fce_tb/llc_fce_o_dut_1 \
	/can_mac_pcs_fce_tb/llc_fce_i_dut_2 \
	/can_mac_pcs_fce_tb/llc_fce_o_dut_2 \
	/can_mac_pcs_fce_tb/status_latch_dut_1 \
	/can_mac_pcs_fce_tb/clear_status_dut_1 \
	/can_mac_pcs_fce_tb/status_latch_dut_2 \
	/can_mac_pcs_fce_tb/clear_status_dut_2 \
	/can_mac_pcs_fce_tb/test_id \
	/can_mac_pcs_fce_tb/check_id \
	/can_mac_pcs_fce_tb/ide_cov \
	/can_mac_pcs_fce_tb/fdf_cov \
	/can_mac_pcs_fce_tb/dlc_cov \
	/can_mac_pcs_fce_tb/ftyp_cov \
	/can_mac_pcs_fce_tb/brs_cov \
	/can_mac_pcs_fce_tb/esi_cov \
	/can_mac_pcs_fce_tb/init_barrier \
	/can_mac_pcs_fce_tb/test_num \
	/can_mac_pcs_fce_tb/tx_llc_rec_dut_1 \
	/can_mac_pcs_fce_tb/tx_llc_rec_dut_2 \
	/can_mac_pcs_fce_tb/rx_llc_rec_dut_2 \
	/can_mac_pcs_fce_tb/~ANONYMOUS~0 \
	/can_mac_pcs_fce_tb/~ANONYMOUS~1
wv.cursors.add -time 143481550ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 143431591088ps -to 143531508912ps
wv.time.unit.auto.set
transcript $curr_transcript
