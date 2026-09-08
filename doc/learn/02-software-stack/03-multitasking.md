# 03. 多任务系统

本文基于 `rtos/sys/kernel.c` 与 `rtos/src/app.c`，说明本项目 RTOS 的调度、任务状态、
上下文切换与同步机制。

## 1. 任务控制块（include/kernel.h）

```c
typedef enum { TASK_READY=0, TASK_RUNNING, TASK_WAITING } eTaskState;
typedef enum { WAIT_NONE=0, WAIT_DELAY, WAIT_UART, WAIT_SUSPEND } eWaitReason;

typedef struct {
    uint32_t *sp;              // 栈指针（指向 SAVE_CONTEXT 帧）
    eTaskState state;          // 任务状态
    eWaitReason wait_reason;   // 阻塞原因
    uint32_t wake_tick;        // 延时唤醒节拍
    void (*entry)(void *arg);  // 任务入口
    void *arg;
    const char *name;
    uint32_t *stack_base;      // 栈底（低水位检测用）
    uint32_t stack_words;      // 栈大小（字）
} task_t;
#define MAX_TASKS 8
```

任务表是**全静态**数组 `tasks[MAX_TASKS]`（`kernel.c:6`），无动态内存分配。

## 2. 任务创建（kernel.c:67-92）

```c
int task_create(void (*entry)(void*), const char *name, void *arg,
                uint32_t *stack, uint32_t stack_words) {
    ...
    prvInitialiseStack(pxTask);   // 伪造初始帧
    return (int)uxTaskCount++;
}
```

`prvInitialiseStack`（`kernel.c:20-46`）伪造一个符合 SAVE_CONTEXT 布局的帧：
- 栈顶向下 36 字（144B）。
- `pxTop[0]=gp`、`pxTop[1]=tp`（当前值）、`pxTop[2]=ra=0`、`pxTop[8]=a0=arg`。
- `pxTop[124/4]=0x1880`（mstatus：MPP=M、**MPIE=1**）。
- `pxTop[128/4]=entry`（mepc=任务入口）。

首次调度时 `vPortStartFirstTask` 载入该帧 → `mret` 进任务，`MPIE=1` 自动开中断。

## 3. 调度器：全表扫描 round-robin（kernel.c:95-136）

```c
static int prvFindNextReady(void) {
    int iStart = (iCurrentIndex < 0) ? 0 : (iCurrentIndex + 1);
    for (int iStep = 0; iStep < MAX_TASKS; ++iStep) {
        int iIdx = (iStart + iStep) % MAX_TASKS;   // 从当前任务之后环形扫描
        if ((iIdx < (int)uxTaskCount) && (tasks[iIdx].state == TASK_READY))
            return iIdx;
    }
    return -1;
}

void scheduler_switch(void) {
    if (pxCurrentTCB && pxCurrentTCB->state == TASK_RUNNING)
        pxCurrentTCB->state = TASK_READY;     // 当前任务降级
    iNext = prvFindNextReady();
    if (iNext < 0) return;
    ...
    tasks[iNext].state = TASK_RUNNING;
    pxCurrentTCB = &tasks[iNext];             // 只换指针，sp 由汇编端恢复
    iCurrentIndex = iNext;
}
```

**只在 trap 上下文被调用**（MIE=0），所以不需要再关中断（`kernel.c:108-112` 注释）。

## 4. tick 与抢占（kernel.c:139-154）

```c
void kernel_tick(void) {
    ++kernel_tick_count;
    for (i...) 
        if (WAITING && WAIT_DELAY && wake_tick <= kernel_tick_count) → READY;
    scheduler_switch();       // 每个 tick 都抢占 → 时间片轮转
}
```

`vHandle_interrupt`（trap 上下文）在定时器中断里调 `kernel_tick()`——
每 1ms 抢占一次，实现**抢占式时间片轮转**。

## 5. 任务 API

| API | 作用 | 实现 |
|-----|------|------|
| `task_yield` | 主动让出 CPU | `ecall` → trap → `scheduler_switch`（协作式） |
| `task_delay(ticks)` | 延时休眠 | 临界区内置 WAITING/WAIT_DELAY/wake_tick → ecall |
| `task_block(reason)` | 无超时阻塞 | 同上，等 `task_wakeup` |
| `task_wakeup(id)` | 唤醒 | 临界区内 WAITING→READY |
| `task_mark_suspended(id)` | 挂起 | 置 WAITING/WAIT_SUSPEND |

关键：`task_delay`/`task_block` 都是"置状态 → 关中断 → ecall"，
`task_wakeup` 用临界区保护任务表。

## 6. 应用：5 个任务（src/app.c）

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

任务职责：
- `app_idle`：死循环 `task_yield()`——CPU 空闲时的兜底任务（不停 ecall 让权）。
- `app_uart_rx`：每 10ms `uart_poll()` + `input_dispatch()`（唯一的串口读任务）。
- `shell_task`：阻塞在 WAIT_UART，被唤醒后处理命令。
- `app_led`：每 500ms `gpio_toggle()`（LED 闪烁，也是"系统还活着"的指示灯）。
- `game_task`：初始挂起，`game` 命令唤醒后跑 Asteroids。

`app_run`（`app.c:45-71`）顺序：kernel_init → uart_init → 创建 5 任务 →
gpio_init → shell_init → game_init → input_init → 挂起 game → **task_start**。

## 7. task_start（kernel.c:219-242）

```c
void task_start(void) {
    vPortSetupTimerInterrupt();        // 开 MTIE（不开全局中断）
    __asm__ volatile("csrci mstatus, 0x8");   // 保持 MIE=0
    iFirst = prvFindNextReady();       // 选首个任务
    ...
    vPortStartFirstTask();             // 载 sp → RESTORE → mret（MPIE=1 → 开中断）
    for (;;) { }                       // 调度器永不返回
}
```

## 8. 栈低水位检测（kernel.c:269-289）

```c
uint32_t task_stack_usage(int iId) {
    for (p = stack_base; p < sp; ++p)
        if (*p != 0U) break;           // 从栈底扫非零，估已用
    ...
}
```

Shell 的 `task` 命令用它显示每个任务的栈占用/总大小（`shell.c:82-97`），
调试栈溢出非常有用。

## 9. 易错点

- **任务栈必须够大**：`shell_stack`/`game_stack` 是 1024 字（4KB），
  因为 `uart_write_dec` 等用了栈上缓冲，shell 命令解析也会递归/循环。
- **临界区不能缺**：`task_delay` 修改 TCB 状态必须在关中断下进行，
  否则 tick 中断可能同时改状态造成数据竞争。
- **第一个任务开中断时机**：靠帧 mstatus 的 MPIE=1，不能在 task_start 里提前 csrsi。