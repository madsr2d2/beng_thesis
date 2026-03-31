onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup "TB Signals" \
	( -decimal /can_mac_crc_tb/crc_i ) \
	( -decimal /can_mac_crc_tb/crc_o ) \
	( -logic /can_mac_crc_tb/clk ) \
	( -logic /can_mac_crc_tb/reset ) \
	( -logic /can_mac_crc_tb/frame_rst ) \
	( -logic /can_mac_crc_tb/dut_rst ) \
	( -decimal /can_mac_crc_tb/reset_id ) \
	( -decimal /can_mac_crc_tb/crc_check_id ) \
	( -decimal /can_mac_crc_tb/output_stable_id )

add wave -vgroup "u_dut Internals" \
	( -logic /can_mac_crc_tb/u_dut/clk_i ) \
	( -logic /can_mac_crc_tb/u_dut/rst_i ) \
	( -decimal /can_mac_crc_tb/u_dut/crc_i ) \
	( -decimal /can_mac_crc_tb/u_dut/crc_o ) \
	( -literal /can_mac_crc_tb/u_dut/crc15_out ) \
	( -literal /can_mac_crc_tb/u_dut/crc17_out ) \
	( -literal /can_mac_crc_tb/u_dut/crc21_out ) \
	( -logic /can_mac_crc_tb/u_dut/valid )

add wave -vgroup u_crc15 \
	( -logic /can_mac_crc_tb/u_dut/u_crc15/clk_i ) \
	( -logic /can_mac_crc_tb/u_dut/u_crc15/reset_i ) \
	( -logic /can_mac_crc_tb/u_dut/u_crc15/start_crc_i ) \
	( -literal /can_mac_crc_tb/u_dut/u_crc15/data_i ) \
	( -logic /can_mac_crc_tb/u_dut/u_crc15/data_valid_i ) \
	( -literal /can_mac_crc_tb/u_dut/u_crc15/crc_o ) \
	( -literal /can_mac_crc_tb/u_dut/u_crc15/crc_reg )

add wave -vgroup u_crc17 \
	( -logic /can_mac_crc_tb/u_dut/u_crc17/clk_i ) \
	( -logic /can_mac_crc_tb/u_dut/u_crc17/reset_i ) \
	( -logic /can_mac_crc_tb/u_dut/u_crc17/start_crc_i ) \
	( -literal /can_mac_crc_tb/u_dut/u_crc17/data_i ) \
	( -logic /can_mac_crc_tb/u_dut/u_crc17/data_valid_i ) \
	( -literal /can_mac_crc_tb/u_dut/u_crc17/crc_o ) \
	( -literal /can_mac_crc_tb/u_dut/u_crc17/crc_reg )

add wave -vgroup u_crc21 \
	( -logic /can_mac_crc_tb/u_dut/u_crc21/clk_i ) \
	( -logic /can_mac_crc_tb/u_dut/u_crc21/reset_i ) \
	( -logic /can_mac_crc_tb/u_dut/u_crc21/start_crc_i ) \
	( -literal /can_mac_crc_tb/u_dut/u_crc21/data_i ) \
	( -logic /can_mac_crc_tb/u_dut/u_crc21/data_valid_i ) \
	( -literal /can_mac_crc_tb/u_dut/u_crc21/crc_o ) \
	( -literal /can_mac_crc_tb/u_dut/u_crc21/crc_reg )

wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 100000ns
wv.time.unit.auto.set
transcript $curr_transcript
