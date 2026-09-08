# 08. 内部异常通路（ecall / ebreak）

## 1. 异常识别

`src/ctl_ifid.v:103-125` 处理 `OP_CSR` 且 `funct3 == FUNC3_EXCP`（000）的情况，
用 `imm`（即 funct12）区分：

```verilog
F12_ECALL:  is_excp = 1'b1; excp_cause = EXCP_CAUSE_ECALL;  // 11
F12_EBREAK: is_excp = 1'b1; excp_cause = EXCP_CAUSE_EBREAK; // 3
F12_MRET:   is_mret = 1'b1; is_excp = 1'b0;
```

宏定义在 `src/rvdef.vh:110-128`：

```verilog
`define F12_ECALL   12'h000
`define F12_EBREAK  12'h001
`define F12_MRET    12'h302
`define EXCP_CAUSE_EBREAK  32'd3
`define EXCP_CAUSE_ECALL   32'd11
```

## 2. 异常通道（core_ctl.v:386-389）

ID 阶段把异常信息锁存进 `excp_token / excp_ismret / excp_cause`：

```verilog
if_token<=0; ifid_token<=1;
excp_token  <= ifid_ecall_w;   // ecall/ebreak 置 1
excp_ismret <= ifid_mret_w;
excp_cause  <= ifid_mcause_w;
excp_mtval  <= 32'd0;
```

`excp_token` 一直保持到下一个指令的 ID 拍，期间驱动：
- `core_wb` 的 `csr_wen = 010`（异常写 CSR）。
- `wb_mux_pc` 的重定向：`excp_token → nextpc = mtvec`。

## 3. 异常时的 CSR 写入（regfile_csr.v:63-71）

```verilog
else if (perips_token==1 && wen == 3'b010) begin
    intrpt <= 1'b0;
    csr[5] <= pc;            // mepc = ecall/ebreak 自身地址
    csr[6] <= excp_cause;    // mcause = 11 / 3
    csr[7] <= excp_mtval;    // mtval = 0
    csr[0][7] <= csr[0][3];  // MPIE = MIE
    csr[0][3] <= 1'b0;       // MIE = 0
end
```

注意：**mepc 保存 `pc`（异常指令自身地址）**，而不是 nextpc——
ecall/ebreak 的"下一指令"语义由软件负责：trap 处理里 `mepc+4` 跳过异常指令。

## 4. 重定向与返回

- **进入**：`wb_mux_pc` 在 `excp_token` 有效时 `nextpc = mtvec`，WB 采样拍写入 `wb_pc`。
- **返回**：软件在 trap handler 里 `csrw mepc` 改返回地址后 `mret`，
  硬件 `wen==011` 使 `MIE <= MPIE`，`wb_mux_pc` 里 `is_mret → nextpc = mepc`。

## 5. 中断与异常的差别（重要）

| | ecall/ebreak（异常） | 定时器中断 |
|---|---|---|
| mcause | 11 / 3 | 0x80000007（最高位=1） |
| mepc | `pc`（异常指令地址，软件 +4） | `nextpc`（被中断指令的真实下一 PC） |
| 软件动作 | trap 里 `mepc+4` | 不需要动 mepc |
| 触发源 | 指令本身（同步） | mtip 外部（异步） |

`rtos/port/portASM.S:20` 用 `mcause` 的符号位区分：
`bge a0, x0, synchronous_exception`（mcause[31]==0 是异常，==1 是中断）。

## 6. 测试：ins/except.s

`ins/except.s` 自带 trap handler：

```asm
la t0,trap_handler
csrw mtvec,t0
ecall
after_ecall: ...
ebreak
after_ebreak: ...

trap_handler:
    csrr t0,mcause
    li t1,11
    beq t0,t1,handle_ecall     # 区分两种异常
    li t1,3
    beq t0,t1,handle_ebreak
    j fail
handle_ecall:
    addi s0,s0,1
    csrr t2,mepc
    addi t2,t2,4
    csrw mepc,t2              # mepc+4 跳过 ecall
    mret
```

验证：`s0` 累加 1、2，最终 x31=1 表示 ecall 和 ebreak 都正确触发并返回。

## 7. 易错点

- **mepc 语义**：异常保存 `pc`（软件 +4），中断保存 `nextpc`——两者不能混淆，
  混淆的后果就是"返回地址错位"（见 03-debug-pitfalls/03）。
- **MBIT**：中断的 mcause 最高位必须是 1（`0x80000007`），软件靠它区分路径。
- **trap handler 里不能再开中断**：硬件已把 MIE 清 0，软件在返回前保持关中断。