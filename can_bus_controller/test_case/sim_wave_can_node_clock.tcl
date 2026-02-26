onerror { resume }
set curr_transcript [transcript]
transcript off

add wave -expand -vgroup TB \
	/can_node_clock_tb/clk \
	/can_node_clock_tb/reset \
	/can_node_clock_tb/bit_clk \
	/can_node_clock_tb/rx \
	/can_node_clock_tb/rx_sync \
	/can_node_clock_tb/sample_rx \
	/can_node_clock_tb/transmit \
	/can_node_clock_tb/frame_req \
	/can_node_clock_tb/frame_ack \
	/can_node_clock_tb/send_worst \
	( -vgroup constants \
		/can_node_clock_tb/test_id \
		/can_node_clock_tb/reset_id \
		/can_node_clock_tb/source_id \
		/can_node_clock_tb/gc_TbTimeOut \
		/can_node_clock_tb/gc_TbClkPeriod \
		/can_node_clock_tb/gc_bit_rate_hz \
		/can_node_clock_tb/gc_bin_size \
		/can_node_clock_tb/gc_frames_to_send \
		/can_node_clock_tb/c_tb_seg1 \
		/can_node_clock_tb/c_tb_seg2 \
		/can_node_clock_tb/c_tb_prop_seg \
		/can_node_clock_tb/c_min_mac_frame_length \
		/can_node_clock_tb/c_max_mac_frame_length \
		/can_node_clock_tb/c_nominal_bit_time \
		/can_node_clock_tb/c_min_rx_sample_point \
		/can_node_clock_tb/c_max_rx_sample_point \
		/can_node_clock_tb/c_clock_delta_1 \
		/can_node_clock_tb/c_clock_delta_2 \
		/can_node_clock_tb/c_clock_delta \
		/can_node_clock_tb/c_max_clock_delta \
		/can_node_clock_tb/RV \
	) \
	/can_node_clock_tb/v_bit_time \
	( -vgroup Source \
		/can_node_clock_tb/p_bit_source/v_frame_length \
		/can_node_clock_tb/p_bit_source/v_delta_frequency \
		/can_node_clock_tb/p_bit_source/v_last_bits \
	) \
	( -vgroup Tester \
		/can_node_clock_tb/p_main_tester/v_start_time \
		/can_node_clock_tb/p_main_tester/v_time_to_sample \
	)
add wave -expand -vgroup Dut \
	/can_node_clock_tb/u_dut/clk_i \
	/can_node_clock_tb/u_dut/reset_i \
	/can_node_clock_tb/u_dut/rx_i \
	/can_node_clock_tb/u_dut/sample_rx_o \
	/can_node_clock_tb/u_dut/transmit_o \
	/can_node_clock_tb/u_dut/segment \
	/can_node_clock_tb/u_dut/time_quantum_count \
	/can_node_clock_tb/u_dut/phase_seg1_length \
	/can_node_clock_tb/u_dut/phase_seg2_length \
	/can_node_clock_tb/u_dut/clk_div_counter \
	/can_node_clock_tb/u_dut/rx_prev \
	/can_node_clock_tb/u_dut/gc_bit_rate_hz \
	/can_node_clock_tb/u_dut/gc_default_prop_seg_length \
	/can_node_clock_tb/u_dut/gc_default_phase_seg_1_length \
	/can_node_clock_tb/u_dut/gc_default_phase_seg_2_length \
	/can_node_clock_tb/u_dut/gc_sync_jump_width \
	/can_node_clock_tb/u_dut/c_nominal_time_quanta_per_bit \
	/can_node_clock_tb/u_dut/c_bit_period \
	/can_node_clock_tb/u_dut/c_bit_quanta \
	/can_node_clock_tb/u_dut/c_bit_quanta_cycles \
	( -vgroup Resync \
		/can_node_clock_tb/u_dut/p_rx_sample_pulse_gen/v_phase_error \
		/can_node_clock_tb/u_dut/p_rx_sample_pulse_gen/v_phase_seg1_length \
		/can_node_clock_tb/u_dut/p_rx_sample_pulse_gen/v_phase_seg2_length \
	)
wv.cursors.add -time 160827870ns+0 -name {Default cursor}
wv.cursors.setactive -name {Default cursor}
wv.cursors.subcursor.add -time 236277905ns -name {Cursor 1}
wv.cursors.setactive -name {Default cursor}
wv.zoom.range -from 0fs -to 370278403838ps
wv.time.unit.auto.set
transcript $curr_transcript
