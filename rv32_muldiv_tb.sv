`timescale 1ns / 1ps

module rv32_muldiv_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b0;
    logic [2:0] operation;
    logic [31:0] operand_a, operand_b;
    logic busy, done;
    logic [31:0] result;
    integer failures = 0;

    always #5 clk = ~clk;

    rv32_muldiv dut (
        .clk(clk), .reset(reset), .start(start), .operation(operation),
        .operand_a(operand_a), .operand_b(operand_b),
        .busy(busy), .done(done), .result(result)
    );

    task automatic check(
        input logic [2:0] op,
        input logic [31:0] a,
        input logic [31:0] b,
        input logic [31:0] expected
    );
        begin
            @(negedge clk);
            operation = op;
            operand_a = a;
            operand_b = b;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            while (!done) @(negedge clk);
            if (result !== expected) begin
                $error("op=%0d a=%08x b=%08x expected=%08x actual=%08x",
                       op, a, b, expected, result);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        repeat (2) @(negedge clk);
        reset = 1'b0;
        check(3'd0, 32'hfffffffe, 32'd3, 32'hfffffffa);
        check(3'd1, 32'hfffffffe, 32'd3, 32'hffffffff);
        check(3'd2, 32'hfffffffe, 32'hffffffff, 32'hfffffffe);
        check(3'd3, 32'hffffffff, 32'd2, 32'h00000001);
        check(3'd4, -32'd7, 32'd3, -32'd2);
        check(3'd5, 32'hfffffff9, 32'd3, 32'h55555553);
        check(3'd6, -32'd7, 32'd3, 32'hffffffff);
        check(3'd7, 32'hfffffff9, 32'd3, 32'd0);
        check(3'd4, 32'h12345678, 32'd0, 32'hffffffff);
        check(3'd6, 32'h12345678, 32'd0, 32'h12345678);
        check(3'd4, 32'h80000000, 32'hffffffff, 32'h80000000);
        check(3'd6, 32'h80000000, 32'hffffffff, 32'd0);
        if (failures == 0) $display("PASS: rv32_muldiv");
        else $fatal(1, "FAIL: rv32_muldiv (%0d failures)", failures);
        $finish;
    end
endmodule
