ENTRY(_start);

MEMORY
{
    irom (x)  : ORIGIN = 0x00000000, LENGTH = 18K
    dram (rw)  : ORIGIN = 0x80000000, LENGTH = 24K
}


_sys_heap_size = 1K;
_sys_stack_size = 8K;

__global_pointer$ = ORIGIN(dram) + LENGTH(dram) / 2;

SECTIONS
{
    . = ORIGIN(irom);
    .text : {
        *(.text.start)
        *(.text*)
    } > irom

    .data : {
        . = ALIGN(4);
        _sys_data_start = .;
        *(.srodata*)
        *(.rodata*)
        *(.data*)
        *(.sdata*)
        _sys_data_end = .;
    } > dram

    .bss : {
        . = ALIGN(4);
        _sys_bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        _sys_bss_end = .;
    } > dram

    .stack : {
        . = ALIGN(8);
        _sys_stack_end = .;
        . += _sys_stack_size;
        _sys_stack_top = ORIGIN(dram) + LENGTH(dram);
    } > dram
}

# common symbol aliases used by startup/port code
PROVIDE(_stack_top = _sys_stack_top);
PROVIDE(_bss_start = _sys_bss_start);
PROVIDE(_bss_end = _sys_bss_end);
PROVIDE(_data_start = _sys_data_start);
PROVIDE(_data_end = _sys_data_end);