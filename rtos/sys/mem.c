#include "mem.h"

void vPortMemCpy(void *pvDest, const void *pvSource, unsigned int uxCount)
{
    char *pcDest = (char *)pvDest;
    const char *pcSource = (const char *)pvSource;

    for (unsigned int i = 0U; i < uxCount; ++i) {
        pcDest[i] = pcSource[i];
    }
}

void vPortMemSet(void *pvDest, char pcValue, unsigned int uxCount)
{
    char *pcDest = (char *)pvDest;

    for (unsigned int i = 0U; i < uxCount; ++i) {
        pcDest[i] = pcValue;
    }
}
