---
permalink: /learn/02-software-stack/01-qemu-environment/
lang: en
---
# 01. QEMU Development Environment

## 1. Why QEMU

Our own FPGA CPU requires a full synthesis and re-flash each time it is brought up
(minutes per iteration), and when there is a hardware bug it is hard to tell whether
the "CPU design is wrong" or "the software is wrong". QEMU provides **standard RISC-V
simulation** (strictly implementing the spec), so we first get the software logic
correct on the simulator and then port it onto the board — that way, when problems
arise on the board, we can focus on the hardware.

## 2. How to Run

`rtos/CMakeLists.txt` defines the `run`/`debug`/`gdb` targets (QEMU version) and the
`mem` target (FPGA version):

```cmake
add_custom_target(run
    COMMAND qemu-system-riscv32 -nographic -machine virt -cpu rv32 \
            -bios none -kernel MiniRTOS.elf
    DEPENDS MiniRTOS.elf)
```

Command breakdown (QEMU 8.2.2):
- `-nographic`: connects the UART to the current terminal (no graphical window).
- `-machine virt`: QEMU's generic virt platform.
- `-cpu rv32`: RV32 core.
- `-bios none`: does not use OpenSBI/firmware; runs `_start` directly from 0x80000000 (all in M mode).
- `-kernel MiniRTOS.elf`: loads the kernel ELF.

## 3. QEMU virt Address Space (vs FPGA)

| Address | QEMU virt | FPGA yscore |
|---------|-----------|-------------|
| 0x80000000 | Kernel load point (RAM) | Data memory 0x80000000 |
| 0x10000000 | NS16550 UART | axil_uart |
| 0x02000000 | CLINT (10MHz) | CLINT (50MHz) |
| GPIO | none | 0x20000000 |

## 4. How the port Layer Isolates Differences

The differences between QEMU and FPGA all converge in `rtos/port/`:

- **UART register layout**: QEMU uses NS16550 (RBR/THR share address 0x0, LSR at 0x5),
  while the FPGA uses axil_uart (THR@0x0, RBR@0x4, STAT@0x8) — the difference is in the
  register definitions in `portmacro.h`.
- **CLINT frequency**: QEMU mtime is 10MHz (1ms = 10000 counts), FPGA is 50MHz
  (1ms = 50000) — the difference is in `ulTimerIncrementsForOneTick` in `port/timer.c`.
- **Context frame**: the SAVE/RESTORE_CONTEXT macros in `portmacro.h` match `portASM.S`
  exactly (144-byte frame, mstatus@124, mepc@128), common to both QEMU and FPGA.
- **GPIO**: QEMU has no GPIO, so `lib/gpio.c` degrades to software simulation on QEMU
  (see the comments in `include/gpio.h`).

Everything else (`sys/kernel.c`, `src/*.c`, `lib/*.c`) is reused verbatim.

## 5. Debugging Tips

- **Disassembly**: `riscv-none-elf-objdump -D -h -z MiniRTOS.elf` or `ninja dasm`.
- **GDB**: `ninja debug` (QEMU starts with `-gdb tcp::1234 -S`) then `ninja gdb` to connect;
  you can set breakpoints, single-step, and inspect registers (this is the most powerful
  tool for locating "runaway/hang" bugs).
- **Compare runs**: with the same code, if QEMU behaves correctly but the FPGA does not,
  the problem is in the hardware; if both misbehave, the problem is in the software.
  This dichotomy is the main thread of joint debugging in this project (see 03-debug-pitfalls).
