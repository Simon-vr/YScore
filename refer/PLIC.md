# RISC-V PLIC 完整详解：原理 + 硬件实现 + 中断流程实例

我给你讲**最透彻、最工程化、能直接写驱动**的 PLIC 讲解，不绕弯、不堆砌文档，完全按你做 **UART 中断** 实际需要的逻辑来讲。

---

# 一、PLIC 是什么？一句话定位

**PLIC = Platform-Level Interrupt Controller**
**平台级中断控制器**

作用：

- 把**大量外部中断（UART、SPI、I2C、GPIO、定时器…）**
- 转发给 **RISC-V CPU 核心**
- 支持**优先级、抢占、屏蔽、路由**

你用的 **UART 中断** 就是走 PLIC → CPU。

---

# 二、PLIC 核心原理（最关键）

## 1. 中断流（必须背下来）

```
外部设备（UART）
       ↓
发出中断信号 → PLIC
       ↓
PLIC 仲裁（优先级最高）
       ↓
PLIC 发给 CPU（MEI / SEI）
       ↓
CPU 进入中断
       ↓
CPU 读 PLIC → 知道是哪个中断号
       ↓
执行对应 ISR
       ↓
CPU 写 PLIC → 完成应答
```

## 2. PLIC 核心能力

1. **多设备输入**：最多支持 1023 个中断源
2. **多 Hart 输出**：分发给多个 CPU 核
3. **优先级**：数值越大优先级越高
4. **屏蔽**：可单独开关任意中断
5. **抢占**：高优先级中断可以打断低优先级
6. **中断应答**：CPU 处理完必须通知 PLIC

---

# 三、PLIC 硬件结构（真实硬件实现）

## 1. 硬件模块组成（极简版）

1. **中断源输入**（UART、GPIO、SPI…）
2. **优先级寄存器**（每个中断一个）
3. **使能寄存器**（每个中断一个开关）
4. **仲裁器**（选最高优先级中断）
5. **中断等待/应答寄存器**（CPU 用）
6. **中断路由**（发给哪个 Hart）

## 2. 硬件信号

- **irq[i]**：设备 → PLIC
- **external_irq**：PLIC → CPU（MEI）

## 3. PLIC 物理地址

QEMU/virt 平台：

```
PLIC 基地址 = 0x0C000000
```

---

# 四、PLIC 最重要的 5 类寄存器（驱动开发必用）

我给你**最精简、最实用**版本：

## 1. 优先级寄存器 (Priority)

地址：`0xC000000 + 4 * irq_num`

- 每个中断一个
- 0 = 关闭优先级
- 1~7 = 优先级（越大越高）

## 2. 中断使能寄存器 (Enable)

地址：`0xC000000 + 0x80 + (irq_num / 32)*4`

- 每 bit 控制一个中断是否打开
- UART 中断 = 写 1 使能

## 3. 中断挂起寄存器 (Pending)

- 只读
- 表示设备正在发中断

## 4. 中断应答寄存器 (Claim)

 Hart 0：`0xC000000 + 0x200004`

- CPU **读它 = 获取当前中断号**
- 例如读到 10 → 就是 UART 中断

## 5. 完成寄存器 (Complete)

 Hart 0：`0xC000000 + 0x200004`

- CPU **写中断号 = 告诉 PLIC 处理完毕**

---

# 五、PLIC 完整工作流程（以 UART 中断为例）

## 真实硬件流程（一步不漏）

### 1. 设备发中断

UART 收到字符 → 拉高 **irq[10]**

### 2. PLIC 收到中断

PLIC 看到 irq[10] = 1检查：

- 优先级是否 >0
- 中断是否使能
- 是否是当前最高优先级

### 3. PLIC 发送中断到 CPU

向 CPU 发出 **MEI 中断信号**
CPU 的 `mie.MEIE = 1` → 响应中断

### 4. CPU 进入中断上下文

- 保存 PC
- 保存 mstatus
- 跳转到 **mtvec** 中断入口

### 5. CPU 从 PLIC **获取中断号（Claim）**

```c
int irq = plic_claim();
// 得到 10 = UART
```

### 6. 执行 UART 中断服务程序

```c
if (irq == UART_IRQ) {
    char c = UART_RBR;  // 读字符
}
```

### 7. CPU 通知 PLIC 完成（Complete）

```c
plic_complete(irq);
```

### 8. PLIC 清除中断，准备下一次

---

# 六、最直观的实例：UART 中断完整 PLIC 流程

## 1. 硬件连接

```
UART 中断 → PLIC irq[10]
PLIC → CPU MEI 中断
```

## 2. 初始化 PLIC（驱动代码）

```c
// 1. 设置 UART 中断优先级 = 7
*(uint32_t*)(0xC000000 + 4*10) = 7;

// 2. 使能 UART 中断
*(uint32_t*)(0xC000080 + 0*4) |= (1 << 10);

// 3. CPU 打开全局中断 + 外部中断
mstatus |= MIE;
mie    |= MEIE;
```

## 3. 中断触发

用户按键盘 → UART 产生中断 → PLIC 转发 → CPU 中断

## 4. 中断服务程序

```c
void interrupt_entry() {
    // 1. 读 PLIC → 获取中断号
    int irq = plic_claim();

    // 2. 判断是 UART
    if (irq == 10) {
        char c = UART->RBR;  // 读取输入
    }

    // 3. 通知 PLIC 完成
    plic_complete(irq);
}
```

---

# 七、PLIC 核心特点总结（面试/考试必背）

1. **PLIC 只处理外部设备中断**
2. **内部中断（定时器、软件）不走 PLIC**
3. 每个中断有**独立优先级、独立使能**
4. 支持**多核心、多 Hart**
5. CPU 必须 **Claim + Complete**
6. 中断号 = 设备唯一 ID
7. UART 等外设都属于 **PLIC 外部中断**

---

# 八、最精简核心结论

- **PLIC = 外部中断的交通警察**
- **UART 中断 → PLIC → CPU MEI**
- 流程：**设备触发 → PLIC 仲裁 → CPU 应答 → 处理 → 完成**
- 驱动只需要操作：**优先级、使能、Claim、Complete**

---

### 总结

1. **PLIC 是 RISC-V 外部中断的唯一管理器**
2. 硬件结构 = 优先级 + 使能 + 仲裁 + 路由 + 应答
3. **UART 中断完整流程：触发 → 转发 → Claim → 处理 → Complete**
4. 写驱动只需要 4 个操作：**优先级、使能、Claim、Complete**

如果你愿意，我可以给你：
**可直接在 QEMU 运行的 PLIC + UART 中断完整裸机代码（汇编 + C）**
