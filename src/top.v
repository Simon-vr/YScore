`timescale 1ns / 1ps

module top (
    input  clk,       // 50MHz 系统时钟
    input  rst_n,     // 外部复位按键（低有效，未消抖）
    input         uart_rx,
    output        uart_tx,
    output [3:0]  gpio
);

//============================================================================
// rst 消抖（20ms @ 50MHz = 1,000,000 周期）
//============================================================================
    reg [19:0] rst_cnt;         // 2^20 = 1,048,576 > 1,000,000
    reg        rst_debounced;   // 消抖后的复位信号

    always @(posedge clk) begin
        if (!rst_n) begin
            rst_cnt <= rst_cnt + 1'b1;
            if (rst_cnt == 20'd1_000_000)
                rst_debounced <= 1'b0;  // 确认低电平有效
        end else begin
            rst_cnt <= 20'd0;
            rst_debounced <= 1'b1;      // 释放复位
        end
    end

//============================================================================
// core_ctl 实例化
//============================================================================
    core_ctl u_core_ctl (
        .clk(clk),
        .rst(rst_debounced),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .gpio  (gpio)
    );

endmodule