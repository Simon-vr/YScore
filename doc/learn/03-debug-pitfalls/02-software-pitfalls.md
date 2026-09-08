---
permalink: /learn/03-debug-pitfalls/02-software-pitfalls/
lang: en
---
# 02. Software Pitfalls: Shell and Game Sharing the UART Buffer

This article records a real bug in the `rtos` software layer: the Shell and Game tasks
competing for the same UART input buffer, ultimately solved with the "input ownership token"
mechanism.

## 1. Background: Two Tasks That Read Input

- **shell task**: blocks on `WAIT_UART`, handles command lines.
- **game task**: reads keys every frame while running (`game_read_input`).
- Both read from the same 128-byte RX ring buffer in `uart.c` (the producer is the single
  `uart_rx` task, but the consumers are two: shell and game).

## 2. Symptom and First Version

Initially there was **no arbitration for "who should consume input"**: both shell and game
directly did `while (uart_available()) { uart_getchar(); ... }`.

**Symptom**: after starting `game`, the game could not be controlled — pressing `a`/`d`/space
had no effect, or keys were grabbed by both shell and game at once.

## 3. Troubleshooting

- Confirmed the ring buffer (`uart.c:9-11`) itself was fine: SPSC (single-producer
  single-consumer) is safe, but here there are **multiple consumers**, so the task reading
  `tail` is not unique.
- When `uart_available()`'s "has data" check is true for both tasks, whichever is scheduled
  first drains the data, and the other reads empty → keypresses are lost.
- After shell wakes up, its `while (uart_available())` also swallows the game's keypresses
  (treating them as command-line characters), and may even trigger an `unknown command`
  print on unexpected characters.

## 4. Solution: Input Ownership Token (rtos/src/input.c)

Introduced `input.c`'s "current owner" mechanism so that only one task has the right to read
input at any given time:

```c
typedef enum { INPUT_SHELL = 0, INPUT_GAME = 1 } eInputOwner;

static int owner_ids[2];
static eInputOwner current_owner = INPUT_SHELL;   // shell by default

void input_init(int iShellId, int iGameId) {
    owner_ids[INPUT_SHELL] = iShellId;
    owner_ids[INPUT_GAME] = iGameId;
    current_owner = INPUT_SHELL;
}

void input_set_owner(eInputOwner owner) { current_owner = owner; }

void input_dispatch(void) {   // called by the uart_rx task every 10ms
    if (uart_available() != 0)
        task_wakeup(owner_ids[current_owner]);   // only wake the current owner
}
```

Combined with the task side:
- **game startup**: `shell_cmd_game` calls `input_set_owner(INPUT_GAME)` + wakes game
  (`shell.c:280-286`); the shell itself sets `shell_waiting_game=1`, then `task_block(WAIT_SUSPEND)`.
- **game exit**: after `game_exit`, `input_set_owner(INPUT_SHELL)` + wakes shell
  (`game.c:294-296`), then game does `task_block(WAIT_SUSPEND)` to wait for the next start.

This way:
- While game runs, the shell is suspended and does not read the buffer → keys are only
  consumed by game.
- When game exits, the shell resumes and input ownership is returned → the command line works again.

## 5. Lessons

1. **A single-producer single-consumer ring buffer is only safe when the consumer is unique**.
   Once a second consumer appears, you must arbitrate with ownership/token, not "whoever reads
   it first keeps it".
2. **Use task states for mutual exclusion**: `task_block(WAIT_SUSPEND)` makes the task that does
   not consume input fully sleep, which is more reliable than relying on flag bits (no grabbing
   in scheduler gaps).
3. **Wakeups must go only to the current owner**: `input_dispatch` only does
   `task_wakeup(owner_ids[current_owner])`, avoiding waking a task that would immediately grab input.
