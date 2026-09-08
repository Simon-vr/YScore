#include "shell.h"
#include "input.h"
#include "kernel.h"
#include "portmacro.h"
#include "uart.h"
#include "utils.h"
#include "gpio.h"

#define SHELL_INPUT_MAX 64U

/* ==================== 状态量 ==================== */
static char shell_line[SHELL_INPUT_MAX];
static unsigned int shell_length;
static int shell_waiting_game;

int game_task_id = -1;

/* ==================== 工具 ==================== */
static void shell_print_prompt(void)
{
    uart_write_string("RV32> ");
}

static void shell_reset_line(void)
{
    shell_length = 0U;
    shell_line[0] = '\0';
}

static void shell_put_crlf(void)
{
    uart_write_string("\r\n");
}

/* ==================== 初始化 / 开机横幅 ==================== */
void shell_init(void)
{
    shell_reset_line();
    shell_waiting_game = 0;
    uart_write_string("system stack pointer initiated... \r\n");
    uart_write_string("mtvec address initiated... \r\n");
    uart_write_string("time interrupt initiated... \r\n");
    uart_write_string("UART initiated... \r\n");
    uart_write_string("GPIO initiated... \r\n");
    uart_write_string("system task queue initiated... \r\n");
    uart_write_string("task stacks initiated... \r\n");
    uart_write_string("tasks created... \r\n");
    uart_write_string("finished... \r\n");
    uart_write_string("\r\n");
    uart_write_string("\r\n");
    uart_write_string("================================\r\n");
    uart_write_string("      Welcome to YScore\r\n");
    uart_write_string("================================\r\n");
    uart_write_string("type 'help' for commands\r\n");

    shell_print_prompt();
}

/* ==================== 命令实现 ==================== */

static void shell_handle_help(void)
{
    uart_write_string("commands:\r\n");
    uart_write_string("  help        - show this message\r\n");
    uart_write_string("  banner      - print boot banner again\r\n");
    uart_write_string("  info        - SoC identity\r\n");
    uart_write_string("  task        - task list (state/wait/stack)\r\n");
    uart_write_string("  cpu         - CSR status\r\n");
    uart_write_string("  timer       - CLINT timer status\r\n");
    uart_write_string("  mem <addr> [len] - memory dump\r\n");
    uart_write_string("  irq         - interrupt status\r\n");
    uart_write_string("  gpio        - GPIO status\r\n");
    uart_write_string("  game        - run Asteroids\r\n");
}


static void shell_cmd_task(void)
{
    uint32_t i;
    uint32_t ulCount = task_count();

    uart_write_string("Name        State       Wait        Stack\r\n");

    for (i = 0U; i < ulCount; ++i) {
        int iId = (int)i;

        uart_write_string(task_name(iId));
        uart_write_string("        ");
        uart_write_string(task_state_str(iId));
        uart_write_string("       ");
        uart_write_string(task_wait_str(iId));
        uart_write_string("          ");
        uart_write_dec(task_stack_usage(iId));
        uart_write_string("/");
        uart_write_dec(task_stack_size(iId));
        shell_put_crlf();
    }

    shell_put_crlf();
    uart_write_string("Tick Count: ");
    uart_write_dec(kernel_tick_count);
    shell_put_crlf();
    uart_write_string("Context Switch: ");
    uart_write_dec(context_switch_count);
    shell_put_crlf();
}

static void shell_cmd_info(void)
{
    shell_put_crlf();
    uart_write_string("============================================\r\n");
    uart_write_string("CPU:\r\n");
    uart_write_string("  ISA                    RV32I + Zicsr\r\n");
    uart_write_string("  Privilege              Machine Mode\r\n");
    uart_write_string("  Clock                  50 MHz\r\n");
    shell_put_crlf();
    uart_write_string("Memory:\r\n");
    uart_write_string("  Instruction Memory     18 KB\r\n");
    uart_write_string("  Data Memory            24 KB\r\n");
    shell_put_crlf();
    uart_write_string("Bus:\r\n");
    uart_write_string("  AXI4-Lite\r\n");
    shell_put_crlf();
    uart_write_string("Peripheral:\r\n");
    uart_write_string("  MEM(data memory)       0x8000_0000\r\n");
    uart_write_string("  CLINT(timer)           0x0200_0000\r\n");
    uart_write_string("  UART (axil_uart)       0x1000_0000\r\n");
    uart_write_string("  GPIO (led output)      0x2000_0000\r\n");
    shell_put_crlf();
    uart_write_string("RTOS:\r\n");
    uart_write_string("  Tick                   1000 Hz\r\n");
    uart_write_string("  UART Polling           100 Hz\r\n");
    uart_write_string("  LED                    2 Hz \r\n");
    uart_write_string("============================================\r\n");
}

static void shell_cmd_cpu(void)
{
    uint32_t mstatus, mtvec, mepc, mcause, mie, mip;

    __asm__ volatile("csrr %0, mstatus" : "=r"(mstatus));
    __asm__ volatile("csrr %0, mtvec"   : "=r"(mtvec));
    __asm__ volatile("csrr %0, mepc"    : "=r"(mepc));
    __asm__ volatile("csrr %0, mcause"  : "=r"(mcause));
    __asm__ volatile("csrr %0, mie"     : "=r"(mie));
    __asm__ volatile("csrr %0, mip"     : "=r"(mip));

    uart_write_string("PC      : "); uart_write_hex(mepc); shell_put_crlf();
    uart_write_string("mstatus : "); uart_write_hex(mstatus); shell_put_crlf();
    uart_write_string("mtvec   : "); uart_write_hex(mtvec); shell_put_crlf();
    uart_write_string("mepc    : "); uart_write_hex(mepc); shell_put_crlf();
    uart_write_string("mcause  : "); uart_write_hex(mcause); shell_put_crlf();
    shell_put_crlf();
    uart_write_string("mie:\r\n");
    uart_write_string("  MTIE  ");
    uart_write_string((mie & (1U << 7)) != 0U ? "enabled\r\n" : "disabled\r\n");
    shell_put_crlf();
    uart_write_string("mip:\r\n");
    uart_write_string("  MTIP  ");
    uart_write_string((mip & (1U << 7)) != 0U ? "pending\r\n" : "idle\r\n");
}

static void shell_cmd_timer(void)
{
    volatile uint32_t *pulTimeLowReg = (volatile uint32_t *)pulTimeLow;
    volatile uint32_t *pulTimeHighReg = (volatile uint32_t *)pulTimeHigh;
    volatile uint64_t *pullMtimecmpReg = (volatile uint64_t *)pullMachineTimerCompareRegister;
    uint64_t ullMtime, ullMtimecmp;
    uint32_t ulTimeLow, ulTimeHigh;
    uint32_t mip;

    do {
        ulTimeHigh = *pulTimeHighReg;
        ulTimeLow = *pulTimeLowReg;
    } while (ulTimeHigh != *pulTimeHighReg);

    ullMtime = (uint64_t)ulTimeHigh;
    ullMtime <<= 32ULL;
    ullMtime |= (uint64_t)ulTimeLow;

    ullMtimecmp = *pullMtimecmpReg;

    __asm__ volatile("csrr %0, mip" : "=r"(mip));

    uart_write_string("mtime:    "); uart_write_dec((uint32_t)(ullMtime & 0xFFFFFFFFU)); shell_put_crlf();
    uart_write_string("mtimecmp: "); uart_write_dec((uint32_t)(ullMtimecmp & 0xFFFFFFFFU)); shell_put_crlf();
    shell_put_crlf();
    uart_write_string("Interrupt:\r\n");
    uart_write_string("  MTIP ");
    uart_write_string((mip & (1U << 7)) != 0U ? "ACTIVE\r\n" : "IDLE\r\n");
    shell_put_crlf();
    uart_write_string("Tick: ");
    uart_write_dec(kernel_tick_count);
    shell_put_crlf();
    uart_write_string("Scheduler: ");
    uart_write_string(pxCurrentTCB != 0 ? "RUNNING\r\n" : "STOPPED\r\n");
}

static void shell_cmd_mem(const char *args)
{
    uint32_t addr;
    uint32_t i, length;
    volatile unsigned char *ptr;
    const char *p = args;

    p = utils_skip_spaces(p);
    if (*p == '\0') {
        uart_write_string("usage: mem <hex_addr> [length]\r\n");
        return;
    }

    addr = utils_parse_hex(p) + 0x10000000;
    length = 16U;

    while (*p != '\0' && *p != ' ' && *p != '\t') {
        ++p;
    }
    p = utils_skip_spaces(p);
    if (*p != '\0') {
        length = utils_parse_hex(p);
        if (length == 0U || length > 256U) {
            length = 16U;
        }
    }

    ptr = (volatile unsigned char *)addr;

    for (i = 0U; i < length; ++i) {
        if ((i % 16U) == 0U) {
            if (i != 0U) {
                shell_put_crlf();
            }
            uart_write_hex(addr + i);
            uart_write_string(": ");
        } else if ((i % 8U) == 0U) {
            uart_write_string(" ");
        }

        uart_write_char(' ');
        uart_write_hex8(ptr[i]);
    }

    shell_put_crlf();
}

static void shell_cmd_irq(void)
{
    uint32_t mie, mip;

    __asm__ volatile("csrr %0, mie" : "=r"(mie));
    __asm__ volatile("csrr %0, mip" : "=r"(mip));

    uart_write_string("Interrupt Status:\r\n");
    shell_put_crlf();
    uart_write_string("Timer:\r\n");
    uart_write_string("  ");
    uart_write_string((mie & (1U << 7)) != 0U ? "enabled\r\n" : "disabled\r\n");
    uart_write_string("  count: ");
    uart_write_dec(kernel_tick_count);
    shell_put_crlf();
    shell_put_crlf();
    uart_write_string("External:\r\n");
    uart_write_string("  ");
    uart_write_string((mie & (1U << 11)) != 0U ? "enabled\r\n" : "disabled\r\n");
    uart_write_string("  ");
    uart_write_string((mip & (1U << 11)) != 0U ? "pending\r\n" : "idle\r\n");
}

static void shell_cmd_gpio(void)
{
    uart_write_string("GPIO Output: 0x");
    uart_write_hex8((uint8_t)(gpio_get_output() & 0xFFU));
    shell_put_crlf();
    /* 低电平点亮: bit=0 表示 LED 亮 */
    uart_write_string("LED: ");
    uart_write_string((gpio_get_output() & 0x01U) != 0U ? "OFF\r\n" : "ON\r\n");
}


static void shell_cmd_game(void)
{
    uart_write_string("Starting Asteroids... (q to quit)\r\n");
    input_set_owner(INPUT_GAME);
    task_wakeup(game_task_id);
    shell_waiting_game = 1;
}

/* ==================== 命令解析 ==================== */
static void shell_parse_line(const char *line)
{
    const char *command = utils_skip_spaces(line);

    if (*command == '\0') {
        return;
    }

    if (utils_streq(command, "help")) {
        shell_handle_help();
        return;
    }
    if (utils_streq(command, "banner")) {
        uart_write_string("██╗   ██╗███████╗ ██████╗ ██████╗ ██████╗ ███████╗\r\n");
        uart_write_string("╚██╗ ██╔╝██╔════╝██╔════╝██╔═══██╗██╔══██╗██╔════╝\r\n");
        uart_write_string(" ╚████╔╝ ███████╗██║     ██║   ██║██████╔╝█████╗  \r\n");
        uart_write_string("  ╚██╔╝  ╚════██║██║     ██║   ██║██╔══██╗██╔══╝  \r\n");
        uart_write_string("   ██║   ███████║╚██████╗╚██████╔╝██║  ██║███████╗\r\n");
        uart_write_string("   ╚═╝   ╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝\r\n");
        uart_write_string("                                                  \r\n");
        return;
    }
    if (utils_streq(command, "task")) {
        shell_cmd_task();
        return;
    }
    if (utils_streq(command, "info")) {
        shell_cmd_info();
        return;
    }
    if (utils_streq(command, "cpu")) {
        shell_cmd_cpu();
        return;
    }
    if (utils_streq(command, "timer")) {
        shell_cmd_timer();
        return;
    }
    if (utils_streq(command, "irq")) {
        shell_cmd_irq();
        return;
    }
    if (utils_streq(command, "gpio")) {
        shell_cmd_gpio();
        return;
    }
    if (utils_streq(command, "game")) {
        shell_cmd_game();
        return;
    }

    
    if (command[0] == 'm' && command[1] == 'e' && command[2] == 'm') {
        shell_cmd_mem(command + 3);
        return;
    }

    uart_write_string("unknown command: ");
    uart_write_string(command);
    shell_put_crlf();
}

/* ==================== 输入处理 ==================== */
static void shell_handle_char(char c)
{
    /* 换行提交 */
    if (c == '\r' || c == '\n') {
        shell_put_crlf();

        if (shell_length == 0U) {
            shell_print_prompt();
            return;
        }

        shell_parse_line(shell_line);
        shell_reset_line();
        shell_print_prompt();
        return;
    }
    /* 删除字符 */
    if (c == '\b' || c == 0x7f) {
        if (shell_length != 0U) {
            --shell_length;
            shell_line[shell_length] = '\0';
            uart_write_char('\b');
            uart_write_char(' ');
            uart_write_char('\b');
        }
        return;
    }
    /* 超过限制 */
    if (shell_length >= (SHELL_INPUT_MAX - 1U)) {
        uart_write_string("\r\nline too long\r\n");
        shell_reset_line();
        shell_print_prompt();
        return;
    }

    shell_line[shell_length++] = c;
    shell_line[shell_length] = '\0';
    uart_write_char(c);
}

/*
 * Shell 本身是 RTOS 任务: 阻塞在 WAIT_UART 上, 由 uart_rx 任务唤醒。
 * 被唤醒后排空 ring buffer 拼行执行。
 */
void shell_task(void *arg)
{
    (void)arg;

    for (;;) {
        task_block(WAIT_UART);

        while (uart_available() != 0) {
            shell_handle_char(uart_getchar());
        }

        if (shell_waiting_game != 0) {
            shell_waiting_game = 0;
            task_block(WAIT_SUSPEND);
            shell_print_prompt();
        }
    }
}