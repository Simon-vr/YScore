---
permalink: /learn/
lang: en
---
# YScore Documentation Navigation

This directory holds the complete documentation for the YScore SoC, recording the full process of this CPU's hardware design, software stack, and joint debugging from scratch.

## Table of Contents

```
doc/learn/
├── README.md                  ← This file (navigation)
├── 00-project-overview.md     ← Project overview: features / design principles / architecture / directories / Debug methodology
│
├── 01-hardware-basics/        ← Hardware part (in per-instruction-class implementation order)
│   ├── README.md
│   ├── 00-design-flow.md        ★ Hardware design flow: waveform (wave.drawio) first → architecture (arch.drawio) → then code
│   ├── 01-r-instructions.md       R instructions (datapath + control path + RI.s test)
│   ├── 02-i-instructions.md       I instructions (ADDI/ANDI/... + RI.s test)
│   ├── 03-ls-instructions.md      Load/Store instructions (mem_ctl drum-style byte storage + LS.s)
│   ├── 04-branch-instructions.md  Branch instructions (exe_next jump decision + branch.s)
│   ├── 05-other-instructions.md   JAL/JALR/LUI/AUIPC (others.s)
│   ├── 06-c-language-test.md      C language compilation test (test.c / ELF / bin2mem flow)
│   ├── 07-csr-implementation.md   CSR hardware implementation (regfile_csr.v + zicsr.s)
│   ├── 08-exception-handling.md   Internal exception path (ecall/ebreak + except.s)
│   ├── 09-axi-peripherals.md      AXI4-Lite bus (five-channel handshake / axil_master state machine)
│   ├── 10-uart-gpio-adaptation.md UART / GPIO peripheral adaptation
│   ├── 11-fpga-deployment.md      Quartus synthesis / ModelSim simulation / resource usage
│   └── 12-tb-simulation-guide.md  ★ Simulation testbench mycpu_sim.v explained (snapshot/disassembly/STOP_PC + sim.do)
│
├── 02-software-stack/         ← Software part (RTOS firmware)
│   ├── README.md
│   ├── 01-qemu-environment.md     QEMU development environment and operating principles
│   ├── 02-runtime-environment.md  Runtime environment (linking / startup / interrupts / stack / port / lib)
│   ├── 03-multitasking.md         Multitasking system (scheduling / task states / context switching)
│   ├── 04-shell-implementation.md Shell program (command parsing / echo / input ownership)
│   ├── 05-game-implementation.md  Game program (Asteroids game / rendering / input contention)
│   ├── 06-porting-guide.md        Porting from QEMU to FPGA (only modify the port layer)
│   └── 07-post-port-debug.md      Post-porting Debug guide (on-board troubleshooting flow)
│
└── 03-debug-pitfalls/         ← Debug pitfall guide (**recommended to read first**)
    ├── README.md
    ├── 01-hardware-pitfalls.md     Hardware pitfalls (byte alignment / async read / mask bits)
    ├── 02-software-pitfalls.md     Software pitfalls (UART buffer sharing / token mechanism)
    └── 03-hw-sw-co-debug.md        Full hardware-software combined Debug record (the bugs in this session)
```

## Recommended Reading Order

1. **Read through** `00-project-overview.md` to build an overall understanding.
2. **Hardware intro**: read `01-hardware-basics/00-design-flow.md` (design flow) first,
   then build step by step in numbered order from R instructions to the AXI bus.
3. **Software intro**: follow the `02-software-stack/` numbered order, from the QEMU environment to RTOS multitasking.
4. **Troubleshooting**: the three files in `03-debug-pitfalls/` record three typical troubleshooting processes, of which
   `03-hw-sw-co-debug.md` documents the layer-by-layer hardware-software co-debugging bugs that actually occurred in this project.
   It is strongly recommended to consult it when you encounter similar symptoms.

## Code Reference Conventions

- Hardware: `src/<module>.v:<line>`, e.g. `src/regfile_csr.v:79`.
- Software: `rtos/<subdir>/<file>.<ext>:<line>`, e.g. `rtos/sys/kernel.c:113`.
- Tests: `ins/<file>.<ext>`.
- All references can be jumped to directly in the source, making it easy to read and look up at the same time.
