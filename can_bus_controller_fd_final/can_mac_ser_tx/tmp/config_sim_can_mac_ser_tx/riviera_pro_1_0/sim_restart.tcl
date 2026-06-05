if {![info exists run_all]} {
  do ./sim_config.tcl
}

restart
acdb clear

# Run simulation
simcom

acdb save
