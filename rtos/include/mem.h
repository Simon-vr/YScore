#ifndef LIB_MEM_H
#define LIB_MEM_H

/* 字节级内存拷贝（freestanding，不依赖标准库 memcpy） */
void vPortMemCpy(void *pvDest, const void *pvSource, unsigned int uxCount);

/* 字节级内存填充 */
void vPortMemSet(void *pvDest, char pcValue, unsigned int uxCount);
#endif
