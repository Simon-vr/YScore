`timescale 1ns / 1ps
`include "rvdef.vh"

module ifid_mux_alusrc1(
input      opt,
input[4:0] rs1,
input[31:0] regdata,
output reg[31:0] alusrc
    );
always@* begin
    case (opt)
        `OPT_ALUSRC1_REGDATA: alusrc = regdata;
        `OPT_ALUSRC1_RS1:     alusrc = {27'b0, rs1};
        default:              alusrc = regdata;
    endcase
end
endmodule