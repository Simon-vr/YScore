typedef unsigned int uint32_t;

#define UART_BASE   0x10000000

#define UART_RX     (*(volatile unsigned char *)(UART_BASE + 0x00))
#define UART_STATUS (*(volatile unsigned char *)(UART_BASE + 0x04))
#define UART_TX     (*(volatile unsigned char *)(UART_BASE + 0x08))


static int uart_rx_ready(void)
{
    return UART_STATUS & 0x01;
}


static void uart_putc(char c)
{
    while (!(UART_STATUS & 0x02))
        ;

    UART_TX = (unsigned char)c;
}


static char uart_getc(void)
{
    while (!uart_rx_ready())
        ;

    return UART_RX;
}


void test(void)
{
    uart_putc('\r');
    uart_putc('\n');

    uart_putc('>');
    uart_putc(' ');

    while (1)
    {
        char c = uart_getc();

        if (c == '\r' || c == '\n')
        {
            uart_putc('\r');
            uart_putc('\n');
            uart_putc('>');
            uart_putc(' ');
        }
        else
        {
            uart_putc(c);
        }
    }
}