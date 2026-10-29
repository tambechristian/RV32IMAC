# RV32IMAC Linux-Oriented Processor Core

This directory contains a separate RV32IMAC processor implementation for the
Cmod A7-35T. It does not replace or modify the proven RV32I SoC under `src`.

## Implemented architecture

- RV32I base integer instruction set
- RV32M iterative multiply and divide
- RV32A word atomics: LR/SC and the standard AMO operations
- RV32C compressed integer instructions
- Machine, supervisor, and user privilege modes
- Machine and supervisor trap entry and return
- Exception and interrupt delegation
- Machine and supervisor CSRs needed by an S-mode operating system
- Sv32 virtual memory with:
  - two-level page-table walks
  - 4 KiB pages and 4 MiB superpages
  - an eight-entry TLB
  - U/S, SUM, MXR, R/W/X permission checks
  - hardware accessed/dirty PTE updates
  - full TLB flush on `sfence.vma`
- A unified physical-memory interface and a Wishbone Classic wrapper
- Halt, resume, single-step, PC, and integer-register debug access

The core traps naturally aligned violations rather than implementing
misaligned load, store, or atomic emulation. Atomic ordering bits are accepted;
the current single-core, uncached memory system already serializes accesses.

## Main modules

- `rv32imac_core.sv`: processor, privileged architecture, CSRs, traps, and
  unified virtual-memory request path
- `sv32_mmu.sv`: TLB and Sv32 page-table walker
- `rv32_muldiv.sv`: iterative RV32M execution unit
- `rv32c_decoder.sv`: RV32C decompressor
- `rv32imac_wb.sv`: Wishbone-facing core wrapper
- `rv32imac_pkg.sv`: architectural constants

The native physical-memory request remains asserted until `memory_ready`.
`memory_error` is sampled with `memory_ready`. The Wishbone wrapper maps this
handshake to `CYC`, `STB`, `ACK`, and `ERR`.

## Run the regressions

Place the OSS CAD Suite `bin` directory on `PATH`, then run:

```powershell
.\RV32IMAC\run_tests.ps1
```

The regressions cover:

- all eight RV32M operations, signed corner cases, divide by zero, and overflow
- representative RV32C arithmetic, control-flow, stack, and illegal encodings
- Sv32 bypass, 4 KiB translation, superpages, TLB hits, execute permissions,
  and accessed/dirty updates
- integrated RV32IMAC execution with compressed instructions, memory, and AMO
- M-mode to S-mode entry, delegated S-mode `ecall`, trap CSRs, and `sret`

To synthesize the standalone Wishbone core for the Cmod A7-35T:

```powershell
vivado -mode batch -source RV32IMAC\synth_core.tcl
```

## Linux platform requirements

This is a Linux-oriented processor core, not yet a complete Linux-bootable
Cmod A7 system. A practical Linux platform still needs:

- substantially more RAM than the onboard 512 KiB SRAM
- a CLINT-compatible machine timer and software-interrupt block
- a PLIC-compatible external interrupt controller
- boot firmware such as OpenSBI and a matching device tree
- a UART console and a Linux-accessible storage or network device
- physical memory protection (PMP) if required by the selected OpenSBI build

The existing Cmod SoC peripherals can be reused behind the Wishbone wrapper,
but their addresses and interrupt topology must be described consistently to
firmware and the device tree. Do not point the established `scripts\build.tcl`
flow at this directory until those platform components and adequate external
memory have been integrated.
