---
permalink: /zh/learn/01-hardware-basics/11-fpga-deployment/
---
# 11. FPGA 综合与部署

## 1. 硬件平台

- **开发板**：Altera EP4CE10 （Cyclone IV E）。
- **综合工具**：Quartus Prime 25.1 Standard Edition。
- **仿真工具**：ModelSim 20.1。
- **时钟**：板上 50MHz，`top.v` 端口 `clk`。
- **复位**：按键 `rst_n` 低有效，`top.v:17-26` 做 20ms 消抖（`rst_cnt` 计到 1,000,000）。

## 2. 顶层结构（src/top.v）

```verilog
module top (input clk, input rst_n, input uart_rx, output uart_tx, output [3:0] gpio);
    // 1. rst 消抖
    // 2. core_ctl 实例化（把 UART/GPIO 引脚接进核心）
    core_ctl u_core_ctl(.clk(clk), .rst(rst_debounced),
                        .uart_rx(uart_rx), .uart_tx(uart_tx), .gpio(gpio));
endmodule
```

`core_ctl` 内部通过 `core_perips` 把 UART/GPIO 接到 AXI 总线与外设 IP。

## 3. ModelSim 仿真

### 3.1 一键运行（simulation/modelsim/sim.do）

```tcl
vlib verilog_libs/...              # 编译 Altera 库（altera_primitives 等）
vlog -vlog01compat +incdir+d:/yscore/src \
     {d:/yscore/src/core_ctl.v} ... {d:/yscore/src/clint.v}   # 编译全部 RTL
vlog +incdir+d:/yscore/tb {d:/yscore/tb/mycpu_sim.v}
vsim -t 1ps ... mycpu_sim
add wave *
view structure
run -all
```

用法：在 ModelSim 里 `cd d:/yscore/simulation/modelsim`，`do sim.do`。

### 3.2 tb 特性（tb/mycpu_sim.v）

- 10ns 时钟（`#5 dclk = ~dclk`，`mycpu_sim.v:433`），默认跑 `SIM_CYCLES=1000000`。
- **寄存器/CSR 快照**：每周期采样 32 个 GPR + 9 个 CSR，检测变化并打印
  （`detect_register_changes`，`mycpu_sim.v:436-493`），给出"谁变了、PC 在哪、什么指令"。
- **指令名反汇编**：`get_instr_name` 把机器码翻译成可读指令（`mycpu_sim.v:104-258`）。
- **断点**：`+STOP_PC=0x80000214` 命令行覆盖，跑到指定 WB 地址自动 `$finish`
  （`mycpu_sim.v:357`、`394-400`）。
- **层次信号引出**：token、AXI 握手、CSR、CLINT mtime 等全部引出方便看波形。

## 4. 内存初始化流程

1. `ninja`（rtos 工程）编译出 `MiniRTOS.elf`。
2. `ninja dasm` → `MiniRTOS_shturl.txt` 反汇编。
3. `ninja bin` → `MiniRTOS_text.bin` / `MiniRTOS_data.bin`。
4. `ninja mem` → `imem.mem` + `dmem0~3.mem`（`bin2mem.py`）。
5. 硬件 `$readmemh` 加载：
   - `core_if.v:11` 读 `D:\yscore\rtos\build\imem.mem`（指令）。
   - `mem_cell.v:15` 四个 cell 读 `dmem0~3.mem`（数据）。

## 5. 上板流程

1. Quartus 打开工程（`yscore.qpf`），编译综合。
2. 检查时序：`time.sdc` 约束（50MHz 时钟）。
3. Programmer 烧录 `yscore.sof`。
4. 串口终端（如 PuTTY）连接 UART，115200，8N1。
5. 开机应看到 banner 与 `RV32> ` 提示符，LED 每 500ms 闪烁。

## 6. 资源占用

- EP4CE10（Cyclone IV E）：约 10K LE。
- 指令存储 18KB：`core_if.v` 用 1~2 个 M9K。
- 数据存储 24KB：`mem_cell.v` 4 个 6KB M9K。
- 详细数据可在 Quartus 编译报告的 "Resource Utilization" 里查看
  （LE / 寄存器 / M9K 块 / 引脚）。

## 7. 常见部署问题

- **上板正常但 ModelSim 正常**：多半是内存初始化路径错误（`$readmemh` 的绝对路径）。
- **复位后状态不定**：确认 `rst_debounced` 在按键按下 20ms 后才释放，
  `regfile.v`/`regfile_csr.v` 都是异步复位。
- **时序不收敛**：检查 `time.sdc`，必要时在 `core_perips` 的 AXI 路径上打拍。
- **LED 全亮**：`gpio_data_out` 复位为 0（低电平点亮=全亮），是"软件还没跑起来"的信号
  ——用于判断是否卡在早期初始化。
