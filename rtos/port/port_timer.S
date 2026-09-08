#include "portmacro.h"

.global vportENABLE_INTERRUPT
.global vportUPDATE_MTIMER_COMPARE_REGISTER

.section .text.port_timer

vportENABLE_INTERRUPT:
    li t0, (1 << 7)
    csrw mie, t0        # 使能时钟中断 (MTIE)
    # 注意: 不要在此处设置 mstatus.MIE。
    # 全局中断由首次 mret 通过任务帧 mstatus(MPIE=1) 打开, 避免启动竞态。
    ret

vportUPDATE_MTIMER_COMPARE_REGISTER:
    li a0, pullMachineTimerCompareRegister
    la a1, pullNextTime
    lw a1, 0(a1)

    li a4, -1
    lw a2, 0(a1)                # 加载ullNextTime低32位
    lw a3, 4(a1)                # 加载ullNextTime高32位

    # 更新MachineTimerCompareRegister
    sw a4, 0(a0)                # 先写入0xFFFFFFFF到低位，防止中间触发中断
    sw a3, 4(a0)                # 写高位
    sw a2, 0(a0)                # 写低位

    # 更新NextTime到下一次
    la t0, ulTimerIncrementsForOneTick
    lw t0, (t0)
    add a4, t0, a2               # 更新低位
    sltu t1, a4, a2              # 看看有没有进位
    add t2, a3, t1               # 有进位就加高位
    sw a4, 0(a1)                 # 写回nexttime低位
    sw t2, 4(a1)                 # 写回高位

    # Keep the timer interrupt minimal. Do not touch GPIO/UART here:
    # peripheral access in an interrupt context can stall the CPU and
    # trigger the deadlock pattern seen during long runs.
    ret