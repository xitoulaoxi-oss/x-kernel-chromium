# 实验索引

| ID | 状态 | 主题 | 结果 | 决策 |
|---|---|---|---|---|
| E000 | pass (run3) | 新构建内核最小启动验收 | colors=892；两窗口；Alt+Tab 翻转；peak_ws≈2.15 GiB | 通过；但峰值内存未达 1.5G 资格线 |
| E001 | pass | 崩溃/卡死/泄漏观测工具 | observe/monitor/hb/run-finals 已落地；E002 联调通过 | 工具可用 |
| E002 | pass (stability) | 30 分钟稳定性 + 负载循环 | 30 HB、双窗口、colors=892；QEMU peak 2.36GB | 稳定通过；内存口径待 E004 |
| E003 | planned | 性能基线 5 次 | plan.md 已写 | 待 E002 后执行 |
| E004 | planned | 峰值内存压到 1.5G | 低内存变体已写 | 待 E003 后执行 |

> 状态只在实验结束时更新；不要把中间读数写成结论。
