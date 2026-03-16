# Waveform save to .../test_case/sim_wave_{module}.tcl

# Info on terminal
puts "Waveform save to $wave_path/$sim_wave_module_name"

# Waveform file current delete
file delete $wave_path/$sim_wave_module_name

# Waveform file save
wv.savetomacro $wave_path/$sim_wave_module_name

# EOF
