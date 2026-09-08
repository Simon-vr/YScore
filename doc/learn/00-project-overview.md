---
permalink: /learn/00-project-overview/
lang: en
---
# 00. Project Overview

## 1. What This Is

**YScore** (Your Simple Core) is a RISC-V SoC written completely from scratch:

- **ISA**: RV32I + Zicsr (no M multiplication extension; multiplication is emulated by the software library `rtos/lib/math.c`).
- **Pipeline**: 5-stage multi-cycle (IF → ID → EXE → PERIPS → WB).
- **Bus**: hand-written AXI4-Lite (1 master, 3 slaves: UART / GPIO / CLINT), plus 2 fixed-latency peripherals not on the bus (DMEM, CLINT).
- **Software**: bare-metal preemptive RTOS + Shell command line + Asteroids game, compiled from C, running on FPGA.

The project contains two independent workspaces, **hardware** (`src/`, Verilog) and **firmware** (`rtos/`, C + assembly),
connected via ELF → `bin2mem.py` → `*.mem` files.

## 2. Implemented Features

| Category       | Feature                                                                 | Corresponding Code                                            |
| --------       | ----------------------------------------------------------------------- | ------------------------------------------------------------- |
| Instruction set| Full RV32I instruction set (R/I/L/S/B/J/U/CSR) + Zicsr                  | `src/ctl_*.v`, `src/rvdef.vh`                                  |
| Internal exceptions | ecall / ebreak → mepc / mcause / mtvec / mret                       | `src/regfile_csr.v`, `src/ctl_ifid.v`                          |
| Peripherals    | UART (AXI4-Lite, 115200), GPIO (lights LED on low level), CLINT (mtime timer) | `src/axil_uart.v`, `src/axil_gpio.v`, `src/clint.v`    |
| Bus            | Hand-written AXI4-Lite Master state machine (five-channel read/write)   | `src/axil_master.v`                                            |
| Memory         | Instruction 18KB (synchronous read M9K), data 24KB (4x6KB byte banks, drum-style addressing) | `src/core_if.v`, `src/mem_ctl.v`, `src/mem_cell.v` |
| Software       | Preemptive round-robin scheduler, multitasking, Shell, Asteroids        | `rtos/sys/kernel.c` etc.                                       |
| Co-debugging   | QEMU verification first + FPGA on-board, only modify the port layer     | `rtos/port/*`                                                  |

## 3. Design Principle: Stage-Wise Hardware Separation

Core idea: **the stages of one instruction are decoupled into independent modules**, each responsible for only one thing, linked by well-defined interfaces and "tokens".
This lets you pinpoint a bug to a specific stage rather than digging through one big state machine.

> **Accompanying design flow**: every piece of hardware in this project follows the order
> **① draw the intended waveform in drawio (`src/wave.drawio`)
> → ② draw the architecture diagram to make the nets explicit (`src/arch.drawio`) → ③ write Verilog**,
> then check against the ModelSim waveform cycle by cycle. This method is precisely to avoid
> "missing a cycle" and "messy nets", the two hardest kinds of hardware bug to find. See `01-hardware-basics`.

```
IF  stage    core_if     synchronous read of the instruction memory (M9K), outputs the instruction one cycle later
ID  stage    core_id     field splitting + immediate extension
             ctl_ifid    decode: ALU source selection / immediate type / exception and mret recognition
             ctl_exe     ALU function code + next-PC function code
             ctl_perips  whether memory/peripheral access is needed (peripsen)
             ctl_wb      writeback selection + register write enable + CSR write enable
EXE stage    core_exe    exe_alu (33-bit carry/borrow) + exe_next (branch/jump target calculation)
PERIPS stage core_perips address decode + three peripheral access paths (MEM fixed 1 cycle / CLINT fixed 1 cycle / AXI handshake)
WB  stage    core_wb     writeback data selection (ALU/Load/PC4/CSR/LUI/AUIPC)
             wb_mux_pc   next-PC selection (sequential/branch target/jump target/mtvec/mepc)
             regfile_csr CSR register file + exception/interrupt state update + intrpt generation
```

The control path (`ctl_*`) and datapath (`core_*`, `exe_*`, `ifid_*`) are completely separated.
This will be emphasized repeatedly in the Debug chapters: **first check whether ctl gives the correct control signals, then check whether data takes the correct path**.

## 4. Overall Architecture

```
                 ┌──────────────────────────────────────────────┐
                 │                  core_ctl                    │
                 │  (token serial state machine + pipeline registers + exception path) │
                 └────┬────────┬────────┬──────────┬────────────┘
                      │        │        │          │
   core_if     core_id     core_exe    core_perips    core_wb
   (fetch)     (decode)    (compute+jump) (mem/periph)  (writeback+PC select)
                      │        │        │          │
              ┌───────┴────────┴───┬────┴──────────┴──────┐
              │   regfile(32x32)   │  mem_ctl(24KB)       │
              │   regfile_csr(CSR) │  clint(mtime)        │
              │                    │  axil_master→        │
              │                    │    axil_uart         │
              │                    │    axil_gpio         │
              └────────────────────┴──────────────────────┘
```

**Token serial**: `core_ctl.v` uses an if-else chain that advances only one token per cycle
(`wb_token → if_token → ifid_token → exe_token → perips_token → wb_pending → wb_token`),
ensuring only one instruction is in the pipeline at a time. Multi-cycle behavior: AXI accesses in the PERIPS stage pause for several cycles,
and the WB stage is split into "retire cycle + sample cycle" (see chapter 07 and 03-debug-pitfalls/03).

**Address map** (decoded in `src/core_perips.v:24-27`):

| Address range                     | Peripheral             | Access method                          |
| ---------------------------        | ---------------------  | -------------------------------------- |
| `0x0000_0000~0x0000_47FF`          | Instruction memory 18KB| IF stage synchronous read (not in PERIPS) |
| `0x8000_0000~0x8000_5FFF`          | Data memory 24KB       | PERIPS fixed 1 cycle (`is_mem`)         |
| `0x0200_0000~0x0200_BFFF`          | CLINT (mtime/mtimecmp) | PERIPS fixed 1 cycle (`is_clint`)       |
| `0x1000_0000~0x1000_001F`          | UART (AXI-Lite)        | PERIPS via `axil_master` handshake      |
| `0x2000_0000~0x2000_000F`          | GPIO (AXI-Lite)        | PERIPS via `axil_master` handshake      |

## 5. Project Directory Description

```
yscore/
├── src/                # Hardware Verilog (top-level top.v → core_ctl.v → stage/peripheral modules)
├── tb/                 # ModelSim simulation (mycpu_sim.v: register/CSR snapshot + instruction printing)
├── simulation/modelsim/ # ModelSim project (sim.do one-click compile and run)
├── rtos/               # Firmware project (CMake + riscv-none-elf-gcc)
│   ├── src/            # Application layer (app/shell/game/input/main)
│   ├── sys/            # Kernel (kernel.c scheduler + mem.c)
│   ├── port/           # Porting layer (portmacro.h/portASM.S/interrupt/critical/timer)
│   ├── lib/            # Drivers and utilities (uart/gpio/math/utils)
│   ├── include/        # Header files
│   ├── startup/        # Startup scripts + linker scripts
│   ├── bin2mem.py      # ELF → imem.mem / dmem0~3.mem
│   └── CMakeLists.txt  # Cross compilation
├── ins/                # Assembly/C test cases (RI/LS/branch/others/zicsr/except/test.c)
└── doc/learn/          # This learning documentation
```

## 6. Debug Methodology (Used Throughout)

This project's troubleshooting has formed a reusable flow that every Debug chapter uses:

1. **Symptom → Suspicion**: first clarify "what is broken" (no printing? stuck? LED state?), and list the most likely suspects.
2. **Pin down the layer**: software before hardware; use map/dasm disassembly to rule out the software layer.
3. **Simulation localization**: run `sim.do` in ModelSim, use the register/CSR snapshots and waveforms in tb to find the "PC/instruction that crashed".
4. **Read the hardware dataflow**: follow the instruction from IF to WB stage by stage, looking at the ctl control signals and data values.
5. **Change one thing, verify one round**: after any fix you must re-simulate / re-run on board to regress, to avoid "fixing A and breaking B".

Key tools:

- `riscv-none-elf-objdump -D -h -z` disassembly (`ninja dasm`).
- ModelSim `simulation/modelsim/sim.do` (see the simulation notes in 01-hardware-basics/01).
- tb supports command-line breakpoint override: `+STOP_PC=0x...` (`tb/mycpu_sim.v:357`).
