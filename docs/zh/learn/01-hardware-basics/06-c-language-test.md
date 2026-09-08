---
permalink: /zh/learn/01-hardware-basics/06-c-language-test/
---
# 06. C 语言编译测试

汇编指令逐类通过后，下一步是验证 C 编译器生成的代码能在本 CPU 上正确运行。
这一步打通了"交叉编译 → ELF → 内存文件 → 上板/仿真"的完整工具链。

## 1. 工具链

`rtos/CMakeLists.txt`：

- 编译器 `riscv-none-elf-gcc`，`-march=rv32i_zicsr -mabi=ilp32 -mcmodel=medany`
  （`CMakeLists.txt:45-53`）。
- `-O0 -g -ffreestanding -nostdlib -nostartfiles`（`CMakeLists.txt:56-64`）：
  无 libc、无默认启动文件，全部自包含。
- 链接脚本 `rtos/startup/link.ld`（`-T`，`CMakeLists.txt:66-71`）。
- 生成 ELF 后，`ninja dasm` 出反汇编，`ninja bin` 提取 `.text`/`.data` 段，
  `ninja mem` 调 `bin2mem.py` 生成内存文件（`CMakeLists.txt:121-166`）。

## 2. 内存布局（rtos/startup/link.ld）

```ld
MEMORY {
    irom (x)  : ORIGIN = 0x00000000, LENGTH = 18K
    dram (rw) : ORIGIN = 0x80000000, LENGTH = 24K
}
_sys_heap_size = 1K;
_sys_stack_size = 8K;
```

- `.text` 放 `irom`（0x0 起），`_start` 必须排最前（`*(.text.start)`）。
- `.data` / `.bss` / `.stack` 放 `dram`（0x80000000 起），
  `__global_pointer$ = ORIGIN(dram) + LENGTH(dram)/2`。
- `_stack_top = ORIGIN(dram) + LENGTH(dram)`（栈顶=DRAM 顶端）。

## 3. ELF → 内存文件（bin2mem.py）

`rtos/bin2mem.py` 两个转换：

1. **imem**（`convert_imem`）：把 `.text.bin` 每 4 字节按**小端**拼成一条 32 位指令，
   每行一个 `%08x`。`core_if.v` 的 `$readmemh` 逐行读入。
2. **dmem**（`convert_dmem`）：把 `.data.bin` 补齐到 24KB，
   按**字节**拆成 4 个 bank 文件 `dmem0.mem`~`dmem3.mem`，
   与 `mem_ctl.v` 的 4 个 `mem_cell` 一一对应。

命令行用法（`CMakeLists.txt:159-166`）：

```
python bin2mem.py 24 <text.bin> <data.bin> <输出目录>
```

## 4. 测试程序 ins/test.c

`ins/test.c` 是一个"确定性校验"程序，综合覆盖：

- 静态 `.data` 数组访问（`checksum`，含异或+加法）。
- 栈上 `volatile mem[64]` 写入 + 读回校验（访存）。
- `logic_mix`（移位/异或/加减，覆盖 SLL/SRL/SRA/XOR/ADD/SUB）。
- 有符号分支（`if(a<b) ... else ...`）与无符号分支（`if(a>b) ... else ...`）。
- 大量算术混合。

30000 轮循环是为了在 FPGA 上跑几秒（`test.c:45-51` 注释）。

**确定性校验思路**（`test.c:136-151` 注释）：
先在主机/模拟器上跑一次记录 `state` 的期望值，再把
`if(state != 0xXXXXXXXX) return 4;` 固化到测试里，上板后结果可复现。

## 5. 验证方法

1. 交叉编译 `test.c` → 生成 `imem.mem`/`dmem0~3.mem`。
2. **仿真**：跑 `sim.do`，看 tb 快照里最终 `x31`（或程序 `return` 值对应的寄存器）。
3. **上板**：`ins.bat` 流程（汇编 `-march=rv32i_zicsr`，链接 `-Ttext 0x0`，
   objcopy 出 bin，`bin2mem.py` 转 mem），烧进 FPGA，看结果寄存器/GPIO。

## 6. C 编译需要特别注意的点

- **无标准库**：不能依赖 `memcpy`/`printf`，`rtos/sys/mem.c` 提供了 `vPortMemCpy/Set`。
- **无乘法指令**：`-march=rv32i` 没有 M 扩展，乘法/除法由编译器内联调用
  `rtos/lib/math.c` 的软乘除（`umul/udiv/...`）。C 里写 `i*17` 也会走软乘法。
- **启动代码**：没有 `crt0`，必须自己 `_start` 设栈、清 .bss、设 mtvec（见 02-software-stack/02）。
- **全局指针**：`__global_pointer$` 由链接脚本提供，`startup.S` 里 `la gp, __global_pointer$`。