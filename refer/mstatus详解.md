# RV32 MSTATUS 寄存器位详解（RISC-V 标准）

`mstatus` 是 **M-mode（机器模式）** 下的核心状态寄存器，用于控制全局中断、特权级切换、内存保护、浮点状态等。
RV32 中 `mstatus` 为 **32 位**，标准位域布局如下（从高位到低位）：

## 1. 位域总览

| 位    | 名称     | 全称                             | 功能简述                       |
| ----- | -------- | -------------------------------- | ------------------------------ |
| 31    | `SD`   | State Dirty                      | 浮点/扩展状态脏位              |
| 30:23 | `WPRI` | Write Preserve, Read Ignore      | 保留位，写0读忽略              |
| 22    | `TSR`  | Trap SRET                        | 禁止 S-mode 执行 `sret`      |
| 21    | `TW`   | Timeout Wait                     | 禁止 S-mode 执行 `wfi`       |
| 20    | `TVM`  | Trap Virtual Memory              | 禁止 S-mode 访问页表基址寄存器 |
| 19    | `MXL`  | XLEN for M-mode                  | M-mode 寄存器宽度（RV32=01）   |
| 18:15 | `XS`   | Extension Status                 | 自定义扩展状态                 |
| 14:13 | `FS`   | Floating-Point Status            | 浮点单元状态                   |
| 12:11 | `MPP`  | M-mode Previous Privilege        | M-mode 陷入前特权级            |
| 10:9  | `VS`   | Vector Extension Status          | 向量扩展状态                   |
| 8     | `SPP`  | S-mode Previous Privilege        | S-mode 陷入前特权级            |
| 7     | `MPIE` | M-mode Previous Interrupt Enable | M-mode 旧中断使能              |
| 6     | `UBE`  | U-mode Big Endian                | U-mode 字节序（0=小端）        |
| 5     | `SPIE` | S-mode Previous Interrupt Enable | S-mode 旧中断使能              |
| 4     | `UPIE` | U-mode Previous Interrupt Enable | U-mode 旧中断使能              |
| 3     | `MIE`  | M-mode Interrupt Enable          | M-mode 全局中断使能            |
| 2     | `SIE`  | S-mode Interrupt Enable          | S-mode 全局中断使能            |
| 1     | `WPRI` | Reserved                         | 保留                           |
| 0     | `UIE`  | U-mode Interrupt Enable          | U-mode 全局中断使能            |

---

## 2. 关键位详细解释

### （1）全局中断使能组

- **`MIE[3]`**
  M-mode 全局中断使能。

  - `1`：允许 M-mode 中断
  - `0`：关闭 M-mode 中断
- **`SIE[2]`**
  S-mode 全局中断使能（需 S-mode 支持）。
- **`UIE[0]`**
  U-mode 全局中断使能。

---

### （2）中断陷入保存组（Previous IE）

发生异常/中断时，**当前 IE 会自动保存到 PIE，然后 IE 清 0**，返回时再恢复。

- **`MPIE[7]`**：保存陷入前的 `MIE`
- **`SPIE[5]`**：保存陷入前的 `SIE`
- **`UPIE[4]`**：保存陷入前的 `UIE`

典型流程：

1. 中断触发 → `MIE` → `MPIE`，`MIE=0`
2. 执行 `mret` → `MPIE` → `MIE`，恢复中断

---

### （3）特权级模式保存组（Previous Privilege）

记录**异常发生前的运行特权级**，`mret` 时恢复。

- **`MPP[12:11]`**
  M-mode 陷入前特权级：

  - `00`：U-mode
  - `01`：保留
  - `10`：S-mode
  - `11`：M-mode
- **`SPP[8]`**
  S-mode 陷入前特权级：

  - `0`：U-mode
  - `1`：S-mode

---

### （4）虚拟内存与 S-mode 限制位（用于虚拟机/监控）

- **`TSR[22]`**
  `1`：S-mode 执行 `sret` 会触发非法指令异常。
- **`TW[21]`**
  `1`：S-mode 执行 `wfi` 会触发异常。
- **`TVM[20]`**
  `1`：S-mode 访问 `satp` 等页表寄存器触发异常。

---

### （5）浮点 / 扩展状态

- **`FS[14:13]`** 浮点单元状态

  - `00`：关闭
  - `01`：初始
  - `10`：干净
  - `11`：脏（已修改）
- **`XS[18:15]`** 自定义扩展状态
- **`VS[10:9]`** 向量扩展状态
- **`SD[31]`**
  当 `FS/XS/VS` 任意为 `11`（脏）时，`SD=1`，表示上下文需要保存。

---

### （6）MXL[19]

RV32 中固定为 **`01`**，表示 M-mode 寄存器宽度为 32 位。

---

### （7）UBE[6]

U-mode 字节序：

- `0`：小端（默认）
- `1`：大端

---

## 3. 最常用位速记（嵌入式/OS 开发重点）

- `MIE[3]`：开/关 M-mode 中断
- `MPIE[7]`：中断返回恢复使能
- `MPP[12:11]`：控制 `mret` 返回到哪个特权级
- `FS[14:13]`：浮点上下文开关
- `SD[31]`：判断是否需要保存浮点/扩展上下文

需要我给你一份 **RV32 mstatus 常用操作汇编示例**（开中断、关中断、mret 恢复）吗？
