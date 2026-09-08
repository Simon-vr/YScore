`timescale 1ns / 1ps
module core_if (
    input clk,
    input [31:0] ins_adr,
    output reg [31:0] ins
);
    (* ramstyle = "M9K" *) reg [31:0] ins_mem [0:4607]; // 18KB指令存储器，同步读(M9K)
    wire [29:0] addr = ins_adr[31:2];

    initial begin
        $readmemh("D:\\yscore\\rtos\\build\\imem.mem", ins_mem);
    end

    always @(posedge clk) begin
        ins <= ins_mem[addr];
    end

endmodule