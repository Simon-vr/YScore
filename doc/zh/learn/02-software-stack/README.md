---
permalink: /zh/learn/02-software-stack/
---
# 02. 软件栈

这一部分对应 `rtos/` 固件工程：从 QEMU 开发环境、运行时环境，到 RTOS 多任务、
Shell、Game，以及"只需改 port 层"的移植思想。

```
02-software-stack/
├── README.md
├── 01-qemu-environment.md     QEMU 开发环境
├── 02-runtime-environment.md  运行时环境（链接/启动/中断/栈/port/lib）
├── 03-multitasking.md         多任务系统
├── 04-shell-implementation.md Shell 程序
├── 05-game-implementation.md  Game 程序
├── 06-porting-guide.md        从 QEMU 移植到 FPGA
└── 07-post-port-debug.md      移植后 Debug 指南
```

## 设计原则

**先软件后硬件**：软件先在 QEMU（标准 RISC-V 模拟器）上验证逻辑正确，
再把相同的 C 代码通过 `port` 层移植到自家 FPGA CPU。`port` 层是硬件相关的全部隔离点，
上层（`sys/kernel.c`、`src/shell.c` 等）与硬件无关。

```
                    QEMU (标准 rv32)              FPGA (yscore CPU)
                     ┌────────────┐               ┌────────────┐
  上层 src/sys/lib   │ 相同代码    │               │ 相同代码    │
  移植层 port        │ NS16550     │               │ axil_uart   │
                     │ 10MHz CLINT │               │ 50MHz CLINT │
                     └────────────┘               └────────────┘
```