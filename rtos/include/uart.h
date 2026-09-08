#ifndef UART_H
#define UART_H
#include "portmacro.h"
void uart_init(void);

/* 轮询输入层: uart_poll() 由 uart_rx 任务周期调用 */
void uart_poll(void);
int uart_available(void);
char uart_getchar(void);

void uart_write_char(char c);
void uart_write_string(const char *str);
void uart_write_dec(uint32_t value);
void uart_write_hex(uint32_t value);
void uart_write_hex8(uint8_t value);

#endif