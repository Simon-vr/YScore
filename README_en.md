> 🌐 **Language / 语言：** [**简体中文**](README.md) · [**English**](README_en.md)

---

# YScore — An RV32I SoC from Scratch That Runs C

> **Yes! core / Your Simple Core** —— A hand-written Verilog 5-stage multi-cycle RISC-V processor + AXI4-Lite bus adapter + bare-metal RTOS.

---

## Demo

![Demo video](doc/image/README_zh/show.mp4)

![Hardware architecture](doc/image/README_zh/arch.svg)

---

## What's Inside

- **Processor**: RV32I + Zicsr ISA, 5-stage multi-cycle pipeline (IF → ID → EXE → PERIPS → WB), with internal `ecall`/`ebreak` exceptions and CLINT timer interrupts.
- **Bus & Peripherals**: AXI4-Lite Master (read/write 5-channel handshake FSM) driving UART (AXI-Lite slave, 115200), GPIO (active-low LED), CLINT (64-bit `mtime`).
- **Memory**: 18KB instruction memory + 24KB data memory (4×6KB byte banks, barrel addressing for 8/16/32-bit).
- **Software**: bare-metal preemptive round-robin RTOS, Shell CLI + Asteroids game, C cross-compilation ready.
- **Co-verification**: QEMU (standard RV32) first, then port to FPGA by changing only the `port` layer.

---

## Hardware Requirements

| Item            | Version/Model                                  |
| --------------- | ---------------------------------------------- |
| Board           | EmbedFire Altera EP4CE10 Zhengtu Pro (Cyclone IV E) |
| Synthesis tool  | Quartus Prime 25.1 Standard Edition            |
| Simulation tool | ModelSim 20.1                                  |
| Cross compiler  | RISC-V GCC 15.2.0 (xPack) `riscv-none-elf-gcc` |
| Build tool      | CMake ≥ 3.20 + Ninja                           |
| Emulator        | QEMU `qemu-system-riscv32`                     |
| OS              | Windows 11 / WSL                               |

**Resource usage**: ~10K LE, 6~7 M9K blocks (18KB IMEM + 24KB DMEM). See the Quartus
compile report and `doc/learn/01-hardware-basics/11-fpga-deployment.md`.

---

## System Architecture

### Pipeline: token-serial multi-cycle

```
   ┌────────┐   ┌────────┐   ┌────────┐   ┌─────────────┐   ┌──────────┐
   │  IF    │ → │  ID    │ → │  EXE   │ → │   PERIPS    │ → │   WB     │
   │ fetch  │   │ decode │   │  ALU   │   │ mem/io      │   │ writeback│
   └────────┘   └────────┘   └────────┘   └─────────────┘   └──────────┘
     core_if     core_id      core_exe     core_perips       core_wb
                 ctl_ifid     ctl_exe      mem_ctl/clint     wb_mux_pc
                 ctl_perips                  axil_master
                 ctl_wb
```

- **Only one instruction at a time**: `core_ctl.v` advances the token with an if-else chain each
  cycle (`wb_token → if_token → ifid_token → exe_token → perips_token → wb_pending → wb_token`).

### Separate control / datapath

- Control: `ctl_ifid.v` (decode source select / exception detect), `ctl_exe.v` (ALU / next-PC),
  `ctl_perips.v` (mem-enable), `ctl_wb.v` (writeback select / write-enable).
- Datapath: `core_id.v` (fields + immediate), `core_exe.v` (ALU + next), `core_wb.v` (writeback mux).

### Interrupt / exception path

| Type         | Trigger           | mepc                                             | mcause         | Return |
| ------------ | ----------------- | ------------------------------------------------ | -------------- | ------ |
| Timer IRQ    | `mtip` (CLINT)    | **`perips_nextpc`** (real next PC of the interrupted instruction) | `0x80000007` | `mret` |
| ecall/ebreak | the instruction   | `pc` (faulting instr addr, software +4)          | `11` / `3`     | `mret` |

`intrpt` is a **register output** (not combinational) and, together with the WB sample cycle,
completes the PC redirection.

### Memory map

| Address range                 | Peripheral                      | Access            |
| ----------------------------- | ------------------------------- | ----------------- |
| `0x0000_0000 ~ 0x0000_47FF` | Instruction memory 18KB         | IF sync read      |
| `0x0200_0000 ~ 0x0200_BFFF` | CLINT (mtime/mtimecmp, 50MHz)   | PERIPS fixed 1 cyc |
| `0x1000_0000 ~ 0x1000_001F` | UART (AXI-Lite, 115200)         | PERIPS via axil_master |
| `0x2000_0000 ~ 0x2000_000F` | GPIO (low 4 bits LED, active-low) | PERIPS via axil_master |
| `0x8000_0000 ~ 0x8000_5FFF` | Data memory 24KB                | PERIPS fixed 1 cyc |

### UART registers (AXI-Lite, base 0x10000000)

Referenced from Z-core

| Offset | Name     | Dir  | Description                                          |
| ------ | -------- | ---- | ---------------------------------------------------- |
| 0x00   | TX_DATA  | W    | Transmit byte                                        |
| 0x04   | RX_DATA  | R    | Receive byte                                         |
| 0x08   | STATUS   | R    | bit0 tx_empty / bit1 tx_busy / bit2 rx_valid / bit3 rx_error |
| 0x0C   | CTRL     | R/W  | Control                                              |
| 0x10   | BAUD_DIV | R/W  | Baud divider (50MHz/(16×115200)≈27)                  |

### RTOS task model

- Static task table (8 slots), `READY / RUNNING / WAITING` states, block reasons
  `WAIT_DELAY / WAIT_UART / WAIT_SUSPEND`.
- Preemptive round-robin: CLINT ticks every 1ms → `kernel_tick` → `scheduler_switch`.
- Cooperative yield: `task_yield()` = `ecall`.
- 5 tasks: `idle` / `uart_rx` (10ms poll) / `shell` (CLI) / `led` (500ms blink) / `game` (Asteroids).
- Shell and Game share the UART input buffer via an "input ownership token" (`input.c`).

---

## Directory layout

```
yscore/
├── src/                 # Hardware Verilog
│   ├── core_*.v         # Pipeline stages
│   ├── ctl_*.v          # Control path
│   ├── exe_*.v          # ALU / next-PC
│   ├── mem_*.v          # Data memory (barrel byte banks)
│   ├── axil_*.v         # AXI-Lite bus / peripherals
│   ├── regfile*.v       # Register file / CSR
│   ├── clint.v / top.v  # Timer / top level
│   └── rvdef.vh         # Instruction / control encodings
├── tb/                  # ModelSim sim (regfile/CSR snapshot + disasm + breakpoints)
├── simulation/modelsim/ # One-click sim via sim.do
├── rtos/                # Firmware (CMake cross-compile)
│   ├── src/             # app/shell/game/input/main
│   ├── sys/             # kernel.c (scheduler) / mem.c
│   ├── port/            # port layer (QEMU/FPGA isolation)
│   ├── lib/             # uart/gpio/math/utils
│   ├── include/         # headers
│   ├── startup/         # startup script + linker script
│   ├── bin2mem.py       # ELF → imem.mem / dmem0~3.mem
│   └── CMakeLists.txt
├── ins/                 # Instruction tests (RI/LS/branch/others/zicsr/except/test.c)
├── refer/               # Study notes (CSR/interrupt/mstatus/linker script, etc.)
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

### 3. Run on QEMU (software-first verification)

```bash
ninja -C build run       # qemu-system-riscv32 -nographic -machine virt \
                         #   -cpu rv32 -bios none -kernel MiniRTOS.elf
```

### 4. FPGA deployment

1. Open `yscore.qpf` in Quartus and synthesize.
2. Program `yscore.sof` via the Programmer.
3. Connect a serial terminal at 115200; on boot you should see the banner and `RV32> ` prompt, with the LED blinking every 500ms.

### 5. Instruction tests

```bash
cd ins
riscv-none-elf-as -march=rv32i_zicsr RI.s -o RI.o
riscv-none-elf-ld -Ttext 0x00000000 RI.o -o RI.elf
riscv-none-elf-objcopy -O binary --only-section=.text RI.elf RI.bin
python bin2mem.py        # generate imem.mem
# Run ModelSim sim; check final x31 value in the tb snapshot
```

---

## Full Learning Docs

👉 **[doc/learn/](doc/learn/)**

Progress chapter by chapter:

- **00 Project overview**: features / design principles (stage separation) / architecture / layout / Debug methodology.
- **01 Hardware basics**: R → I → Load/Store → Branch → JAL/LUI/AUIPC → C test → CSR → exception → AXI → peripherals → FPGA.
- **02 Software stack**: QEMU → runtime environment → multitasking → Shell → Game → porting → on-board Debug.
- **03 Debug pitfalls**: hardware gotchas (byte alignment / async read / mask bits), software gotchas (input ownership),
  plus a **full hardware+software Debug record** (typing `help` returns banner, output then hangs, LED diagnostics,
  three nested bugs fixed layer by layer).

---

## References & Thanks

- [SparrowRV](https://github.com/xiaowuzxc/SparrowRV): inspired the start of this project.
- **一生一芯** (One Student One Chip): Bilibili lecture series, reference for architecture and pipeline design.
- [Z-Core](https://github.com/paudiaz99/Z-Core): reference for the AXI4-Lite GPIO / UART peripherals.

---

> 🌐 **Language / 语言：** [**简体中文**](README.md) · [**English**](README_en.md)
