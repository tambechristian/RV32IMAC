# AS4C32M16SB-7TCN connections extracted from the routed Zulu A7 PCB.
set_property PACKAGE_PIN U2  [get_ports {sdram_addr[0]}]
set_property PACKAGE_PIN T3  [get_ports {sdram_addr[1]}]
set_property PACKAGE_PIN T2  [get_ports {sdram_addr[2]}]
set_property PACKAGE_PIN T1  [get_ports {sdram_addr[3]}]
set_property PACKAGE_PIN R3  [get_ports {sdram_addr[4]}]
set_property PACKAGE_PIN R2  [get_ports {sdram_addr[5]}]
set_property PACKAGE_PIN P3  [get_ports {sdram_addr[6]}]
set_property PACKAGE_PIN P1  [get_ports {sdram_addr[7]}]
set_property PACKAGE_PIN N3  [get_ports {sdram_addr[8]}]
set_property PACKAGE_PIN N2  [get_ports {sdram_addr[9]}]
set_property PACKAGE_PIN U3  [get_ports {sdram_addr[10]}]
set_property PACKAGE_PIN N1  [get_ports {sdram_addr[11]}]
set_property PACKAGE_PIN M3  [get_ports {sdram_addr[12]}]
set_property PACKAGE_PIN V2  [get_ports {sdram_ba[0]}]
set_property PACKAGE_PIN U1  [get_ports {sdram_ba[1]}]

set_property PACKAGE_PIN V8  [get_ports {sdram_dq[0]}]
set_property PACKAGE_PIN V7  [get_ports {sdram_dq[1]}]
set_property PACKAGE_PIN W7  [get_ports {sdram_dq[2]}]
set_property PACKAGE_PIN W6  [get_ports {sdram_dq[3]}]
set_property PACKAGE_PIN U5  [get_ports {sdram_dq[4]}]
set_property PACKAGE_PIN W5  [get_ports {sdram_dq[5]}]
set_property PACKAGE_PIN V5  [get_ports {sdram_dq[6]}]
set_property PACKAGE_PIN U4  [get_ports {sdram_dq[7]}]
set_property PACKAGE_PIN L1  [get_ports {sdram_dq[8]}]
set_property PACKAGE_PIN K3  [get_ports {sdram_dq[9]}]
set_property PACKAGE_PIN K2  [get_ports {sdram_dq[10]}]
set_property PACKAGE_PIN J1  [get_ports {sdram_dq[11]}]
set_property PACKAGE_PIN J3  [get_ports {sdram_dq[12]}]
set_property PACKAGE_PIN H1  [get_ports {sdram_dq[13]}]
set_property PACKAGE_PIN A14 [get_ports {sdram_dq[14]}]
set_property PACKAGE_PIN A15 [get_ports {sdram_dq[15]}]

set_property PACKAGE_PIN M1 [get_ports sdram_clk]
set_property PACKAGE_PIN M2 [get_ports sdram_cke]
set_property PACKAGE_PIN W2 [get_ports sdram_cs_n]
set_property PACKAGE_PIN V3 [get_ports sdram_ras_n]
set_property PACKAGE_PIN W3 [get_ports sdram_cas_n]
set_property PACKAGE_PIN V4 [get_ports sdram_we_n]
set_property PACKAGE_PIN W4 [get_ports {sdram_dqm[0]}]
set_property PACKAGE_PIN L2 [get_ports {sdram_dqm[1]}]

set_property IOSTANDARD LVCMOS33 [get_ports {
    sdram_addr[*] sdram_ba[*] sdram_dq[*] sdram_clk sdram_cke
    sdram_cs_n sdram_ras_n sdram_cas_n sdram_we_n sdram_dqm[*]
}]
set_property SLEW FAST [get_ports {
    sdram_addr[*] sdram_ba[*] sdram_clk sdram_cke
    sdram_cs_n sdram_ras_n sdram_cas_n sdram_we_n sdram_dqm[*]
}]
set_property DRIVE 8 [get_ports {
    sdram_addr[*] sdram_ba[*] sdram_dq[*] sdram_clk sdram_cke
    sdram_cs_n sdram_ras_n sdram_cas_n sdram_we_n sdram_dqm[*]
}]

# Add input/output delay constraints after the final MMCM and forwarded-clock
# topology is fixed and measured against the routed PCB flight times.
