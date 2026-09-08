---
permalink: /learn/03-debug-pitfalls/03-hw-sw-co-debug/
lang: en
---
# 03. Full Record of Hardware-Software Combined Debug

> This is the **most core** chapter of this project: the complete process of debugging a bug
> that really occurred during hardware-software co-debugging. The symptoms kept changing and
> we kept narrowing in, finally pinpointing a very subtle interrupt-semantics error in the
> hardware pipeline.

---

## Round 0: Symptom

After bring-up the system was basically usable, but two weird phenomena appeared:

1. **Input/output mismatch**: typing `help` in the shell returned the `banner` ASCII art.
2. **Whole system hangs after output**: after a long output (e.g. the dozens of lines of `help`),
   the system no longer responds to any input, and the LED freezes in one state.

> Disassembly ruled out a "command-table error": in `shell_parse_line`, `help` is the first and
> fully exact match (`utils_streq`), and `help` can never match the `banner` branch. **So the
> misplacement must come from a corrupted execution flow, not the software logic.**

---

## Round 1: Suspect Stack Overflow

**Symptom**: hangs after output → the first suspicion is **task stack overflow** (UART output
uses an on-stack buffer).

**Troubleshooting**: enlarged the task stacks to the maximum (increased all of `idle/rx/shell/led/game`
stacks in `app.c`).

**Result**: no effect. It still hangs.

**Conclusion**: not a stack overflow. Moved on to suspecting interrupt priority.

---

## Round 2: Suspect External Interrupt Priority / Preemption

**Symptom unchanged**. Began suspecting a **priority conflict between interrupts and CSR instructions**.

**Troubleshooting**: at that time, `regfile_csr.v`'s `intrpt` was **combinational logic**:

```verilog
assign intrpt = perips_token && csr[0][3] && csr[2][7] && mtip;
```

`core_ctl`'s PC redirect only looks at this `intrpt`, but CSR writes (`csrci mstatus` to clear
MIE, etc.) have **higher priority** than the interrupt branch in `regfile_csr`'s if-else. So when
a CSR instruction retired exactly at the moment `mtip` fired: the PC was redirected into the trap,
but `mepc/mcause` were **stale values from the previous trap** (a phantom trap) → the return
address was corrupted.

**Change 1**: made `intrpt` a **registered output** (`regfile_csr.v:23`), set only in the interrupt
capture branch and cleared otherwise; and added one cycle to the WB stage (`core_ctl.v` adds
`wb_pending`) so the registered `intrpt` is visible on the sampling cycle before the PC is redirected.

**Result**: **still hangs**, but the symptom became "hangs immediately at startup, GPIO stays lit".

> This step "fixed the mechanism and exposed a new bug" — see Round 3.

---

## Round 3: WB-Stage Exception Write Not Idempotent → MIE Always 0

**New symptom**: hangs at startup, GPIO stays lit (low-level lights up, and GPIO is fully lit on reset).

**Troubleshooting**: because WB was given a "retire cycle + sampling cycle" (`core_ctl.v:444-451`),
`perips_token` stays high for **2 cycles** during retirement. But `regfile_csr`'s exception branch
(ecall) writes:

```verilog
csr[0][7] <= csr[0][3];   // MPIE = MIE
csr[0][3] <= 1'b0;        // MIE = 0
```

Executed once on each of two consecutive clock edges:

```
1st edge: MPIE ← MIE(=1)    MIE ← 0
2nd edge: MPIE ← MIE(now=0) MIE ← 0   ← MPIE overwritten to 0!
```

`MPIE←MIE` reads the **current** MIE; on the 2nd edge MIE has already been cleared by the 1st
edge, so MPIE is written as 0. When the task later resumes, `mret` does `MIE←MPIE=0` —
**mstatus.MIE stays 0 forever**, so the 1ms timer interrupt can never fire → the clock interrupt
is dead → all tick-dependent tasks (uart_rx, led) sleep → GPIO stays in the reset-lit state with
no response.

**Locating evidence**: in ModelSim, after the first `ecall` (`task_yield`), mstatus =
`0x1800` (MPIE=0) instead of `0x1880` (MPIE=1).

**Change 2**: made the "retire cycle" take effect for only one cycle (all side effects committed
only once); the 2nd cycle is a separate "sampling cycle" used only to wait for the registered
`intrpt` to be visible before redirecting the PC:

```verilog
end else if (perips_token && !wb_token) begin
    perips_token <= 1'b0;     // retire cycle: GPR/CSR/exception/interrupt capture only this edge
    wb_pending   <= 1'b1;
end else if (wb_pending && !wb_token) begin
    wb_pc        <= wb_pc_w;  // sampling cycle: intrpt visible → redirect PC
    wb_token     <= 1'b1;
    wb_pending   <= 1'b0;
end
```

**Result**: the system could run (banner printed, LED blinking), but the symptom became
"LED blinks twice then hangs" — on to Round 4.

---

## Round 4 (root cause): Interrupt Saves `pc+4` Instead of the Real Next PC

**Symptom**: interrupts work normally now, but "typing help returns banner" persists.

**Deeper troubleshooting**: since the command table is correct and scheduling is alive, "help→banner"
can only mean one thing — **the execution flow is incorrectly jumped back/misplaced somewhere**.
Focus on the interrupt's `mepc` save logic:

`regfile_csr.v`'s interrupt capture write:

```verilog
csr[5] <= pc + 4;   // mepc = PC of the interrupted instruction + 4
```

**Problem**: for **sequential instructions**, the next PC is indeed `pc+4`; but for a **taken
branch / JAL / JALR**, the real next PC is the **jump target** (`perips_nextpc`, already computed
by `exe_next`)!

Interrupt flow: a taken jump is retiring → interrupt capture does `mepc=pc+4` (the fall-through
address) → PC is redirected to mtvec (the jump target is discarded) → the trap handler finishes →
`mret` returns to `pc+4` → **that jump is silently cancelled**, and the execution flow falls into
code it should never execute.

**Why it manifests as "help→banner"**: the idle task runs an infinite `for(;;) task_yield();`,
so an interrupt easily lands on idle's `j` or a **backward jump branch** in a function loop — once
that jump is cancelled, idle "slides" into the neighboring function body in `.text` (such as the
shell init/render code), reprinting earlier output (banner) or corrupting data structures → hang.

**Why it did not happen at first**: the original version (combinational `intrpt`, `mepc=pc`)
"re-executed the interrupted instruction once" — a branch would re-execute, so **the control flow
was actually correct** (double-execution of side effects was another bug). When changed to "save
pc+4" to fix side effects, it accidentally broke the branch control flow; and this bug had been
masked by Round 3's MIE hang until MIE was fixed and interrupts actually started running.

**Change 3 (final fix)**: the interrupt saves the **real next PC**, using `perips_nextpc` (already
computed in the EXE stage) instead of `pc+4`:

```verilog
// regfile_csr.v adds a nextpc input
input [31:0] nextpc;
...
// interrupt capture
csr[5] <= nextpc;   // mepc = the real next PC of the interrupted instruction
```

`core_ctl.v` connects `perips_nextpc` to `regfile_csr`:

```verilog
u_regfile_csr(..., .nextpc(perips_nextpc), ...);
```

> `perips_nextpc` is the "true next PC of this instruction" computed by `exe_next.v`:
> sequential = pc+4, branch = target, JAL = jump target, JALR = {rs1+imm with low bit cleared}.
> Saving it on interrupt lets `mret` return precisely to the next instruction that should execute.
> **Exceptions (ecall/ebreak) still save `pc`** (the software itself skips +4 past the exception instruction).

**Result**: on the board, `help` prints help, `banner` prints banner, input/output fully match;
long output no longer hangs; the LED blinks continuously; `timer`/`task`/`game` all work.
**Finally passing.**

---

## Retrospective: The Relationship Between the Three Bugs

| Round | Bug | Why invisible at the time |
|-------|-----|---------------------------|
| Combinational `intrpt` phantom trap | CSR retirement and interrupt on the same cycle, mepc/mcause stale | Masked by the "hang" of the two bugs below |
| Exception write not idempotent → MPIE=0 → MIE=0 | Interrupts never fire, system sleeps | Exposed only after fix 1 |
| Interrupt saves pc+4 → branch cancelled | Control flow corrupted (help→banner) | Exposed only after fix 2 (interrupts work) |

> Each fix exposes the next layer, all the way down to the deepest root cause.
> **This exactly shows: change only one thing at a time and re-verify after each change,**
> so you can peel apart nested bugs layer by layer.

## Lessons

1. **"Input returns wrong output" ≠ software command-table error**: when the matching logic has
   been proven correct by disassembly, it must be **execution-flow corruption** (wrong PC jump).
2. **The interrupt's return address must be the "real next PC"**: only sequential instructions
   are pc+4; branches/jumps must save the jump target — this is the core requirement of RISC-V
   precise exceptions.
3. **Any "retire cycle" side effect must execute exactly once**: read-modify-write-style updates
   (like `MPIE←MIE; MIE←0`) produce different results if run twice in a row — the easiest pitfall
   of a pipeline "extra cycle".
4. **Use LED state as a diagnostic probe**: GPIO is fully lit on reset (low-level lights up);
   `gpio_init` writes 0x0F to turn it off; "only one lit and not blinking" = the led task toggled
   only once then slept = tick interrupt dead. This repeatedly provided key clues across many rounds.
