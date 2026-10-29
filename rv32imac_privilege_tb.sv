`timescale 1ns / 1ps

module rv32imac_privilege_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic memory_valid, memory_write;
    logic [31:0] memory_address, memory_write_data;
    logic [3:0] memory_write_strobe;
    logic [31:0] memory_read_data;
    logic debug_halt_request = 1'b0;
    logic debug_halted;
    logic [31:0] debug_program_counter;
    logic [4:0] debug_register_index;
    logic [31:0] debug_register_data;
    logic [31:0] memory [0:255];
    integer failures = 0;

    always #5 clk = ~clk;
    assign memory_read_data = memory[memory_address[9:2]];

    rv32imac_core dut (
        .clk(clk), .reset(reset),
        .memory_valid(memory_valid), .memory_write(memory_write),
        .memory_address(memory_address), .memory_write_data(memory_write_data),
        .memory_write_strobe(memory_write_strobe),
        .memory_ready(memory_valid), .memory_read_data(memory_read_data),
        .memory_error(1'b0),
        .irq_software_m(1'b0), .irq_timer_m(1'b0), .irq_external_m(1'b0),
        .irq_software_s(1'b0), .irq_timer_s(1'b0), .irq_external_s(1'b0),
        .time_value(64'd0),
        .debug_halt_request(debug_halt_request),
        .debug_resume_request(1'b0), .debug_step_request(1'b0),
        .debug_halted(debug_halted),
        .debug_program_counter(debug_program_counter),
        .debug_register_index(debug_register_index),
        .debug_register_data(debug_register_data),
        .debug_register_write(1'b0),
        .debug_register_write_data(32'd0)
    );

    task automatic check_register(
        input logic [4:0] index,
        input logic [31:0] expected
    );
        begin
            debug_register_index = index;
            #1;
            if (debug_register_data !== expected) begin
                $error("x%0d expected=%08x actual=%08x",
                       index, expected, debug_register_data);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        for (integer i = 0; i < 256; i++) memory[i] = 32'h00000013;
        memory['h00] = 32'h08000093; // addi x1,x0,0x80
        memory['h01] = 32'h30509073; // csrw mtvec,x1
        memory['h02] = 32'h20000093; // addi x1,x0,0x200
        memory['h03] = 32'h30209073; // csrw medeleg,x1
        memory['h04] = 32'h0a000093; // addi x1,x0,0xa0
        memory['h05] = 32'h10509073; // csrw stvec,x1
        memory['h06] = 32'h04000093; // addi x1,x0,0x40
        memory['h07] = 32'h34109073; // csrw mepc,x1
        memory['h08] = 32'h000010b7; // lui x1,0x1
        memory['h09] = 32'h80008093; // addi x1,x1,-2048 (MPP=S)
        memory['h0a] = 32'h30009073; // csrw mstatus,x1
        memory['h0b] = 32'h30200073; // mret

        memory['h10] = 32'h05500113; // addi x2,x0,0x55
        memory['h11] = 32'h00000073; // ecall from S-mode
        memory['h12] = 32'h06600293; // addi x5,x0,0x66
        memory['h13] = 32'h0000006f; // loop

        memory['h28] = 32'h142021f3; // csrr x3,scause
        memory['h29] = 32'h14102273; // csrr x4,sepc
        memory['h2a] = 32'h00420213; // addi x4,x4,4
        memory['h2b] = 32'h14121073; // csrw sepc,x4
        memory['h2c] = 32'h10200073; // sret

        repeat (3) @(negedge clk);
        reset = 1'b0;
        repeat (300) @(negedge clk);
        debug_halt_request = 1'b1;
        while (!debug_halted) @(negedge clk);
        debug_halt_request = 1'b0;

        check_register(5'd2, 32'h55);
        check_register(5'd3, 32'd9);
        check_register(5'd5, 32'h66);
        if (debug_program_counter !== 32'h0000004c) begin
            $error("expected S-mode loop PC 0000004c actual=%08x",
                   debug_program_counter);
            failures = failures + 1;
        end

        if (failures == 0) $display("PASS: rv32imac_privilege");
        else $fatal(1, "FAIL: rv32imac_privilege (%0d failures)", failures);
        $finish;
    end
endmodule
