`timescale 1ns / 1ps

module zulu_sdram_controller #(
    parameter integer CLOCK_FREQUENCY_HZ = 100_000_000,
    parameter integer POWERUP_DELAY_CYCLES = CLOCK_FREQUENCY_HZ / 5_000,
    parameter integer REFRESH_INTERVAL_CYCLES =
        (CLOCK_FREQUENCY_HZ * 78) / 10_000_000,
    parameter integer T_RP_CYCLES = 2,
    parameter integer T_RCD_CYCLES = 2,
    parameter integer T_RFC_CYCLES = 7,
    parameter integer T_MRD_CYCLES = 2,
    parameter integer T_WRITE_RECOVERY_CYCLES = 4,
    parameter integer CAS_LATENCY = 3
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        wb_cyc,
    input  logic        wb_stb,
    input  logic        wb_we,
    input  logic [31:0] wb_adr,
    input  logic [31:0] wb_dat_w,
    input  logic [3:0]  wb_sel,
    output logic        wb_ack,
    output logic        wb_err,
    output logic [31:0] wb_dat_r,
    output logic        init_done,
    output logic        sdram_clk,
    output logic        sdram_cke,
    output logic        sdram_cs_n,
    output logic        sdram_ras_n,
    output logic        sdram_cas_n,
    output logic        sdram_we_n,
    output logic [1:0]  sdram_ba,
    output logic [12:0] sdram_addr,
    inout  wire  [15:0] sdram_dq,
    output logic [1:0]  sdram_dqm
);
    localparam logic [12:0] MODE_REGISTER = 13'h030;

    typedef enum logic [4:0] {
        POWERUP_WAIT,
        INIT_CKE,
        INIT_PRECHARGE,
        INIT_PRECHARGE_WAIT,
        INIT_REFRESH_1,
        INIT_REFRESH_WAIT_1,
        INIT_REFRESH_2,
        INIT_REFRESH_WAIT_2,
        INIT_MODE,
        INIT_MODE_WAIT,
        IDLE,
        REFRESH_COMMAND,
        REFRESH_WAIT,
        ACTIVATE_COMMAND,
        ACTIVATE_WAIT,
        READ_COMMAND,
        READ_WAIT,
        READ_RECOVERY,
        WRITE_COMMAND,
        WRITE_RECOVERY,
        RESPOND,
        WAIT_RELEASE
    } state_t;

    state_t state;
    logic [31:0] wait_counter;
    logic [31:0] refresh_counter;
    logic [25:0] request_address;
    logic [31:0] request_write_data;
    logic [3:0] request_select;
    logic request_write;
    logic half_select;
    logic [31:0] read_data;
    logic [15:0] dq_output;
    logic dq_output_enable;
    logic [24:0] halfword_address;
    logic [1:0] selected_bank;
    logic [12:0] selected_row;
    logic [9:0] selected_column;

    assign sdram_clk = ~clk;
    assign sdram_dq = dq_output_enable ? dq_output : 16'hzzzz;

    always_comb begin
        halfword_address = request_address[25:1] + half_select;
        selected_bank = halfword_address[24:23];
        selected_row = halfword_address[22:10];
        selected_column = halfword_address[9:0];

        wb_ack = state == RESPOND;
        wb_err = 1'b0;
        wb_dat_r = read_data;

        sdram_cke = state != POWERUP_WAIT;
        sdram_cs_n = state == POWERUP_WAIT;
        sdram_ras_n = 1'b1;
        sdram_cas_n = 1'b1;
        sdram_we_n = 1'b1;
        sdram_ba = selected_bank;
        sdram_addr = 13'd0;
        sdram_dqm = 2'b11;
        dq_output = half_select ? request_write_data[31:16] :
                                  request_write_data[15:0];
        dq_output_enable = 1'b0;

        unique case (state)
            INIT_PRECHARGE: begin
                sdram_ras_n = 1'b0;
                sdram_we_n = 1'b0;
                sdram_addr[10] = 1'b1;
            end
            INIT_REFRESH_1, INIT_REFRESH_2, REFRESH_COMMAND: begin
                sdram_ras_n = 1'b0;
                sdram_cas_n = 1'b0;
            end
            INIT_MODE: begin
                sdram_ras_n = 1'b0;
                sdram_cas_n = 1'b0;
                sdram_we_n = 1'b0;
                sdram_ba = 2'b00;
                sdram_addr = MODE_REGISTER;
            end
            ACTIVATE_COMMAND: begin
                sdram_ras_n = 1'b0;
                sdram_ba = selected_bank;
                sdram_addr = selected_row;
            end
            READ_COMMAND: begin
                sdram_cas_n = 1'b0;
                sdram_ba = selected_bank;
                sdram_addr = {2'b00, 1'b1, selected_column};
                sdram_dqm = 2'b00;
            end
            READ_WAIT: sdram_dqm = 2'b00;
            WRITE_COMMAND: begin
                sdram_cas_n = 1'b0;
                sdram_we_n = 1'b0;
                sdram_ba = selected_bank;
                sdram_addr = {2'b00, 1'b1, selected_column};
                sdram_dqm = half_select ? ~request_select[3:2] :
                                          ~request_select[1:0];
                dq_output_enable = 1'b1;
            end
            default: begin end
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= POWERUP_WAIT;
            wait_counter <= 32'd0;
            refresh_counter <= 32'd0;
            request_address <= 26'd0;
            request_write_data <= 32'd0;
            request_select <= 4'd0;
            request_write <= 1'b0;
            half_select <= 1'b0;
            read_data <= 32'd0;
            init_done <= 1'b0;
        end else begin
            if (init_done && state != REFRESH_COMMAND) begin
                if (refresh_counter < REFRESH_INTERVAL_CYCLES)
                    refresh_counter <= refresh_counter + 1'b1;
            end

            unique case (state)
                POWERUP_WAIT: begin
                    if (wait_counter + 1 >= POWERUP_DELAY_CYCLES) begin
                        wait_counter <= 32'd0;
                        state <= INIT_CKE;
                    end else begin
                        wait_counter <= wait_counter + 1'b1;
                    end
                end
                INIT_CKE: state <= INIT_PRECHARGE;
                INIT_PRECHARGE: begin
                    wait_counter <= T_RP_CYCLES - 1;
                    state <= INIT_PRECHARGE_WAIT;
                end
                INIT_PRECHARGE_WAIT: begin
                    if (wait_counter == 0)
                        state <= INIT_REFRESH_1;
                    else
                        wait_counter <= wait_counter - 1'b1;
                end
                INIT_REFRESH_1: begin
                    wait_counter <= T_RFC_CYCLES - 1;
                    state <= INIT_REFRESH_WAIT_1;
                end
                INIT_REFRESH_WAIT_1: begin
                    if (wait_counter == 0)
                        state <= INIT_REFRESH_2;
                    else
                        wait_counter <= wait_counter - 1'b1;
                end
                INIT_REFRESH_2: begin
                    wait_counter <= T_RFC_CYCLES - 1;
                    state <= INIT_REFRESH_WAIT_2;
                end
                INIT_REFRESH_WAIT_2: begin
                    if (wait_counter == 0)
                        state <= INIT_MODE;
                    else
                        wait_counter <= wait_counter - 1'b1;
                end
                INIT_MODE: begin
                    wait_counter <= T_MRD_CYCLES - 1;
                    state <= INIT_MODE_WAIT;
                end
                INIT_MODE_WAIT: begin
                    if (wait_counter == 0) begin
                        init_done <= 1'b1;
                        refresh_counter <= 32'd0;
                        state <= IDLE;
                    end else begin
                        wait_counter <= wait_counter - 1'b1;
                    end
                end
                IDLE: begin
                    if (refresh_counter >= REFRESH_INTERVAL_CYCLES) begin
                        state <= REFRESH_COMMAND;
                    end else if (wb_cyc && wb_stb) begin
                        request_address <= wb_adr[25:0];
                        request_write_data <= wb_dat_w;
                        request_select <= wb_sel;
                        request_write <= wb_we;
                        half_select <= 1'b0;
                        state <= ACTIVATE_COMMAND;
                    end
                end
                REFRESH_COMMAND: begin
                    refresh_counter <= 32'd0;
                    wait_counter <= T_RFC_CYCLES - 1;
                    state <= REFRESH_WAIT;
                end
                REFRESH_WAIT: begin
                    if (wait_counter == 0)
                        state <= IDLE;
                    else
                        wait_counter <= wait_counter - 1'b1;
                end
                ACTIVATE_COMMAND: begin
                    wait_counter <= T_RCD_CYCLES - 1;
                    state <= ACTIVATE_WAIT;
                end
                ACTIVATE_WAIT: begin
                    if (wait_counter == 0) begin
                        if (request_write)
                            state <= WRITE_COMMAND;
                        else
                            state <= READ_COMMAND;
                    end else begin
                        wait_counter <= wait_counter - 1'b1;
                    end
                end
                READ_COMMAND: begin
                    wait_counter <= CAS_LATENCY - 1;
                    state <= READ_WAIT;
                end
                READ_WAIT: begin
                    if (wait_counter == 0) begin
                        if (half_select)
                            read_data[31:16] <= sdram_dq;
                        else
                            read_data[15:0] <= sdram_dq;
                        wait_counter <= T_RP_CYCLES - 1;
                        state <= READ_RECOVERY;
                    end else begin
                        wait_counter <= wait_counter - 1'b1;
                    end
                end
                READ_RECOVERY: begin
                    if (wait_counter == 0) begin
                        if (half_select) begin
                            state <= RESPOND;
                        end else begin
                            half_select <= 1'b1;
                            state <= ACTIVATE_COMMAND;
                        end
                    end else begin
                        wait_counter <= wait_counter - 1'b1;
                    end
                end
                WRITE_COMMAND: begin
                    wait_counter <= T_WRITE_RECOVERY_CYCLES - 1;
                    state <= WRITE_RECOVERY;
                end
                WRITE_RECOVERY: begin
                    if (wait_counter == 0) begin
                        if (half_select) begin
                            state <= RESPOND;
                        end else begin
                            half_select <= 1'b1;
                            state <= ACTIVATE_COMMAND;
                        end
                    end else begin
                        wait_counter <= wait_counter - 1'b1;
                    end
                end
                RESPOND: state <= WAIT_RELEASE;
                WAIT_RELEASE: begin
                    if (!(wb_cyc && wb_stb))
                        state <= IDLE;
                end
                default: state <= POWERUP_WAIT;
            endcase
        end
    end
endmodule
