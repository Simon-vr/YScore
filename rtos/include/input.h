#ifndef INPUT_H
#define INPUT_H

typedef enum {
    INPUT_SHELL = 0,
    INPUT_GAME = 1
} eInputOwner;

void input_init(int iShellId, int iGameId);
void input_set_owner(eInputOwner owner);
eInputOwner input_get_owner(void);

/* 由 uart_rx 任务调用: 有数据且 owner 阻塞在 UART 时唤醒 owner */
void input_dispatch(void);

#endif