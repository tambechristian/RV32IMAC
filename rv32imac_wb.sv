`timescale 1ns / 1ps

module rv32imac_wb (
    input  logic        clk,
    input  logic        reset,
    output logic        wb_cyc,
    output logic        wb_stb,
    output logic        wb_we,
    output logic [31:0] wb_adr,
    output logic [31:0] wb_dat_w,
    output logic [3:0]  wb_sel,
    input  logic        wb_ack,
    input  logic        wb_err,
    input  logic [31:0] wb_dat_r,
    input  logic        irq_software_m,
    input  logic        irq_timer_m,
    input  logic        irq_external_m,
    input  logic        irq_software_s,
    input  logic        irq_timer_s,
    input  logic        irq_external_s,
    input  logic [63:0] time_value,
    input  logic        debug_halt_request,
    input  logic        debug_resume_request,
    input  logic        debug_step_request,
    output logic        debug_halted,
    output logic [31:0] debug_program_counter,
    input  logic [4:0]  debug_register_index,
    output logic [31:0] debug_register_data,
    input  logic        debug_register_write,
    input  logic [31:0] debug_register_write_data
);
    logic memory_valid;

    assign wb_cyc = memory_valid;
    assign wb_stb = memory_valid;

    rv32imac_core core (
        .clk(clk),
        .reset(reset),
        .memory_valid(memory_valid),
        .memory_write(wb_we),
        .memory_address(wb_adr),
        .memory_write_data(wb_dat_w),
        .memory_write_strobe(wb_sel),
        .memory_ready(wb_ack || wb_err),
        .memory_read_data(wb_dat_r),
        .memory_error(wb_err),
        .irq_software_m(irq_software_m),
        .irq_timer_m(irq_timer_m),
        .irq_external_m(irq_external_m),
        .irq_software_s(irq_software_s),
        .irq_timer_s(irq_timer_s),
        .irq_external_s(irq_external_s),
        .time_value(time_value),
        .debug_halt_request(debug_halt_request),
        .debug_resume_request(debug_resume_request),
        .debug_step_request(debug_step_request),
        .debug_halted(debug_halted),
        .debug_program_counter(debug_program_counter),
        .debug_register_index(debug_register_index),
        .debug_register_data(debug_register_data),
        .debug_register_write(debug_register_write),
        .debug_register_write_data(debug_register_write_data)
    );
endmodule
