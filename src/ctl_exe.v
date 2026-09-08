`timescale 1ns / 1ps
`include "rvdef.vh"

module ctl_exe (
    input[31:0] ins,
    output reg[3:0] alu_func,
    output reg[3:0] next_func
);
    //声明
    wire  [6:0]  opcode;
    wire  [2:0]  funct3;
    wire  [6:0]  funct7;
    wire  [9:0]  func;
    // 提取指令字段
    assign opcode = ins[6:0];
    assign funct3 = ins[14:12];
    assign funct7 = ins[31:25];
    assign func   = {funct7, funct3}; // for R-type

    always @(*) begin
        // 默认值
        alu_func  = `ALU_ADD;
        next_func = `NEXT_SEQ;

        case (opcode)
            `OP_RTYPE: begin
                case (func)
                    `FUNC_ADD:  alu_func = `ALU_ADD;
                    `FUNC_SUB:  alu_func = `ALU_SUB;
                    `FUNC_AND:  alu_func = `ALU_AND;
                    `FUNC_OR:   alu_func = `ALU_OR;
                    `FUNC_XOR:  alu_func = `ALU_XOR;
                    `FUNC_SLL:  alu_func = `ALU_SLL;
                    `FUNC_SRL:  alu_func = `ALU_SRL;
                    `FUNC_SRA:  alu_func = `ALU_SRA;
                    `FUNC_SLT:  alu_func = `ALU_SLT;
                    `FUNC_SLTU: alu_func = `ALU_SLTU;
                    default:    alu_func = `ALU_ADD;
                endcase
            end
            `OP_ITYPE: begin
                case (funct3)
                    `FUNC3_ADDI:   alu_func = `ALU_ADD;
                    `FUNC3_ANDI:   alu_func = `ALU_AND;
                    `FUNC3_ORI:    alu_func = `ALU_OR;
                    `FUNC3_XORI:   alu_func = `ALU_XOR;
                    `FUNC3_SLLI:   alu_func = `ALU_SLL;
                    `FUNC3_SRAI: begin
                        if (funct7 == `FUNC7_SRAI)
                            alu_func = `ALU_SRA;
                        else if (funct7 == `FUNC7_SRLI)
                            alu_func = `ALU_SRL;
                        else
                            alu_func = `ALU_SRA;
                    end
                    `FUNC3_SLTI:   alu_func = `ALU_SLT;
                    `FUNC3_SLTIU:  alu_func = `ALU_SLTU;
                    default:       alu_func = `ALU_ADD;
                endcase
            end
            `OP_LOAD: begin
                alu_func = `ALU_ADD;
            end
            `OP_STORE: begin
                alu_func = `ALU_ADD;
            end
            `OP_BRANCH: begin
                alu_func = `ALU_SUB;
                case (funct3)
                    `FUNC3_BEQ:  next_func = `NEXT_BEQ;
                    `FUNC3_BNE:  next_func = `NEXT_BNE;
                    `FUNC3_BLT:  next_func = `NEXT_BLT;
                    `FUNC3_BGE:  next_func = `NEXT_BGE;
                    `FUNC3_BLTU: next_func = `NEXT_BLTU;
                    `FUNC3_BGEU: next_func = `NEXT_BGEU;
                    default:     next_func = `NEXT_SEQ;
                endcase
            end
            `OP_JAL: begin
                alu_func  = `ALU_ADD;
                next_func = `NEXT_JAL;
            end
            `OP_JALR: begin
                alu_func  = `ALU_ADD;
                next_func = `NEXT_JALR;
            end
            `OP_LUI: begin
                alu_func = `ALU_ADD;
            end
            `OP_AUIPC: begin
                alu_func = `ALU_ADD;
            end
            `OP_CSR: begin
                case(funct3)
                    `FUNC3_CSRRW: alu_func = `ALU_SRC1;
                    `FUNC3_CSRRS: alu_func = `ALU_OR;
                    `FUNC3_CSRRC: alu_func = `ALU_ANDN;
                    `FUNC3_CSRRWI: alu_func = `ALU_SRC1;
                    `FUNC3_CSRRSI: alu_func = `ALU_OR;
                    `FUNC3_CSRRCI: alu_func = `ALU_ANDN;
                    default: alu_func = `ALU_SRC1;
                endcase
            end
            default: begin
                alu_func = `ALU_ADD;
            end
        endcase
    end

endmodule
