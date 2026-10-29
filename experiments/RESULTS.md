# 实验结果总表（2026-10-29 恢复后）

## 结论先行

- 功能/稳定性：E000、E002 通过；E001 工具完成；E004 combined 功能通过。
- 性能：**E003 没有拿到有效的首帧/页面加载 5 次样本**，不能把无效运行写成指标。
- 内存：客机 used 约 753–816 MB；宿主 QEMU 峰值 2.26–2.36 GB。1.5G 资格线口径未固定，宿主口径下仍未通过。

## 实验

| ID | 状态 | 证据 | 关键读数 |
|---|---|---|---|
| E000 | pass | experiments/E000-baseline/run3 | colors=892；双窗口；Alt+Tab 翻转；peak_ws≈2.31 GB |
| E001 | pass | host/observe.py、monitor-qemu.ps1、guest/hb*、docs/observability.md | 合成 CRASH/HANG/LEAK 命中；E002 真实会话联调通过；warmup 默认 5 min |
| E002 | pass | experiments/E002-stability30/run、E002-loadloop/run | 30 个 HB；10 次 ctrl+r；colors=892；guest used 816 MB；QEMU peak 2.32–2.36 GB；post-warmup 无泄漏 |
| E003 | partial (flaky) | e003d report；E003-standard5/run1..5 | 5 类 n=5 无首帧；标准 x4 只有 2/5 找到首帧（50–60s），3/5 页面 blank |
| E004 | partial | experiments/E004-combined/run | 功能通过；guest used 753 MB；QEMU peak 2.26 GB；相对基线只降约 97 MB |
| E005 | invalid (for qualification) | experiments/E005-tb256b/run | 宿主 tb-size=256：peak 1.45GB、colors=892；仅诊断，用户澄清 1.5G 指客机 Chromium |
| E006 | pass (upper bound) | experiments/E002-stability30/run、E005-stability30/run | guest used 816–840MB <1.5G；per-process RSS 脚本仍有 bug |

## 关键事实

1. E002 的逐步截图里，正常的 x4-win1 是 colors=835；说明页面本身能画。
2. 一旦套上 perf 的 frame watch/c1-perf-x 链，最终帧回到 colors=262（空白+spinner），first_frame 缺失。
3. perf_run.py 原先没有传 -Disk；for github 的父目录下没有 delivered/，所以 5 次全部 0.4 s。已加 --disk。
4. 1.5G 若按宿主 QEMU 工作集，本机当前 2.2 GB 左右，差距约 0.7 GB；若按客机 used，0.8 GB 在内。必须先固定口径。

## 可回滚点

- 本地提交（未 push）：
  - 6b925de fix(perf): pass disk image to harness
  - 87e0152 test(e002): 30min stability pass
  - 5423cc2 test(e004): record combined memory result
- 变体脚本：guest/x4-win1-lowmem.sh、x5c-win2-lowmem.sh、x4-win1-disk.sh、x4-win1-memflags.sh
- 原始日志在 experiments/*/run*/ 与 evidence/perf/*，不提交大文件。

## 恢复后的优先级

1. 先固定 1.5G 口径（问组委会/看统一脚本）。
2. 修 perf frame-watch 的首帧检测：确认是 c1-perf-x 的 Xorg 配置、screendump 时序，还是 c2 启动链。
3. 再跑 5 次性能；没有 5 个完整样本就不写性能结论。
4. E004 只做单变量 + 30 分钟复测，不把 3 分钟 smoke 当稳定结论。

| E008 | invalid | experiments/E008-nogpu5/run1..5 | 单次 x4-nogpu 70.064s/835；5 次 0/5，final 262–265 |
