# Full execute script used for automatic testing
set run_all 1

# Get configuration variables
do ./sim_config.tcl

# Execute pre scripts
do ./sim_pre_scripts.tcl

# Compile all the files
if {[catch {do ./sim_com_osvvm.tcl} fid]} {
  quit
}
if {[catch {do ./sim_link_tool_libs.tcl} fid]} {
  quit
}
if {[catch {do ./sim_com.tcl} fid]} {
  quit
} 
# Execute the simulation
if {[catch {do ./sim_run.tcl} fid]} {
  quit
}
#Close toggle coverage file
acdb off

# close simulation
endsim

quit
