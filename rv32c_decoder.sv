`timescale 1ns / 1ps

module rv32c_decoder (
    input  logic [15:0] compressed,
    output logic [31:0] instruction,
    output logic        illegal
);
    logic [4:0] rd, rs1, rs2;
    logic [4:0] crd, crs1, crs2;
    logic [31:0] imm;

    function automatic logic [31:0] enc_i(
        input logic [11:0] i, input logic [4:0] s1,
        input logic [2:0] f3, input logic [4:0] d, input logic [6:0] op
    );
        enc_i = {i, s1, f3, d, op};
    endfunction

    function automatic logic [31:0] enc_r(
        input logic [6:0] f7, input logic [4:0] s2, input logic [4:0] s1,
        input logic [2:0] f3, input logic [4:0] d, input logic [6:0] op
    );
        enc_r = {f7, s2, s1, f3, d, op};
    endfunction

    function automatic logic [31:0] enc_s(
        input logic [11:0] i, input logic [4:0] s2,
        input logic [4:0] s1, input logic [2:0] f3
    );
        enc_s = {i[11:5], s2, s1, f3, i[4:0], 7'b0100011};
    endfunction

    function automatic logic [31:0] enc_b(
        input logic [12:0] i, input logic [4:0] s2,
        input logic [4:0] s1, input logic [2:0] f3
    );
        enc_b = {i[12], i[10:5], s2, s1, f3, i[4:1], i[11], 7'b1100011};
    endfunction

    function automatic logic [31:0] enc_j(input logic [20:0] i, input logic [4:0] d);
        enc_j = {i[20], i[10:1], i[11], i[19:12], d, 7'b1101111};
    endfunction

    always_comb begin
        rd = compressed[11:7];
        rs1 = compressed[11:7];
        rs2 = compressed[6:2];
        crd = {2'b01, compressed[4:2]};
        crs1 = {2'b01, compressed[9:7]};
        crs2 = {2'b01, compressed[4:2]};
        instruction = 32'h00000013;
        illegal = 1'b0;
        imm = 32'd0;

        unique case (compressed[1:0])
            2'b00: unique case (compressed[15:13])
                3'b000: begin // C.ADDI4SPN
                    imm = {22'd0, compressed[10:7], compressed[12:11],
                           compressed[5], compressed[6], 2'b00};
                    instruction = enc_i(imm[11:0], 5'd2, 3'b000, crd, 7'b0010011);
                    illegal = imm == 0;
                end
                3'b010: begin // C.LW
                    imm = {25'd0, compressed[5], compressed[12:10], compressed[6], 2'b00};
                    instruction = enc_i(imm[11:0], crs1, 3'b010, crd, 7'b0000011);
                end
                3'b110: begin // C.SW
                    imm = {25'd0, compressed[5], compressed[12:10], compressed[6], 2'b00};
                    instruction = enc_s(imm[11:0], crs2, crs1, 3'b010);
                end
                default: illegal = 1'b1;
            endcase
            2'b01: unique case (compressed[15:13])
                3'b000: begin // C.ADDI / C.NOP
                    imm = {{26{compressed[12]}}, compressed[12], compressed[6:2]};
                    instruction = enc_i(imm[11:0], rs1, 3'b000, rd, 7'b0010011);
                end
                3'b001: begin // C.JAL (RV32)
                    imm = {{20{compressed[12]}}, compressed[12], compressed[8],
                           compressed[10:9], compressed[6], compressed[7],
                           compressed[2], compressed[11], compressed[5:3], 1'b0};
                    instruction = enc_j(imm[20:0], 5'd1);
                end
                3'b010: begin // C.LI
                    imm = {{26{compressed[12]}}, compressed[12], compressed[6:2]};
                    instruction = enc_i(imm[11:0], 5'd0, 3'b000, rd, 7'b0010011);
                    illegal = rd == 0;
                end
                3'b011: begin
                    if (rd == 5'd2) begin // C.ADDI16SP
                        imm = {{22{compressed[12]}}, compressed[12], compressed[4:3],
                               compressed[5], compressed[2], compressed[6], 4'b0000};
                        instruction = enc_i(imm[11:0], 5'd2, 3'b000, 5'd2, 7'b0010011);
                        illegal = imm == 0;
                    end else begin // C.LUI
                        imm = {{14{compressed[12]}}, compressed[12], compressed[6:2], 12'd0};
                        instruction = {imm[31:12], rd, 7'b0110111};
                        illegal = rd == 0 || rd == 2 || imm == 0;
                    end
                end
                3'b100: begin
                    unique case (compressed[11:10])
                        2'b00: begin // C.SRLI
                            instruction = enc_i({7'b0000000, compressed[6:2]}, crs1,
                                                3'b101, crs1, 7'b0010011);
                            illegal = compressed[12];
                        end
                        2'b01: begin // C.SRAI
                            instruction = enc_i({7'b0100000, compressed[6:2]}, crs1,
                                                3'b101, crs1, 7'b0010011);
                            illegal = compressed[12];
                        end
                        2'b10: begin // C.ANDI
                            imm = {{26{compressed[12]}}, compressed[12], compressed[6:2]};
                            instruction = enc_i(imm[11:0], crs1, 3'b111, crs1, 7'b0010011);
                        end
                        default: begin
                            illegal = compressed[12];
                            unique case (compressed[6:5])
                                2'b00: instruction = enc_r(7'b0100000, crs2, crs1, 3'b000, crs1, 7'b0110011); // SUB
                                2'b01: instruction = enc_r(7'b0000000, crs2, crs1, 3'b100, crs1, 7'b0110011); // XOR
                                2'b10: instruction = enc_r(7'b0000000, crs2, crs1, 3'b110, crs1, 7'b0110011); // OR
                                2'b11: instruction = enc_r(7'b0000000, crs2, crs1, 3'b111, crs1, 7'b0110011); // AND
                            endcase
                        end
                    endcase
                end
                3'b101: begin // C.J
                    imm = {{20{compressed[12]}}, compressed[12], compressed[8],
                           compressed[10:9], compressed[6], compressed[7],
                           compressed[2], compressed[11], compressed[5:3], 1'b0};
                    instruction = enc_j(imm[20:0], 5'd0);
                end
                3'b110, 3'b111: begin // C.BEQZ / C.BNEZ
                    imm = {{23{compressed[12]}}, compressed[12], compressed[6:5],
                           compressed[2], compressed[11:10], compressed[4:3], 1'b0};
                    instruction = enc_b(imm[12:0], 5'd0, crs1,
                                        compressed[13] ? 3'b001 : 3'b000);
                end
            endcase
            2'b10: unique case (compressed[15:13])
                3'b000: begin // C.SLLI
                    instruction = enc_i({7'b0000000, compressed[6:2]}, rs1,
                                        3'b001, rd, 7'b0010011);
                    illegal = compressed[12] || rd == 0;
                end
                3'b010: begin // C.LWSP
                    imm = {24'd0, compressed[3:2], compressed[12],
                           compressed[6:4], 2'b00};
                    instruction = enc_i(imm[11:0], 5'd2, 3'b010, rd, 7'b0000011);
                    illegal = rd == 0;
                end
                3'b100: begin
                    if (!compressed[12]) begin
                        if (rs2 == 0) begin // C.JR
                            instruction = enc_i(12'd0, rs1, 3'b000, 5'd0, 7'b1100111);
                            illegal = rs1 == 0;
                        end else begin // C.MV
                            instruction = enc_r(7'd0, rs2, 5'd0, 3'b000, rd, 7'b0110011);
                            illegal = rd == 0;
                        end
                    end else if (rd == 0 && rs2 == 0) begin
                        instruction = 32'h00100073; // C.EBREAK
                    end else if (rs2 == 0) begin // C.JALR
                        instruction = enc_i(12'd0, rs1, 3'b000, 5'd1, 7'b1100111);
                        illegal = rs1 == 0;
                    end else begin // C.ADD
                        instruction = enc_r(7'd0, rs2, rs1, 3'b000, rd, 7'b0110011);
                        illegal = rd == 0;
                    end
                end
                3'b110: begin // C.SWSP
                    imm = {24'd0, compressed[8:7], compressed[12:9], 2'b00};
                    instruction = enc_s(imm[11:0], rs2, 5'd2, 3'b010);
                end
                default: illegal = 1'b1;
            endcase
            default: illegal = 1'b1;
        endcase
    end
endmodule
