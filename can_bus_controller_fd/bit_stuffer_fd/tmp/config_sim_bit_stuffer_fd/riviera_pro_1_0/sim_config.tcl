#------------------------------------------------------------------------------#
# AUTO generated information
#------------------------------------------------------------------------------#
set module_name "bit_stuffer_fd"
set dut_entity "u_dut*"
set test_bench_name "bit_stuffer_fd_tb"
set abs_path "c:/git_folder/triton_func"

proc simcom {} {
  run "-all"
}

set load_wave_file true
set sim_wave_module_name "sim_wave_bit_stuffer_fd.tcl"

# hdl path relative to testcase folder
set hdl_path "c:/git_folder/triton_func/HW_TEST_SUITE/hdl_src"

# Relative path to work (temp) folder 
set work_path "C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/bit_stuffer_fd/tmp/config_sim_bit_stuffer_fd/riviera_pro_1_0"

# Relative path to simulation coverage folder
set cov_path "C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/bit_stuffer_fd/tmp/config_sim_bit_stuffer_fd/coverage_1_0"

# Point to testcase path
set test_case_path "C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/bit_stuffer_fd/test_case"

# wave file path
set wave_path ${test_case_path}

# Sets test generics
set generics ""

# Set argument for VHDL compiler
set acom_args ""

# Set argument for Verilog compiler
set alog_args ""

# Set argument for simulator
set asim_args ""

set glbl ""

# Python program call
set python_string_app "pythonw"
set python_string_name "c:/git_folder/triton_func/HW_TEST_SUITE/app/testSuite.py"
set python_string_arg_t "C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/bit_stuffer_fd/test_case/config_sim_bit_stuffer_fd.cfg"
set python_string_args "-no-html-report -p riviera_pro -t $python_string_arg_t -sq -pa :mode prepare"

set tool_libraries {
 "C:/git_folder/tools_library_output/Riviera-PRO-2024.10-x64/osvvm/2023.04"
}

# Libraries compile order
set libraries {
  glbl
  bit_stuffer_fd
}


# Core files dictionary
set core_files [dict create]

# Insert core files
dict set core_files glbl [dict create \
  verilog {
    "C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/bit_stuffer_fd/tmp/config_sim_bit_stuffer_fd/riviera_pro_1_0/glbl.v"
  } \
]

dict set core_files bit_stuffer_fd [dict create \
  vhdl {
    "C:/git_folder/triton_func/modules/ip_lib/man_global_p/hdl_src/man_global_p.vhd"
    "C:/git_folder/triton_func/modules/ip_lib/avalon_mm/hdl_src/avalon_mm_extif_defs_p.vhd"
    "C:/git_folder/triton_func/modules/simlib/common_tb_pkgs/common_tb_pkg.vhd"
    "C:/git_folder/triton_func/modules/simlib/common_tb_pkgs/common_register_interface_pkg.vhd"
    "C:/git_folder/triton_func/modules/simlib/verification_components/extif/hdl_src/extif_transaction_vc.vhd"
    "C:/git_folder/triton_func/modules/simlib/verification_components/extif/hdl_src/extif_memory_vc.vhd"
    "C:/git_folder/triton_func/modules/simlib/verification_components/extif/hdl_src/extif_transaction_vc_pkg.vhd"
    "C:/git_folder/triton_func/modules/simlib/verification_components/event_handler/hdl_src/event_handler_vc.vhd"
    "C:/git_folder/triton_func/modules/simlib/verification_components/event_handler/hdl_src/event_handler_vc_pkg.vhd"
    "C:/git_folder/triton_func/modules/simlib/global_random_seed.vhd"
    "C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/bit_stuffer_fd/hdl_src/bit_stuffer_fd.vhd"
    "C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/bit_stuffer_fd/hdl_src/can_protocol_pkg.vhd"
    "C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/bit_stuffer_fd/hdl_src/can_types_pkg.vhd"
    "C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/bit_stuffer_fd/hdl_src/can_timing_pkg.vhd"
    "C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/bit_stuffer_fd/hdl_tb/bit_stuffer_fd_tb.vhd"
  } \
]



# OSVVM files dictionary
set osvvm_files [dict create \
]


