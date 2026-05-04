onerror { resume }
set curr_transcript [transcript]
transcript off

add wave /gen_crc_model_tb/clk_i
add wave /gen_crc_model_tb/reset_i
add wave /gen_crc_model_tb/test_start
add wave /gen_crc_model_tb/test_end
add wave /gen_crc_model_tb/gc_TbTimeOut
add wave /gen_crc_model_tb/gc_TbClkPeriod
add wave /gen_crc_model_tb/c_data_width
add wave /gen_crc_model_tb/RV
add wave -vgroup CRC-16/ARC \
	/gen_crc_model_tb/g_test_loop_16__0/start_crc_i \
	/gen_crc_model_tb/g_test_loop_16__0/data_i \
	/gen_crc_model_tb/g_test_loop_16__0/data_valid_i \
	/gen_crc_model_tb/g_test_loop_16__0/end_crc_i \
	/gen_crc_model_tb/g_test_loop_16__0/crc_o \
	/gen_crc_model_tb/g_test_loop_16__0/crc_valid_o \
	/gen_crc_model_tb/g_test_loop_16__0/test \
	/gen_crc_model_tb/g_test_loop_16__0/c_crc_poly \
	/gen_crc_model_tb/g_test_loop_16__0/c_crc_init \
	/gen_crc_model_tb/g_test_loop_16__0/c_crc_xor \
	( -literal /gen_crc_model_tb/g_test_loop_16__0/c_reverse_input ) \
	/gen_crc_model_tb/g_test_loop_16__0/c_reverse_output
add wave -vgroup CRC-16/CCITT-FALSE \
	/gen_crc_model_tb/g_test_loop_16__1/start_crc_i \
	/gen_crc_model_tb/g_test_loop_16__1/data_i \
	/gen_crc_model_tb/g_test_loop_16__1/data_valid_i \
	/gen_crc_model_tb/g_test_loop_16__1/end_crc_i \
	/gen_crc_model_tb/g_test_loop_16__1/crc_o \
	/gen_crc_model_tb/g_test_loop_16__1/crc_valid_o \
	/gen_crc_model_tb/g_test_loop_16__1/test \
	/gen_crc_model_tb/g_test_loop_16__1/c_crc_poly \
	/gen_crc_model_tb/g_test_loop_16__1/c_crc_init \
	/gen_crc_model_tb/g_test_loop_16__1/c_crc_xor \
	( -literal /gen_crc_model_tb/g_test_loop_16__1/c_reverse_input ) \
	/gen_crc_model_tb/g_test_loop_16__1/c_reverse_output
add wave -vgroup CRC-16/DNP \
	/gen_crc_model_tb/g_test_loop_16__2/start_crc_i \
	/gen_crc_model_tb/g_test_loop_16__2/data_i \
	/gen_crc_model_tb/g_test_loop_16__2/data_valid_i \
	/gen_crc_model_tb/g_test_loop_16__2/end_crc_i \
	/gen_crc_model_tb/g_test_loop_16__2/crc_o \
	/gen_crc_model_tb/g_test_loop_16__2/crc_valid_o \
	/gen_crc_model_tb/g_test_loop_16__2/test \
	/gen_crc_model_tb/g_test_loop_16__2/c_crc_poly \
	/gen_crc_model_tb/g_test_loop_16__2/c_crc_init \
	/gen_crc_model_tb/g_test_loop_16__2/c_crc_xor \
	( -literal /gen_crc_model_tb/g_test_loop_16__2/c_reverse_input ) \
	/gen_crc_model_tb/g_test_loop_16__2/c_reverse_output
add wave -expand -vgroup CRC-32 \
	/gen_crc_model_tb/g_test_loop_32__0/start_crc_i \
	/gen_crc_model_tb/g_test_loop_32__0/data_i \
	/gen_crc_model_tb/g_test_loop_32__0/data_valid_i \
	/gen_crc_model_tb/g_test_loop_32__0/end_crc_i \
	/gen_crc_model_tb/g_test_loop_32__0/crc_o \
	/gen_crc_model_tb/g_test_loop_32__0/crc_valid_o \
	/gen_crc_model_tb/g_test_loop_32__0/test \
	/gen_crc_model_tb/g_test_loop_32__0/c_crc_width \
	/gen_crc_model_tb/g_test_loop_32__0/c_crc_poly \
	/gen_crc_model_tb/g_test_loop_32__0/c_crc_init \
	/gen_crc_model_tb/g_test_loop_32__0/c_crc_xor \
	( -literal /gen_crc_model_tb/g_test_loop_32__0/c_reverse_input ) \
	/gen_crc_model_tb/g_test_loop_32__0/c_reverse_output \
	/gen_crc_model_tb/g_test_loop_32__0/u_dut/data
add wave -vgroup CRC-32/MPEG-2 \
	/gen_crc_model_tb/g_test_loop_32__1/start_crc_i \
	/gen_crc_model_tb/g_test_loop_32__1/data_i \
	/gen_crc_model_tb/g_test_loop_32__1/data_valid_i \
	/gen_crc_model_tb/g_test_loop_32__1/end_crc_i \
	/gen_crc_model_tb/g_test_loop_32__1/crc_o \
	/gen_crc_model_tb/g_test_loop_32__1/crc_valid_o \
	/gen_crc_model_tb/g_test_loop_32__1/test \
	/gen_crc_model_tb/g_test_loop_32__1/c_crc_width \
	/gen_crc_model_tb/g_test_loop_32__1/c_crc_poly \
	/gen_crc_model_tb/g_test_loop_32__1/c_crc_init \
	/gen_crc_model_tb/g_test_loop_32__1/c_crc_xor \
	( -literal /gen_crc_model_tb/g_test_loop_32__1/c_reverse_input ) \
	/gen_crc_model_tb/g_test_loop_32__1/c_reverse_output \
	/gen_crc_model_tb/g_test_loop_32__1/u_dut/data
wv.cursors.add -time 210ns+0 -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 80230ps -to 216830ps
wv.time.unit.auto.set
transcript $curr_transcript
