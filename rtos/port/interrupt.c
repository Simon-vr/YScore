#include "portmacro.h"

#include "kernel.h"
#include "uart.h"

void vHandle_interrupt(uint32_t mcause, uint32_t mepc)
{
    (void)mepc;

    switch (mcause & 0x7fffffffU) {
        case 7U: /* 定时器中断: tick + 抢占调度 */
            vportUPDATE_MTIMER_COMPARE_REGISTER();
            kernel_tick();
            break;
        default:
            break;
    }
}

static void print_trap_info(const char *cause_str, uint32_t mepc)
{
    uint32_t mtval;

    __asm__ volatile("csrr %0, mtval" : "=r"(mtval));

    uart_write_string("TRAP OCCURRED\r\n");
    uart_write_string("mcause: ");
    uart_write_string(cause_str);
    uart_write_string("\r\nmepc: ");
    uart_write_hex(mepc);
    uart_write_string("\r\nmtval: ");
    uart_write_hex(mtval);
    uart_write_string("\r\nSystem recovered\r\n");
}

void vHandle_exception(uint32_t mcause, uint32_t mepc)
{
    const char *cause_str;

    switch (mcause & 0x7FFFFFFFU) {
        case 11U: /* M-mode ecall: 协作式任务切换 */
            scheduler_switch();
            return;
        case 0U:
            cause_str = "Instruction address misaligned";
            break;
        case 1U:
            cause_str = "Instruction access fault";
            break;
        case 2U:
            cause_str = "Illegal instruction";
            break;
        case 3U:
            cause_str = "Breakpoint (ebreak)";
            break;
        case 4U:
            cause_str = "Load address misaligned";
            break;
        case 5U:
            cause_str = "Load access fault";
            break;
        case 6U:
            cause_str = "Store/AMO address misaligned";
            break;
        case 7U:
            cause_str = "Store/AMO access fault";
            break;
        default:
            cause_str = "Unknown";
            break;
    }

    //print_trap_info(cause_str, mepc);
}