`timescale 1ns / 1ps
module ifid_insmem(
    input  [31:0] ins_adr,
    output wire[31:0] ins,
    output wire[4:0] rs1,
    output wire[4:0] rs2,
    output wire[4:0] rd,
    output wire[11:0] csraddr,
    output wire[11:0] imm,
    output wire[11:0] offset,
    output wire[11:0] branch_offset,
    output wire[19:0] jump_offset,
    output wire[19:0] upper_imm
);

reg [31:0] ins_reg [0:4095]; // 4KB指令存储器，1024条指令
wire [29:0] addr = ins_adr[31:2];

// 综合路径: 使用可综合的readmemh初始化ROM
initial begin
    $readmemh("D:\\yscore\\rtos\\build\\imem.mem", ins_reg);
end

assign ins = ins_reg[addr];
//opcode = ins[6:0];
assign rd = ins[11:7];
//000
assign rs1 = ins[19:15];
assign rs2 = ins[24:20];
assign csraddr = ins[31:20];//for CSR instructions, 12
assign imm = ins[31:20];//for I-type/load offset, 12
assign offset = {ins[31:25], ins[11:7]};//for S-type/branch offset, 12
assign branch_offset = {ins[31], ins[7], ins[30:25], ins[11:8]};//for branch offset, 12
assign jump_offset = {ins[31], ins[19:12], ins[20], ins[30:21]};//for J-type/jump offset, 20
assign upper_imm = ins[31:12];//for U-type/upper immediate, 20
endmodule