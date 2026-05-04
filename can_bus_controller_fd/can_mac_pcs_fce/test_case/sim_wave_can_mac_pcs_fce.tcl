onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup durt1_metadata \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_ser_tx/tx_mac_fsm_o/data ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_ser_tx/tx_mac_fsm_o/llc_metadata/brs ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_ser_tx/tx_mac_fsm_o/llc_metadata/esi ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_ser_tx/tx_mac_fsm_o/llc_metadata/fdf ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_ser_tx/tx_mac_fsm_o/llc_metadata/ftyp ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_ser_tx/tx_mac_fsm_o/llc_metadata/ide ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_ser_tx/tx_mac_fsm_o/valid )

add wave -vgroup dut1_mac_fsm \
	( -literal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/llc_frame_len )

add wave -vgroup group_end \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/llc_stream_done ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/llc_stream_start ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/stream_index ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/bit_index ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/byte_index ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/saw_dominant_during_flag ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/ack_error_caused_flag ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/ack_success_seen ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/was_previous_frame_tx ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/overload ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/crc_length ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/data_len ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/bit_count ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/is_transmitter ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/state ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/crc_rst ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/bs_rst ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/rst_i ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/clk_i )

add wave -vgroup dut1_sb \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_bs/bs_o/valid ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_bs/bs_o/data )

add wave -vgroup dut1_pcs \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/mac_to_pcs/tx_data ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/tx_o ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/rx_i ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/pcs_to_mac/rx_data ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/pcs_to_mac/sample_point ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/pcs_to_mac/secondary_sample_point ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/mac_to_pcs/data_phase_stop ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/mac_to_pcs/do_hard_sync ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/mac_to_pcs/next_bit_is_brs ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/mac_to_pcs/next_bit_is_res ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/mac_to_pcs/transmitting )

add wave -vgroup dut1_pcs_internals \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/data_phase_active ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/first_data_bit_boundary_seen ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/ssp_standoff_active ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/bit_boundary ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_pcs/tdc_delay ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/ssp_seen ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/ssp_active ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_pcs/delay_count_tq ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/tdc_count_active ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_pcs/active_sjw ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_pcs/active_phase_seg2 ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_pcs/active_phase_seg1 ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_pcs/active_prop_seg ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_pcs/recessive_counter ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_pcs/phase2_shortening ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_pcs/phase1_extension ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/sync_applied ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/rx_bus_prev ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_pcs/seg_count ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_pcs/clk_count ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_pcs/segment )

add wave -vgroup dut2_mac_fsm \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/llc_frame_len ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/llc_stream_done ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/llc_stream_start ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/stream_index ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/bit_index ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/byte_index ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/saw_dominant_during_flag ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/ack_error_caused_flag ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/ack_success_seen ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/was_previous_frame_tx ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/overload ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/crc_length ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/data_len ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/bit_count ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/is_transmitter ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/state ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/crc_rst ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/bs_rst ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/rst_i ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/clk_i )

add wave -vgroup dut2_pcs \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/pcs_to_mac/rx_data ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/mac_to_pcs/tx_data ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/pcs_to_mac/sample_point ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/pcs_to_mac/secondary_sample_point ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/mac_to_pcs/data_phase_stop ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/mac_to_pcs/do_hard_sync ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/mac_to_pcs/next_bit_is_brs ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/mac_to_pcs/next_bit_is_res ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/mac_to_pcs/transmitting )

add wave -vgroup dut2_pcs_internals \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_pcs/data_phase_active ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_pcs/first_data_bit_boundary_seen ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_pcs/ssp_standoff_active ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_pcs/bit_boundary ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_pcs/tdc_delay ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_pcs/ssp_seen ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_pcs/ssp_active ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_pcs/delay_count_tq ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_pcs/tdc_count_active ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_pcs/active_sjw ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_pcs/active_phase_seg2 ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_pcs/active_phase_seg1 ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_pcs/active_prop_seg ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_pcs/recessive_counter ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_pcs/phase2_shortening ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_pcs/phase1_extension ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_pcs/sync_applied ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_pcs/rx_bus_prev ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_pcs/seg_count ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_pcs/clk_count ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_pcs/segment ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_pcs/rx_i ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_pcs/tx_o ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_pcs/rst_i ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_pcs/clk_i )

add wave -vgroup dut_sb \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_bs/bs_o/valid ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_bs/bs_o/data )

add wave -vgroup dut_1_essentials \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/fce_to_mac/bus_off ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/is_transmitter ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/mac_ser_i/llc_metadata/fdf ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_mac/ser_to_fsm/llc_metadata/brs ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/bs_i/valid ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/bs_i/data ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/mac_i/tx_data ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/mac_o/rx_data ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/state ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/bit_count ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/mac_o/sample_point ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/mac_o/secondary_sample_point ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/mac_i/transmitting ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/mac_i/do_hard_sync ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/mac_i/data_phase_stop ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/mac_i/next_bit_is_brs ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_pcs/mac_i/next_bit_is_res ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/ack_success_seen ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/data_len ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_mac/u_can_mac_fsm/crc_length )

add wave -vgroup dut1_fce \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_fce/mac_o/bus_off ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_fce/mac_i/transmitting ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_fce/clk_i ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_fce/fce_state ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_fce/idle_count ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_fce/llc_i/normal_mode ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_fce/llc_o/bus_off ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_fce/mac_i/error ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_fce/mac_i/error_delimiter_too_late ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_fce/mac_i/passive_tx_ack_error_exempt_1 ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_fce/mac_i/primary_error ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_fce/mac_i/sending_error_overload_flag ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_fce/mac_i/successful_transfer ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_fce/mac_i/transmitting ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_fce/mac_o/bus_off ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_fce/mac_o/error_active ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_fce/pcs_i/idle_condition ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_fce/pcs_o/bus_off ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_fce/receiver_error_count ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_1/u_fce/rst_i ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_1/u_fce/transmitter_error_count )

add wave -vgroup dut2_essentials \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/rst ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/mac_to_pcs/tx_data ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/pcs_to_mac/rx_data ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/state ) \
	( -decimal /can_mac_pcs_fce_tb/u_dut_2/u_mac/u_can_mac_fsm/bit_count ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/pcs_to_mac/sample_point ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/mac_to_pcs/transmitting ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/mac_to_pcs/do_hard_sync ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/mac_to_pcs/data_phase_stop ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/mac_to_pcs/next_bit_is_brs ) \
	( -logic /can_mac_pcs_fce_tb/u_dut_2/mac_to_pcs/next_bit_is_res )

wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 100000ns
wv.time.unit.auto.set
transcript $curr_transcript
