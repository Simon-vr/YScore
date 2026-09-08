---
permalink: /learn/01-hardware-basics/02-i-instructions/
lang: en
---
# 02. I Instructions

## 1. Encoding Definition

I-type arithmetic opcode = `7'b0010011`, immediate `imm = ins[31:20]` (12 bits, needs sign extension).
funct3 distinguishes ADDI/ANDI/ORI/XORI/SLLI/SRAI/SLTI/SLTIU (`src/rvdef.vh:45-57`).

Special point: **SLLI and SRAI share funct3=`3'b101`**, distinguished by funct7 (`FUNC7_SRLI=0000000` / `FUNC7_SRAI=0100000`).

## 2. Datapath

Compared with R instructions, the only difference is the source of the ALU's second operand: the immediate rather than rs2.

### 2.1 Immediate Extension

`src/core_id.v:28-35` extends according to `opt_ie`:

```verilog
OPT_IE_IU:     eimm = {{20{1'b0}}, imm};      // unsigned
OPT_IE_IS:     eimm = {{20{imm[11]}}, imm};   // sign extension
OPT_IE_OFFSET: eimm = {{20{offset[11]}}, offset}; // S/B type
```

I-type arithmetic uses `OPT_IE_IS` (sign extension). The shift amount `shamt` of SLLI/SRAI takes `data2[4:0]`
(`data2[4:0]` at `src/exe_alu.v:19`).

### 2.2 Control Path

`src/ctl_ifid.v:40-75`:

```verilog
OP_ITYPE: begin
    case (funct3)
        FUNC3_ADDI: begin
            opt_ie = OPT_IE_IS;
            opt_alusrc2 = OPT_ALUSRC_IMM;   // ALU second source = immediate
        end
        ...
        FUNC3_SLLI: opt_alusrc2 = OPT_ALUSRC_IMM;   // shift amount used as an immediate
```

The ALU function is given by `src/ctl_exe.v:41-60` (SRAI needs to decide SRL/SRA based on funct7).

`src/ctl_wb.v:27-28`: I instructions have `reg_write = 1`.

## 3. Writeback and Next PC

Same as R instructions: `opt_wb = OPT_WB_ALU`, `next_func = NEXT_SEQ`.
Note that the defaults in `src/ctl_exe.v:22-23` are exactly `ALU_ADD` / `NEXT_SEQ`,
so many instruction types only need to change a few fields.

## 4. Test: ins/RI.s (First Half)

The first 9 instructions of RI.s are I instructions:

```asm
addi x1,x0,10
slti x3,x2,20          # EXPECT: x3 = 1 (signed comparison)
sltiu x4,x2,20         # EXPECT: x4 = 1 (unsigned)
xori x6,x5,0x0f        # EXPECT: 0x5a
srai x14,x13,3         # li x13,-32 → EXPECT: -4 (arithmetic shift right preserves sign)
```

SRAI is especially worth looking at: `li x13,-32; srai x14,x13,3` should yield `-4`,
verifying whether `$signed(data1) >>> data2[4:0]` at `src/exe_alu.v:26` preserves the sign bit.

## 5. Common Pitfalls

- **SLLI mistaken for SRAI**: `src/ctl_exe.v:48-55` must use funct7 to distinguish `SRLI`/`SRAI`,
  otherwise a logical shift right will be treated as an arithmetic shift right.
- **Missing immediate sign extension**: ADDI/ORI/ANDI etc. must use `OPT_IE_IS`,
  otherwise a negative immediate (e.g. `addi x1,x0,-1`) becomes a large positive like 0x00000FFF.
- **SLTIU uses unsigned comparison**: `src/exe_alu.v:22` is `data1 < data2` (unsigned),
  so SLTIU and SLTI must be distinguished (`ALU_SLTU` vs `ALU_SLT`).
