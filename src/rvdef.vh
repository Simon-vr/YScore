// ==============================
// RV32I 指令操作码定义
// ==============================
`ifndef RV32I_OPCODEF
`define RV32I_OPCODEF

`define OP_RTYPE   7'b0110011 // R型
`define OP_ITYPE   7'b0010011 // I型算术
`define OP_LOAD    7'b0000011 // I型Load
`define OP_STORE   7'b0100011 // S型Store
`define OP_BRANCH  7'b1100011 // B型Branch
`define OP_JAL     7'b1101111 // JAL
`define OP_JALR    7'b1100111 // JALR
`define OP_LUI     7'b0110111 // LUI
`define OP_AUIPC   7'b0010111 // AUIPC
`define OP_CSR     7'b1110011 // Zicsr

`endif

// ==============================
// RV32I R-Type 功能码 {funct7, funct3} (10bit)
// ==============================
`ifndef RV32I_FUNC_RF
`define RV32I_FUNC_RF

`define FUNC_ADD   10'b0000000_000 // ADD
`define FUNC_SUB   10'b0100000_000 // SUB
`define FUNC_AND   10'b0000000_111 // AND
`define FUNC_OR    10'b0000000_110 // OR
`define FUNC_XOR   10'b0000000_100 // XOR
`define FUNC_SLL   10'b0000000_001 // 逻辑左移
`define FUNC_SRL   10'b0000000_101 // 逻辑右移
`define FUNC_SRA   10'b0100000_101 // 算术右移
`define FUNC_SLT   10'b0000000_010 // 有符号小于比较
`define FUNC_SLTU  10'b0000000_011 // 无符号小于比较

`endif

// ==============================
// RV32I I-Type 功能码 funct3 (3bit)
// ==============================
`ifndef RV32I_FUNC_IF
`define RV32I_FUNC_IF

`define FUNC3_ADDI  3'b000 // ADDI
`define FUNC3_ANDI  3'b111 // ANDI
`define FUNC3_ORI   3'b110 // ORI
`define FUNC3_XORI  3'b100 // XORI
`define FUNC3_SLLI  3'b001 // SLLI
`define FUNC3_SRAI  3'b101 // SRAI (与SRLI共用funct3，通过funct7区分)
`define FUNC3_SLTI  3'b010 // SLTI
`define FUNC3_SLTIU 3'b011 // SLTIU

`define FUNC7_SRLI  7'b0000000 // SRLI funct7
`define FUNC7_SRAI  7'b0100000 // SRAI funct7

`endif

// ==============================
// RV32I Load/Store 功能码 funct3 (3bit)
// ==============================
`ifndef RV32I_FUNC_LSF
`define RV32I_FUNC_LSF

`define FUNC3_LB   3'b000
`define FUNC3_LH   3'b001
`define FUNC3_LW   3'b010
`define FUNC3_LBU  3'b100
`define FUNC3_LHU  3'b101
`define FUNC3_SB   3'b000
`define FUNC3_SH   3'b001
`define FUNC3_SW   3'b010

`endif

// ==============================
// RV32I Branch 功能码 funct3 (3bit)
// ==============================
`ifndef RV32I_FUNC_BF
`define RV32I_FUNC_BF

`define FUNC3_BEQ  3'b000
`define FUNC3_BNE  3'b001
`define FUNC3_BLT  3'b100
`define FUNC3_BGE  3'b101
`define FUNC3_BLTU 3'b110
`define FUNC3_BGEU 3'b111

`endif

// ==============================
// RV32I CSR 功能码 funct3 (3bit) — SYSTEM opcode (1110011)
// ==============================
`ifndef RV32I_FUNC_CSR
`define RV32I_FUNC_CSR

`define FUNC3_CSRRW  3'b001 // CSRRW
`define FUNC3_CSRRS  3'b010 // CSRRS
`define FUNC3_CSRRC  3'b011 // CSRRC
`define FUNC3_CSRRWI 3'b101 // CSRRWI
`define FUNC3_CSRRSI 3'b110 // CSRRSI
`define FUNC3_CSRRCI 3'b111 // CSRRCI
`define FUNC3_EXCP  3'b000 // ECALL/EBREAK/MRET/WFI (funct12区分)

`endif

// ==============================
// RV32I SYSTEM funct12 (ins[31:20])
// ==============================
`ifndef RV32I_SYSTEM_F12
`define RV32I_SYSTEM_F12

`define F12_ECALL   12'h000
`define F12_EBREAK  12'h001
`define F12_MRET    12'h302

`endif

// ==============================
// 异常/陷阱原因编码
// ==============================
`ifndef RV32I_EXCP_CAUSE
`define RV32I_EXCP_CAUSE

`define EXCP_CAUSE_NONE    32'd0
`define EXCP_CAUSE_EBREAK  32'd3
`define EXCP_CAUSE_ECALL   32'd11
`define EXCP_CAUSE_MRET    32'hffff_ffff
`endif

// ==============================
// ALU 功能码定义 (4bit)
// ==============================
`ifndef RV32I_ALU_FUNC
`define RV32I_ALU_FUNC

`define ALU_ADD   4'b0000 // 加法 ADD/ADDI
`define ALU_SUB   4'b0001 // 减法 SUB
`define ALU_SLL   4'b0010 // 逻辑左移 SLL/SLLI
`define ALU_OR    4'b0011 // 按位或 OR/ORI
`define ALU_AND   4'b0100 // 按位与 AND/ANDI
`define ALU_SLTU  4'b0101 // 无符号比较 SLTU/SLTIU
`define ALU_SLT   4'b0110 // 有符号比较 SLT/SLTI
`define ALU_XOR   4'b0111 // 按位异或 XOR/XORI
`define ALU_SRL   4'b1000 // 逻辑右移 SRL/SRLI
`define ALU_SRA   4'b1001 // 算术右移 SRA/SRAI
`define ALU_SRC1  4'b1010 // 直接输出 data1
`define ALU_SRC2  4'b1011 // 直接输出 data2
`define ALU_ANDN  4'b1100 // ~data1 & data2 (ANDN)

`endif

// ==============================
// 控制信号编码定义
// ==============================
// 立即数扩展
`ifndef RV32I_CTRL_IE
`define RV32I_CTRL_IE

`define OPT_IE_IU     2'b00 // I-type unsigned
`define OPT_IE_IS     2'b01 // I-type signed
`define OPT_IE_OFFSET 2'b10 // S-type/branch offset

`endif

// ALU第二操作数选择
`ifndef RV32I_CTRL_ALUSRC
`define RV32I_CTRL_ALUSRC

`define OPT_ALUSRC_REG 2'b00 // rs2 data
`define OPT_ALUSRC_IMM 2'b01 // extended immediate
`define OPT_ALUSRC_CSR 2'b10 // CSR data

`endif

// ALU第一操作数选择
`ifndef RV32I_CTRL_ALUSRC1
`define RV32I_CTRL_ALUSRC1

`define OPT_ALUSRC1_REGDATA 1'b0 // regfile odata1
`define OPT_ALUSRC1_RS1     1'b1 // rs1 零扩展

`endif

// 内存写使能
`ifndef RV32I_CTRL_MEMW
`define RV32I_CTRL_MEMW

`define MEM_W_NONE 2'b00
`define MEM_W_B    2'b01
`define MEM_W_H    2'b10
`define MEM_W_W    2'b11

`endif

// 寄存器写回数据选择
`ifndef RV32I_CTRL_WB
`define RV32I_CTRL_WB

`define OPT_WB_ALU   4'b0000
`define OPT_WB_LB    4'b0001
`define OPT_WB_LBU   4'b0010
`define OPT_WB_LH    4'b0011
`define OPT_WB_LHU   4'b0100
`define OPT_WB_LW    4'b0101
`define OPT_WB_PC4   4'b0110 // PC+4 for JAL/JALR
`define OPT_WB_LUI   4'b0111 // LUI
`define OPT_WB_AUIPC 4'b1000 // AUIPC
`define OPT_WB_CSR   4'b1001 // CSR

`endif

// 下一PC选择
`ifndef RV32I_CTRL_NEXT
`define RV32I_CTRL_NEXT

`define NEXT_SEQ   4'b0000 // 顺序执行
`define NEXT_BEQ   4'b0001 // BEQ
`define NEXT_BNE   4'b0010 // BNE
`define NEXT_BLT   4'b0011 // BLT
`define NEXT_BGE   4'b0100 // BGE
`define NEXT_JAL   4'b0101 // JAL
`define NEXT_JALR  4'b0110 // JALR
`define NEXT_BLTU  4'b0111 // BLTU
`define NEXT_BGEU  4'b1000 // BGEU
`endif


// ==============================
// RV32-Zicsr 有效地址
// ==============================
`ifndef RV32ZICSR
`define RV32ZICSR

`define ADDR_MSTATUS    12'h300  
`define ADDR_MISA       12'h301  
`define ADDR_MIE        12'h304  
`define ADDR_MTVEC      12'h305  
`define ADDR_MSCRATCH   12'h340  
`define ADDR_MEPC       12'h341  
`define ADDR_MCAUSE     12'h342  
`define ADDR_MTVAL      12'h343  
`define ADDR_MIP        12'h344  

`endif

// ==============================
// CLINT 地址 (adr[15:0], 基址=0x0200_xxxx)
// ==============================
`ifndef RV32I_CLINT_ADDR
`define RV32I_CLINT_ADDR

`define CLINT_MTIME_LOW    16'hbff8
`define CLINT_MTIME_HIGH   16'hbffc
`define CLINT_MTIMECMP_LOW 16'h4000
`define CLINT_MTIMECMP_HIGH 16'h4004

`endif