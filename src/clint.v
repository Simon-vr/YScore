`timescale 1ns / 1ps
`include "rvdef.vh"

module clint (
    input [31:0] adr,
    input [31:0] idata,
    input        clk,
    input        rst,
    input [1:0]  wen,
    output reg [31:0] odata,
    output reg    mtip
);

    reg [63:0] mtime;
    reg [63:0] mtimecmp;

    always @(posedge clk) begin
        if (!rst) begin
            mtime <= 64'd0;
            mtimecmp <= 64'hffffffffffffffff;
        end else begin
            mtime <= mtime + 1'b1;
            if (wen == `MEM_W_W) begin
                case (adr[15:0])
                    `CLINT_MTIME_LOW:    mtime[31:0]   <= idata;
                    `CLINT_MTIME_HIGH:   mtime[63:32]  <= idata;
                    `CLINT_MTIMECMP_LOW: mtimecmp[31:0] <= idata;
                    `CLINT_MTIMECMP_HIGH: mtimecmp[63:32] <= idata;
                    default: ;
                endcase
            end
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            mtip <= 1'b0;
        end else begin
            mtip <= (mtime >= mtimecmp);
        end
    end

    always @(posedge clk) begin
        case (adr[15:0])
            `CLINT_MTIME_LOW:    odata <= mtime[31:0];
            `CLINT_MTIME_HIGH:   odata <= mtime[63:32];
            `CLINT_MTIMECMP_LOW: odata <= mtimecmp[31:0];
            `CLINT_MTIMECMP_HIGH: odata <= mtimecmp[63:32];
            default: odata <= 32'b0;
        endcase
    end

endmodule
