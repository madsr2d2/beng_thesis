# Get configuration variables
do ./sim_config.tcl
$python_string_app $python_string_name {*}$python_string_args
# Update the files list
do ./sim_config.tcl
set run_first 1