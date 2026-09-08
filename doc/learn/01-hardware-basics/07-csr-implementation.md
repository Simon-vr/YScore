# 07. CSR 硬件实现

## 1. CSR 寄存器堆：regfile_csr.v

`src/regfile_csr.v` 是 CSR 硬件核心，实现了 9 个机器模式 CSR：

| 索引 | CSR | 地址 | 说明 |
|------|-----|------|------|
| 0 | mstatus | 0x300 | 机器状态（MIE/MPIE/MPP） |
| 1 | misa | 0x301 | 机器 ISA |
| 2 | mie | 0x304 | 中断使能（bit7=MTIE） |
| 3 | mtvec | 0x305 | 陷阱向量基址 |
| 4 | mscratch | 0x340 | 临时寄存器 |
| 5 | mepc | 0x341 | 异常/中断返回 PC |
| 6 | mcause | 0x342 | 陷阱原因 |
| 7 | mtval | 0x343 | 陷阱值 |
| 8 | mip | 0x344 | 中断挂起 |

地址宏在 `src/rvdef.vh:232-245`。读写端口：

```verilog
// src/core_ctl.v:154-170
regfile_csr u_regfile_csr(
    .wen   (perips_token ? wb_csrwen_w : 3'b000),
    .raddr (ifid_csraddr_w),      // 读 CSR（ID 阶段）
    .waddr (perips_csraddr),
    .idata (wb_csr_w),
    .odata (ifid_csrdata_w),
    .pc    (perips_pc),
    .nextpc (perips_nextpc),
    ...
    .mtip  (perips_mtip_w),
    .perips_token (perips_token),
    .intrpt (csr_intrpt_w)
);
```

`wen` 的 3 位编码（`src/core_wb.v:17-27` 组合逻辑产生）：

```
excp_token ? 010   （异常：ecall/ebreak 写 mepc/mcause/mtval/MPIE/MIE）
is_mret    ? 011   （mret：MIE ← MPIE）
ctl_csrw   ? 001   （CSR 指令写）
默认       000
```

## 2. CSR 指令译码

`src/ctl_ifid.v:103-149` 处理 `OP_CSR`：

- `opt_alusrc2 = OPT_ALUSRC_CSR`：ALU 第二源 = CSR 读值（`src/ifid_mux_alusrc2.v`）。
- `CSRRSI/CSRRCI/CSRRWI` 用 `opt_alusrc1 = OPT_ALUSRC1_RS1`（把 rs1 当立即数 uimm）。
- funct3 对应 ALU 功能（`src/ctl_exe.v:93-103`）：

```verilog
CSRRW : ALU_SRC1   // 直接写
CSRRS : ALU_OR     // 置位：old | rs1
CSRRC : ALU_ANDN   // 清零：~rs1 & old（ALU_ANDN = ~data1 & data2）
```

`src/ctl_wb.v:63-67`：CSR 指令 `reg_write=1, csr_write=1, opt_wb=OPT_WB_CSR`
（写回原 CSR 值，见 `src/core_wb.v:40` `OPT_WB_CSR: wbreg=csrdata`）。

## 3. CSR 读写时序

- **读**：ID 阶段 `ifid_csraddr_w` 组合读出 `odata`，锁存进 `ifid_csr` → `exe_csr` → `perips_csr`。
- **写**：WB 退休拍 `perips_token && ctl_csrw` 时，`wb_csr_w`（ALU 结果）写入目标 CSR。

## 4. 中断/异常对 CSR 的更新（重要）

`regfile_csr.v` 的 `always` 块里，写优先级是：

```
rst > wen==001(CSR指令) > wen==010(异常) > wen==011(mret) > (perips_token && MIE) 中断捕获 > 默认
```

- **异常（010）**：`mepc <= pc`（ecall 自身地址，软件 +4 跳过）、`mcause <= excp_cause`、
  `mtval <= excp_mtval`、`MPIE <= MIE`、`MIE <= 0`。
- **中断捕获**：条件 `perips_token && MIE && MTIE && mtip`，
  `mepc <= nextpc`（**被中断指令的真实下一 PC**，见下）、`mcause <= 0x80000007`、
  `MPIE <= MIE`、`MIE <= 0`、`intrpt <= 1`。
- **mret（011）**：`MIE <= MPIE`。

> **关键设计**：中断捕获保存的是 `nextpc`（即 `perips_nextpc`，被中断指令的**真实**下一 PC），
> 而不是 `pc+4`。对于顺序指令两者相同，但对于**分支/跳转**（beq/bne/jal/jalr），
> 真正的下一指令在目标地址，`pc+4` 是错的。这条教训的完整排错过程见
> `03-debug-pitfalls/03`——正是本项目最后一次硬软联调的核心 bug。

## 5. intrpt 信号：寄存器化 vs 组合逻辑

早期版本 `intrpt` 是组合逻辑 `assign intrpt = perips_token && MIE && MTIE && mtip`
（与 CSR 写优先级无关），导致"CSR 指令退休与中断同拍"时 PC 被劫持进 trap 但
mepc/mcause 是陈旧值（幻影 trap）。现版本把 `intrpt` 做成**寄存器输出**
（`src/regfile_csr.v:23`），只在中断分支里 `intrpt <= 1`，其余分支清 0。
配合 WB 的"退休拍 + 采样拍"（`src/core_ctl.v:444-451`），
intrpt 在退休拍置位、采样拍被 `wb_mux_pc` 采样，完成重定向。
详见 `03-debug-pitfalls/03`。

## 6. 测试：ins/zicsr.s

`ins/zicsr.s` 用 mscratch（0x340）完整验证 6 种 CSR 指令：

```asm
csrrwi x0,0x340,0        # mscratch = 0
li x5,0x12345678
csrrw x6,0x340,x5        # 读旧值(0)到 x6，写入新值
bne x6,x0,fail
csrr x7,0x340            # x7 = 0x12345678
...
csrrs x6,0x340,x5        # 置位（OR）
csrrc x6,0x340,x5        # 清零（ANDN）
csrrwi/csr rsi/csr rci  # 立即数版本
pass: li x31,1; ...
fail: li x31,0; ...
```

最终看 x31。

## 7. 易错点

- **CSR 写值来源**：写的是 `wb_csr_w`（ALU 结果），CSRRS 的"置位"必须用 `ALU_OR`，
  CSRRC 的"清零"必须用 `ALU_ANDN`（`~data1 & data2`），且 operands 顺序不能反。
- **写回旧值**：CSR 指令写回的是**读到的旧 CSR 值**（`OPT_WB_CSR: wbreg=csrdata`），
  不是新值。
- **中断保存 nextpc**：见第 4 节，这是本项目踩过的坑。