onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup "can_pcs_tb" \
	( -logic /can_pcs_tb/clk_tx ) \
	( -logic /can_pcs_tb/clk_rx ) \
	( -logic /can_pcs_tb/reset ) \
	( -logic /can_pcs_tb/tx_tx_bus ) \
	( -logic /can_pcs_tb/rx_tx_bus ) \
	( -logic /can_pcs_tb/bus_level ) \
	( -logic /can_pcs_tb/rx_bus_wire ) \
	( -logic /can_pcs_tb/tx_loopback ) \
	( -logic /can_pcs_tb/tx_mac_i/polarity ) \
	( -logic /can_pcs_tb/tx_mac_i/use_data_rate ) \
	( -logic /can_pcs_tb/polarity_history ) \
	( -logic /can_pcs_tb/tx_mac_i/start_tdc ) \
	( -logic /can_pcs_tb/tx_mac_o/bus_polarity ) \
	( -logic /can_pcs_tb/tx_mac_o/sample_point ) \
	( -logic /can_pcs_tb/tx_mac_o/secondary_sample_point ) \
	( -literal /can_pcs_tb/tx_mac_o/tdc_delay ) \
	( -logic /can_pcs_tb/tx_fce_i/bus_off ) \
	( -logic /can_pcs_tb/tx_fce_o/idle_condition ) \
	( -logic /can_pcs_tb/rx_mac_i/polarity ) \
	( -logic /can_pcs_tb/rx_mac_i/use_data_rate ) \
	( -logic /can_pcs_tb/rx_mac_i/hard_sync_en ) \
	( -logic /can_pcs_tb/rx_mac_o/bus_polarity ) \
	( -logic /can_pcs_tb/rx_mac_o/sample_point ) \
	( -logic /can_pcs_tb/rx_fce_i/bus_off ) \
	( -logic /can_pcs_tb/rx_fce_o/idle_condition ) \
	( -decimal /can_pcs_tb/test_id ) \
	( -decimal /can_pcs_tb/check_id ) \
	( -logic /can_pcs_tb/init_barrier ) \
	( -decimal /can_pcs_tb/test_num ) \
	( -decimal /can_pcs_tb/bit_name ) \
	( -binary /can_pcs_tb/polarity_history ) \
	( -binary /can_pcs_tb/rx_bits ) \
	( -decimal /can_pcs_tb/rx_bit_index ) \
	( -decimal /can_pcs_tb/tx_bit_index )

add wave -vgroup "u_pcs_rx" \
	( -logic /can_pcs_tb/u_pcs_rx/mac_i/tx_data ) \
	( -logic /can_pcs_tb/u_pcs_rx/tx_o ) \
	( -logic /can_pcs_tb/u_pcs_rx/rx_i ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_o/rx_data ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_i/do_hard_sync ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_i/use_data_rate ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_i/current_bit_is_res ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_i/current_bit_is_brs ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_i/data_phase_stop ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_i/transmitting ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_o/sample_point ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_o/secondary_sample_point ) \
	( -decimal /can_pcs_tb/u_pcs_rx/mac_o/tdc_delay ) \
	( -logic /can_pcs_tb/u_pcs_rx/fce_o/idle_condition ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_i/start_tdc ) \
	( -logic /can_pcs_tb/u_pcs_rx/brs_sample_point_seen ) \
	( -logic /can_pcs_tb/u_pcs_rx/crc_delimiter_sample_point_seen ) \
	( -logic /can_pcs_tb/u_pcs_rx/fce_i/bus_off ) 

add wave -vgroup "u_pcs_rx internals" \
	( -logic /can_pcs_tb/u_pcs_rx/bit_boundary ) \
	( -logic /can_pcs_tb/u_pcs_rx/use_data_rate ) \
	( -logic /can_pcs_tb/u_pcs_rx/tdc_delay ) \
	( -logic /can_pcs_tb/u_pcs_rx/tdc_counting ) \
	( -decimal /can_pcs_tb/u_pcs_rx/delay_count_tq ) \
	( -logic /can_pcs_tb/u_pcs_tx/first_data_bit_boundary_seen) \
	( -literal /can_pcs_tb/u_pcs_rx/segment ) \
	( -decimal /can_pcs_tb/u_pcs_rx/clk_count ) \
	( -decimal /can_pcs_tb/u_pcs_rx/seg_count ) \
	( -decimal /can_pcs_tb/u_pcs_rx/ssp_active ) \
	( -decimal /can_pcs_tb/u_pcs_rx/data_phase_active ) \
	( -decimal /can_pcs_tb/u_pcs_rx/ssp_seen ) \
	( -logic /can_pcs_tb/u_pcs_rx/rx_bus_prev ) \
	( -logic /can_pcs_tb/u_pcs_rx/sync_applied ) \
	( -logic /can_pcs_tb/u_pcs_rx/hard_sync_applied ) \
	( -logic /can_pcs_tb/u_pcs_rx/sampled_polarity ) \
	( -decimal /can_pcs_tb/u_pcs_rx/phase1_extension ) \
	( -decimal /can_pcs_tb/u_pcs_rx/phase2_shortening ) \
	( -decimal /can_pcs_tb/u_pcs_rx/recessive_counter ) \
	( -logic /can_pcs_tb/u_pcs_rx/edge_detected ) \
	( -decimal /can_pcs_tb/u_pcs_rx/active_prop_seg ) \
	( -decimal /can_pcs_tb/u_pcs_rx/active_phase_seg1 ) \
	( -decimal /can_pcs_tb/u_pcs_rx/active_phase_seg2 ) \
	( -logic /can_pcs_tb/u_pcs_rx/use_data_rate ) 

add wave -vgroup "u_pcs_tx" \
	( -logic /can_pcs_tb/u_pcs_tx/mac_i/tx_data ) \
	( -logic /can_pcs_tb/u_pcs_tx/tx_o ) \
	( -logic /can_pcs_tb/u_pcs_tx/rx_i ) \
	( -logic /can_pcs_tb/u_pcs_tx/polarity_history ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_o/rx_data ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_i/do_hard_sync ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_i/use_data_rate ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_i/current_bit_is_res ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_i/current_bit_is_brs ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_i/data_phase_stop ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_i/transmitting ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_o/sample_point ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_o/secondary_sample_point ) \
	( -decimal /can_pcs_tb/u_pcs_tx/mac_o/tdc_delay ) \
	( -logic /can_pcs_tb/u_pcs_tx/fce_o/idle_condition ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_i/start_tdc ) \
	( -logic /can_pcs_tb/u_pcs_tx/brs_sample_point_seen ) \
	( -logic /can_pcs_tb/u_pcs_tx/crc_delimiter_sample_point_seen ) \
	( -logic /can_pcs_tb/u_pcs_tx/fce_i/bus_off ) 


add wave -vgroup "pcs_tx_internals" \
	( -logic /can_pcs_tb/u_pcs_tx/bit_boundary ) \
	( -logic /can_pcs_tb/u_pcs_tx/use_data_rate ) \
	( -logic /can_pcs_tb/u_pcs_tx/tdc_delay ) \
	( -logic /can_pcs_tb/u_pcs_tx/tdc_counting ) \
	( -decimal /can_pcs_tb/u_pcs_tx/delay_count_tq ) \
	( -logic /can_pcs_tb/u_pcs_tx/first_data_bit_boundary_seen) \
	( -literal /can_pcs_tb/u_pcs_tx/segment ) \
	( -decimal /can_pcs_tb/u_pcs_tx/clk_count ) \
	( -decimal /can_pcs_tb/u_pcs_tx/seg_count ) \
	( -decimal /can_pcs_tb/u_pcs_tx/ssp_active ) \
	( -decimal /can_pcs_tb/u_pcs_tx/data_phase_active ) \
	( -decimal /can_pcs_tb/u_pcs_tx/ssp_seen ) \
	( -logic /can_pcs_tb/u_pcs_tx/rx_bus_prev ) \
	( -logic /can_pcs_tb/u_pcs_tx/sync_applied ) \
	( -logic /can_pcs_tb/u_pcs_tx/hard_sync_applied ) \
	( -logic /can_pcs_tb/u_pcs_tx/sampled_polarity ) \
	( -decimal /can_pcs_tb/u_pcs_tx/phase1_extension ) \
	( -decimal /can_pcs_tb/u_pcs_tx/phase2_shortening ) \
	( -decimal /can_pcs_tb/u_pcs_tx/recessive_counter ) \
	( -logic /can_pcs_tb/u_pcs_tx/edge_detected ) \
	( -decimal /can_pcs_tb/u_pcs_tx/active_prop_seg ) \
	( -decimal /can_pcs_tb/u_pcs_tx/active_phase_seg1 ) \
	( -decimal /can_pcs_tb/u_pcs_tx/active_phase_seg2 ) \
	( -logic /can_pcs_tb/u_pcs_tx/use_data_rate ) 

wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 100000ns
wv.time.unit.auto.set
transcript $curr_transcript
