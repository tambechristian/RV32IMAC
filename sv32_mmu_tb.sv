`timescale 1ns / 1ps

module sv32_mmu_tb;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic flush = 1'b0;
    logic request_valid = 1'b0;
    logic request_ready;
    logic [31:0] virtual_address;
    logic request_write, request_execute;
    logic [31:0] request_write_data;
    logic [3:0] request_write_strobe;
    logic [1:0] privilege;
    logic sum, mxr;
    logic [31:0] satp;
    logic response_valid;
    logic [31:0] response_read_data;
    logic response_page_fault, response_access_fault;
    logic physical_valid, physical_write;
    logic [31:0] physical_address, physical_write_data;
    logic [3:0] physical_write_strobe;
    logic physical_ready, physical_error;
    logic [31:0] physical_read_data;
    integer mode = 0;
    integer walk_reads = 0;
    integer ad_writes = 0;
    integer failures = 0;
    logic [31:0] last_data_address;

    always #5 clk = ~clk;
    assign physical_ready = physical_valid;
    assign physical_error = 1'b0;

    always_comb begin
        physical_read_data = 32'ha5a55a5a;
        case (mode)
            1, 3: case (physical_address)
                32'h00001004: physical_read_data = 32'h00000801;
                32'h0000200c: physical_read_data =
                    mode == 3 ? 32'h000c0007 : 32'h000c00c7;
                default: physical_read_data = 32'ha5a55a5a;
            endcase
            2: if (physical_address == 32'h00001008)
                physical_read_data = 32'h001000c3;
            default: physical_read_data = 32'ha5a55a5a;
        endcase
    end

    always_ff @(posedge clk) begin
        if (physical_valid && !physical_write &&
            physical_address >= 32'h00001000 && physical_address < 32'h00003000)
            walk_reads <= walk_reads + 1;
        if (physical_valid && physical_write && physical_address == 32'h0000200c) begin
            ad_writes <= ad_writes + 1;
            if (physical_write_data !== 32'h000c00c7 ||
                physical_write_strobe !== 4'hf) begin
                $error("bad A/D update data=%08x sel=%x",
                       physical_write_data, physical_write_strobe);
                failures <= failures + 1;
            end
        end
        if (physical_valid &&
            !(physical_address >= 32'h00001000 && physical_address < 32'h00003000))
            last_data_address <= physical_address;
    end

    sv32_mmu dut (
        .clk(clk), .reset(reset), .flush(flush),
        .request_valid(request_valid), .request_ready(request_ready),
        .virtual_address(virtual_address), .request_write(request_write),
        .request_execute(request_execute), .request_write_data(request_write_data),
        .request_write_strobe(request_write_strobe), .privilege(privilege),
        .sum(sum), .mxr(mxr), .satp(satp), .response_valid(response_valid),
        .response_read_data(response_read_data),
        .response_page_fault(response_page_fault),
        .response_access_fault(response_access_fault),
        .physical_valid(physical_valid), .physical_write(physical_write),
        .physical_address(physical_address),
        .physical_write_data(physical_write_data),
        .physical_write_strobe(physical_write_strobe),
        .physical_ready(physical_ready), .physical_read_data(physical_read_data),
        .physical_error(physical_error)
    );

    task automatic access(
        input logic [31:0] address,
        input logic write_access,
        input logic execute_access,
        input logic expect_page_fault,
        input logic [31:0] expected_physical
    );
        begin
            @(negedge clk);
            last_data_address = 32'hxxxxxxxx;
            virtual_address = address;
            request_write = write_access;
            request_execute = execute_access;
            request_valid = 1'b1;
            while (!request_ready) @(negedge clk);
            @(negedge clk);
            request_valid = 1'b0;
            while (!response_valid) @(negedge clk);
            if (response_page_fault !== expect_page_fault ||
                response_access_fault !== 1'b0) begin
                $error("address=%08x expected page fault=%b actual=%b access=%b",
                       address, expect_page_fault, response_page_fault,
                       response_access_fault);
                failures = failures + 1;
            end
            if (!expect_page_fault && last_data_address !== expected_physical) begin
                $error("address=%08x expected physical=%08x actual=%08x",
                       address, expected_physical, last_data_address);
                failures = failures + 1;
            end
            @(negedge clk);
        end
    endtask

    initial begin
        virtual_address = 0;
        request_write = 0;
        request_execute = 0;
        request_write_data = 32'h11223344;
        request_write_strobe = 4'hf;
        privilege = 2'b01;
        sum = 0;
        mxr = 0;
        satp = 0;
        repeat (2) @(negedge clk);
        reset = 1'b0;

        access(32'h12345004, 0, 0, 0, 32'h12345004);

        mode = 1;
        satp = 32'h80000001;
        access(32'h00403044, 0, 0, 0, 32'h00300044);
        if (walk_reads != 2) begin
            $error("4 KiB walk used %0d PTE reads", walk_reads);
            failures = failures + 1;
        end
        access(32'h00403048, 0, 0, 0, 32'h00300048);
        if (walk_reads != 2) begin
            $error("TLB hit unexpectedly walked page tables");
            failures = failures + 1;
        end

        flush = 1'b1;
        @(negedge clk);
        flush = 1'b0;
        mode = 2;
        access(32'h00801234, 0, 0, 0, 32'h00401234);

        flush = 1'b1;
        @(negedge clk);
        flush = 1'b0;
        mode = 1;
        access(32'h00403044, 0, 1, 1, 32'd0);

        flush = 1'b1;
        @(negedge clk);
        flush = 1'b0;
        mode = 3;
        access(32'h00403044, 1, 0, 0, 32'h00300044);
        if (ad_writes != 1) begin
            $error("expected one A/D PTE write, got %0d", ad_writes);
            failures = failures + 1;
        end

        if (failures == 0) $display("PASS: sv32_mmu");
        else $fatal(1, "FAIL: sv32_mmu (%0d failures)", failures);
        $finish;
    end
endmodule
