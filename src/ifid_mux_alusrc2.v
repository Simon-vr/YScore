`timescale 1ns / 1ps
`include "rvdef.vh"

module ifid_mux_alusrc2(
input[1:0] opt,
input[31:0] regdata2,
input[31:0] immdata,
input[31:0] csrdata,
output reg[31:0] alusrc
    );
always@* begin
    case (opt)
        `OPT_ALUSRC_REG: alusrc = regdata2;
        `OPT_ALUSRC_IMM: alusrc = immdata;
        `OPT_ALUSRC_CSR: alusrc = csrdata;
        default: alusrc = 32'b0;
    endcase
end
endmodule
