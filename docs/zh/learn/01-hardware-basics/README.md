---
permalink: /zh/learn/01-hardware-basics/
---
# 01. 硬件基础（按指令实现顺序）

这一部分按照本项目实际的硬件搭建顺序组织：先做 R 指令，再逐类扩展指令集，
每类指令都有对应的数据通路、控制通路说明和 `ins/` 下的测试用例。

```
01-hardware-basics/
├── README.md
├── 00-design-flow.md          ★ 硬件设计流程：先波形(wave.drawio)→再架构(arch.drawio)→后写码
├── 01-r-instructions.md       R 指令
├── 02-i-instructions.md       I 指令
├── 03-ls-instructions.md      Load/Store 指令
├── 04-branch-instructions.md  分支指令
├── 05-other-instructions.md   JAL/JALR/LUI/AUIPC
├── 06-c-language-test.md      C 语言编译测试
├── 07-csr-implementation.md   CSR 硬件
├── 08-exception-handling.md   内部异常通路
├── 09-axi-peripherals.md      AXI4-Lite 总线
├── 10-uart-gpio-adaptation.md UART/GPIO 适配
├── 11-fpga-deployment.md      FPGA 综合部署
└── 12-tb-simulation-guide.md  ★ 仿真测试平台 tb/mycpu_sim.v 详解 + sim.do 一键运行
```

> **⭐ 强烈建议先读 `00-design-flow.md`**：它总结了本项目"先画波形、再画架构、
> 后写代码"的硬件设计方法，理解它才能看懂后面每章"数据通路/控制通路"的来历。
>
> **💡 配合阅读 `12-tb-simulation-guide.md`**：仿真测试平台的使用方法
> （寄存器/CSR 快照、STOP_PC 断点、sim.do 一键跑），每一章测试都靠它验证。

## 阅读前提

- 先通读 `00-project-overview.md`，了解阶段分离与 token 串行的整体思想。
- 熟悉 RV32I 指令编码（opcode / funct3 / funct7 / 立即数布局）。
- 会用 ModelSim 跑仿真（见 01-r-instructions.md 的仿真说明）与 objdump 看反汇编。

## 每章结构约定

每章按以下套路展开，方便对照代码：

1. **指令编码**：该指令在 `src/rvdef.vh` 中的定义。
2. **数据通路**：操作数如何从寄存器/立即数进入 ALU。
3. **控制通路**：`ctl_*` 模块给出哪些控制信号、作用在哪。
4. **写回与下一 PC**：`core_wb` / `exe_next` / `wb_mux_pc` 怎么处理。
5. **测试**：`ins/` 对应测试文件与验证方法。