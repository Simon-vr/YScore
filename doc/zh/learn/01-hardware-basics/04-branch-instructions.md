---
permalink: /zh/learn/01-hardware-basics/04-branch-instructions/
---
# 04. 分支指令

## 1. 编码定义

B 型 opcode = `7'b1100011`，funct3 区分 BEQ/BNE/BLT/BGE/BLTU/BGEU（`src/rvdef.vh:82-87`）。
分支立即数布局特殊：

```verilog
// src/core_id.v:23
wire [11:0] branch_offset = {ins[31], ins[7], ins[30:25], ins[11:8]};
```

在 `src/ifid_immex.v:24` 扩展成 32 位并左移一位（×2）：

```verilog
assign ebranch_offset = {{19{branch_offset[11]}}, branch_offset, 1'b0};
```

## 2. 数据通路

### 2.1 ALU：做减法比较

`src/ctl_exe.v:67-78` 分支指令统一 `alu_func = ALU_SUB`，用 rs1 - rs2 产生比较标志：

```verilog
OP_BRANCH: begin
    alu_func = ALU_SUB;
    case (funct3)
        FUNC3_BEQ:  next_func = NEXT_BEQ;
        FUNC3_BNE:  next_func = NEXT_BNE;
        FUNC3_BLT:  next_func = NEXT_BLT;
        FUNC3_BGE:  next_func = NEXT_BGE;
        FUNC3_BLTU: next_func = NEXT_BLTU;
        FUNC3_BGEU: next_func = NEXT_BGEU;
    endcase
end
```

### 2.2 标志位（src/exe_alu.v:34-39）

`exe_alu` 输出 4 个标志供 `exe_next` 判定：

```verilog
zero     = (res == 32'b0);          // rs1==rs2（对 SUB 即差为 0）
sign     = res[31];                 // 结果的符号位
carry    = (func==SUB) ? ~res[32] : res[32]; // 无符号比较用（借位取反）
overflow = low_res[31] ^ res[32];   // 有符号溢出
```

### 2.3 下一 PC 判定（src/exe_next.v）

`exe_next` 用 `next_func` + 标志位决定下一 PC：

```verilog
NEXT_BEQ:  if (zero==1)      next_pc = cur_pc + branch_offset;
           else              next_pc = cur_pc + 4;
NEXT_BLT:  if (sign^overflow) next_pc = cur_pc + branch_offset;   // 有符号小于
           else              next_pc = cur_pc + 4;
NEXT_BLTU: if (carry==0)      next_pc = cur_pc + branch_offset;   // 无符号小于
           else              next_pc = cur_pc + 4;
```

有符号比较 `BLT/BGE` 用 `sign ^ overflow`（即真结果为负），
无符号比较 `BLTU/BGEU` 用 `carry`（借位）。

## 3. 控制通路要点

- 分支**不写寄存器**（`src/ctl_wb.v` 无 OP_BRANCH case，`reg_write=0`）。
- 分支**不访存**（`ctl_perips.v` 无 OP_BRANCH case，`peripsen=0`），PERIPS 透传。
- 下一 PC 的最终选择在 `src/wb_mux_pc.v`：

```verilog
if (excp_token)   nextpc = mtvec;
else if (is_mret) nextpc = mepc;
else if (intrpt)  nextpc = mtvec;
else              nextpc = perips_nextpc;   // 分支目标 / 顺序地址
```

正常分支走最后一项：`perips_nextpc` 就是 `exe_next` 算出的目标或 `cur_pc+4`。
分支目标在 EXE 拍锁存进 `perips_nextpc`，WB 采样拍写入 `wb_pc`。

## 4. 测试：ins/branch.s

`ins/branch.s` 对 6 种分支都做了"跳对→继续，跳错→fail"的测试：

```asm
li x31,0
beq x5,x6,beq_ok        # x5==x6 → 应跳转
beq x0,x0,fail          # 若上一跳没发生，x0==x0 无条件跳到 fail
...
bgeu x5,x6,bgeu_ok      # 0xffffffff >= 1 无符号成立
pass:
li x31,1
pass_loop: beq x31,x31,pass_loop    # 死循环锁死 x31=1
fail:
li x31,0
fail_loop: beq x31,x31,fail_loop
```

看最终 x31：`1` = 全过，`0` = 失败。

## 5. 易错点

- **有符号/无符号混淆**：BLT 用 `sign^overflow`，BLTU 用 `carry`，两者不能互换。
- **分支偏移 ×2**：`ebranch_offset` 已左移一位，若忘记会在 `cur_pc + offset` 处错位。
- **BGEU 特例**：`bgeu x5,x6` 在 x5=0xffffffff, x6=1 时应成立——无符号比较要正确处理全 1 数。