`timescale 1ns / 1ps

module zulu_sdram_controller_tb;
    localparam integer CAS_LATENCY = 3;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic wb_cyc = 1'b0;
    logic wb_stb = 1'b0;
    logic wb_we = 1'b0;
    logic [31:0] wb_adr = 32'd0;
    logic [31:0] wb_dat_w = 32'd0;
    logic [3:0] wb_sel = 4'd0;
    logic wb_ack;
    logic wb_err;
    logic [31:0] wb_dat_r;
    logic init_done;
    logic sdram_clk;
    logic sdram_cke;
    logic sdram_cs_n;
    logic sdram_ras_n;
    logic sdram_cas_n;
    logic sdram_we_n;
    logic [1:0] sdram_ba;
    logic [12:0] sdram_addr;
    wire [15:0] sdram_dq;
    logic [1:0] sdram_dqm;
    logic [15:0] model_dq;
    logic model_dq_enable = 1'b0;
    logic [15:0] model_memory [0:2047];
    logic [12:0] open_row [0:3];
    logic [3:0] row_open = 4'd0;
    integer read_delay = 0;
    integer read_index = 0;
    integer precharge_count = 0;
    integer refresh_count = 0;
    integer mode_count = 0;
    integer failures = 0;

    assign sdram_dq = model_dq_enable ? model_dq : 16'hzzzz;
    always #5 clk = ~clk;

    zulu_sdram_controller #(
        .POWERUP_DELAY_CYCLES(8),
        .REFRESH_INTERVAL_CYCLES(40),
        .T_RP_CYCLES(2),
        .T_RCD_CYCLES(2),
        .T_RFC_CYCLES(3),
        .T_MRD_CYCLES(2),
        .T_WRITE_RECOVERY_CYCLES(3),
        .CAS_LATENCY(CAS_LATENCY)
    ) dut (
        .clk(clk),
        .reset(reset),
        .wb_cyc(wb_cyc),
        .wb_stb(wb_stb),
        .wb_we(wb_we),
        .wb_adr(wb_adr),
        .wb_dat_w(wb_dat_w),
        .wb_sel(wb_sel),
        .wb_ack(wb_ack),
        .wb_err(wb_err),
        .wb_dat_r(wb_dat_r),
        .init_done(init_done),
        .sdram_clk(sdram_clk),
        .sdram_cke(sdram_cke),
        .sdram_cs_n(sdram_cs_n),
        .sdram_ras_n(sdram_ras_n),
        .sdram_cas_n(sdram_cas_n),
        .sdram_we_n(sdram_we_n),
        .sdram_ba(sdram_ba),
        .sdram_addr(sdram_addr),
        .sdram_dq(sdram_dq),
        .sdram_dqm(sdram_dqm)
    );

    always @(posedge clk) begin
        if (!sdram_cs_n && sdram_cke) begin
            unique case ({sdram_ras_n, sdram_cas_n, sdram_we_n})
                3'b011: begin
                    open_row[sdram_ba] = sdram_addr;
                    row_open[sdram_ba] = 1'b1;
                end
                3'b101: begin
                    if (!row_open[sdram_ba])
                        $fatal(1, "READ without open row");
                    read_index = {open_row[sdram_ba][0], sdram_addr[9:0]};
                    read_delay = CAS_LATENCY;
                end
                3'b100: begin
                    if (!row_open[sdram_ba])
                        $fatal(1, "WRITE without open row");
                    read_index = {open_row[sdram_ba][0], sdram_addr[9:0]};
                    if (!sdram_dqm[0])
                        model_memory[read_index][7:0] = sdram_dq[7:0];
                    if (!sdram_dqm[1])
                        model_memory[read_index][15:8] = sdram_dq[15:8];
                    if (sdram_addr[10])
                        row_open[sdram_ba] = 1'b0;
                end
                3'b010: begin
                    precharge_count = precharge_count + 1;
                    row_open = 4'd0;
                end
                3'b001: refresh_count = refresh_count + 1;
                3'b000: mode_count = mode_count + 1;
                default: begin end
            endcase
        end
    end

    always @(negedge clk) begin
        model_dq_enable = 1'b0;
        if (read_delay > 0) begin
            read_delay = read_delay - 1;
            if (read_delay == 0) begin
                model_dq = model_memory[read_index];
                model_dq_enable = 1'b1;
            end
        end
    end

    task automatic wishbone_write(
        input logic [31:0] address,
        input logic [31:0] data,
        input logic [3:0] select
    );
        begin
            @(negedge clk);
            wb_adr = address;
            wb_dat_w = data;
            wb_sel = select;
            wb_we = 1'b1;
            wb_cyc = 1'b1;
            wb_stb = 1'b1;
            while (!wb_ack)
                @(negedge clk);
            if (wb_err)
                $fatal(1, "Unexpected Wishbone write error");
            wb_cyc = 1'b0;
            wb_stb = 1'b0;
            wb_we = 1'b0;
            @(negedge clk);
        end
    endtask

    task automatic wishbone_read(
        input logic [31:0] address,
        output logic [31:0] data
    );
        begin
            @(negedge clk);
            wb_adr = address;
            wb_sel = 4'b1111;
            wb_we = 1'b0;
            wb_cyc = 1'b1;
            wb_stb = 1'b1;
            while (!wb_ack)
                @(negedge clk);
            if (wb_err)
                $fatal(1, "Unexpected Wishbone read error");
            data = wb_dat_r;
            wb_cyc = 1'b0;
            wb_stb = 1'b0;
            @(negedge clk);
        end
    endtask

    initial begin
        logic [31:0] value;

        for (integer i = 0; i < 2048; i++)
            model_memory[i] = 16'd0;
        repeat (4) @(negedge clk);
        reset = 1'b0;

        while (!init_done)
            @(negedge clk);
        if (precharge_count != 1 || refresh_count != 2 || mode_count != 1) begin
            $error(
                "Initialization commands precharge=%0d refresh=%0d mode=%0d",
                precharge_count,
                refresh_count,
                mode_count
            );
            failures = failures + 1;
        end

        wishbone_write(32'h00000100, 32'h11223344, 4'b1111);
        wishbone_read(32'h00000100, value);
        if (value !== 32'h11223344) begin
            $error("Full-word read expected=11223344 actual=%08x", value);
            failures = failures + 1;
        end

        wishbone_write(32'h00000100, 32'ha1b2c3d4, 4'b0101);
        wishbone_read(32'h00000100, value);
        if (value !== 32'h11b233d4) begin
            $error("Masked write expected=11b233d4 actual=%08x", value);
            failures = failures + 1;
        end

        repeat (100) @(negedge clk);
        if (refresh_count <= 2) begin
            $error("Periodic refresh did not run");
            failures = failures + 1;
        end

        if (failures == 0)
            $display("PASS: zulu_sdram_controller");
        else
            $fatal(1, "FAIL: zulu_sdram_controller (%0d failures)", failures);
        $finish;
    end
endmodule
