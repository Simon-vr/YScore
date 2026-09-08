---
permalink: /learn/01-hardware-basics/03-ls-instructions/
lang: en
---
# 03. Load / Store Instructions

## 1. Encoding Definition

- Load opcode = `7'b0000011`, funct3 distinguishes LB/LH/LW/LBU/LHU (`src/rvdef.vh:65-69`).
- Store opcode = `7'b0100011`, funct3 distinguishes SB/SH/SW (`src/rvdef.vh:70-72`).
- S-type immediate `offset = {ins[31:25], ins[11:7]}`, sign-extended using `OPT_IE_OFFSET`.

## 2. Data Path

### 2.1 Address Calculation

The Load/Store address = `rs1 + sign-extended immediate`, so `src/ctl_exe.v:61-66` uniformly sets `alu_func = ALU_ADD`.

### 2.2 Whether to Enter PERIPS

`src/ctl_perips.v:21-33`: for Load/Store `peripsen = 1` (memory access required),
and Store also provides `mem_write` (`MEM_W_B/H/W`):

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

### 2.3 Memory Access Flow in the PERIPS Stage

The EXE→PERIPS beat in `src/core_ctl.v:406-443`:

```verilog
else if (exe_token && !perips_token) begin
    perips_req <= 1'b0;
    if (exe_ctl_peripsen && !perips_pending) begin
        perips_pending <= 1'b1;
        perips_req     <= 1'b1;      // issue a req pulse
    end else if (exe_ctl_peripsen && perips_pending && perips_done) begin
        perips_data <= perips_data_w;  // capture read data
        ...
        perips_token <= 1'b1;          // advance to WB
    end
    ...
end
```

`core_perips` decodes by `adr[31]` (`src/core_perips.v:24-27`): the data memory `is_mem` goes through
`mem_ctl` (fixed 1 beat, `mem_busy_r`/`mem_done_r`, see `src/core_perips.v:48-63`).

## 3. Data Memory: mem_ctl (Barrel-Shifted Byte Banks)

`src/mem_ctl.v` is the core of this project's memory implementation; the design evolution is detailed in `03-debug-pitfalls/01`. Key points:

### 3.1 Split into 4 Independent Byte Banks

24KB = 4 × 6KB (each `mem_cell.v` has a depth of 6144, M9K). The reason is that **M9K is single-port only**,
and synthesis tools do not support "one memory supporting 8/16/32-bit reads/writes" well, so it is split into 4 8-bit memory cells,
each cell independently controlling its write enable `we[0..3]`.

### 3.2 Write Enable Generation (src/mem_ctl.v:19-33)

```verilog
case(wen)
    2'b01: we = 4'b1 << offset;               // SB
    2'b10: case(offset)                        // SH
        2'b00: we = 4'b0011;
        2'b01: we = 4'b0110;
        2'b10: we = 4'b1100;
        2'b11: we = 4'b1001;                  // ★crosses word boundary
    endcase
    2'b11: we = 4'b1111;                       // SW
endcase
```

Note that when SH's `offset==2'b11`, `we=1001`: the halfword crosses two word boundaries, and byte 0 lands in the next word.
This was exactly the pitfall hit during earlier debugging (a mask write was off by one bit).

### 3.3 Data Barrel Shift (src/mem_ctl.v:36-50)

Write data is rotated by `offset` to ensure each byte lands in the correct bank:

```verilog
2'b00: wdata_shifted = idata;
2'b01: wdata_shifted = {idata[23:0], idata[31:24]};
2'b10: wdata_shifted = {idata[15:0], idata[31:16]};
2'b11: wdata_shifted = {idata[7:0],  idata[31:8]};
```

### 3.4 Byte Address (src/mem_ctl.v:52-88)

Each bank's address `mem_addr[i] = base_addr + ((offset + i) >= 4 ? 1 : 0)`,
handling halfword/byte accesses that cross word boundaries. This is the "most core" comment in the whole module.

### 3.5 Read Barrel Right-Shift (src/mem_ctl.v:134-149)

After the 4 banks are reassembled into `rdata_rotated`, it is right-shifted by `offset` to restore byte order.

## 4. Write-Back

`src/ctl_wb.v:30-42` selects the Load sign-extension method based on funct3:

```verilog
OP_LOAD: begin
    reg_write = 1;
    case (funct3)
        FUNC3_LB:  opt_wb = OPT_WB_LB;    // sign-extend
        FUNC3_LBU: opt_wb = OPT_WB_LBU;   // zero-extend
        FUNC3_LH:  opt_wb = OPT_WB_LH;
        FUNC3_LHU: opt_wb = OPT_WB_LHU;
        FUNC3_LW:  opt_wb = OPT_WB_LW;
    endcase
end
```

`src/core_wb.v:31-36` implements the corresponding sign/zero extension. Store does not write back to a register (`reg_write = 0`).

## 5. Test: ins/LS.s

`ins/LS.s` covers SW/LW, SH/LHU, SB/LBU, LH/LB sign extension, and **mixed cross-byte accesses**:

```asm
li x10,0x80000000
li x5,0x12345678
sw x5,0(x10)
lw x6,0(x10)            # EXPECT: x6 = 0x12345678
...
li x5,-2
sh x5,12(x10)
lh x6,12(x10)           # EXPECT: x6 = 0xfffffffe (sign-extended)
...
sw x5,20(x10)           # x5 = 0xaabbccdd
lb  x6,20(x10)          # EXPECT: 0xffffffdd
lbu x7,21(x10)          # EXPECT: 0x000000cc
lh  x8,20(x10)          # EXPECT: 0xffffccdd
lhu x9,22(x10)          # EXPECT: 0x0000aabb
```

Finally, checking the x5~x9 register values confirms that all 8/16/32-bit reads and writes are correct.

## 6. Pitfalls

- **SW overwrite**: `we = 4'b1111` unconditionally writes all 4 bytes; even with an unaligned address it will still cross words (this project supports it directly).
- **SH crossing a word boundary** (offset=3) is a test dead spot and must be covered with mixed cases.
- **Load sign extension**: LB/LH must extend by the most significant bit, LBU/LHU must zero-extend; the case in `core_wb.v` must not be written incorrectly.
- **PERIPS waiting**: Load must wait for `perips_done` before advancing, otherwise it reads the previous beat's data.
