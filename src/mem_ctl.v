`timescale 1ns/1ps
module mem_ctl #(
    parameter MEM_WIDTH = 15  // 24KB = 2^15 bytes = 4*6KB
) (
    input[31:0]    adr,
    input[31:0]    idata,
    input[1:0]     wen,        // 01=sb 10=sh 11=sw
    input          clk,
    output reg[31:0]  odata
);

    // ====================== 1. 基础信号拆分 ======================
    wire [1:0]           offset = adr[1:0];
    // Mask address to 24KB (0x6000 bytes)
    wire [14:0]          adr_masked = adr[14:0];
    wire [MEM_WIDTH-3:0] base_addr = adr_masked[14:2];

    // ====================== 2. 写使能生成（支持 1001） ======================
    reg [3:0] we;
    always @(*) begin
        case(wen)
            2'b01: we = 4'b1 << offset;
            2'b10: case(offset)
                2'b00: we = 4'b0011;
                2'b01: we = 4'b0110;
                2'b10: we = 4'b1100;
                2'b11: we = 4'b1001;
                default: we = 4'b0000;
            endcase
            2'b11: we = 4'b1111;
            default: we = 4'b0000;
        endcase
    end

    // ====================== 2. 写入数据：桶形左移（按offset旋转） ======================
    reg [31:0] wdata_shifted;
    always @(*) begin
        case(offset)
            2'b00: wdata_shifted = idata;
            2'b01: wdata_shifted = {idata[23:0], idata[31:24]};
            2'b10: wdata_shifted = {idata[15:0], idata[31:16]};
            2'b11: wdata_shifted = {idata[7:0], idata[31:8]};
            default: wdata_shifted = idata;
        endcase
    end
    wire [7:0] wbyte [3:0];
    assign wbyte[0] = wdata_shifted[7:0];
    assign wbyte[1] = wdata_shifted[15:8];
    assign wbyte[2] = wdata_shifted[23:16];
    assign wbyte[3] = wdata_shifted[31:24];

    // ====================== 3. 每个字节单元的地址计算（核心！跨字边界+1） ======================
    // 对于第i个字节单元，地址 = base_addr + ((offset + i) >= 4)
    reg [MEM_WIDTH-3:0] mem_addr [3:0];
    always @(*) begin
        case (offset)
            2'b00: begin
                mem_addr[0] = base_addr;
                mem_addr[1] = base_addr;
                mem_addr[2] = base_addr;
                mem_addr[3] = base_addr;
            end
            2'b01:begin
                mem_addr[0] = base_addr + 1'd1;
                mem_addr[1] = base_addr;
                mem_addr[2] = base_addr;
                mem_addr[3] = base_addr;
            end
            2'b10:begin
                mem_addr[0] = base_addr + 1'd1;
                mem_addr[1] = base_addr + 1'd1;
                mem_addr[2] = base_addr;
                mem_addr[3] = base_addr;
            end
            2'b11:begin
                mem_addr[0] = base_addr + 1'd1;
                mem_addr[1] = base_addr + 1'd1;
                mem_addr[2] = base_addr + 1'd1;
                mem_addr[3] = base_addr;
            end
            default:begin
                mem_addr[0] = base_addr;
                mem_addr[1] = base_addr;
                mem_addr[2] = base_addr;
                mem_addr[3] = base_addr;
            end
        endcase
    end
    // ====================== 4. 4个独立字节存储单元 ======================
    wire [7:0] rbyte [3:0];
    mem_cell #(
    .ADDR_WIDTH(13),          // 8KB per cell
    .INITIAL_PATH("D:\\yscore\\rtos\\build\\dmem0.mem")
    ) u_cell0 (
        .clk(clk),
        .addr(mem_addr[0][12:0]),
        .data_in(wbyte[0]), 
        .mem_write(we[0]),
        .data_out(rbyte[0])
    );

    mem_cell #(
    .ADDR_WIDTH(13),
    .INITIAL_PATH("D:\\yscore\\rtos\\build\\dmem1.mem")
    ) u_cell1 (
        .clk(clk),
        .addr(mem_addr[1][12:0]),
        .data_in(wbyte[1]), 
        .mem_write(we[1]),
        .data_out(rbyte[1])
    );

    mem_cell #(
    .ADDR_WIDTH(13),
    .INITIAL_PATH("D:\\yscore\\rtos\\build\\dmem2.mem")
    ) u_cell2 (
        .clk(clk),
        .addr(mem_addr[2][12:0]),
        .data_in(wbyte[2]), 
        .mem_write(we[2]),
        .data_out(rbyte[2])
    );

    mem_cell #(
    .ADDR_WIDTH(13),
    .INITIAL_PATH("D:\\yscore\\rtos\\build\\dmem3.mem")
    ) u_cell3 (
        .clk(clk),
        .addr(mem_addr[3][12:0]),
        .data_in(wbyte[3]), 
        .mem_write(we[3]),
        .data_out(rbyte[3])
    );
    // ====================== 6. 读出数据：桶形右移（恢复原序） ======================
    wire [31:0] rdata_rotated = {rbyte[3], rbyte[2], rbyte[1], rbyte[0]};
    always @(*) begin
        if (wen != 2'b00) begin
            odata = 32'b0; // 写操作时不输出有效数据
        end
        else begin
            case(offset)
                2'b00: odata = rdata_rotated;
                2'b01: odata = {rdata_rotated[7:0], rdata_rotated[31:8]};
                2'b10: odata = {rdata_rotated[15:0], rdata_rotated[31:16]};
                2'b11: odata = {rdata_rotated[23:0], rdata_rotated[31:24]};
                default: odata = rdata_rotated;
            endcase
        end
    end
endmodule