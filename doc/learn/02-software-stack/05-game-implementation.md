# 05. Game 程序（Asteroids）

本文基于 `rtos/src/game.c`，说明 Asteroids 小游戏的实现：VT100 终端渲染、
帧率控制、输入所有权竞争、以及无硬件乘除的随机数。

## 1. 游戏概览

- 30×14 字符游戏区，`A` 是飞船（底行移动），`|` 是子弹，`*` 是陨石。
- 按键：`a`/`d` 左右移动，` `（空格）发射，`q`/Esc 退出。
- 帧率 100Hz（`GAME_PERIOD = 10`，即 `task_delay(10)` = 10ms）。

```c
#define GAME_COLS     30U
#define GAME_ROWS     14U
#define MAX_AST       6U
#define START_LIVES   3U
#define GAME_PERIOD   10U   /* 100Hz */
#define AST_FALL_INTERVAL 5U /* 陨石每 5 帧(100ms)落一行 */
```

## 2. 输入竞争：与 Shell 共享 UART

Game 和 Shell 都是"读 UART 输入的任务"。为避免争抢，用 `input.c` 的输入所有权：

- 启动：`shell_cmd_game` 调 `input_set_owner(INPUT_GAME)` + `task_wakeup(game_task_id)`
  （`shell.c:280-286`）。
- 游戏输入：`game_read_input`（`game.c:159-197`）在游戏运行期间排空 ring buffer。
- 退出：`game_exit` 后 `input_set_owner(INPUT_SHELL)` + `task_wakeup(shell_task_id)`
  （`game.c:294-296`），然后 `task_block(WAIT_SUSPEND)` 挂起等下次启动。

`game.c:28` 的 `int shell_task_id` 定义在这里，由 `app.c` 赋值。

## 3. 游戏主循环（game_task, game.c:273-300）

```c
for (;;) {
    game_enter();                       // 清屏 + 画边框
    while (game_quit == 0) {
        game_read_input();              // 消费输入
        if (game_over != 0) { task_delay(GAME_PERIOD); continue; }  // 冻结画面等 q
        game_update();                  // 逻辑 + 渲染
        task_delay(GAME_PERIOD);        // 100Hz
    }
    game_exit();
    input_set_owner(INPUT_SHELL);
    task_wakeup(shell_task_id);
    task_block(WAIT_SUSPEND);           // 挂起，等 shell 再次唤醒
}
```

`task_delay(GAME_PERIOD)` 让出 CPU——游戏帧率由 RTOS 时钟中断驱动，
不是忙等。

## 4. 渲染：VT100 终端控制

终端需要支持 ANSI 转义序列：

```c
static void put_cursor(uint32_t row, uint32_t col) {
    uart_write_string("\033[");      // ESC[
    uart_write_dec(row);
    uart_write_char(';');
    uart_write_dec(col);
    uart_write_char('H');            // 光标定位
}
```

`game_enter`（`game.c:125-150`）：
`"\033[H\033[J"`（清屏）+ `"\033[?25l"`（隐藏光标）+ 画边框/分数/飞船。
`game_exit`（`game.c:152-156`）：`"\033[?25h"`（显示光标）+ 清屏。

`draw_border`（`game.c:55-78`）用 `put_char_at` 定位画 `+`/`-`/`|` 边框。

## 5. 游戏逻辑（game_update, game.c:200-270）

每帧：

1. **擦除上一帧飞船**（`old_ship_x != ship_x` 时），避免移动残影。
2. **子弹上移**：`bullet_y--`，`put_char_at` 画 `|`。
3. **陨石下落**：每 `AST_FALL_INTERVAL` 帧落一行（与飞船/子弹帧率解耦）。
   到底行且与飞船同列 → `lives--`，归 0 则 `game_over=1` 画 GAME OVER。
4. **子弹 vs 陨石**：同列同行使陨石消失、`score+=10`。
5. **最后画飞船**，保证不被陨石擦除。

渲染用 VT100 光标定位，每帧覆盖画，字符不会累积成残影。

## 6. 无硬件乘除

`game.c` 没有用乘法。随机数用 xorshift32（纯移位+异或）：

```c
static uint32_t rng(void) {
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 17;
    rng_state ^= rng_state << 5;
    return rng_state;
}
```

`respawn_asteroid`（`game.c:108-112`）用 `umod(rng(), GAME_COLS)` 取模
（`lib/math.c` 的软取余，因为 RV32I 无 M 扩展）。

## 7. 易错点

- **输入所有权**：game 运行期间 shell 必须挂起（WAIT_SUSPEND），
  否则两者同时读 ring buffer 会争抢（见 03-debug-pitfalls/02）。
- **帧率依赖 tick**：`task_delay` 靠时钟中断唤醒，如果 tick 中断被破坏，
  游戏会假死（本项目的真实 bug 就表现为"卡死"）。
- **渲染不要越界**：`put_char_at` 的行列要保证在终端内，边框 30×14 是约定好的。