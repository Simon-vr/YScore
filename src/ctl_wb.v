`timescale 1ns / 1ps
`include "rvdef.vh"

module ctl_wb (
    input[31:0] ins,
    output reg[3:0] opt_wb,
    output reg reg_write,
    output reg csr_write
);
    //声明
    wire  [6:0]  opcode;
    wire  [2:0]  funct3;
    // 提取指令字段
    assign opcode = ins[6:0];
    assign funct3 = ins[14:12];

    always @(*) begin
        // 默认值
        reg_write = 0;
        csr_write = 0;
        opt_wb    = `OPT_WB_ALU;

        case (opcode)
            `OP_RTYPE: begin
                reg_write = 1;
            end
            `OP_ITYPE: begin
                reg_write = 1;
            end
            `OP_LOAD: begin
                reg_write = 1;
                case (funct3)
                    `FUNC3_LB:  opt_wb = `OPT_WB_LB;
                    `FUNC3_LBU: opt_wb = `OPT_WB_LBU;
                    `FUNC3_LH:  opt_wb = `OPT_WB_LH;
                    `FUNC3_LHU: opt_wb = `OPT_WB_LHU;
                    `FUNC3_LW:  opt_wb = `OPT_WB_LW;
                    default: begin
                        opt_wb    = `OPT_WB_ALU;
                        reg_write = 0;
                    end
                endcase
            end
            `OP_STORE: begin
                reg_write = 0;
            end
            `OP_JAL: begin
                reg_write = 1;
                opt_wb    = `OPT_WB_PC4;
            end
            `OP_JALR: begin
                reg_write = 1;
                opt_wb    = `OPT_WB_PC4;
            end
            `OP_LUI: begin
                reg_write = 1;
                opt_wb    = `OPT_WB_LUI;
            end
            `OP_AUIPC: begin
                reg_write = 1;
                opt_wb    = `OPT_WB_AUIPC;
            end
            `OP_CSR: begin
                reg_write = 1;
                csr_write = 1;
                opt_wb    = `OPT_WB_CSR;
            end
            default: begin
                reg_write = 0;
                csr_write = 0;
            end
        endcase
    end

endmodule