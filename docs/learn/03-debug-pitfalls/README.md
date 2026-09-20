---
permalink: /learn/03-debug-pitfalls/
lang: en
---
# 03. Debug Pitfalls Guide

Long ago a teacher told me: if a person has 10 units of skill, then in practice they can only
write — and should only write — code worth 6 units. If they push to their limit and write
10-unit code, they will have no energy left to debug it, nor the capacity to review the whole
project.

Of course, in the age of AI this claim is debatable. Still, while building this project I hit
countless pitfalls, consuming a great deal of time and energy. Several times I debugged for two
days straight with no progress and nearly gave up. Because the architecture is custom, many bugs
could not be effectively located by AI (GPT 5.3) at the time the project was completed — it
could only offer hypotheses — so I still had to reproduce the problem by hand and solve it the
old way.

So here I have selected three debug processes that I find relatively representative and remember
clearly (only a drop in the ocean of all the difficulties), recording the real bugs that
occurred and were resolved one by one in this project.

```
03-debug-pitfalls/
├── README.md
├── 01-hardware-pitfalls.md   Hardware pitfalls (memory byte alignment / async read / mask bits)
├── 02-software-pitfalls.md   Software pitfalls (UART buffer sharing / input ownership token)
└── 03-hw-sw-co-debug.md      Full hardware-software combined Debug record
```

## Quick Index by Type

| Pitfall to look for                                                           | Chapter |
| ----------------------------------------------------------------------------- | ------- |
| 8/16/32-bit memory access, barrel banks, mask-bit error                       | 01      |
| Async read cannot be synthesized into M9K, changed to sync read               | 01      |
| Shell/Game sharing the UART buffer, token mechanism                           | 02      |
| "Typing help returns banner", "hang after output", LED-state diagnosis        | 03      |
| WB retire stage non-idempotent, MPIE overwritten to 0, interrupt saves nextpc | 03      |
