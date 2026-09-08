`timescale 1ns / 1ps
`include "rvdef.vh"
module exe_alu(
input[3:0] func,     
input[31:0] data1,   
input[31:0] data2,   
output reg zero,     
output reg sign,
output reg carry,  //carry or borrow
output reg overflow,  //overflow      
output reg[31:0] alures 
);
reg[32:0] res;
reg[31:0] low_res;
always @* begin
    case(func)
        `ALU_ADD:  res = {1'b0, data1} + {1'b0, data2};              // 加法 ADD/ADDI (33bit: res[32]=进位)
        `ALU_SUB:  res = {1'b0, data1} - {1'b0, data2};              // 减法 SUB      (33bit: res[32]=借位)
        `ALU_SLL:  res = {1'b0, data1 << data2[4:0]};                // 逻辑左移 SLL/SLLI
        `ALU_OR:   res = {1'b0, data1 | data2};                      // 按位或 OR/ORI
        `ALU_AND:  res = {1'b0, data1 & data2};                      // 按位与 AND/ANDI
        `ALU_SLTU: res = {1'b0, (data1 < data2) ? 32'd1 : 32'd0};    // 无符号比较 SLTU/SLTIU
        `ALU_SLT:  res = {1'b0, ($signed(data1) < $signed(data2)) ? 32'd1 : 32'd0}; // 有符号比较 SLT/SLTI
        `ALU_XOR:  res = {1'b0, data1 ^ data2};                      // 按位异或 XOR/XORI
        `ALU_SRL:  res = {1'b0, data1 >> data2[4:0]};                // 逻辑右移 SRL/SRLI
        `ALU_SRA:  res = {1'b0, $signed(data1) >>> data2[4:0]};      // 算术右移 SRA/SRAI
        `ALU_SRC1: res = {1'b0, data1};                               // 直接输出 data1
        `ALU_SRC2: res = {1'b0, data2};                               // 直接输出 data2
        `ALU_ANDN: res = {1'b0, (~data1) & data2};                    // ~data1 & data2 (ANDN)
        default:   res = 33'b0;                                      // 默认输出0
    endcase
    alures = res[31:0];
    // 标志位生成
    zero = (res == 32'b0) ? 1'b1 : 1'b0;    // 结果为0时置1
    sign = res[31];       // 取结果最高位为符号位                 
    carry = (func == `ALU_SUB) ? (~res[32]) : res[32];//是否发生借位
    
    low_res = (func == `ALU_SUB) ? (data1[30:0] + (~data2[30:0]) + 1) : (data1[30:0] + data2[30:0]);
    overflow = low_res[31] ^ res[32];
end

endmodule