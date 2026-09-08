---
permalink: /learn/01-hardware-basics/05-other-instructions/
lang: en
---
# 05. Other Instructions: JAL / JALR / LUI / AUIPC

## 1. LUI / AUIPC

### 1.1 Encoding

- LUI opcode = `7'b0110111`: `rd = imm[31:12] << 12` (U-type immediate).
- AUIPC opcode = `7'b0010111`: `rd = pc + (imm[31:12] << 12)`.

The U-type immediate `upper_imm = ins[31:12]`, and in `src/ifid_immex.v:27` the low 12 bits are filled with zeros:
`eupper_imm = {upper_imm, 12'b0}`.

### 1.2 Data Path

`src/ctl_ifid.v:95-102`: LUI/AUIPC `opt_alusrc2 = OPT_ALUSRC_IMM` (ALU second source = immediate).

`src/ctl_exe.v:87-92`: `alu_func = ALU_ADD`.

`src/ctl_wb.v:55-62` selects the write-back source:

```verilog
OP_LUI:   reg_write=1; opt_wb = OPT_WB_LUI;    // wbreg = upperimm
OP_AUIPC: reg_write=1; opt_wb = OPT_WB_AUIPC;  // wbreg = upperimm + pc
```

Corresponding to `src/core_wb.v:38-39`:

```verilog
OPT_WB_LUI:   wbreg = upperimm;
OPT_WB_AUIPC: wbreg = upperimm + pc;
```

`perips_nextpc = NEXT_SEQ` (LUI/AUIPC do not change PC).

## 2. JAL

### 2.1 Encoding

opcode = `7'b1101111`, the J-type immediate layout is special:

```verilog
// src/core_id.v:24
wire [19:0] jump_offset = {ins[31], ins[19:12], ins[20], ins[30:21]};
// src/ifid_immex.v:25
assign ejump_offset = {{11{jump_offset[19]}}, jump_offset, 1'b0};  // shift left by one
```

### 2.2 Data Path

- `src/ctl_exe.v:79-82`: `alu_func=ADD`, `next_func = NEXT_JAL`.
- `src/exe_next.v:54`: `NEXT_JAL: next_pc = cur_pc + jump_offset`.
- Write-back: `src/ctl_wb.v:47-50` sets `opt_wb = OPT_WB_PC4`, i.e. `wbreg = pc + 4`
  (`src/core_wb.v:37`) — storing the return address into `rd`.

## 3. JALR

### 3.1 Encoding

opcode = `7'b1100111`, `rd = rs1 + imm`, with the **lowest bit cleared** (RV32 spec).

### 3.2 Data Path

- `src/ctl_exe.v:83-86`: `alu_func=ADD`, `next_func = NEXT_JALR`.
- `src/exe_next.v:55`: `NEXT_JALR: next_pc = {alu_res[31:1], 1'b0}` — `alu_res` is `rs1+imm`.
- Write-back is likewise `OPT_WB_PC4` (`src/ctl_wb.v:51-54`), return address = `pc+4`.

## 4. Next PC Summary (src/exe_next.v)

```
sequential → NEXT_SEQ → cur_pc + 4
branch     → NEXT_Bxx → condition ? cur_pc + offset : cur_pc + 4
JAL        → NEXT_JAL → cur_pc + jump_offset
JALR       → NEXT_JALR → {alu_res[31:1], 1'b0}
```

This `next_pc` is the **`perips_nextpc`** saved during interrupts/exceptions (see Chapters 07/08, as well as
the key lesson in `03-debug-pitfalls/03`: "when an interrupt hits a branch, you must save nextpc, not pc+4").

## 5. Test: ins/others.s

`ins/others.s` covers LUI/AUIPC/JAL/JALR interleaved with ordinary instructions:

```asm
lui x5,0x12345          # x5 = 0x12345000
li x6,0x12345000
bne x5,x6,fail

auipc x7,0              # x7 = address of this instruction
addi x8,x7,0
bne x7,x8,fail

jal x5,jal_target       # x5 = return address (non-zero)
beq x5,x0,fail
...
la x6,jalr_return
jalr x0,x6,0            # jump and clear the lowest bit
jal x0,fail
jalr_return:
...
pass: li x31,1; loop: jal x0,loop
fail: li x31,0; fail_loop: jal x0,fail_loop
```

Look at x31: 1 = all passed, 0 = failed.

## 6. Pitfalls

- **JALR lowest bit clear**: if `{alu_res[31:1], 1'b0}` is omitted, jumping to an odd address will cause an infinite loop or fetch the wrong instruction.
- **J-type immediate concatenation order**: the order of `{ins[31], ins[19:12], ins[20], ins[30:21]}` must not be wrong.
- **LUI immediate concatenation**: the U-type immediate is `ins[31:12]` shifted left by 12 bits; distinguish it from AUIPC's `+pc`.
