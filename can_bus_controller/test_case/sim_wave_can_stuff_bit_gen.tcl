onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -expand -vgroup TB \
	/can_stuff_bit_gen_tb/test_id \
	/can_stuff_bit_gen_tb/reset_id \
	/can_stuff_bit_gen_tb/clk \
	/can_stuff_bit_gen_tb/reset \
	/can_stuff_bit_gen_tb/stuff_bit \
	/can_stuff_bit_gen_tb/valid \
	/can_stuff_bit_gen_tb/rx \
	/can_stuff_bit_gen_tb/sample_rx \
	/can_stuff_bit_gen_tb/transmit \
	/can_stuff_bit_gen_tb/gc_TbTimeOut \
	/can_stuff_bit_gen_tb/gc_TbClkPeriod \
	/can_stuff_bit_gen_tb/gc_bit_string_length \
	/can_stuff_bit_gen_tb/RV \
	( -vgroup Tester \
		( -bin /can_stuff_bit_gen_tb/p_main_tester/v_bit_string ) \
		( -bin /can_stuff_bit_gen_tb/p_main_tester/v_stuff_mask ) \
		( -bin /can_stuff_bit_gen_tb/p_main_tester/v_stuff_bit_array ) \
		/can_stuff_bit_gen_tb/p_main_tester/v_stuff_bit \
	)
add wave -expand -vgroup Dut \
	/can_stuff_bit_gen_tb/u_can_stuff_bit_gen_dut/clk_i \
	/can_stuff_bit_gen_tb/u_can_stuff_bit_gen_dut/reset_i \
	/can_stuff_bit_gen_tb/u_can_stuff_bit_gen_dut/rx_i \
	/can_stuff_bit_gen_tb/u_can_stuff_bit_gen_dut/sample_rx_i \
	/can_stuff_bit_gen_tb/u_can_stuff_bit_gen_dut/stuff_bit_o \
	/can_stuff_bit_gen_tb/u_can_stuff_bit_gen_dut/stuff_bit_valid_o \
	/can_stuff_bit_gen_tb/u_can_stuff_bit_gen_dut/rx_prev \
	/can_stuff_bit_gen_tb/u_can_stuff_bit_gen_dut/count \
	/can_stuff_bit_gen_tb/u_can_stuff_bit_gen_dut/c_max_consecutive_identical_bits
add wave -expand -vgroup {Node Clock} \
	/can_stuff_bit_gen_tb/u_can_node_clock/clk_i \
	/can_stuff_bit_gen_tb/u_can_node_clock/reset_i \
	/can_stuff_bit_gen_tb/u_can_node_clock/rx_i \
	/can_stuff_bit_gen_tb/u_can_node_clock/sample_rx_o \
	/can_stuff_bit_gen_tb/u_can_node_clock/transmit_o \
	/can_stuff_bit_gen_tb/u_can_node_clock/dbg_enable_resync_i \
	/can_stuff_bit_gen_tb/u_can_node_clock/edge_detected \
	/can_stuff_bit_gen_tb/u_can_node_clock/time_quantum_count \
	/can_stuff_bit_gen_tb/u_can_node_clock/phase_seg1_length \
	/can_stuff_bit_gen_tb/u_can_node_clock/phase_seg2_length \
	/can_stuff_bit_gen_tb/u_can_node_clock/clk_div_counter \
	/can_stuff_bit_gen_tb/u_can_node_clock/rx_prev \
	/can_stuff_bit_gen_tb/u_can_node_clock/sample_point \
	/can_stuff_bit_gen_tb/u_can_node_clock/next_sample_point \
	/can_stuff_bit_gen_tb/u_can_node_clock/end_of_bit_time \
	/can_stuff_bit_gen_tb/u_can_node_clock/next_end_of_bit_time \
	/can_stuff_bit_gen_tb/u_can_node_clock/resync_enable \
	/can_stuff_bit_gen_tb/u_can_node_clock/sof_is_next \
	/can_stuff_bit_gen_tb/u_can_node_clock/gc_bit_rate_hz \
	/can_stuff_bit_gen_tb/u_can_node_clock/c_bit_period \
	/can_stuff_bit_gen_tb/u_can_node_clock/c_bit_quanta \
	/can_stuff_bit_gen_tb/u_can_node_clock/c_bit_quanta_cycles
wv.cursors.add -time 19905575ns+0 -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 8061723838ps -to 20528935588ps
wv.time.unit.auto.set
transcript $curr_transcript
