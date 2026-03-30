# Get configuration variables
if {![info exists run_all]} {
  framework.documents.closeall -vhdl
  clear
  if {![info exists run_first]  || $run_first} {
    transcript off
    set run_first 0
    do ./sim_config.tcl
    if {[catch {do ./sim_pre_scripts.tcl} fid]} {
      quit
    }
    # Todo this can cause a conflict with tools lib if both is used.
    # Remove the osvvm files from the config file if using the tools lib linker
    if {[catch {do ./sim_com_osvvm.tcl} fid]} {
      quit
    }
    if {[catch {do ./sim_link_tool_libs.tcl} fid]} {
      quit
    }
  }
}

if {[llength $core_files]} {
    dict for {library file_list} $core_files {
        if {![file exist ${work_path}/lib_$library/$library.lib]} {
            alib $library ${work_path}/lib_$library/$library.lib
        }
        dict for {file_t flist} $file_list {
            if {$file_t == "vhdl"} {
                acom -incr -o -2008 -d $work_path -dbg {*}$acom_args -work $library  {*}$flist
            } elseif {$file_t == "verilog"} {
                alog -incr -sv2k5 -o $work_path -dbg {*}$alog_args -work $library {*}$flist
            }
        }
    }
}

# Set the working library as the last one which should be the testbench library
set worklib [lindex $libraries end]
