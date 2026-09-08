.section .text
.globl _start

_start:

    li x5,0

loop:

    addi x5,x5,1
    addi x6,x0,0

    jal x0,loop