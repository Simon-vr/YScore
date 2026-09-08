@echo off
echo Starting RISC-V (RV32I_Zicsr) assembly build process...

:: 1. 汇编：指定架构为 rv32i_zicsr
riscv-none-elf-as -march=rv32i_zicsr imem.s -o imem.o
if errorlevel 1 (
    echo Error: Assembly failed!
    pause
    exit /b 1
)

:: 2. 链接：指定起始地址 0x00000000
riscv-none-elf-ld -Ttext 0x00000000 imem.o -o imem.elf
if errorlevel 1 (
    echo Error: Linking failed!
    pause
    exit /b 1
)

:: 3. 从 ELF 提取二进制（只提取 .text 段，确保地址从 0 开始）
riscv-none-elf-objcopy -O binary --only-section=.text imem.elf imem.bin
if errorlevel 1 (
    echo Error: Object copy failed!
    pause
    exit /b 1
)

:: 4. 运行转换脚本（生成你模拟器需要的格式）
python bin2mem.py
if errorlevel 1 (
    echo Error: Python script execution failed!
    pause
    exit /b 1
)

echo Build completed successfully!
pause