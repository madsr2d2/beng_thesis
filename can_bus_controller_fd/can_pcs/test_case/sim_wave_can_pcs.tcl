onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup "can_pcs_tb :: TB" \
	( -decimal /can_pcs_tb/res_bit_index ) \
	( -decimal /can_pcs_tb/frames_to_send ) \
	( -decimal /can_pcs_tb/crc_delimiter_index ) \
	( -logic /can_pcs_tb/tx_clock_is_leading ) \
	( -logic /can_pcs_tb/clk_tx ) \
	( -logic /can_pcs_tb/clk_rx ) \
	( -logic /can_pcs_tb/reset ) \
	( -logic /can_pcs_tb/tx_from_tx_dut ) \
	( -logic /can_pcs_tb/tx_from_rx_dut ) \
	( -logic /can_pcs_tb/rx_at_rx_dut ) \
	( -logic /can_pcs_tb/rx_at_tx_dut ) \
	( -logic /can_pcs_tb/tx_mac_i/tx_data ) \
	( -logic /can_pcs_tb/tx_mac_i/next_bit_is_res ) \
	( -logic /can_pcs_tb/tx_mac_i/next_bit_is_brs ) \
	( -logic /can_pcs_tb/tx_mac_i/data_phase_stop ) \
	( -logic /can_pcs_tb/tx_mac_i/do_hard_sync ) \
	( -logic /can_pcs_tb/tx_mac_i/transmitting ) \
	( -logic /can_pcs_tb/tx_mac_o/rx_data ) \
	( -logic /can_pcs_tb/tx_mac_o/sample_point ) \
	( -logic /can_pcs_tb/tx_mac_o/secondary_sample_point ) \
	( -literal /can_pcs_tb/tx_mac_o/tdc_delay ) \
	( -logic /can_pcs_tb/tx_fce_i/bus_off ) \
	( -logic /can_pcs_tb/tx_fce_o/idle_condition ) \
	( -logic /can_pcs_tb/rx_mac_i/tx_data ) \
	( -logic /can_pcs_tb/rx_mac_i/next_bit_is_res ) \
	( -logic /can_pcs_tb/rx_mac_i/next_bit_is_brs ) \
	( -logic /can_pcs_tb/rx_mac_i/data_phase_stop ) \
	( -logic /can_pcs_tb/rx_mac_i/do_hard_sync ) \
	( -logic /can_pcs_tb/rx_mac_i/transmitting ) \
	( -logic /can_pcs_tb/rx_mac_o/rx_data ) \
	( -logic /can_pcs_tb/rx_mac_o/sample_point ) \
	( -logic /can_pcs_tb/rx_mac_o/secondary_sample_point ) \
	( -literal /can_pcs_tb/rx_mac_o/tdc_delay ) \
	( -logic /can_pcs_tb/rx_fce_i/bus_off ) \
	( -logic /can_pcs_tb/rx_fce_o/idle_condition ) \
	( -decimal /can_pcs_tb/test_id ) \
	( -decimal /can_pcs_tb/check_id ) \
	( -logic /can_pcs_tb/init_barrier ) \
	( -literal /can_pcs_tb/polarity_history ) \
	( -logic /can_pcs_tb/tx_on_bus_at_tx ) \
	( -logic /can_pcs_tb/tx_on_bus_at_rx ) \
	( -logic /can_pcs_tb/rx_on_bus_at_rx ) \
	( -logic /can_pcs_tb/rx_on_bus_at_tx ) \
	( -logic /can_pcs_tb/bus_at_tx ) \
	( -logic /can_pcs_tb/bus_at_rx ) \
	( -logic /can_pcs_tb/bus_level )

add wave -vgroup "u_pcs_tx :: inputs" \
	( -logic /can_pcs_tb/u_pcs_tx/clk_i ) \
	( -logic /can_pcs_tb/u_pcs_tx/rst_i ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_i/tx_data ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_i/next_bit_is_res ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_i/next_bit_is_brs ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_i/data_phase_stop ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_i/do_hard_sync ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_i/transmitting ) \
	( -logic /can_pcs_tb/u_pcs_tx/fce_i/bus_off ) \
	( -logic /can_pcs_tb/u_pcs_tx/rx_i )

add wave -vgroup "u_pcs_tx :: outputs" \
	( -logic /can_pcs_tb/u_pcs_tx/mac_o/rx_data ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_o/sample_point ) \
	( -logic /can_pcs_tb/u_pcs_tx/mac_o/secondary_sample_point ) \
	( -literal /can_pcs_tb/u_pcs_tx/mac_o/tdc_delay ) \
	( -logic /can_pcs_tb/u_pcs_tx/fce_o/idle_condition ) \
	( -logic /can_pcs_tb/u_pcs_tx/tx_o )

add wave -vgroup "u_pcs_tx :: internals" \
	( -decimal /can_pcs_tb/u_pcs_tx/segment ) \
	( -decimal /can_pcs_tb/u_pcs_tx/clk_count ) \
	( -decimal /can_pcs_tb/u_pcs_tx/seg_count ) \
	( -logic /can_pcs_tb/u_pcs_tx/rx_bus_prev ) \
	( -logic /can_pcs_tb/u_pcs_tx/sync_applied ) \
	( -decimal /can_pcs_tb/u_pcs_tx/phase1_extension ) \
	( -decimal /can_pcs_tb/u_pcs_tx/phase2_shortening ) \
	( -decimal /can_pcs_tb/u_pcs_tx/recessive_counter ) \
	( -decimal /can_pcs_tb/u_pcs_tx/active_prop_seg ) \
	( -decimal /can_pcs_tb/u_pcs_tx/active_phase_seg1 ) \
	( -decimal /can_pcs_tb/u_pcs_tx/active_phase_seg2 ) \
	( -decimal /can_pcs_tb/u_pcs_tx/active_sjw ) \
	( -logic /can_pcs_tb/u_pcs_tx/tdc_count_active ) \
	( -decimal /can_pcs_tb/u_pcs_tx/delay_count_tq ) \
	( -logic /can_pcs_tb/u_pcs_tx/ssp_active ) \
	( -logic /can_pcs_tb/u_pcs_tx/ssp_seen ) \
	( -decimal /can_pcs_tb/u_pcs_tx/tdc_delay ) \
	( -logic /can_pcs_tb/u_pcs_tx/bit_boundary ) \
	( -logic /can_pcs_tb/u_pcs_tx/ssp_standoff_active ) \
	( -logic /can_pcs_tb/u_pcs_tx/first_data_bit_boundary_seen ) \
	( -logic /can_pcs_tb/u_pcs_tx/data_phase_active )

add wave -vgroup "u_pcs_rx :: inputs" \
	( -logic /can_pcs_tb/u_pcs_rx/clk_i ) \
	( -logic /can_pcs_tb/u_pcs_rx/rst_i ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_i/tx_data ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_i/next_bit_is_res ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_i/next_bit_is_brs ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_i/data_phase_stop ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_i/do_hard_sync ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_i/transmitting ) \
	( -logic /can_pcs_tb/u_pcs_rx/fce_i/bus_off ) \
	( -logic /can_pcs_tb/u_pcs_rx/rx_i )

add wave -vgroup "u_pcs_rx :: outputs" \
	( -logic /can_pcs_tb/u_pcs_rx/mac_o/rx_data ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_o/sample_point ) \
	( -logic /can_pcs_tb/u_pcs_rx/mac_o/secondary_sample_point ) \
	( -literal /can_pcs_tb/u_pcs_rx/mac_o/tdc_delay ) \
	( -logic /can_pcs_tb/u_pcs_rx/fce_o/idle_condition ) \
	( -logic /can_pcs_tb/u_pcs_rx/tx_o )

add wave -vgroup "u_pcs_rx :: internals" \
	( -decimal /can_pcs_tb/u_pcs_rx/segment ) \
	( -decimal /can_pcs_tb/u_pcs_rx/clk_count ) \
	( -decimal /can_pcs_tb/u_pcs_rx/seg_count ) \
	( -logic /can_pcs_tb/u_pcs_rx/rx_bus_prev ) \
	( -logic /can_pcs_tb/u_pcs_rx/sync_applied ) \
	( -decimal /can_pcs_tb/u_pcs_rx/phase1_extension ) \
	( -decimal /can_pcs_tb/u_pcs_rx/phase2_shortening ) \
	( -decimal /can_pcs_tb/u_pcs_rx/recessive_counter ) \
	( -decimal /can_pcs_tb/u_pcs_rx/active_prop_seg ) \
	( -decimal /can_pcs_tb/u_pcs_rx/active_phase_seg1 ) \
	( -decimal /can_pcs_tb/u_pcs_rx/active_phase_seg2 ) \
	( -decimal /can_pcs_tb/u_pcs_rx/active_sjw ) \
	( -logic /can_pcs_tb/u_pcs_rx/tdc_count_active ) \
	( -decimal /can_pcs_tb/u_pcs_rx/delay_count_tq ) \
	( -logic /can_pcs_tb/u_pcs_rx/ssp_active ) \
	( -logic /can_pcs_tb/u_pcs_rx/ssp_seen ) \
	( -decimal /can_pcs_tb/u_pcs_rx/tdc_delay ) \
	( -logic /can_pcs_tb/u_pcs_rx/bit_boundary ) \
	( -logic /can_pcs_tb/u_pcs_rx/ssp_standoff_active ) \
	( -logic /can_pcs_tb/u_pcs_rx/first_data_bit_boundary_seen ) \
	( -logic /can_pcs_tb/u_pcs_rx/data_phase_active )

wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 100000ns
wv.time.unit.auto.set
transcript $curr_transcript
