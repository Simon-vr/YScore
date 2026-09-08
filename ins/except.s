.section .text
.globl _start

_start:

    li x31,0
    li s0,0


    # =================================================
    # mtvec
    # =================================================

    la t0,trap_handler

    csrw mtvec,t0


    # =================================================
    # ECALL
    # =================================================

    ecall

after_ecall:

    li t0,1

    bne s0,t0,fail


    # =================================================
    # EBREAK
    # =================================================

    ebreak

after_ebreak:

    li t0,2

    bne s0,t0,fail


    # =================================================
    # PASS
    # =================================================

    li x31,1

pass_loop:
    jal x0,pass_loop


fail:

    li x31,0

fail_loop:
    jal x0,fail_loop



# =====================================================
# Trap handler
# =====================================================

trap_handler:

    csrr t0,mcause

    # ECALL from M-mode = 11
    li t1,11

    beq t0,t1,handle_ecall


    # EBREAK = 3
    li t1,3

    beq t0,t1,handle_ebreak


    j fail


handle_ecall:

    addi s0,s0,1

    csrr t2,mepc
    addi t2,t2,4
    csrw mepc,t2

    mret


handle_ebreak:

    addi s0,s0,1

    csrr t2,mepc
    addi t2,t2,4
    csrw mepc,t2

    mret