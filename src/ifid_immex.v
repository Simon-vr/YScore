`timescale 1ns / 1ps
`include "rvdef.vh"
module ifid_immex(
input[1:0] sign,
input[11:0] imm,
input[11:0] offset,
input[11:0] branch_offset,
input[19:0] jump_offset,
input[19:0] upper_imm,
output reg[31:0] eimm,
output wire[31:0] ebranch_offset,
output wire[31:0] ejump_offset,
output wire[31:0] eupper_imm
);
always @(*) begin  //alu source
    case(sign)
        `OPT_IE_IU:     eimm={{20{1'b0}}, imm};       //I-type unsigned
        `OPT_IE_IS:     eimm={{20{imm[11]}}, imm};     //I-type signed
        `OPT_IE_OFFSET: eimm={{20{offset[11]}}, offset}; //S-type
        default:        eimm=32'h0;
    endcase
end
//永远输出, 判断交给next模块
assign ebranch_offset = {{19{branch_offset[11]}}, branch_offset, 1'b0};//for branch offset, 12
assign ejump_offset = {{11{jump_offset[19]}}, jump_offset, 1'b0};//for J-type/jump offset, 20
//永远输出, 判断交给write back模块
assign eupper_imm = {upper_imm, 12'b0};//for U-type/upper imm, 20
endmodule
