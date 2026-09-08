`timescale 1ns/1ps
`include "rvdef.vh"
module exe_next (
    input [31:0] cur_pc,
    input [3:0] func,
    input sign,
    input zero,
    input carry,
    input overflow,
    input [31:0] branch_offset,
    input [31:0] jump_offset,
    input [31:0] alu_res,
    output reg [31:0] next_pc
);
always @* begin
    case (func)
        `NEXT_SEQ: next_pc = cur_pc + 4; // 顺序执行
        `NEXT_BEQ: begin  //BEQ
            if (zero == 1'b1)
                next_pc = cur_pc + branch_offset;
            else
                next_pc = cur_pc + 4;
        end
        `NEXT_BNE: begin  //BNE
            if (zero == 1'b0)
                next_pc = cur_pc + branch_offset;
            else
                next_pc = cur_pc + 4;
        end
        `NEXT_BLT: begin  //BLT
            if (sign^overflow == 1'b1)
                next_pc = cur_pc + branch_offset;
            else
                next_pc = cur_pc + 4;
        end
        `NEXT_BLTU: begin  
            if (carry == 1'b0)
                next_pc = cur_pc + branch_offset;
            else
                next_pc = cur_pc + 4;
        end
        `NEXT_BGE: begin
            if (sign^overflow == 1'b0)
                next_pc = cur_pc + branch_offset;
            else
                next_pc = cur_pc + 4;
        end
        `NEXT_BGEU: begin
            if (carry == 1'b1)
                next_pc = cur_pc + branch_offset;
            else
                next_pc = cur_pc + 4;
        end
        `NEXT_JAL: next_pc = cur_pc + jump_offset; //JAL
        `NEXT_JALR: next_pc = {alu_res[31:1], 1'b0}; //JALR
        default: next_pc = cur_pc + 4; 

    endcase
end
endmodule