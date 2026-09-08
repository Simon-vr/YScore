#include "portmacro.h"
.global vPortStartFirstTask
.global trap_handler
.section .text.trap_handler
.align 8   # align to 2^8 bytes
vPortStartFirstTask:
    la t0, pxCurrentTCB
    lw t0, 0(t0)   
    lw sp, 0(t0)                       # load sp
    RESTORE_CONTEXT
    mret        # 首次调用疑似有问题

trap_handler:
    SAVE_CONTEXT
    la t0, pxCurrentTCB
    lw t0, 0(t0)
    sw sp, 0(t0)
    csrr a0, mcause                     # handle function param 1 : reason of interrupt
    csrr a1, mepc                       # return addr 
    bge a0, x0, synchronous_exception   # check the signed num's [0]: 0:exception, 1: interrupt

    asynchronous_interrupt:
        call vHandle_interrupt
        j processed_source

    synchronous_exception:
        addi a1, a1, 4                  # Synchronous so update exception return address
        sw a1, 128( sp )                # 写回帧内 mepc 偏移(128), RESTORE_CONTEXT 据此 mret
        call vHandle_exception
        j processed_source

    processed_source:
        la t0, pxCurrentTCB
        lw t0, 0(t0)
        lw sp, 0(t0)
        RESTORE_CONTEXT
        mret
