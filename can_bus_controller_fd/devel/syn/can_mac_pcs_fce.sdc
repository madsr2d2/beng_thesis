
# Clock constraint; nominal CAN bit clock is much slower but 6 ns (166 MHz)
# overconstrains the design to find the worst-case timing paths.
create_clock -name "clk" -period 6.000ns [get_ports {clk_i}]

# Automatically constrain PLL and other generated clocks
derive_pll_clocks -create_base_clocks

# Automatically calculate clock uncertainty to jitter and other effects.
derive_clock_uncertainty

# tsu/th constraints
set_input_delay -clock clk 2.0 [get_ports {reset_i}]
set_input_delay -clock clk 2.0 [get_ports {tx_llc_valid_i}]
set_input_delay -clock clk 2.0 [get_ports {tx_llc_sop_i}]
set_input_delay -clock clk 2.0 [get_ports {tx_llc_eop_i}]
set_input_delay -clock clk 2.0 [get_ports {tx_llc_data_i[*]}]
set_input_delay -clock clk 2.0 [get_ports {rx_llc_ready_i}]
set_input_delay -clock clk 2.0 [get_ports {fce_normal_mode_i}]
set_input_delay -clock clk 2.0 [get_ports {rx_i}]

# tpd constraints
set_output_delay -clock clk 2.0 [get_ports {tx_llc_ready_o}]
set_output_delay -clock clk 2.0 [get_ports {tx_llc_status_o[*]}]
set_output_delay -clock clk 2.0 [get_ports {rx_llc_valid_o}]
set_output_delay -clock clk 2.0 [get_ports {rx_llc_sop_o}]
set_output_delay -clock clk 2.0 [get_ports {rx_llc_eop_o}]
set_output_delay -clock clk 2.0 [get_ports {rx_llc_data_o[*]}]
set_output_delay -clock clk 2.0 [get_ports {fce_bus_off_o}]
set_output_delay -clock clk 2.0 [get_ports {tx_o}]

# EOF
