---
permalink: /learn/02-software-stack/02-runtime-environment/
lang: en
---
# 02. Runtime Environment

This article explains everything in `rtos/` needed "before a program runs": the linker
script, the startup code, trap handling (the vehicle for context switching), CSR
read/write, and clock interrupt setup.

## 1. Linker Script (startup/link.ld)

```ld
MEMORY {
    irom (x)  : ORIGIN = 0x00000000, LENGTH = 18K   // instructions, FPGA IMEM
    dram (rw) : ORIGIN = 0x80000000, LENGTH = 24K   // data, FPGA DMEM
}
_sys_heap_size = 1K;
_sys_stack_size = 8K;
__global_pointer$ = ORIGIN(dram) + LENGTH(dram) / 2;
```

- `.text` goes to irom, `.data`/`.bss`/`.stack` go to dram.
- `_stack_top = ORIGIN(dram) + LENGTH(dram)` (stack top = top of DRAM).
- `PROVIDE` exports `_stack_top`/`_bss_start`/`_bss_end` and other symbols for use by
  the assembly/startup code.

## 2. Startup Code (startup/startup.S)

```asm
_start:
    la sp, _stack_top          # set stack top
    la gp, __global_pointer$   # set global pointer (gp-relative addressing optimization)
    la a0, _bss_start          # clear .bss
    la a1, _bss_end
    bgeu a0, a1, 4f
3:  sw zero, 0(a0)
    addi a0, a0, 4
    bltu a0, a1, 3b
4:  la t0, trap_handler
    csrw mtvec, t0             # set trap vector
    call main                  # enter C entry
    li a0, 0; li a7, 93; ecall # syscall exit after main returns (never happens)
```

Key points:
- **No .data relocation**: at link time the data segment is placed directly in dram
  (0x80000000), already loaded by `$readmemh`.
- **.bss must be cleared**: C uninitialized global variables are a zero-value region in
  the linker, but RAM is random at power-on, so it must be zeroed.
- **gp points to the middle of dram**: the compiler uses gp-relative addressing to access
  the small-data region (`sdata/sbss`).

## 3. Trap Handling and Context Switching (port/portASM.S)

`trap_handler` is the single entry point for all interrupts/exceptions:

```asm
trap_handler:
    SAVE_CONTEXT               # save 36 registers to the stack (144-byte frame)
    la t0, pxCurrentTCB
    lw t0, 0(t0)
    sw sp, 0(t0)               # store current task sp back into the TCB
    csrr a0, mcause
    csrr a1, mepc
    bge a0, x0, synchronous_exception   # mcause sign bit: 0=exception, 1=interrupt
asynchronous_interrupt:
    call vHandle_interrupt
    j processed_source
synchronous_exception:
    addi a1, a1, 4             # synchronous exception return address +4 (skip ecall/ebreak)
    sw a1, 128(sp)             # write back mepc into the frame
    call vHandle_exception
    j processed_source
processed_source:
    la t0, pxCurrentTCB
    lw t0, 0(t0)
    lw sp, 0(t0)               # may have switched to the new task sp
    RESTORE_CONTEXT
    mret
```

The `SAVE_CONTEXT`/`RESTORE_CONTEXT` macros are in `portmacro.h:54-132`:
- The frame is 144 bytes (36 words), saving gp/tp/ra and all general-purpose registers,
  with mstatus@124 and mepc@128 stored at the end.
- **The stack grows down**: after `addi sp, sp, -144`, registers are pushed in order from offset 0.

At first startup, `vPortStartFirstTask` (`portASM.S:6-11`) fetches the first task's sp from
the TCB, then `RESTORE_CONTEXT` + `mret` enters the first task (frame mepc = task entry,
mstatus MPIE=1 → interrupts enabled).

## 4. Interrupt Handling Dispatch (port/interrupt.c)

```c
void vHandle_interrupt(uint32_t mcause, uint32_t mepc) {
    switch (mcause & 0x7fffffffU) {
        case 7U:  // timer interrupt
            vportUPDATE_MTIMER_COMPARE_REGISTER();  // re-arm mtimecmp
            kernel_tick();                           // tick++ and preemptive schedule
            break;
    }
}
void vHandle_exception(uint32_t mcause, uint32_t mepc) {
    switch (mcause & 0x7fffffffU) {
        case 11U: scheduler_switch(); return;   // ecall: cooperative task switch
        ...
    }
}
```

Note that `print_trap_info` at `interrupt.c:73` is commented out (it originally printed to
the UART from the trap context; a blocking peripheral would hang the system — see `kernel.c:134`
and 03-debug-pitfalls).

## 5. Clock Interrupt Setup (port/timer.c + port_timer.S)

`vPortSetupTimerInterrupt` (`timer.c:8-27`):
1. Reads the 64-bit mtime stably (a `do...while` verifies the high word does not wrap).
2. `ullNextTime = mtime + 50000` (1ms at 50MHz).
3. Writes mtimecmp, then pre-adds 50000 once more.
4. `vportENABLE_INTERRUPT()`: `csrw mie, (1<<7)` enables only MTIE.

`vportUPDATE_MTIMER_COMPARE_REGISTER` (`port_timer.S:15-41`) is called in every tick interrupt:
- First writes the mtimecmp low word `0xFFFFFFFF` to prevent mid-trigger, then the high word,
  then the low word (safe 64-bit write).
- `ullNextTime += 50000` (with carry).
- In assembly, **it never touches UART/GPIO** (see the comment at `port_timer.S:38-40`).

> **Startup race**: `vportENABLE_INTERRUPT` enables only `mie.MTIE`, **not** `mstatus.MIE`.
> Global interrupts are enabled by the first task's frame `mstatus(MPIE=1)` on `mret`
> (`kernel.c:226-227` explicitly does `csrci mstatus, 0x8` keeping MIE=0 until the first mret).

## 6. Critical Section (port/critical.c)

```c
static uint32_t ulCriticalNesting = 0U;
void vPortEnterCritical(void) {
    if (ulCriticalNesting == 0U) port_disable_interrupts();  // csrci mstatus,0x8
    ++ulCriticalNesting;
}
void vPortExitCritical(void) {
    if (ulCriticalNesting == 0U) return;
    --ulCriticalNesting;
    if (ulCriticalNesting == 0U) port_enable_interrupts();   // csrsi mstatus,0x8
}
```

The nesting counter guarantees interrupts are only truly disabled/enabled at the outermost
level. Task state modifications (`task_delay`/`task_wakeup`) are all wrapped in critical sections.

## 7. lib / sys Utilities

- `lib/math.c`: RV32I has no M extension, so `umul/udiv/umod/imul/idiv/imod` are implemented
  with shifts and add/subtract (`umul_core` accumulates bit by bit, `udivmod_core` uses the
  restoring remainder method).
- `lib/utils.c`: `utils_skip_spaces` / `utils_streq` / `utils_parse_hex` (used for shell parsing).
- `sys/mem.c`: `vPortMemCpy` / `vPortMemSet` (freestanding, no libc).

## 8. Common Pitfalls

- **.bss must be cleared**: forgetting this yields randomly-initialized global variables.
- **The SAVE_CONTEXT frame layout must match prvInitialiseStack**:
  `sys/kernel.c:32` `pxTop -= 36`, `mstatus@124`, `mepc@128` must correspond one-to-one with the
  `portmacro.h` macros.
- **Do not touch blocking peripherals from the trap context**: UART transmission is
  polling/blocking, and printing from inside an interrupt deadlocks the scheduler
  (this project actually hit this; see 03-debug-pitfalls).
