---
permalink: /learn/01-hardware-basics/12-tb-simulation-guide/
lang: en
---
# 12. Simulation Testbench tb/mycpu_sim.v

> This article details the principles and usage of the project's only simulation testbench `tb/mycpu_sim.v`,
> and how to run it in one click with `simulation/modelsim/sim.do`.
> It is the basic tool for every class of hardware instruction test and every "run-crash localization".

---

## 1. Summary in One Sentence

`mycpu_sim.v` instantiates the core under test `core_ctl`, generates a 10ns clock, **samples the 32 general-purpose registers
and 9 CSRs every cycle**, detects changes, and prints "which register/CSR changed, at which instruction, at what PC",
while also providing **instruction disassembly** and **PC breakpoints**. When finished, it automatically prints the final register/CSR snapshot.

```
        tb/mycpu_sim.v                    core under test
   ┌────────────────────┐           ┌──────────────┐
   │ clock/reset gen    │           │   core_ctl    │
   │ instr disasm (func)│  dclk     │              │
   │ reg/CSR snapshot   │ ────────→ │  u_regfile    │
   │ change detect+print│           │  u_regfile_csr│
   │ PC breakpoint stop │           │  u_core_perips│
   └────────────────────┘           └──────────────┘
        ↑ hierarchical access dut.* (waveform/signal exposure)
```

## 2. Clock and Reset (mycpu_sim.v:327-433)

```verilog
initial begin
    dclk = 0; rst = 0;
    ...
    #20;  rst = 1;        // reset for the first 20ns, then release
    repeat(SIM_CYCLES) begin
        #10;              // one cycle every 10ns
        ...
    end
    $finish;
end
always #5 dclk = ~dclk;   // 5ns toggle → 10ns period (100MHz simulation clock)
```

- **Reset**: `rst=1` is released after `#20` (the first 20ns is reset low).
- **Cycle count**: default `SIM_CYCLES = 1000000` (`mycpu_sim.v:95`) — 1 million cycles.
  This scale covers one complete UART transmit/receive window (the "seconds" in simulation are virtual time, unrelated to baud rate).

## 3. Core Instantiation and Hierarchical Signal Exposure (mycpu_sim.v:13-77)

```verilog
core_ctl dut(
    .clk(dclk), .rst(rst), .uart_rx(rx), .uart_tx(tx), .gpio(gpio)
);
```

Via **hierarchical access** `dut.<internal signal>`, internal nets are brought out to the tb top level for easy printing and waveform viewing:

| Category | Exposed signals (`dut.*`)                                                                               |
| -------- | ----------------------------------------------------------------------------------------------------- |
| token    | `wb_token` `if_token` `ifid_token` `exe_token` `perips_token` `excp_token`                |
| pipeline | `wb_pc` `ifid_alusrc1/2` `exe_alures` `perips_data` `wb_reg_w` `wb_csr_w` `wb_csrwen_w` |
| CSR      | `csr_mtvec` `csr_mepc` `csr_intrpt_w`                                                           |
| peripheral | `u_core_perips.u_clint.mtime` / `mtimecmp` (64-bit), `perips_mtip_w`                            |
| state    | `perips_req` `perips_pending` `perips_done` `perips_busy`                                     |
| decode   | `u_core_perips.is_mem` `is_uart` `is_gpio`                                                      |
| AXI      | `axil_awvalid/awready/wvalid/wready/bvalid/bready/arvalid/arready/rvalid/rready/rdata`              |
| instruction | `ifid_ins_w` (current instruction) `ctl_alufunc_w` `ctl_alusrc2_w` `exe_res_w`                           |

> These nets all appear in the ModelSim waveform window with `add wave *`,
> and are the key to "checking beat by beat against the expected waveform" (see `00-design-flow.md`).

## 4. Instruction Disassembly: get_instr_name (mycpu_sim.v:104-258)

A purely combinational function that translates a 32-bit machine code into a readable instruction name (including register numbers):

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
        7'b1110011: ...              // CSR + ECALL/EBREAK recognition
        ...
```

Supporting functions:

- `get_alu_name` (`mycpu_sim.v:261-280`): ALU function name (ADD/SUB/SLL/...).
- `get_reg_name` (`mycpu_sim.v:283-324`): register number → ABI name (x0=zero, x1=ra, x2=sp...).

**Purpose**: when printing "which instruction changed which register", it directly shows `ADD x15, x1, x2` instead of raw machine code,
which combined with the PC makes the execution flow easy to read.

## 5. Core Monitoring: Per-Cycle Sampling + Change Detection (mycpu_sim.v:371-401, 436-493)

The main loop each cycle:

```verilog
repeat(SIM_CYCLES) begin
    trace_pc  = wb_pc;           // latch this cycle's "currently writing back" PC/instruction/ALU
    trace_ins = IM_ins;
    trace_alu_func = CTL_alu_func;
    trace_opt_alusrc = CTL_opt_alusrc;
    trace_alu_res = ALU_res;
    #10;
    cycle_count = cycle_count + 1;
    for (i=0;i<32;i=i+1) regfile_new[i] = dut.u_regfile.regfile[i];   // snapshot GPR
    for (i=0;i<9;i=i+1)  csr_new[i]    = dut.u_regfile_csr.csr[i];    // snapshot CSR
    detect_register_changes();       // detect changes and print
end
```

`detect_register_changes` (`mycpu_sim.v:436-493`):

- Compares each register/CSR against the previous cycle's snapshot, and prints on change:
  ```
  [CYCLE 123] PC: 0x00000014 | Instruction: ADD    x15, x1, x2
  ALU_func: ADD, ALU_result: 0x00000019
  s1 (x9): 0x00000001 --> 0x00000002 [1-->2]
  ```
- **Ignores x0** (`j != 0`, `mycpu_sim.v:445`).
- Only prints the instruction line on the beat where something changed (`changed_count == 1`, `mycpu_sim.v:447,466`),
  to avoid spamming every cycle.

## 6. PC Breakpoint: STOP_PC (mycpu_sim.v:98-101, 356-362, 394-400)

Two ways to set it:

```verilog
parameter [31:0] STOP_PC = 32'hffffffff;   // default: don't stop by PC
```

1. **Change the parameter**: change `STOP_PC` to the target address; when it reaches that PC (write-back stage) it automatically does `$finish`.
2. **Command-line override** (without changing the file):

   ```tcl
   vsim ... +STOP_PC=0x80000214 mycpu_sim
   ```

   Parsed by `$value$plusargs("STOP_PC=0x%h", stop_pc_r)` (`mycpu_sim.v:357`).

Decision logic (`mycpu_sim.v:394-400`):

```verilog
if (stop_pc_r != 32'hFFFFFFFF && wb_pc == stop_pc_r) begin
    $display("[BREAK] Reached target PC = 0x%08h at cycle %0d", ...);
    disable sim_main;
end
```

**Usage**: find the address of the instruction you want to stop at in the disassembly (`ninja dasm`) (e.g. the help
branch of `shell_parse_line`), set STOP_PC, run to there, and print the register snapshot — the most direct way to localize "the state is wrong after a certain instruction executed".

## 7. Final Snapshot (mycpu_sim.v:404-428)

After running to completion or stopping at a breakpoint, it prints:

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

- Registers are shown in three columns: ABI name + hexadecimal + decimal.
- CSRs are shown by index (`csr[0]=mstatus, csr[2]=mie, csr[3]=mtvec, csr[5]=mepc, csr[6]=mcause...`).

**Verifying instruction tests**: assembly tests (RI.s/LS.s/branch.s...) all end with `x31` equal to a specific value
(1=pass, 0=fail); look at the value of `[t6] (x31)` in the final snapshot to determine pass/fail.

## 8. One-Click Run: simulation/modelsim/sim.do

### 8.1 What It Does

```tcl
transcript on
if ![file isdirectory verilog_libs] { file mkdir verilog_libs }

// 1. compile the Altera simulation libraries (M9K and other primitives need them)
vlib verilog_libs/altera_ver; vmap altera_ver ...
vlog ... {e:/quartus/.../altera_primitives.v}
vlib ... lpm_ver / sgate_ver / altera_mf_ver / altera_lnsim_ver / cycloneive_ver

// 2. clean and rebuild rtl_work
vdel -lib rtl_work -all; vlib rtl_work; vmap work rtl_work

// 3. compile all RTL (src/*.v, +incdir specifies the include path)
vlog -vlog01compat +incdir+d:/yscore/src {d:/yscore/src/core_ctl.v} ... {d:/yscore/src/clint.v}

// 4. compile the tb
vlog -vlog01compat +incdir+d:/yscore/tb {d:/yscore/tb/mycpu_sim.v}

// 5. start the simulation
vsim -t 1ps -L altera_ver ... -voptargs="+acc" mycpu_sim

// 6. open the waveform + run
add wave *
view structure
view signals
run -all
```

### 8.2 How to Run

```bash
cd d:/yscore/simulation/modelsim
vsim -do sim.do
```

Key points:

- **Must compile the Altera libraries first**: `mem_cell.v`/`core_if.v` use `(* ramstyle="M9K" *)`,
  which needs libraries such as `altera_mf_ver`/`cycloneive_ver` to simulate (the paths point to the Quartus installation directory).
- **`+incdir+d:/yscore/src`**: the search path for `$readmemh` and `include "rvdef.vh"`.
- **`-voptargs="+acc"`**: preserves hierarchical access capability; otherwise `dut.u_regfile.regfile[i]` is not accessible.
- **`-t 1ps`**: time precision of 1ps for more detailed waveforms.
