# Ensure cross-compilers and try-compile type are set before project()
cmake_minimum_required(VERSION 3.20)

# ==============================
# 工具链（在 project() 之前设置以便生效）
# ==============================
# 只保留静态自检, 避免报错
# set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(CMAKE_C_COMPILER     riscv-none-elf-gcc)
set(CMAKE_ASM_COMPILER   riscv-none-elf-gcc)  
set(CMAKE_LINKER         riscv-none-elf-ld)
set(CMAKE_OBJDUMP        riscv-none-elf-objdump)

# 指定为交叉编译平台, 防止CMake误以为是本地编译环境
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR riscv)

# 强制取消自检
# set(CMAKE_C_COMPILER_WORKS TRUE CACHE BOOL "" FORCE)
# set(CMAKE_ASM_COMPILER_WORKS TRUE CACHE BOOL "" FORCE)

# 所有「描述目标平台、编译器、系统属性」的变量，必须放在 project() 之前！
project(MiniRTOS LANGUAGES C ASM)

# 目标文件
set(TARGET ${PROJECT_NAME})

# ==============================
# 运行 / 调试工具
# ==============================
find_program(QEMU_SYSTEM_RISCV32 qemu-system-riscv32)
if(NOT QEMU_SYSTEM_RISCV32)
    set(QEMU_SYSTEM_RISCV32 qemu-system-riscv32)
endif()

find_program(RISCV_GDB riscv64-elf-gdb)
if(NOT RISCV_GDB)
    set(RISCV_GDB riscv64-elf-gdb)
endif()

# ==============================
# 编译选项
# ==============================
set(ARCH_FLAGS
    # 指定RISC-V架构：rv32i（32位整数指令集）+ zicsr（控制状态寄存器指令，裸机/内核必备）
    -march=rv32i_zicsr
    # 指定应用二进制接口：32位，int/long/pointer都是32位，无浮点寄存器（对应rv32i）
    -mabi=ilp32
    # 代码模型：medlow = 程序和数据都在低2GB空间(0x00000000-0x7fffffff)
    # medany = 程序和数据可以在整个4GB地址空间内，但编译器会生成更大的指令（可能需要更多寄存器）来访问高地址
    -mcmodel=medany
)


set(C_FLAGS
    -O0
    -g
    -ffreestanding  # 无宿主环境，没有操作系统、没有标准库
    -nostdlib       # 不链接标准库（libc）
    -nostartfiles   # 不使用默认的启动文件（crt0.o等），我们有自己的启动代码
    -Wall
    -Wextra
)

set(LINK_FLAGS
    -nostdlib          
    -nostartfiles
    -T ${CMAKE_SOURCE_DIR}/startup/link.ld
    -Wl,-Map=${TARGET}.map
)

# ==============================
# 正确区分 C 和 ASM 选项（关键修复）
# ==============================
# 架构选项：C 和汇编都需要
# 避免 generator expression 与列表展开产生尾部符号问题，
# 将标志合并为字符串并直接赋给 C/ASM 标志变量
string(JOIN " " ARCH_FLAGS_STR ${ARCH_FLAGS})
string(JOIN " " C_FLAGS_STR ${C_FLAGS})

# 将 flags 存入 cache 变量，确保 CMake 在生成 Makefile 时能正确展开它们
set(CMAKE_C_FLAGS "${ARCH_FLAGS_STR} ${C_FLAGS_STR}" CACHE STRING "C flags" FORCE)
set(CMAKE_ASM_FLAGS "${ARCH_FLAGS_STR} -g" CACHE STRING "ASM flags" FORCE)

# 链接选项：直接设置到 CMAKE_EXE_LINKER_FLAGS（作为 cache 变量）
string(JOIN " " LINK_FLAGS_STR ${LINK_FLAGS})
set(CMAKE_EXE_LINKER_FLAGS "${LINK_FLAGS_STR}" CACHE STRING "Linker flags" FORCE)

# ==============================
# 头文件路径
# ==============================
include_directories(
    ${CMAKE_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/lib
    ${CMAKE_SOURCE_DIR}/port
)

# ==============================
# 自动扫描所有源文件
# ==============================
file(GLOB_RECURSE SRC_FILES CONFIGURE_DEPENDS
    ${CMAKE_SOURCE_DIR}/src/*.c
    ${CMAKE_SOURCE_DIR}/port/*.c
    ${CMAKE_SOURCE_DIR}/lib/*.c
    ${CMAKE_SOURCE_DIR}/sys/*.c
)

file(GLOB_RECURSE ASM_FILES CONFIGURE_DEPENDS
    ${CMAKE_SOURCE_DIR}/port/*.S
    ${CMAKE_SOURCE_DIR}/startup/*.S
    ${CMAKE_SOURCE_DIR}/src/*.S
)

# ==============================
# 生成 elf
# ==============================
add_executable(${TARGET}.elf ${SRC_FILES} ${ASM_FILES})

# ==============================
# 生成反汇编（方便调试）
# ==============================
add_custom_target(dasm
    COMMAND ${CMAKE_OBJDUMP} -D -h -z -M no-aliases ${TARGET}.elf > ${TARGET}_shturl.txt
    DEPENDS ${TARGET}.elf
)

# ==============================
# 提取 .text 段为二进制文件
# ==============================
set(OBJCOPY riscv-none-elf-objcopy)

add_custom_target(bin_text
    COMMAND ${OBJCOPY} -O binary --only-section=.text ${TARGET}.elf ${TARGET}_text.bin
    DEPENDS ${TARGET}.elf
    COMMENT "Extracting .text section -> ${TARGET}_text.bin"
)

# ==============================
# 提取 .data / .bss / .heap / .stack 段为二进制文件
# ==============================
add_custom_target(bin_data
    COMMAND ${OBJCOPY} -O binary -j .data -j .bss -j .heap -j .stack ${TARGET}.elf ${TARGET}_data.bin
    DEPENDS ${TARGET}.elf
    COMMENT "Extracting .data/.bss/.heap/.stack -> ${TARGET}_data.bin"
)

# ==============================
# 一键生成所有二进制文件
# ==============================
add_custom_target(bin
    DEPENDS bin_text bin_data
)

# ==============================
# 从 bin 生成 .mem 文件 (dmem=16KB)
# ==============================
add_custom_target(mem
    DEPENDS bin
    COMMAND E:/miniforge/python.exe ${CMAKE_SOURCE_DIR}/bin2mem.py
            24
            ${CMAKE_BINARY_DIR}/${TARGET}_text.bin
            ${CMAKE_BINARY_DIR}/${TARGET}_data.bin
            ${CMAKE_BINARY_DIR}
    COMMENT "Generating imem.mem + dmem.mem (24KB) from bin files"
)