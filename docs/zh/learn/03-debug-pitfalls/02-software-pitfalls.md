---
permalink: /zh/learn/03-debug-pitfalls/02-software-pitfalls/
---
# 02. 软件部分踩坑：Shell 与 Game 共享 UART 缓冲

本文记录 `rtos` 软件层一个真实 bug：Shell 与 Game 两个任务竞争同一个 UART 输入缓冲，
最终通过"输入所有权令牌"机制解决。对应 `doc/todo.md` 里"debug 踩坑指南 - 软件部分"。

## 1. 背景：两个读输入的任务

- **shell 任务**：阻塞在 `WAIT_UART`，处理命令行。
- **game 任务**：运行时每帧读按键（`game_read_input`）。
- 两者都从同一个 `uart.c` 的 128 字节 RX 环形缓冲读数据
  （生产者是唯一的 `uart_rx` 任务，消费者却有 shell/game 两个）。

## 2. 现象与第一版设计

最初**没有"谁该消费输入"的仲裁**：shell 和 game 都直接
`while (uart_available()) { uart_getchar(); ... }`。

**现象**：启动 `game` 后无法操控游戏——按 `a`/`d`/空格没有反应，
或按键同时被 shell 和 game 抢读。

## 3. 排查

- 确认 ring buffer（`uart.c:9-11`）本身没问题：SPSC（单生产者单消费者）是安全的，
  但这里**消费者有多个**，读 `tail` 的任务不唯一。
- `uart_available()` 的"有数据"判断对两个任务都为真时，谁先被调度谁就把数据读完，
  另一个任务读到空 → 按键丢失。
- shell 醒来后 `while (uart_available())` 会把 game 的按键也吞掉（当作命令行字符），
  甚至可能因为收到非预期字符触发 `unknown command` 打印。

## 4. 解决：输入所有权令牌（rtos/src/input.c）

引入 `input.c` 的"当前 owner"机制，同一时刻只有一个任务有权读输入：

```c
typedef enum { INPUT_SHELL = 0, INPUT_GAME = 1 } eInputOwner;

static int owner_ids[2];
static eInputOwner current_owner = INPUT_SHELL;   // 默认 shell

void input_init(int iShellId, int iGameId) {
    owner_ids[INPUT_SHELL] = iShellId;
    owner_ids[INPUT_GAME] = iGameId;
    current_owner = INPUT_SHELL;
}

void input_set_owner(eInputOwner owner) { current_owner = owner; }

void input_dispatch(void) {   // 由 uart_rx 任务每 10ms 调用
    if (uart_available() != 0)
        task_wakeup(owner_ids[current_owner]);   // 只唤醒当前 owner
}
```

配合任务侧：
- **game 启动**：`shell_cmd_game` 调 `input_set_owner(INPUT_GAME)` + 唤醒 game
  （`shell.c:280-286`）；shell 自己 `shell_waiting_game=1`，随后 `task_block(WAIT_SUSPEND)`。
- **game 退出**：`game_exit` 后 `input_set_owner(INPUT_SHELL)` + 唤醒 shell
  （`game.c:294-296`），game 再 `task_block(WAIT_SUSPEND)` 等下次启动。

这样：
- game 运行时，shell 挂起不读缓冲 → 按键只被 game 消费。
- game 退出，shell 恢复、输入权归还 → 命令行继续可用。

## 5. 教训

1. **单生产者单消费者的环形缓冲，只有消费者唯一时才安全**。
   一旦出现第二个消费者，必须用所有权/令牌仲裁，而不是"谁读到算谁的"。
2. **用任务状态做互斥**：`task_block(WAIT_SUSPEND)` 让不消费输入的任务彻底睡死，
   比靠标志位更可靠（不会在调度空隙抢读）。
3. **唤醒必须只发给当前 owner**：`input_dispatch` 只 `task_wakeup(owner_ids[current_owner])`，
   避免唤醒一个醒来就抢读的任务。