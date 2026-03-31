onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup TB \
	( -logic /can_mac_bs_tb/clk ) \
	( -logic /can_mac_bs_tb/reset )

add wave -vgroup "BS Input" \
	( -logic   /can_mac_bs_tb/bs_i/start ) \
	( -logic   /can_mac_bs_tb/bs_i/valid ) \
	( -literal /can_mac_bs_tb/bs_i/data )

add wave -vgroup "BS Output" \
	( -logic   /can_mac_bs_tb/bs_o/valid ) \
	( -literal /can_mac_bs_tb/bs_o/data ) \
	( -literal /can_mac_bs_tb/bs_o/sbc )

add wave -vgroup Dut \
	( -logic   /can_mac_bs_tb/u_dut/clk_i ) \
	( -decimal /can_mac_bs_tb/u_dut/count ) \
	( -logic /can_mac_bs_tb/u_dut/last_polarity ) \
	( -literal /can_mac_bs_tb/u_dut/stuff_count )

wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 1000ns
wv.time.unit.auto.set
transcript $curr_transcript
