# 03. Debug 踩坑指南

这一部分是整个文档的**精华**，记录了本项目真实发生、逐个解决的 debug 过程。

```
03-debug-pitfalls/
├── README.md
├── 01-hardware-pitfalls.md   硬件部分踩坑（内存字节对齐 / 异步读 / 掩码位）
├── 02-software-pitfalls.md   软件部分踩坑（UART 缓冲共享 / 输入所有权令牌）
└── 03-hw-sw-co-debug.md      硬软结合 Debug 完整实录（本次对话中的 bug）
```

## 按类型快速索引

| 想找的坑 | 所在章节 |
|----------|----------|
| 内存 8/16/32 位读写、滚筒式 bank、掩码位错 | 01 |
| 异步读无法综合成 M9K、改同步读 | 01 |
| Shell/Game 共享 UART 缓冲、令牌机制 | 02 |
| "输入 help 返回 banner"、"输出后卡死"、LED 状态诊断 | 03 |
| WB 退休拍非幂等、MPIE 被踏零、中断保存 nextpc | 03 |