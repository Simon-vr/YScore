# 04. Shell 程序

本文基于 `rtos/src/shell.c`，说明命令行 Shell 的实现，重点是：
**Shell 本身是一个 RTOS 任务**，阻塞在串口输入上，由 uart_rx 任务唤醒。

## 1. 任务模型

```
uart_rx 任务 (每10ms)          shell 任务
  uart_poll() → 硬件→环形缓冲        task_block(WAIT_UART)  ← 阻塞
  input_dispatch() → 有数据→唤醒 shell
                                        ↓ 被唤醒
  shell_task 排空 ring buffer: 逐字符拼行, 回车执行命令
```

`shell_task`（`shell.c:396-413`）：

```c
for (;;) {
    task_block(WAIT_UART);               // 阻塞等输入
    while (uart_available() != 0)
        shell_handle_char(uart_getchar()); // 排空环形缓冲
    if (shell_waiting_game != 0) {
        shell_waiting_game = 0;
        task_block(WAIT_SUSPEND);        // game 运行时 shell 挂起
        shell_print_prompt();
    }
}
```

`task_wakeup(shell_task_id)` 由 `input_dispatch`（`input.c:25-30`）调用——
`uart_rx` 任务发现环形缓冲有数据就唤醒当前输入 owner。

## 2. 命令解析（shell_parse_line, shell.c:289-349）

`if-else` 链逐个精确匹配（`utils_streq` 全串比较）：

```c
if (utils_streq(command, "help"))  { shell_handle_help(); return; }
if (utils_streq(command, "banner")){ ...ASCII banner...; return; }
if (utils_streq(command, "task"))  { shell_cmd_task();  return; }
if (utils_streq(command, "info"))  { shell_cmd_info();  return; }
if (utils_streq(command, "cpu"))   { shell_cmd_cpu();   return; }
if (utils_streq(command, "timer")) { shell_cmd_timer(); return; }
if (utils_streq(command, "irq"))   { shell_cmd_irq();   return; }
if (utils_streq(command, "gpio"))  { shell_cmd_gpio();  return; }
if (utils_streq(command, "game"))  { shell_cmd_game();  return; }
if (command[0]=='m' && ... 'mem')  { shell_cmd_mem(command+3); return; }
uart_write_string("unknown command: "); ...
```

支持命令：`help` / `banner` / `task` / `info` / `cpu` / `timer` / `irq` / `gpio` / `game` / `mem`。

## 3. 逐字符输入处理（shell_handle_char, shell.c:352-390）

```c
if (c == '\r' || c == '\n') {        // 回车提交
    shell_put_crlf();
    if (shell_length == 0U) { shell_print_prompt(); return; }
    shell_parse_line(shell_line);
    shell_reset_line();
    shell_print_prompt();
    return;
}
if (c == '\b' || c == 0x7f) {        // 退格：\b 空格 \b
    if (shell_length != 0U) {
        --shell_length; shell_line[shell_length]='\0';
        uart_write_char('\b'); uart_write_char(' '); uart_write_char('\b');
    }
    return;
}
if (shell_length >= SHELL_INPUT_MAX-1U) { ... "line too long" ... }
shell_line[shell_length++] = c;
shell_line[shell_length] = '\0';
uart_write_char(c);                  // ★ 回显在 shell 层
```

- 回显是 **shell 层**做的（`shell.c:389`），不是驱动层。
- 行缓冲 `shell_line[64]`，溢出保护。

## 4. 常用命令实现要点

- **task**（`shell.c:77-106`）：遍历任务表打印 name/state/wait/stack，
  末尾打印 `Tick Count` 与 `Context Switch`。
- **info**（`shell.c:108-135`）：打印 CPU/内存/外设地址/RTOS 配置
  （ISA、18KB IMEM、24KB DMEM、UART@0x10000000、GPIO@0x20000000、Tick 1000Hz）。
- **cpu**（`shell.c:137-161`）：`csrr` 读 mstatus/mtvec/mepc/mcause/mie/mip 并打印。
- **timer**（`shell.c:163-197`）：读 CLINT mtime/mtimecmp（64 位稳定读）+ mip + tick 计数。
- **mem**（`shell.c:199-244`）：`utils_parse_hex` 解析地址，从 `0x10000000` 偏移读内存并 dump。
- **gpio**（`shell.c:269-277`）：读 `gpio_get_output()`，低电平点亮判断 LED ON/OFF。
- **game**（`shell.c:280-286`）：`input_set_owner(INPUT_GAME)` + 唤醒 game 任务。

## 5. banner 命令（shell.c:301-310）

`banner` 命令输出 ASCII 大字 "YSCORE"（用 `██`/`╚` 等块字符拼的），
这是调试时区分"执行流是否正确"的标志——如果输入 help 却打出 banner，
说明 PC 流错乱（见 03-debug-pitfalls/03 的根因分析）。

## 6. 输入所有权（input.c）

Shell 与 Game 共享同一 UART 输入，用 `input.c` 的"当前 owner"机制避免争抢：

```c
static int owner_ids[2];
static eInputOwner current_owner = INPUT_SHELL;   // 默认 shell

void input_dispatch(void) {
    if (uart_available() != 0)
        task_wakeup(owner_ids[current_owner]);    // 只唤醒当前 owner
}
```

- `game` 命令 → `input_set_owner(INPUT_GAME)`，输入归 game。
- game 退出 → `input_set_owner(INPUT_SHELL)`，归还 shell。

这个"输入所有权令牌"机制是后来加的，最初 shell 与 game 直接竞争输入导致游戏无法操控
（见 03-debug-pitfalls/02）。

## 7. 易错点

- **shell 层回显 vs 驱动层回显**：本项目回显在 shell 层；如果在驱动层也回显，
  输入会打两遍。
- **回车后必须换行+提示符**：`shell_put_crlf` + `shell_print_prompt` 缺一不可。
- **命令必须精确匹配**：`utils_streq` 全串比较，`help` 不会误匹配 `banner`——
  若出现"help 返回 banner"是硬件 PC 错乱，不是命令表问题（见 Debug 章节）。