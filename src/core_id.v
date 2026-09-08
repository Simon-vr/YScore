`timescale 1ns / 1ps
`include "rvdef.vh"
module core_id (
    input[31:0] ins,       // 来自IF阶段中间寄存器的指令
    input[1:0] opt_ie,     // 来自 ifid ctl

    output wire[4:0] rs1,
    output wire[4:0] rs2,
    output wire[4:0] rd,
    output wire[11:0] csraddr,
    output reg[31:0] eimm,
    output wire[31:0] ebranch_offset,
    output wire[31:0] ejump_offset,
    output wire[31:0] eupper_imm
);
    // 字段提取
    assign rd = ins[11:7];
    assign rs1 = ins[19:15];
    assign rs2 = ins[24:20];
    assign csraddr = ins[31:20];//for CSR instructions, 12
    wire [11:0] imm = ins[31:20];//for I-type/load offset, 12
    wire [11:0] offset = {ins[31:25], ins[11:7]};//for S-type/branch offset, 12
    wire [11:0] branch_offset = {ins[31], ins[7], ins[30:25], ins[11:8]};//for branch offset, 12
    wire [19:0] jump_offset = {ins[31], ins[19:12], ins[20], ins[30:21]};//for J-type/jump offset, 20
    wire [19:0] upper_imm = ins[31:12];//for U-type/upper immediate, 20

    // 立即数扩展
    always @(*) begin  //alu source
        case(opt_ie)
            `OPT_IE_IU:     eimm = {{20{1'b0}}, imm};       //I-type unsigned
            `OPT_IE_IS:     eimm = {{20{imm[11]}}, imm};     //I-type signed
            `OPT_IE_OFFSET: eimm = {{20{offset[11]}}, offset}; //S-type
            default:        eimm = 32'h0;
        endcase
    end
    //永远输出, 判断交给next模块
    assign ebranch_offset = {{19{branch_offset[11]}}, branch_offset, 1'b0};//for branch offset, 12
    assign ejump_offset = {{11{jump_offset[19]}}, jump_offset, 1'b0};//for J-type/jump offset, 20
    //永远输出, 判断交给write back模块
    assign eupper_imm = {upper_imm, 12'b0};//for U-type/upper imm, 20

endmodule