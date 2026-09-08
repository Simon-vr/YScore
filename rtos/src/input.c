#include "input.h"
#include "kernel.h"
#include "uart.h"

static int owner_ids[2];
static eInputOwner current_owner = INPUT_SHELL;

void input_init(int iShellId, int iGameId)
{
    owner_ids[INPUT_SHELL] = iShellId;
    owner_ids[INPUT_GAME] = iGameId;
    current_owner = INPUT_SHELL;
}

void input_set_owner(eInputOwner owner)
{
    current_owner = owner;
}

eInputOwner input_get_owner(void)
{
    return current_owner;
}

void input_dispatch(void)
{
    if (uart_available() != 0) {
        task_wakeup(owner_ids[current_owner]);
    }
}