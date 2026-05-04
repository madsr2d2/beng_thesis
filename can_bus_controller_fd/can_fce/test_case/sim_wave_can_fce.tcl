onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup TB \
	( -logic /can_fce_tb/clk ) \
	( -logic /can_fce_tb/reset ) 
add wave -vgroup Dut \
	( -logic /can_fce_tb/u_dut/clk)
wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 100000ns
wv.time.unit.auto.set
transcript $curr_transcript
