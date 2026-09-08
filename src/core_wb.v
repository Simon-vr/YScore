`timescale 1ns / 1ps
`include "rvdef.vh"
module core_wb(
input[3:0] opt_wb,
input[31:0] memdata,
input[31:0] alures,
input[31:0] pc,
input[31:0] upperimm,
input[31:0] csrdata,
input       excp_token,
input       is_mret,
input       ctl_csrw,
output reg[31:0] wbreg,
output reg[31:0] wbcsr,
output reg[2:0]  csr_wen
);
always @(*) begin
    if(excp_token) begin
        csr_wen = 3'b010;
    end else if(is_mret) begin
        csr_wen = 3'b011;
    end else if(ctl_csrw) begin
        csr_wen = 3'b001;
    end else begin
        csr_wen = 3'b000;
    end
end
always @(*) begin
    wbcsr = alures;
    case(opt_wb)
        `OPT_WB_ALU:   wbreg=alures;                             //alu
        `OPT_WB_LB:    wbreg={{24{memdata[7]}}, memdata[7:0]};   //lb
        `OPT_WB_LBU:   wbreg={24'b0, memdata[7:0]};              //lbu
        `OPT_WB_LH:    wbreg={{16{memdata[15]}}, memdata[15:0]}; //lh
        `OPT_WB_LHU:   wbreg={16'b0, memdata[15:0]};             //lhu
        `OPT_WB_LW:    wbreg=memdata;                             //lw
        `OPT_WB_PC4:   wbreg=pc+4;                                //jal, jalr
        `OPT_WB_LUI:   wbreg=upperimm;                            //lui
        `OPT_WB_AUIPC: wbreg=upperimm+pc;                         //auipc
        `OPT_WB_CSR:   wbreg=csrdata;                               //csr
        default:       wbreg=32'h0;
    endcase
end
    
endmodule