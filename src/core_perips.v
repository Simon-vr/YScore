`timescale 1ns / 1ps

module core_perips (
    input        clk,
    input        rst,        // 低电平复位
    input [31:0] adr,
    input [31:0] idata,
    input [1:0]  wen,        // 01=sb 10=sh 11=sw
    input        req,        // perips_req 脉冲

    output [31:0] odata,
    output        busy,
    output        done,
    output        mtip,

    input         uart_rx,
    output        uart_tx,
    output [3:0]  gpio
);
    wire[63:0] gpio_all;
//=============================================================================
// 地址译码
//=============================================================================
    wire is_mem  = (adr[31] == 1'b1);           
    wire is_uart = (adr[31:16] == 16'h1000);    
    wire is_gpio = (adr[31:16] == 16'h2000);    
    wire is_clint = (adr[31:16] == 16'h0200);

//=============================================================================
// MEM — 固定一拍，不经过 AXI-Lite
//=============================================================================
    reg [1:0]  ram_wen;
    wire [31:0] ram_rdata;

    always @(*) begin
        if (is_mem) ram_wen = wen;
        else        ram_wen = 2'b00;
    end

    mem_ctl mem (
        .clk   (clk),
        .adr   (adr),
        .idata (idata),
        .wen   (ram_wen),
        .odata(ram_rdata)
    );

    reg mem_busy_r;
    reg mem_done_r;
    always @(posedge clk) begin
        if (!rst) begin
            mem_busy_r <= 1'b0;
            mem_done_r <= 1'b0;
        end else begin
            mem_done_r <= 1'b0;
            if (req && is_mem) begin
                mem_busy_r <= 1'b1;
            end else if (mem_busy_r) begin
                mem_busy_r <= 1'b0;
                mem_done_r <= 1'b1;
            end
        end
    end

//=============================================================================
// CLINT — 固定一拍，不经过 AXI-Lite
//=============================================================================
    wire [31:0] clint_rdata;
    reg  [1:0]  clint_wen;

    always @(*) begin
        if (is_clint) clint_wen = wen;
        else          clint_wen = 2'b00;
    end

    clint u_clint (
        .clk   (clk),
        .rst   (rst),
        .adr   (adr),
        .idata (idata),
        .wen   (clint_wen),
        .odata(clint_rdata),
        .mtip (mtip)
    );

    reg clint_busy_r;
    reg clint_done_r;
    always @(posedge clk) begin
        if (!rst) begin
            clint_busy_r <= 1'b0;
            clint_done_r <= 1'b0;
        end else begin
            clint_done_r <= 1'b0;
            if (req && is_clint) begin
                clint_busy_r <= 1'b1;
            end else if (clint_busy_r) begin
                clint_busy_r <= 1'b0;
                clint_done_r <= 1'b1;
            end
        end
    end

//=============================================================================
// AXI-Lite 总线 — 内部互联线网
//=============================================================================
    wire [31:0] s_axil_awaddr;
    wire        s_axil_awvalid;
    wire        s_axil_awready;
    wire [31:0] s_axil_wdata;
    wire [3:0]  s_axil_wstrb;
    wire        s_axil_wvalid;
    wire        s_axil_wready;
    wire [1:0]  s_axil_bresp;
    wire        s_axil_bvalid;
    wire        s_axil_bready;
    wire [31:0] s_axil_araddr;
    wire        s_axil_arvalid;
    wire        s_axil_arready;
    wire [31:0] s_axil_rdata;
    wire [1:0]  s_axil_rresp;
    wire        s_axil_rvalid;
    wire        s_axil_rready;

//=============================================================================
// AXI-Lite Master
//=============================================================================
    wire axil_mem_req = req && (is_uart || is_gpio);
    wire axil_mem_wen = (wen != 2'b00);

    wire [3:0] axil_wstrb;
    assign axil_wstrb = (wen == 2'b01) ? 4'b0001 :
                        (wen == 2'b10) ? 4'b0011 :
                        (wen == 2'b11) ? 4'b1111 : 4'b0000;

    wire [31:0] axil_rdata;
    wire        axil_ready;
    wire        axil_busy;

    axil_master #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32),
        .STRB_WIDTH(4)
    ) u_axil_master (
        .clk   (clk),
        .rstn  (rst),

        .mem_req   (axil_mem_req),
        .mem_wen   (axil_mem_wen),
        .mem_addr  (adr),
        .mem_wdata (idata),
        .mem_wstrb (axil_wstrb),
        .mem_rdata (axil_rdata),
        .mem_ready (axil_ready),
        .mem_busy  (axil_busy),

        // AXI-Lite Master → 互联线网
        .m_axil_awaddr (s_axil_awaddr),
        .m_axil_awprot (),
        .m_axil_awvalid(s_axil_awvalid),
        .m_axil_awready(s_axil_awready),
        .m_axil_wdata  (s_axil_wdata),
        .m_axil_wstrb  (s_axil_wstrb),
        .m_axil_wvalid (s_axil_wvalid),
        .m_axil_wready (s_axil_wready),
        .m_axil_bresp  (s_axil_bresp),
        .m_axil_bvalid (s_axil_bvalid),
        .m_axil_bready (s_axil_bready),
        .m_axil_araddr (s_axil_araddr),
        .m_axil_arprot (),
        .m_axil_arvalid(s_axil_arvalid),
        .m_axil_arready(s_axil_arready),
        .m_axil_rdata  (s_axil_rdata),
        .m_axil_rresp  (s_axil_rresp),
        .m_axil_rvalid (s_axil_rvalid),
        .m_axil_rready (s_axil_rready)
    );

//=============================================================================
// AXI-Lite Slave — UART
//=============================================================================
    wire        uart_awready, uart_wready, uart_bvalid;
    wire [1:0]  uart_bresp;
    wire        uart_arready;
    wire [31:0] uart_rdata_s;
    wire [1:0]  uart_rresp;
    wire        uart_rvalid;
// 0x00: TX_DATA  [W]   - Write byte to transmit (bits [7:0])
// 0x04: RX_DATA  [R]   - Read received byte (bits [7:0])
// 0x08: STATUS   [R]   - Status register
// 0x0C: CTRL     [R/W] - Control register
// 0x10: BAUD_DIV [R/W] - Baud rate divisor
// status
// bit 0: tx_empty  - 发送缓冲区空 (1=空)
// bit 1: tx_busy   - 发送忙 (1=正在发送)
// bit 2: rx_valid  - 接收数据有效 (1=有数据可读)
// bit 3: rx_error  - 接收错误 (帧错误)
// bits 4-31: 保留
    axil_uart #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(12)
    ) u_axil_uart (
        .clk  (clk),
        .rst  (~rst),

        .s_axil_awaddr (s_axil_awaddr[11:0]),
        .s_axil_awprot (3'b000),
        .s_axil_awvalid(s_axil_awvalid && is_uart),
        .s_axil_awready(uart_awready),
        .s_axil_wdata  (s_axil_wdata),
        .s_axil_wstrb  (s_axil_wstrb),
        .s_axil_wvalid (s_axil_wvalid && is_uart),
        .s_axil_wready (uart_wready),
        .s_axil_bresp  (uart_bresp),
        .s_axil_bvalid (uart_bvalid),
        .s_axil_bready (s_axil_bready),
        .s_axil_araddr (s_axil_araddr[11:0]),
        .s_axil_arprot (3'b000),
        .s_axil_arvalid(s_axil_arvalid && is_uart),
        .s_axil_arready(uart_arready),
        .s_axil_rdata  (uart_rdata_s),
        .s_axil_rresp  (uart_rresp),
        .s_axil_rvalid (uart_rvalid),
        .s_axil_rready (s_axil_rready),

        .uart_tx(uart_tx),
        .uart_rx(uart_rx)
    );

//=============================================================================
// AXI-Lite Slave — GPIO
//=============================================================================
    wire        gpio_awready, gpio_wready, gpio_bvalid;
    wire [1:0]  gpio_bresp;
    wire        gpio_arready;
    wire [31:0] gpio_rdata_s;
    wire [1:0]  gpio_rresp;
    wire        gpio_rvalid;
//      Offset 0x00: DATA[31:0]  (Read: Pin State, Write: Output Latch)
//      Offset 0x04: DATA[63:32]
//      Offset 0x08: DIR[31:0]   (0 = Input/High-Z, 1 = Output)
//      Offset 0x0C: DIR[63:32]
axil_gpio #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(32),
        .STRB_WIDTH(4),
        .N_GPIO(64)
    ) u_axil_gpio (
        .clk  (clk),
        .rst  (~rst),

        .s_axil_awaddr (s_axil_awaddr),
        .s_axil_awprot (3'b000),
        .s_axil_awvalid(s_axil_awvalid && is_gpio),
        .s_axil_awready(gpio_awready),
        .s_axil_wdata  (s_axil_wdata),
        .s_axil_wstrb  (s_axil_wstrb),
        .s_axil_wvalid (s_axil_wvalid && is_gpio),
        .s_axil_wready (gpio_wready),
        .s_axil_bresp  (gpio_bresp),
        .s_axil_bvalid (gpio_bvalid),
        .s_axil_bready (s_axil_bready),
        .s_axil_araddr (s_axil_araddr),
        .s_axil_arprot (3'b000),
        .s_axil_arvalid(s_axil_arvalid && is_gpio),
        .s_axil_arready(gpio_arready),
        .s_axil_rdata  (gpio_rdata_s),
        .s_axil_rresp  (gpio_rresp),
        .s_axil_rvalid (gpio_rvalid),
        .s_axil_rready (s_axil_rready),

        .gpio(gpio_all)
    );
    assign gpio = gpio_all[3:0];
//=============================================================================
// AXI-Lite 返回多路选择
//=============================================================================
    assign s_axil_awready = is_uart ? uart_awready :
                            is_gpio ? gpio_awready : 1'b0;
    assign s_axil_wready  = is_uart ? uart_wready  :
                            is_gpio ? gpio_wready  : 1'b0;
    assign s_axil_bresp   = is_uart ? uart_bresp   : gpio_bresp;
    assign s_axil_bvalid  = is_uart ? uart_bvalid  :
                            is_gpio ? gpio_bvalid  : 1'b0;
    assign s_axil_arready = is_uart ? uart_arready :
                            is_gpio ? gpio_arready : 1'b0;
    assign s_axil_rdata   = is_uart ? uart_rdata_s :
                            is_gpio ? gpio_rdata_s : 32'b0;
    assign s_axil_rresp   = is_uart ? uart_rresp   : gpio_rresp;
    assign s_axil_rvalid  = is_uart ? uart_rvalid  :
                            is_gpio ? gpio_rvalid  : 1'b0;

//=============================================================================
// 输出多路选择
//=============================================================================
    assign odata = (!rst) ? 32'b0 :
                   is_mem   ? ram_rdata :
                   is_clint ? clint_rdata :
                   s_axil_rdata;

    assign busy = is_mem   ? mem_busy_r :
                  is_clint ? clint_busy_r :
                  axil_busy;

    assign done = is_mem   ? mem_done_r :
                  is_clint ? clint_done_r :
                  axil_ready;

endmodule