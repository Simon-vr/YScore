---
permalink: /learn/02-software-stack/
lang: en
---
# 02. Software Stack

This part corresponds to the `rtos/` firmware project: from the QEMU development
environment and the runtime environment, to the RTOS multitasking, Shell, Game,
and the porting philosophy of "only modify the port layer".

```
02-software-stack/
├── README.md
├── 01-qemu-environment.md     QEMU development environment
├── 02-runtime-environment.md  Runtime environment (link/startup/interrupt/stack/port/lib)
├── 03-multitasking.md         Multitasking system
├── 04-shell-implementation.md Shell program
├── 05-game-implementation.md  Game program
├── 06-porting-guide.md        Porting from QEMU to FPGA
└── 07-post-port-debug.md      Post-port Debug guide
```

## Design Principles

**Software first, hardware second**: software is first verified on QEMU (a standard
RISC-V simulator) for correct logic, then the same C code is ported to our own FPGA
CPU through the `port` layer. The `port` layer is the single isolation point for all
hardware-specific code; the upper layers (`sys/kernel.c`, `src/shell.c`, etc.) are
hardware-independent.

```
                    QEMU (standard rv32)              FPGA (yscore CPU)
                     ┌────────────┐               ┌────────────┐
  upper src/sys/lib  │ same code  │               │ same code  │
  port layer         │ NS16550     │               │ axil_uart   │
                     │ 10MHz CLINT │               │ 50MHz CLINT │
                     └────────────┘               └────────────┘
```
