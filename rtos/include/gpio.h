#ifndef GPIO_H
#define GPIO_H
#include "portmacro.h"

/*
 * GPIO 驱动。
 *
 * 注意: QEMU virt 机器没有 GPIO 外设, 本模块在 QEMU 下退化为"软件模拟":
 *       状态保存在内存变量中, gpio 命令 / led 任务读取的即是该软件状态。
 *
 * 若移植到自带 GPIO 的真实 SoC, 将 GPIO_BASE_ADDR 指向实际 MMIO 窗口,
 * 并在 gpio_toggle() 中补上寄存器写入即可, 上层 API 不变。
 */
void gpio_init(void);
void gpio_toggle(void);
uint32_t gpio_get_output(void);

#endif