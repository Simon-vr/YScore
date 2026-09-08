#include "portmacro.h"

/* yscore SoC CLINT mtime 为 50MHz, 1ms tick = 50000 计数 */
const uint32_t ulTimerIncrementsForOneTick = 50000UL;
uint64_t ullNextTime = 0ULL;
const uint64_t *pullNextTime = &ullNextTime;

void vPortSetupTimerInterrupt(void)
{
    uint32_t ulCurrentTimeHigh;
    uint32_t ulCurrentTimeLow;

    do {
        ulCurrentTimeHigh = *(volatile uint32_t *)(pulTimeHigh);
        ulCurrentTimeLow = *(volatile uint32_t *)(pulTimeLow);
    } while (ulCurrentTimeHigh != *(volatile uint32_t *)(pulTimeHigh));

    ullNextTime = (uint64_t)ulCurrentTimeHigh;
    ullNextTime <<= 32ULL;
    ullNextTime |= (uint64_t)ulCurrentTimeLow;
    ullNextTime += (uint64_t)ulTimerIncrementsForOneTick;

    *(volatile uint64_t *)(pullMachineTimerCompareRegister) = ullNextTime;
    ullNextTime += (uint64_t)ulTimerIncrementsForOneTick;

    vportENABLE_INTERRUPT();
}