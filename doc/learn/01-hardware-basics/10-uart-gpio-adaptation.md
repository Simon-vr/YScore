# 10. UART / GPIO 外设适配

## 1. UART（axil_uart.v）

AXI4-Lite 从机，本项目只用到 5 个寄存器（`src/core_perips.v:187-197` 注释）：

| 偏移 | 寄存器 | 方向 | 说明 |
|------|--------|------|------|
| 0x00 | TX_DATA | W | 发送字节（bits[7:0]） |
| 0x04 | RX_DATA | R | 接收字节（bits[7:0]） |
| 0x08 | STATUS | R | bit0 tx_empty, bit1 tx_busy, bit2 rx_valid, bit3 rx_error |
| 0x0C | CTRL | R/W | 控制 |
| 0x10 | BAUD_DIV | R/W | 波特率分频 |

### 1.1 寄存器定义（rtos/port/portmacro.h:8-18）

```c
#define UART_BASE_ADDR  0x10000000
#define UART_THR        (UART_BASE_ADDR + 0x00)  /* 写发送 */
#define UART_RBR        (UART_BASE_ADDR + 0x04)  /* 读接收 */
#define UART_STAT       (UART_BASE_ADDR + 0x08)  /* 状态 */
#define UART_CTRL       (UART_BASE_ADDR + 0x0C)
#define UART_BAUD_DIV   (UART_BASE_ADDR + 0x10)

#define UART_STAT_TX_EMPTY  0x01
#define UART_STAT_TX_BUSY   0x02
#define UART_STAT_RX_VALID  0x04
#define UART_STAT_RX_ERROR  0x08
```

### 1.2 驱动（rtos/lib/uart.c）

**发送**（`uart_write_char`，`uart.c:56-71`）——轮询等 TX 空再写：

```c
while (((*uart_reg(UART_STAT) & UART_STAT_TX_EMPTY) == 0U) ||
       ((*uart_reg(UART_STAT) & UART_STAT_TX_BUSY) != 0U)) {
    ++timeout;
    if (timeout >= UART_TX_TIMEOUT) return;   // 100000 次防卡死
}
*uart_reg(UART_THR) = (uint8_t)c;
```

> 超时机制（`UART_TX_TIMEOUT`）是后期加的：如果 TX 被外设卡住，绝不能死等冻结整个系统。
> 这也是 `kernel.c:134` 与 `port_timer.S:38` 注释里"不要在中断上下文碰 UART"的由来。

**接收**（`uart_poll`，`uart.c:24-36`）——把硬件 RX 读进软件环形缓冲：

```c
while ((*uart_reg(UART_STAT) & UART_STAT_RX_VALID) != 0U) {
    char c = (char)*uart_reg(UART_RBR);
    uint32_t next = (rx_head + 1U) & RX_RING_MASK;   // 128B 环形缓冲
    if (next != rx_tail) { rx_ring[rx_head] = c; rx_head = next; }
    /* 满则丢弃 */
}
```

**环形缓冲**（`uart.c:9-11`）：`rx_ring[128]` + `rx_head`/`rx_tail`，
SPSC（单生产者 uart_rx 任务，单消费者 shell/game 任务）。

## 2. GPIO（axil_gpio.v）

AXI4-Lite 从机，本项目只用到低 4 位驱动 LED，**低电平点亮**（bit=0 → 亮）。
寄存器（`src/core_perips.v:238-241`）：

| 偏移 | 寄存器 | 说明 |
|------|--------|------|
| 0x00 | DATA | 输出锁存 / 读引脚 |
| 0x08 | DIR | 方向（0=输入，1=输出） |

### 2.1 驱动（rtos/lib/gpio.c）

```c
void gpio_init(void) {
    GPIO_DIR = 0x0FU;              // [3:0] 设为输出
    gpio_output = 0x0FU;           // 低电平点亮：全 1 = 全灭
    GPIO_DATA = gpio_output;
}
void gpio_toggle(void) {
    gpio_output ^= GPIO_LED_MASK;  // 翻转 bit0
    GPIO_DATA = gpio_output;
}
```

### 2.2 硬件复位值

`axil_gpio.v:129`：`gpio_data_out <= {N_GPIO{1'b0}}`——**复位时全 0 = 全亮**。
软件 `gpio_init` 写 0x0F 全部熄灭。这解释了 Debug 记录里"LED 状态"为什么能作为
"CPU 有没有跑过 gpio_init"的诊断信号（见 03-debug-pitfalls/03）。

## 3. UART/GPIO 如何被上层使用

- `app_led` 任务每 500ms 调 `gpio_toggle()`（`rtos/src/app.c:35-43`）→ LED 闪烁。
- `shell_cmd_gpio` 读取 `gpio_get_output()` 打印 LED 状态（`rtos/src/shell.c:269-277`）。
- `uart_rx` 任务每 10ms `uart_poll()` 收集输入（`rtos/src/app.c:24-33`）。
- Shell 的 `help`/`echo` 等命令通过 `uart_write_*` 输出。

## 4. 测试：ins/uart.c

`ins/uart.c` 是最简单的 UART 回环测试：提示符 `> ` 后回显每个输入字符。

```c
#define UART_RX     0x10000000   // 注意：这里是早期 3 寄存器布局
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

（该测试是早期寄存器布局，与当前 `portmacro.h` 的 THR/RBR/STAT 布局不同——
移植时以 `portmacro.h` 为准。）

## 5. 易错点

- **发送前必须查 TX_EMPTY 且 !TX_BUSY**：axil_uart 无 FIFO，TX FSM 忙时写入会被静默丢弃
  （`src/axil_uart.v` 的 `tx_start` 单周期脉冲逻辑）。
- **RX 无 overrun 保护**：axil_uart RX 只有单字节，1ms 轮询若同时到达多字节会丢。
  软件层靠 128B 环形缓冲缓解，但 10ms 轮询周期较长，快速输入仍可能丢（Game 场景）。
- **低电平点亮**：GPIO 写 0 才亮，写 1 灭——调试时别把逻辑写反。