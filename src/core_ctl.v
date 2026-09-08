`timescale 1ns / 1ps
module core_ctl (
    input  clk,
    input  rst,          //低电平复位
    input         uart_rx,
    output        uart_tx,
    output [3:0]  gpio
);

//============================================================================
// 1. 控制信号线网
//============================================================================
    wire [1:0] ctl_ie_w;
    wire [1:0] ctl_alusrc2_w;
    wire       ctl_alusrc1_w;
    wire       ctl_peripsen_w;
    wire [3:0] ctl_alufunc_w;
    wire [3:0] ctl_nextfunc_w;
    wire [3:0] ctl_wb_w;
    wire       ctl_regw_w;
    wire       ctl_csrw_w;
    wire [1:0] ctl_memw_w;

//============================================================================
// 2. ifid 阶段线网
//============================================================================
    wire [31:0] ifid_ins_w;
    wire [4:0]  ifid_rs1_w;
    wire [4:0]  ifid_rs2_w;
    wire [4:0]  ifid_rd_w;
    wire [11:0] ifid_csraddr_w;
    wire [31:0] ifid_eimm_w;
    wire [31:0] ifid_branch_w;
    wire [31:0] ifid_jump_w;
    wire [31:0] ifid_upper_w;
    wire [31:0] ifid_odata1_w;
    wire [31:0] ifid_odata2_w;
    wire [31:0] ifid_alusrc1_w;
    wire [31:0] ifid_alusrc2_w;
    wire [31:0] ifid_csrdata_w;

    wire        ifid_ecall_w;
    wire        ifid_mret_w;
    wire [31:0] ifid_mcause_w;

//============================================================================
// 3. exe 阶段线网
//============================================================================
    wire [31:0] exe_res_w;
    wire [31:0] exe_next_pc_w;

//============================================================================
// 4. perips / wb 阶段线网
//============================================================================
    wire [1:0]  exe_memw_w;
    wire [31:0] perips_data_w;
    wire        perips_mtip_w;
    wire [31:0] wb_reg_w;
    wire [31:0] wb_csr_w;
    wire [2:0]  wb_csrwen_w;
    wire[31:0]  csr_mtvec;
    wire[31:0]  csr_mepc;
    wire        csr_intrpt_w;
    wire[31:0]  wb_pc_w;

//============================================================================
// 5. token 标志
//============================================================================
    
    reg if_token;
    reg ifid_token;
    reg exe_token;
    reg perips_token;
    reg perips_pending;
    reg perips_req;
    reg wb_pending;
    reg wb_token;

//============================================================================
// 6. 流水线寄存器
//============================================================================
    reg [31:0] wb_pc;

    reg [31:0] if_pc;
    reg [31:0] ifid_pc;
    reg [31:0] ifid_regdata2;
    reg [31:0] ifid_alusrc1;
    reg [31:0] ifid_alusrc2;
    reg [31:0] ifid_branch;
    reg [31:0] ifid_jump;
    reg [31:0] ifid_upper;
    reg [4:0]  ifid_regdest;
    reg [3:0]  ifid_ctl_alufunc;
    reg [3:0]  ifid_ctl_nextfunc;
    reg [3:0]  ifid_ctl_wb;
    reg [1:0]  ifid_ctl_memw;
    reg        ifid_ctl_regw;
    reg        ifid_ctl_csrw;
    reg        ifid_ctl_peripsen;
    reg [31:0] ifid_csr;
    reg [11:0] ifid_csraddr;

    reg [31:0] exe_pc;
    reg [31:0] exe_regdata2;
    reg [31:0] exe_alures;
    reg [31:0] exe_nextpc;
    reg [31:0] exe_upper;
    reg [4:0]  exe_regdest;
    reg [3:0]  exe_ctl_wb;
    reg [1:0]  exe_ctl_memw;
    reg        exe_ctl_regw;
    reg        exe_ctl_csrw;
    reg        exe_ctl_peripsen;
    reg [31:0] exe_csr;
    reg [11:0] exe_csraddr;

    reg [31:0] perips_pc;
    reg [31:0] perips_alures;
    reg [31:0] perips_upper;
    reg [31:0] perips_nextpc;
    reg [31:0] perips_data;
    reg [4:0]  perips_regdest;
    reg [3:0]  perips_ctl_wb;
    reg        perips_ctl_regw;
    reg        perips_ctl_csrw;
    reg [31:0] perips_csr;
    reg [11:0] perips_csraddr;

//============================================================================
// 7. 异常状态通道
//============================================================================

    reg excp_token;
    reg excp_ismret;
    reg[31:0] excp_cause;
    reg[31:0] excp_mtval;

//============================================================================
// 8. 核心硬件模块
//============================================================================

    regfile u_regfile(
        .clk   (clk),
        .rst   (rst),
        .src1  (ifid_rs1_w),
        .src2  (ifid_rs2_w),
        .wen   (perips_token && perips_ctl_regw),
        .des   (perips_regdest),
        .idata (wb_reg_w),
        .odata1(ifid_odata1_w),
        .odata2(ifid_odata2_w)
    );

    regfile_csr u_regfile_csr(
        .clk   (clk),
        .rst   (rst),
        .wen   (perips_token? wb_csrwen_w : 3'b000),
        .raddr (ifid_csraddr_w),
        .waddr (perips_csraddr),
        .idata (wb_csr_w),
        .odata (ifid_csrdata_w),
        .pc    (perips_pc),
        .nextpc (perips_nextpc),
        .excp_cause (excp_cause),
        .excp_mtval (excp_mtval),
        .mtvec (csr_mtvec),
        .mepc  (csr_mepc),
        .mtip  (perips_mtip_w),
        .perips_token (perips_token),
        .intrpt (csr_intrpt_w)
    );

    core_if u_core_if(
        .clk    (clk),
        .ins_adr(wb_pc),
        .ins    (ifid_ins_w)
    );

    core_id u_core_id(
        .ins      (ifid_ins_w),
        .opt_ie   (ctl_ie_w),
        .rs1      (ifid_rs1_w),
        .rs2      (ifid_rs2_w),
        .rd       (ifid_rd_w),
        .csraddr  (ifid_csraddr_w),
        .eimm     (ifid_eimm_w),
        .ebranch_offset(ifid_branch_w),
        .ejump_offset  (ifid_jump_w),
        .eupper_imm    (ifid_upper_w)
    );

    ctl_ifid u_ctl_ifid(
        .ins        (ifid_ins_w),
        .opt_ie     (ctl_ie_w),
        .opt_alusrc2 (ctl_alusrc2_w),
        .opt_alusrc1(ctl_alusrc1_w),
        .is_excp    (ifid_ecall_w),
        .is_mret    (ifid_mret_w),
        .excp_cause (ifid_mcause_w)
    );

    ctl_exe u_ctl_exe(
        .ins      (ifid_ins_w),
        .alu_func (ctl_alufunc_w),
        .next_func(ctl_nextfunc_w)
    );

    ctl_perips u_ctl_perips(
        .ins      (ifid_ins_w),
        .mem_write(ctl_memw_w),
        .peripsen (ctl_peripsen_w)
    );

    ctl_wb u_ctl_wb(
        .ins      (ifid_ins_w),
        .opt_wb   (ctl_wb_w),
        .reg_write(ctl_regw_w),
        .csr_write(ctl_csrw_w)
    );


    ifid_mux_alusrc1 u_ifid_mux_alusrc1(
        .opt     (ctl_alusrc1_w),
        .rs1     (ifid_rs1_w),
        .regdata (ifid_odata1_w),
        .alusrc  (ifid_alusrc1_w)
    );

    ifid_mux_alusrc2 u_ifid_mux_alusrc2(
        .opt     (ctl_alusrc2_w),
        .regdata2(ifid_odata2_w),
        .immdata (ifid_eimm_w),
        .csrdata (ifid_csrdata_w),
        .alusrc  (ifid_alusrc2_w)
    );

    core_exe u_core_exe(
        .alufunc      (ifid_ctl_alufunc),
        .data1        (ifid_alusrc1),
        .data2        (ifid_alusrc2),
        .cur_pc       (ifid_pc),
        .next_func    (ifid_ctl_nextfunc),
        .branch_offset(ifid_branch),
        .jump_offset  (ifid_jump),
        .res          (exe_res_w),
        .next_pc      (exe_next_pc_w)
    );

    assign exe_memw_w = exe_ctl_memw;

    wire perips_done;
    wire perips_busy;

    core_perips u_core_perips(
        .clk  (clk),
        .rst  (rst),
        .adr  (exe_alures),
        .idata(exe_regdata2),
        .wen  (exe_token ? exe_memw_w : 2'b00),
        .req  (perips_req),
        .odata(perips_data_w),
        .busy (perips_busy),
        .done (perips_done),
        .mtip (perips_mtip_w),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .gpio (gpio)
    );

    core_wb u_core_wb(
        .opt_wb  (perips_ctl_wb),
        .memdata (perips_data),
        .alures  (perips_alures),
        .pc      (perips_pc),
        .upperimm(perips_upper),
        .csrdata(perips_csr),
        .excp_token(excp_token),
        .is_mret  (excp_ismret),
        .ctl_csrw(perips_ctl_csrw),
        .wbreg   (wb_reg_w),
        .wbcsr   (wb_csr_w),
        .csr_wen (wb_csrwen_w)
    );

    wb_mux_pc u_wb_mux_pc(
        .perips_nextpc (perips_nextpc),
        .mepc          (csr_mepc),
        .mtvec         (csr_mtvec),
        .excp_token    (excp_token),
        .is_mret       (excp_ismret),
        .intrpt        (csr_intrpt_w),
        .nextpc        (wb_pc_w)
    );

//============================================================================
// 9. 多周期流水线控制
//============================================================================
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            wb_pc           <= 32'h0;
            wb_token        <= 1'b1;
            wb_pending      <= 1'b0;
            if_token        <= 1'b0;
            ifid_token      <= 1'b0;
            exe_token       <= 1'b0;
            perips_token    <= 1'b0;
            perips_pending  <= 1'b0;
            perips_req      <= 1'b0;

            if_pc           <= 32'h0;

            ifid_pc         <= 32'h0;
            ifid_regdata2   <= 32'h0;
            ifid_alusrc1    <= 32'h0;
            ifid_alusrc2    <= 32'h0;
            ifid_branch     <= 32'h0;
            ifid_jump       <= 32'h0;
            ifid_upper      <= 32'h0;
            ifid_regdest    <= 5'd0;
            ifid_ctl_alufunc<= 4'h0;
            ifid_ctl_nextfunc<= 4'h0;
            ifid_ctl_wb     <= 4'h0;
            ifid_ctl_memw   <= 2'h0;
            ifid_ctl_regw   <= 1'b0;
            ifid_ctl_csrw   <= 1'b0;
            ifid_ctl_peripsen <= 1'b0;
            ifid_csr        <= 32'd0;
            ifid_csraddr    <= 12'd0;

            exe_pc          <= 32'h0;
            exe_regdata2    <= 32'h0;
            exe_alures      <= 32'h0;
            exe_nextpc      <= 32'h0;
            exe_upper       <= 32'h0;
            exe_regdest     <= 5'd0;
            exe_ctl_wb      <= 4'h0;
            exe_ctl_memw    <= 2'h0;
            exe_ctl_regw    <= 1'b0;
            exe_ctl_csrw    <= 1'b0;
            exe_ctl_peripsen <= 1'b0;
            exe_csr         <= 32'd0;
            exe_csraddr     <= 12'd0;

            perips_pc       <= 32'h0;
            perips_alures   <= 32'h0;
            perips_upper    <= 32'h0;
            perips_nextpc   <= 32'h0;
            perips_data     <= 32'h0;
            perips_regdest  <= 5'd0;
            perips_ctl_wb   <= 4'h0;
            perips_ctl_regw <= 1'b0;
            perips_ctl_csrw <= 1'b0;
            perips_csr      <= 32'd0;
            perips_csraddr  <= 12'd0;

            excp_token      <= 1'b0;
            excp_ismret      <= 1'b0;
            excp_cause      <= 32'd0;   
            excp_mtval      <= 32'd0;
        end else if (wb_token && !if_token) begin
            // IF: 同步RAM取指, 一拍后指令有效; 中间寄存器锁存PC
            if_pc           <= wb_pc;
            wb_token        <= 1'b0;
            if_token        <= 1'b1;
        end else if (if_token && !ifid_token) begin
            // ID: 译码中间寄存器中的指令
            ifid_pc          <= if_pc;
            ifid_regdata2    <= ifid_odata2_w;
            ifid_alusrc1     <= ifid_alusrc1_w;
            ifid_alusrc2     <= ifid_alusrc2_w;
            ifid_branch      <= ifid_branch_w;
            ifid_jump        <= ifid_jump_w;
            ifid_upper       <= ifid_upper_w;
            ifid_regdest     <= ifid_rd_w;
            ifid_ctl_alufunc <= ctl_alufunc_w;
            ifid_ctl_nextfunc<= ctl_nextfunc_w;
            ifid_ctl_wb      <= ctl_wb_w;
            ifid_ctl_memw    <= ctl_memw_w;
            ifid_ctl_regw    <= ctl_regw_w;
            ifid_ctl_csrw    <= ctl_csrw_w;
            ifid_ctl_peripsen <= ctl_peripsen_w;
            ifid_csr         <= ifid_csrdata_w;
            ifid_csraddr     <= ifid_csraddr_w;
            if_token         <= 1'b0;
            ifid_token       <= 1'b1;

            excp_token        <= ifid_ecall_w;
            excp_ismret       <= ifid_mret_w;
            excp_cause        <= ifid_mcause_w;
            excp_mtval        <= 32'd0; 
        end else if (ifid_token && !exe_token) begin
            exe_pc           <= ifid_pc;
            exe_regdata2     <= ifid_regdata2;
            exe_alures       <= exe_res_w;
            exe_nextpc       <= exe_next_pc_w;
            exe_upper        <= ifid_upper;
            exe_regdest      <= ifid_regdest;
            exe_ctl_wb       <= ifid_ctl_wb;
            exe_ctl_memw     <= ifid_ctl_memw;
            exe_ctl_regw     <= ifid_ctl_regw;
            exe_ctl_csrw     <= ifid_ctl_csrw;
            exe_ctl_peripsen <= ifid_ctl_peripsen;
            exe_csr          <= ifid_csr;
            exe_csraddr      <= ifid_csraddr;
            ifid_token       <= 1'b0;
            exe_token        <= 1'b1;
        end else if (exe_token && !perips_token) begin
            perips_req <= 1'b0;
            if (exe_ctl_peripsen && !perips_pending) begin
                // 发送 req 脉冲，等待 perips 完成
                perips_pending <= 1'b1;
                perips_req     <= 1'b1;
            end else if (exe_ctl_peripsen && perips_pending && perips_done) begin
                // perips 完成，捕获数据并传递 token
                perips_pc        <= exe_pc;
                perips_alures    <= exe_alures;
                perips_upper     <= exe_upper;
                perips_nextpc    <= exe_nextpc;
                perips_data      <= perips_data_w;
                perips_regdest   <= exe_regdest;
                perips_ctl_wb    <= exe_ctl_wb;
                perips_ctl_regw  <= exe_ctl_regw;
                perips_ctl_csrw  <= exe_ctl_csrw;
                perips_csr       <= exe_csr;
                perips_csraddr   <= exe_csraddr;
                perips_pending   <= 1'b0;
                exe_token        <= 1'b0;
                perips_token     <= 1'b1;
            end else if (!exe_ctl_peripsen) begin
                // 不需要 perips，直接传递
                perips_pc        <= exe_pc;
                perips_alures    <= exe_alures;
                perips_upper     <= exe_upper;
                perips_nextpc    <= exe_nextpc;
                perips_data      <= perips_data_w;
                perips_regdest   <= exe_regdest;
                perips_ctl_wb    <= exe_ctl_wb;
                perips_ctl_regw  <= exe_ctl_regw;
                perips_ctl_csrw  <= exe_ctl_csrw;
                perips_csr       <= exe_csr;
                perips_csraddr   <= exe_csraddr;
                exe_token        <= 1'b0;
                perips_token     <= 1'b1;
            end
        end else if (perips_token && !wb_token ) begin
                wb_pending <= 1'b1;
                perips_token <= 1'b0;
        end else if (wb_pending && !wb_token) begin
                wb_pc            <= wb_pc_w;
                wb_token         <= 1'b1; 
                wb_pending       <= 1'b0;
        end
    end

endmodule
