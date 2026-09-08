---
permalink: /learn/01-hardware-basics/04-branch-instructions/
lang: en
---
# 04. Branch Instructions

## 1. Encoding Definition

B-type opcode = `7'b1100011`, funct3 distinguishes BEQ/BNE/BLT/BGE/BLTU/BGEU (`src/rvdef.vh:82-87`).
The branch immediate layout is special:

```verilog
// src/core_id.v:23
wire [11:0] branch_offset = {ins[31], ins[7], ins[30:25], ins[11:8]};
```

In `src/ifid_immex.v:24` it is extended to 32 bits and shifted left by one (×2):

```verilog
assign ebranch_offset = {{19{branch_offset[11]}}, branch_offset, 1'b0};
```

## 2. Data Path

### 2.1 ALU: Subtraction Comparison

`src/ctl_exe.v:67-78` uniformly sets `alu_func = ALU_SUB` for branch instructions, using rs1 - rs2 to produce comparison flags:

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

### 2.2 Flags (src/exe_alu.v:34-39)

`exe_alu` outputs 4 flags for `exe_next` to evaluate:

```verilog
zero     = (res == 32'b0);          // rs1==rs2 (for SUB, the difference is 0)
sign     = res[31];                 // sign bit of the result
carry    = (func==SUB) ? ~res[32] : res[32]; // used for unsigned comparison (borrow inverted)
overflow = low_res[31] ^ res[32];   // signed overflow
```

### 2.3 Next PC Evaluation (src/exe_next.v)

`exe_next` uses `next_func` + the flags to decide the next PC:

```verilog
NEXT_BEQ:  if (zero==1)      next_pc = cur_pc + branch_offset;
           else              next_pc = cur_pc + 4;
NEXT_BLT:  if (sign^overflow) next_pc = cur_pc + branch_offset;   // signed less-than
           else              next_pc = cur_pc + 4;
NEXT_BLTU: if (carry==0)      next_pc = cur_pc + branch_offset;   // unsigned less-than
           else              next_pc = cur_pc + 4;
```

Signed comparisons `BLT/BGE` use `sign ^ overflow` (i.e. the true result is negative),
unsigned comparisons `BLTU/BGEU` use `carry` (borrow).

## 3. Control Path Highlights

- Branches **do not write registers** (`src/ctl_wb.v` has no OP_BRANCH case, `reg_write=0`).
- Branches **do not access memory** (`ctl_perips.v` has no OP_BRANCH case, `peripsen=0`), PERIPS passes through.
- The final selection of the next PC is in `src/wb_mux_pc.v`:

```verilog
if (excp_token)   nextpc = mtvec;
else if (is_mret) nextpc = mepc;
else if (intrpt)  nextpc = mtvec;
else              nextpc = perips_nextpc;   // branch target / sequential address
```

Normal branches take the last item: `perips_nextpc` is the target computed by `exe_next` or `cur_pc+4`.
The branch target is latched into `perips_nextpc` during the EXE beat, and written into `wb_pc` on the WB sample beat.

## 4. Test: ins/branch.s

`ins/branch.s` tests all 6 branch types with "jump correctly → continue, jump incorrectly → fail":

```asm
li x31,0
beq x5,x6,beq_ok        # x5==x6 → should jump
beq x0,x0,fail          # if the previous jump didn't happen, x0==x0 unconditionally jumps to fail
...
bgeu x5,x6,bgeu_ok      # 0xffffffff >= 1 is true unsigned
pass:
li x31,1
pass_loop: beq x31,x31,pass_loop    # infinite loop locks x31=1
fail:
li x31,0
fail_loop: beq x31,x31,fail_loop
```

Look at the final x31: `1` = all passed, `0` = failed.

## 5. Pitfalls

- **Signed/unsigned confusion**: BLT uses `sign^overflow`, BLTU uses `carry`; the two cannot be interchanged.
- **Branch offset ×2**: `ebranch_offset` is already shifted left by one; forgetting this will misalign at `cur_pc + offset`.
- **BGEU special case**: `bgeu x5,x6` with x5=0xffffffff, x6=1 should hold — unsigned comparison must correctly handle all-ones numbers.
