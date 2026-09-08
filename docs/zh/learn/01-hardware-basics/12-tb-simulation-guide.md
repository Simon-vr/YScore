---
permalink: /zh/learn/01-hardware-basics/12-tb-simulation-guide/
---
# 12. 仿真测试平台 tb/mycpu_sim.v

> 本文详细介绍本项目唯一的仿真测试平台 `tb/mycpu_sim.v` 的原理与用法，
> 以及如何用 `simulation/modelsim/sim.do` 一键跑起来。
> 这是每一类硬件指令测试、每一次"跑崩定位"的基础工具。

---

## 1. 一句话总结

`mycpu_sim.v` 例化了被测核 `core_ctl`，产生 10ns 时钟，**逐周期采样 32 个通用寄存器
与 9 个 CSR**，检测变化并打印"哪个寄存器/CSR 变了、在哪条指令、PC 是多少"，
同时提供**指令反汇编**与 **PC 断点**能力。跑完自动打印最终寄存器/CSR 快照。

```
        tb/mycpu_sim.v                    被测核
   ┌────────────────────┐           ┌──────────────┐
   │ 时钟/复位生成       │           │   core_ctl    │
   │ 指令反汇编(函数)    │  dclk     │              │
   │ 寄存器/CSR快照      │ ────────→ │  u_regfile    │
   │ 变化检测+打印       │           │  u_regfile_csr│
   │ PC断点停止          │           │  u_core_perips│
   └────────────────────┘           └──────────────┘
        ↑ 层次访问 dut.*（波形/信号引出）
```

## 2. 时钟与复位（mycpu_sim.v:327-433）

```verilog
initial begin
    dclk = 0; rst = 0;
    ...
    #20;  rst = 1;        // 前 20ns 复位，之后释放
    repeat(SIM_CYCLES) begin
        #10;              // 每 10ns 一个周期
        ...
    end
    $finish;
end
always #5 dclk = ~dclk;   // 5ns 翻转 → 10ns 周期（100MHz 仿真时钟）
```

- **复位**：`#20` 后 `rst=1` 释放（前 20ns 为复位低电平）。
- **周期数**：默认 `SIM_CYCLES = 1000000`（`mycpu_sim.v:95`）——100 万个周期。
  这个量级能覆盖一次完整的 UART 收发窗口（仿真里的"秒"是虚拟时间，与波特率无关）。

## 3. 被测核例化与层次信号引出（mycpu_sim.v:13-77）

```verilog
core_ctl dut(
    .clk(dclk), .rst(rst), .uart_rx(rx), .uart_tx(tx), .gpio(gpio)
);
```

通过 **层次访问** `dut.<内部信号>` 把内部线网引到 tb 顶层，便于打印与看波形：

| 类别   | 引出的信号（`dut.*`）                                                                               |
| ------ | ----------------------------------------------------------------------------------------------------- |
| token  | `wb_token` `if_token` `ifid_token` `exe_token` `perips_token` `excp_token`                |
| 流水线 | `wb_pc` `ifid_alusrc1/2` `exe_alures` `perips_data` `wb_reg_w` `wb_csr_w` `wb_csrwen_w` |
| CSR    | `csr_mtvec` `csr_mepc` `csr_intrpt_w`                                                           |
| 外设   | `u_core_perips.u_clint.mtime` / `mtimecmp`（64 位）、`perips_mtip_w`                            |
| 状态   | `perips_req` `perips_pending` `perips_done` `perips_busy`                                     |
| 译码   | `u_core_perips.is_mem` `is_uart` `is_gpio`                                                      |
| AXI    | `axil_awvalid/awready/wvalid/wready/bvalid/bready/arvalid/arready/rvalid/rready/rdata`              |
| 指令   | `ifid_ins_w`（当前指令）`ctl_alufunc_w` `ctl_alusrc2_w` `exe_res_w`                           |

> 这些线在 `add wave *` 时都会出现在 ModelSim 波形窗口，
> 是"对照设想波形逐拍核对"的关键（见 `00-design-flow.md`）。

## 4. 指令反汇编：get_instr_name（mycpu_sim.v:104-258）

一个纯组合函数，把 32 位机器码翻译成可读指令名（含寄存器号）：

```verilog
function [70*8:0] get_instr_name;
    input [31:0] ins;
    input [3:0] alu_func;
    input [1:0] opt_alusrc;
    ...
    case (opcode)
        7'b0110011: case (func10)
            10'b0000000_000: $sformat(name, "ADD    x%0d, x%0d, x%0d", rd, rs1, rs2);
            10'b0100000_000: $sformat(name, "SUB    ...");
            ...
        7'b0010011: case (funct3)   // I-type
            3'b000: $sformat(name, "ADDI   x%0d, x%0d, %0d", rd, rs1, $signed(imm12));
            ...
        7'b1100011: ...              // B-type
        7'b1110011: ...              // CSR + ECALL/EBREAK 识别
        ...
```

配套函数：

- `get_alu_name`（`mycpu_sim.v:261-280`）：ALU 功能名（ADD/SUB/SLL/...）。
- `get_reg_name`（`mycpu_sim.v:283-324`）：寄存器编号 → ABI 名（x0=zero, x1=ra, x2=sp...）。

**作用**：打印"哪条指令改了什么寄存器"时，直接显示 `ADD x15, x1, x2` 而不是裸机器码，
配合 PC 能快速读懂执行流。

## 5. 核心监控：逐周期采样 + 变化检测（mycpu_sim.v:371-401, 436-493）

主循环每周期：

```verilog
repeat(SIM_CYCLES) begin
    trace_pc  = wb_pc;           // 锁存本周期"正在写回"的 PC/指令/ALU
    trace_ins = IM_ins;
    trace_alu_func = CTL_alu_func;
    trace_opt_alusrc = CTL_opt_alusrc;
    trace_alu_res = ALU_res;
    #10;
    cycle_count = cycle_count + 1;
    for (i=0;i<32;i=i+1) regfile_new[i] = dut.u_regfile.regfile[i];   // 快照 GPR
    for (i=0;i<9;i=i+1)  csr_new[i]    = dut.u_regfile_csr.csr[i];    // 快照 CSR
    detect_register_changes();       // 检测变化并打印
end
```

`detect_register_changes`（`mycpu_sim.v:436-493`）：

- 对每个寄存器/CSR 与上一周期快照比较，有变化就打印：
  ```
  [CYCLE 123] PC: 0x00000014 | Instruction: ADD    x15, x1, x2
  ALU_func: ADD, ALU_result: 0x00000019
  s1 (x9): 0x00000001 --> 0x00000002 [1-->2]
  ```
- **忽略 x0**（`j != 0`，`mycpu_sim.v:445`）。
- 只有"变化的那一拍"才打印指令行（`changed_count == 1`，`mycpu_sim.v:447,466`），
  避免每个周期都刷屏。

## 6. PC 断点：STOP_PC（mycpu_sim.v:98-101, 356-362, 394-400）

两种设置方式：

```verilog
parameter [31:0] STOP_PC = 32'hffffffff;   // 默认不按 PC 停
```

1. **改参数**：把 `STOP_PC` 改成目标地址，跑到此 PC（写回阶段）自动 `$finish`。
2. **命令行覆盖**（不改文件）：

   ```tcl
   vsim ... +STOP_PC=0x80000214 mycpu_sim
   ```

   `$value$plusargs("STOP_PC=0x%h", stop_pc_r)`（`mycpu_sim.v:357`）解析。

判定逻辑（`mycpu_sim.v:394-400`）：

```verilog
if (stop_pc_r != 32'hFFFFFFFF && wb_pc == stop_pc_r) begin
    $display("[BREAK] Reached target PC = 0x%08h at cycle %0d", ...);
    disable sim_main;
end
```

**用法**：从反汇编（`ninja dasm`）里找到想停的指令地址（如 `shell_parse_line` 的 help
分支），设 STOP_PC，跑到那里打印寄存器快照——定位"某条指令执行后状态错"最直接。

## 7. 最终快照（mycpu_sim.v:404-428）

跑满或断点停止后，打印：

```
Total cycles executed: 1000000
Total instructions that have changed regfile: 1234

Final Register State:
  [zero] (x 0) = 0x00000000 =          0
  [ra  ] (x 1) = 0x00000000 =          0
  ...
Final CSR State:
  CSR[0] = 0x00001888 =       6280   ...
```

- 寄存器以 ABI 名 + 十六进制 + 十进制三列显示。
- CSR 按索引显示（`csr[0]=mstatus, csr[2]=mie, csr[3]=mtvec, csr[5]=mepc, csr[6]=mcause...`）。

**验证指令测试**：汇编测试（RI.s/LS.s/branch.s...）最后都让 `x31` 等于特定值
（1=pass, 0=fail），看最终快照里 `[t6] (x31)` 的值即可判断通过与否。

## 8. 一键运行：simulation/modelsim/sim.do

### 8.1 它做了什么

```tcl
transcript on
if ![file isdirectory verilog_libs] { file mkdir verilog_libs }

// 1. 编译 Altera 仿真库（M9K 等原语需要）
vlib verilog_libs/altera_ver; vmap altera_ver ...
vlog ... {e:/quartus/.../altera_primitives.v}
vlib ... lpm_ver / sgate_ver / altera_mf_ver / altera_lnsim_ver / cycloneive_ver

// 2. 清理并重建 rtl_work
vdel -lib rtl_work -all; vlib rtl_work; vmap work rtl_work

// 3. 编译全部 RTL（src/*.v，+incdir 指定 include 路径）
vlog -vlog01compat +incdir+d:/yscore/src {d:/yscore/src/core_ctl.v} ... {d:/yscore/src/clint.v}

// 4. 编译 tb
vlog -vlog01compat +incdir+d:/yscore/tb {d:/yscore/tb/mycpu_sim.v}

// 5. 启动仿真
vsim -t 1ps -L altera_ver ... -voptargs="+acc" mycpu_sim

// 6. 打开波形 + 跑
add wave *
view structure
view signals
run -all
```

### 8.2 怎么跑

```bash
cd d:/yscore/simulation/modelsim
vsim -do sim.do
```

要点：

- **必须先编译 Altera 库**：`mem_cell.v`/`core_if.v` 用了 `(* ramstyle="M9K" *)`，
  需要 `altera_mf_ver`/`cycloneive_ver` 等库才能仿真（路径指向 Quartus 安装目录）。
- **`+incdir+d:/yscore/src`**：`$readmemh` 与 `include "rvdef.vh"` 的查找路径。
- **`-voptargs="+acc"`**：保留层次访问能力，否则 `dut.u_regfile.regfile[i]` 访问不到。
- **`-t 1ps`**：时间精度 1ps，波形更精细。
