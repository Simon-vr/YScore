---
permalink: /learn/02-software-stack/04-shell-implementation/
lang: en
---
# 04. Shell Program

This article is based on `rtos/src/shell.c` and explains the implementation of the
command-line Shell. The key point is: **the Shell itself is an RTOS task** that blocks
on serial input and is woken up by the uart_rx task.

## 1. Task Model

```
uart_rx task (every 10ms)          shell task
  uart_poll() → hardware→ring buffer     task_block(WAIT_UART)  ← blocked
  input_dispatch() → data → wake shell
                                        ↓ woken up
  shell_task drains ring buffer: build lines char by char, execute command on Enter
```

`shell_task` (`shell.c:396-413`):

```c
for (;;) {
    task_block(WAIT_UART);               // block waiting for input
    while (uart_available() != 0)
        shell_handle_char(uart_getchar()); // drain the ring buffer
    if (shell_waiting_game != 0) {
        shell_waiting_game = 0;
        task_block(WAIT_SUSPEND);        // suspend shell while game is running
        shell_print_prompt();
    }
}
```

`task_wakeup(shell_task_id)` is called by `input_dispatch` (`input.c:25-30`) — the `uart_rx`
task wakes the current input owner when the ring buffer has data.

## 2. Command Parsing (shell_parse_line, shell.c:289-349)

An `if-else` chain matches each command exactly (`utils_streq` full-string comparison):

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

Supported commands: `help` / `banner` / `task` / `info` / `cpu` / `timer` / `irq` / `gpio` / `game` / `mem`.

## 3. Per-Character Input Handling (shell_handle_char, shell.c:352-390)

```c
if (c == '\r' || c == '\n') {        // Enter submits
    shell_put_crlf();
    if (shell_length == 0U) { shell_print_prompt(); return; }
    shell_parse_line(shell_line);
    shell_reset_line();
    shell_print_prompt();
    return;
}
if (c == '\b' || c == 0x7f) {        // backspace: \b space \b
    if (shell_length != 0U) {
        --shell_length; shell_line[shell_length]='\0';
        uart_write_char('\b'); uart_write_char(' '); uart_write_char('\b');
    }
    return;
}
if (shell_length >= SHELL_INPUT_MAX-1U) { ... "line too long" ... }
shell_line[shell_length++] = c;
shell_line[shell_length] = '\0';
uart_write_char(c);                  // ★ echo happens in the shell layer
```

- Echo is done by the **shell layer** (`shell.c:389`), not the driver layer.
- Line buffer `shell_line[64]`, with overflow protection.

## 4. Key Points of Common Commands

- **task** (`shell.c:77-106`): iterates the task table printing name/state/wait/stack,
  then prints `Tick Count` and `Context Switch`.
- **info** (`shell.c:108-135`): prints CPU/memory/peripheral addresses/RTOS config
  (ISA, 18KB IMEM, 24KB DMEM, UART@0x10000000, GPIO@0x20000000, Tick 1000Hz).
- **cpu** (`shell.c:137-161`): `csrr` reads mstatus/mtvec/mepc/mcause/mie/mip and prints them.
- **timer** (`shell.c:163-197`): reads CLINT mtime/mtimecmp (stable 64-bit read) + mip + tick count.
- **mem** (`shell.c:199-244`): `utils_parse_hex` parses the address, reads memory from the
  `0x10000000` offset and dumps it.
- **gpio** (`shell.c:269-277`): reads `gpio_get_output()`, low level lights up to determine LED ON/OFF.
- **game** (`shell.c:280-286`): `input_set_owner(INPUT_GAME)` + wakes the game task.

## 5. banner Command (shell.c:301-310)

The `banner` command prints the large ASCII text "YSCORE" (composed of `██`/`╚` and other
block characters). This is a marker for debugging whether "the execution flow is correct" —
if you type `help` but get the banner, it means the PC flow is corrupted
(see the root-cause analysis in 03-debug-pitfalls/03).

## 6. Input Ownership (input.c)

Shell and Game share the same UART input; the `input.c` "current owner" mechanism avoids
contention:

```c
static int owner_ids[2];
static eInputOwner current_owner = INPUT_SHELL;   // shell by default

void input_dispatch(void) {
    if (uart_available() != 0)
        task_wakeup(owner_ids[current_owner]);    // only wake the current owner
}
```

- The `game` command → `input_set_owner(INPUT_GAME)`, input belongs to game.
- game exits → `input_set_owner(INPUT_SHELL)`, returns input to shell.

This "input ownership token" mechanism was added later; initially shell and game competed
directly for input, making the game uncontrollable (see 03-debug-pitfalls/02).

## 7. Common Pitfalls

- **Shell-layer echo vs driver-layer echo**: this project echoes in the shell layer; if the
  driver layer also echoed, input would be printed twice.
- **After Enter, a newline + prompt are required**: `shell_put_crlf` + `shell_print_prompt`
  are both indispensable.
- **Commands must match exactly**: `utils_streq` does full-string comparison, so `help` will
  never match `banner` — if "help returns banner", it is a hardware PC corruption, not a
  command-table problem (see the Debug section).
