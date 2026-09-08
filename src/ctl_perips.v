`timescale 1ns / 1ps
`include "rvdef.vh"

module ctl_perips (
    input[31:0] ins,
    output reg[1:0] mem_write,
    output reg       peripsen     // 1: 需要外设/访存, 0: 跳过PERIPS阶段
);
    //声明
    wire  [6:0]  opcode;
    wire  [2:0]  funct3;
    // 提取指令字段
    assign opcode = ins[6:0];
    assign funct3 = ins[14:12];

    always @(*) begin
        // 默认值
        mem_write = `MEM_W_NONE;
        peripsen  = 1'b0;            // 默认跳过PERIPS

        case (opcode)
            `OP_STORE: begin
                peripsen = 1'b1;
                case (funct3)
                    `FUNC3_SB: mem_write = `MEM_W_B;
                    `FUNC3_SH: mem_write = `MEM_W_H;
                    `FUNC3_SW: mem_write = `MEM_W_W;
                    default:   mem_write = `MEM_W_NONE;
                endcase
            end
            `OP_LOAD: begin
                peripsen = 1'b1;
            end
            default: begin
                mem_write = `MEM_W_NONE;
            end
        endcase
    end

endmodule