# 05. 其他指令：JAL / JALR / LUI / AUIPC

## 1. LUI / AUIPC

### 1.1 编码

- LUI opcode = `7'b0110111`：`rd = imm[31:12] << 12`（U 型立即数）。
- AUIPC opcode = `7'b0010111`：`rd = pc + (imm[31:12] << 12)`。

U 型立即数 `upper_imm = ins[31:12]`，在 `src/ifid_immex.v:27` 拼低位 12 个 0：
`eupper_imm = {upper_imm, 12'b0}`。

### 1.2 数据通路

`src/ctl_ifid.v:95-102`：LUI/AUIPC `opt_alusrc2 = OPT_ALUSRC_IMM`（ALU 第二源 = 立即数）。

`src/ctl_exe.v:87-92`：`alu_func = ALU_ADD`。

`src/ctl_wb.v:55-62` 选择回写源：

```verilog
OP_LUI:   reg_write=1; opt_wb = OPT_WB_LUI;    // wbreg = upperimm
OP_AUIPC: reg_write=1; opt_wb = OPT_WB_AUIPC;  // wbreg = upperimm + pc
```

对应 `src/core_wb.v:38-39`：

```verilog
OPT_WB_LUI:   wbreg = upperimm;
OPT_WB_AUIPC: wbreg = upperimm + pc;
```

`perips_nextpc = NEXT_SEQ`（LUI/AUIPC 不改 PC）。

## 2. JAL

### 2.1 编码

opcode = `7'b1101111`，J 型立即数布局特殊：

```verilog
// src/core_id.v:24
wire [19:0] jump_offset = {ins[31], ins[19:12], ins[20], ins[30:21]};
// src/ifid_immex.v:25
assign ejump_offset = {{11{jump_offset[19]}}, jump_offset, 1'b0};  // 左移一位
```

### 2.2 数据通路

- `src/ctl_exe.v:79-82`：`alu_func=ADD`，`next_func = NEXT_JAL`。
- `src/exe_next.v:54`：`NEXT_JAL: next_pc = cur_pc + jump_offset`。
- 写回：`src/ctl_wb.v:47-50` 给 `opt_wb = OPT_WB_PC4`，即 `wbreg = pc + 4`
  （`src/core_wb.v:37`）——把返回地址存进 `rd`。

## 3. JALR

### 3.1 编码

opcode = `7'b1100111`，`rd = rs1 + imm`，且**最低位清零**（RV32 规范）。

### 3.2 数据通路

- `src/ctl_exe.v:83-86`：`alu_func=ADD`，`next_func = NEXT_JALR`。
- `src/exe_next.v:55`：`NEXT_JALR: next_pc = {alu_res[31:1], 1'b0}`——`alu_res` 即 `rs1+imm`。
- 写回同样 `OPT_WB_PC4`（`src/ctl_wb.v:51-54`），返回地址 = `pc+4`。

## 4. 下一 PC 汇总（src/exe_next.v）

```
顺序指令 → NEXT_SEQ → cur_pc + 4
分支     → NEXT_Bxx → 条件成立 ? cur_pc + 偏移 : cur_pc + 4
JAL      → NEXT_JAL → cur_pc + jump_offset
JALR     → NEXT_JALR → {alu_res[31:1], 1'b0}
```

这个 `next_pc` 就是中断/异常时保存的 **`perips_nextpc`**（详见 07/08 章，以及
`03-debug-pitfalls/03` 中"分支上打中断必须保存 nextpc 而非 pc+4"的关键教训）。

## 5. 测试：ins/others.s

`ins/others.s` 覆盖 LUI/AUIPC/JAL/JALR/普通指令穿插：

```asm
lui x5,0x12345          # x5 = 0x12345000
li x6,0x12345000
bne x5,x6,fail

auipc x7,0              # x7 = 本条指令地址
addi x8,x7,0
bne x7,x8,fail

jal x5,jal_target       # x5 = 返回地址(非零)
beq x5,x0,fail
...
la x6,jalr_return
jalr x0,x6,0            # 跳转并清最低位
jal x0,fail
jalr_return:
...
pass: li x31,1; loop: jal x0,loop
fail: li x31,0; fail_loop: jal x0,fail_loop
```

看 x31：1 = 全过，0 = 失败。

## 6. 易错点

- **JALR 最低位清零**：`{alu_res[31:1], 1'b0}` 若漏掉，跳转到奇数地址会死循环或取错指令。
- **J 型立即数拼接顺序**：`{ins[31], ins[19:12], ins[20], ins[30:21]}` 顺序不能错。
- **LUI 立即数拼位**：U 型立即数是 `ins[31:12]` 左移 12 位，与 AUIPC 的 `+pc` 区分。