`timescale 1ns / 1ps

module mycpu_sim;

// ============ 时钟和复位信号 ============
reg dclk;
reg rst;
wire tx;
wire rx;
wire [3:0] gpio;

// ============ 实例化 core_ctl ============
core_ctl dut(
    .clk(dclk),
    .rst(rst),
    .uart_rx(rx),
    .uart_tx(tx),
    .gpio(gpio)
);

// UART RX 空闲为高电平
assign rx = 1'b1;

// ============ 波形监视信号（通过层次访问） ============
wire        excp_token   = dut.excp_token;
wire        excp_ismret  = dut.excp_ismret;
wire        wb_token      = dut.wb_token;
wire        if_token      = dut.if_token;
wire        ifid_token    = dut.ifid_token;
wire        exe_token     = dut.exe_token;
wire        perips_token  = dut.perips_token;

wire [31:0] wb_pc         = dut.wb_pc;
wire [31:0] ifid_alusrc1   = dut.ifid_alusrc1;
wire [31:0] ifid_alusrc2   = dut.ifid_alusrc2;
wire [31:0] exe_alures    = dut.exe_alures;
wire [31:0] perips_data   = dut.perips_data;
wire perips_ctl_regw      = dut.perips_ctl_regw;
wire [31:0] wb_reg_w      = dut.wb_reg_w;
wire [31:0] wb_csr_w      = dut.wb_csr_w;
wire [2:0]  wb_csrwen_w   = dut.wb_csrwen_w;
wire [31:0] csr_mtvec      = dut.csr_mtvec;
wire [31:0] csr_mepc       = dut.csr_mepc;
wire [63:0] clint_mtime    = dut.u_core_perips.u_clint.mtime;
wire [63:0] clint_mtimecmp = dut.u_core_perips.u_clint.mtimecmp;
wire        perips_mtip    = dut.perips_mtip_w;
wire        csr_intrpt     = dut.csr_intrpt_w;

// perips 状态信号
wire        perips_done    = dut.perips_done;
wire        perips_busy    = dut.perips_busy;
wire        perips_req     = dut.perips_req;
wire        perips_pending = dut.perips_pending;

// 地址译码选择信号
wire        is_mem         = dut.u_core_perips.is_mem;
wire        is_uart        = dut.u_core_perips.is_uart;
wire        is_gpio        = dut.u_core_perips.is_gpio;

// AXI-Lite 关键握手信号（内部线网）
wire        axil_awvalid   = dut.u_core_perips.s_axil_awvalid;
wire        axil_awready   = dut.u_core_perips.s_axil_awready;
wire        axil_wvalid    = dut.u_core_perips.s_axil_wvalid;
wire        axil_wready    = dut.u_core_perips.s_axil_wready;
wire        axil_bvalid    = dut.u_core_perips.s_axil_bvalid;
wire        axil_bready    = dut.u_core_perips.s_axil_bready;
wire        axil_arvalid   = dut.u_core_perips.s_axil_arvalid;
wire        axil_arready   = dut.u_core_perips.s_axil_arready;
wire        axil_rvalid    = dut.u_core_perips.s_axil_rvalid;
wire        axil_rready    = dut.u_core_perips.s_axil_rready;
wire [31:0] axil_rdata    = dut.u_core_perips.s_axil_rdata;

// 保留供 display 任务使用的信号
wire [31:0] IM_ins         = dut.ifid_ins_w;
wire [3:0]  CTL_alu_func   = dut.ctl_alufunc_w;
wire [1:0]  CTL_opt_alusrc = dut.ctl_alusrc2_w;
wire [31:0] ALU_res        = dut.exe_res_w;

// ============ CSR 快照数组（用于检测变化） ============
reg [31:0] csr_old[8:0];
reg [31:0] csr_new[8:0];

// ============ 寄存器快照数组（用于检测变化） ============
reg [31:0] regfile_old[31:0];
reg [31:0] regfile_new[31:0];
integer i;
integer cycle_count;
integer ins_count;
reg [31:0] trace_pc;
reg [31:0] trace_ins;
reg [3:0]  trace_alu_func;
reg [1:0]  trace_opt_alusrc;
reg [31:0] trace_alu_res;
reg [31:0] stop_pc_r;
localparam integer SIM_CYCLES = 1000000;

// ============ PC断点停止控制 ============
// 设置 STOP_PC 后，仿真运行到此 PC (写回阶段) 时自动 $finish
// 默认 32'hFFFFFFFF 表示不按 PC 停止，跑满 SIM_CYCLES
// 可通过命令行覆盖: +STOP_PC=0x80000214
parameter [31:0] STOP_PC = 32'hffffffff;

// ============ 指令名称查找表（RV32I完整指令集） ============
function [70*8:0] get_instr_name;
    input [31:0] ins;
    input [3:0] alu_func;
    input [1:0] opt_alusrc;
    reg [70*8:0] name;
    reg [6:0] opcode;
    reg [4:0] rd, rs1, rs2, funct3;
    reg [6:0] funct7;
    reg [9:0] func10;
    reg [19:0] imm20;
    reg [11:0] imm12;
    
    begin
        // 提取指令字段
        opcode  = ins[6:0];
        rd      = ins[11:7];
        funct3  = ins[14:12];
        rs1     = ins[19:15];
        rs2     = ins[24:20];
        funct7  = ins[31:25];
        func10  = {funct7, funct3};
        imm12   = ins[31:20];
        imm20   = ins[31:12];
        
        case (opcode)
            // ========== R-type (0110011) ==========
            7'b0110011: begin
                case (func10)
                    10'b0000000_000: $sformat(name, "ADD    x%0d, x%0d, x%0d", rd, rs1, rs2);
                    10'b0100000_000: $sformat(name, "SUB    x%0d, x%0d, x%0d", rd, rs1, rs2);
                    10'b0000000_001: $sformat(name, "SLL    x%0d, x%0d, x%0d", rd, rs1, rs2);
                    10'b0000000_101: $sformat(name, "SRL    x%0d, x%0d, x%0d", rd, rs1, rs2);
                    10'b0100000_101: $sformat(name, "SRA    x%0d, x%0d, x%0d", rd, rs1, rs2);
                    10'b0000000_111: $sformat(name, "AND    x%0d, x%0d, x%0d", rd, rs1, rs2);
                    10'b0000000_110: $sformat(name, "OR     x%0d, x%0d, x%0d", rd, rs1, rs2);
                    10'b0000000_100: $sformat(name, "XOR    x%0d, x%0d, x%0d", rd, rs1, rs2);
                    10'b0000000_010: $sformat(name, "SLT    x%0d, x%0d, x%0d", rd, rs1, rs2);
                    10'b0000000_011: $sformat(name, "SLTU   x%0d, x%0d, x%0d", rd, rs1, rs2);
                    default: $sformat(name, "R-UNK  x%0d, x%0d, x%0d [f10=%b]", rd, rs1, rs2, func10);
                endcase
            end
            
            // ========== I-type 立即数运算 (0010011) ==========
            7'b0010011: begin
                case (funct3)
                    3'b000: $sformat(name, "ADDI   x%0d, x%0d, %0d", rd, rs1, $signed(imm12));
                    3'b100: $sformat(name, "XORI   x%0d, x%0d, %0d", rd, rs1, $signed(imm12));
                    3'b110: $sformat(name, "ORI    x%0d, x%0d, %0d", rd, rs1, $signed(imm12));
                    3'b111: $sformat(name, "ANDI   x%0d, x%0d, %0d", rd, rs1, $signed(imm12));
                    3'b010: $sformat(name, "SLTI   x%0d, x%0d, %0d", rd, rs1, $signed(imm12));
                    3'b011: $sformat(name, "SLTIU  x%0d, x%0d, %0d", rd, rs1, $signed(imm12));
                    3'b001: $sformat(name, "SLLI   x%0d, x%0d, %0d", rd, rs1, rs2);
                    3'b101: begin
                        if (funct7 == 7'b0000000)
                            $sformat(name, "SRLI   x%0d, x%0d, %0d", rd, rs1, rs2);
                        else if (funct7 == 7'b0100000)
                            $sformat(name, "SRAI   x%0d, x%0d, %0d", rd, rs1, rs2);
                        else
                            $sformat(name, "SHIFT? x%0d, x%0d, %0d", rd, rs1, rs2);
                    end
                    default: $sformat(name, "I-UNK  x%0d, x%0d, %0d", rd, rs1, imm12);
                endcase
            end
            
            // ========== Load 指令 (0000011) ==========
            7'b0000011: begin
                case (funct3)
                    3'b000: $sformat(name, "LB     x%0d, %0d(x%0d)", rd, $signed(imm12), rs1);
                    3'b001: $sformat(name, "LH     x%0d, %0d(x%0d)", rd, $signed(imm12), rs1);
                    3'b010: $sformat(name, "LW     x%0d, %0d(x%0d)", rd, $signed(imm12), rs1);
                    3'b100: $sformat(name, "LBU    x%0d, %0d(x%0d)", rd, $signed(imm12), rs1);
                    3'b101: $sformat(name, "LHU    x%0d, %0d(x%0d)", rd, $signed(imm12), rs1);
                    default: $sformat(name, "LOAD?  x%0d, %0d(x%0d)", rd, $signed(imm12), rs1);
                endcase
            end
            
            // ========== S-type 存储指令 (0100111) ==========
            7'b0100111: begin
                case (funct3)
                    3'b000: $sformat(name, "SB     x%0d, %0d(x%0d)", rs2, $signed({ins[31:25], ins[11:7]}), rs1);
                    3'b001: $sformat(name, "SH     x%0d, %0d(x%0d)", rs2, $signed({ins[31:25], ins[11:7]}), rs1);
                    3'b010: $sformat(name, "SW     x%0d, %0d(x%0d)", rs2, $signed({ins[31:25], ins[11:7]}), rs1);
                    default: $sformat(name, "STORE? x%0d, %0d(x%0d)", rs2, $signed({ins[31:25], ins[11:7]}), rs1);
                endcase
            end
            
            // ========== B-type 分支指令 (1100011) ==========
            7'b1100011: begin
                case (funct3)
                    3'b000: $sformat(name, "BEQ    x%0d, x%0d, %0d", rs1, rs2, $signed({ins[31], ins[7], ins[30:25], ins[11:8]}));
                    3'b001: $sformat(name, "BNE    x%0d, x%0d, %0d", rs1, rs2, $signed({ins[31], ins[7], ins[30:25], ins[11:8]}));
                    3'b100: $sformat(name, "BLT    x%0d, x%0d, %0d", rs1, rs2, $signed({ins[31], ins[7], ins[30:25], ins[11:8]}));
                    3'b101: $sformat(name, "BGE    x%0d, x%0d, %0d", rs1, rs2, $signed({ins[31], ins[7], ins[30:25], ins[11:8]}));
                    3'b110: $sformat(name, "BLTU   x%0d, x%0d, %0d", rs1, rs2, $signed({ins[31], ins[7], ins[30:25], ins[11:8]}));
                    3'b111: $sformat(name, "BGEU   x%0d, x%0d, %0d", rs1, rs2, $signed({ins[31], ins[7], ins[30:25], ins[11:8]}));
                    default: $sformat(name, "BRANCH? x%0d, x%0d", rs1, rs2);
                endcase
            end
            
            // ========== U-type LUI (0110111) ==========
            7'b0110111: begin
                $sformat(name, "LUI    x%0d, 0x%h", rd, imm20);
            end
            
            // ========== U-type AUIPC (0010111) ==========
            7'b0010111: begin
                $sformat(name, "AUIPC  x%0d, 0x%h", rd, imm20);
            end
            
            // ========== J-type JAL (1101111) ==========
            7'b1101111: begin
                $sformat(name, "JAL    x%0d, %0d", rd, $signed({ins[31], ins[19:12], ins[20], ins[30:21]}));
            end
            
            // ========== JALR (1100111) ==========
            7'b1100111: begin
                $sformat(name, "JALR   x%0d, x%0d, %0d", rd, rs1, $signed(imm12));
            end
            
            // ========== FENCE (0001111) ==========
            7'b0001111: begin
                $sformat(name, "FENCE");
            end
            
            // ========== CSR 指令 (1110011) ==========
            7'b1110011: begin
                case (funct3)
                    3'b001: $sformat(name, "CSRRW  x%0d, 0x%03h, x%0d", rd, imm12[11:0], rs1);
                    3'b010: $sformat(name, "CSRRS  x%0d, 0x%03h, x%0d", rd, imm12[11:0], rs1);
                    3'b011: $sformat(name, "CSRRC  x%0d, 0x%03h, x%0d", rd, imm12[11:0], rs1);
                    3'b101: $sformat(name, "CSRRWI x%0d, 0x%03h, %0d", rd, imm12[11:0], rs1);
                    3'b110: $sformat(name, "CSRRSI x%0d, 0x%03h, %0d", rd, imm12[11:0], rs1);
                    3'b111: $sformat(name, "CSRRCI x%0d, 0x%03h, %0d", rd, imm12[11:0], rs1);
                    default: begin
                        if (ins == 32'b0)
                            $sformat(name, "NOP");
                        else if (ins == 32'h00000073)
                            $sformat(name, "ECALL");
                        else if (ins == 32'h00100073)
                            $sformat(name, "EBREAK");
                        else
                            $sformat(name, "SYSTEM 0x%08h", ins);
                    end
                endcase
            end
            
            // ========== 未知指令 ==========
            default: begin
                $sformat(name, "UNKNOWN 0x%08h [op=%b]", ins, opcode);
            end
        endcase
        
        get_instr_name = name;
    end
endfunction

// ============ ALU功能名称 ============
function [7*8:0] get_alu_name;
    input [3:0] func;
    reg [15*8:0] name;
    begin
        case (func)
            4'b0000: $sformat(name, "ADD");
            4'b0001: $sformat(name, "SUB");
            4'b0010: $sformat(name, "SLL");
            4'b0011: $sformat(name, "OR");
            4'b0100: $sformat(name, "AND");
            4'b0101: $sformat(name, "SLTU");
            4'b0110: $sformat(name, "SLT");
            4'b0111: $sformat(name, "XOR");
            4'b1000: $sformat(name, "SRL");
            4'b1001: $sformat(name, "SRA");
            default: $sformat(name, "UNKNOWN");
        endcase
        get_alu_name = name;
    end
endfunction

// ============ 寄存器名字映射（RISC-V标准命名） ============
function [3*8:0] get_reg_name;
    input [4:0] reg_num;
    reg [3*8:0] name;
    begin
        case (reg_num)
            0:  $sformat(name, "zero");
            1:  $sformat(name, "ra");
            2:  $sformat(name, "sp");
            3:  $sformat(name, "gp");
            4:  $sformat(name, "tp");
            5:  $sformat(name, "t0");
            6:  $sformat(name, "t1");
            7:  $sformat(name, "t2");
            8:  $sformat(name, "s0");
            9:  $sformat(name, "s1");
            10: $sformat(name, "a0");
            11: $sformat(name, "a1");
            12: $sformat(name, "a2");
            13: $sformat(name, "a3");
            14: $sformat(name, "a4");
            15: $sformat(name, "a5");
            16: $sformat(name, "a6");
            17: $sformat(name, "a7");
            18: $sformat(name, "s2");
            19: $sformat(name, "s3");
            20: $sformat(name, "s4");
            21: $sformat(name, "s5");
            22: $sformat(name, "s6");
            23: $sformat(name, "s7");
            24: $sformat(name, "s8");
            25: $sformat(name, "s9");
            26: $sformat(name, "s10");
            27: $sformat(name, "s11");
            28: $sformat(name, "t3");
            29: $sformat(name, "t4");
            30: $sformat(name, "t5");
            31: $sformat(name, "t6");
            default: $sformat(name, "x%d", reg_num);
        endcase
        get_reg_name = name;
    end
endfunction

// ============ 监控进程 ============
initial begin
    // 初始化
    dclk = 0;
    rst = 0;
    cycle_count = 0;
    ins_count = 0;
    trace_pc = 32'b0;
    trace_ins = 32'b0;
    trace_alu_func = 4'b0;
    trace_opt_alusrc = 2'b0;
    trace_alu_res = 32'b0;
    
    // 初始化寄存器快照
    for (i = 0; i < 32; i = i + 1) begin
        regfile_old[i] = 32'h0;
        regfile_new[i] = 32'h0;
    end
    for (i = 0; i < 9; i = i + 1) begin
        csr_old[i] = 32'h0;
        csr_new[i] = 32'h0;
    end
    
    $display("\n");
    $display("================================================================");
    $display("           RISC-V Single-Cycle CPU Simulation");
    $display("================================================================");
    $display("Simulation started at %0t", $time);
    $display("================================================================\n");

    // 命令行覆盖 STOP_PC
    if ($value$plusargs("STOP_PC=0x%h", stop_pc_r)) begin
        $display("[INFO] Override STOP_PC = 0x%08h (from command line)", stop_pc_r);
    end else begin
        stop_pc_r = STOP_PC;
        if (STOP_PC != 32'hFFFFFFFF)
            $display("[INFO] STOP_PC = 0x%08h (from parameter)", STOP_PC);
    end

    #20;
    rst = 1;
    $display("[START] CPU start execution\n");
    
    // 运行指定周期数（需足够覆盖UART发送窗口）
    begin: sim_main
        repeat(SIM_CYCLES) begin
            // 先锁存本周期将执行的指令信息，供写回后打印
            trace_pc = wb_pc;
            trace_ins = IM_ins;
            trace_alu_func = CTL_alu_func;
            trace_opt_alusrc = CTL_opt_alusrc;
            trace_alu_res = ALU_res;

            #10;  // 10ns周期
            cycle_count = cycle_count + 1;
            
            // 读取当前寄存器状态
            for (i = 0; i < 32; i = i + 1) begin
                regfile_new[i] = dut.u_regfile.regfile[i];
            end
            for (i = 0; i < 9; i = i + 1) begin
                csr_new[i] = dut.u_regfile_csr.csr[i];
            end
            
            // 检测寄存器变化
            detect_register_changes();

            // PC断点检测：写回阶段 PC 匹配时停止
            if (stop_pc_r != 32'hFFFFFFFF && wb_pc == stop_pc_r) begin
                $display("");
                $display("================================================================");
                $display("  [BREAK] Reached target PC = 0x%08h at cycle %0d", stop_pc_r, cycle_count);
                $display("================================================================");
                disable sim_main;
            end
        end
    end
    
    // 仿真统计
    $display("\n");
    $display("================================================================");
    $display("                  Simulation Summary");
    $display("================================================================");
    $display("Total cycles executed: %0d", cycle_count);
    $display("Total instructions that have changed regfile: %0d", ins_count);
    
    $display("\nFinal Register State:");
    $display("--------");
    for (i = 0; i < 32; i = i + 1) begin
            $display("  [%s] (x%2d) = 0x%08h = %10d", get_reg_name(i), i, regfile_new[i], $signed(regfile_new[i]));
        end
    $display("--------\n");

    $display("Final CSR State:");
    $display("--------");
    for (i = 0; i < 9; i = i + 1) begin
            $display("  CSR[%0d] = 0x%08h = %10d", i, csr_new[i], $signed(csr_new[i]));
        end
    $display("--------\n");
    
    $display("================================================================");
    $display("Simulation ended at %0t\n", $time);
    
    $finish;
end

// ============ 时钟生成 ============
always #5 dclk = ~dclk;

// ============ 寄存器变化检测 ============
task detect_register_changes;
    integer j;
    integer changed_count;
    
    begin
        changed_count = 0;
        
        // 每有寄存器变化就输出
        for (j = 0; j < 32; j = j + 1) begin
            if (regfile_new[j] != regfile_old[j] && j != 0) begin  // 忽略x0
                changed_count = changed_count + 1;
                if (changed_count == 1) begin
                    ins_count = ins_count + 1;
                    
                    $display("[CYCLE %0d] PC: 0x%08h | Instruction: %s",
                             cycle_count, trace_pc, get_instr_name(trace_ins, trace_alu_func, trace_opt_alusrc));
                    $display("ALU_func: %s, ALU_result: 0x%08h",
                             get_alu_name(trace_alu_func), trace_alu_res);
                end
                
                $display("%s (x%2d): 0x%08h --> 0x%08h [%d-->%d]",
                         get_reg_name(j), j, regfile_old[j], regfile_new[j],
                         $signed(regfile_old[j]), $signed(regfile_new[j]));
            end
        end
        
        // 检测CSR变化
        for (j = 0; j < 9; j = j + 1) begin
            if (csr_new[j] != csr_old[j]) begin
                changed_count = changed_count + 1;
                if (changed_count == 1) begin
                    ins_count = ins_count + 1;
                    
                    $display("[CYCLE %0d] PC: 0x%08h | Instruction: %s",
                             cycle_count, trace_pc, get_instr_name(trace_ins, trace_alu_func, trace_opt_alusrc));
                    $display("ALU_func: %s, ALU_result: 0x%08h",
                             get_alu_name(trace_alu_func), trace_alu_res);
                end
                
                $display("CSR[%0d]: 0x%08h --> 0x%08h [%d-->%d]",
                         j, csr_old[j], csr_new[j],
                         $signed(csr_old[j]), $signed(csr_new[j]));
            end
        end
        
        if (changed_count > 0) begin
            $display("");
        end
        
        // 更新快照
        for (j = 0; j < 32; j = j + 1) begin
            regfile_old[j] = regfile_new[j];
        end
        for (j = 0; j < 9; j = j + 1) begin
            csr_old[j] = csr_new[j];
        end
    end
endtask

endmodule
