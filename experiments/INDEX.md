# 实验索引

| ID | 状态 | 主题 | 结果 | 决策 |
|---|---|---|---|---|
| E000 | pass (run3) | 新构建内核最小启动验收 | colors=892；两窗口；Alt+Tab 翻转；peak_ws≈2.15 GiB | 通过；但峰值内存未达 1.5G 资格线 |
| E001 | pass | 崩溃/卡死/泄漏观测工具 | observe/monitor/hb/run-finals 已落地；E002 联调通过 | 工具可用 |
| E002 | pass | 30 分钟稳定性 + 负载循环 | 30 HB + 10 次重载、colors=892；QEMU peak 2.32-2.36GB | 通过；内存口径待 E004 |
| E003 | partial (unstable) | 性能基线 5 次 | e003f 单次首帧 50.038s；e003g 3/3 仍 blank | 改用标准 x4 或继续定位 |
| E004 | partial | 峰值内存压到 1.5G | combined 功能通过；guest used 753MB；QEMU 2.11GiB | 待单变量与口径确认 |

> 状态只在实验结束时更新；不要把中间读数写成结论。

| E005 | partial | 宿主 QEMU 工作集 TCG tb-size 诊断 | tb-size=256：peak 1.45GB、colors=892；CPU 上升 | 待 30min 稳定 |

| E006 | in_progress | 客机 Chromium 内存 1.5G | chrome-mem.sh 已写 | 待跑 |
