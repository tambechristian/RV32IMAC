`timescale 1ns / 1ps

module rv32c_decoder_tb;
    logic [15:0] compressed;
    logic [31:0] instruction;
    logic illegal;
    integer failures = 0;

    rv32c_decoder dut (
        .compressed(compressed),
        .instruction(instruction),
        .illegal(illegal)
    );

    task automatic check(
        input logic [15:0] value,
        input logic [31:0] expected,
        input logic expected_illegal
    );
        begin
            compressed = value;
            #1;
            if (instruction !== expected || illegal !== expected_illegal) begin
                $error("compressed=%04x expected=%08x/%b actual=%08x/%b",
                       value, expected, expected_illegal, instruction, illegal);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        check(16'h0001, 32'h00000013, 1'b0); // C.NOP
        check(16'h557d, 32'hfff00513, 1'b0); // C.LI a0,-1
        check(16'h8082, 32'h00008067, 1'b0); // C.JR ra
        check(16'h852e, 32'h00b00533, 1'b0); // C.MV a0,a1
        check(16'h952e, 32'h00b50533, 1'b0); // C.ADD a0,a1
        check(16'h9002, 32'h00100073, 1'b0); // C.EBREAK
        check(16'h4502, 32'h00012503, 1'b0); // C.LWSP a0,0(sp)
        check(16'hc02a, 32'h00a12023, 1'b0); // C.SWSP a0,0(sp)
        check(16'h0000, 32'h00010413, 1'b1); // reserved C.ADDI4SPN
        if (failures == 0) $display("PASS: rv32c_decoder");
        else $fatal(1, "FAIL: rv32c_decoder (%0d failures)", failures);
        $finish;
    end
endmodule
