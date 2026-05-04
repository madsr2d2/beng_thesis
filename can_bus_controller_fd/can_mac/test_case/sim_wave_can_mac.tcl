onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup "can_mac_tb :: TB" \
	( -logic /can_mac_tb/clk ) \
	( -logic /can_mac_tb/reset ) \
	( -logic /can_mac_tb/bus_level ) \
	( -literal /can_mac_tb/tx_llc_i/avalon_st_source/data ) \
	( -logic /can_mac_tb/tx_llc_i/avalon_st_source/valid ) \
	( -logic /can_mac_tb/tx_llc_i/avalon_st_source/startofpacket ) \
	( -logic /can_mac_tb/tx_llc_i/avalon_st_source/endofpacket ) \
	( -logic /can_mac_tb/tx_llc_o/avalon_st_sink/ready ) \
	( -literal /can_mac_tb/tx_llc_o/transfer_status ) \
	( -logic /can_mac_tb/tx_pcs_i/rx_data ) \
	( -logic /can_mac_tb/tx_pcs_i/sample_point ) \
	( -logic /can_mac_tb/tx_pcs_i/secondary_sample_point ) \
	( -literal /can_mac_tb/tx_pcs_i/tdc_delay ) \
	( -logic /can_mac_tb/tx_pcs_o/tx_data ) \
	( -logic /can_mac_tb/tx_pcs_o/next_bit_is_res ) \
	( -logic /can_mac_tb/tx_pcs_o/next_bit_is_brs ) \
	( -logic /can_mac_tb/tx_pcs_o/data_phase_stop ) \
	( -logic /can_mac_tb/tx_pcs_o/do_hard_sync ) \
	( -logic /can_mac_tb/tx_pcs_o/transmitting ) \
	( -logic /can_mac_tb/tx_fce_i/error_active ) \
	( -logic /can_mac_tb/tx_fce_i/bus_off ) \
	( -logic /can_mac_tb/tx_fce_o/transmitting ) \
	( -logic /can_mac_tb/tx_fce_o/error ) \
	( -logic /can_mac_tb/tx_fce_o/primary_error ) \
	( -logic /can_mac_tb/tx_fce_o/sending_error_overload_flag ) \
	( -logic /can_mac_tb/tx_fce_o/passive_tx_ack_error_exempt_1 ) \
	( -logic /can_mac_tb/tx_fce_o/error_delimiter_too_late ) \
	( -logic /can_mac_tb/tx_fce_o/successful_transfer ) \
	( -literal /can_mac_tb/status_latch ) \
	( -logic /can_mac_tb/clear_status ) \
	( -logic /can_mac_tb/rx_llc_i/avalon_st_sink/ready ) \
	( -literal /can_mac_tb/rx_llc_o/avalon_st_source/data ) \
	( -logic /can_mac_tb/rx_llc_o/avalon_st_source/valid ) \
	( -logic /can_mac_tb/rx_llc_o/avalon_st_source/startofpacket ) \
	( -logic /can_mac_tb/rx_llc_o/avalon_st_source/endofpacket ) \
	( -logic /can_mac_tb/rx_pcs_i/rx_data ) \
	( -logic /can_mac_tb/rx_pcs_i/sample_point ) \
	( -logic /can_mac_tb/rx_pcs_i/secondary_sample_point ) \
	( -literal /can_mac_tb/rx_pcs_i/tdc_delay ) \
	( -logic /can_mac_tb/rx_pcs_o/tx_data ) \
	( -logic /can_mac_tb/rx_pcs_o/next_bit_is_res ) \
	( -logic /can_mac_tb/rx_pcs_o/next_bit_is_brs ) \
	( -logic /can_mac_tb/rx_pcs_o/data_phase_stop ) \
	( -logic /can_mac_tb/rx_pcs_o/do_hard_sync ) \
	( -logic /can_mac_tb/rx_pcs_o/transmitting ) \
	( -logic /can_mac_tb/rx_fce_i/error_active ) \
	( -logic /can_mac_tb/rx_fce_i/bus_off ) \
	( -logic /can_mac_tb/rx_fce_o/transmitting ) \
	( -logic /can_mac_tb/rx_fce_o/error ) \
	( -logic /can_mac_tb/rx_fce_o/primary_error ) \
	( -logic /can_mac_tb/rx_fce_o/sending_error_overload_flag ) \
	( -logic /can_mac_tb/rx_fce_o/passive_tx_ack_error_exempt_1 ) \
	( -logic /can_mac_tb/rx_fce_o/error_delimiter_too_late ) \
	( -logic /can_mac_tb/rx_fce_o/successful_transfer ) \
	( -decimal /can_mac_tb/test_id ) \
	( -decimal /can_mac_tb/check_id ) \
	( -logic /can_mac_tb/init_barrier ) \
	( -decimal /can_mac_tb/test_num ) \
	( -logic /can_mac_tb/transmitting ) \
	( -logic /can_mac_tb/pcs_valid_seen ) \
	( -logic /can_mac_tb/llc_valid_seen ) \
	( -logic /can_mac_tb/fce_active_seen ) \
	( -logic /can_mac_tb/clear_latches )

add wave -vgroup "u_mac_tx :: inputs" \
	( -logic /can_mac_tb/u_mac_tx/clk ) \
	( -logic /can_mac_tb/u_mac_tx/rst ) \
	( -literal /can_mac_tb/u_mac_tx/llc_i/avalon_st_source/data ) \
	( -logic /can_mac_tb/u_mac_tx/llc_i/avalon_st_source/valid ) \
	( -logic /can_mac_tb/u_mac_tx/llc_i/avalon_st_source/startofpacket ) \
	( -logic /can_mac_tb/u_mac_tx/llc_i/avalon_st_source/endofpacket ) \
	( -logic /can_mac_tb/u_mac_tx/pcs_i/rx_data ) \
	( -logic /can_mac_tb/u_mac_tx/pcs_i/sample_point ) \
	( -logic /can_mac_tb/u_mac_tx/pcs_i/secondary_sample_point ) \
	( -literal /can_mac_tb/u_mac_tx/pcs_i/tdc_delay ) \
	( -logic /can_mac_tb/u_mac_tx/fce_i/error_active ) \
	( -logic /can_mac_tb/u_mac_tx/fce_i/bus_off )

add wave -vgroup "u_mac_tx :: outputs" \
	( -logic /can_mac_tb/u_mac_tx/llc_o/avalon_st_sink/ready ) \
	( -literal /can_mac_tb/u_mac_tx/llc_o/transfer_status ) \
	( -logic /can_mac_tb/u_mac_tx/pcs_o/tx_data ) \
	( -logic /can_mac_tb/u_mac_tx/pcs_o/next_bit_is_res ) \
	( -logic /can_mac_tb/u_mac_tx/pcs_o/next_bit_is_brs ) \
	( -logic /can_mac_tb/u_mac_tx/pcs_o/data_phase_stop ) \
	( -logic /can_mac_tb/u_mac_tx/pcs_o/do_hard_sync ) \
	( -logic /can_mac_tb/u_mac_tx/pcs_o/transmitting ) \
	( -logic /can_mac_tb/u_mac_tx/fce_o/transmitting ) \
	( -logic /can_mac_tb/u_mac_tx/fce_o/error ) \
	( -logic /can_mac_tb/u_mac_tx/fce_o/primary_error ) \
	( -logic /can_mac_tb/u_mac_tx/fce_o/sending_error_overload_flag ) \
	( -logic /can_mac_tb/u_mac_tx/fce_o/passive_tx_ack_error_exempt_1 ) \
	( -logic /can_mac_tb/u_mac_tx/fce_o/error_delimiter_too_late ) \
	( -logic /can_mac_tb/u_mac_tx/fce_o/successful_transfer )

add wave -vgroup "u_mac_tx :: internals" \
	( -logic /can_mac_tb/u_mac_tx/ser_to_fsm/data ) \
	( -logic /can_mac_tb/u_mac_tx/ser_to_fsm/valid ) \
	( -logic /can_mac_tb/u_mac_tx/ser_to_fsm/llc_metadata/ide ) \
	( -logic /can_mac_tb/u_mac_tx/ser_to_fsm/llc_metadata/fdf ) \
	( -literal /can_mac_tb/u_mac_tx/ser_to_fsm/llc_metadata/dlc ) \
	( -logic /can_mac_tb/u_mac_tx/ser_to_fsm/llc_metadata/ftyp ) \
	( -logic /can_mac_tb/u_mac_tx/ser_to_fsm/llc_metadata/brs ) \
	( -logic /can_mac_tb/u_mac_tx/ser_to_fsm/llc_metadata/esi ) \
	( -literal /can_mac_tb/u_mac_tx/fsm_to_ser/transfer_status ) \
	( -logic /can_mac_tb/u_mac_tx/fsm_to_ser/ready ) \
	( -logic /can_mac_tb/u_mac_tx/fsm_to_bs_fd/data ) \
	( -logic /can_mac_tb/u_mac_tx/fsm_to_bs_fd/valid ) \
	( -logic /can_mac_tb/u_mac_tx/fsm_to_bs_fd/fixed_bit_stuffing_en ) \
	( -logic /can_mac_tb/u_mac_tx/bs_fd_to_fsm/data ) \
	( -logic /can_mac_tb/u_mac_tx/bs_fd_to_fsm/valid ) \
	( -literal /can_mac_tb/u_mac_tx/bs_fd_to_fsm/stuff_bit_count ) \
	( -logic /can_mac_tb/u_mac_tx/fsm_bs_fd_rst ) \
	( -literal /can_mac_tb/u_mac_tx/fsm_to_crc/crc_poly_select ) \
	( -logic /can_mac_tb/u_mac_tx/fsm_to_crc/valid_cc ) \
	( -logic /can_mac_tb/u_mac_tx/fsm_to_crc/valid_fd ) \
	( -logic /can_mac_tb/u_mac_tx/fsm_to_crc/data_cc ) \
	( -logic /can_mac_tb/u_mac_tx/fsm_to_crc/data_fd ) \
	( -literal /can_mac_tb/u_mac_tx/crc_to_fsm/crc ) \
	( -logic /can_mac_tb/u_mac_tx/fsm_crc_rst )

add wave -vgroup "u_mac_tx/u_can_mac_ser_tx :: inputs" \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/clk_i ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/rst_i ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/llc_i/avalon_st_source/data ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/llc_i/avalon_st_source/valid ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/llc_i/avalon_st_source/startofpacket ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/llc_i/avalon_st_source/endofpacket ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/tx_mac_fsm_i/transfer_status ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/tx_mac_fsm_i/ready )

add wave -vgroup "u_mac_tx/u_can_mac_ser_tx :: outputs" \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/llc_o/avalon_st_sink/ready ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/llc_o/transfer_status ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/tx_mac_fsm_o/data ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/tx_mac_fsm_o/valid ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/tx_mac_fsm_o/llc_metadata/ide ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/tx_mac_fsm_o/llc_metadata/fdf ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/tx_mac_fsm_o/llc_metadata/dlc ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/tx_mac_fsm_o/llc_metadata/ftyp ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/tx_mac_fsm_o/llc_metadata/brs ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/tx_mac_fsm_o/llc_metadata/esi )

add wave -vgroup "u_mac_tx/u_can_mac_ser_tx :: internals" \
	( -decimal /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/state ) \
	( -decimal /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/count ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/llc_frame_buffer ) \
	( -decimal /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/id_bits_remaining ) \
	( -decimal /can_mac_tb/u_mac_tx/u_can_mac_ser_tx/padding_bits_remaining )

add wave -vgroup "u_mac_tx/u_can_mac_fsm_tx :: inputs" \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/clk_i ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/rst_i ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/mac_ser_i/data ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/mac_ser_i/valid ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/mac_ser_i/llc_metadata/ide ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/mac_ser_i/llc_metadata/fdf ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/mac_ser_i/llc_metadata/dlc ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/mac_ser_i/llc_metadata/ftyp ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/mac_ser_i/llc_metadata/brs ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/mac_ser_i/llc_metadata/esi ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/pcs_i/rx_data ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/pcs_i/sample_point ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/pcs_i/secondary_sample_point ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/pcs_i/tdc_delay ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/bs_i/data ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/bs_i/valid ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/bs_i/stuff_bit_count ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/crc_i/crc ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/fce_i/error_active ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/fce_i/bus_off )

add wave -vgroup "u_mac_tx/u_can_mac_fsm_tx :: outputs" \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/mac_ser_o/transfer_status ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/mac_ser_o/ready ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/pcs_o/tx_data ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/pcs_o/next_bit_is_res ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/pcs_o/next_bit_is_brs ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/pcs_o/data_phase_stop ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/pcs_o/do_hard_sync ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/pcs_o/transmitting ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/bs_o/data ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/bs_o/valid ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/bs_o/fixed_bit_stuffing_en ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/bs_rst ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/crc_o/crc_poly_select ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/crc_o/valid_cc ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/crc_o/valid_fd ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/crc_o/data_cc ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/crc_o/data_fd ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/crc_rst ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/fce_o/transmitting ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/fce_o/error ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/fce_o/primary_error ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/fce_o/sending_error_overload_flag ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/fce_o/passive_tx_ack_error_exempt_1 ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/fce_o/error_delimiter_too_late ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/fce_o/successful_transfer )

add wave -vgroup "u_mac_tx/u_can_mac_fsm_tx :: internals" \
	( -decimal /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/state ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/overload ) \
	( -decimal /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/bit_count ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/polarity_history ) \
	( -decimal /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/data_len ) \
	( -decimal /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/crc_length ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/was_previous_frame_tx ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/ack_success_seen ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/secondary_sample_point_error_pending ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/skip_sof ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/ack_error_caused_flag ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/saw_dominant_during_flag ) \
	( -decimal /can_mac_tb/u_mac_tx/u_can_mac_fsm_tx/dominant_run_count )

add wave -vgroup "u_mac_tx/u_can_mac_bs :: inputs" \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_bs/clk_i ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_bs/rst_i ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_bs/bs_i/data ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_bs/bs_i/valid ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_bs/bs_i/fixed_bit_stuffing_en )

add wave -vgroup "u_mac_tx/u_can_mac_bs :: outputs" \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_bs/bs_o/data ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_bs/bs_o/valid ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_bs/bs_o/stuff_bit_count )

add wave -vgroup "u_mac_tx/u_can_mac_bs :: internals" \
	( -decimal /can_mac_tb/u_mac_tx/u_can_mac_bs/count ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_bs/last_polarity ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_bs/stuff_count ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_bs/fsb_en_latch )

add wave -vgroup "u_mac_tx/u_can_mac_crc :: inputs" \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_crc/clk_i ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_crc/rst_i ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_crc/crc_i/crc_poly_select ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_crc/crc_i/valid_cc ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_crc/crc_i/valid_fd ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_crc/crc_i/data_cc ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_crc/crc_i/data_fd )

add wave -vgroup "u_mac_tx/u_can_mac_crc :: outputs" \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_crc/crc_o/crc )

add wave -vgroup "u_mac_tx/u_can_mac_crc :: internals" \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_crc/crc15_out ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_crc/crc17_out ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_crc/crc21_out )

add wave -vgroup "u_mac_tx/u_can_mac_crc/u_crc15 :: inputs" \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc15/clk_i ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc15/reset_i ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc15/start_crc_i ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc15/data_i ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc15/data_valid_i )

add wave -vgroup "u_mac_tx/u_can_mac_crc/u_crc15 :: outputs" \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc15/crc_o )

add wave -vgroup "u_mac_tx/u_can_mac_crc/u_crc15 :: internals" \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc15/crc_reg )

add wave -vgroup "u_mac_tx/u_can_mac_crc/u_crc17 :: inputs" \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc17/clk_i ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc17/reset_i ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc17/start_crc_i ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc17/data_i ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc17/data_valid_i )

add wave -vgroup "u_mac_tx/u_can_mac_crc/u_crc17 :: outputs" \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc17/crc_o )

add wave -vgroup "u_mac_tx/u_can_mac_crc/u_crc17 :: internals" \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc17/crc_reg )

add wave -vgroup "u_mac_tx/u_can_mac_crc/u_crc21 :: inputs" \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc21/clk_i ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc21/reset_i ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc21/start_crc_i ) \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc21/data_i ) \
	( -logic /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc21/data_valid_i )

add wave -vgroup "u_mac_tx/u_can_mac_crc/u_crc21 :: outputs" \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc21/crc_o )

add wave -vgroup "u_mac_tx/u_can_mac_crc/u_crc21 :: internals" \
	( -literal /can_mac_tb/u_mac_tx/u_can_mac_crc/u_crc21/crc_reg )

add wave -vgroup "u_mac_rx :: inputs" \
	( -logic /can_mac_tb/u_mac_rx/clk ) \
	( -logic /can_mac_tb/u_mac_rx/rst ) \
	( -logic /can_mac_tb/u_mac_rx/llc_i/avalon_st_sink/ready ) \
	( -logic /can_mac_tb/u_mac_rx/pcs_i/rx_data ) \
	( -logic /can_mac_tb/u_mac_rx/pcs_i/sample_point ) \
	( -logic /can_mac_tb/u_mac_rx/pcs_i/secondary_sample_point ) \
	( -literal /can_mac_tb/u_mac_rx/pcs_i/tdc_delay ) \
	( -logic /can_mac_tb/u_mac_rx/fce_i/error_active ) \
	( -logic /can_mac_tb/u_mac_rx/fce_i/bus_off ) \
	( -logic /can_mac_tb/u_mac_rx/transmitting_i )

add wave -vgroup "u_mac_rx :: outputs" \
	( -literal /can_mac_tb/u_mac_rx/llc_o/avalon_st_source/data ) \
	( -logic /can_mac_tb/u_mac_rx/llc_o/avalon_st_source/valid ) \
	( -logic /can_mac_tb/u_mac_rx/llc_o/avalon_st_source/startofpacket ) \
	( -logic /can_mac_tb/u_mac_rx/llc_o/avalon_st_source/endofpacket ) \
	( -logic /can_mac_tb/u_mac_rx/pcs_o/tx_data ) \
	( -logic /can_mac_tb/u_mac_rx/pcs_o/next_bit_is_res ) \
	( -logic /can_mac_tb/u_mac_rx/pcs_o/next_bit_is_brs ) \
	( -logic /can_mac_tb/u_mac_rx/pcs_o/data_phase_stop ) \
	( -logic /can_mac_tb/u_mac_rx/pcs_o/do_hard_sync ) \
	( -logic /can_mac_tb/u_mac_rx/pcs_o/transmitting ) \
	( -logic /can_mac_tb/u_mac_rx/fce_o/transmitting ) \
	( -logic /can_mac_tb/u_mac_rx/fce_o/error ) \
	( -logic /can_mac_tb/u_mac_rx/fce_o/primary_error ) \
	( -logic /can_mac_tb/u_mac_rx/fce_o/sending_error_overload_flag ) \
	( -logic /can_mac_tb/u_mac_rx/fce_o/passive_tx_ack_error_exempt_1 ) \
	( -logic /can_mac_tb/u_mac_rx/fce_o/error_delimiter_too_late ) \
	( -logic /can_mac_tb/u_mac_rx/fce_o/successful_transfer )

add wave -vgroup "u_mac_rx :: internals" \
	( -logic /can_mac_tb/u_mac_rx/fsm_to_bs/data ) \
	( -logic /can_mac_tb/u_mac_rx/fsm_to_bs/valid ) \
	( -logic /can_mac_tb/u_mac_rx/fsm_to_bs/fixed_bit_stuffing_en ) \
	( -logic /can_mac_tb/u_mac_rx/bs_to_fsm/data ) \
	( -logic /can_mac_tb/u_mac_rx/bs_to_fsm/valid ) \
	( -literal /can_mac_tb/u_mac_rx/bs_to_fsm/stuff_bit_count ) \
	( -logic /can_mac_tb/u_mac_rx/fsm_bs_rst ) \
	( -literal /can_mac_tb/u_mac_rx/fsm_to_crc/crc_poly_select ) \
	( -logic /can_mac_tb/u_mac_rx/fsm_to_crc/valid_cc ) \
	( -logic /can_mac_tb/u_mac_rx/fsm_to_crc/valid_fd ) \
	( -logic /can_mac_tb/u_mac_rx/fsm_to_crc/data_cc ) \
	( -logic /can_mac_tb/u_mac_rx/fsm_to_crc/data_fd ) \
	( -literal /can_mac_tb/u_mac_rx/crc_to_fsm/crc ) \
	( -logic /can_mac_tb/u_mac_rx/fsm_crc_rst )

add wave -vgroup "u_mac_rx/u_can_mac_fsm_rx :: inputs" \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/clk_i ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/rst_i ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/llc_i/avalon_st_sink/ready ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/pcs_i/rx_data ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/pcs_i/sample_point ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/pcs_i/secondary_sample_point ) \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/pcs_i/tdc_delay ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/bs_i/data ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/bs_i/valid ) \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/bs_i/stuff_bit_count ) \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/crc_i/crc ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/fce_i/error_active ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/fce_i/bus_off ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/transmitting_i )

add wave -vgroup "u_mac_rx/u_can_mac_fsm_rx :: outputs" \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/llc_o/avalon_st_source/data ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/llc_o/avalon_st_source/valid ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/llc_o/avalon_st_source/startofpacket ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/llc_o/avalon_st_source/endofpacket ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/pcs_o/tx_data ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/pcs_o/next_bit_is_res ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/pcs_o/next_bit_is_brs ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/pcs_o/data_phase_stop ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/pcs_o/do_hard_sync ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/pcs_o/transmitting ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/bs_o/data ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/bs_o/valid ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/bs_o/fixed_bit_stuffing_en ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/bs_rst ) \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/crc_o/crc_poly_select ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/crc_o/valid_cc ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/crc_o/valid_fd ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/crc_o/data_cc ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/crc_o/data_fd ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/crc_rst ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/fce_o/transmitting ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/fce_o/error ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/fce_o/primary_error ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/fce_o/sending_error_overload_flag ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/fce_o/passive_tx_ack_error_exempt_1 ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/fce_o/error_delimiter_too_late ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/fce_o/successful_transfer )

add wave -vgroup "u_mac_rx/u_can_mac_fsm_rx :: internals" \
	( -decimal /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/fsm_state ) \
	( -decimal /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/bit_count ) \
	( -decimal /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/byte_index ) \
	( -decimal /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/stream_index ) \
	( -decimal /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/bit_index ) \
	( -decimal /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/data_len ) \
	( -decimal /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/crc_length ) \
	( -decimal /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/llc_frame_len ) \
	( -decimal /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/llc_frame ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/crc_mismatch ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/llc_stream_start ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/llc_stream_done ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_fsm_rx/overload )

add wave -vgroup "u_mac_rx/u_can_mac_bs :: inputs" \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_bs/clk_i ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_bs/rst_i ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_bs/bs_i/data ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_bs/bs_i/valid ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_bs/bs_i/fixed_bit_stuffing_en )

add wave -vgroup "u_mac_rx/u_can_mac_bs :: outputs" \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_bs/bs_o/data ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_bs/bs_o/valid ) \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_bs/bs_o/stuff_bit_count )

add wave -vgroup "u_mac_rx/u_can_mac_bs :: internals" \
	( -decimal /can_mac_tb/u_mac_rx/u_can_mac_bs/count ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_bs/last_polarity ) \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_bs/stuff_count ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_bs/fsb_en_latch )

add wave -vgroup "u_mac_rx/u_can_mac_crc :: inputs" \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_crc/clk_i ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_crc/rst_i ) \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_crc/crc_i/crc_poly_select ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_crc/crc_i/valid_cc ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_crc/crc_i/valid_fd ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_crc/crc_i/data_cc ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_crc/crc_i/data_fd )

add wave -vgroup "u_mac_rx/u_can_mac_crc :: outputs" \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_crc/crc_o/crc )

add wave -vgroup "u_mac_rx/u_can_mac_crc :: internals" \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_crc/crc15_out ) \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_crc/crc17_out ) \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_crc/crc21_out )

add wave -vgroup "u_mac_rx/u_can_mac_crc/u_crc15 :: inputs" \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc15/clk_i ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc15/reset_i ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc15/start_crc_i ) \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc15/data_i ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc15/data_valid_i )

add wave -vgroup "u_mac_rx/u_can_mac_crc/u_crc15 :: outputs" \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc15/crc_o )

add wave -vgroup "u_mac_rx/u_can_mac_crc/u_crc15 :: internals" \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc15/crc_reg )

add wave -vgroup "u_mac_rx/u_can_mac_crc/u_crc17 :: inputs" \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc17/clk_i ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc17/reset_i ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc17/start_crc_i ) \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc17/data_i ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc17/data_valid_i )

add wave -vgroup "u_mac_rx/u_can_mac_crc/u_crc17 :: outputs" \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc17/crc_o )

add wave -vgroup "u_mac_rx/u_can_mac_crc/u_crc17 :: internals" \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc17/crc_reg )

add wave -vgroup "u_mac_rx/u_can_mac_crc/u_crc21 :: inputs" \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc21/clk_i ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc21/reset_i ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc21/start_crc_i ) \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc21/data_i ) \
	( -logic /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc21/data_valid_i )

add wave -vgroup "u_mac_rx/u_can_mac_crc/u_crc21 :: outputs" \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc21/crc_o )

add wave -vgroup "u_mac_rx/u_can_mac_crc/u_crc21 :: internals" \
	( -literal /can_mac_tb/u_mac_rx/u_can_mac_crc/u_crc21/crc_reg )

wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 100000ns
wv.time.unit.auto.set
transcript $curr_transcript
