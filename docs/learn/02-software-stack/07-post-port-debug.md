---
permalink: /learn/02-software-stack/07-post-port-debug/
lang: en
---
# 07. Post-Port Debug Guide

This article is the standard troubleshooting flow for "software verified on QEMU but
misbehaving after porting to FPGA". It corresponds to the real pitfalls this project
actually hit (see 03-debug-pitfalls).

## 1. Core Principle

**Dichotomy**: QEMU behaves correctly + FPGA misbehaves → the problem is in the hardware;
both misbehave → the problem is in the software. This is the first judgment after porting.

## 2. Standard Troubleshooting Flow

```
Found a problem on the board
   │
   ├─ ① Determine the level: does QEMU also misbehave on the same code?
   │      ├─ also misbehaves → software bug, fix on QEMU (fast)
   │      └─ only FPGA misbehaves → hardware bug, continue
   │
   ├─ ② Collect the scene: was the banner printed? How many LEDs lit / blinking? Any input echo?
   │      (LED state is a natural probe for "whether the CPU ran gpio_init")
   │
   ├─ ③ Pin down the instruction: run ModelSim simulation (sim.do), locate the "crashing PC /
   │      last normal instruction", look at the disassembly (map/dasm)
   │   
   │
   ├─ ④ Inspect the hardware data/control flow: check the ctl control signals and data values
   │      stage by stage from IF to WB
   │
   └─ ⑤ Change one thing → re-simulate / re-flash and re-test → loop
```

## 3. Common Symptom → Suspect Mapping

| Symptom                     | Priority suspect                                                              |
| --------------------------- | ----------------------------------------------------------------------------- |
| No output at all / no banner | Stuck early at startup: .bss/stack/mtvec/instruction fetch; or GPIO lit on reset |
| Banner present, no input echo | uart_rx task asleep (tick interrupt not firing) / wrong input ownership      |
| Typing help returns banner   | **PC flow corrupted** (wrong interrupt return address) → see 03-debug-pitfalls/03 |
| Whole system hangs after output | Interrupt corrupting scheduling / trap context touching a blocking peripheral |
| One LED lit, not blinking   | led task asleep (tick interrupt not firing)                                   |
| Some instruction results wrong | Check the corresponding ctl/alu/exe_next (hardware decode/operation)        |

## 4. Key Troubleshooting Tools

### 4.1 Disassembly (map/dasm)

`ninja dasm` generates `MiniRTOS_shturl.txt`. After locating the faulting PC, compare against
the source to determine whether the wrong instruction was fetched (PC error) or an arithmetic
error occurred.

### 4.2 ModelSim Simulation

`simulation/modelsim/sim.do` runs in one click. `tb/mycpu_sim.v` prints:

- Each cycle's "register/CSR changes + PC + instruction name".
- Supports `+STOP_PC=0x...` to stop at a given address (`mycpu_sim.v:357`).

Key signals to watch in the waveform: `if_token/ifid_token/exe_token/perips_token/wb_token`
(token progression), `perips_data_w`, `wb_pc_w`, `csr_intrpt_w`, and the AXI handshake
`axil_*valid/ready`.

### 4.3 QEMU Comparison

Swap the same `portmacro.h`/`timer.c` to QEMU parameters, run `ninja run` on QEMU, and confirm
the software behavior baseline.
