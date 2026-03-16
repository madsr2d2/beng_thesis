onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -vgroup TB \
	( -logic /can_mac_crc_tx_tb/clk ) \
	( -logic /can_mac_crc_tx_tb/reset )

add wave -vgroup "CRC Input" \
	( -literal /can_mac_crc_tx_tb/crc_i/crc_poly_select ) \
	( -logic   /can_mac_crc_tx_tb/crc_i/start ) \
	( -logic   /can_mac_crc_tx_tb/crc_i/valid ) \
	( -logic   /can_mac_crc_tx_tb/crc_i/data )

add wave -vgroup "CRC Output" \
	( -literal /can_mac_crc_tx_tb/crc_o/crc )

add wave -vgroup Dut \
	( -logic   /can_mac_crc_tx_tb/u_dut/clk_i ) \
	( -logic   /can_mac_crc_tx_tb/u_dut/sel_crc15 ) \
	( -logic   /can_mac_crc_tx_tb/u_dut/sel_crc17 ) \
	( -logic   /can_mac_crc_tx_tb/u_dut/sel_crc21 ) \
	( -logic   /can_mac_crc_tx_tb/u_dut/start_sl ) \
	( -logic   /can_mac_crc_tx_tb/u_dut/valid_sl ) \
	( -literal /can_mac_crc_tx_tb/u_dut/crc15_out ) \
	( -literal /can_mac_crc_tx_tb/u_dut/crc17_out ) \
	( -literal /can_mac_crc_tx_tb/u_dut/crc21_out )

wv.cursors.add -time 0ns -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0ns -to 1000ns
wv.time.unit.auto.set
transcript $curr_transcript
