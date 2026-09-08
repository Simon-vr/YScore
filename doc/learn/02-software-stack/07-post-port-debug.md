# 07. 移植后 Debug 指南

本文是"软件已在 QEMU 上验证通过、移植到 FPGA 后出问题"的标准排查流程。
对应本项目实际踩过的坑（详见 03-debug-pitfalls）。

## 1. 核心原则

**二分法**：QEMU 行为正确 + FPGA 行为错误 → 问题在硬件；
两者都错 → 问题在软件。这是移植后调试的第一判断。

## 2. 标准排查流程

```
上板发现有问题
   │
   ├─ ① 判定层面：QEMU 跑同样代码是否也错？
   │      ├─ 也错 → 软件 bug，回 QEMU 修（快）
   │      └─ 只有 FPGA 错 → 硬件 bug，继续
   │
   ├─ ② 收集现场：banner 打了吗？LED 亮几个/闪不闪？输入有回显吗？
   │      （LED 状态是"CPU 是否跑过 gpio_init"的天然探针）
   │
   ├─ ③ 锁定指令：跑 ModelSim 仿真（sim.do），定位"跑崩的 PC / 最后一条正常指令", 看反汇编（map/dasm），
   │   
   │
   ├─ ④ 看硬件数据/控制流：从 IF 到 WB 逐级查 ctl 控制信号与 data 值
   │
   └─ ⑤ 改一处 → 重新仿真/上板回归 → 循环
```

## 3. 常见症状 → 嫌疑对照

| 症状                   | 优先嫌疑                                                        |
| ---------------------- | --------------------------------------------------------------- |
| 完全不打印 / 无 banner | 启动早期卡住：.bss/栈/mtvec/取指；或 GPIO 复位即亮              |
| banner 有，输入无回显  | uart_rx 任务睡死（tick 中断没来）/ 输入所有权错                 |
| 输入 help 返回 banner  | **PC 流错乱**（中断返回地址错）→ 见 03-debug-pitfalls/03 |
| 输出后整机卡死         | 中断破坏调度 / trap 上下文碰阻塞外设                            |
| LED 亮一个固定不闪     | led 任务睡死（tick 中断没来）                                   |
| 某些指令结果错误       | 查对应 ctl/alu/exe_next（硬件译码/运算）                        |

## 4. 关键排查工具

### 4.1 反汇编（map/dasm）

`ninja dasm` 生成 `MiniRTOS_shturl.txt`。定位到出错 PC 后对照源码，
判断是取错指令（PC 错）还是运算错。

### 4.2 ModelSim 仿真

`simulation/modelsim/sim.do` 一键跑。`tb/mycpu_sim.v` 会打印：

- 每周期"寄存器/CSR 变化 + 所在 PC + 指令名"。
- 支持 `+STOP_PC=0x...` 在指定地址停住（`mycpu_sim.v:357`）。

看波形关键信号：`if_token/ifid_token/exe_token/perips_token/wb_token`（token 推进）、
`perips_data_w`、`wb_pc_w`、`csr_intrpt_w`、AXI 握手 `axil_*valid/ready`。

### 4.3 QEMU 对照

同一份 `portmacro.h`/`timer.c` 换成 QEMU 参数，`ninja run` 在 QEMU 上跑，
确认软件行为基准。
