#include "gpio.h"
#include "portmacro.h"

#define GPIO_LED_MASK 0x01U

#define GPIO_DATA (*(volatile uint32_t *)(GPIO_BASE_ADDR + 0x00))
#define GPIO_DIR  (*(volatile uint32_t *)(GPIO_BASE_ADDR + 0x08))

static volatile uint32_t gpio_output = 0U;

void gpio_init(void)
{
    /* GPIO[3:0] 设为输出 (硬件已忽略方向, 仅保持写习惯) */
    GPIO_DIR = 0x0FU;
    /* 低电平点亮: 初始全灭 = 全 1 */
    gpio_output = 0x0FU;
    GPIO_DATA = gpio_output;
}

void gpio_toggle(void)
{
    gpio_output ^= GPIO_LED_MASK;
    GPIO_DATA = gpio_output;
}

uint32_t gpio_get_output(void)
{
    return gpio_output;
}