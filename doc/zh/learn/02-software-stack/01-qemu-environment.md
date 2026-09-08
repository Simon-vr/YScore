---
permalink: /zh/learn/02-software-stack/01-qemu-environment/
---
# 01. QEMU 开发环境

## 1. 为什么用 QEMU

自家 FPGA CPU 每次上板都要重新综合烧录（分钟级），而且硬件有 bug 时很难区分
"CPU 设计错了"还是"软件写错了"。QEMU 提供**标准的 RISC-V 模拟**（严格实现规范），
先用它在模拟器上把软件逻辑调对，再移植上板——这样上板出问题时就聚焦在硬件。

## 2. 运行方式

`rtos/CMakeLists.txt` 里定义了 `run`/`debug`/`gdb` 目标（QEMU 版）或 `mem` 目标（FPGA 版）：

```cmake
add_custom_target(run
    COMMAND qemu-system-riscv32 -nographic -machine virt -cpu rv32 \
            -bios none -kernel MiniRTOS.elf
    DEPENDS MiniRTOS.elf)
```

命令拆解（QEMU 8.2.2）：
- `-nographic`：把 UART 接到当前终端（无图形窗口）。
- `-machine virt`：QEMU 的通用 virt 平台。
- `-cpu rv32`：RV32 内核。
- `-bios none`：不用 OpenSBI/固件，直接从 0x80000000 跑 `_start`（全程 M 模式）。
- `-kernel MiniRTOS.elf`：加载内核 ELF。

## 3. QEMU virt 的地址空间（与 FPGA 的对照）

| 地址 | QEMU virt | FPGA yscore |
|------|-----------|-------------|
| 0x80000000 | 内核加载点（RAM） | 数据存储器 0x80000000 |
| 0x10000000 | NS16550 UART | axil_uart |
| 0x02000000 | CLINT（10MHz） | CLINT（50MHz） |
| GPIO | 无 | 0x20000000 |

对照参考笔记：`qemu_virt内存空间.md`。

## 4. port 层如何隔离差异

QEMU 与 FPGA 的差异全部收敛在 `rtos/port/`：

- **UART 寄存器布局**：QEMU 是 NS16550（RBR/THR 同址 0x0、LSR 在 0x5），
  FPGA 是 axil_uart（THR@0x0、RBR@0x4、STAT@0x8）——差别在 `portmacro.h` 的寄存器定义。
- **CLINT 频率**：QEMU mtime 10MHz（1ms=10000 计数），FPGA 50MHz（1ms=50000）——
  差别在 `port/timer.c` 的 `ulTimerIncrementsForOneTick`。
- **上下文帧**：`portmacro.h` 的 SAVE/RESTORE_CONTEXT 宏与 `portASM.S` 完全一致
  （144 字节帧，mstatus@124、mepc@128），QEMU 与 FPGA 通用。
- **GPIO**：QEMU 无 GPIO，`lib/gpio.c` 在 QEMU 退化为软件模拟（见 `include/gpio.h` 注释）。

其余（`sys/kernel.c`、`src/*.c`、`lib/*.c`）逐字复用。

## 5. 调试技巧

- **反汇编**：`riscv-none-elf-objdump -D -h -z MiniRTOS.elf` 或 `ninja dasm`。
- **GDB**：`ninja debug`（QEMU 挂 `-gdb tcp::1234 -S`）后 `ninja gdb` 连接，
  可打断点、单步、看寄存器（这是定位"跑飞/卡死"最有力的手段）。
- **对比运行**：同一份代码，QEMU 上行为正确 + FPGA 上行为异常 → 问题在硬件；
  两者都异常 → 问题在软件。这个二分法是本项目联调的主线（见 03-debug-pitfalls）。