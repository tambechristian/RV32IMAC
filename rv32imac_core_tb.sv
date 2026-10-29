`timescale 1ns / 1ps

module rv32imac_core_tb;
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

    always_ff @(posedge clk) begin
        if (memory_valid && memory_write) begin
            if (memory_write_strobe[0]) memory[memory_address[9:2]][7:0] <= memory_write_data[7:0];
            if (memory_write_strobe[1]) memory[memory_address[9:2]][15:8] <= memory_write_data[15:8];
            if (memory_write_strobe[2]) memory[memory_address[9:2]][23:16] <= memory_write_data[23:16];
            if (memory_write_strobe[3]) memory[memory_address[9:2]][31:24] <= memory_write_data[31:24];
        end
    end

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
        memory[0] = 32'h00500093; // addi x1,x0,5
        memory[1] = 32'h00700113; // addi x2,x0,7
        memory[2] = 32'h022081b3; // mul x3,x1,x2
        memory[3] = 32'h10302023; // sw x3,0x100(x0)
        memory[4] = 32'h10002203; // lw x4,0x100(x0)
        memory[5] = 32'h00010205; // c.addi x4,1; c.nop
        memory[6] = 32'h10000313; // addi x6,x0,0x100
        memory[7] = 32'h001322af; // amoadd.w x5,x1,(x6)
        memory[8] = 32'h00032383; // lw x7,0(x6)
        memory[9] = 32'h0000006f; // loop

        repeat (3) @(negedge clk);
        reset = 1'b0;
        repeat (500) @(negedge clk);
        debug_halt_request = 1'b1;
        while (!debug_halted) @(negedge clk);
        debug_halt_request = 1'b0;

        check_register(5'd3, 32'd35);
        check_register(5'd4, 32'd36);
        check_register(5'd5, 32'd35);
        check_register(5'd7, 32'd40);
        if (memory[64] !== 32'd40) begin
            $error("memory[0x100] expected=00000028 actual=%08x", memory[64]);
            failures = failures + 1;
        end
        if (debug_program_counter !== 32'h00000024) begin
            $error("expected loop PC 00000024 actual=%08x", debug_program_counter);
            failures = failures + 1;
        end

        if (failures == 0) $display("PASS: rv32imac_core");
        else $fatal(1, "FAIL: rv32imac_core (%0d failures)", failures);
        $finish;
    end
endmodule
