package zulu_platform_pkg;
    localparam logic [31:0] BOOT_ROM_BASE = 32'h0000_0000;
    localparam logic [31:0] BOOT_ROM_SIZE = 32'h0001_0000;
    localparam logic [31:0] ACLINT_BASE   = 32'h0200_0000;
    localparam logic [31:0] ACLINT_SIZE   = 32'h0001_0000;
    localparam logic [31:0] PLIC_BASE     = 32'h0C00_0000;
    localparam logic [31:0] PLIC_SIZE     = 32'h0040_0000;
    localparam logic [31:0] UART_BASE     = 32'h1000_0000;
    localparam logic [31:0] UART_SIZE     = 32'h0000_1000;
    localparam logic [31:0] SDRAM_BASE    = 32'h8000_0000;
    localparam logic [31:0] SDRAM_SIZE    = 32'h0400_0000;

    localparam int unsigned CPU_CLOCK_HZ      = 100_000_000;
    localparam int unsigned TIMEBASE_CLOCK_HZ = 1_000_000;
    localparam int unsigned UART_BAUD_RATE    = 115_200;
endpackage
