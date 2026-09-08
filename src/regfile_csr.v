`timescale 1ns / 1ps
`include "rvdef.vh"

module regfile_csr (
    input clk,
    input rst,
    input[2:0] wen,
    input mtip,
    input perips_token,
    // type 1 csr
    input[11:0] raddr,
    input[11:0] waddr,
    input[31:0] idata,
    output reg[31:0] odata,
    // type 2 excp
    input[31:0] pc,
    input[31:0] nextpc,
    input[31:0] excp_cause,
    input[31:0] excp_mtval,
    output[31:0] mtvec,
    //type 3 mret    
    output[31:0] mepc,
    //type 4 interrupt
    output reg intrpt
);
reg[31:0] csr[0:8];
always @(*) begin
    case(raddr)
        `ADDR_MSTATUS: odata = csr[0];
        `ADDR_MISA: odata = csr[1];
        `ADDR_MIE: odata = csr[2];
        `ADDR_MTVEC: odata = csr[3];
        `ADDR_MSCRATCH: odata = csr[4];
        `ADDR_MEPC: odata = csr[5];
        `ADDR_MCAUSE: odata = csr[6];
        `ADDR_MTVAL: odata = csr[7];
        `ADDR_MIP: odata = csr[8];
        default: odata = 32'h0;
    endcase
end
assign mtvec = csr[3];
assign mepc = csr[5];

integer i;
always @(posedge clk or negedge rst) begin
    if (!rst) begin
        intrpt <= 1'b0;
        csr[0] <= 32'h00001888; // mstatus
        for (i=1; i<9; i=i+1)
            csr[i] <= 32'h0;
    end else if (perips_token == 1'b1 && wen == 3'b001) begin      //csr ins
        intrpt <= 1'b0;
        case(waddr)
            `ADDR_MSTATUS: csr[0] <= idata;   // 机器状态寄存器：控制全局中断使能、特权模式切换、浮点状态、内存访问权限等核心CPU状态      
            `ADDR_MISA: csr[1] <= idata;      // (可能用不到)机器ISA寄存器：只读（或部分可写），指示CPU支持的指令集扩展（A/C/D/F等）和当前XLEN位数
            `ADDR_MIE: csr[2] <= idata;       // 机器中断使能寄存器：按位控制各个中断源（软件、定时器、外部中断）是否被允许响应
            `ADDR_MTVEC: csr[3] <= idata;     // 机器陷阱向量基址寄存器：存放异常/中断入口地址，支持直接模式或向量模式跳转 
            `ADDR_MSCRATCH: csr[4] <= idata;  // 机器模式临时存储寄存器：软硬件约定用于保存上下文指针或临时数据，典型用法是在异常入口处暂存SP（栈指针） 
            `ADDR_MEPC: csr[5] <= idata;      // 机器异常程序计数器：发生异常/中断时，硬件自动保存返回地址，用于异常返回（MRET）时恢复PC 
            `ADDR_MCAUSE: csr[6] <= idata;    // 机器异常原因寄存器：记录上次异常/中断的原因编码（最高位指示是否中断，低位存放具体编码）
            `ADDR_MTVAL: csr[7] <= idata;     // (可能用不到)机器异常值寄存器：记录与异常相关的附加信息，如无效地址（页错误/未对齐）、非法指令的编码等   
            `ADDR_MIP: csr[8] <= idata;       // 机器中断等待寄存器：按位指示当前哪些中断源处于等待（挂起）状态，用于软件查询或优先级仲裁  
        endcase
    end else if (perips_token == 1'b1 && wen == 3'b010) begin  // 发生异常时写入
        intrpt <= 1'b0;
        csr[5] <= pc; // mepc
        csr[6] <= excp_cause; // mcause
        csr[7] <= excp_mtval; // mtval
        //将当前 MIE（位3）复制到 MPIE（位7）
        csr[0][7] <= csr[0][3];  // MPIE = MIE
        // 将 MIE 清零
        csr[0][3] <= 1'b0;          // MIE = 0
    end else if (perips_token == 1'b1 && wen == 3'b011) begin  // mret时写入
        intrpt <= 1'b0;
        csr[0][3] <= csr[0][7]; // mstatus.MIE = mstatus.MPIE
    end else if (perips_token == 1'b1 && csr[0][3] == 1'b1) begin  // 检查外中断是否成立
        intrpt <= 1'b0;
        if (csr[2][7] == 1'b1 && mtip == 1'b1) begin
            csr[5] <= nextpc; // mepc = 被中断指令的真实下一PC(分支/跳转时非pc+4)
            csr[6] <= 32'h80000007;
            //将当前 MIE（位3）复制到 MPIE（位7）
            csr[0][7] <= csr[0][3];  // MPIE = MIE
            // 将 MIE 清零
            csr[0][3] <= 1'b0;          // MIE = 0
            intrpt <= 1'b1;
        end
    end else begin
        intrpt <= 1'b0;
    end
end
endmodule