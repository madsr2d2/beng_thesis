if {[llength $osvvm_files]} {
    dict for {library file_list} $osvvm_files {
        if {![file exist ${work_path}/lib_$library/$library.lib]} {
            alib $library ${work_path}/lib_$library/$library.lib
        }
        try {
            acom -incr -o -2008 -d $work_path -dbg {*}$acom_args -work $library  {*}$file_list
        } on error errmsg {
            puts "Error: $errmsg"
            return 1
        }
    }
}