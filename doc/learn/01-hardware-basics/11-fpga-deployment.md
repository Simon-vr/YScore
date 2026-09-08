---
permalink: /learn/01-hardware-basics/11-fpga-deployment/
lang: en
---
# 11. FPGA Synthesis and Deployment

## 1. Hardware Platform

- **Development board**: Altera EP4CE10 (Cyclone IV E).
- **Synthesis tool**: Quartus Prime 25.1 Standard Edition.
- **Simulation tool**: ModelSim 20.1.
- **Clock**: 50MHz on the board, `clk` port of `top.v`.
- **Reset**: button `rst_n` active-low; `top.v:17-26` performs 20ms debouncing (`rst_cnt` counts to 1,000,000).

## 2. Top-Level Structure (src/top.v)

```verilog
module top (input clk, input rst_n, input uart_rx, output uart_tx, output [3:0] gpio);
    // 1. rst debounce
    // 2. core_ctl instantiation (wire the UART/GPIO pins into the core)
    core_ctl u_core_ctl(.clk(clk), .rst(rst_debounced),
                        .uart_rx(uart_rx), .uart_tx(uart_tx), .gpio(gpio));
endmodule
```

Inside, `core_ctl` connects UART/GPIO to the AXI bus and the peripheral IPs through `core_perips`.

## 3. ModelSim Simulation

### 3.1 One-Click Run (simulation/modelsim/sim.do)

```tcl
vlib verilog_libs/...              # compile Altera libraries (altera_primitives, etc.)
vlog -vlog01compat +incdir+d:/yscore/src \
     {d:/yscore/src/core_ctl.v} ... {d:/yscore/src/clint.v}   # compile all RTL
vlog +incdir+d:/yscore/tb {d:/yscore/tb/mycpu_sim.v}
vsim -t 1ps ... mycpu_sim
add wave *
view structure
run -all
```

Usage: in ModelSim `cd d:/yscore/simulation/modelsim`, then `do sim.do`.

### 3.2 tb Features (tb/mycpu_sim.v)

- 10ns clock (`#5 dclk = ~dclk`, `mycpu_sim.v:433`), runs `SIM_CYCLES=1000000` by default.
- **Register/CSR snapshots**: samples the 32 GPRs + 9 CSRs every cycle, detects changes, and prints
  (`detect_register_changes`, `mycpu_sim.v:436-493`), giving "what changed, where the PC is, what instruction".
- **Instruction-name disassembly**: `get_instr_name` translates machine code into readable instructions (`mycpu_sim.v:104-258`).
- **Breakpoints**: `+STOP_PC=0x80000214` command-line override; when the specified WB address is reached it automatically does `$finish`
  (`mycpu_sim.v:357`, `394-400`).
- **Hierarchical signal exposure**: tokens, AXI handshakes, CSR, CLINT mtime, etc. are all brought out for easy waveform viewing.

## 4. Memory Initialization Flow

1. `ninja` (the rtos project) compiles out `MiniRTOS.elf`.
2. `ninja dasm` → `MiniRTOS_shturl.txt` disassembly.
3. `ninja bin` → `MiniRTOS_text.bin` / `MiniRTOS_data.bin`.
4. `ninja mem` → `imem.mem` + `dmem0~3.mem` (`bin2mem.py`).
5. Hardware `$readmemh` loading:
   - `core_if.v:11` reads `D:\yscore\rtos\build\imem.mem` (instructions).
   - `mem_cell.v:15` — the four cells read `dmem0~3.mem` (data).

## 5. On-Board Flow

1. Open the project in Quartus (`yscore.qpf`), compile and synthesize.
2. Check timing: `time.sdc` constraints (50MHz clock).
3. Program `yscore.sof` with the Programmer.
4. Connect a serial terminal (e.g. PuTTY) to the UART, 115200, 8N1.
5. On power-up you should see the banner and the `RV32> ` prompt, with the LED blinking every 500ms.

## 6. Resource Usage

- EP4CE10 (Cyclone IV E): about 10K LE.
- Instruction memory 18KB: `core_if.v` uses 1~2 M9Ks.
- Data memory 24KB: `mem_cell.v` 4 × 6KB M9Ks.
- Detailed figures can be viewed in the "Resource Utilization" section of the Quartus compilation report
  (LE / registers / M9K blocks / pins).

## 7. Common Deployment Problems

- **Works on the board but ModelSim works too**: most likely a wrong memory initialization path (the absolute path in `$readmemh`).
- **Undefined state after reset**: confirm that `rst_debounced` is only released 20ms after the button is pressed;
  `regfile.v`/`regfile_csr.v` are both asynchronously reset.
- **Timing not converging**: check `time.sdc`; if necessary, pipeline the AXI path in `core_perips`.
- **All LEDs on**: `gpio_data_out` resets to 0 (active-low = all on), a signal that "software hasn't started yet"
  — used to determine whether it is stuck in early initialization.
