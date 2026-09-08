`timescale 1ns / 1ps
module core_exe (
    input[3:0] alufunc,
    input[31:0] data1,
    input[31:0] data2,
    input[31:0] cur_pc,
    input[3:0] next_func,
    input[31:0] branch_offset,
    input[31:0] jump_offset,

    output[31:0] res,
    output[31:0] next_pc
);
    //ALU运算
    wire zero;
    wire sign;
    wire carry;
    wire overflow;

    exe_alu u_exe_alu(
        .func(alufunc),
        .data1(data1),
        .data2(data2),
        .zero(zero),
        .sign(sign),
        .carry(carry),
        .overflow(overflow),
        .alures(res)
    );
    //下一PC计算
    exe_next u_exe_next(
        .cur_pc(cur_pc),
        .func(next_func),
        .sign(sign),
        .zero(zero),
        .carry(carry),
        .overflow(overflow),
        .branch_offset(branch_offset),
        .jump_offset(jump_offset),
        .alu_res(res),
        .next_pc(next_pc)
    );

endmodule