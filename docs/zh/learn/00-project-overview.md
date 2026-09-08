---
permalink: /zh/learn/00-project-overview/
---
# 00. 项目总览

## 1. 这是什么

**YScore**（Your Simple Core）是一个完全从零手写的 RISC-V SoC：

- **ISA**：RV32I + Zicsr（无乘法扩展 M，乘法用软件库 `rtos/lib/math.c` 模拟）。
- **流水线**：5 级多周期（IF → ID → EXE → PERIPS → WB）
- **总线**：手写 AXI4-Lite（1 主 3 从：UART / GPIO / CLINT），另有 2 个不走总线的固定延迟外设（DMEM、CLINT）。
- **软件**：裸机抢占式 RTOS + Shell 命令行 + Asteroids 游戏，C 语言编译，FPGA 上板运行。

项目包含 **硬件**（`src/`，Verilog）与 **固件**（`rtos/`，C + 汇编）两个独立工程，
通过 ELF → `bin2mem.py` → `*.mem` 文件对接。

## 2. 实现功能

| 类别     | 功能                                                                     | 对应代码                                                  |
| -------- | ------------------------------------------------------------------------ | --------------------------------------------------------- |
| 指令集   | RV32I 全指令（R/I/L/S/B/J/U/CSR）+ Zicsr                                 | `src/ctl_*.v`、`src/rvdef.vh`                         |
| 内部异常 | ecall / ebreak → mepc / mcause / mtvec / mret                           | `src/regfile_csr.v`、`src/ctl_ifid.v`                 |
| 外设     | UART（AXI4-Lite，115200）、GPIO（低电平点亮 LED）、CLINT（mtime 定时器） | `src/axil_uart.v`、`src/axil_gpio.v`、`src/clint.v` |
| 总线     | 手写 AXI4-Lite Master 状态机（读写五通道）                               | `src/axil_master.v`                                     |
| 内存     | 指令 18KB（同步读 M9K）、数据 24KB（4×6KB 字节 bank，滚筒式寻址）       | `src/core_if.v`、`src/mem_ctl.v`、`src/mem_cell.v`  |
| 软件     | 抢占式时间片轮转调度器、多任务、Shell、Asteroids                         | `rtos/sys/kernel.c` 等                                  |
| 联调     | QEMU 先行验证 + FPGA 上板，只需改 port 层                                | `rtos/port/*`                                           |

## 3. 设计原则：各阶段硬件分离

核心思想：**一条指令的各个阶段解耦成独立模块**，每个模块只负责一件事，之间用明确的接口与
"token"（令牌）衔接。这样定位 bug 时能直接锁到某一个阶段，而不是在一大坨状态机里翻。

> **配套设计流程**：本项目每段硬件都遵循 **① drawio 画设想波形（`src/wave.drawio`）
> → ② 画架构图明确线网（`src/arch.drawio`）→ ③ 写 Verilog** 的顺序，
> 写完后对照 ModelSim 波形逐拍核对。这套方法正是为了规避"漏打一拍"和"线网混乱"
> 两类最难查的硬件 bug，详见 `01-hardware-basics`。

```
IF 阶段   core_if     同步读指令存储器（M9K），一拍后出指令
ID 阶段   core_id      拆字段 + 立即数扩展
         ctl_ifid     译码：ALU源选择 / 立即数类型 / 异常与mret识别
         ctl_exe      ALU功能码 + 下一PC功能码
         ctl_perips   是否需要访存/外设（peripsen）
         ctl_wb       回写选择 + 寄存器写使能 + CSR写使能
EXE 阶段  core_exe     exe_alu（33bit 进位/借位）+ exe_next（分支/跳转目标计算）
PERIPS 阶段 core_perips 地址译码 + 三种外设访问路径（MEM固定1拍 / CLINT固定1拍 / AXI握手）
WB 阶段   core_wb     写回数据选择（ALU/Load/PC4/CSR/LUI/AUIPC）
         wb_mux_pc    下一 PC 选择（顺序/分支目标/跳转目标/mtvec/mepc）
         regfile_csr  CSR 寄存器堆 + 异常/中断状态更新 + intrpt 产生
```

控制通路（`ctl_*`）与数据通路（`core_*`、`exe_*`、`ifid_*`）完全分离，
这在后面的 Debug 章节会反复体现：**先看 ctl 是否给了正确控制信号，再看 data 是否走了正确的通路**。

## 4. 整体架构

```
                 ┌──────────────────────────────────────────────┐
                 │                  core_ctl                    │
                 │  (token 串行状态机 + 流水线寄存器 + 异常通道)   │
                 └────┬────────┬────────┬──────────┬────────────┘
                      │        │        │          │
   core_if     core_id     core_exe    core_perips    core_wb
   (取指)      (译码)      (运算+跳转)  (访存/外设)    (写回+选PC)
                      │        │        │          │
              ┌───────┴────────┴───┬────┴──────────┴──────┐
              │   regfile(32×32)   │  mem_ctl(24KB)       │
              │   regfile_csr(CSR) │  clint(mtime)        │
              │                    │  axil_master→        │
              │                    │    axil_uart         │
              │                    │    axil_gpio         │
              └────────────────────┴──────────────────────┘
```

**token 串行**：`core_ctl.v` 用一个 if-else 链，每拍只推进一个 token
（`wb_token → if_token → ifid_token → exe_token → perips_token → wb_pending → wb_token`），
保证同一时刻只有一条指令在流水线里。多周期体现在：PERIPS 阶段的 AXI 访问会暂停若干拍，
WB 阶段分"退休拍 + 采样拍"两拍（详见 07 章与 03-debug-pitfalls/03）。

**地址映射**（`src/core_perips.v:24-27` 译码）：

| 地址区间                    | 外设                    | 访问方式                         |
| --------------------------- | ----------------------- | -------------------------------- |
| `0x0000_0000~0x0000_47FF` | 指令存储器 18KB         | IF 阶段同步读（不进 PERIPS）     |
| `0x8000_0000~0x8000_5FFF` | 数据存储器 24KB         | PERIPS 固定 1 拍（`is_mem`）   |
| `0x0200_0000~0x0200_BFFF` | CLINT（mtime/mtimecmp） | PERIPS 固定 1 拍（`is_clint`） |
| `0x1000_0000~0x1000_001F` | UART（AXI-Lite）        | PERIPS 经`axil_master` 握手    |
| `0x2000_0000~0x2000_000F` | GPIO（AXI-Lite）        | PERIPS 经`axil_master` 握手    |

## 5. 项目目录说明

```
yscore/
├── src/                # 硬件 Verilog（顶层 top.v → core_ctl.v → 各阶段/外设模块）
├── tb/                 # ModelSim 仿真（mycpu_sim.v：寄存器/CSR 快照 + 指令打印）
├── simulation/modelsim/ # ModelSim 工程（sim.do 一键编译运行）
├── rtos/               # 固件工程（CMake + riscv-none-elf-gcc）
│   ├── src/            # 应用层（app/shell/game/input/main）
│   ├── sys/            # 内核（kernel.c 调度器 + mem.c）
│   ├── port/           # 移植层（portmacro.h/portASM.S/interrupt/critical/timer）
│   ├── lib/            # 驱动与工具（uart/gpio/math/utils）
│   ├── include/        # 头文件
│   ├── startup/        # 启动脚本 + 链接脚本
│   ├── bin2mem.py      # ELF → imem.mem / dmem0~3.mem
│   └── CMakeLists.txt  # 交叉编译
├── ins/                # 汇编/C 测试用例（RI/LS/branch/others/zicsr/except/test.c）
└── doc/learn/          # 本学习文档
```

## 6. Debug 方法论（贯穿全文）

本项目排错形成了一套可复用流程，各 Debug 章节都会用到：

1. **现象 → 怀疑**：先明确"是什么坏了"（不打印？卡死？LED 状态？），列出最可能的嫌疑。
2. **锁定层面**：先软件后硬件，用 map/dasm 反汇编排除软件层。
3. **仿真定位**：ModelSim 跑 `sim.do`，用 tb 里的寄存器/CSR 快照与波形找到"跑崩的 PC/指令"。
4. **读硬件数据流**：顺着该指令从 IF 到 WB 逐级看 ctl 控制信号与 data 值。
5. **改一处、验证一轮**：改完必须重新仿真/上板回归，防止"修好 A 弄坏 B"。

关键工具：

- `riscv-none-elf-objdump -D -h -z` 反汇编（`ninja dasm`）。
- ModelSim `simulation/modelsim/sim.do`（见 01-hardware-basics/01 的仿真说明）。
- tb 支持命令行覆盖断点：`+STOP_PC=0x...`（`tb/mycpu_sim.v:357`）。

