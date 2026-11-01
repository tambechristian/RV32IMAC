# Zulu A7 RV32IMAC Platform

This directory defines the Zulu A7 Linux platform contract for the RV32IMAC
core and starts the external SDR SDRAM and OpenSBI support.

The fitted device marking is `XC7A35T-2CPG236I`. Select the installed Vivado
part `xc7a35tcpg236-2`; Vivado does not expose a `xc7a35tcpg236-2I` part name.

## Hardware contract

| Region | Base | Size |
|---|---:|---:|
| Boot ROM | `0x00000000` | 64 KiB |
| ACLINT/CLINT | `0x02000000` | 64 KiB |
| PLIC | `0x0C000000` | 4 MiB |
| NS16550A UART | `0x10000000` | 4 KiB |
| SDRAM | `0x80000000` | 64 MiB |

The intended CPU clock is 100 MHz. The ACLINT `mtime` clock contract is
1 MHz. UART registers are 32-bit accesses spaced four bytes apart
(`reg-shift = 2`), and UART interrupt source 1 is routed through the PLIC.

The SDRAM controller implements a 32-bit Wishbone slave over the board's
`AS4C32M16SB-7TCN` x16 SDR SDRAM. Each Wishbone access uses two SDRAM
halfword operations. The current XDC contains the routed SDRAM pins only.

## OpenSBI layout

- OpenSBI `fw_jump`: `0x80000000`
- Linux entry address: `0x80400000`
- Device tree relocation address: `0x83E00000`

Build the generic OpenSBI platform from PowerShell:

```powershell
.\opensbi\build_opensbi.ps1 -OpenSbiRoot C:\path\to\opensbi -UseLlvm
```

The script requires GNU make and `dtc`. Modern OpenSBI requires a linker
that can create PIE executables, so LLVM/LLD with `-UseLlvm` is recommended.
For a compatible GNU toolchain, omit `-UseLlvm` and use `-CrossCompile` to
select its compiler prefix.

This flow was validated with OpenSBI v1.9 commit
`cbf9f6734dd85a982c63e3cb5db7ffe09da839ca` and LLVM 22.1.8. On native
Windows, the build script includes `windows-opensbi.mk` to place archive
inputs in response files and avoid the Windows command-line length limit.
Generated firmware under `opensbi/build/` is intentionally not committed.

## Current status

Implemented:

- OpenSBI CPU contract (`mhartid`, machine identification CSRs, reset vector)
- Zulu memory-map constants
- RV32IMAC device tree
- OpenSBI build script
- Wishbone SDR SDRAM controller, behavioral testbench, and routed SDRAM pins

Still required before Linux can run on hardware:

- 12 MHz input clock pin and MMCM/reset logic
- complete clock, reset, UART, and timing constraints
- boot ROM and firmware-loading path
- Wishbone address decoder/interconnect
- ACLINT/CLINT, PLIC, and NS16550A-compatible UART RTL
- integrated Zulu top-level simulation and Vivado implementation

The DTS describes the final hardware contract. Do not boot this DTS until
the missing memory-mapped peripherals implement that contract.
