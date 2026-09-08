# 01. R 指令（数据通路 + 控制通路）

## 1. 编码定义

R 型指令 opcode = `7'b0110011`，由 `funct7`（`ins[31:25]`）与 `funct3`（`ins[14:12]`）
组合成 10 位功能码 `func = {funct7, funct3}`。定义在 `src/rvdef.vh:23-37`：

```verilog
`define FUNC_ADD   10'b0000000_000
`define FUNC_SUB   10'b0100000_000
`define FUNC_AND   10'b0000000_111
...
```

## 2. 数据通路

### 2.1 取指（IF）

`src/core_if.v`：同步读指令存储器，`ins_mem[0:4607]` 共 4608 条（18KB，M9K），
`$readmemh` 从 `rtos\build\imem.mem` 加载。`ins_adr[31:2]` 取字地址。

`core_ctl` 的 IF 拍（`src/core_ctl.v:359-363`）：

```verilog
else if (wb_token && !if_token) begin
    if_pc <= wb_pc;
    wb_token <= 1'b0;
    if_token <= 1'b1;
end
```

因为 M9K 是同步读，先锁存 PC，下一拍 `core_if` 输出指令。

### 2.2 译码（ID）

`src/core_id.v` 拆字段并扩展立即数：

- `rd = ins[11:7]`，`rs1 = ins[19:15]`，`rs2 = ins[24:20]`。
- 寄存器堆 `src/regfile.v`：`odata1 = regfile[rs1]`，`odata2 = regfile[rs2]`（组合读）。

R 指令不涉及立即数，`opt_ie` 走默认的 `OPT_IE_IU`。

### 2.3 运算（EXE）

`src/core_exe.v` 例化 `exe_alu` 与 `exe_next`。R 指令两个源都来自寄存器堆，
ALU 第二个操作数选择 `opt_alusrc2 = OPT_ALUSRC_REG`（`src/ctl_ifid.v:34` 默认值）。

`src/exe_alu.v` 的关键：**用 33 位 `res` 保留进位/借位**：

```verilog
ALU_ADD:  res = {1'b0, data1} + {1'b0, data2};
ALU_SUB:  res = {1'b0, data1} - {1'b0, data2};
...
carry   = (func == ALU_SUB) ? (~res[32]) : res[32]; // SUB看借位
overflow = low_res[31] ^ res[32];
```

R 指令的 `next_func` 是 `NEXT_SEQ`（顺序执行，下一 PC = `cur_pc + 4`，见 `src/exe_next.v:17`）。

### 2.4 写回（WB）

`src/core_wb.v` 按 `opt_wb` 选择回写数据。R 指令 `opt_wb = OPT_WB_ALU`（默认值），
`wbreg = alures`。`src/regfile.v` 在 `perips_token && perips_ctl_regw` 时写入（`src/core_ctl.v:147`）。

## 3. 控制通路

R 指令在 `src/ctl_ifid.v` 里**不需要任何特判**（opcode 落到 default，全部默认值即可），
真正的 ALU 功能由 `src/ctl_exe.v:26-39` 依据 `func` 给出：

```verilog
OP_RTYPE: begin
    case (func)
        FUNC_ADD:  alu_func = ALU_ADD;
        FUNC_SUB:  alu_func = ALU_SUB;
        ...
        FUNC_SLTU: alu_func = ALU_SLTU;
    endcase
end
```

`src/ctl_wb.v:24-25` 给 R 指令 `reg_write = 1`，`csr_write = 0`。

## 4. 流水线推进（token）

`src/core_ctl.v:390-405` 的 EXE 拍把 ifid 阶段锁存的 ALU 源与结果推进到 exe 阶段：

```verilog
else if (ifid_token && !exe_token) begin
    exe_pc <= ifid_pc;
    exe_alures <= exe_res_w;      // 组合结果，本拍沿锁存
    exe_nextpc <= exe_next_pc_w;
    ...
    ifid_token <= 1'b0;
    exe_token <= 1'b1;
end
```

R 指令无访存，`exe_ctl_peripsen = 0`，PERIPS 阶段直接透传（`src/core_ctl.v:428-443`）。

## 5. 测试：ins/RI.s

`ins/RI.s` 覆盖了所有 I 型与 R 型指令（ADDI/SLTI/XORI/.../ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND）。
每条指令旁有 `# EXPECT: 寄存器值` 注释。例如：

```asm
addi x1,x0,10
addi x2,x1,5
# EXPECT: x2 = 15
...
and x31,x5,x7
# EXPECT: 0x55   ← 最终看 x31 判断整体通过
```

验证方法（二选一）：

1. **ModelSim**：把 RI.s 汇编→链接→objcopy 出 `imem.bin`，`bin2mem.py` 转 `imem.mem`，
   跑 `sim.do`，在 tb 的最终寄存器快照里看 `x31 = 0x55`（`tb/mycpu_sim.v:412-417`）。
2. **波形**：`add wave *` 后直接观察 `exe_alures`、`regfile` 变化。

> 💡 仿真平台的完整用法（时钟/复位、寄存器快照、指令反汇编、`STOP_PC` 断点、
> `sim.do` 一键运行）见 **`12-tb-simulation-guide.md`**。

## 6. 常见错误排查点

- **结果 0 或乱值**：优先查 `ctl_alufunc_w`（`src/ctl_exe.v`）是否正确，再查 ALU 源选择
  `ifid_alusrc1/2`（`src/ctl_ifid.v` 的 `opt_alusrc2`）。
- **写不进寄存器**：查 `perips_ctl_regw` 是否在 WB 退休拍为 1，以及 `wb_reg_w` 选择是否 `OPT_WB_ALU`。
- **下一 PC 错误**：查 `exe_next` 的 `next_func`（R 指令应为 `NEXT_SEQ`）。
