set script_dir [file dirname [file normalize [info script]]]

read_verilog -sv [file join $script_dir rv32imac_pkg.sv]
read_verilog -sv [file join $script_dir rv32c_decoder.sv]
read_verilog -sv [file join $script_dir rv32_muldiv.sv]
read_verilog -sv [file join $script_dir sv32_mmu.sv]
read_verilog -sv [file join $script_dir rv32imac_core.sv]
read_verilog -sv [file join $script_dir rv32imac_wb.sv]

synth_design -top rv32imac_wb -part xc7a35tcpg236-1
report_utilization
report_timing_summary
exit
