---
permalink: /zh/learn/03-debug-pitfalls/03-hw-sw-co-debug/
---
# 03. 硬软结合 Debug 完整实录

> 这是本项目**最核心**的一章：一次真实发生在软硬联调阶段的 bug 排查全过程。
> 症状不断变化、层层逼近，最终定位到硬件流水线里一个非常隐蔽的中断语义错误。
> 完整对应 `doc/todo.md` 里"软硬结合部分"的记录。

---

## 第 0 轮：症状

上板后系统基本可用，但出现两个诡异现象：

1. **输入输出不匹配**：在 shell 输入 `help`，返回的却是 `banner` 的 ASCII 大图。
2. **输出后整机卡死**：执行一次较长输出（如 `help` 的几十行文本）后，
   系统不再响应任何输入，LED 停在一个状态。

> 反汇编排除了"命令表错"：`shell_parse_line` 里 `help` 是最先且全串精确匹配的
> （`utils_streq`），`help` 绝无可能匹配到 `banner` 分支。**所以错位一定来自执行流错乱，
> 不是软件逻辑。**

---

## 第 1 轮：怀疑堆栈溢出

**症状**：输出后卡死 → 最先怀疑 **任务栈溢出**（UART 输出用了栈上缓冲）。

**排查**：把任务栈开到最大（`app.c` 的 `idle/rx/shell/led/game` 栈都加大）。

**结果**：无效。卡死依旧。

**结论**：不是栈溢出。转向中断优先级怀疑。

---

## 第 2 轮：怀疑外中断优先级 / 抢占

**症状不变**。开始怀疑**中断与 CSR 指令的优先级冲突**。

**排查**：当时 `regfile_csr.v` 的 `intrpt` 是**组合逻辑**：

```verilog
assign intrpt = perips_token && csr[0][3] && csr[2][7] && mtip;
```

`core_ctl` 的 PC 重定向只看这个 `intrpt`，但 CSR 写（`csrci mstatus` 清 MIE 等）
在 `regfile_csr` 的 if-else 里**优先级高于**中断分支。于是当一条 CSR 指令退休
恰好撞上 `mtip` 时：PC 被重定向进 trap，但 `mepc/mcause` 是**上一次 trap 的陈旧值**
（幻影 trap）→ 返回地址错乱。

**修改 1**：把 `intrpt` 改成**寄存器输出**（`regfile_csr.v:23`），
只在中断捕获分支置位，其余清 0；并给 WB 阶段加一拍（`core_ctl.v` 增加 `wb_pending`）
让寄存器化的 `intrpt` 在采样拍可见，再重定向 PC。

**结果**：**依然卡死**，但症状变为"**一开机就卡死，GPIO 一直亮灯**"。

> 这一步"修对了机制、暴露了新 bug"——见第 3 轮。

---

## 第 3 轮：WB 阶段异常写入非幂等 → MIE 永远为 0

**新症状**：开机就卡死，GPIO 常亮（低电平点亮，GPIO 复位即全亮）。

**排查**：因为给 WB 加了"退休拍 + 采样拍"（`core_ctl.v:444-451`），
`perips_token` 在退休期间持续 **2 拍**。而 `regfile_csr` 的异常分支（ecall）写：

```verilog
csr[0][7] <= csr[0][3];   // MPIE = MIE
csr[0][3] <= 1'b0;        // MIE = 0
```

在连续两个时钟沿各执行一次：

```
第1拍沿: MPIE ← MIE(=1)    MIE ← 0
第2拍沿: MPIE ← MIE(现=0)  MIE ← 0   ← MPIE 被踏成 0！
```

`MPIE←MIE` 读取的是**当前** MIE，第 2 拍时 MIE 已被第 1 拍清零，
于是 MPIE 被写成 0。之后任务恢复时 `mret` 执行 `MIE←MPIE=0`——
**mstatus.MIE 永久为 0**，1ms 定时器中断永远无法触发 → 时钟中断失效 →
所有依赖 tick 的任务（uart_rx、led）睡死 → GPIO 停在复位亮灯状态、无任何响应。

**定位证据**：ModelSim 里看第一个 `ecall`（`task_yield`）后
mstatus = `0x1800`（MPIE=0）而非 `0x1880`（MPIE=1）。

**修改 2**：让"退休拍"只生效一拍（所有副作用只提交一次），
第 2 拍独立为"采样拍"只用来等寄存器化的 `intrpt` 可见后做 PC 重定向：

```verilog
end else if (perips_token && !wb_token) begin
    perips_token <= 1'b0;     // 退休拍：GPR/CSR/异常/中断捕获只本拍沿生效
    wb_pending   <= 1'b1;
end else if (wb_pending && !wb_token) begin
    wb_pc        <= wb_pc_w;  // 采样拍：intrpt 可见 → 重定向 PC
    wb_token     <= 1'b1;
    wb_pending   <= 1'b0;
end
```

**结果**：系统能跑起来了（banner 打印、LED 闪烁），但**症状变为"灯闪两下就卡死"**——
进入第 4 轮。

---

## 第 4 轮（根因）：中断保存 `pc+4` 而非真实下一 PC

**症状**：中断正常工作了，但"输入 help 返回 banner"仍在。

**深入排查**：既然命令表没错、调度也活了，那"help→banner"只剩一种可能——
**执行流在某处被错误地回跳/错位**。聚焦中断的 `mepc` 保存逻辑：

`regfile_csr.v` 中断捕获写：

```verilog
csr[5] <= pc + 4;   // mepc = 被中断指令的 PC + 4
```

**问题**：对**顺序指令**，下一 PC 确实是 `pc+4`；但对 **taken 分支 / JAL / JALR**，
真正的下一 PC 是**跳转目标**（`exe_next` 已算好的 `perips_nextpc`）！

中断流程：某条 taken 跳转正在退休 → 中断捕获 `mepc=pc+4`（fall-through 地址）→
PC 重定向到 mtvec（跳转目标被丢弃）→ trap handler 处理完 → `mret` 回到 `pc+4` →
**这条跳转被静默撤销**，执行流掉进本不该执行的代码。

**为什么表现为"help→banner"**：idle 任务死循环 `for(;;) task_yield();`，
中断很容易落在 idle 的 `j` 或各函数循环的**回跳分支**上——一旦该跳转被撤销，
idle 就"滑"进 `.text` 里相邻的函数体（如 shell 初始化/渲染代码），
重打之前的输出（banner）或破坏数据结构 → 卡死。

**为什么"一开始都没发生"**：最初的版本（组合 `intrpt`、`mepc=pc`）是
"被中断指令重执行一遍"——分支会重新执行，**控制流反而是对的**
（副作用双执行是另一个 bug）。改成"保存 pc+4"修副作用时，
意外把分支控制流弄坏了；而这个 bug 一直被第 3 轮的 MIE 卡死掩盖，
直到 MIE 修好、中断真正跑起来才暴露。

**修改 3（最终修复）**：中断保存**真实下一 PC**，用 EXE 阶段已经算好的
`perips_nextpc` 而不是 `pc+4`：

```verilog
// regfile_csr.v 增加 nextpc 输入
input [31:0] nextpc;
...
// 中断捕获
csr[5] <= nextpc;   // mepc = 被中断指令的真实下一 PC
```

`core_ctl.v` 把 `perips_nextpc` 接给 `regfile_csr`：

```verilog
u_regfile_csr(..., .nextpc(perips_nextpc), ...);
```

> `perips_nextpc` 是 `exe_next.v` 算好的"这条指令真正的下一 PC"：
> 顺序=pc+4、分支=目标、JAL=跳转目标、JALR={rs1+imm 清低位}。
> 中断时保存它，`mret` 就能精确回到下一条该执行的指令。
> **异常（ecall/ebreak）仍保存 `pc`**（软件自己 +4 跳过异常指令）。

**结果**：上板，`help` 输出 help、`banner` 输出 banner、输入输出完全匹配；
长输出不再卡死；LED 持续闪烁；`timer`/`task`/`game` 全部正常。
**最终跑通。**

---

## 复盘：三个 bug 的相互关系

| 轮次 | bug | 为什么当时看不到 |
|------|-----|------------------|
| 组合 `intrpt` 幻影 trap | CSR 退休与中断同拍，mepc/mcause 陈旧 | 被下面两个 bug 的"卡死"掩盖 |
| 异常写入非幂等 → MPIE=0 → MIE=0 | 中断彻底不触发，系统睡死 | 修复①后才暴露 |
| 中断保存 pc+4 → 分支撤销 | 控制流错乱（help→banner） | 修复②（中断能跑）后才暴露 |

> 每个 bug 修复后都会暴露下一层，直到最深层的根因。
> **这正说明：每次只改一处、每次改完必须重新验证**，才能把嵌套的 bug 逐层剥开。

## 教训总结

1. **"输入返回了错误的输出" ≠ 软件命令表错误**：当匹配逻辑已被反汇编证实正确时，
   一定是**执行流错乱**（PC 跳错）。
2. **中断的返回地址必须是"真实下一 PC"**：顺序指令才是 pc+4，
   分支/跳转必须保存跳转目标——这是 RISC-V 精确异常的核心要求。
3. **任何"退休拍"的副作用必须只执行一次**：读-改-写型更新（如 `MPIE←MIE; MIE←0`）
   连续执行两次结果不同，是流水线"多打一拍"最容易踩的坑。
4. **用 LED 状态当诊断探针**：GPIO 复位即全亮（低电平点亮），
   `gpio_init` 写 0x0F 熄灭；"只亮一个且不闪" = led 任务只 toggle 过一次就睡死
   = tick 中断失效。这在多轮排查里反复提供关键线索。