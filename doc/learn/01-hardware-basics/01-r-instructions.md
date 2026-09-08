---
permalink: /learn/01-hardware-basics/01-r-instructions/
lang: en
---
# 01. R Instructions (Datapath + Control Path)

## 1. Encoding Definition

R-type instruction opcode = `7'b0110011`. The `funct7` (`ins[31:25]`) and `funct3` (`ins[14:12]`)
combine into a 10-bit function code `func = {funct7, funct3}`. Defined in `src/rvdef.vh:23-37`:

```verilog
`define FUNC_ADD   10'b0000000_000
`define FUNC_SUB   10'b0100000_000
`define FUNC_AND   10'b0000000_111
...
```

## 2. Datapath

### 2.1 Fetch (IF)

`src/core_if.v`: synchronously reads the instruction memory. `ins_mem[0:4607]` has 4608 entries (18KB, M9K),
loaded via `$readmemh` from `rtos\build\imem.mem`. `ins_adr[31:2]` provides the word address.

The IF cycle of `core_ctl` (`src/core_ctl.v:359-363`):

```verilog
else if (wb_token && !if_token) begin
    if_pc <= wb_pc;
    wb_token <= 1'b0;
    if_token <= 1'b1;
end
```

Because M9K is a synchronous read, the PC is latched first and `core_if` outputs the instruction on the next cycle.

### 2.2 Decode (ID)

`src/core_id.v` splits the fields and extends the immediate:

- `rd = ins[11:7]`, `rs1 = ins[19:15]`, `rs2 = ins[24:20]`.
- Register file `src/regfile.v`: `odata1 = regfile[rs1]`, `odata2 = regfile[rs2]` (combinational read).

R instructions involve no immediate, so `opt_ie` uses the default `OPT_IE_IU`.

### 2.3 Compute (EXE)

`src/core_exe.v` instantiates `exe_alu` and `exe_next`. Both sources of an R instruction come from the register file,
and the ALU's second operand selects `opt_alusrc2 = OPT_ALUSRC_REG` (default value in `src/ctl_ifid.v:34`).

The key point of `src/exe_alu.v`: **use a 33-bit `res` to preserve carry/borrow**:

```verilog
ALU_ADD:  res = {1'b0, data1} + {1'b0, data2};
ALU_SUB:  res = {1'b0, data1} - {1'b0, data2};
...
carry   = (func == ALU_SUB) ? (~res[32]) : res[32]; // SUB checks borrow
overflow = low_res[31] ^ res[32];
```

The `next_func` of R instructions is `NEXT_SEQ` (sequential execution, next PC = `cur_pc + 4`, see `src/exe_next.v:17`).

### 2.4 Writeback (WB)

`src/core_wb.v` selects the writeback data by `opt_wb`. R instructions have `opt_wb = OPT_WB_ALU` (default),
and `wbreg = alures`. `src/regfile.v` writes when `perips_token && perips_ctl_regw` (`src/core_ctl.v:147`).

## 3. Control Path

R instructions need **no special handling** in `src/ctl_ifid.v` (the opcode falls into default; all defaults suffice).
The actual ALU function is given by `src/ctl_exe.v:26-39` based on `func`:

```verilog
OP_RTYPE: begin
    case (func)
        FUNC_ADD:  alu_func = ALU_ADD;
        FUNC_SUB:  alu_func = ALU_SUB;
        ...
        FUNC_SLTU: alu_func = ALU_SLTU;
    endcase
end
```

`src/ctl_wb.v:24-25` gives R instructions `reg_write = 1` and `csr_write = 0`.

## 4. Pipeline Advance (token)

The EXE cycle of `src/core_ctl.v:390-405` advances the ALU sources and result latched in the ifid stage to the exe stage:

```verilog
else if (ifid_token && !exe_token) begin
    exe_pc <= ifid_pc;
    exe_alures <= exe_res_w;      // combinational result, latched on this cycle's edge
    exe_nextpc <= exe_next_pc_w;
    ...
    ifid_token <= 1'b0;
    exe_token <= 1'b1;
end
```

R instructions have no memory access, so `exe_ctl_peripsen = 0` and the PERIPS stage passes through directly (`src/core_ctl.v:428-443`).

## 5. Test: ins/RI.s

`ins/RI.s` covers all I-type and R-type instructions (ADDI/SLTI/XORI/.../ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND).
Each instruction has an `# EXPECT: register value` comment beside it. For example:

```asm
addi x1,x0,10
addi x2,x1,5
# EXPECT: x2 = 15
...
and x31,x5,x7
# EXPECT: 0x55   ← final check of x31 to judge overall pass
```

Verification method (choose one):

1. **ModelSim**: assemble → link → objcopy `RI.s` to `imem.bin`, `bin2mem.py` converts to `imem.mem`,
   run `sim.do`, and in the tb's final register snapshot check `x31 = 0x55` (`tb/mycpu_sim.v:412-417`).
2. **Waveform**: after `add wave *`, directly observe `exe_alures` and `regfile` changes.

> The complete usage of the simulation platform (clock/reset, register snapshot, instruction disassembly, `STOP_PC` breakpoint,
> `sim.do` one-click run) is described in **`12-tb-simulation-guide.md`**.

## 6. Common Error Troubleshooting Points

- **Result 0 or garbage**: first check whether `ctl_alufunc_w` (`src/ctl_exe.v`) is correct, then check the ALU source selection
  `ifid_alusrc1/2` (`opt_alusrc2` in `src/ctl_ifid.v`).
- **Register not written**: check whether `perips_ctl_regw` is 1 in the WB retire cycle, and whether `wb_reg_w` selects `OPT_WB_ALU`.
- **Wrong next PC**: check `next_func` of `exe_next` (should be `NEXT_SEQ` for R instructions).
