# 03. Load / Store 指令

## 1. 编码定义

- Load opcode = `7'b0000011`，funct3 区分 LB/LH/LW/LBU/LHU（`src/rvdef.vh:65-69`）。
- Store opcode = `7'b0100011`，funct3 区分 SB/SH/SW（`src/rvdef.vh:70-72`）。
- S 型立即数 `offset = {ins[31:25], ins[11:7]}`，用 `OPT_IE_OFFSET` 符号扩展。

## 2. 数据通路

### 2.1 地址计算

Load/Store 的地址 = `rs1 + 符号扩展的立即数`，所以 `src/ctl_exe.v:61-66` 统一 `alu_func = ALU_ADD`。

### 2.2 是否进入 PERIPS

`src/ctl_perips.v:21-33`：Load/Store 的 `peripsen = 1`（需要访存），
Store 同时给出 `mem_write`（`MEM_W_B/H/W`）：

```verilog
OP_STORE: begin
    peripsen = 1'b1;
    case (funct3)
        FUNC3_SB: mem_write = MEM_W_B;
        FUNC3_SH: mem_write = MEM_W_H;
        FUNC3_SW: mem_write = MEM_W_W;
    endcase
end
OP_LOAD: begin
    peripsen = 1'b1;
end
```

### 2.3 PERIPS 阶段的访存流程

`src/core_ctl.v:406-443` 的 EXE→PERIPS 拍：

```verilog
else if (exe_token && !perips_token) begin
    perips_req <= 1'b0;
    if (exe_ctl_peripsen && !perips_pending) begin
        perips_pending <= 1'b1;
        perips_req     <= 1'b1;      // 发出 req 脉冲
    end else if (exe_ctl_peripsen && perips_pending && perips_done) begin
        perips_data <= perips_data_w;  // 捕获读取数据
        ...
        perips_token <= 1'b1;          // 推进到 WB
    end
    ...
end
```

`core_perips` 根据 `adr[31]` 译码（`src/core_perips.v:24-27`）：数据存储器 `is_mem` 走
`mem_ctl`（固定 1 拍，`mem_busy_r`/`mem_done_r`，见 `src/core_perips.v:48-63`）。

## 3. 数据存储器：mem_ctl（滚筒式字节 bank）

`src/mem_ctl.v` 是本项目内存实现的核心，设计演进详见 `03-debug-pitfalls/01`。要点：

### 3.1 拆成 4 个独立字节 bank

24KB = 4 × 6KB（每个 `mem_cell.v` 深度 6144，M9K）。原因是 **M9K 只有单口**，
且综合工具对"一个存储器同时支持 8/16/32 位读写"支持不好，所以拆成 4 个 8 位存储单元，
每个单元独立控制写使能 `we[0..3]`。

### 3.2 写使能生成（src/mem_ctl.v:19-33）

```verilog
case(wen)
    2'b01: we = 4'b1 << offset;               // SB
    2'b10: case(offset)                        // SH
        2'b00: we = 4'b0011;
        2'b01: we = 4'b0110;
        2'b10: we = 4'b1100;
        2'b11: we = 4'b1001;                  // ★跨字边界
    endcase
    2'b11: we = 4'b1111;                       // SW
endcase
```

注意 SH 的 `offset==2'b11` 时 `we=1001`：半字跨越两个字边界，第 0 字节落在下一字。
这正是当初调试踩过的坑（掩码写错一位）。

### 3.3 数据桶形移位（src/mem_ctl.v:36-50）

写入数据按 `offset` 旋转，保证每个字节落到正确的 bank：

```verilog
2'b00: wdata_shifted = idata;
2'b01: wdata_shifted = {idata[23:0], idata[31:24]};
2'b10: wdata_shifted = {idata[15:0], idata[31:16]};
2'b11: wdata_shifted = {idata[7:0],  idata[31:8]};
```

### 3.4 字节地址（src/mem_ctl.v:52-88）

每个 bank 的地址 `mem_addr[i] = base_addr + ((offset + i) >= 4 ? 1 : 0)`，
处理跨字边界的半字/字节访问。这是整个模块"最核心"的一段注释。

### 3.5 读出桶形右移（src/mem_ctl.v:134-149）

4 个 bank 拼回 `rdata_rotated` 后按 `offset` 右移还原字节序。

## 4. 写回

`src/ctl_wb.v:30-42` 依据 funct3 选择 Load 的符号扩展方式：

```verilog
OP_LOAD: begin
    reg_write = 1;
    case (funct3)
        FUNC3_LB:  opt_wb = OPT_WB_LB;    // 符号扩展
        FUNC3_LBU: opt_wb = OPT_WB_LBU;   // 零扩展
        FUNC3_LH:  opt_wb = OPT_WB_LH;
        FUNC3_LHU: opt_wb = OPT_WB_LHU;
        FUNC3_LW:  opt_wb = OPT_WB_LW;
    endcase
end
```

`src/core_wb.v:31-36` 对应实现符号/零扩展。Store 不写回寄存器（`reg_write = 0`）。

## 5. 测试：ins/LS.s

`ins/LS.s` 覆盖 SW/LW、SH/LHU、SB/LBU、LH/LB 符号扩展、以及**跨字节混合访问**：

```asm
li x10,0x80000000
li x5,0x12345678
sw x5,0(x10)
lw x6,0(x10)            # EXPECT: x6 = 0x12345678
...
li x5,-2
sh x5,12(x10)
lh x6,12(x10)           # EXPECT: x6 = 0xfffffffe（符号扩展）
...
sw x5,20(x10)           # x5 = 0xaabbccdd
lb  x6,20(x10)          # EXPECT: 0xffffffdd
lbu x7,21(x10)          # EXPECT: 0x000000cc
lh  x8,20(x10)          # EXPECT: 0xffffccdd
lhu x9,22(x10)          # EXPECT: 0x0000aabb
```

最后检查 x5~x9 寄存器值即可确认 8/16/32 位读写全部正确。

## 6. 易错点

- **SW 覆盖写**：`we = 4'b1111` 无条件写满 4 字节，地址不对齐时仍会跨字（本项目直接支持）。
- **SH 跨字边界**（offset=3）是测试死角，必须用混合用例覆盖。
- **Load 符号扩展**：LB/LH 要按最高位扩展，LBU/LHU 要零扩展，`core_wb.v` 的 case 不能写错。
- **PERIPS 等待**：Load 必须等 `perips_done` 再推进，否则读到的是上一拍数据。
