#include "app.h"
#include "game.h"
#include "gpio.h"
#include "input.h"
#include "kernel.h"
#include "shell.h"
#include "uart.h"

static uint32_t idle_stack[256];
static uint32_t rx_stack[256];
static uint32_t shell_stack[1024];
static uint32_t led_stack[256];
static uint32_t game_stack[1024];

static void app_idle(void *arg)
{
    (void)arg;

    for (;;) {
        task_yield();
    }
}

static void app_uart_rx(void *arg)
{
    (void)arg;

    for (;;) {
        uart_poll();
        input_dispatch();
        task_delay(10U);
    }
}

static void app_led(void *arg)
{
    (void)arg;

    for (;;) {
        gpio_toggle();
        task_delay(500U);
    }
}

void app_run(void)
{
    (void)idle_stack;
    (void)rx_stack;
    (void)led_stack;

    kernel_init();
    uart_init();

    task_create(app_idle, "idle", 0, idle_stack, 256);
    task_create(app_uart_rx, "uart_rx", 0, rx_stack, 256);
    shell_task_id = task_create(shell_task, "shell", 0, shell_stack, 1024);
    task_create(app_led, "led", 0, led_stack, 256);
    game_task_id = task_create(game_task, "game", 0, game_stack, 1024);

    gpio_init();
    shell_init();
    game_init();
    input_init(shell_task_id, game_task_id);

    task_mark_suspended(game_task_id);

    task_start();

    for (;;) {
    }
}