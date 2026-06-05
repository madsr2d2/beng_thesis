
if {[catch {workspace.create Temp} fid]} {
    workspace.open Temp.alintws
}

if { [file exists C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/can_pcs/test_case/alint_pro_pre_cmd.do] == 1} {
   do C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/can_pcs/test_case/alint_pro_pre_cmd.do
} 

# Include files
workspace.project.create  -force can_pcs
project.clean  -project can_pcs
workspace.file.add -destination can_pcs -f {C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/can_pcs/tmp/config_sim_can_pcs/alint_pro_1_0/alint_pro_lib_can_pcs_files.lst}
project.parse -project can_pcs

workspace.project.setactive -project can_pcs


global.pref.generateblackbox yes

do "c:/git_folder/triton_func/HW_TEST_SUITE/app/plugins/aldec/alint_pro/policies/Triton_3_1_policy.do"

project.pref.vhdlstandard -project can_pcs -format vhdl2008
project.pref.vlogstandard -project can_pcs -format sv2005

#do C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/can_pcs/tmp/config_sim_can_pcs/alint_pro_1_0/alint_pro_pre_cmd.do

# Generic list


project.elaborate
project.lint -parse
project.lint -elab
project.synthesize
project.lint -synthesis
project.constrain 
project.pref.constraintstofile -name can_pcs_constraints.adc
create_clock -period 10 -name Input_Clk [get_ports can_pcs/clk_i]

create_reset -rise_clock [get_clocks Input_Clk] -fall_clock [get_clocks Input_Clk] -name Input_Rst [get_ports can_pcs/reset_i] -polarity active-high

workspace.file.add -destination can_pcs can_pcs_constraints.adc
project.constrain 
project.lint -constraints


project.waiver.add -f C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/can_pcs/tmp/config_sim_can_pcs/alint_pro_1_0/alint_pro_exfiles.lst


     