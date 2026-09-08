---
permalink: /
title: YScore
lang: en
---

# YScore — Write an RV32I SoC that runs C, from scratch

> **Yes! core / Your Simple Core** — a hand-written Verilog 5-stage multi-cycle RISC-V processor + AXI4-Lite bus adaptation + bare-metal RTOS.

---

## Demo

<video controls muted preload="metadata" style="max-width:100%">
  <source src="{{ site.baseurl }}/image/show.mp4" type="video/mp4">
</video>

![Hardware architecture]({{ site.baseurl }}/image/arch.svg)

---

## What's inside

- **Processor**: RV32I + Zicsr, 5-stage multi-cycle pipeline (IF → ID → EXE → PERIPS → WB), supporting ecall/ebreak internal exceptions and the CLINT timer interrupt.
- **Bus & peripherals**: a hand-written AXI4-Lite Master (read/write five-channel handshake state machine) driving UART (AXI-Lite slave, 115200), GPIO (LEDs lit by low level) and CLINT (64-bit mtime).
- **Memory**: 18KB instruction memory + 24KB data memory (4×6KB byte banks, rotating addressing for 8/16/32-bit).
- **Software**: a bare-metal preemptive round-robin RTOS, a Shell CLI + an Asteroids mini-game, built with a C cross-compiler.
- **Bring-up**: verified first on QEMU (standard RV32), then ported to FPGA by changing only the `port` layer.

---

## Required toolchain

| Item          | Version / model                                   |
| ------------- | ------------------------------------------------ |
| Dev board     | Forlinx Altera EP4CE10 ZhengTu Pro (Cyclone IV E) |
| Synthesis     | Quartus Prime 25.1 Standard Edition              |
| Simulation    | ModelSim 20.1                                    |
| Cross-compiler| RISC-V GCC 15.2.0 (xPack) `riscv-none-elf-gcc`  |
| Build tools   | CMake ≥ 3.20 + Ninja                             |
| Emulator      | QEMU `qemu-system-riscv32`                      |
| OS            | Windows 11 / WSL                                 |

**Resource usage**: about 10K LE, 6~7 M9K blocks (18KB IMEM + 24KB DMEM). See the Quartus
build reports and `doc/learn/01-hardware-basics/11-fpga-deployment.md`.

---

## System architecture

### Pipeline: token-serial multi-cycle

```
   ┌────────┐   ┌────────┐   ┌────────┐   ┌─────────────┐   ┌──────────┐
   │  IF    │ → │  ID    │ → │  EXE   │ → │   PERIPS    │ → │   WB     │
   └────────┘   └────────┘   └────────┘   └─────────────┘   └──────────┘
     core_if     core_id      core_exe     core_perips       core_wb
                 ctl_ifid     ctl_exe      mem_ctl/clint     wb_mux_pc
                 ctl_perips                  axil_master
                 ctl_wb
```

- **Only one instruction in flight**: `core_ctl.v` advances a token one stage per cycle
  (`wb_token → if_token → ifid_token → exe_token → perips_token → wb_pending → wb_token`).

### Separated control / datapath

- Control: `ctl_ifid.v` (decode source select / exception detection), `ctl_exe.v` (ALU / next-PC function),
  `ctl_perips.v` (memory-access enable), `ctl_wb.v` (write-back select / write enable).
- Data: `core_id.v` (fields + immediate), `core_exe.v` (ALU + next), `core_wb.v` (write-back mux).

### Interrupt / exception paths

| Type          | Trigger           | mepc                                               | mcause         | Return  |
| ------------- | ----------------- | -------------------------------------------------- | -------------- | ------- |
| Timer interrupt| `mtip` (CLINT)   | **`perips_nextpc`** (real next PC of interrupted instr.) | `0x80000007` | `mret` |
| ecall/ebreak  | the instruction   | `pc` (faulting instr. address, software +4)         | `11` / `3`    | `mret` |

`intrpt` is a **register output** (not combinational), combined with the WB sample stage to redirect the PC.

### Memory map

| Address range                     | Peripheral                       | Access                 |
| --------------------------------- | -------------------------------- | ---------------------- |
| `0x0000_0000 ~ 0x0000_47FF` | Instruction memory 18KB          | IF synchronous read    |
| `0x0200_0000 ~ 0x0200_BFFF` | CLINT (mtime/mtimecmp, 50MHz)    | PERIPS fixed 1 cycle   |
| `0x1000_0000 ~ 0x1000_001F` | UART (AXI-Lite, 115200)          | PERIPS via axil_master |
| `0x2000_0000 ~ 0x2000_000F` | GPIO (low 4 bits LED, active-low)| PERIPS via axil_master |
| `0x8000_0000 ~ 0x8000_5FFF` | Data memory 24KB                 | PERIPS fixed 1 cycle   |

### UART registers (AXI-Lite, base 0x10000000)

Reference: Z-core

| Offset | Name     | Dir | Description                                                |
| ------ | -------- | --- | ---------------------------------------------------------- |
| 0x00   | TX_DATA  | W   | Transmit byte                                              |
| 0x04   | RX_DATA  | R   | Receive byte                                               |
| 0x08   | STATUS   | R   | bit0 tx_empty / bit1 tx_busy / bit2 rx_valid / bit3 rx_error|
| 0x0C   | CTRL     | R/W | Control                                                    |
| 0x10   | BAUD_DIV | R/W | Baud divider (50MHz/(16×115200)≈27)                      |

### RTOS task model

- Static task table (8 entries), `READY / RUNNING / WAITING` states,
  blocking reasons `WAIT_DELAY / WAIT_UART / WAIT_SUSPEND`.
- Preemptive round-robin: CLINT tick every 1ms → `kernel_tick` → `scheduler_switch`.
- Cooperative yield: `task_yield()` = `ecall`.
- 5 tasks: `idle` / `uart_rx` (10ms UART poll) / `shell` (CLI) / `led` (500ms blink) / `game` (Asteroids).
- Shell and Game share the UART input buffer via an "input ownership token" (`input.c`).

---

## Directory structure

```
yscore/
├── src/                 # Hardware Verilog
│   ├── core_*.v         # Pipeline stages
│   ├── ctl_*.v          # Control path
│   ├── exe_*.v          # ALU / next PC
│   ├── mem_*.v          # Data memory (rotating byte banks)
│   ├── axil_*.v         # AXI-Lite bus/peripherals
│   ├── regfile*.v       # Register file / CSR
│   ├── clint.v / top.v  # Timer / top
│   └── rvdef.vh         # Instruction/control encodings
├── tb/                  # ModelSim sim (regfile/CSR snapshot + disassembly + breakpoints)
├── simulation/modelsim/ # sim.do one-click sim
├── rtos/                # Firmware (CMake cross-compile)
│   ├── src/             # app/shell/game/input/main
│   ├── sys/             # kernel.c (scheduler) / mem.c
│   ├── port/            # Porting layer (QEMU/FPGA isolation)
│   ├── lib/             # uart/gpio/math/utils
│   ├── include/         # headers
│   ├── startup/         # startup + linker script
│   ├── bin2mem.py       # ELF → imem.mem / dmem0~3.mem
│   └── CMakeLists.txt
├── ins/                 # Instruction tests (RI/LS/branch/others/zicsr/except/test.c)
└── doc/learn/           # Full learning docs (see below)
```

---

## Quick Start

### 1. ModelSim simulation

```bash
cd d:/yscore/simulation/modelsim
vsim -do sim.do          # compile RTL + tb, run 1M cycles
```

### 2. Build firmware

```bash
cd d:/yscore/rtos
cmake -B build -G Ninja
ninja -C build           # → MiniRTOS.elf
ninja -C build dasm      # → disassembly
ninja -C build bin       # → *_text.bin / *_data.bin
ninja -C build mem       # → imem.mem + dmem0~3.mem (feed to hardware)
```

### 3. Run on QEMU (verify software first)

```bash
ninja -C build run       # qemu-system-riscv32 -nographic -machine virt \
                         #   -cpu rv32 -bios none -kernel MiniRTOS.elf
```

### 4. FPGA bring-up

1. Open `yscore.qpf` in Quartus and synthesize.
2. Program `yscore.sof` with the Programmer.
3. Connect a 115200 serial terminal; on boot you should see the banner and `RV32> ` prompt, with the LED blinking every 500ms.

### 5. Instruction tests

```bash
cd ins
riscv-none-elf-as -march=rv32i_zicsr RI.s -o RI.o
riscv-none-elf-ld -Ttext 0x00000000 RI.o -o RI.elf
riscv-none-elf-objcopy -O binary --only-section=.text RI.elf RI.bin
python bin2mem.py        # generate imem.mem
# Run in ModelSim; check x31's final value in the tb snapshot
```

---

## Full documentation

👉 **[Documentation index]({{ site.baseurl }}/learn/)**

Progress through the chapters:

- **00 Project Overview**: features / design principles (stage separation) / architecture / directory / Debug methodology.
- **01 Hardware Basics**: R → I → Load/Store → Branch → JAL/LUI/AUIPC → C test → CSR → exceptions → AXI → peripherals → FPGA.
- **02 Software Stack**: QEMU → runtime environment → multitasking → Shell → Game → porting → on-board Debug.
- **03 Debug Pitfalls**: hardware pitfalls (byte alignment / async read / mask bits), software pitfalls (input ownership),
  and a **complete HW/SW co-debug walkthrough** (typing help returns banner, hang after output, LED diagnosis,
  three nested bugs fixed layer by layer).

---

## Credits

- [SparrowRV](https://github.com/xiaowuzxc/SparrowRV): inspired the start of this project.
- **一生一芯 (YSC)** : Bilibili course series, reference for microarchitecture and pipeline design.
- [Z-Core](https://github.com/paudiaz99/Z-Core): reference for the AXI4-Lite GPIO / UART peripheral implementation.
