#include "game.h"
#include "input.h"
#include "kernel.h"
#include "math.h"
#include "uart.h"

#define GAME_COLS     30U
#define GAME_ROWS     14U
#define MAX_AST       6U
#define START_LIVES   3U
#define GAME_PERIOD   10U   /* 100Hz */
#define AST_FALL_INTERVAL 5U /* 陨石每 5 帧(100ms)落一行 = 速度降为原来的 1/5 */

static uint32_t ship_x;
static uint32_t old_ship_x;
static uint32_t bullet_x;
static uint32_t bullet_y;
static int lives;
static int score;
static uint32_t ast_x[MAX_AST];
static uint32_t ast_y[MAX_AST];
static uint32_t num_ast;
static uint32_t ast_counter;
static int game_quit;
static int game_over;
static uint32_t rng_state;

int shell_task_id = -1;

/* ==================== 随机数(xorshift32, 无乘除法) ==================== */
static uint32_t rng(void)
{
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 17;
    rng_state ^= rng_state << 5;
    return rng_state;
}

/* ==================== 渲染工具 ==================== */
static void put_cursor(uint32_t row, uint32_t col)
{
    uart_write_string("\033[");
    uart_write_dec(row);
    uart_write_char(';');
    uart_write_dec(col);
    uart_write_char('H');
}

static void put_char_at(uint32_t row, uint32_t col, char ch)
{
    put_cursor(row, col);
    uart_write_char(ch);
}

static void draw_border(void)
{
    uint32_t i;

    /* 顶边框: 行 2, 列 1..COLS+2 */
    put_char_at(2U, 1U, '+');
    for (i = 2U; i <= GAME_COLS + 1U; ++i) {
        put_char_at(2U, i, '-');
    }
    put_char_at(2U, GAME_COLS + 2U, '+');

    /* 左右边框: 行 3..ROWS+2 */
    for (i = 1U; i <= GAME_ROWS; ++i) {
        put_char_at(i + 2U, 1U, '|');
        put_char_at(i + 2U, GAME_COLS + 2U, '|');
    }

    /* 底边框: 行 ROWS+3 */
    put_char_at(GAME_ROWS + 3U, 1U, '+');
    for (i = 2U; i <= GAME_COLS + 1U; ++i) {
        put_char_at(GAME_ROWS + 3U, i, '-');
    }
    put_char_at(GAME_ROWS + 3U, GAME_COLS + 2U, '+');
}

static void draw_score(void)
{
    put_cursor(1U, 1U);
    uart_write_string("SCORE: ");
    uart_write_dec((uint32_t)score);
    uart_write_string("  LIVES: ");
    uart_write_dec((uint32_t)lives);
    uart_write_string("  ");
}

static void draw_ship(void)
{
    put_char_at(GAME_ROWS + 2U, ship_x + 1U, 'A');
}

static void erase_ship_at(uint32_t col)
{
    put_char_at(GAME_ROWS + 2U, col + 1U, ' ');
}

static void draw_game_over(void)
{
    put_cursor(GAME_ROWS + 4U, 1U);
    uart_write_string("GAME OVER  SCORE: ");
    uart_write_dec((uint32_t)score);
    uart_write_string("  press q to quit");
}

static void respawn_asteroid(uint32_t i)
{
    ast_x[i] = 1U + umod(rng(), GAME_COLS);
    ast_y[i] = 1U;
}

/* ==================== 初始化 ==================== */
void game_init(void)
{
    uint32_t i;

    rng_state = 1U;
    for (i = 0U; i < MAX_AST; ++i) {
        respawn_asteroid(i);
    }
}

static void game_enter(void)
{
    uint32_t i;

    uart_write_string("\033[H\033[J");
    uart_write_string("\033[?25l");

    ship_x = GAME_COLS / 2U;
    old_ship_x = ship_x;
    bullet_x = 0U;
    bullet_y = 0U;
    lives = START_LIVES;
    score = 0;
    num_ast = 3U;
    ast_counter = 0U;
    game_quit = 0;
    game_over = 0;

    for (i = 0U; i < MAX_AST; ++i) {
        respawn_asteroid(i);
    }

    draw_border();
    draw_score();
    draw_ship();
}

static void game_exit(void)
{
    uart_write_string("\033[?25h");
    uart_write_string("\033[H\033[J");
}

/* ==================== 输入 ==================== */
static void game_read_input(void)
{
    while (uart_available() != 0) {
        char c = uart_getchar();

        /* 游戏结束后仅响应 q/Esc 退出 */
        if (game_over != 0) {
            if (c == 'q' || c == 0x1b) {
                game_quit = 1;
            }
            continue;
        }

        switch (c) {
            case 'a':
                if (ship_x > 1U) {
                    --ship_x;
                }
                break;
            case 'd':
                if (ship_x < GAME_COLS) {
                    ++ship_x;
                }
                break;
            case ' ':
                if (bullet_y == 0U) {
                    bullet_y = GAME_ROWS;
                    bullet_x = ship_x;
                }
                break;
            case 'q':
            case 0x1b:
                game_quit = 1;
                break;
            default:
                break;
        }
    }
}

/* ==================== 逻辑与渲染 ==================== */
static void game_update(void)
{
    uint32_t i;

    /* 先擦除上一帧飞船位置, 避免移动后残留残影 */
    if (old_ship_x != ship_x) {
        erase_ship_at(old_ship_x);
    }

    /* 子弹上移 */
    if (bullet_y != 0U) {
        put_char_at(bullet_y + 1U, bullet_x + 1U, ' ');
        if (bullet_y > 1U) {
            --bullet_y;
            put_char_at(bullet_y + 1U, bullet_x + 1U, '|');
        } else {
            bullet_y = 0U;
        }
    }

    /* 陨石下落(每 AST_FALL_INTERVAL 帧落一行, 与飞船/子弹帧率解耦) */
    ++ast_counter;
    if (ast_counter >= AST_FALL_INTERVAL) {
        ast_counter = 0U;

        for (i = 0U; i < num_ast; ++i) {
            uint32_t old_y = ast_y[i];

            if (old_y == 0U) {
                continue;
            }

            put_char_at(old_y + 1U, ast_x[i] + 1U, ' ');

            if (ast_y[i] >= GAME_ROWS) {
                /* 到达底行(飞船所在行): 若列一致则击中飞船 */
                if ((lives > 0) && (ast_x[i] == ship_x)) {
                    --lives;
                    draw_score();
                    if (lives <= 0) {
                        game_over = 1;
                        draw_game_over();
                    }
                }
                respawn_asteroid(i);
            } else {
                ++ast_y[i];
            }

            put_char_at(ast_y[i] + 1U, ast_x[i] + 1U, '*');
        }
    }

    /* 子弹 vs 陨石 */
    if (bullet_y != 0U) {
        for (i = 0U; i < num_ast; ++i) {
            if ((ast_x[i] == bullet_x) && (ast_y[i] == bullet_y)) {
                put_char_at(bullet_y + 1U, bullet_x + 1U, ' ');
                bullet_y = 0U;
                score += 10;
                draw_score();
                respawn_asteroid(i);
                put_char_at(ast_y[i] + 1U, ast_x[i] + 1U, '*');
            }
        }
    }

    /* 飞船最后绘制, 保证不被陨石擦除 */
    draw_ship();
    old_ship_x = ship_x;
}

/* ==================== 主循环 ==================== */
void game_task(void *arg)
{
    (void)arg;

    for (;;) {
        /* 由 shell 的 game 命令唤醒后进入; 结束后阻塞等待下次启动 */
        game_enter();

        while (game_quit == 0) {
            game_read_input();

            if (game_over != 0) {
                /* 游戏结束: 冻结画面, 等待玩家按 q/Esc 退出 */
                task_delay(GAME_PERIOD);
                continue;
            }

            game_update();
            task_delay(GAME_PERIOD);
        }

        game_exit();
        input_set_owner(INPUT_SHELL);
        task_wakeup(shell_task_id);

        task_block(WAIT_SUSPEND);
    }
}