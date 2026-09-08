---
permalink: /zh/learn/02-software-stack/02-runtime-environment/
---
# 02. 运行时环境

本文说明 `rtos/` 里"程序跑起来之前"需要的一切：链接脚本、启动代码、
trap 处理（上下文切换载体）、CSR 读写、时钟中断设置。

## 1. 链接脚本（startup/link.ld）

```ld
MEMORY {
    irom (x)  : ORIGIN = 0x00000000, LENGTH = 18K   // 指令，FPGA IMEM
    dram (rw) : ORIGIN = 0x80000000, LENGTH = 24K   // 数据，FPGA DMEM
}
_sys_heap_size = 1K;
_sys_stack_size = 8K;
__global_pointer$ = ORIGIN(dram) + LENGTH(dram) / 2;
```

- `.text` 放 irom，`.data`/`.bss`/`.stack` 放 dram。
- `_stack_top = ORIGIN(dram) + LENGTH(dram)`（栈顶=DRAM 顶）。
- `PROVIDE` 导出 `_stack_top`/`_bss_start`/`_bss_end` 等符号供汇编/启动代码用。

## 2. 启动代码（startup/startup.S）

```asm
_start:
    la sp, _stack_top          # 设栈顶
    la gp, __global_pointer$   # 设全局指针（gp 相对寻址优化）
    la a0, _bss_start          # 清 .bss
    la a1, _bss_end
    bgeu a0, a1, 4f
3:  sw zero, 0(a0)
    addi a0, a0, 4
    bltu a0, a1, 3b
4:  la t0, trap_handler
    csrw mtvec, t0             # 设陷阱向量
    call main                  # 进 C 入口
    li a0, 0; li a7, 93; ecall # main 返回后 syscall exit（不会发生）
```

要点：
- **.data 不用搬**：链接时 data 段直接落在 dram（0x80000000），`$readmemh` 已加载好。
- **必须清 .bss**：C 未初始化全局变量在链接器里是 0 值区，RAM 上电随机，必须清零。
- **gp 指向 dram 中点**：编译器用 gp 相对寻址访问小数据区（`sdata/sbss`）。

## 3. trap 处理与上下文切换（port/portASM.S）

`trap_handler` 是所有中断/异常的唯一入口：

```asm
trap_handler:
    SAVE_CONTEXT               # 保存 36 个寄存器到栈（144 字节帧）
    la t0, pxCurrentTCB
    lw t0, 0(t0)
    sw sp, 0(t0)               # 当前任务 sp 存回 TCB
    csrr a0, mcause
    csrr a1, mepc
    bge a0, x0, synchronous_exception   # mcause 符号位: 0=异常, 1=中断
asynchronous_interrupt:
    call vHandle_interrupt
    j processed_source
synchronous_exception:
    addi a1, a1, 4             # 同步异常返回地址 +4（跳过 ecall/ebreak）
    sw a1, 128(sp)             # 写回帧内 mepc
    call vHandle_exception
    j processed_source
processed_source:
    la t0, pxCurrentTCB
    lw t0, 0(t0)
    lw sp, 0(t0)               # 可能已切到新任务 sp
    RESTORE_CONTEXT
    mret
```

`SAVE_CONTEXT`/`RESTORE_CONTEXT` 宏在 `portmacro.h:54-132`：
- 帧 144 字节（36 字），保存 gp/tp/ra 及全部通用寄存器，末尾存 mstatus@124、mepc@128。
- **栈向下增长**，`addi sp, sp, -144` 后从 0 偏移依次压入。

首次启动 `vPortStartFirstTask`（`portASM.S:6-11`）：从 TCB 取首个任务 sp，
`RESTORE_CONTEXT` + `mret` 进入第一个任务（帧内 mepc=任务入口、mstatus MPIE=1 → 开中断）。

## 4. 中断处理分发（port/interrupt.c）

```c
void vHandle_interrupt(uint32_t mcause, uint32_t mepc) {
    switch (mcause & 0x7fffffffU) {
        case 7U:  // 定时器中断
            vportUPDATE_MTIMER_COMPARE_REGISTER();  // 重设 mtimecmp
            kernel_tick();                           // tick++ 并抢占调度
            break;
    }
}
void vHandle_exception(uint32_t mcause, uint32_t mepc) {
    switch (mcause & 0x7fffffffU) {
        case 11U: scheduler_switch(); return;   // ecall：协作式任务切换
        ...
    }
}
```

注意 `interrupt.c:73` 的 `print_trap_info` 被注释掉了（原来在 trap 上下文打印 UART，
阻塞外设会让系统卡死——见 `kernel.c:134` 与 03-debug-pitfalls）。

## 5. 时钟中断设置（port/timer.c + port_timer.S）

`vPortSetupTimerInterrupt`（`timer.c:8-27`）：
1. 稳定读 mtime 64 位（`do...while` 校验高位不翻转）。
2. `ullNextTime = mtime + 50000`（50MHz 下 1ms）。
3. 写 mtimecmp，再预加一次 50000。
4. `vportENABLE_INTERRUPT()`：`csrw mie, (1<<7)` 只开 MTIE。

`vportUPDATE_MTIMER_COMPARE_REGISTER`（`port_timer.S:15-41`）在每次 tick 中断里被调用：
- 先写 mtimecmp 低位 `0xFFFFFFFF` 防中间触发，再写高位、低位（64 位安全写）。
- `ullNextTime += 50000`（带进位）。
- 汇编里**不碰 UART/GPIO**（`port_timer.S:38-40` 注释）。

> **启动竞态**：`vportENABLE_INTERRUPT` 只开 `mie.MTIE`，**不开** `mstatus.MIE`。
> 全局中断靠首个任务的帧 `mstatus(MPIE=1)` 在 `mret` 时打开
> （`kernel.c:226-227` 明确 `csrci mstatus, 0x8` 保持 MIE=0 直到首次 mret）。

## 6. 临界区（port/critical.c）

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

嵌套计数保证最外层才真正关/开中断。任务状态修改（`task_delay`/`task_wakeup`）都包在临界区里。

## 7. lib / sys 工具

- `lib/math.c`：RV32I 无 M 扩展，用移位+加减实现 `umul/udiv/umod/imul/idiv/imod`
  （`umul_core` 逐位累加、`udivmod_core` 恢复余数法）。
- `lib/utils.c`：`utils_skip_spaces` / `utils_streq` / `utils_parse_hex`（shell 解析用）。
- `sys/mem.c`：`vPortMemCpy` / `vPortMemSet`（freestanding，无 libc）。

## 8. 易错点

- **.bss 必须清零**：漏清会得到随机初始化的全局变量。
- **SAVE_CONTEXT 帧布局必须与 prvInitialiseStack 一致**：
  `sys/kernel.c:32` `pxTop -= 36`、`mstatus@124`、`mepc@128` 与 `portmacro.h` 宏一一对应。
- **trap 上下文不要碰阻塞外设**：UART 发送是轮询阻塞，在中断里打印会死锁调度器
  （本项目实际踩过，见 03-debug-pitfalls）。