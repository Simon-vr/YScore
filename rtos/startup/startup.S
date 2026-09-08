
.global _start

.section .text.start
_start: 
    # allocate runtime pointer
    la sp, _stack_top
    la gp, __global_pointer$

    # 1: already loaded .data 

    2: # clean .bss or not
    la a0, _bss_start
    la a1, _bss_end
    bgeu a0, a1, 4f # don't need to clean

    3: # clean .bss
    sw zero, 0(a0)
    addi a0, a0, 4
    bltu a0, a1, 3b

    4: 
    # set trap_handler
    la t0, trap_handler
    csrw mtvec, t0

    call main
    # return
    li a0, 0
    li a7, 93  #syscall exit
    ecall