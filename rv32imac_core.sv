`timescale 1ns / 1ps

module rv32imac_core #(
    parameter logic [31:0] RESET_VECTOR = 32'h00000000,
    parameter logic [31:0] HART_ID = 32'd0
) (
    input  logic        clk,
    input  logic        reset,
    output logic        memory_valid,
    output logic        memory_write,
    output logic [31:0] memory_address,
    output logic [31:0] memory_write_data,
    output logic [3:0]  memory_write_strobe,
    input  logic        memory_ready,
    input  logic [31:0] memory_read_data,
    input  logic        memory_error,
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
    import rv32imac_pkg::*;

    typedef enum logic [4:0] {
        FETCH_REQUEST, FETCH_WAIT, FETCH_CROSS_REQUEST, FETCH_CROSS_WAIT,
        EXECUTE, DATA_REQUEST, DATA_WAIT, MULDIV_WAIT,
        AMO_WRITE_REQUEST, AMO_WRITE_WAIT, WFI_WAIT
    } state_t;
    state_t state;
    privilege_t privilege_mode;
    logic [31:0] registers [0:31];
    logic [31:0] pc, instruction, fetch_word, next_pc;
    logic [1:0] instruction_length;
    logic instruction_compressed, compressed_illegal;
    logic [31:0] decompressed_instruction;

    logic [31:0] mstatus, medeleg, mideleg, mie, mtvec, mscratch;
    logic [31:0] mepc, mcause, mtval, mcounteren;
    logic [31:0] stvec, sscratch, sepc, scause, stval, scounteren, satp;
    logic [63:0] cycle_counter, instret_counter;
    logic sfence_flush;

    logic mmu_request_valid, mmu_request_ready, mmu_request_write, mmu_request_execute;
    logic [31:0] mmu_virtual_address, mmu_request_wdata;
    logic [3:0] mmu_request_wstrb;
    logic mmu_response_valid, mmu_page_fault, mmu_access_fault;
    logic [31:0] mmu_response_rdata;

    logic muldiv_start, muldiv_busy, muldiv_done;
    logic [2:0] muldiv_operation;
    logic [31:0] muldiv_result;

    logic pending_write, pending_execute;
    logic [31:0] pending_address, pending_wdata;
    logic [3:0] pending_wstrb;
    logic [4:0] pending_rd;
    logic [2:0] pending_funct3;
    logic [1:0] pending_offset;
    logic [2:0] pending_memory_kind;
    logic [31:0] amo_old_value, amo_new_value;
    logic [4:0] amo_rd;
    logic reservation_valid;
    logic [31:0] reservation_address;
    logic debug_step_active, debug_halt_pending;
    logic trap_entered;

    localparam logic [2:0] MEM_FETCH = 3'd0, MEM_LOAD = 3'd1, MEM_STORE = 3'd2,
                             MEM_LR = 3'd3, MEM_SC = 3'd4, MEM_AMO = 3'd5;

    wire logic [6:0] opcode = instruction[6:0];
    wire logic [2:0] funct3 = instruction[14:12];
    wire logic [6:0] funct7 = instruction[31:25];
    wire logic [4:0] rd = instruction[11:7];
    wire logic [4:0] rs1 = instruction[19:15];
    wire logic [4:0] rs2 = instruction[24:20];
    wire logic [31:0] rs1_value = rs1 == 0 ? 32'd0 : registers[rs1];
    wire logic [31:0] rs2_value = rs2 == 0 ? 32'd0 : registers[rs2];
    wire logic [31:0] imm_i = {{20{instruction[31]}}, instruction[31:20]};
    wire logic [31:0] imm_s = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
    wire logic [31:0] imm_b = {{19{instruction[31]}}, instruction[31], instruction[7],
                               instruction[30:25], instruction[11:8], 1'b0};
    wire logic [31:0] imm_u = {instruction[31:12], 12'd0};
    wire logic [31:0] imm_j = {{11{instruction[31]}}, instruction[31],
                               instruction[19:12], instruction[20], instruction[30:21], 1'b0};
    wire logic [31:0] mip_value = {20'd0, irq_external_m, 1'd0, irq_external_s,
                                   1'd0, irq_timer_m, 1'd0, irq_timer_s,
                                   1'd0, irq_software_m, 1'd0, irq_software_s, 1'd0};
    wire logic [31:0] enabled_pending = mie & mip_value;
    wire logic interrupt_available = |enabled_pending;
    wire logic [15:0] compressed_halfword =
        pc[1] ? fetch_word[31:16] : fetch_word[15:0];
    wire logic [31:0] data_effective_address =
        rs1_value + (opcode == 7'b0000011 ? imm_i : imm_s);

    rv32c_decoder compressed_decoder (
        .compressed(compressed_halfword),
        .instruction(decompressed_instruction),
        .illegal(compressed_illegal)
    );

    rv32_muldiv muldiv (
        .clk(clk), .reset(reset), .start(muldiv_start), .operation(muldiv_operation),
        .operand_a(rs1_value), .operand_b(rs2_value), .busy(muldiv_busy),
        .done(muldiv_done), .result(muldiv_result)
    );

    sv32_mmu mmu (
        .clk(clk), .reset(reset), .flush(sfence_flush),
        .request_valid(mmu_request_valid), .request_ready(mmu_request_ready),
        .virtual_address(mmu_virtual_address), .request_write(mmu_request_write),
        .request_execute(mmu_request_execute), .request_write_data(mmu_request_wdata),
        .request_write_strobe(mmu_request_wstrb), .privilege(privilege_mode),
        .sum(mstatus[18]), .mxr(mstatus[19]), .satp(satp),
        .response_valid(mmu_response_valid), .response_read_data(mmu_response_rdata),
        .response_page_fault(mmu_page_fault), .response_access_fault(mmu_access_fault),
        .physical_valid(memory_valid), .physical_write(memory_write),
        .physical_address(memory_address), .physical_write_data(memory_write_data),
        .physical_write_strobe(memory_write_strobe), .physical_ready(memory_ready),
        .physical_read_data(memory_read_data), .physical_error(memory_error)
    );

    assign debug_program_counter = pc;
    assign debug_register_data = debug_register_index == 0 ? 32'd0 :
                                 registers[debug_register_index];

    function automatic logic [31:0] csr_read(input logic [11:0] address);
        logic [31:0] sstatus_mask;
        begin
            sstatus_mask = 32'h000de122;
            unique case (address)
                CSR_SSTATUS: csr_read = mstatus & sstatus_mask;
                CSR_SIE: csr_read = mie & mideleg;
                CSR_STVEC: csr_read = stvec;
                CSR_SCOUNTEREN: csr_read = scounteren;
                CSR_SSCRATCH: csr_read = sscratch;
                CSR_SEPC: csr_read = sepc;
                CSR_SCAUSE: csr_read = scause;
                CSR_STVAL: csr_read = stval;
                CSR_SIP: csr_read = mip_value & mideleg;
                CSR_SATP: csr_read = satp;
                CSR_MSTATUS: csr_read = mstatus;
                CSR_MISA: csr_read = MISA_VALUE;
                CSR_MEDELEG: csr_read = medeleg;
                CSR_MIDELEG: csr_read = mideleg;
                CSR_MIE: csr_read = mie;
                CSR_MTVEC: csr_read = mtvec;
                CSR_MCOUNTEREN: csr_read = mcounteren;
                CSR_MSCRATCH: csr_read = mscratch;
                CSR_MEPC: csr_read = mepc;
                CSR_MCAUSE: csr_read = mcause;
                CSR_MTVAL: csr_read = mtval;
                CSR_MIP: csr_read = mip_value;
                CSR_MCYCLE, CSR_CYCLE: csr_read = cycle_counter[31:0];
                CSR_MINSTRET, CSR_INSTRET: csr_read = instret_counter[31:0];
                CSR_TIME: csr_read = time_value[31:0];
                CSR_MHARTID: csr_read = HART_ID;
                CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID,
                CSR_MCONFIGPTR: csr_read = 32'd0;
                default: csr_read = 32'd0;
            endcase
        end
    endfunction

    function automatic logic csr_exists(input logic [11:0] address);
        begin
            unique case (address)
                CSR_SSTATUS, CSR_SIE, CSR_STVEC, CSR_SCOUNTEREN, CSR_SSCRATCH,
                CSR_SEPC, CSR_SCAUSE, CSR_STVAL, CSR_SIP, CSR_SATP,
                CSR_MSTATUS, CSR_MISA, CSR_MEDELEG, CSR_MIDELEG, CSR_MIE,
                CSR_MTVEC, CSR_MCOUNTEREN, CSR_MSCRATCH, CSR_MEPC, CSR_MCAUSE,
                CSR_MTVAL, CSR_MIP, CSR_MCYCLE, CSR_MINSTRET, CSR_CYCLE,
                CSR_TIME, CSR_INSTRET, CSR_MVENDORID, CSR_MARCHID,
                CSR_MIMPID, CSR_MHARTID, CSR_MCONFIGPTR: csr_exists = 1'b1;
                default: csr_exists = 1'b0;
            endcase
        end
    endfunction

    function automatic logic csr_access_illegal(
        input logic [11:0] address,
        input logic write_access
    );
        logic counter_allowed;
        begin
            counter_allowed = address[11:8] != 4'hc ||
                privilege_mode == PRIV_M ||
                (privilege_mode == PRIV_S && mcounteren[address[1:0]]) ||
                (privilege_mode == PRIV_U && mcounteren[address[1:0]] &&
                 scounteren[address[1:0]]);
            csr_access_illegal = !csr_exists(address) ||
                privilege_mode < address[9:8] ||
                (write_access && address[11:10] == 2'b11) ||
                !counter_allowed;
        end
    endfunction

    task automatic write_csr(input logic [11:0] address, input logic [31:0] value);
        logic [31:0] sstatus_mask;
        begin
            sstatus_mask = 32'h000de122;
            unique case (address)
                CSR_SSTATUS: mstatus <= (mstatus & ~sstatus_mask) | (value & sstatus_mask);
                CSR_SIE: mie <= (mie & ~mideleg) | (value & mideleg);
                CSR_STVEC: stvec <= {value[31:2], value[1:0] == 2'b01 ? 2'b01 : 2'b00};
                CSR_SCOUNTEREN: scounteren <= value;
                CSR_SSCRATCH: sscratch <= value;
                CSR_SEPC: sepc <= {value[31:1], 1'b0};
                CSR_SCAUSE: scause <= value;
                CSR_STVAL: stval <= value;
                CSR_SIP: begin end
                CSR_SATP: begin satp <= value & 32'h803fffff; sfence_flush <= 1'b1; end
                CSR_MSTATUS: mstatus <= value & 32'h007ff9aa;
                CSR_MEDELEG: medeleg <= value & 32'h0000b3ff;
                CSR_MIDELEG: mideleg <= value & 32'h00000222;
                CSR_MIE: mie <= value & 32'h00000aaa;
                CSR_MTVEC: mtvec <= {value[31:2], value[1:0] == 2'b01 ? 2'b01 : 2'b00};
                CSR_MCOUNTEREN: mcounteren <= value;
                CSR_MSCRATCH: mscratch <= value;
                CSR_MEPC: mepc <= {value[31:1], 1'b0};
                CSR_MCAUSE: mcause <= value;
                CSR_MTVAL: mtval <= value;
                CSR_MCYCLE: cycle_counter[31:0] <= value;
                CSR_MINSTRET: instret_counter[31:0] <= value;
                default: begin end
            endcase
        end
    endtask

    task automatic enter_trap(
        input logic [31:0] cause,
        input logic [31:0] trap_value,
        input logic [31:0] trap_pc
    );
        logic delegated;
        logic [4:0] cause_index;
        logic is_interrupt;
        logic [31:0] vector;
        begin
            trap_entered = 1'b1;
            is_interrupt = cause[31];
            cause_index = cause[4:0];
            delegated = privilege_mode != PRIV_M &&
                (is_interrupt ? mideleg[cause_index] : medeleg[cause_index]);
            if (delegated) begin
                sepc <= {trap_pc[31:1], 1'b0};
                scause <= cause;
                stval <= trap_value;
                mstatus[8] <= privilege_mode == PRIV_S;
                mstatus[5] <= mstatus[1];
                mstatus[1] <= 1'b0;
                privilege_mode <= PRIV_S;
                vector = {stvec[31:2], 2'b00};
                if (is_interrupt && stvec[1:0] == 2'b01)
                    vector = vector + {cause_index, 2'b00};
                pc <= vector;
            end else begin
                mepc <= {trap_pc[31:1], 1'b0};
                mcause <= cause;
                mtval <= trap_value;
                mstatus[12:11] <= privilege_mode;
                mstatus[7] <= mstatus[3];
                mstatus[3] <= 1'b0;
                privilege_mode <= PRIV_M;
                vector = {mtvec[31:2], 2'b00};
                if (is_interrupt && mtvec[1:0] == 2'b01)
                    vector = vector + {cause_index, 2'b00};
                pc <= vector;
            end
            reservation_valid <= 1'b0;
            state <= FETCH_REQUEST;
        end
    endtask

    function automatic logic [31:0] selected_interrupt_cause;
        begin
            if (enabled_pending[11]) selected_interrupt_cause = IRQ_EXTERNAL_M;
            else if (enabled_pending[3]) selected_interrupt_cause = IRQ_SOFTWARE_M;
            else if (enabled_pending[7]) selected_interrupt_cause = IRQ_TIMER_M;
            else if (enabled_pending[9]) selected_interrupt_cause = IRQ_EXTERNAL_S;
            else if (enabled_pending[1]) selected_interrupt_cause = IRQ_SOFTWARE_S;
            else selected_interrupt_cause = IRQ_TIMER_S;
        end
    endfunction

    function automatic logic interrupt_enabled_now(input logic [31:0] cause);
        logic delegated;
        begin
            delegated = mideleg[cause[4:0]];
            if (delegated)
                interrupt_enabled_now = privilege_mode < PRIV_S ||
                                        (privilege_mode == PRIV_S && mstatus[1]);
            else
                interrupt_enabled_now = privilege_mode < PRIV_M ||
                                        (privilege_mode == PRIV_M && mstatus[3]);
        end
    endfunction

    always_comb begin
        mmu_request_valid = 1'b0;
        mmu_request_write = pending_write;
        mmu_request_execute = pending_execute;
        mmu_virtual_address = pending_address;
        mmu_request_wdata = pending_wdata;
        mmu_request_wstrb = pending_wstrb;
        muldiv_start = 1'b0;
        muldiv_operation = funct3;
        if (state == FETCH_REQUEST) begin
            mmu_virtual_address = {pc[31:2], 2'b00};
            mmu_request_write = 1'b0;
            mmu_request_execute = 1'b1;
            mmu_request_wstrb = 4'd0;
        end else if (state == AMO_WRITE_REQUEST) begin
            mmu_request_wdata = amo_new_value;
        end
        if (state == FETCH_REQUEST || state == FETCH_CROSS_REQUEST ||
            state == DATA_REQUEST || state == AMO_WRITE_REQUEST)
            mmu_request_valid = 1'b1;
        if (state == EXECUTE && opcode == 7'b0110011 && funct7 == 7'b0000001)
            muldiv_start = !muldiv_busy;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= FETCH_REQUEST;
            privilege_mode <= PRIV_M;
            pc <= RESET_VECTOR;
            instruction <= 32'h00000013;
            instruction_length <= 2'd0;
            instruction_compressed <= 1'b0;
            mstatus <= 32'd0;
            medeleg <= 32'd0;
            mideleg <= 32'd0;
            mie <= 32'd0;
            mtvec <= 32'd0;
            mscratch <= 32'd0;
            mepc <= 32'd0;
            mcause <= 32'd0;
            mtval <= 32'd0;
            mcounteren <= 32'd0;
            stvec <= 32'd0;
            sscratch <= 32'd0;
            sepc <= 32'd0;
            scause <= 32'd0;
            stval <= 32'd0;
            scounteren <= 32'd0;
            satp <= 32'd0;
            cycle_counter <= 64'd0;
            instret_counter <= 64'd0;
            sfence_flush <= 1'b0;
            debug_halted <= 1'b0;
            debug_step_active <= 1'b0;
            debug_halt_pending <= 1'b0;
            trap_entered = 1'b0;
            reservation_valid <= 1'b0;
            pending_address <= 32'd0;
            pending_write <= 1'b0;
            pending_execute <= 1'b0;
            pending_wdata <= 32'd0;
            pending_wstrb <= 4'd0;
            for (integer i = 0; i < 32; i++) registers[i] <= 32'd0;
        end else begin
            trap_entered = 1'b0;
            cycle_counter <= cycle_counter + 1'b1;
            sfence_flush <= 1'b0;
            registers[0] <= 32'd0;
            if (debug_halt_request) debug_halt_pending <= 1'b1;
            if (debug_halted) begin
                if (debug_resume_request) begin
                    debug_halted <= 1'b0;
                    state <= FETCH_REQUEST;
                end else if (debug_step_request) begin
                    debug_halted <= 1'b0;
                    debug_step_active <= 1'b1;
                    state <= FETCH_REQUEST;
                end else if (debug_register_write && debug_register_index != 0) begin
                    registers[debug_register_index] <= debug_register_write_data;
                end
            end else unique case (state)
                FETCH_REQUEST: begin
                    logic [31:0] irq_cause;
                    irq_cause = selected_interrupt_cause();
                    if (debug_step_active) begin
                        debug_halted <= 1'b1;
                        debug_step_active <= 1'b0;
                    end else if (debug_halt_pending || debug_halt_request) begin
                        debug_halted <= 1'b1;
                        debug_halt_pending <= 1'b0;
                    end else if (interrupt_available && interrupt_enabled_now(irq_cause)) begin
                        enter_trap(irq_cause, 32'd0, pc);
                    end else if (pc[0]) begin
                        enter_trap(CAUSE_INST_MISALIGNED, pc, pc);
                    end else begin
                        pending_address <= {pc[31:2], 2'b00};
                        pending_execute <= 1'b1;
                        pending_write <= 1'b0;
                        pending_wstrb <= 4'd0;
                        if (mmu_request_ready) state <= FETCH_WAIT;
                    end
                end
                FETCH_WAIT: if (mmu_response_valid) begin
                    if (mmu_page_fault) enter_trap(CAUSE_INST_PAGE, pc, pc);
                    else if (mmu_access_fault) enter_trap(CAUSE_INST_ACCESS, pc, pc);
                    else begin
                        fetch_word <= mmu_response_rdata;
                        if ((pc[1] ? mmu_response_rdata[17:16] : mmu_response_rdata[1:0]) != 2'b11) begin
                            instruction <= pc[1] ? {16'd0, mmu_response_rdata[31:16]} :
                                                 {16'd0, mmu_response_rdata[15:0]};
                            instruction_length <= 2'd2;
                            instruction_compressed <= 1'b1;
                            state <= EXECUTE;
                        end else if (!pc[1]) begin
                            instruction <= mmu_response_rdata;
                            instruction_length <= 2'd0; // encoding for four bytes
                            instruction_compressed <= 1'b0;
                            state <= EXECUTE;
                        end else begin
                            pending_address <= {pc[31:2], 2'b00} + 32'd4;
                            state <= FETCH_CROSS_REQUEST;
                        end
                    end
                end
                FETCH_CROSS_REQUEST: if (mmu_request_ready) state <= FETCH_CROSS_WAIT;
                FETCH_CROSS_WAIT: if (mmu_response_valid) begin
                    if (mmu_page_fault) enter_trap(CAUSE_INST_PAGE, pc + 32'd2, pc);
                    else if (mmu_access_fault) enter_trap(CAUSE_INST_ACCESS, pc + 32'd2, pc);
                    else begin
                        instruction <= {mmu_response_rdata[15:0], fetch_word[31:16]};
                        instruction_length <= 2'd0;
                        instruction_compressed <= 1'b0;
                        state <= EXECUTE;
                    end
                end
                EXECUTE: begin : execute_block
                    logic [31:0] effective_instruction;
                    logic [31:0] sequential_pc;
                    logic illegal_instruction;
                    logic retired;
                    logic branch_taken;
                    logic [31:0] csr_old, csr_source, csr_new;
                    logic csr_write_access;
                    effective_instruction = instruction;
                    sequential_pc = pc + (instruction_length == 2 ? 32'd2 : 32'd4);
                    illegal_instruction = 1'b0;
                    retired = 1'b1;
                    branch_taken = 1'b0;
                    instruction <= effective_instruction;
                    if (instruction_compressed) begin
                        if (compressed_illegal) enter_trap(CAUSE_ILLEGAL, instruction, pc);
                        else begin
                            instruction <= decompressed_instruction;
                            instruction_compressed <= 1'b0;
                            state <= EXECUTE;
                        end
                    end else unique case (effective_instruction[6:0])
                        7'b0110111: begin registers[effective_instruction[11:7]] <=
                            {effective_instruction[31:12], 12'd0}; pc <= sequential_pc; state <= FETCH_REQUEST; end
                        7'b0010111: begin registers[effective_instruction[11:7]] <=
                            pc + {effective_instruction[31:12], 12'd0}; pc <= sequential_pc; state <= FETCH_REQUEST; end
                        7'b1101111: begin
                            if (effective_instruction[11:7] != 0)
                                registers[effective_instruction[11:7]] <= sequential_pc;
                            pc <= pc + imm_j; state <= FETCH_REQUEST;
                        end
                        7'b1100111: begin
                            if (funct3 != 0) enter_trap(CAUSE_ILLEGAL, effective_instruction, pc);
                            else begin
                                if (rd != 0) registers[rd] <= sequential_pc;
                                pc <= (rs1_value + imm_i) & 32'hfffffffe;
                                state <= FETCH_REQUEST;
                            end
                        end
                        7'b1100011: begin
                            unique case (funct3)
                                3'b000: branch_taken = rs1_value == rs2_value;
                                3'b001: branch_taken = rs1_value != rs2_value;
                                3'b100: branch_taken = $signed(rs1_value) < $signed(rs2_value);
                                3'b101: branch_taken = $signed(rs1_value) >= $signed(rs2_value);
                                3'b110: branch_taken = rs1_value < rs2_value;
                                3'b111: branch_taken = rs1_value >= rs2_value;
                                default: illegal_instruction = 1'b1;
                            endcase
                            if (illegal_instruction) enter_trap(CAUSE_ILLEGAL, effective_instruction, pc);
                            else begin pc <= branch_taken ? pc + imm_b : sequential_pc; state <= FETCH_REQUEST; end
                        end
                        7'b0010011: begin
                            unique case (funct3)
                                3'b000: if (rd != 0) registers[rd] <= rs1_value + imm_i;
                                3'b010: if (rd != 0) registers[rd] <= $signed(rs1_value) < $signed(imm_i);
                                3'b011: if (rd != 0) registers[rd] <= rs1_value < imm_i;
                                3'b100: if (rd != 0) registers[rd] <= rs1_value ^ imm_i;
                                3'b110: if (rd != 0) registers[rd] <= rs1_value | imm_i;
                                3'b111: if (rd != 0) registers[rd] <= rs1_value & imm_i;
                                3'b001: begin
                                    if (effective_instruction[31:25] != 0)
                                        illegal_instruction = 1'b1;
                                    else if (rd != 0)
                                        registers[rd] <= rs1_value << effective_instruction[24:20];
                                end
                                3'b101: begin
                                    if (effective_instruction[31:25] == 0) begin
                                        if (rd != 0) registers[rd] <= rs1_value >> effective_instruction[24:20];
                                    end else if (effective_instruction[31:25] == 7'b0100000) begin
                                        if (rd != 0) registers[rd] <= $signed(rs1_value) >>> effective_instruction[24:20];
                                    end else illegal_instruction = 1'b1;
                                end
                            endcase
                            if (illegal_instruction)
                                enter_trap(CAUSE_ILLEGAL, effective_instruction, pc);
                            else begin pc <= sequential_pc; state <= FETCH_REQUEST; end
                        end
                        7'b0110011: if (funct7 == 7'b0000001) begin
                            pending_rd <= rd;
                            next_pc <= sequential_pc;
                            state <= MULDIV_WAIT;
                            retired = 1'b0;
                        end else begin
                            if (rd != 0) unique case ({funct7, funct3})
                                {7'b0000000,3'b000}: registers[rd] <= rs1_value + rs2_value;
                                {7'b0100000,3'b000}: registers[rd] <= rs1_value - rs2_value;
                                {7'b0000000,3'b001}: registers[rd] <= rs1_value << rs2_value[4:0];
                                {7'b0000000,3'b010}: registers[rd] <= $signed(rs1_value) < $signed(rs2_value);
                                {7'b0000000,3'b011}: registers[rd] <= rs1_value < rs2_value;
                                {7'b0000000,3'b100}: registers[rd] <= rs1_value ^ rs2_value;
                                {7'b0000000,3'b101}: registers[rd] <= rs1_value >> rs2_value[4:0];
                                {7'b0100000,3'b101}: registers[rd] <= $signed(rs1_value) >>> rs2_value[4:0];
                                {7'b0000000,3'b110}: registers[rd] <= rs1_value | rs2_value;
                                {7'b0000000,3'b111}: registers[rd] <= rs1_value & rs2_value;
                                default: illegal_instruction = 1'b1;
                            endcase
                            if (illegal_instruction) enter_trap(CAUSE_ILLEGAL, effective_instruction, pc);
                            else begin pc <= sequential_pc; state <= FETCH_REQUEST; end
                        end
                        7'b0000011, 7'b0100011: begin
                            pending_address <= data_effective_address;
                            pending_write <= effective_instruction[6:0] == 7'b0100011;
                            pending_execute <= 1'b0;
                            pending_rd <= rd;
                            pending_funct3 <= funct3;
                            pending_offset <= data_effective_address[1:0];
                            pending_memory_kind <= effective_instruction[6:0] == 7'b0000011 ? MEM_LOAD : MEM_STORE;
                            next_pc <= sequential_pc;
                            if (effective_instruction[6:0] == 7'b0100011) begin
                                unique case (funct3)
                                    3'b000: begin pending_wdata <= rs2_value << (8 * data_effective_address[1:0]); pending_wstrb <= 4'b0001 << data_effective_address[1:0]; end
                                    3'b001: begin pending_wdata <= rs2_value << (16 * data_effective_address[1]); pending_wstrb <= 4'b0011 << {data_effective_address[1],1'b0}; end
                                    3'b010: begin pending_wdata <= rs2_value; pending_wstrb <= 4'b1111; end
                                    default: illegal_instruction = 1'b1;
                                endcase
                            end else pending_wstrb <= 4'd0;
                            if ((funct3 == 3'b001 || funct3 == 3'b101) && data_effective_address[0])
                                enter_trap(effective_instruction[6:0] == 7'b0000011 ? CAUSE_LOAD_MISALIGNED : CAUSE_STORE_MISALIGNED, data_effective_address, pc);
                            else if (funct3 == 3'b010 && |data_effective_address[1:0])
                                enter_trap(effective_instruction[6:0] == 7'b0000011 ? CAUSE_LOAD_MISALIGNED : CAUSE_STORE_MISALIGNED, data_effective_address, pc);
                            else if (illegal_instruction) enter_trap(CAUSE_ILLEGAL, effective_instruction, pc);
                            else begin state <= DATA_REQUEST; retired = 1'b0; end
                        end
                        7'b0101111: begin // RV32A word operations
                            if (funct3 != 3'b010 || |rs1_value[1:0]) begin
                                enter_trap(|rs1_value[1:0] ? CAUSE_STORE_MISALIGNED : CAUSE_ILLEGAL,
                                           |rs1_value[1:0] ? rs1_value : effective_instruction, pc);
                            end else if (effective_instruction[31:27] == 5'b00011) begin // SC.W
                                if (!reservation_valid || reservation_address != rs1_value) begin
                                    if (rd != 0) registers[rd] <= 32'd1;
                                    pc <= sequential_pc; state <= FETCH_REQUEST;
                                end else begin
                                    pending_address <= rs1_value; pending_write <= 1'b1;
                                    pending_execute <= 1'b0; pending_wdata <= rs2_value;
                                    pending_wstrb <= 4'b1111; pending_rd <= rd;
                                    pending_memory_kind <= MEM_SC; next_pc <= sequential_pc;
                                    reservation_valid <= 1'b0; state <= DATA_REQUEST; retired = 1'b0;
                                end
                            end else begin
                                pending_address <= rs1_value; pending_write <= 1'b0;
                                pending_execute <= 1'b0; pending_wstrb <= 4'd0;
                                pending_rd <= rd; amo_rd <= rd; next_pc <= sequential_pc;
                                pending_memory_kind <= effective_instruction[31:27] == 5'b00010 ? MEM_LR : MEM_AMO;
                                state <= DATA_REQUEST; retired = 1'b0;
                            end
                        end
                        7'b0001111: begin // FENCE / FENCE.I
                            pc <= sequential_pc; state <= FETCH_REQUEST;
                        end
                        7'b1110011: begin
                            if (effective_instruction == 32'h00000073) begin
                                enter_trap(privilege_mode == PRIV_M ? CAUSE_ECALL_M :
                                           privilege_mode == PRIV_S ? CAUSE_ECALL_S : CAUSE_ECALL_U, 0, pc);
                            end else if (effective_instruction == 32'h00100073) begin
                                enter_trap(CAUSE_BREAKPOINT, pc, pc);
                            end else if (effective_instruction == 32'h30200073) begin
                                if (privilege_mode != PRIV_M) enter_trap(CAUSE_ILLEGAL, effective_instruction, pc);
                                else begin
                                    privilege_mode <= privilege_t'(mstatus[12:11]);
                                    mstatus[3] <= mstatus[7]; mstatus[7] <= 1'b1;
                                    mstatus[12:11] <= PRIV_U; pc <= mepc; state <= FETCH_REQUEST;
                                end
                            end else if (effective_instruction == 32'h10200073) begin
                                if (privilege_mode < PRIV_S || (privilege_mode == PRIV_S && mstatus[22]))
                                    enter_trap(CAUSE_ILLEGAL, effective_instruction, pc);
                                else begin
                                    if (mstatus[8]) privilege_mode <= PRIV_S;
                                    else privilege_mode <= PRIV_U;
                                    mstatus[1] <= mstatus[5]; mstatus[5] <= 1'b1;
                                    mstatus[8] <= 1'b0; pc <= sepc; state <= FETCH_REQUEST;
                                end
                            end else if ((effective_instruction & 32'hfe007fff) == 32'h12000073) begin
                                if (privilege_mode == PRIV_U || (privilege_mode == PRIV_S && mstatus[20]))
                                    enter_trap(CAUSE_ILLEGAL, effective_instruction, pc);
                                else begin sfence_flush <= 1'b1; pc <= sequential_pc; state <= FETCH_REQUEST; end
                            end else if (effective_instruction == 32'h10500073) begin
                                pc <= sequential_pc; state <= WFI_WAIT;
                            end else if (funct3 != 0) begin
                                csr_old = csr_read(effective_instruction[31:20]);
                                csr_source = funct3[2] ? {27'd0, effective_instruction[19:15]} : rs1_value;
                                csr_write_access = funct3[1:0] == 2'b01 || csr_source != 0;
                                unique case (funct3[1:0])
                                    2'b01: csr_new = csr_source;
                                    2'b10: csr_new = csr_old | csr_source;
                                    2'b11: csr_new = csr_old & ~csr_source;
                                    default: csr_new = csr_old;
                                endcase
                                if (csr_access_illegal(effective_instruction[31:20], csr_write_access))
                                    enter_trap(CAUSE_ILLEGAL, effective_instruction, pc);
                                else begin
                                    if (rd != 0) registers[rd] <= csr_old;
                                    if (csr_write_access) write_csr(effective_instruction[31:20], csr_new);
                                    pc <= sequential_pc; state <= FETCH_REQUEST;
                                end
                            end else enter_trap(CAUSE_ILLEGAL, effective_instruction, pc);
                        end
                        default: enter_trap(CAUSE_ILLEGAL, effective_instruction, pc);
                    endcase
                    if (retired && !trap_entered && !instruction_compressed)
                        instret_counter <= instret_counter + 1'b1;
                end
                DATA_REQUEST: if (mmu_request_ready) state <= DATA_WAIT;
                DATA_WAIT: if (mmu_response_valid) begin : data_response
                    logic [7:0] byte_value;
                    logic [15:0] half_value;
                    byte_value = mmu_response_rdata >> (pending_offset * 8);
                    half_value = mmu_response_rdata >> (pending_offset[1] * 16);
                    if (mmu_page_fault) enter_trap(pending_write ? CAUSE_STORE_PAGE : CAUSE_LOAD_PAGE,
                                                   pending_address, pc);
                    else if (mmu_access_fault) enter_trap(pending_write ? CAUSE_STORE_ACCESS : CAUSE_LOAD_ACCESS,
                                                          pending_address, pc);
                    else unique case (pending_memory_kind)
                        MEM_LOAD: begin
                            if (pending_rd != 0) unique case (pending_funct3)
                                3'b000: registers[pending_rd] <= {{24{byte_value[7]}}, byte_value};
                                3'b001: registers[pending_rd] <= {{16{half_value[15]}}, half_value};
                                3'b010: registers[pending_rd] <= mmu_response_rdata;
                                3'b100: registers[pending_rd] <= {24'd0, byte_value};
                                3'b101: registers[pending_rd] <= {16'd0, half_value};
                                default: registers[pending_rd] <= 32'd0;
                            endcase
                            pc <= next_pc; state <= FETCH_REQUEST; instret_counter <= instret_counter + 1'b1;
                        end
                        MEM_STORE: begin pc <= next_pc; state <= FETCH_REQUEST; reservation_valid <= 1'b0; instret_counter <= instret_counter + 1'b1; end
                        MEM_LR: begin
                            if (pending_rd != 0) registers[pending_rd] <= mmu_response_rdata;
                            reservation_valid <= 1'b1; reservation_address <= pending_address;
                            pc <= next_pc; state <= FETCH_REQUEST; instret_counter <= instret_counter + 1'b1;
                        end
                        MEM_SC: begin
                            if (pending_rd != 0) registers[pending_rd] <= 32'd0;
                            pc <= next_pc; state <= FETCH_REQUEST; instret_counter <= instret_counter + 1'b1;
                        end
                        default: begin // AMO read complete
                            amo_old_value <= mmu_response_rdata;
                            unique case (instruction[31:27])
                                5'b00001: amo_new_value <= rs2_value; // swap
                                5'b00000: amo_new_value <= mmu_response_rdata + rs2_value;
                                5'b00100: amo_new_value <= mmu_response_rdata ^ rs2_value;
                                5'b01100: amo_new_value <= mmu_response_rdata & rs2_value;
                                5'b01000: amo_new_value <= mmu_response_rdata | rs2_value;
                                5'b10000: amo_new_value <= $signed(mmu_response_rdata) < $signed(rs2_value) ? mmu_response_rdata : rs2_value;
                                5'b10100: amo_new_value <= $signed(mmu_response_rdata) > $signed(rs2_value) ? mmu_response_rdata : rs2_value;
                                5'b11000: amo_new_value <= mmu_response_rdata < rs2_value ? mmu_response_rdata : rs2_value;
                                5'b11100: amo_new_value <= mmu_response_rdata > rs2_value ? mmu_response_rdata : rs2_value;
                                default: amo_new_value <= mmu_response_rdata;
                            endcase
                            pending_write <= 1'b1; pending_wdata <= amo_new_value;
                            pending_wstrb <= 4'b1111; state <= AMO_WRITE_REQUEST;
                        end
                    endcase
                end
                AMO_WRITE_REQUEST: begin
                    pending_wdata <= amo_new_value;
                    if (mmu_request_ready) state <= AMO_WRITE_WAIT;
                end
                AMO_WRITE_WAIT: if (mmu_response_valid) begin
                    if (mmu_page_fault) enter_trap(CAUSE_STORE_PAGE, pending_address, pc);
                    else if (mmu_access_fault) enter_trap(CAUSE_STORE_ACCESS, pending_address, pc);
                    else begin
                        if (amo_rd != 0) registers[amo_rd] <= amo_old_value;
                        reservation_valid <= 1'b0; pc <= next_pc;
                        state <= FETCH_REQUEST; instret_counter <= instret_counter + 1'b1;
                    end
                end
                MULDIV_WAIT: if (muldiv_done) begin
                    if (pending_rd != 0) registers[pending_rd] <= muldiv_result;
                    pc <= next_pc; state <= FETCH_REQUEST; instret_counter <= instret_counter + 1'b1;
                end
                WFI_WAIT: if (interrupt_available || debug_halt_pending || debug_halt_request)
                    state <= FETCH_REQUEST;
                default: state <= FETCH_REQUEST;
            endcase
        end
    end
endmodule
