`timescale 1ns/1ps
module mem_cell #(
    parameter ADDR_WIDTH = 13,          // 8KB per cell (32KB total with 4 cells)
    parameter INITIAL_PATH = "D:\\yscore\\ins\\dmem0.mem"
) (
    input clk,
    input [ADDR_WIDTH-1:0] addr,
    input [7:0] data_in,
    input mem_write,
    output reg [7:0] data_out
);
    parameter cell_size = 2 ** ADDR_WIDTH;
    (* ramstyle = "M9K" *)reg [7:0] memory [0:6143];   //6KB
    initial begin
    $readmemh(INITIAL_PATH, memory);
    end
    always @(posedge clk) begin
        if (mem_write) begin
            memory[addr] <= data_in;
        end
        data_out <= memory[addr];
    end

endmodule