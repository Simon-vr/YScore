---
permalink: /learn/03-debug-pitfalls/01-hardware-pitfalls/
lang: en
---
# 01. Hardware Pitfalls: Memory Implementation

This article fully records the design evolution of the `mem_ctl.v` data memory and three
real pitfalls encountered.

## 1. Requirements and the First Version (failed)

The CPU needs byte-addressable 8/16/32-bit reads/writes (SB/SH/SW, LB/LH/LW), and addresses
may be **unaligned** (RISC-V allows unaligned half-word/byte access; this project supports it directly).

The first version used a single 32-bit-wide RAM with `adr[1:0]` as the offset selector.
**Problem**: M9K (the on-chip RAM of Altera Cyclone IV) is 9 bits wide and single-port, so a
32-bit-wide RAM either occupies 4 M9K blocks and still has trouble doing byte write-enables,
or it must use async reads (see pitfall B).

## 2. Pitfall Records

### Pitfall A: 8-bit alignment / 32-bit read-write — barrel-style 4×8bit banks

**Symptom**: 8/16-bit read/write is corrupted; 32-bit is fine.

**First attempt**: directly use a 32-bit RAM + offset to select bytes. After synthesis, the
byte write-enable is hard to map onto M9K.

**Inspired by RAID**: switched to **4 independent 8-bit memory cells** (`mem_cell.v`, depth
6144 each), where each cell handles one byte and `we[3:0]` independently controls writes.
24KB = 4 × 6KB.

Key points (`mem_ctl.v`):

- **Write-enable** is generated from `wen` (SB/SH/SW) and `offset` (`adr[1:0]`) (`mem_ctl.v:19-33`).
- **Write data** is barrel-shifted left so each byte lands in the correct bank (`mem_ctl.v:36-50`).
- **Readback** is barrel-shifted right to restore (`mem_ctl.v:134-149`).
- **Byte address**: `mem_addr[i] = base + ((offset+i)>=4)`, handling cross-word boundaries (`mem_ctl.v:52-88`).

### Pitfall B: Synthesis too slow — async read cannot map to M9K

**Symptom**: combining the 4 banks causes synthesis time to explode, sometimes not converging.

**Root cause**: the first `mem_cell` used combinational logic to read `memory[addr]` directly
(async read). M9K is a synchronous RAM, so async reads cannot be mapped; the synthesizer can
only degrade to LUT/register arrays, consuming a huge amount of logic → synthesis explosion.

**Fix**: `mem_cell.v:17-22` switched to **synchronous read**:

```verilog
always @(posedge clk) begin
    if (mem_write) memory[addr] <= data_in;
    data_out <= memory[addr];      // synchronous read, one-cycle delay
end
```

The cost is one extra cycle of read latency — compensated by the fixed one-cycle `mem_done_r`
in the pipeline's PERIPS stage (`core_perips.v:48-63`).

### Pitfall C: Barrel mask off by one bit — exposed by test.c after LS.s passes

**Symptom**: `ins/LS.s` (basic SW/LW/SH/LHU/SB/LBU) all pass, but running `ins/test.c`
(a C program with mixed access to on-stack arrays) gives wrong results.

**Troubleshooting process**:

1. **Look at the waveform**: locate the "crash point" in ModelSim.
2. **Get the PC**: obtain the faulting PC from the waveform/tb printout.
3. **Find the disassembly**: `objdump -d` to locate the C source line for that PC.
4. **Determine it is a memory-access problem**: the faulting instruction is an on-stack load/store.
5. **Check the .mem files**: the contents of imem.mem / dmem0~3.mem are correct (not an init problem).
6. **Check the hardware path**: verify the write-enable/shift/address generation in `mem_ctl.v` bit by bit.

**Root cause**: for `SH` (half-word) at `offset==2'b11` (address `...11`, crossing the word
boundary), the write-enable should be `4'b1001` (byte 0 falls into the next word, byte 1 into
the high bits of the current word). In the case at `mem_ctl.v:27` this entry was originally
written as `4'b1000` — **the mask was off by one bit**.

The LS.s SH test only used `offset==0` (`sh x5,4(x10)`, aligned) and did not cover cross-word
cases; the stack operations in test.c hit `offset==3`, exposing it.

**Fix**: corrected `we = 4'b1001` at `mem_ctl.v:27`.

## 3. Lessons

1. **Aligned tests ≠ full coverage**: you must specifically test unaligned (cross-word
   boundary) 8/16-bit accesses.
2. **Async reads do not hold on Altera M9K**: on-chip RAM must be read synchronously; multi-cycle
   latency is compensated by the pipeline rhythm.
3. **Flow for locating "memory-access" bugs**: waveform to get PC → disassembly → rule out .mem →
   check hardware mask/shift/address, confirming one step at a time.
