---
permalink: /learn/01-hardware-basics/08-exception-handling/
lang: en
---
# 08. Internal Exception Path (ecall / ebreak)

## 1. Exception Recognition

`src/ctl_ifid.v:103-125` handles the case of `OP_CSR` with `funct3 == FUNC3_EXCP` (000),
distinguishing them using `imm` (i.e. funct12):

```verilog
F12_ECALL:  is_excp = 1'b1; excp_cause = EXCP_CAUSE_ECALL;  // 11
F12_EBREAK: is_excp = 1'b1; excp_cause = EXCP_CAUSE_EBREAK; // 3
F12_MRET:   is_mret = 1'b1; is_excp = 1'b0;
```

The macros are defined in `src/rvdef.vh:110-128`:

```verilog
`define F12_ECALL   12'h000
`define F12_EBREAK  12'h001
`define F12_MRET    12'h302
`define EXCP_CAUSE_EBREAK  32'd3
`define EXCP_CAUSE_ECALL   32'd11
```

## 2. Exception Path (core_ctl.v:386-389)

The ID stage latches the exception information into `excp_token / excp_ismret / excp_cause`:

```verilog
if_token<=0; ifid_token<=1;
excp_token  <= ifid_ecall_w;   // ecall/ebreak set to 1
excp_ismret <= ifid_mret_w;
excp_cause  <= ifid_mcause_w;
excp_mtval  <= 32'd0;
```

`excp_token` remains held until the next instruction's ID beat, during which it drives:
- `core_wb`'s `csr_wen = 010` (exception CSR write).
- `wb_mux_pc`'s redirect: `excp_token → nextpc = mtvec`.

## 3. CSR Writes on Exception (regfile_csr.v:63-71)

```verilog
else if (perips_token==1 && wen == 3'b010) begin
    intrpt <= 1'b0;
    csr[5] <= pc;            // mepc = address of the ecall/ebreak instruction itself
    csr[6] <= excp_cause;    // mcause = 11 / 3
    csr[7] <= excp_mtval;    // mtval = 0
    csr[0][7] <= csr[0][3];  // MPIE = MIE
    csr[0][3] <= 1'b0;       // MIE = 0
end
```

Note: **mepc saves `pc` (the address of the exception instruction itself)**, not nextpc —
the "next instruction" semantics of ecall/ebreak is handled by software: in the trap handler, `mepc+4` skips the exception instruction.

## 4. Redirect and Return

- **Enter**: `wb_mux_pc` sets `nextpc = mtvec` while `excp_token` is valid, and `wb_pc` is written on the WB sample beat.
- **Return**: software does `csrw mepc` in the trap handler to change the return address, then `mret`;
  hardware's `wen==011` sets `MIE <= MPIE`, and in `wb_mux_pc` `is_mret → nextpc = mepc`.

## 5. Difference Between Interrupts and Exceptions (Important)

| | ecall/ebreak (exception) | timer interrupt |
|---|---|---|
| mcause | 11 / 3 | 0x80000007 (highest bit = 1) |
| mepc | `pc` (exception instruction address, software +4) | `nextpc` (true next PC of the interrupted instruction) |
| software action | `mepc+4` in trap | no need to touch mepc |
| trigger source | the instruction itself (synchronous) | mtip external (asynchronous) |

`rtos/port/portASM.S:20` uses the sign bit of `mcause` to distinguish:
`bge a0, x0, synchronous_exception` (mcause[31]==0 is an exception, ==1 is an interrupt).

## 6. Test: ins/except.s

`ins/except.s` comes with its own trap handler:

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
    beq t0,t1,handle_ecall     # distinguish the two exceptions
    li t1,3
    beq t0,t1,handle_ebreak
    j fail
handle_ecall:
    addi s0,s0,1
    csrr t2,mepc
    addi t2,t2,4
    csrw mepc,t2              # mepc+4 skips the ecall
    mret
```

Verification: `s0` accumulates 1, 2; finally x31=1 means both ecall and ebreak triggered and returned correctly.

## 7. Pitfalls

- **mepc semantics**: exceptions save `pc` (software +4), interrupts save `nextpc` — the two must not be confused;
  confusing them results in a "misaligned return address" (see 03-debug-pitfalls/03).
- **MBIT**: the highest bit of the interrupt mcause must be 1 (`0x80000007`); software relies on it to distinguish the path.
- **Do not re-enable interrupts inside the trap handler**: hardware has already cleared MIE to 0; software must keep interrupts disabled before returning.
