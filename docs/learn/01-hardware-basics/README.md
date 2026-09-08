---
permalink: /learn/01-hardware-basics/
lang: en
---
# 01. Hardware Basics (In Instruction Implementation Order)

This section is organized according to the actual hardware building order of this project: R instructions first, then expanding the instruction set class by class.
Each instruction class has its corresponding datapath and control path descriptions plus test cases under `ins/`.

```
01-hardware-basics/
├── README.md
├── 00-design-flow.md          ★ Hardware design flow: waveform (wave.drawio) → architecture (arch.drawio) → then code
├── 01-r-instructions.md       R instructions
├── 02-i-instructions.md       I instructions
├── 03-ls-instructions.md      Load/Store instructions
├── 04-branch-instructions.md  Branch instructions
├── 05-other-instructions.md   JAL/JALR/LUI/AUIPC
├── 06-c-language-test.md      C language compilation test
├── 07-csr-implementation.md   CSR hardware
├── 08-exception-handling.md   Internal exception path
├── 09-axi-peripherals.md      AXI4-Lite bus
├── 10-uart-gpio-adaptation.md UART/GPIO adaptation
├── 11-fpga-deployment.md      FPGA synthesis and deployment
└── 12-tb-simulation-guide.md  ★ Simulation testbench tb/mycpu_sim.v explained + sim.do one-click run
```

> **Strongly recommended to read `00-design-flow.md` first**: it summarizes this project's hardware design method of "draw the waveform first, then the architecture,
> then the code". Understanding it is needed to see where each chapter's "datapath/control path" comes from.
>
> **Read `12-tb-simulation-guide.md` alongside it**: the usage of the simulation testbench
> (register/CSR snapshot, STOP_PC breakpoint, sim.do one-click run); every chapter's tests rely on it.

## Prerequisites

- Read through `00-project-overview.md` first to understand the overall idea of stage separation and token serialization.
- Be familiar with RV32I instruction encoding (opcode / funct3 / funct7 / immediate layout).
- Know how to run simulation in ModelSim (see the simulation notes in 01-r-instructions.md) and use objdump to view disassembly.

## Per-Chapter Structure Convention

Each chapter follows the same pattern for easy reference against the code:

1. **Instruction encoding**: the definition of the instruction in `src/rvdef.vh`.
2. **Datapath**: how operands enter the ALU from registers/immediates.
3. **Control path**: which control signals the `ctl_*` modules give and where they take effect.
4. **Writeback and next PC**: how `core_wb` / `exe_next` / `wb_mux_pc` handle it.
5. **Testing**: the corresponding test file under `ins/` and the verification method.
