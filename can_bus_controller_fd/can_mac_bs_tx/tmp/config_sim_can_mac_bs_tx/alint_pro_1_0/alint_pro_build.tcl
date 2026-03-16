
if {[catch {workspace.create Temp} fid]} {
    workspace.open Temp.alintws
}

if { [file exists C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/can_mac_bs_tx/test_case/alint_pro_pre_cmd.do] == 1} {
   do C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/can_mac_bs_tx/test_case/alint_pro_pre_cmd.do
} 

# Include files
workspace.project.create  -force can_mac_bs_tx
project.clean  -project can_mac_bs_tx
workspace.file.add -destination can_mac_bs_tx -f {C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/can_mac_bs_tx/tmp/config_sim_can_mac_bs_tx/alint_pro_1_0/alint_pro_lib_can_mac_bs_tx_files.lst}
project.parse -project can_mac_bs_tx

workspace.project.setactive -project can_mac_bs_tx


global.pref.generateblackbox yes

do "c:/git_folder/triton_func/HW_TEST_SUITE/app/plugins/aldec/alint_pro/policies/Triton_3_1_policy.do"

project.pref.vhdlstandard -project can_mac_bs_tx -format vhdl2008
project.pref.vlogstandard -project can_mac_bs_tx -format sv2005

#do C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/can_mac_bs_tx/tmp/config_sim_can_mac_bs_tx/alint_pro_1_0/alint_pro_pre_cmd.do

# Generic list


project.elaborate
project.lint -parse
project.lint -elab
project.synthesize
project.lint -synthesis
project.constrain 
project.pref.constraintstofile -name can_mac_bs_tx_constraints.adc
create_clock -period 10 -name Input_Clk [get_ports can_mac_bs_tx/clk_i]

create_reset -rise_clock [get_clocks Input_Clk] -fall_clock [get_clocks Input_Clk] -name Input_Rst [get_ports can_mac_bs_tx/reset_i] -polarity active-high

workspace.file.add -destination can_mac_bs_tx can_mac_bs_tx_constraints.adc
project.constrain 
project.lint -constraints


project.waiver.add -f C:/git_folder/triton_func/modules/ip_lib/can_bus_controller_fd/can_mac_bs_tx/tmp/config_sim_can_mac_bs_tx/alint_pro_1_0/alint_pro_exfiles.lst


     