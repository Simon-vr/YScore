#include "portmacro.h"

static uint32_t ulCriticalNesting = 0U;

static void port_disable_interrupts(void)
{
    __asm__ volatile("csrci mstatus, 0x8" ::: "memory");
}

static void port_enable_interrupts(void)
{
    __asm__ volatile("csrsi mstatus, 0x8" ::: "memory");
}

void vPortEnterCritical(void)
{
    if (ulCriticalNesting == 0U) {
        port_disable_interrupts();
    }

    ++ulCriticalNesting;
}

void vPortExitCritical(void)
{
    if (ulCriticalNesting == 0U) {
        return;
    }

    --ulCriticalNesting;

    if (ulCriticalNesting == 0U) {
        port_enable_interrupts();
    }
}

uint32_t vPortEnterCriticalFromISR(void)
{
    uint32_t uxSavedMstatus;

    __asm__ volatile("csrr %0, mstatus" : "=r"(uxSavedMstatus));
    __asm__ volatile("csrci mstatus, 0x8" ::: "memory");
    return uxSavedMstatus;
}

void vPortExitCriticalFromISR(uint32_t uxSavedMstatus)
{
    __asm__ volatile("csrw mstatus, %0" :: "r"(uxSavedMstatus) : "memory");
}