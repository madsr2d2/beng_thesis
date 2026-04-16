onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup "can_mac_tx_tb :: TB" \
	( -logic /can_mac_tx_tb/clk ) \
	( -logic /can_mac_tx_tb/reset ) \
	( -literal /can_mac_tx_tb/llc_i/avalon_st_source/data ) \
	( -logic /can_mac_tx_tb/llc_i/avalon_st_source/valid ) \
	( -logic /can_mac_tx_tb/llc_i/avalon_st_source/startofpacket ) \
	( -logic /can_mac_tx_tb/llc_i/avalon_st_source/endofpacket ) \
	( -logic /can_mac_tx_tb/llc_o/avalon_st_sink/ready ) \
	( -literal /can_mac_tx_tb/llc_o/transfer_status ) \
	( -logic /can_mac_tx_tb/pcs_i/bus_polarity ) \
	( -logic /can_mac_tx_tb/pcs_i/sample_point ) \
	( -logic /can_mac_tx_tb/pcs_i/secondary_sample_point ) \
	( -literal /can_mac_tx_tb/pcs_i/tdc_delay ) \
	( -logic /can_mac_tx_tb/pcs_o/polarity ) \
	( -logic /can_mac_tx_tb/pcs_o/use_data_rate ) \
	( -logic /can_mac_tx_tb/pcs_o/start_tdc ) \
	( -logic /can_mac_tx_tb/fce_i/error_active ) \
	( -logic /can_mac_tx_tb/fce_i/bus_off ) \
	( -logic /can_mac_tx_tb/fce_o/transmitting ) \
	( -logic /can_mac_tx_tb/fce_o/error ) \
	( -logic /can_mac_tx_tb/fce_o/primary_error ) \
	( -logic /can_mac_tx_tb/fce_o/sending_error_overload_flag ) \
	( -logic /can_mac_tx_tb/fce_o/passive_tx_ack_error_exempt ) \
	( -logic /can_mac_tx_tb/fce_o/error_delimiter_too_late ) \
	( -logic /can_mac_tx_tb/fce_o/successful_transfer ) \
	( -logic /can_mac_tx_tb/bus_override_en ) \
	( -literal /can_mac_tx_tb/status_latch ) \
	( -literal /can_mac_tx_tb/fce_latch ) \
	( -decimal /can_mac_tx_tb/bus_idx ) \
	( -decimal /can_mac_tx_tb/aux_inj_pos ) \
	( -decimal /can_mac_tx_tb/test_id ) \
	( -decimal /can_mac_tx_tb/reset_check_id ) \
	( -decimal /can_mac_tx_tb/status_check_id ) \
	( -decimal /can_mac_tx_tb/stream_check_id ) \
	( -decimal /can_mac_tx_tb/fce_check_id ) \
	( -logic /can_mac_tx_tb/init_barrier )

add wave -vgroup "u_dut :: inputs" \
	( -logic /can_mac_tx_tb/u_dut/clk ) \
	( -logic /can_mac_tx_tb/u_dut/rst ) \
	( -literal /can_mac_tx_tb/u_dut/llc_i/avalon_st_source/data ) \
	( -logic /can_mac_tx_tb/u_dut/llc_i/avalon_st_source/valid ) \
	( -logic /can_mac_tx_tb/u_dut/llc_i/avalon_st_source/startofpacket ) \
	( -logic /can_mac_tx_tb/u_dut/llc_i/avalon_st_source/endofpacket ) \
	( -logic /can_mac_tx_tb/u_dut/pcs_i/bus_polarity ) \
	( -logic /can_mac_tx_tb/u_dut/pcs_i/sample_point ) \
	( -logic /can_mac_tx_tb/u_dut/pcs_i/secondary_sample_point ) \
	( -literal /can_mac_tx_tb/u_dut/pcs_i/tdc_delay ) \
	( -logic /can_mac_tx_tb/u_dut/fce_i/error_active ) \
	( -logic /can_mac_tx_tb/u_dut/fce_i/bus_off )

add wave -vgroup "u_dut :: outputs" \
	( -logic /can_mac_tx_tb/u_dut/llc_o/avalon_st_sink/ready ) \
	( -literal /can_mac_tx_tb/u_dut/llc_o/transfer_status ) \
	( -logic /can_mac_tx_tb/u_dut/pcs_o/polarity ) \
	( -logic /can_mac_tx_tb/u_dut/pcs_o/use_data_rate ) \
	( -logic /can_mac_tx_tb/u_dut/pcs_o/start_tdc ) \
	( -logic /can_mac_tx_tb/u_dut/fce_o/transmitting ) \
	( -logic /can_mac_tx_tb/u_dut/fce_o/error ) \
	( -logic /can_mac_tx_tb/u_dut/fce_o/primary_error ) \
	( -logic /can_mac_tx_tb/u_dut/fce_o/sending_error_overload_flag ) \
	( -logic /can_mac_tx_tb/u_dut/fce_o/passive_tx_ack_error_exempt ) \
	( -logic /can_mac_tx_tb/u_dut/fce_o/error_delimiter_too_late ) \
	( -logic /can_mac_tx_tb/u_dut/fce_o/successful_transfer )

add wave -vgroup "u_dut :: internals" \
	( -logic /can_mac_tx_tb/u_dut/ser_to_fsm/data ) \
	( -logic /can_mac_tx_tb/u_dut/ser_to_fsm/valid ) \
	( -logic /can_mac_tx_tb/u_dut/ser_to_fsm/llc_metadata/ide ) \
	( -logic /can_mac_tx_tb/u_dut/ser_to_fsm/llc_metadata/fdf ) \
	( -literal /can_mac_tx_tb/u_dut/ser_to_fsm/llc_metadata/dlc ) \
	( -logic /can_mac_tx_tb/u_dut/ser_to_fsm/llc_metadata/ftyp ) \
	( -logic /can_mac_tx_tb/u_dut/ser_to_fsm/llc_metadata/brs ) \
	( -logic /can_mac_tx_tb/u_dut/ser_to_fsm/llc_metadata/esi ) \
	( -literal /can_mac_tx_tb/u_dut/fsm_to_ser/transfer_status ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_to_ser/ready ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_to_bs_fd/data ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_to_bs_fd/valid ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_to_bs_fd/fixed_bit_stuffing_en ) \
	( -logic /can_mac_tx_tb/u_dut/bs_fd_to_fsm/data ) \
	( -logic /can_mac_tx_tb/u_dut/bs_fd_to_fsm/valid ) \
	( -literal /can_mac_tx_tb/u_dut/bs_fd_to_fsm/stuff_bit_count ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_bs_fd_rst ) \
	( -literal /can_mac_tx_tb/u_dut/fsm_to_crc/crc_poly_select ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_to_crc/valid_cc ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_to_crc/valid_fd ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_to_crc/data_cc ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_to_crc/data_fd ) \
	( -literal /can_mac_tx_tb/u_dut/crc_to_fsm/crc ) \
	( -logic /can_mac_tx_tb/u_dut/fsm_crc_rst )

add wave -vgroup "u_dut/u_can_mac_ser_tx :: inputs" \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/clk_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/rst_i ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/llc_i/avalon_st_source/data ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/llc_i/avalon_st_source/valid ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/llc_i/avalon_st_source/startofpacket ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/llc_i/avalon_st_source/endofpacket ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/tx_mac_fsm_i/transfer_status ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/tx_mac_fsm_i/ready )

add wave -vgroup "u_dut/u_can_mac_ser_tx :: outputs" \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/llc_o/avalon_st_sink/ready ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/llc_o/transfer_status ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/tx_mac_fsm_o/data ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/tx_mac_fsm_o/valid ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/tx_mac_fsm_o/llc_metadata/ide ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/tx_mac_fsm_o/llc_metadata/fdf ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/tx_mac_fsm_o/llc_metadata/dlc ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/tx_mac_fsm_o/llc_metadata/ftyp ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/tx_mac_fsm_o/llc_metadata/brs ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/tx_mac_fsm_o/llc_metadata/esi )

add wave -vgroup "u_dut/u_can_mac_ser_tx :: internals" \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/state ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/count ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/llc_frame_buffer ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/id_bits_remaining ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_ser_tx/padding_bits_remaining )

add wave -vgroup "u_dut/u_can_mac_fsm_tx :: inputs" \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/clk_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/rst_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/mac_ser_i/data ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/mac_ser_i/valid ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/mac_ser_i/llc_metadata/ide ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/mac_ser_i/llc_metadata/fdf ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/mac_ser_i/llc_metadata/dlc ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/mac_ser_i/llc_metadata/ftyp ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/mac_ser_i/llc_metadata/brs ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/mac_ser_i/llc_metadata/esi ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/pcs_i/bus_polarity ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/pcs_i/sample_point ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/pcs_i/secondary_sample_point ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/pcs_i/tdc_delay ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/bs_i/data ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/bs_i/valid ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/bs_i/stuff_bit_count ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/crc_i/crc ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/fce_i/error_active ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/fce_i/bus_off )

add wave -vgroup "u_dut/u_can_mac_fsm_tx :: outputs" \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/mac_ser_o/transfer_status ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/mac_ser_o/ready ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/pcs_o/polarity ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/pcs_o/use_data_rate ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/pcs_o/start_tdc ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/bs_o/data ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/bs_o/valid ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/bs_o/fixed_bit_stuffing_en ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/bs_rst ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/crc_o/crc_poly_select ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/crc_o/valid_cc ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/crc_o/valid_fd ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/crc_o/data_cc ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/crc_o/data_fd ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/crc_rst ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/fce_o/transmitting ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/fce_o/error ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/fce_o/primary_error ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/fce_o/sending_error_overload_flag ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/fce_o/passive_tx_ack_error_exempt ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/fce_o/error_delimiter_too_late ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/fce_o/successful_transfer )

add wave -vgroup "u_dut/u_can_mac_fsm_tx :: internals" \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/state ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/overload ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/bit_count ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/polarity_history ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/data_len ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/crc_length ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/was_previous_frame_tx ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/ack_success_seen ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/secondary_sample_point_error_pending ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/skip_sof ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/ack_error_caused_flag ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/saw_dominant_during_flag ) \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_fsm_tx/dominant_run_count )

add wave -vgroup "u_dut/u_can_mac_bs :: inputs" \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_bs/clk_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_bs/rst_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_bs/bs_i/data ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_bs/bs_i/valid ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_bs/bs_i/fixed_bit_stuffing_en )

add wave -vgroup "u_dut/u_can_mac_bs :: outputs" \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_bs/bs_o/data ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_bs/bs_o/valid ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_bs/bs_o/stuff_bit_count )

add wave -vgroup "u_dut/u_can_mac_bs :: internals" \
	( -decimal /can_mac_tx_tb/u_dut/u_can_mac_bs/count ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_bs/last_polarity ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_bs/stuff_count ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_bs/fsb_en_latch )

add wave -vgroup "u_dut/u_can_mac_crc :: inputs" \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/clk_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/rst_i ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_crc/crc_i/crc_poly_select ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/crc_i/valid_cc ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/crc_i/valid_fd ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/crc_i/data_cc ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/crc_i/data_fd )

add wave -vgroup "u_dut/u_can_mac_crc :: outputs" \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_crc/crc_o/crc )

add wave -vgroup "u_dut/u_can_mac_crc :: internals" \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_crc/crc15_out ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_crc/crc17_out ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_crc/crc21_out )

add wave -vgroup "u_dut/u_can_mac_crc/u_crc15 :: inputs" \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc15/clk_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc15/reset_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc15/start_crc_i ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc15/data_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc15/data_valid_i )

add wave -vgroup "u_dut/u_can_mac_crc/u_crc15 :: outputs" \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc15/crc_o )

add wave -vgroup "u_dut/u_can_mac_crc/u_crc15 :: internals" \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc15/crc_reg )

add wave -vgroup "u_dut/u_can_mac_crc/u_crc17 :: inputs" \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc17/clk_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc17/reset_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc17/start_crc_i ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc17/data_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc17/data_valid_i )

add wave -vgroup "u_dut/u_can_mac_crc/u_crc17 :: outputs" \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc17/crc_o )

add wave -vgroup "u_dut/u_can_mac_crc/u_crc17 :: internals" \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc17/crc_reg )

add wave -vgroup "u_dut/u_can_mac_crc/u_crc21 :: inputs" \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc21/clk_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc21/reset_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc21/start_crc_i ) \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc21/data_i ) \
	( -logic /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc21/data_valid_i )

add wave -vgroup "u_dut/u_can_mac_crc/u_crc21 :: outputs" \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc21/crc_o )

add wave -vgroup "u_dut/u_can_mac_crc/u_crc21 :: internals" \
	( -literal /can_mac_tx_tb/u_dut/u_can_mac_crc/u_crc21/crc_reg )

wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 100000ns
wv.time.unit.auto.set
transcript $curr_transcript
