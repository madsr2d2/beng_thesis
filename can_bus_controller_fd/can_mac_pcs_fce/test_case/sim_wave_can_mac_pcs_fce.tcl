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
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/drive_bit_d \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/drive_bit \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/transmitted_bits_shift_reg \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/was_previous_frame_tx \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/ack_success_seen \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/bit_error_at_ssp \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/ack_error_caused_flag \
	/can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/saw_dominant_during_flag
add wave -expand -vgroup /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm \
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
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/drive_bit_d \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/drive_bit \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/transmitted_bits_shift_reg \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/was_previous_frame_tx \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/ack_success_seen \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/bit_error_at_ssp \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/ack_error_caused_flag \
	/can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/saw_dominant_during_flag
wv.cursors.add -time 46460ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0fs -to 1472205022ps
wv.time.unit.auto.set
transcript $curr_transcript
