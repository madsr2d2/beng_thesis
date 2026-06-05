if {![info exists run_all]} {
  do ./sim_config.tcl
}
# Simulate

asim -dbg \
     -t 0 \
     -dataset ${work_path} \
     -datasetname sim \
     -cc_all \
     -acdb \
     -acdb_cov sbt \
     -acdb_file "$work_path/$module_name.acdb" \
     -vhdlassertbreak error \
     {*}$generics \
     {*}$asim_args \
     $glbl \
     $test_bench_name 

   
#Configure toggle coverage
toggle  -rec "*" \
        -report all
        
        
if {![info exists run_all]} {
  # Wave only load if its there
  if {[file exists "$wave_path/$sim_wave_module_name" ]} {
    do $wave_path/$sim_wave_module_name
  }
}

# Run simulation
simcom

acdb save


