onerror { resume }
set curr_transcript [transcript]
transcript off

add wave /gen_crc_tb/clk_i
add wave /gen_crc_tb/reset_i
add wave /gen_crc_tb/test_start
add wave /gen_crc_tb/test_end
add wave /gen_crc_tb/gc_TbTimeOut
add wave /gen_crc_tb/gc_TbClkPeriod
add wave /gen_crc_tb/c_data_width
add wave /gen_crc_tb/RV
add wave -vgroup CRC-16/ARC \
	/gen_crc_tb/g_test_loop_16__0/start_crc_i \
	/gen_crc_tb/g_test_loop_16__0/data_i \
	/gen_crc_tb/g_test_loop_16__0/data_valid_i \
	/gen_crc_tb/g_test_loop_16__0/crc_o \
	/gen_crc_tb/g_test_loop_16__0/crc_ref \
	/gen_crc_tb/g_test_loop_16__0/test \
	/gen_crc_tb/g_test_loop_16__0/c_crc_poly \
	/gen_crc_tb/g_test_loop_16__0/c_crc_init \
	/gen_crc_tb/g_test_loop_16__0/c_crc_xor \
	( -literal /gen_crc_tb/g_test_loop_16__0/c_reverse_input ) \
	/gen_crc_tb/g_test_loop_16__0/c_reverse_output
add wave -vgroup CRC-16/CCITT-FALSE \
	/gen_crc_tb/g_test_loop_16__1/start_crc_i \
	/gen_crc_tb/g_test_loop_16__1/data_i \
	/gen_crc_tb/g_test_loop_16__1/data_valid_i \
	/gen_crc_tb/g_test_loop_16__1/crc_o \
	/gen_crc_tb/g_test_loop_16__1/crc_ref \
	/gen_crc_tb/g_test_loop_16__1/test \
	/gen_crc_tb/g_test_loop_16__1/c_crc_poly \
	/gen_crc_tb/g_test_loop_16__1/c_crc_init \
	/gen_crc_tb/g_test_loop_16__1/c_crc_xor \
	( -literal /gen_crc_tb/g_test_loop_16__1/c_reverse_input ) \
	/gen_crc_tb/g_test_loop_16__1/c_reverse_output
add wave -vgroup CRC-16/DNP \
	/gen_crc_tb/g_test_loop_16__2/start_crc_i \
	/gen_crc_tb/g_test_loop_16__2/data_i \
	/gen_crc_tb/g_test_loop_16__2/data_valid_i \
	/gen_crc_tb/g_test_loop_16__2/crc_o \
	/gen_crc_tb/g_test_loop_16__2/crc_ref \
	/gen_crc_tb/g_test_loop_16__2/test \
	/gen_crc_tb/g_test_loop_16__2/c_crc_poly \
	/gen_crc_tb/g_test_loop_16__2/c_crc_init \
	/gen_crc_tb/g_test_loop_16__2/c_crc_xor \
	( -literal /gen_crc_tb/g_test_loop_16__2/c_reverse_input ) \
	/gen_crc_tb/g_test_loop_16__2/c_reverse_output
add wave -vgroup CRC-32 \
	/gen_crc_tb/g_test_loop_32__0/start_crc_i \
	/gen_crc_tb/g_test_loop_32__0/data_i \
	/gen_crc_tb/g_test_loop_32__0/data_valid_i \
	/gen_crc_tb/g_test_loop_32__0/crc_o \
	/gen_crc_tb/g_test_loop_32__0/crc_ref \
	/gen_crc_tb/g_test_loop_32__0/test \
	/gen_crc_tb/g_test_loop_32__0/c_crc_width \
	/gen_crc_tb/g_test_loop_32__0/c_crc_poly \
	/gen_crc_tb/g_test_loop_32__0/c_crc_init \
	/gen_crc_tb/g_test_loop_32__0/c_crc_xor \
	( -literal /gen_crc_tb/g_test_loop_32__0/c_reverse_input ) \
	/gen_crc_tb/g_test_loop_32__0/c_reverse_output \
	/gen_crc_tb/g_test_loop_32__0/u_dut/data
add wave -vgroup CRC-32/MPEG-2 \
	/gen_crc_tb/g_test_loop_32__1/start_crc_i \
	/gen_crc_tb/g_test_loop_32__1/data_i \
	/gen_crc_tb/g_test_loop_32__1/data_valid_i \
	/gen_crc_tb/g_test_loop_32__1/crc_o \
	/gen_crc_tb/g_test_loop_32__1/crc_ref \
	/gen_crc_tb/g_test_loop_32__1/test \
	/gen_crc_tb/g_test_loop_32__1/c_crc_width \
	/gen_crc_tb/g_test_loop_32__1/c_crc_poly \
	/gen_crc_tb/g_test_loop_32__1/c_crc_init \
	/gen_crc_tb/g_test_loop_32__1/c_crc_xor \
	( -literal /gen_crc_tb/g_test_loop_32__1/c_reverse_input ) \
	/gen_crc_tb/g_test_loop_32__1/c_reverse_output \
	/gen_crc_tb/g_test_loop_32__1/u_dut/data
add wave -expand -vgroup {15 bit} \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/clk_i \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/reset_i \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/start_crc_i \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/data_i \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/data_valid_i \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/crc_o \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/crc \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/crc_r \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/data \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/gc_data_width \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/gc_crc_width \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/gc_crc_poly \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/gc_xor_value \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/gc_crc_init \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/gc_ref_input \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/gc_ref_output \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/c_crc_poly \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/c_xor_value \
	/gen_crc_tb/g_data_width__15/g_test_loop_32bit_crc_8_bit_data__0/u_dut/c_crc_init
wv.cursors.add -time 36655ns+0 -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0fs -to 38487750ps
wv.time.unit.auto.set
transcript $curr_transcript
