---
permalink: /learn/02-software-stack/03-multitasking/
lang: en
---
# 03. Multitasking System

This article is based on `rtos/sys/kernel.c` and `rtos/src/app.c`, and explains the
scheduling, task states, context switching, and synchronization mechanisms of this
project's RTOS.

## 1. Task Control Block (include/kernel.h)

```c
typedef enum { TASK_READY=0, TASK_RUNNING, TASK_WAITING } eTaskState;
typedef enum { WAIT_NONE=0, WAIT_DELAY, WAIT_UART, WAIT_SUSPEND } eWaitReason;

typedef struct {
    uint32_t *sp;              // stack pointer (points to the SAVE_CONTEXT frame)
    eTaskState state;          // task state
    eWaitReason wait_reason;   // blocking reason
    uint32_t wake_tick;        // wake-up tick for delays
    void (*entry)(void *arg);  // task entry
    void *arg;
    const char *name;
    uint32_t *stack_base;      // stack base (for low-watermark detection)
    uint32_t stack_words;      // stack size (words)
} task_t;
#define MAX_TASKS 8
```

The task table is a **fully static** array `tasks[MAX_TASKS]` (`kernel.c:6`), with no
dynamic memory allocation.

## 2. Task Creation (kernel.c:67-92)

```c
int task_create(void (*entry)(void*), const char *name, void *arg,
                uint32_t *stack, uint32_t stack_words) {
    ...
    prvInitialiseStack(pxTask);   // forge the initial frame
    return (int)uxTaskCount++;
}
```

`prvInitialiseStack` (`kernel.c:20-46`) forges a frame matching the SAVE_CONTEXT layout:
- 36 words down from the stack top (144B).
- `pxTop[0]=gp`, `pxTop[1]=tp` (current values), `pxTop[2]=ra=0`, `pxTop[8]=a0=arg`.
- `pxTop[124/4]=0x1880` (mstatus: MPP=M, **MPIE=1**).
- `pxTop[128/4]=entry` (mepc = task entry).

At first scheduling, `vPortStartFirstTask` loads this frame → `mret` enters the task,
and `MPIE=1` enables interrupts automatically.

## 3. Scheduler: Full-Table Scan Round-Robin (kernel.c:95-136)

```c
static int prvFindNextReady(void) {
    int iStart = (iCurrentIndex < 0) ? 0 : (iCurrentIndex + 1);
    for (int iStep = 0; iStep < MAX_TASKS; ++iStep) {
        int iIdx = (iStart + iStep) % MAX_TASKS;   // ring-scan starting after the current task
        if ((iIdx < (int)uxTaskCount) && (tasks[iIdx].state == TASK_READY))
            return iIdx;
    }
    return -1;
}

void scheduler_switch(void) {
    if (pxCurrentTCB && pxCurrentTCB->state == TASK_RUNNING)
        pxCurrentTCB->state = TASK_READY;     // demote the current task
    iNext = prvFindNextReady();
    if (iNext < 0) return;
    ...
    tasks[iNext].state = TASK_RUNNING;
    pxCurrentTCB = &tasks[iNext];             // only the pointer changes; sp is restored on the asm side
    iCurrentIndex = iNext;
}
```

It is **only called from the trap context** (MIE=0), so it does not need to disable
interrupts again (`kernel.c:108-112` comment).

## 4. Tick and Preemption (kernel.c:139-154)

```c
void kernel_tick(void) {
    ++kernel_tick_count;
    for (i...) 
        if (WAITING && WAIT_DELAY && wake_tick <= kernel_tick_count) → READY;
    scheduler_switch();       // preempt every tick → time-slice round-robin
}
```

`vHandle_interrupt` (trap context) calls `kernel_tick()` in the timer interrupt — preempting
every 1ms, implementing **preemptive time-slice round-robin**.

## 5. Task API

| API | Purpose | Implementation |
|-----|---------|----------------|
| `task_yield` | Voluntarily yield the CPU | `ecall` → trap → `scheduler_switch` (cooperative) |
| `task_delay(ticks)` | Delay/sleep | set WAITING/WAIT_DELAY/wake_tick inside a critical section → ecall |
| `task_block(reason)` | Block without timeout | same, waits for `task_wakeup` |
| `task_wakeup(id)` | Wake a task | WAITING→READY inside a critical section |
| `task_mark_suspended(id)` | Suspend | set WAITING/WAIT_SUSPEND |

Key point: `task_delay`/`task_block` both do "set state → disable interrupts → ecall",
while `task_wakeup` protects the task table with a critical section.

## 6. Application: 5 Tasks (src/app.c)

```c
static uint32_t idle_stack[256];    // 1KB
static uint32_t rx_stack[256];      // 1KB
static uint32_t shell_stack[1024];  // 4KB
static uint32_t led_stack[256];     // 1KB
static uint32_t game_stack[1024];   // 4KB

task_create(app_idle,    "idle",    0, idle_stack,  256);   // id=0
task_create(app_uart_rx, "uart_rx", 0, rx_stack,    256);   // id=1
shell_task_id = task_create(shell_task, "shell", 0, shell_stack, 1024); // id=2
task_create(app_led,     "led",     0, led_stack,   256);   // id=3
game_task_id  = task_create(game_task,  "game",  0, game_stack, 1024); // id=4
```

Task responsibilities:
- `app_idle`: an infinite `task_yield()` loop — the fallback task when the CPU is idle
  (keeps yielding via ecall).
- `app_uart_rx`: every 10ms runs `uart_poll()` + `input_dispatch()` (the only serial read task).
- `shell_task`: blocks on WAIT_UART, and processes commands after being woken.
- `app_led`: every 500ms runs `gpio_toggle()` (LED blinking — also the "system is alive" indicator).
- `game_task`: initially suspended; runs Asteroids after being woken by the `game` command.

`app_run` (`app.c:45-71`) order: kernel_init → uart_init → create 5 tasks →
gpio_init → shell_init → game_init → input_init → suspend game → **task_start**.

## 7. task_start (kernel.c:219-242)

```c
void task_start(void) {
    vPortSetupTimerInterrupt();        // enable MTIE (not global interrupts)
    __asm__ volatile("csrci mstatus, 0x8");   // keep MIE=0
    iFirst = prvFindNextReady();       // pick the first task
    ...
    vPortStartFirstTask();             // load sp → RESTORE → mret (MPIE=1 → enable interrupts)
    for (;;) { }                       // the scheduler never returns
}
```

## 8. Stack Low-Watermark Detection (kernel.c:269-289)

```c
uint32_t task_stack_usage(int iId) {
    for (p = stack_base; p < sp; ++p)
        if (*p != 0U) break;           // scan from the stack base for nonzero to estimate usage
    ...
}
```

The shell's `task` command uses it to show each task's stack usage/total size
(`shell.c:82-97`), which is very useful for debugging stack overflows.

## 9. Common Pitfalls

- **Task stacks must be big enough**: `shell_stack`/`game_stack` are 1024 words (4KB),
  because `uart_write_dec` and others use on-stack buffers, and shell command parsing also
  recurses/loops.
- **Critical sections must not be missing**: `task_delay` must modify TCB state with
  interrupts disabled, otherwise the tick interrupt may modify state simultaneously causing
  a data race.
- **Timing of enabling interrupts for the first task**: this relies on MPIE=1 in the frame's
  mstatus; you must not `csrsi` early inside task_start.
