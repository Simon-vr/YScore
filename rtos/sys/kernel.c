#include "kernel.h"
#include "uart.h"
#include "math.h"

/* ==================== 任务表(全静态) ==================== */
static task_t tasks[MAX_TASKS];
static uint32_t uxTaskCount = 0U;
static int iCurrentIndex = -1;

task_t * volatile pxCurrentTCB = 0;
volatile uint32_t kernel_tick_count = 0U;
volatile uint32_t context_switch_count = 0U;

/* ==================== 栈初始化 ==================== */
/*
 * 伪造一个符合 SAVE_CONTEXT / RESTORE_CONTEXT 布局的帧:
 * 帧内保存 gp/tp、通用寄存器，末尾(124/128 字节处)存 mstatus / mepc。
 * 首次调度时 vPortStartFirstTask() 载入 sp -> RESTORE_CONTEXT -> mret 进入任务。
 */
static void prvInitialiseStack(task_t *pxTask)
{
    uint32_t *pxTop = pxTask->stack_base + pxTask->stack_words;
    uint32_t ulInitialGp;
    uint32_t ulInitialTp;

    __asm__ volatile("mv %0, gp" : "=r"(ulInitialGp));
    __asm__ volatile("mv %0, tp" : "=r"(ulInitialTp));

    while ((((uint32_t)pxTop) & portBYTE_ALIGNMENT_MASK) != 0U) {
        --pxTop;
    }
    pxTop -= 36U;   /* 36 字帧, 144 字节 */

    for (uint32_t i = 0U; i < 36U; ++i) {
        pxTop[i] = 0U;
    }

    pxTop[0U] = ulInitialGp;                      /* gp */
    pxTop[1U] = ulInitialTp;                      /* tp */
    pxTop[2U] = 0U;                               /* ra */
    pxTop[8U] = (uint32_t)pxTask->arg;            /* a0 */
    pxTop[124U / sizeof(uint32_t)] = 0x1880U;     /* mstatus: MPP=M, MPIE=1 */
    pxTop[128U / sizeof(uint32_t)] = (uint32_t)pxTask->entry; /* mepc */

    pxTask->sp = pxTop;
}

/* ==================== 初始化 ==================== */
void kernel_init(void)
{
    for (uint32_t i = 0U; i < MAX_TASKS; ++i) {
        tasks[i].entry = 0;
        tasks[i].name = 0;
        tasks[i].state = TASK_READY;
        tasks[i].wait_reason = WAIT_NONE;
        tasks[i].sp = 0;
    }

    uxTaskCount = 0U;
    iCurrentIndex = -1;
    pxCurrentTCB = 0;
    kernel_tick_count = 0U;
    context_switch_count = 0U;
}

/* ==================== 任务创建 ==================== */
int task_create(void (*entry)(void *), const char *name, void *arg,
                uint32_t *stack, uint32_t stack_words)
{
    task_t *pxTask;

    if ((entry == 0) || (name == 0) || (stack == 0) || (stack_words == 0U)) {
        return -1;
    }
    if (uxTaskCount >= MAX_TASKS) {
        return -1;
    }

    pxTask = &tasks[uxTaskCount];
    pxTask->entry = entry;
    pxTask->name = name;
    pxTask->arg = arg;
    pxTask->stack_base = stack;
    pxTask->stack_words = stack_words;
    pxTask->state = TASK_READY;
    pxTask->wait_reason = WAIT_NONE;
    pxTask->wake_tick = 0U;

    prvInitialiseStack(pxTask);

    return (int)uxTaskCount++;
}

/* ==================== 调度器: 全表扫描 round-robin ==================== */
static int prvFindNextReady(void)
{
    int iStart = (iCurrentIndex < 0) ? 0 : (iCurrentIndex + 1);

    for (int iStep = 0; iStep < MAX_TASKS; ++iStep) {
        int iIdx = (iStart + iStep) % MAX_TASKS;
        if ((iIdx < (int)uxTaskCount) && (tasks[iIdx].state == TASK_READY)) {
            return iIdx;
        }
    }
    return -1;
}

/*
 * 在 trap 处理中被调用: 当前任务 sp 已由汇编保存到 pxCurrentTCB->sp。
 * 这里把当前任务降为 READY(若非阻塞), 选出下一个 READY 任务。
 * 注意: 本函数只在 trap 上下文(mcause/MIE=0)被调用, 无需再关中断。
 */
void scheduler_switch(void)
{
    int iNext;

    if ((pxCurrentTCB != 0) && (pxCurrentTCB->state == TASK_RUNNING)) {
        pxCurrentTCB->state = TASK_READY;
    }

    iNext = prvFindNextReady();
    if (iNext < 0) {
        return;
    }

    if (pxCurrentTCB != &tasks[iNext]) {
        ++context_switch_count;
    }

    tasks[iNext].state = TASK_RUNNING;
    pxCurrentTCB = &tasks[iNext];
    iCurrentIndex = iNext;

    /* Never print from interrupt context: UART TX is a blocking peripheral,
       and a stuck TX state can deadlock the scheduler. */
}

/* ==================== tick(定时器中断入口, trap 上下文) ==================== */
void kernel_tick(void)
{
    ++kernel_tick_count;

    for (uint32_t i = 0U; i < uxTaskCount; ++i) {
        if ((tasks[i].state == TASK_WAITING) &&
            (tasks[i].wait_reason == WAIT_DELAY) &&
            (tasks[i].wake_tick <= kernel_tick_count)) {
            tasks[i].state = TASK_READY;
            tasks[i].wait_reason = WAIT_NONE;
        }
    }

    /* 时间片轮转: 每个 tick 都抢占, 让所有就绪任务共享 CPU */
    scheduler_switch();
}

/* ==================== 任务 API ==================== */
void task_yield(void)
{
    __asm__ volatile("ecall");
}

void task_delay(uint32_t ulTicks)
{
    if (ulTicks == 0U) {
        task_yield();
        return;
    }

    vPortEnterCritical();
    if (pxCurrentTCB != 0) {
        pxCurrentTCB->state = TASK_WAITING;
        pxCurrentTCB->wait_reason = WAIT_DELAY;
        pxCurrentTCB->wake_tick = kernel_tick_count + ulTicks;
    }
    vPortExitCritical();

    task_yield();
}

void task_block(eWaitReason reason)
{
    vPortEnterCritical();
    if (pxCurrentTCB != 0) {
        pxCurrentTCB->state = TASK_WAITING;
        pxCurrentTCB->wait_reason = reason;
    }
    vPortExitCritical();

    task_yield();
}

void task_wakeup(int iId)
{
    if ((iId < 0) || (iId >= (int)uxTaskCount)) {
        return;
    }

    vPortEnterCritical();
    if (tasks[iId].state == TASK_WAITING) {
        tasks[iId].state = TASK_READY;
        tasks[iId].wait_reason = WAIT_NONE;
    }
    vPortExitCritical();
}

void task_mark_suspended(int iId)
{
    if ((iId < 0) || (iId >= (int)uxTaskCount)) {
        return;
    }

    vPortEnterCritical();
    tasks[iId].state = TASK_WAITING;
    tasks[iId].wait_reason = WAIT_SUSPEND;
    vPortExitCritical();
}

/* ==================== 启动调度器 ==================== */
void task_start(void)
{
    int iFirst;

    /* 使能 MTIE(不使能全局中断) */
    vPortSetupTimerInterrupt();

    /* 保持 MIE=0, 直到首次 mret 通过任务帧 mstatus(MPIE=1) 打开全局中断 */
    __asm__ volatile("csrci mstatus, 0x8" ::: "memory");

    iFirst = prvFindNextReady();
    if (iFirst < 0) {
        for (;;) {
        }
    }
    tasks[iFirst].state = TASK_RUNNING;
    pxCurrentTCB = &tasks[iFirst];
    iCurrentIndex = iFirst;

    vPortStartFirstTask();

    for (;;) {
    }
}

/* ==================== 查询 ==================== */
uint32_t task_count(void)
{
    return uxTaskCount;
}

int task_id_by_name(const char *pcName)
{
    for (uint32_t i = 0U; i < uxTaskCount; ++i) {
        const char *pcA = tasks[i].name;
        const char *pcB = pcName;
        while ((*pcA != '\0') && (*pcB != '\0')) {
            if (*pcA != *pcB) {
                break;
            }
            ++pcA;
            ++pcB;
        }
        if ((*pcA == '\0') && (*pcB == '\0')) {
            return (int)i;
        }
    }
    return -1;
}

uint32_t task_stack_usage(int iId)
{
    task_t *pxTask;
    uint32_t ulFree = 0U;
    uint32_t *p;

    if ((iId < 0) || (iId >= (int)uxTaskCount)) {
        return 0U;
    }

    pxTask = &tasks[iId];
    for (p = pxTask->stack_base; p < pxTask->sp; ++p) {
        if (*p == 0U) {
            ++ulFree;
        } else {
            break;
        }
    }
    return (ulFree < pxTask->stack_words) ? (pxTask->stack_words - ulFree)
                                          : pxTask->stack_words;
}

const char *task_name(int iId)
{
    if ((iId < 0) || (iId >= (int)uxTaskCount) || (tasks[iId].name == 0)) {
        return "?";
    }
    return tasks[iId].name;
}

uint32_t task_stack_size(int iId)
{
    if ((iId < 0) || (iId >= (int)uxTaskCount)) {
        return 0U;
    }
    return tasks[iId].stack_words;
}

const char *task_state_str(int iId)
{
    if ((iId < 0) || (iId >= (int)uxTaskCount)) {
        return "?";
    }

    switch (tasks[iId].state) {
        case TASK_READY:   return "READY";
        case TASK_RUNNING: return "RUNNING";
        case TASK_WAITING: return "WAITING";
        default:           return "?";
    }
}

const char *task_wait_str(int iId)
{
    if ((iId < 0) || (iId >= (int)uxTaskCount)) {
        return "?";
    }

    switch (tasks[iId].wait_reason) {
        case WAIT_NONE:    return "-";
        case WAIT_DELAY:   return "DELAY";
        case WAIT_UART:    return "UART";
        case WAIT_SUSPEND: return "SUSPEND";
        default:           return "?";
    }
}
