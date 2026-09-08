.section .text
.globl _start

_start:

    li x31,0


    # =================================================
    # BEQ
    # =================================================

    li x5,10
    li x6,10

    beq x5,x6,beq_ok
    beq x0,x0,fail

beq_ok:


    # =================================================
    # BNE
    # =================================================

    li x5,10
    li x6,20

    bne x5,x6,bne_ok
    beq x0,x0,fail

bne_ok:


    # =================================================
    # BLT signed
    # =================================================

    li x5,-1
    li x6,1

    blt x5,x6,blt_ok
    beq x0,x0,fail

blt_ok:


    # =================================================
    # BGE signed
    # =================================================

    li x5,5
    li x6,3

    bge x5,x6,bge_ok
    beq x0,x0,fail

bge_ok:


    # =================================================
    # BLTU unsigned
    # =================================================

    li x5,1
    li x6,2

    bltu x5,x6,bltu_ok
    beq x0,x0,fail

bltu_ok:


    # =================================================
    # BGEU unsigned
    # =================================================

    li x5,0xffffffff
    li x6,1

    bgeu x5,x6,bgeu_ok
    beq x0,x0,fail

bgeu_ok:


pass:
    li x31,1

pass_loop:
    beq x31,x31,pass_loop


fail:
    li x31,0

fail_loop:
    beq x31,x31,fail_loop