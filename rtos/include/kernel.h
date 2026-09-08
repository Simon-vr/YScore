#ifndef KERNEL_H
#define KERNEL_H

#include "portmacro.h"

/* ==================== 任务状态 ==================== */
typedef enum {
    TASK_READY = 0,   /* 就绪, 可被调度 */
    TASK_RUNNING,     /* 正在运行 */
    TASK_WAITING      /* 阻塞等待 (wait_reason 说明原因) */
} eTaskState;

typedef enum {
    WAIT_NONE = 0,    /* 非阻塞 */
    WAIT_DELAY,       /* 延时等待 */
    WAIT_UART,        /* 等待串口输入 */
    WAIT_SUSPEND      /* 挂起 */
} eWaitReason;

#define MAX_TASKS 8

/* ==================== 任务控制块 ==================== */
typedef struct {
    uint32_t *sp;              /* 保存/栈顶指针 */
    eTaskState state;          /* 任务状态 */
    eWaitReason wait_reason;   /* 阻塞原因 */
    uint32_t wake_tick;        /* 延时唤醒节拍 */
    void (*entry)(void *arg);  /* 任务入口 */
    void *arg;                 /* 任务参数 */
    const char *name;          /* 任务名 */
    uint32_t *stack_base;      /* 栈底 */
    uint32_t stack_words;      /* 栈大小(字) */
} task_t;

#define current_task pxCurrentTCB

extern task_t * volatile pxCurrentTCB;
extern volatile uint32_t kernel_tick_count;
extern volatile uint32_t context_switch_count;

/* ==================== 内核 API ==================== */
void kernel_init(void);
int  task_create(void (*entry)(void *), const char *name, void *arg,
                 uint32_t *stack, uint32_t stack_words);
void task_start(void);
void task_yield(void);
void task_delay(uint32_t ticks);
void task_block(eWaitReason reason);
void task_wakeup(int id);
void task_mark_suspended(int id);

/* 调度器内部(供 trap 处理调用) */
void scheduler_switch(void);
void kernel_tick(void);

/* ==================== 查询(供 task 命令) ==================== */
uint32_t task_count(void);
int  task_id_by_name(const char *name);
uint32_t task_stack_usage(int id);
uint32_t task_stack_size(int id);
const char *task_name(int id);
const char *task_state_str(int id);
const char *task_wait_str(int id);

#endif
