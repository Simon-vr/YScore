---
permalink: /zh/learn/01-hardware-basics/02-i-instructions/
---
# 02. I 指令

## 1. 编码定义

I 型算术 opcode = `7'b0010011`，立即数 `imm = ins[31:20]`（12 位，需符号扩展）。
funct3 区分 ADDI/ANDI/ORI/XORI/SLLI/SRAI/SLTI/SLTIU（`src/rvdef.vh:45-57`）。

特殊点：**SLLI 与 SRAI 共用 funct3=`3'b101`**，靠 funct7 区分（`FUNC7_SRLI=0000000` / `FUNC7_SRAI=0100000`）。

## 2. 数据通路

与 R 指令相比，差别只在 ALU 第二操作数来源：立即数而非 rs2。

### 2.1 立即数扩展

`src/core_id.v:28-35` 依据 `opt_ie` 扩展：

```verilog
OPT_IE_IU:     eimm = {{20{1'b0}}, imm};      // 无符号
OPT_IE_IS:     eimm = {{20{imm[11]}}, imm};   // 符号扩展
OPT_IE_OFFSET: eimm = {{20{offset[11]}}, offset}; // S/B 型
```

I 型算术用 `OPT_IE_IS`（符号扩展）。SLLI/SRAI 的移位量 `shamt` 取 `data2[4:0]`
（`src/exe_alu.v:19` 的 `data2[4:0]`）。

### 2.2 控制通路

`src/ctl_ifid.v:40-75`：

```verilog
OP_ITYPE: begin
    case (funct3)
        FUNC3_ADDI: begin
            opt_ie = OPT_IE_IS;
            opt_alusrc2 = OPT_ALUSRC_IMM;   // ALU 第二源 = 立即数
        end
        ...
        FUNC3_SLLI: opt_alusrc2 = OPT_ALUSRC_IMM;   // 移位量当立即数用
```

ALU 功能由 `src/ctl_exe.v:41-60` 给出（SRAI 需按 funct7 判断 SRL/SRA）。

`src/ctl_wb.v:27-28`：I 指令 `reg_write = 1`。

## 3. 写回与下一 PC

与 R 指令相同：`opt_wb = OPT_WB_ALU`，`next_func = NEXT_SEQ`。
注意 `src/ctl_exe.v:22-23` 的默认值正是 `ALU_ADD` / `NEXT_SEQ`，
所以很多指令类型只需要改个别字段。

## 4. 测试：ins/RI.s（上半部分）

RI.s 前 9 条就是 I 指令：

```asm
addi x1,x0,10
slti x3,x2,20          # EXPECT: x3 = 1（有符号比较）
sltiu x4,x2,20         # EXPECT: x4 = 1（无符号）
xori x6,x5,0x0f        # EXPECT: 0x5a
srai x14,x13,3         # li x13,-32 → EXPECT: -4（算术右移保留符号）
```

SRAI 特别值得看：`li x13,-32; srai x14,x13,3` 结果应为 `-4`，
验证 `src/exe_alu.v:26` 的 `$signed(data1) >>> data2[4:0]` 是否保留符号位。

## 5. 易错点

- **SLLI 误判为 SRAI**：`src/ctl_exe.v:48-55` 必须用 funct7 区分 `SRLI`/`SRAI`，
  否则逻辑右移会被当成算术右移。
- **立即数符号扩展遗漏**：ADDI/ORI/ANDI 等必须 `OPT_IE_IS`，
  否则负数立即数（如 `addi x1,x0,-1`）会变成 0x00000FFF 之类的大正数。
- **SLTIU 用无符号比较**：`src/exe_alu.v:22` 是 `data1 < data2`（无符号），
  SLTIU 与 SLTI 必须区分（`ALU_SLTU` vs `ALU_SLT`）。