

# Clock constraints; nominel freq. is 100 MHz, but uses 125 MHz to overconstrain
create_clock -name "clk" -period 6.000ns [get_ports {clk_i}]

# Automatically constrain PLL and other generated clocks
derive_pll_clocks -create_base_clocks

# Automatically calculate clock uncertainty to jitter and other effects.
derive_clock_uncertainty

# tsu/th constraints
set_input_delay -clock clk 2.0 [get_ports {reset_i}]
set_input_delay -clock clk 2.0 [get_ports {start_crc_i}]
set_input_delay -clock clk 2.0 [get_ports {data_i}]
set_input_delay -clock clk 2.0 [get_ports {data_valid_i}]

# tpd constraints
set_output_delay -clock clk 2.0 [get_ports {crc_o}]

# EOF
