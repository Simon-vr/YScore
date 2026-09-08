---
permalink: /learn/03-debug-pitfalls/
lang: en
---
# 03. Debug Pitfalls Guide

This part is the **essence** of the entire document, recording the real debug processes that
occurred in this project and were resolved one by one.

```
03-debug-pitfalls/
├── README.md
├── 01-hardware-pitfalls.md   Hardware pitfalls (memory byte alignment / async read / mask bits)
├── 02-software-pitfalls.md   Software pitfalls (UART buffer sharing / input ownership token)
└── 03-hw-sw-co-debug.md      Full hardware-software combined Debug record (bugs in this session)
```

## Quick Index by Type

| Pitfall to look for                              | Chapter |
|--------------------------------------------------|---------|
| 8/16/32-bit memory access, barrel banks, mask-bit error | 01 |
| Async read cannot be synthesized into M9K, changed to sync read | 01 |
| Shell/Game sharing the UART buffer, token mechanism | 02 |
| "Typing help returns banner", "hang after output", LED-state diagnosis | 03 |
| WB retire stage non-idempotent, MPIE overwritten to 0, interrupt saves nextpc | 03 |
