`timescale 1ns / 1ps

module regfile(
input clk,
input rst,  // 异步低有效复位

input[4:0] src1,
input[4:0] src2,

input wen,//1:写
input[4:0] des,
input[31:0] idata, 

output wire[31:0] odata1,
output wire[31:0] odata2
);

reg[31:0] regfile[31:0]; // 32个32位寄存器
integer i;
// 写 + 异步复位（时序逻辑）
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        // 复位：所有寄存器清零
        for(i=0; i<32; i=i+1)
            regfile[i] <= 32'd0;
    end
    else if (wen && des != 5'd0) begin
        regfile[des] <= idata; // 正常写寄存器
    end
end

assign odata1 = regfile[src1];
assign odata2 = regfile[src2];
endmodule