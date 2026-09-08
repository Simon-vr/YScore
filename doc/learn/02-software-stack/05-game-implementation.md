---
permalink: /learn/02-software-stack/05-game-implementation/
lang: en
---
# 05. Game Program (Asteroids)

This article is based on `rtos/src/game.c` and explains the Asteroids mini-game
implementation: VT100 terminal rendering, frame-rate control, input-ownership
contention, and random numbers without hardware multiply/divide.

## 1. Game Overview

- 30×14 character play area; `A` is the ship (moves on the bottom row), `|` is a bullet,
  `*` is an asteroid.
- Keys: `a`/`d` move left/right, ` ` (space) fires, `q`/Esc quits.
- Frame rate 100Hz (`GAME_PERIOD = 10`, i.e. `task_delay(10)` = 10ms).

```c
#define GAME_COLS     30U
#define GAME_ROWS     14U
#define MAX_AST       6U
#define START_LIVES   3U
#define GAME_PERIOD   10U   /* 100Hz */
#define AST_FALL_INTERVAL 5U /* an asteroid falls one row every 5 frames (100ms) */
```

## 2. Input Contention: Sharing UART with Shell

Both Game and Shell are "tasks that read UART input". To avoid contention, the
`input.c` input ownership is used:

- Startup: `shell_cmd_game` calls `input_set_owner(INPUT_GAME)` + `task_wakeup(game_task_id)`
  (`shell.c:280-286`).
- Game input: `game_read_input` (`game.c:159-197`) drains the ring buffer while the game runs.
- Exit: after `game_exit`, `input_set_owner(INPUT_SHELL)` + `task_wakeup(shell_task_id)`
  (`game.c:294-296`), then `task_block(WAIT_SUSPEND)` suspends until the next start.

`int shell_task_id` at `game.c:28` is defined here and assigned by `app.c`.

## 3. Game Main Loop (game_task, game.c:273-300)

```c
for (;;) {
    game_enter();                       // clear screen + draw border
    while (game_quit == 0) {
        game_read_input();              // consume input
        if (game_over != 0) { task_delay(GAME_PERIOD); continue; }  // freeze frame, wait for q
        game_update();                  // logic + render
        task_delay(GAME_PERIOD);        // 100Hz
    }
    game_exit();
    input_set_owner(INPUT_SHELL);
    task_wakeup(shell_task_id);
    task_block(WAIT_SUSPEND);           // suspend, wait for shell to wake again
}
```

`task_delay(GAME_PERIOD)` yields the CPU — the game frame rate is driven by the RTOS clock
interrupt, not by busy-waiting.

## 4. Rendering: VT100 Terminal Control

The terminal must support ANSI escape sequences:

```c
static void put_cursor(uint32_t row, uint32_t col) {
    uart_write_string("\033[");      // ESC[
    uart_write_dec(row);
    uart_write_char(';');
    uart_write_dec(col);
    uart_write_char('H');            // cursor position
}
```

`game_enter` (`game.c:125-150`):
`"\033[H\033[J"` (clear screen) + `"\033[?25l"` (hide cursor) + draw border/score/ship.
`game_exit` (`game.c:152-156`): `"\033[?25h"` (show cursor) + clear screen.

`draw_border` (`game.c:55-78`) uses `put_char_at` to position and draw the `+`/`-`/`|` border.

## 5. Game Logic (game_update, game.c:200-270)

Each frame:

1. **Erase the previous frame's ship** (when `old_ship_x != ship_x`), to avoid motion trails.
2. **Bullets move up**: `bullet_y--`, `put_char_at` draws `|`.
3. **Asteroids fall**: one row every `AST_FALL_INTERVAL` frames (decoupled from the ship/bullet
   frame rate). If one reaches the bottom row and shares the ship's column → `lives--`;
   when it hits 0, `game_over=1` and draw GAME OVER.
4. **Bullet vs asteroid**: same column and row makes the asteroid disappear, `score+=10`.
5. **Finally draw the ship**, ensuring it is not erased by asteroids.

Rendering uses VT100 cursor positioning with per-frame overwrite, so characters do not
accumulate into trails.

## 6. No Hardware Multiply/Divide

`game.c` does not use multiplication. Random numbers use xorshift32 (pure shift + XOR):

```c
static uint32_t rng(void) {
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 17;
    rng_state ^= rng_state << 5;
    return rng_state;
}
```

`respawn_asteroid` (`game.c:108-112`) uses `umod(rng(), GAME_COLS)` for the modulo
(`lib/math.c`'s software remainder, because RV32I has no M extension).

## 7. Common Pitfalls

- **Input ownership**: while the game runs, the shell must be suspended (WAIT_SUSPEND),
  otherwise both reading the ring buffer simultaneously would contend (see 03-debug-pitfalls/02).
- **Frame rate depends on tick**: `task_delay` is woken by the clock interrupt; if the tick
  interrupt is broken, the game appears frozen (a real bug in this project manifested as "hang").
- **Rendering must not go out of bounds**: `put_char_at`'s row/column must stay within the
  terminal; the 30×14 border is the agreed-upon size.
