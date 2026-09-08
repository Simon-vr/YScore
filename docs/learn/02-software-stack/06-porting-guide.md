---
permalink: /learn/02-software-stack/06-porting-guide/
lang: en
---
# 06. Porting from QEMU to FPGA (Only Modify the port Layer)

## 1. Porting Philosophy

In this project, software is first debugged on QEMU (standard rv32) and then ported to our
own FPGA CPU. Thanks to the layered design, **porting only requires modifying the
hardware-related code in `rtos/port/`**; the upper layers (`src/*.c`, `sys/kernel.c`,
`lib/*.c`) are reused verbatim.

```
upper (unchanged): src/app.c shell.c game.c input.c / sys/kernel.c / lib/utils.c math.c
port (changed):    port/portmacro.h portASM.S interrupt.c critical.c timer.c port_timer.S
drivers (changed): lib/uart.c lib/gpio.c (different register layouts)
```

## 2. File-by-File Comparison (QEMU → FPGA)

### 2.1 port/portmacro.h — UART Register Definitions (core difference)

QEMU (NS16550):
```c
#define UART_RBR  (UART_BASE_ADDR + 0)
#define UART_THR  (UART_BASE_ADDR + 0)   // RBR/THR share the same address
#define UART_LSR  (UART_BASE_ADDR + 5)
```
FPGA (axil_uart):
```c
#define UART_THR  (UART_BASE_ADDR + 0x00)  // write to transmit
#define UART_RBR  (UART_BASE_ADDR + 0x04)  // read to receive
#define UART_STAT (UART_BASE_ADDR + 0x08)  // status
```

The SAVE/RESTORE_CONTEXT macros, the CLINT base address, and the GPIO base address
(FPGA has it, QEMU does not) are also here.

### 2.2 port/timer.c — CLINT Frequency (a single constant)

```c
// QEMU virt: mtime 10MHz, 1ms = 10000
const uint32_t ulTimerIncrementsForOneTick = 10000UL;
// FPGA yscore: mtime 50MHz, 1ms = 50000
const uint32_t ulTimerIncrementsForOneTick = 50000UL;
```

### 2.3 portASM.S / portmacro.h Frame Layout

Both are identical (144-byte frame, mstatus@124, mepc@128), common to QEMU and FPGA — no change needed.

### 2.4 lib/uart.c — Status Register Bits

```c
// QEMU: LSR bit0 DR / bit5 THRE
// FPGA: STAT bit0 tx_empty / bit1 tx_busy / bit2 rx_valid
```

`uart_poll`'s "has data" check and `uart_write_char`'s "can transmit" check differ, but the
interface `uart_available/getchar/write_*` is unchanged.

### 2.5 lib/gpio.c

QEMU has no GPIO → `gpio.c` degrades to software simulation (state stored in a memory variable);
FPGA → writes `GPIO_DATA` (0x20000000) for real output. The `include/gpio.h` comment explains
the adaptation method.

### 2.6 startup/link.ld — Memory Layout

- QEMU: `.text` @ 0x80000000, `.data` @ 0x80100000 (memory starts at 0x80000000).
- FPGA: `.text` @ 0x00000000 (IMEM), `.data` @ 0x80000000 (DMEM).

## 3. Porting Checklist

- [ ] `portmacro.h` UART/GPIO/CLINT addresses and register layouts.
- [ ] `ulTimerIncrementsForOneTick` in `timer.c` (CLINT frequency).
- [ ] irom/dram base addresses and sizes in `link.ld`.
- [ ] STAT/LSR bit checks in `uart.c`.
- [ ] MMIO writes in `gpio.c` (software simulation on QEMU).
- [ ] `$readmemh` paths in `core_if.v`/`mem_cell.v` point to `rtos/build/*.mem`.

## 4. Build Flow (FPGA Side)

```bash
# 1. Compile firmware
cmake -B build -G Ninja && ninja -C build          # → MiniRTOS.elf
ninja -C build dasm                                 # → disassembly
ninja -C build bin                                  # → *_text.bin / *_data.bin
ninja -C build mem                                  # → imem.mem + dmem0~3.mem

# 2. Synthesize (Quartus GUI or command line) → yscore.sof
# 3. Flash → view output on serial 115200
```

## 5. Post-Porting Must-Tests

- LED blinks every 500ms (tick interrupt + gpio working).
- `timer` command's Tick Count keeps increasing (CLINT frequency correct).
- `help`/`echo`/`info`/`task`/`mem` commands respond correctly (UART TX/RX working).
- After `game` starts/exits, input ownership returns to shell (task/input working).
- Long output + extended burn-in does not freeze (interrupt/scheduler stable).
