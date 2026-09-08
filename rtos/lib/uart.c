#include "portmacro.h"
#include "math.h"
#include "uart.h"

#define RX_RING_SIZE 128U
#define RX_RING_MASK (RX_RING_SIZE - 1U)
#define UART_TX_TIMEOUT 100000U

static volatile char rx_ring[RX_RING_SIZE];
static volatile uint32_t rx_head = 0U;
static volatile uint32_t rx_tail = 0U;

static inline volatile uint8_t *uart_reg(uint32_t addr)
{
    return (volatile uint8_t *)(addr);
}

void uart_init(void)
{
    /* 轮询模式: 不开任何 RX 中断, 不碰 PLIC */
}

/* 轮询硬件 -> RX ring buffer。非阻塞, 永不等待。 */
void uart_poll(void)
{
    while ((*uart_reg(UART_STAT) & UART_STAT_RX_VALID) != 0U) {
        char c = (char)*uart_reg(UART_RBR);
        uint32_t next = (rx_head + 1U) & RX_RING_MASK;

        if (next != rx_tail) {
            rx_ring[rx_head] = c;
            rx_head = next;
        }
        /* 缓冲区满则直接丢弃 */
    }
}
/* 检查是否为空, 否则返回 1 */
int uart_available(void)
{
    return (rx_head != rx_tail) ? 1 : 0;
}

char uart_getchar(void)
{
    char c;

    if (rx_head == rx_tail) {
        return 0;
    }

    c = rx_ring[rx_tail];
    rx_tail = (rx_tail + 1U) & RX_RING_MASK;
    return c;
}

void uart_write_char(char c)
{
    volatile uint32_t timeout = 0U;

    /* Never spin forever on a stalled UART peripheral. A stuck TX path
       must not freeze the whole system. */
    while (((*uart_reg(UART_STAT) & UART_STAT_TX_EMPTY) == 0U) ||
           ((*uart_reg(UART_STAT) & UART_STAT_TX_BUSY) != 0U)) {
        ++timeout;
        if (timeout >= UART_TX_TIMEOUT) {
            return;
        }
    }

    *uart_reg(UART_THR) = (uint8_t)c;
}

void uart_write_string(const char *str)
{
    if (str == 0) {
        return;
    }

    while (*str != '\0') {
        uart_write_char(*str++);
    }
}

void uart_write_dec(uint32_t value)
{
    char buf[12];
    unsigned int index = 0U;

    if (value == 0U) {
        uart_write_char('0');
        return;
    }

    while (value > 0U) {
        buf[index++] = (char)('0' + umod(value, 10U));
        value = udiv(value, 10U);
    }

    while (index > 0U) {
        uart_write_char(buf[--index]);
    }
}

void uart_write_hex(uint32_t value)
{
    static const char hex[] = "0123456789abcdef";
    int i;

    uart_write_string("0x");
    for (i = 7; i >= 0; --i) {
        uart_write_char(hex[(value >> (i * 4)) & 0x0fU]);
    }
}

void uart_write_hex8(uint8_t value)
{
    static const char hex[] = "0123456789abcdef";

    uart_write_char(hex[(value >> 4) & 0x0fU]);
    uart_write_char(hex[value & 0x0fU]);
}