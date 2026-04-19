onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup "can_pcs_tb :: TB" \
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
	( -literal /can_pcs_tb/polarity_history )

add wave -vgroup "u_pcs_tx :: inputs" \
	( -logic /can_pcs_tb/u_pcs_tx/clk_i ) \
	( -logic /can_pcs_tb/u_pcs_tx/rst_i ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_i/polarity ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_i/use_data_rate ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_i/start_tdc ) \
	( -logic /can_pcs_tb/u_pcs_tx/fce_i/bus_off ) \
	( -logic /can_pcs_tb/u_pcs_tx/rx_bus_i )

add wave -vgroup "u_pcs_tx :: outputs" \
	( -logic /can_pcs_tb/u_pcs_tx/mac_o/bus_polarity ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_o/sample_point ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_o/secondary_sample_point ) \
	( -literal /can_pcs_tb/u_pcs_tx/mac_o/tdc_delay ) \
	( -logic /can_pcs_tb/u_pcs_tx/fce_o/idle_condition ) \
	( -logic /can_pcs_tb/u_pcs_tx/tx_bus_o )

add wave -vgroup "u_pcs_tx :: internals" \
	( -decimal /can_pcs_tb/u_pcs_tx/state ) \
	( -decimal /can_pcs_tb/u_pcs_tx/clk_count ) \
	( -decimal /can_pcs_tb/u_pcs_tx/tq_count ) \
	( -decimal /can_pcs_tb/u_pcs_tx/delay_count_clk ) \
	( -logic /can_pcs_tb/u_pcs_tx/tdc_counting ) \
	( -decimal /can_pcs_tb/u_pcs_tx/ssp_position ) \
	( -decimal /can_pcs_tb/u_pcs_tx/tdc_delay ) \
	( -logic /can_pcs_tb/u_pcs_tx/prev_rx_bus ) \
	( -logic /can_pcs_tb/u_pcs_tx/prev_tx_bus ) \
	( -decimal /can_pcs_tb/u_pcs_tx/ssp_delay ) \
	( -logic /can_pcs_tb/u_pcs_tx/ssp_standoff_start ) \
	( -logic /can_pcs_tb/u_pcs_tx/ssp_active ) \
	( -logic /can_pcs_tb/u_pcs_tx/tq_tick ) \
	( -logic /can_pcs_tb/u_pcs_tx/bit_boundary ) \
	( -decimal /can_pcs_tb/u_pcs_tx/active_bit_time ) \
	( -decimal /can_pcs_tb/u_pcs_tx/active_sp ) \
	( -decimal /can_pcs_tb/u_pcs_tx/recessive_counter )

add wave -vgroup "u_pcs_rx :: inputs" \
	( -logic /can_pcs_tb/u_pcs_rx/clk_i ) \
	( -logic /can_pcs_tb/u_pcs_rx/rst_i ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_i/polarity ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_i/use_data_rate ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_i/hard_sync_en ) \
	( -logic /can_pcs_tb/u_pcs_rx/fce_i/bus_off ) \
	( -logic /can_pcs_tb/u_pcs_rx/rx_bus_i )

add wave -vgroup "u_pcs_rx :: outputs" \
	( -logic /can_pcs_tb/u_pcs_rx/mac_o/bus_polarity ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_o/sample_point ) \
	( -logic /can_pcs_tb/u_pcs_rx/fce_o/idle_condition ) \
	( -logic /can_pcs_tb/u_pcs_rx/tx_bus_o )

add wave -vgroup "u_pcs_rx :: internals" \
	( -decimal /can_pcs_tb/u_pcs_rx/rate_state ) \
	( -decimal /can_pcs_tb/u_pcs_rx/segment ) \
	( -decimal /can_pcs_tb/u_pcs_rx/prescaler_count ) \
	( -logic /can_pcs_tb/u_pcs_rx/prescaler_restart ) \
	( -decimal /can_pcs_tb/u_pcs_rx/seg_count ) \
	( -logic /can_pcs_tb/u_pcs_rx/rx_bus_prev ) \
	( -logic /can_pcs_tb/u_pcs_rx/sync_inhibit ) \
	( -logic /can_pcs_tb/u_pcs_rx/sampled_polarity ) \
	( -decimal /can_pcs_tb/u_pcs_rx/phase1_extension ) \
	( -decimal /can_pcs_tb/u_pcs_rx/phase2_shortening ) \
	( -decimal /can_pcs_tb/u_pcs_rx/recessive_counter ) \
	( -logic /can_pcs_tb/u_pcs_rx/tq_tick ) \
	( -logic /can_pcs_tb/u_pcs_rx/edge_detected ) \
	( -decimal /can_pcs_tb/u_pcs_rx/active_prop_seg ) \
	( -decimal /can_pcs_tb/u_pcs_rx/active_phase_seg1 ) \
	( -decimal /can_pcs_tb/u_pcs_rx/active_phase_seg2 ) \
	( -logic /can_pcs_tb/u_pcs_rx/bit_boundary ) \
	( -logic /can_pcs_tb/u_pcs_rx/sample_point )

wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 100000ns
wv.time.unit.auto.set
transcript $curr_transcript
