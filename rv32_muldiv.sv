`timescale 1ns / 1ps

module rv32_muldiv (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic [2:0]  operation,
    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    output logic        busy,
    output logic        done,
    output logic [31:0] result
);
    localparam logic [2:0] OP_MUL = 3'd0, OP_MULH = 3'd1, OP_MULHSU = 3'd2,
                             OP_MULHU = 3'd3, OP_DIV = 3'd4, OP_DIVU = 3'd5,
                             OP_REM = 3'd6, OP_REMU = 3'd7;
    logic [2:0] saved_operation;
    logic [5:0] count;
    logic [63:0] multiplicand, product;
    logic [31:0] multiplier;
    logic [63:0] dividend_shift;
    logic [32:0] remainder_work;
    logic [31:0] divisor, quotient;
    logic negate_result, negate_remainder;
    logic negate_product;
    logic divide_by_zero, signed_overflow;
    logic [31:0] saved_operand_a;

    always_ff @(posedge clk) begin
        if (reset) begin
            busy <= 1'b0;
            done <= 1'b0;
            result <= 32'd0;
            count <= 6'd0;
        end else begin
            done <= 1'b0;
            if (start && !busy) begin
                busy <= 1'b1;
                count <= 6'd0;
                saved_operation <= operation;
                saved_operand_a <= operand_a;
                if (operation <= OP_MULHU) begin
                    negate_product <=
                        (operation == OP_MULH && (operand_a[31] ^ operand_b[31])) ||
                        (operation == OP_MULHSU && operand_a[31]);
                    multiplicand <= {32'd0,
                        ((operation == OP_MULH || operation == OP_MULHSU) && operand_a[31])
                            ? (~operand_a + 1'b1) : operand_a};
                    multiplier <= (operation == OP_MULH && operand_b[31])
                        ? (~operand_b + 1'b1) : operand_b;
                    product <= 64'd0;
                end else begin
                    divide_by_zero <= operand_b == 0;
                    signed_overflow <= (operation == OP_DIV || operation == OP_REM) &&
                                       operand_a == 32'h80000000 && operand_b == 32'hffffffff;
                    negate_result <= (operation == OP_DIV || operation == OP_REM) &&
                                     (operand_a[31] ^ operand_b[31]);
                    negate_remainder <= (operation == OP_DIV || operation == OP_REM) && operand_a[31];
                    dividend_shift <= {32'd0,
                        ((operation == OP_DIV || operation == OP_REM) && operand_a[31])
                            ? (~operand_a + 1'b1) : operand_a};
                    divisor <= ((operation == OP_DIV || operation == OP_REM) && operand_b[31])
                            ? (~operand_b + 1'b1) : operand_b;
                    quotient <= 32'd0;
                    remainder_work <= 33'd0;
                end
            end else if (busy) begin
                if (saved_operation <= OP_MULHU) begin
                    if (multiplier[0]) product <= product + multiplicand;
                    multiplicand <= multiplicand << 1;
                    multiplier <= multiplier >> 1;
                    if (count == 6'd31) begin
                        logic [63:0] final_product;
                        final_product = product + (multiplier[0] ? multiplicand : 64'd0);
                        if (negate_product) final_product = ~final_product + 1'b1;
                        result <= saved_operation == OP_MUL ? final_product[31:0] :
                                  final_product[63:32];
                        busy <= 1'b0;
                        done <= 1'b1;
                    end
                end else if (divide_by_zero) begin
                    result <= (saved_operation == OP_DIV || saved_operation == OP_DIVU)
                            ? 32'hffffffff : saved_operand_a;
                    busy <= 1'b0;
                    done <= 1'b1;
                end else if (signed_overflow) begin
                    result <= (saved_operation == OP_DIV) ? 32'h80000000 : 32'd0;
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    logic [32:0] shifted_remainder;
                    logic [31:0] shifted_dividend;
                    shifted_remainder = {remainder_work[31:0], dividend_shift[31]};
                    shifted_dividend = {dividend_shift[30:0], 1'b0};
                    dividend_shift <= {32'd0, shifted_dividend};
                    if (shifted_remainder >= {1'b0, divisor}) begin
                        remainder_work <= shifted_remainder - {1'b0, divisor};
                        quotient <= {quotient[30:0], 1'b1};
                    end else begin
                        remainder_work <= shifted_remainder;
                        quotient <= {quotient[30:0], 1'b0};
                    end
                    if (count == 6'd31) begin
                        logic [31:0] final_quotient, final_remainder;
                        final_quotient = {quotient[30:0],
                            shifted_remainder >= {1'b0, divisor}};
                        final_remainder = shifted_remainder >= {1'b0, divisor}
                            ? shifted_remainder[31:0] - divisor : shifted_remainder[31:0];
                        if (negate_result) final_quotient = ~final_quotient + 1'b1;
                        if (negate_remainder) final_remainder = ~final_remainder + 1'b1;
                        result <= (saved_operation == OP_DIV || saved_operation == OP_DIVU)
                                ? final_quotient : final_remainder;
                        busy <= 1'b0;
                        done <= 1'b1;
                    end
                end
                count <= count + 1'b1;
            end
        end
    end
endmodule
