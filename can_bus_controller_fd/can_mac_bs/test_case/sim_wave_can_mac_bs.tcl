onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup "TB Signals" \
	( -logic /can_mac_bs_tb/clk_i ) \
	( -logic /can_mac_bs_tb/rst_i ) \
	( -logic /can_mac_bs_tb/frame_rst ) \
	( -decimal /can_mac_bs_tb/bs_i ) \
	( -decimal /can_mac_bs_tb/bs_o ) \
	( -decimal /can_mac_bs_tb/test_done )

add wave -vgroup "u_dut Internals" \
	( -logic /can_mac_bs_tb/u_dut/clk_i ) \
	( -logic /can_mac_bs_tb/u_dut/rst_i ) \
	( -decimal /can_mac_bs_tb/u_dut/bs_i ) \
	( -decimal /can_mac_bs_tb/u_dut/bs_o ) \
	( -decimal /can_mac_bs_tb/u_dut/count ) \
	( -logic /can_mac_bs_tb/u_dut/last_polarity ) \
	( -literal /can_mac_bs_tb/u_dut/stuff_count ) \
	( -logic /can_mac_bs_tb/u_dut/stuff_pending )

wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 100000ns
wv.time.unit.auto.set
transcript $curr_transcript
