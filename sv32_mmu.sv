`timescale 1ns / 1ps

module sv32_mmu #(
    parameter integer TLB_ENTRIES = 8
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        flush,
    input  logic        request_valid,
    output logic        request_ready,
    input  logic [31:0] virtual_address,
    input  logic        request_write,
    input  logic        request_execute,
    input  logic [31:0] request_write_data,
    input  logic [3:0]  request_write_strobe,
    input  logic [1:0]  privilege,
    input  logic        sum,
    input  logic        mxr,
    input  logic [31:0] satp,
    output logic        response_valid,
    output logic [31:0] response_read_data,
    output logic        response_page_fault,
    output logic        response_access_fault,
    output logic        physical_valid,
    output logic        physical_write,
    output logic [31:0] physical_address,
    output logic [31:0] physical_write_data,
    output logic [3:0]  physical_write_strobe,
    input  logic        physical_ready,
    input  logic [31:0] physical_read_data,
    input  logic        physical_error
);
    import rv32imac_pkg::*;
    typedef enum logic [2:0] {
        IDLE, ACCESS, WALK_L1, WALK_L0, WALK_AD, COMPLETE
    } state_t;
    state_t state;

    logic tlb_valid [0:TLB_ENTRIES-1];
    logic tlb_superpage [0:TLB_ENTRIES-1];
    logic [19:0] tlb_vpn [0:TLB_ENTRIES-1];
    logic [21:0] tlb_ppn [0:TLB_ENTRIES-1];
    logic [7:0] tlb_flags [0:TLB_ENTRIES-1];
    logic [$clog2(TLB_ENTRIES)-1:0] replacement_index;

    logic [31:0] saved_vaddr, saved_wdata;
    logic [3:0] saved_wstrb;
    logic saved_write, saved_execute;
    logic [1:0] saved_privilege;
    logic saved_sum, saved_mxr;
    logic [31:0] pte_address, pte_value, translated_address;
    logic [21:0] leaf_ppn;
    logic [7:0] leaf_flags;
    logic leaf_superpage;
    logic tlb_hit;
    logic [$clog2(TLB_ENTRIES)-1:0] tlb_hit_index;

    function automatic logic permission_fault(
        input logic [7:0] flags,
        input logic write_access,
        input logic execute_access,
        input logic [1:0] access_privilege,
        input logic allow_sum,
        input logic allow_mxr
    );
        logic readable;
        begin
            readable = flags[1] || (allow_mxr && flags[3]);
            permission_fault = !flags[0] || (!flags[1] && flags[2]) ||
                (execute_access && !flags[3]) ||
                (write_access && !flags[2]) ||
                (!write_access && !execute_access && !readable) ||
                (access_privilege == PRIV_U && !flags[4]) ||
                (access_privilege == PRIV_S && flags[4] && (execute_access || !allow_sum));
        end
    endfunction

    always_comb begin
        tlb_hit = 1'b0;
        tlb_hit_index = '0;
        for (integer i = 0; i < TLB_ENTRIES; i++) begin
            if (tlb_valid[i] &&
                ((!tlb_superpage[i] && tlb_vpn[i] == virtual_address[31:12]) ||
                 (tlb_superpage[i] && tlb_vpn[i][19:10] == virtual_address[31:22]))) begin
                tlb_hit = 1'b1;
                tlb_hit_index = i[$clog2(TLB_ENTRIES)-1:0];
            end
        end
    end

    always_comb begin
        request_ready = state == IDLE;
        response_valid = state == COMPLETE;
        physical_valid = 1'b0;
        physical_write = 1'b0;
        physical_address = 32'd0;
        physical_write_data = saved_wdata;
        physical_write_strobe = saved_wstrb;
        unique case (state)
            ACCESS: begin
                physical_valid = 1'b1;
                physical_write = saved_write;
                physical_address = translated_address;
            end
            WALK_L1, WALK_L0: begin
                physical_valid = 1'b1;
                physical_address = pte_address;
                physical_write_strobe = 4'b0000;
            end
            WALK_AD: begin
                physical_valid = 1'b1;
                physical_write = 1'b1;
                physical_address = pte_address;
                physical_write_data = pte_value | 32'h00000040 |
                                      (saved_write ? 32'h00000080 : 32'd0);
                physical_write_strobe = 4'b1111;
            end
            default: begin end
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            response_read_data <= 32'd0;
            response_page_fault <= 1'b0;
            response_access_fault <= 1'b0;
            replacement_index <= '0;
            for (integer i = 0; i < TLB_ENTRIES; i++) tlb_valid[i] <= 1'b0;
        end else begin
            if (flush) for (integer i = 0; i < TLB_ENTRIES; i++) tlb_valid[i] <= 1'b0;
            unique case (state)
                IDLE: if (request_valid) begin
                    saved_vaddr <= virtual_address;
                    saved_write <= request_write;
                    saved_execute <= request_execute;
                    saved_wdata <= request_write_data;
                    saved_wstrb <= request_write_strobe;
                    saved_privilege <= privilege;
                    saved_sum <= sum;
                    saved_mxr <= mxr;
                    response_page_fault <= 1'b0;
                    response_access_fault <= 1'b0;
                    if (!satp[31] || privilege == PRIV_M) begin
                        translated_address <= virtual_address;
                        state <= ACCESS;
                    end else if (tlb_hit) begin
                        if (permission_fault(tlb_flags[tlb_hit_index], request_write,
                                             request_execute, privilege, sum, mxr)) begin
                            response_page_fault <= 1'b1;
                            state <= COMPLETE;
                        end else begin
                            translated_address <= tlb_superpage[tlb_hit_index]
                                ? {tlb_ppn[tlb_hit_index][21:10], virtual_address[21:0]}
                                : {tlb_ppn[tlb_hit_index][19:0], virtual_address[11:0]};
                            state <= ACCESS;
                        end
                    end else begin
                        pte_address <= {satp[21:0], 12'd0} +
                                       {virtual_address[31:22], 2'b00};
                        state <= WALK_L1;
                    end
                end
                WALK_L1, WALK_L0: if (physical_ready) begin
                    if (physical_error) begin
                        response_access_fault <= 1'b1;
                        state <= COMPLETE;
                    end else begin
                        pte_value <= physical_read_data;
                        if (!physical_read_data[0] ||
                            (!physical_read_data[1] && physical_read_data[2])) begin
                            response_page_fault <= 1'b1;
                            state <= COMPLETE;
                        end else if (physical_read_data[1] || physical_read_data[3]) begin
                            if ((state == WALK_L1 && physical_read_data[19:10] != 0) ||
                                permission_fault(physical_read_data[7:0], saved_write,
                                                 saved_execute, saved_privilege,
                                                 saved_sum, saved_mxr)) begin
                                response_page_fault <= 1'b1;
                                state <= COMPLETE;
                            end else begin
                                leaf_ppn <= physical_read_data[31:10];
                                leaf_flags <= physical_read_data[7:0];
                                leaf_superpage <= state == WALK_L1;
                                translated_address <= state == WALK_L1
                                    ? {physical_read_data[31:20], saved_vaddr[21:0]}
                                    : {physical_read_data[29:10], saved_vaddr[11:0]};
                                if (!physical_read_data[6] ||
                                    (saved_write && !physical_read_data[7]))
                                    state <= WALK_AD;
                                else begin
                                    tlb_valid[replacement_index] <= 1'b1;
                                    tlb_superpage[replacement_index] <= state == WALK_L1;
                                    tlb_vpn[replacement_index] <= saved_vaddr[31:12];
                                    tlb_ppn[replacement_index] <= physical_read_data[31:10];
                                    tlb_flags[replacement_index] <= physical_read_data[7:0];
                                    replacement_index <= replacement_index + 1'b1;
                                    state <= ACCESS;
                                end
                            end
                        end else if (state == WALK_L1) begin
                            pte_address <= {physical_read_data[31:10], 12'd0} +
                                           {saved_vaddr[21:12], 2'b00};
                            state <= WALK_L0;
                        end else begin
                            response_page_fault <= 1'b1;
                            state <= COMPLETE;
                        end
                    end
                end
                WALK_AD: if (physical_ready) begin
                    if (physical_error) response_access_fault <= 1'b1;
                    else begin
                        tlb_valid[replacement_index] <= 1'b1;
                        tlb_superpage[replacement_index] <= leaf_superpage;
                        tlb_vpn[replacement_index] <= saved_vaddr[31:12];
                        tlb_ppn[replacement_index] <= leaf_ppn;
                        tlb_flags[replacement_index] <= leaf_flags | 8'h40 |
                                                        (saved_write ? 8'h80 : 8'd0);
                        replacement_index <= replacement_index + 1'b1;
                    end
                    if (physical_error) state <= COMPLETE;
                    else state <= ACCESS;
                end
                ACCESS: if (physical_ready) begin
                    response_read_data <= physical_read_data;
                    response_access_fault <= physical_error;
                    state <= COMPLETE;
                end
                COMPLETE: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
