set script_dir [file dirname [file normalize [info script]]]

read_verilog -sv [file join $script_dir rtl zulu_sdram_controller.sv]
synth_design -top zulu_sdram_controller -part xc7a35tcpg236-2
create_clock -name sys_clk -period 10.000 [get_ports clk]

report_utilization -hierarchical
report_timing_summary -delay_type max -max_paths 10
