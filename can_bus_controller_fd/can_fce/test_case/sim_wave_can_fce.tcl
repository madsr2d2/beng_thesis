onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup "can_fce_tb :: TB" \
	( -logic /can_fce_tb/clk ) \
	( -logic /can_fce_tb/reset ) \
	( -logic /can_fce_tb/llc_i/normal_mode_request ) \
	( -logic /can_fce_tb/llc_o/normal_mode_response ) \
	( -logic /can_fce_tb/llc_o/bus_off ) \
	( -logic /can_fce_tb/mac_i/transmitting ) \
	( -logic /can_fce_tb/mac_i/error ) \
	( -logic /can_fce_tb/mac_i/primary_error ) \
	( -logic /can_fce_tb/mac_i/sending_error_overload_flag ) \
	( -logic /can_fce_tb/mac_i/counters_unchanged ) \
	( -logic /can_fce_tb/mac_i/error_delimiter_too_late ) \
	( -logic /can_fce_tb/mac_i/successful_transfer ) \
	( -logic /can_fce_tb/mac_i/error_passive_response ) \
	( -logic /can_fce_tb/mac_i/error_active_response ) \
	( -logic /can_fce_tb/mac_o/error_passive_request ) \
	( -logic /can_fce_tb/mac_o/error_active_request ) \
	( -logic /can_fce_tb/pcs_i/bus_off_response ) \
	( -logic /can_fce_tb/pcs_i/bus_off_release_response ) \
	( -logic /can_fce_tb/pcs_i/idle_condition ) \
	( -logic /can_fce_tb/pcs_o/bus_off_request ) \
	( -logic /can_fce_tb/pcs_o/bus_off_release_request ) \
	( -decimal /can_fce_tb/test_id ) \
	( -logic /can_fce_tb/init_barrier )

add wave -vgroup "u_dut :: inputs" \
	( -logic /can_fce_tb/u_dut/clk_i ) \
	( -logic /can_fce_tb/u_dut/rst_i ) \
	( -logic /can_fce_tb/u_dut/llc_i/normal_mode_request ) \
	( -logic /can_fce_tb/u_dut/mac_i/transmitting ) \
	( -logic /can_fce_tb/u_dut/mac_i/error ) \
	( -logic /can_fce_tb/u_dut/mac_i/primary_error ) \
	( -logic /can_fce_tb/u_dut/mac_i/sending_error_overload_flag ) \
	( -logic /can_fce_tb/u_dut/mac_i/counters_unchanged ) \
	( -logic /can_fce_tb/u_dut/mac_i/error_delimiter_too_late ) \
	( -logic /can_fce_tb/u_dut/mac_i/successful_transfer ) \
	( -logic /can_fce_tb/u_dut/mac_i/error_passive_response ) \
	( -logic /can_fce_tb/u_dut/mac_i/error_active_response ) \
	( -logic /can_fce_tb/u_dut/pcs_i/bus_off_response ) \
	( -logic /can_fce_tb/u_dut/pcs_i/bus_off_release_response ) \
	( -logic /can_fce_tb/u_dut/pcs_i/idle_condition )

add wave -vgroup "u_dut :: outputs" \
	( -logic /can_fce_tb/u_dut/llc_o/normal_mode_response ) \
	( -logic /can_fce_tb/u_dut/llc_o/bus_off ) \
	( -logic /can_fce_tb/u_dut/mac_o/error_passive_request ) \
	( -logic /can_fce_tb/u_dut/mac_o/error_active_request ) \
	( -logic /can_fce_tb/u_dut/pcs_o/bus_off_request ) \
	( -logic /can_fce_tb/u_dut/pcs_o/bus_off_release_request ) \
	( -decimal /can_fce_tb/u_dut/debug_tec_o ) \
	( -decimal /can_fce_tb/u_dut/debug_rec_o )

add wave -vgroup "u_dut :: internals" \
	( -decimal /can_fce_tb/u_dut/tec ) \
	( -decimal /can_fce_tb/u_dut/rec ) \
	( -decimal /can_fce_tb/u_dut/fce_state ) \
	( -decimal /can_fce_tb/u_dut/idle_count )

wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 100000ns
wv.time.unit.auto.set
transcript $curr_transcript
