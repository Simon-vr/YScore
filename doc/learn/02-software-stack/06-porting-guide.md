# 06. 从 QEMU 移植到 FPGA（只需改 port 层）

## 1. 移植思想

本项目软件先在 QEMU（标准 rv32）上调试通过，然后移植到自家 FPGA CPU。
得益于分层设计，**移植只需改 `rtos/port/` 的硬件相关代码**，上层
（`src/*.c`、`sys/kernel.c`、`lib/*.c`）逐字复用。

```
上层（不变）:  src/app.c shell.c game.c input.c / sys/kernel.c / lib/utils.c math.c
移植层（改动）: port/portmacro.h portASM.S interrupt.c critical.c timer.c port_timer.S
驱动（改动）:  lib/uart.c lib/gpio.c（寄存器布局不同）
```

## 2. 逐文件对比（QEMU → FPGA）

### 2.1 port/portmacro.h —— UART 寄存器定义（核心差异）

QEMU（NS16550）：
```c
#define UART_RBR  (UART_BASE_ADDR + 0)
#define UART_THR  (UART_BASE_ADDR + 0)   // RBR/THR 同址
#define UART_LSR  (UART_BASE_ADDR + 5)
```
FPGA（axil_uart）：
```c
#define UART_THR  (UART_BASE_ADDR + 0x00)  // 写发送
#define UART_RBR  (UART_BASE_ADDR + 0x04)  // 读接收
#define UART_STAT (UART_BASE_ADDR + 0x08)  // 状态
```

SAVE/RESTORE_CONTEXT 宏、CLINT 基址、GPIO 基址（FPGA 有，QEMU 无）也在这里。

### 2.2 port/timer.c —— CLINT 频率（一个常量）

```c
// QEMU virt: mtime 10MHz, 1ms = 10000
const uint32_t ulTimerIncrementsForOneTick = 10000UL;
// FPGA yscore: mtime 50MHz, 1ms = 50000
const uint32_t ulTimerIncrementsForOneTick = 50000UL;
```

### 2.3 portASM.S / portmacro.h 帧布局

两者完全一致（144 字节帧、mstatus@124、mepc@128），QEMU 与 FPGA 通用，不用改。

### 2.4 lib/uart.c —— 状态寄存器位

```c
// QEMU: LSR bit0 DR / bit5 THRE
// FPGA: STAT bit0 tx_empty / bit1 tx_busy / bit2 rx_valid
```

`uart_poll` 判断"有接收"、`uart_write_char` 判断"可发送"的条件不同，
但接口 `uart_available/getchar/write_*` 不变。

### 2.5 lib/gpio.c

QEMU 无 GPIO → `gpio.c` 退化为软件模拟（状态存内存变量）；
FPGA → 写 `GPIO_DATA`（0x20000000）真实输出。`include/gpio.h` 注释说明了适配方法。

### 2.6 startup/link.ld —— 内存布局

- QEMU：`.text` @ 0x80000000，`.data` @ 0x80100000（内存从 0x80000000 起）。
- FPGA：`.text` @ 0x00000000（IMEM），`.data` @ 0x80000000（DMEM）。

## 3. 移植检查清单

- [ ] `portmacro.h` UART/GPIO/CLINT 地址与寄存器布局。
- [ ] `timer.c` 的 `ulTimerIncrementsForOneTick`（CLINT 频率）。
- [ ] `link.ld` 的 irom/dram 基址与容量。
- [ ] `uart.c` 的 STAT/LSR 位判断。
- [ ] `gpio.c` 的 MMIO 写（QEMU 为软件模拟）。
- [ ] `core_if.v`/`mem_cell.v` 的 `$readmemh` 路径指向 `rtos/build/*.mem`。

## 4. 构建流程（FPGA 侧）

```bash
# 1. 编译固件
cmake -B build -G Ninja && ninja -C build          # → MiniRTOS.elf
ninja -C build dasm                                 # → 反汇编
ninja -C build bin                                  # → *_text.bin / *_data.bin
ninja -C build mem                                  # → imem.mem + dmem0~3.mem

# 2. 综合（Quartus GUI 或命令行）→ yscore.sof
# 3. 烧录 → 串口 115200 查看输出
```

## 5. 移植后必测项

- LED 500ms 闪烁（tick 中断 + gpio 正常）。
- `timer` 命令 Tick Count 持续增长（CLINT 频率正确）。
- `help`/`echo`/`info`/`task`/`mem` 命令正确响应（UART 收发正确）。
- `game` 启动/退出后输入所有权回到 shell（任务/输入正常）。
- 长输出 + 长时间烤机不冻结（中断/调度稳定）。