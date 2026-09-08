`timescale 1ns / 1ps
`include "rvdef.vh"

module ctl_ifid (
    input[31:0] ins,
    output reg[1:0] opt_ie,    // 立即数扩展选择（00: I无符号, 01: I有符号, 10: S/Branch偏移）
    output reg[1:0] opt_alusrc2, // ALU第二操作数选择（00: 寄存器数据, 01: 立即数, 10: rs2地址）
    output reg      opt_alusrc1,  // ALU第一操作数选择（0: regdata, 1: rs1零扩展）
    output reg      is_excp,
    output reg      is_mret,
    output reg[31:0]      excp_cause
);
    //声明
    wire  [6:0]  opcode;
    wire  [4:0]  rd;
    wire  [2:0]  funct3;
    wire  [4:0]  rs1;
    wire  [4:0]  rs2;
    wire  [11:0] imm;
    wire  [6:0]  funct7;
    wire  [9:0]  func; 
    // 提取指令字段
    assign opcode = ins[6:0];
    assign rd = ins[11:7];
    assign funct3 = ins[14:12];
    assign rs1 = ins[19:15];
    assign rs2 = ins[24:20];
    assign imm = ins[31:20];
    assign funct7 = ins[31:25];
    assign func = {funct7, funct3}; // for R-type

    always @(*) begin
        opt_ie = `OPT_IE_IU;
        opt_alusrc2 = `OPT_ALUSRC_REG;
        opt_alusrc1 = `OPT_ALUSRC1_REGDATA;
        is_excp = 1'b0;
        is_mret = 1'b0;
        excp_cause = 32'b0;
        case (opcode)
            `OP_ITYPE: begin
                case (funct3)
                    `FUNC3_ADDI: begin
                        opt_ie = `OPT_IE_IS;
                        opt_alusrc2 = `OPT_ALUSRC_IMM;
                    end
                    `FUNC3_ANDI: begin
                        opt_ie = `OPT_IE_IS;
                        opt_alusrc2 = `OPT_ALUSRC_IMM;
                    end
                    `FUNC3_ORI: begin
                        opt_ie = `OPT_IE_IS;
                        opt_alusrc2 = `OPT_ALUSRC_IMM;
                    end
                    `FUNC3_XORI: begin
                        opt_ie = `OPT_IE_IS;
                        opt_alusrc2 = `OPT_ALUSRC_IMM;
                    end
                    `FUNC3_SLLI: begin
                        opt_alusrc2 = `OPT_ALUSRC_IMM;
                    end
                    `FUNC3_SRAI: begin
                        opt_alusrc2 = `OPT_ALUSRC_IMM;
                    end
                    `FUNC3_SLTI: begin
                        opt_ie = `OPT_IE_IS;
                        opt_alusrc2 = `OPT_ALUSRC_IMM;
                    end
                    `FUNC3_SLTIU: begin
                        opt_alusrc2 = `OPT_ALUSRC_IMM;
                    end
                    default: begin
                        opt_alusrc2 = `OPT_ALUSRC_IMM;
                    end
                endcase
            end
            `OP_LOAD: begin
                opt_ie = `OPT_IE_IS;
                opt_alusrc2 = `OPT_ALUSRC_IMM;
            end
            `OP_STORE: begin
                opt_ie = `OPT_IE_OFFSET;
                opt_alusrc2 = `OPT_ALUSRC_IMM;
            end
            `OP_BRANCH: begin
                opt_alusrc2 = `OPT_ALUSRC_REG;
            end
            `OP_JAL: begin
                opt_ie = `OPT_IE_OFFSET;
                opt_alusrc2 = `OPT_ALUSRC_IMM;
            end
            `OP_JALR: begin
                opt_ie = `OPT_IE_IS;
                opt_alusrc2 = `OPT_ALUSRC_IMM;
            end
            `OP_LUI: begin
                opt_ie = `OPT_IE_IU;
                opt_alusrc2 = `OPT_ALUSRC_IMM;
            end
            `OP_AUIPC: begin
                opt_ie = `OPT_IE_IU;
                opt_alusrc2 = `OPT_ALUSRC_IMM;
            end
            `OP_CSR: begin
                opt_alusrc2 = `OPT_ALUSRC_CSR;
                case (funct3) 
                    `FUNC3_EXCP: begin
                        case (imm)
                            `F12_ECALL: begin
                                is_excp = 1'b1;
                                excp_cause = `EXCP_CAUSE_ECALL;
                            end
                            `F12_EBREAK: begin
                                is_excp = 1'b1;
                                excp_cause = `EXCP_CAUSE_EBREAK;
                            end
                            `F12_MRET: begin
                                is_excp = 1'b0;
                                is_mret = 1'b1;
                            end
                            default: begin
                                is_excp = 1'b0;
                                is_mret = 1'b0;
                                excp_cause = 32'b0;
                            end
                        endcase
                    end
                    `FUNC3_CSRRW: begin
                        // 默认值
                    end
                    `FUNC3_CSRRS: begin
                        // 默认值
                    end
                    `FUNC3_CSRRC: begin
                        // 默认值
                    end
                    `FUNC3_CSRRWI: begin
                        opt_alusrc1 = `OPT_ALUSRC1_RS1;
                    end
                    `FUNC3_CSRRSI: begin
                        opt_alusrc1 = `OPT_ALUSRC1_RS1;
                    end
                    `FUNC3_CSRRCI: begin
                        opt_alusrc1 = `OPT_ALUSRC1_RS1;
                    end
                    default: begin 
                        opt_alusrc1 = `OPT_ALUSRC1_REGDATA;
                        opt_alusrc2 = `OPT_ALUSRC_CSR;
                    end
                endcase
            end
            default: begin
                opt_ie = `OPT_IE_IU;
                opt_alusrc2 = `OPT_ALUSRC_REG;
                opt_alusrc1 = `OPT_ALUSRC1_REGDATA;
            end
        endcase
    end
endmodule
