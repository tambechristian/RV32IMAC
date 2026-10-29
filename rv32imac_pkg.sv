package rv32imac_pkg;
    typedef enum logic [1:0] {
        PRIV_U = 2'b00,
        PRIV_S = 2'b01,
        PRIV_M = 2'b11
    } privilege_t;

    localparam logic [31:0] MISA_VALUE =
        (32'd1 << 30) | // RV32
        (32'd1 << 0)  | // A
        (32'd1 << 2)  | // C
        (32'd1 << 8)  | // I
        (32'd1 << 12) | // M
        (32'd1 << 18) | // S
        (32'd1 << 20);  // U

    localparam logic [31:0] CAUSE_INST_MISALIGNED = 32'd0;
    localparam logic [31:0] CAUSE_INST_ACCESS     = 32'd1;
    localparam logic [31:0] CAUSE_ILLEGAL         = 32'd2;
    localparam logic [31:0] CAUSE_BREAKPOINT      = 32'd3;
    localparam logic [31:0] CAUSE_LOAD_MISALIGNED = 32'd4;
    localparam logic [31:0] CAUSE_LOAD_ACCESS     = 32'd5;
    localparam logic [31:0] CAUSE_STORE_MISALIGNED= 32'd6;
    localparam logic [31:0] CAUSE_STORE_ACCESS    = 32'd7;
    localparam logic [31:0] CAUSE_ECALL_U         = 32'd8;
    localparam logic [31:0] CAUSE_ECALL_S         = 32'd9;
    localparam logic [31:0] CAUSE_ECALL_M         = 32'd11;
    localparam logic [31:0] CAUSE_INST_PAGE       = 32'd12;
    localparam logic [31:0] CAUSE_LOAD_PAGE       = 32'd13;
    localparam logic [31:0] CAUSE_STORE_PAGE      = 32'd15;

    localparam logic [31:0] IRQ_SOFTWARE_S = 32'h80000001;
    localparam logic [31:0] IRQ_SOFTWARE_M = 32'h80000003;
    localparam logic [31:0] IRQ_TIMER_S    = 32'h80000005;
    localparam logic [31:0] IRQ_TIMER_M    = 32'h80000007;
    localparam logic [31:0] IRQ_EXTERNAL_S = 32'h80000009;
    localparam logic [31:0] IRQ_EXTERNAL_M = 32'h8000000b;

    localparam logic [11:0] CSR_SSTATUS    = 12'h100;
    localparam logic [11:0] CSR_SIE        = 12'h104;
    localparam logic [11:0] CSR_STVEC      = 12'h105;
    localparam logic [11:0] CSR_SCOUNTEREN = 12'h106;
    localparam logic [11:0] CSR_SSCRATCH   = 12'h140;
    localparam logic [11:0] CSR_SEPC       = 12'h141;
    localparam logic [11:0] CSR_SCAUSE     = 12'h142;
    localparam logic [11:0] CSR_STVAL      = 12'h143;
    localparam logic [11:0] CSR_SIP        = 12'h144;
    localparam logic [11:0] CSR_SATP       = 12'h180;
    localparam logic [11:0] CSR_MSTATUS    = 12'h300;
    localparam logic [11:0] CSR_MISA       = 12'h301;
    localparam logic [11:0] CSR_MEDELEG    = 12'h302;
    localparam logic [11:0] CSR_MIDELEG    = 12'h303;
    localparam logic [11:0] CSR_MIE        = 12'h304;
    localparam logic [11:0] CSR_MTVEC      = 12'h305;
    localparam logic [11:0] CSR_MCOUNTEREN = 12'h306;
    localparam logic [11:0] CSR_MSCRATCH   = 12'h340;
    localparam logic [11:0] CSR_MEPC       = 12'h341;
    localparam logic [11:0] CSR_MCAUSE     = 12'h342;
    localparam logic [11:0] CSR_MTVAL      = 12'h343;
    localparam logic [11:0] CSR_MIP        = 12'h344;
    localparam logic [11:0] CSR_MCYCLE     = 12'hb00;
    localparam logic [11:0] CSR_MINSTRET   = 12'hb02;
    localparam logic [11:0] CSR_CYCLE      = 12'hc00;
    localparam logic [11:0] CSR_TIME       = 12'hc01;
    localparam logic [11:0] CSR_INSTRET    = 12'hc02;
endpackage
