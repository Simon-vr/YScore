---
permalink: /learn/01-hardware-basics/10-uart-gpio-adaptation/
lang: en
---
# 10. UART / GPIO Peripheral Adaptation

## 1. UART (axil_uart.v)

AXI4-Lite slave; this project only uses 5 registers (`src/core_perips.v:187-197` comments):

| Offset | Register | Direction | Description |
|--------|----------|-----------|-------------|
| 0x00 | TX_DATA | W | transmit byte (bits[7:0]) |
| 0x04 | RX_DATA | R | receive byte (bits[7:0]) |
| 0x08 | STATUS | R | bit0 tx_empty, bit1 tx_busy, bit2 rx_valid, bit3 rx_error |
| 0x0C | CTRL | R/W | control |
| 0x10 | BAUD_DIV | R/W | baud rate divider |

### 1.1 Register Definition (rtos/port/portmacro.h:8-18)

```c
#define UART_BASE_ADDR  0x10000000
#define UART_THR        (UART_BASE_ADDR + 0x00)  /* write to transmit */
#define UART_RBR        (UART_BASE_ADDR + 0x04)  /* read from receive */
#define UART_STAT       (UART_BASE_ADDR + 0x08)  /* status */
#define UART_CTRL       (UART_BASE_ADDR + 0x0C)
#define UART_BAUD_DIV   (UART_BASE_ADDR + 0x10)

#define UART_STAT_TX_EMPTY  0x01
#define UART_STAT_TX_BUSY   0x02
#define UART_STAT_RX_VALID  0x04
#define UART_STAT_RX_ERROR  0x08
```

### 1.2 Driver (rtos/lib/uart.c)

**Transmit** (`uart_write_char`, `uart.c:56-71`) — poll until TX is empty, then write:

```c
while (((*uart_reg(UART_STAT) & UART_STAT_TX_EMPTY) == 0U) ||
       ((*uart_reg(UART_STAT) & UART_STAT_TX_BUSY) != 0U)) {
    ++timeout;
    if (timeout >= UART_TX_TIMEOUT) return;   // 100000 iterations to prevent a hang
}
*uart_reg(UART_THR) = (uint8_t)c;
```

> The timeout mechanism (`UART_TX_TIMEOUT`) was added later: if TX gets stuck by the peripheral, you must never busy-wait and freeze the whole system.
> This is also the origin of the "don't touch UART in an interrupt context" comments in `kernel.c:134` and `port_timer.S:38`.

**Receive** (`uart_poll`, `uart.c:24-36`) — reads hardware RX into a software ring buffer:

```c
while ((*uart_reg(UART_STAT) & UART_STAT_RX_VALID) != 0U) {
    char c = (char)*uart_reg(UART_RBR);
    uint32_t next = (rx_head + 1U) & RX_RING_MASK;   // 128B ring buffer
    if (next != rx_tail) { rx_ring[rx_head] = c; rx_head = next; }
    /* drop if full */
}
```

**Ring buffer** (`uart.c:9-11`): `rx_ring[128]` + `rx_head`/`rx_tail`,
SPSC (single producer = uart_rx task, single consumer = shell/game task).

## 2. GPIO (axil_gpio.v)

AXI4-Lite slave; this project only uses the low 4 bits to drive LEDs, **active-low** (bit=0 → on).
Registers (`src/core_perips.v:238-241`):

| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | DATA | output latch / read pins |
| 0x08 | DIR | direction (0=input, 1=output) |

### 2.1 Driver (rtos/lib/gpio.c)

```c
void gpio_init(void) {
    GPIO_DIR = 0x0FU;              // [3:0] set to output
    gpio_output = 0x0FU;           // active-low: all 1 = all off
    GPIO_DATA = gpio_output;
}
void gpio_toggle(void) {
    gpio_output ^= GPIO_LED_MASK;  // toggle bit0
    GPIO_DATA = gpio_output;
}
```

### 2.2 Hardware Reset Value

`axil_gpio.v:129`: `gpio_data_out <= {N_GPIO{1'b0}}` — **on reset all 0 = all on**.
Software's `gpio_init` writes 0x0F to turn everything off. This explains why in the debug records the "LED state" can serve as
a diagnostic signal for "whether the CPU has run gpio_init" (see 03-debug-pitfalls/03).

## 3. How UART/GPIO Are Used by the Upper Layers

- The `app_led` task calls `gpio_toggle()` every 500ms (`rtos/src/app.c:35-43`) → LED blinks.
- `shell_cmd_gpio` reads `gpio_get_output()` and prints the LED state (`rtos/src/shell.c:269-277`).
- The `uart_rx` task calls `uart_poll()` every 10ms to collect input (`rtos/src/app.c:24-33`).
- Shell commands such as `help`/`echo` output through `uart_write_*`.

## 4. Test: ins/uart.c

`ins/uart.c` is the simplest UART loopback test: it echoes each input character after the `> ` prompt.

```c
#define UART_RX     0x10000000   // note: this is the early 3-register layout
#define UART_STATUS 0x10000004
#define UART_TX     0x10000008
...
void test(void) {
    uart_putc('>'); uart_putc(' ');
    while (1) {
        char c = uart_getc();
        if (c=='\r'||c=='\n') { uart_putc('\r'); uart_putc('\n'); uart_putc('>'); uart_putc(' '); }
        else uart_putc(c);
    }
}
```

(This test uses the early register layout, which differs from the current THR/RBR/STAT layout in `portmacro.h` —
when porting, use `portmacro.h` as the authoritative reference.)

## 5. Pitfalls

- **Must check TX_EMPTY and !TX_BUSY before transmitting**: axil_uart has no FIFO; if the TX FSM is busy, writes are silently dropped
  (the single-cycle `tx_start` pulse logic in `src/axil_uart.v`).
- **No RX overrun protection**: axil_uart RX is only single-byte; if multiple bytes arrive during a 1ms poll they will be lost.
  The software layer mitigates this with the 128B ring buffer, but with a 10ms poll period, fast input can still lose data (Game scenario).
- **Active-low**: GPIO writes 0 to turn on, 1 to turn off — don't reverse the logic when debugging.
