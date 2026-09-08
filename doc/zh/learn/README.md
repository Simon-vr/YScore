---
permalink: /zh/learn/
---
# YScore 文档导航

本目录是 YScore SoC 的完整文档，从零开始记录这颗 CPU 的硬件设计、软件栈与联调排错全过程。

## 目录总览

```
doc/learn/
├── README.md                  ← 本文件（导航）
├── 00-project-overview.md     ← 项目总览：功能 / 设计原则 / 架构 / 目录 / Debug 方法论
│
├── 01-hardware-basics/        ← 硬件部分（按指令集逐类实现顺序）
│   ├── README.md
│   ├── 00-design-flow.md        ★ 硬件设计流程：先波形(wave.drawio)→再架构(arch.drawio)→后写码
│   ├── 01-r-instructions.md       R 指令（数据通路 + 控制通路 + RI.s 测试）
│   ├── 02-i-instructions.md       I 指令（ADDI/ANDI/... + RI.s 测试）
│   ├── 03-ls-instructions.md      Load/Store 指令（mem_ctl 滚筒式字节存储 + LS.s）
│   ├── 04-branch-instructions.md  分支指令（exe_next 跳转判定 + branch.s）
│   ├── 05-other-instructions.md   JAL/JALR/LUI/AUIPC（others.s）
│   ├── 06-c-language-test.md      C 语言编译测试（test.c / ELF / bin2mem 流程）
│   ├── 07-csr-implementation.md   CSR 硬件实现（regfile_csr.v + zicsr.s）
│   ├── 08-exception-handling.md   内部异常通路（ecall/ebreak + except.s）
│   ├── 09-axi-peripherals.md      AXI4-Lite 总线（五通道握手 / axil_master 状态机）
│   ├── 10-uart-gpio-adaptation.md UART / GPIO 外设适配
│   ├── 11-fpga-deployment.md      Quartus 综合 / ModelSim 仿真 / 资源占用
│   └── 12-tb-simulation-guide.md  ★ 仿真测试平台 mycpu_sim.v 详解（快照/反汇编/STOP_PC + sim.do）
│
├── 02-software-stack/         ← 软件部分（RTOS 固件）
│   ├── README.md
│   ├── 01-qemu-environment.md     QEMU 开发环境与运行原理
│   ├── 02-runtime-environment.md  运行时环境（链接 / 启动 / 中断 / 栈 / port / lib）
│   ├── 03-multitasking.md         多任务系统（调度 / 任务状态 / 上下文切换）
│   ├── 04-shell-implementation.md Shell 程序（命令解析 / 回显 / 输入所有权）
│   ├── 05-game-implementation.md  Game 程序（Asteroids 游戏 / 渲染 / 输入竞争）
│   ├── 06-porting-guide.md        从 QEMU 移植到 FPGA（只改 port 层）
│   └── 07-post-port-debug.md      移植后 Debug 指南（上板定位流程）
│
└── 03-debug-pitfalls/         ← Debug 踩坑指南（**推荐先读**）
    ├── README.md
    ├── 01-hardware-pitfalls.md     硬件部分坑（字节对齐 / 异步读 / 掩码位）
    ├── 02-software-pitfalls.md     软件部分坑（UART 缓冲共享 / 令牌机制）
    └── 03-hw-sw-co-debug.md        硬软结合 Debug 完整实录（本次对话中的 bug）
```

## 推荐阅读顺序

1. **通读** `00-project-overview.md` 建立整体认知。
2. **硬件入门**：先读 `01-hardware-basics/00-design-flow.md`（设计流程），
   再按编号顺序从 R 指令到 AXI 总线逐步搭建。
3. **软件入门**：按 `02-software-stack/` 编号顺序，从 QEMU 环境到 RTOS 多任务。
4. **排错能力**：`03-debug-pitfalls/` 三个文件记录了三类典型的排错过程，其中
   `03-hw-sw-co-debug.md` 记录了本项目真实发生的、层层递进的硬软联调 bug，
   强烈建议在遇到相似症状时对照阅读。

## 代码引用约定

- 硬件：`src/<模块>.v:<行号>`，例如 `src/regfile_csr.v:79`。
- 软件：`rtos/<子目录>/<文件>.<扩展名>:<行号>`，例如 `rtos/sys/kernel.c:113`。
- 测试：`ins/<文件>.<扩展名>`。
- 全部引用均可直接跳转到对应源码，方便边读边查。
