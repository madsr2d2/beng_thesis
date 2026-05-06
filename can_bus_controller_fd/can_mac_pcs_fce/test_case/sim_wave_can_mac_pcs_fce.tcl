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
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/pcs_i \
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
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/llc_frame \
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
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/pcs_i \
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
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/llc_frame \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/llc_stream_start \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/llc_stream_active \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/crc_error_detected \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/delim_found_first_recessive \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/llc_frame_len
wv.cursors.add -time 210592820ns+0 -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 209194225229ps -to 210666430251ps
wv.time.unit.auto.set
transcript $curr_transcript
