---
permalink: /learn/01-hardware-basics/07-csr-implementation/
lang: en
---
# 07. CSR Hardware Implementation

## 1. CSR Register File: regfile_csr.v

`src/regfile_csr.v` is the core of the CSR hardware, implementing 9 machine-mode CSRs:

| Index | CSR | Address | Description |
|-------|-----|---------|-------------|
| 0 | mstatus | 0x300 | Machine status (MIE/MPIE/MPP) |
| 1 | misa | 0x301 | Machine ISA |
| 2 | mie | 0x304 | Interrupt enable (bit7=MTIE) |
| 3 | mtvec | 0x305 | Trap vector base address |
| 4 | mscratch | 0x340 | Scratch register |
| 5 | mepc | 0x341 | Exception/interrupt return PC |
| 6 | mcause | 0x342 | Trap cause |
| 7 | mtval | 0x343 | Trap value |
| 8 | mip | 0x344 | Interrupt pending |

The address macros are in `src/rvdef.vh:232-245`. Read/write ports:

```verilog
// src/core_ctl.v:154-170
regfile_csr u_regfile_csr(
    .wen   (perips_token ? wb_csrwen_w : 3'b000),
    .raddr (ifid_csraddr_w),      // read CSR (ID stage)
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

The 3-bit encoding of `wen` (produced by combinational logic in `src/core_wb.v:17-27`):

```
excp_token ? 010   (exception: ecall/ebreak write mepc/mcause/mtval/MPIE/MIE)
is_mret    ? 011   (mret: MIE ← MPIE)
ctl_csrw   ? 001   (CSR instruction write)
default      000
```

## 2. CSR Instruction Decoding

`src/ctl_ifid.v:103-149` handles `OP_CSR`:

- `opt_alusrc2 = OPT_ALUSRC_CSR`: ALU second source = CSR read value (`src/ifid_mux_alusrc2.v`).
- `CSRRSI/CSRRCI/CSRRWI` use `opt_alusrc1 = OPT_ALUSRC1_RS1` (treating rs1 as the immediate uimm).
- funct3 corresponds to the ALU function (`src/ctl_exe.v:93-103`):

```verilog
CSRRW : ALU_SRC1   // direct write
CSRRS : ALU_OR     // set bits: old | rs1
CSRRC : ALU_ANDN   // clear bits: ~rs1 & old (ALU_ANDN = ~data1 & data2)
```

`src/ctl_wb.v:63-67`: CSR instructions `reg_write=1, csr_write=1, opt_wb=OPT_WB_CSR`
(write back the original CSR value, see `src/core_wb.v:40` `OPT_WB_CSR: wbreg=csrdata`).

## 3. CSR Read/Write Timing

- **Read**: in the ID stage `ifid_csraddr_w` combinationally reads out `odata`, latched into `ifid_csr` → `exe_csr` → `perips_csr`.
- **Write**: on the WB retire beat, when `perips_token && ctl_csrw`, `wb_csr_w` (ALU result) is written into the target CSR.

## 4. Interrupt/Exception CSR Updates (Important)

In the `always` block of `regfile_csr.v`, the write priority is:

```
rst > wen==001(CSR instruction) > wen==010(exception) > wen==011(mret) > (perips_token && MIE) interrupt capture > default
```

- **Exception (010)**: `mepc <= pc` (the ecall instruction's own address; software does +4 to skip), `mcause <= excp_cause`,
  `mtval <= excp_mtval`, `MPIE <= MIE`, `MIE <= 0`.
- **Interrupt capture**: condition `perips_token && MIE && MTIE && mtip`,
  `mepc <= nextpc` (**the true next PC of the interrupted instruction**, see below), `mcause <= 0x80000007`,
  `MPIE <= MIE`, `MIE <= 0`, `intrpt <= 1`.
- **mret (011)**: `MIE <= MPIE`.

> **Key design**: interrupt capture saves `nextpc` (i.e. `perips_nextpc`, the **true** next PC of the interrupted instruction),
> rather than `pc+4`. For sequential instructions the two are the same, but for **branches/jumps** (beq/bne/jal/jalr),
> the real next instruction is at the target address, and `pc+4` would be wrong. The full debugging process for this lesson is in
> `03-debug-pitfalls/03` — it was the core bug of this project's final hardware/software co-debugging.

## 5. The intrpt Signal: Registered vs Combinational

In the early version `intrpt` was combinational: `assign intrpt = perips_token && MIE && MTIE && mtip`
(unrelated to the CSR write priority), which caused "CSR instruction retire and interrupt in the same beat" to hijack the PC into a trap but
leave mepc/mcause stale (a phantom trap). The current version makes `intrpt` a **registered output**
(`src/regfile_csr.v:23`), setting `intrpt <= 1` only in the interrupt branch and clearing it to 0 in all other branches.
Combined with the WB "retire beat + sample beat" (`src/core_ctl.v:444-451`),
intrpt is set on the retire beat and sampled by `wb_mux_pc` on the sample beat, completing the redirect.
See `03-debug-pitfalls/03` for details.

## 6. Test: ins/zicsr.s

`ins/zicsr.s` fully verifies the 6 CSR instructions using mscratch (0x340):

```asm
csrrwi x0,0x340,0        # mscratch = 0
li x5,0x12345678
csrrw x6,0x340,x5        # read old value (0) into x6, write the new value
bne x6,x0,fail
csrr x7,0x340            # x7 = 0x12345678
...
csrrs x6,0x340,x5        # set bits (OR)
csrrc x6,0x340,x5        # clear bits (ANDN)
csrrwi/csr rsi/csr rci  # immediate versions
pass: li x31,1; ...
fail: li x31,0; ...
```

Finally look at x31.

## 7. Pitfalls

- **Source of the CSR write value**: it writes `wb_csr_w` (the ALU result); CSRRS's "set" must use `ALU_OR`,
  and CSRRC's "clear" must use `ALU_ANDN` (`~data1 & data2`), and the operand order must not be reversed.
- **Writing back the old value**: a CSR instruction writes back the **old CSR value that was read** (`OPT_WB_CSR: wbreg=csrdata`),
  not the new value.
- **Interrupt saves nextpc**: see Section 4; this is a pitfall this project has hit.
