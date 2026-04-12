onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup "can_mac_rx_tb :: TB" \
	( -logic /can_mac_rx_tb/clk ) \
	( -logic /can_mac_rx_tb/reset ) \
	( -logic /can_mac_rx_tb/llc_i/avalon_st_sink/ready ) \
	( -literal /can_mac_rx_tb/llc_o/avalon_st_source/data ) \
	( -logic /can_mac_rx_tb/llc_o/avalon_st_source/valid ) \
	( -logic /can_mac_rx_tb/llc_o/avalon_st_source/startofpacket ) \
	( -logic /can_mac_rx_tb/llc_o/avalon_st_source/endofpacket ) \
	( -logic /can_mac_rx_tb/pcs_i/bus_polarity ) \
	( -logic /can_mac_rx_tb/pcs_i/sample_point ) \
	( -logic /can_mac_rx_tb/pcs_i/secondary_sample_point ) \
	( -literal /can_mac_rx_tb/pcs_i/tdc_delay ) \
	( -logic /can_mac_rx_tb/pcs_o/polarity ) \
	( -logic /can_mac_rx_tb/pcs_o/valid ) \
	( -logic /can_mac_rx_tb/pcs_o/use_data_rate ) \
	( -logic /can_mac_rx_tb/pcs_o/start_tdc ) \
	( -logic /can_mac_rx_tb/fce_i/error_passive_request ) \
	( -logic /can_mac_rx_tb/fce_i/error_active_request ) \
	( -logic /can_mac_rx_tb/fce_o/transmitting ) \
	( -logic /can_mac_rx_tb/fce_o/error ) \
	( -logic /can_mac_rx_tb/fce_o/primary_error ) \
	( -logic /can_mac_rx_tb/fce_o/sending_error_overload_flag ) \
	( -logic /can_mac_rx_tb/fce_o/counters_unchanged ) \
	( -logic /can_mac_rx_tb/fce_o/error_delimiter_too_late ) \
	( -logic /can_mac_rx_tb/fce_o/successful_transfer ) \
	( -logic /can_mac_rx_tb/fce_o/error_passive_response ) \
	( -logic /can_mac_rx_tb/fce_o/error_active_response ) \
	( -decimal /can_mac_rx_tb/test_id ) \
	( -decimal /can_mac_rx_tb/check_id ) \
	( -logic /can_mac_rx_tb/init_barrier ) \
	( -logic /can_mac_rx_tb/pcs_ready )

add wave -vgroup "u_dut :: inputs" \
	( -logic /can_mac_rx_tb/u_dut/clk ) \
	( -logic /can_mac_rx_tb/u_dut/rst ) \
	( -logic /can_mac_rx_tb/u_dut/llc_i/avalon_st_sink/ready ) \
	( -logic /can_mac_rx_tb/u_dut/pcs_i/bus_polarity ) \
	( -logic /can_mac_rx_tb/u_dut/pcs_i/sample_point ) \
	( -logic /can_mac_rx_tb/u_dut/pcs_i/secondary_sample_point ) \
	( -literal /can_mac_rx_tb/u_dut/pcs_i/tdc_delay ) \
	( -logic /can_mac_rx_tb/u_dut/fce_i/error_passive_request ) \
	( -logic /can_mac_rx_tb/u_dut/fce_i/error_active_request )

add wave -vgroup "u_dut :: outputs" \
	( -literal /can_mac_rx_tb/u_dut/llc_o/avalon_st_source/data ) \
	( -logic /can_mac_rx_tb/u_dut/llc_o/avalon_st_source/valid ) \
	( -logic /can_mac_rx_tb/u_dut/llc_o/avalon_st_source/startofpacket ) \
	( -logic /can_mac_rx_tb/u_dut/llc_o/avalon_st_source/endofpacket ) \
	( -logic /can_mac_rx_tb/u_dut/pcs_o/polarity ) \
	( -logic /can_mac_rx_tb/u_dut/pcs_o/valid ) \
	( -logic /can_mac_rx_tb/u_dut/pcs_o/use_data_rate ) \
	( -logic /can_mac_rx_tb/u_dut/pcs_o/start_tdc ) \
	( -logic /can_mac_rx_tb/u_dut/fce_o/transmitting ) \
	( -logic /can_mac_rx_tb/u_dut/fce_o/error ) \
	( -logic /can_mac_rx_tb/u_dut/fce_o/primary_error ) \
	( -logic /can_mac_rx_tb/u_dut/fce_o/sending_error_overload_flag ) \
	( -logic /can_mac_rx_tb/u_dut/fce_o/counters_unchanged ) \
	( -logic /can_mac_rx_tb/u_dut/fce_o/error_delimiter_too_late ) \
	( -logic /can_mac_rx_tb/u_dut/fce_o/successful_transfer ) \
	( -logic /can_mac_rx_tb/u_dut/fce_o/error_passive_response ) \
	( -logic /can_mac_rx_tb/u_dut/fce_o/error_active_response )

add wave -vgroup "u_dut :: internals" \
	( -logic /can_mac_rx_tb/u_dut/fsm_to_bs/data ) \
	( -logic /can_mac_rx_tb/u_dut/fsm_to_bs/valid ) \
	( -logic /can_mac_rx_tb/u_dut/fsm_to_bs/fixed_bit_stuffing_en ) \
	( -logic /can_mac_rx_tb/u_dut/bs_to_fsm/data ) \
	( -logic /can_mac_rx_tb/u_dut/bs_to_fsm/valid ) \
	( -literal /can_mac_rx_tb/u_dut/bs_to_fsm/stuff_bit_count ) \
	( -logic /can_mac_rx_tb/u_dut/fsm_bs_rst ) \
	( -literal /can_mac_rx_tb/u_dut/fsm_to_crc/crc_poly_select ) \
	( -logic /can_mac_rx_tb/u_dut/fsm_to_crc/valid_cc ) \
	( -logic /can_mac_rx_tb/u_dut/fsm_to_crc/valid_fd ) \
	( -logic /can_mac_rx_tb/u_dut/fsm_to_crc/data_cc ) \
	( -logic /can_mac_rx_tb/u_dut/fsm_to_crc/data_fd ) \
	( -literal /can_mac_rx_tb/u_dut/crc_to_fsm/crc ) \
	( -logic /can_mac_rx_tb/u_dut/fsm_crc_rst )

add wave -vgroup "u_dut/u_can_mac_fsm_rx :: inputs" \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/clk_i ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/rst_i ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/llc_i/avalon_st_sink/ready ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/pcs_i/bus_polarity ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/pcs_i/sample_point ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/pcs_i/secondary_sample_point ) \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/pcs_i/tdc_delay ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/bs_i/data ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/bs_i/valid ) \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/bs_i/stuff_bit_count ) \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/crc_i/crc ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/fce_i/error_passive_request ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/fce_i/error_active_request )

add wave -vgroup "u_dut/u_can_mac_fsm_rx :: outputs" \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/llc_o/avalon_st_source/data ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/llc_o/avalon_st_source/valid ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/llc_o/avalon_st_source/startofpacket ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/llc_o/avalon_st_source/endofpacket ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/pcs_o/polarity ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/pcs_o/valid ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/pcs_o/use_data_rate ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/pcs_o/start_tdc ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/bs_o/data ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/bs_o/valid ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/bs_o/fixed_bit_stuffing_en ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/bs_rst ) \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/crc_o/crc_poly_select ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/crc_o/valid_cc ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/crc_o/valid_fd ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/crc_o/data_cc ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/crc_o/data_fd ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/crc_rst ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/fce_o/transmitting ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/fce_o/error ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/fce_o/primary_error ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/fce_o/sending_error_overload_flag ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/fce_o/counters_unchanged ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/fce_o/error_delimiter_too_late ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/fce_o/successful_transfer ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/fce_o/error_passive_response ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/fce_o/error_active_response )

add wave -vgroup "u_dut/u_can_mac_fsm_rx :: internals" \
	( -decimal /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/fsm_state ) \
	( -decimal /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/bit_count ) \
	( -decimal /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/byte_index ) \
	( -decimal /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/stream_index ) \
	( -decimal /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/bit_index ) \
	( -decimal /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/data_len ) \
	( -decimal /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/crc_length ) \
	( -decimal /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/llc_frame_len ) \
	( -decimal /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/llc_frame ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/crc_mismatch ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/llc_stream_start ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/llc_stream_done ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_fsm_rx/overload )

add wave -vgroup "u_dut/u_can_mac_bs :: inputs" \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_bs/clk_i ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_bs/rst_i ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_bs/bs_i/data ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_bs/bs_i/valid ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_bs/bs_i/fixed_bit_stuffing_en )

add wave -vgroup "u_dut/u_can_mac_bs :: outputs" \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_bs/bs_o/data ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_bs/bs_o/valid ) \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_bs/bs_o/stuff_bit_count )

add wave -vgroup "u_dut/u_can_mac_bs :: internals" \
	( -decimal /can_mac_rx_tb/u_dut/u_can_mac_bs/count ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_bs/last_polarity ) \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_bs/stuff_count ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_bs/fsb_en_latch )

add wave -vgroup "u_dut/u_can_mac_crc :: inputs" \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_crc/clk_i ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_crc/rst_i ) \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_crc/crc_i/crc_poly_select ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_crc/crc_i/valid_cc ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_crc/crc_i/valid_fd ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_crc/crc_i/data_cc ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_crc/crc_i/data_fd )

add wave -vgroup "u_dut/u_can_mac_crc :: outputs" \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_crc/crc_o/crc )

add wave -vgroup "u_dut/u_can_mac_crc :: internals" \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_crc/crc15_out ) \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_crc/crc17_out ) \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_crc/crc21_out )

add wave -vgroup "u_dut/u_can_mac_crc/u_crc15 :: inputs" \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc15/clk_i ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc15/reset_i ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc15/start_crc_i ) \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc15/data_i ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc15/data_valid_i )

add wave -vgroup "u_dut/u_can_mac_crc/u_crc15 :: outputs" \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc15/crc_o )

add wave -vgroup "u_dut/u_can_mac_crc/u_crc15 :: internals" \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc15/crc_reg )

add wave -vgroup "u_dut/u_can_mac_crc/u_crc17 :: inputs" \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc17/clk_i ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc17/reset_i ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc17/start_crc_i ) \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc17/data_i ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc17/data_valid_i )

add wave -vgroup "u_dut/u_can_mac_crc/u_crc17 :: outputs" \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc17/crc_o )

add wave -vgroup "u_dut/u_can_mac_crc/u_crc17 :: internals" \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc17/crc_reg )

add wave -vgroup "u_dut/u_can_mac_crc/u_crc21 :: inputs" \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc21/clk_i ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc21/reset_i ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc21/start_crc_i ) \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc21/data_i ) \
	( -logic /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc21/data_valid_i )

add wave -vgroup "u_dut/u_can_mac_crc/u_crc21 :: outputs" \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc21/crc_o )

add wave -vgroup "u_dut/u_can_mac_crc/u_crc21 :: internals" \
	( -literal /can_mac_rx_tb/u_dut/u_can_mac_crc/u_crc21/crc_reg )

wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 100000ns
wv.time.unit.auto.set
transcript $curr_transcript
