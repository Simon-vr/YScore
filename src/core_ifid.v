`timescale 1ns / 1ps
module core_ifid (
    input[31:0] ins_adr,
    output[31:0] ins,//to ifid ctl
    input[1:0] opt_ie,//from ifid ctl

    output[4:0] rs1,
    output[4:0] rs2,
    output[4:0] rd,
    output[11:0] csraddr,
    output[31:0] eimm,
    output[31:0] ebranch_offset,
    output[31:0] ejump_offset,
    output[31:0] eupper_imm
);
    wire[11:0] imm;
    wire[11:0] offset;
    wire[11:0] branch_offset;
    wire[19:0] jump_offset;
    wire[19:0] upper_imm;

    ifid_insmem u_insmem(
        //input
        .ins_adr(ins_adr),
        //output
        .ins(ins),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .csraddr(csraddr),
        .imm(imm),
        .offset(offset),
        .branch_offset(branch_offset),
        .jump_offset(jump_offset),
        .upper_imm(upper_imm)
    );

    ifid_immex u_ifid_immex(
        //input
        .sign(opt_ie),
        .imm(imm),
        .offset(offset),
        .branch_offset(branch_offset),
        .jump_offset(jump_offset),
        .upper_imm(upper_imm),
        //output
        .eimm(eimm),
        .ebranch_offset(ebranch_offset),
        .ejump_offset(ejump_offset),
        .eupper_imm(eupper_imm)
    );

    
endmodule