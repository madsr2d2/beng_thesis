# Waveform load from .../test_case/sim_wave_{module}.tcl

# Info on terminal
puts "Waveform load from $wave_path/$sim_wave_module_name"

# Waveforms all current remove
wv.signals.selectall
wv.signals.remove

# Waveforms load from file
source $wave_path/$sim_wave_module_name

# EOF
