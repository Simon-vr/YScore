#ifndef PORTMACRO_H
#define PORTMACRO_H

#define portBYTE_ALIGNMENT            16
#define portBYTE_ALIGNMENT_MASK       (portBYTE_ALIGNMENT - 1)

/* ==================== UART (yscore axil_uart, 0x10000000) ==================== */
#define UART_BASE_ADDR           0x10000000
#define UART_THR                 (UART_BASE_ADDR + 0x00) /* 写发送数据 */
#define UART_RBR                 (UART_BASE_ADDR + 0x04) /* 读接收数据 */
#define UART_STAT                (UART_BASE_ADDR + 0x08) /* 状态: bit0 tx_empty, bit1 tx_busy, bit2 rx_valid, bit3 rx_error */
#define UART_CTRL                (UART_BASE_ADDR + 0x0C)
#define UART_BAUD_DIV            (UART_BASE_ADDR + 0x10)

#define UART_STAT_TX_EMPTY  0x01
#define UART_STAT_TX_BUSY   0x02
#define UART_STAT_RX_VALID  0x04
#define UART_STAT_RX_ERROR  0x08

/* ==================== GPIO (yscore, 输出锁存, 低电平点亮) ==================== */
#define GPIO_BASE_ADDR           0x20000000

/* ==================== CLINT 定时器 ==================== */
/* yscore SoC CLINT mtime 为 50MHz, 1ms tick = 50000 计数 */
#define CLINT_BASE_ADDR                    0x02000000
#define pulTimeLow                      (CLINT_BASE_ADDR + 0xBFF8)
#define pulTimeHigh                     (CLINT_BASE_ADDR + 0xBFFC)
#define pullMachineTimerCompareRegister   (CLINT_BASE_ADDR + 0x4000)

/* 注意: ulTimerIncrementsForOneTick 是真实符号(定义于 port/timer.c), 供汇编读取。
   yscore SoC CLINT 为 50MHz, 1ms tick = 50000 计数。 */

/* ==================== 对 C 文件 ==================== */
#ifndef __ASSEMBLER__
typedef signed char int8_t;
typedef unsigned char uint8_t;
typedef unsigned int uint32_t;
typedef unsigned long long uint64_t;

void vPortSetupTimerInterrupt(void);
void vPortStartFirstTask(void);
void vportENABLE_INTERRUPT(void);
void vportUPDATE_MTIMER_COMPARE_REGISTER(void);
void vPortEnterCritical(void);
void vPortExitCritical(void);
#endif

/* ==================== 对 asm 文件 ==================== */
#ifdef __ASSEMBLER__
.extern ulTimerIncrementsForOneTick
.extern ullNextTime
.extern pullNextTime

.macro SAVE_CONTEXT
    addi sp, sp, -144  # 36*4

    # x0 zero, x2 sp is represented by the active trap-frame pointer
    sw x3,  0(sp)   # gp
    sw x4,  4(sp)   # tp
    sw x1,  8(sp)   # ra
    sw x5,  12(sp)  # t0
    sw x6,  16(sp)  # t1
    sw x7,  20(sp)  # t2
    sw x8,  24(sp)  # s0/fp
    sw x9,  28(sp)  # s1
    sw x10, 32(sp)  # a0
    sw x11, 36(sp)  # a1
    sw x12, 40(sp)  # a2
    sw x13, 44(sp)  # a3
    sw x14, 48(sp)  # a4
    sw x15, 52(sp)  # a5
    sw x16, 56(sp)  # a6
    sw x17, 60(sp)  # a7
    sw x18, 64(sp)  # s2
    sw x19, 68(sp)  # s3
    sw x20, 72(sp)  # s4
    sw x21, 76(sp)  # s5
    sw x22, 80(sp)  # s6
    sw x23, 84(sp)  # s7
    sw x24, 88(sp)  # s8
    sw x25, 92(sp)  # s9
    sw x26, 96(sp)  # s10
    sw x27, 100(sp) # s11
    sw x28, 104(sp) # t3
    sw x29, 108(sp) # t4
    sw x30, 112(sp) # t5
    sw x31, 116(sp) # t6

    csrr t0, mstatus
    csrr t1, mepc
    sw t0, 124(sp)
    sw t1, 128(sp)
.endm

.macro RESTORE_CONTEXT
    lw t0, 124(sp)
    lw t1, 128(sp)
    csrw mstatus, t0
    csrw mepc, t1

    lw x31, 116(sp) # t6
    lw x30, 112(sp) # t5
    lw x29, 108(sp) # t4
    lw x28, 104(sp) # t3
    lw x27, 100(sp) # s11
    lw x26, 96(sp)  # s10
    lw x25, 92(sp)  # s9
    lw x24, 88(sp)  # s8
    lw x23, 84(sp)  # s7
    lw x22, 80(sp)  # s6
    lw x21, 76(sp)  # s5
    lw x20, 72(sp)  # s4
    lw x19, 68(sp)  # s3
    lw x18, 64(sp)  # s2
    lw x17, 60(sp)  # a7
    lw x16, 56(sp)  # a6
    lw x15, 52(sp)  # a5
    lw x14, 48(sp)  # a4
    lw x13, 44(sp)  # a3
    lw x12, 40(sp)  # a2
    lw x11, 36(sp)  # a1
    lw x10, 32(sp)  # a0
    lw x9,  28(sp)  # s1
    lw x8,  24(sp)  # s0/fp
    lw x7,  20(sp)  # t2
    lw x6,  16(sp)  # t1
    lw x5,  12(sp)  # t0
    lw x1,  8(sp)   # ra
    lw x4,  4(sp)   # tp
    lw x3,  0(sp)   # gp
    addi sp, sp, 144
.endm

#endif

#endif