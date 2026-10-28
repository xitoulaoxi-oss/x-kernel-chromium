# STATE

## 截止时间

- 硬停止：2026-10-29 08:00（Asia/Hong_Kong）
- 收尾开始：2026-10-29 07:45
- 到点后：停止新实验，保留当前分支/日志，写总结，不再启动新的 QEMU 长期任务。

## 当前最佳

- 本地最新提交：1678fe9（含 Cargo.lock 更新）
- 远程最新提交：5081473（构建路径修复）
- 当前新构建内核：artifacts/kernel-procfs.bin
  - 大小 8,544,026 B
  - SHA-256 c915565ac145f95335088296edd93b7a9a7c097188781611eb48ba9d1e067785
- 已知可用基线：GitHub Release finals-baseline 的 kernel-procfs.bin（5261ceb3…）
- E000 验证：新构建 c915565… 启动通过（colors=892，两窗口，Alt+Tab 翻转）；**peak_ws≈2.15 GiB，未达 1.5G 资格线**
- 下一步：E001 联调 monitor + run-finals；E003 性能基线时必须把内存资格线纳入

## 规则

1. 只操作 for github 和 runs/、experiments/、/tmp；不碰 D6-001。
2. QEMU 一律使用 -snapshot，不写交付镜像。
3. 每个实验一个分支/目录，可回退；不删除失败数据。
4. 性能判断用 5 次中位数；不以单次最好值下结论。
5. 峰值内存必须关注 1.5G 资格线。
6. 不提交 .bin、截图、视频；原始日志留在 experiments/ 下，必要时 gitignore。
7. 到 07:45 不再启动新的 30 分钟任务；到 08:00 强制停止。

## 当前优先级

1. E000：已完成（通过，但 peak_ws 2.15 GiB 超 1.5G）。
2. E001：观测工具 partial（observe/monitor/hb 已完成；待联调 + run-finals）。
3. E002：30 分钟稳定性 + 10 次负载循环。
4. E003：性能基线 5 次（首帧、页面加载、renderer、峰值内存）。
5. E004+：单变量性能/跨层实验，保留或回退。

## 日志入口

- experiments/INDEX.md
- 每轮 experiments/EXXX/plan.md / decision.md / run/summary.md
- 不在对话中粘贴完整 console，只用摘要和 grep。

## 运行记录

- E000 run1：QEMU -kernel 路径空格失败；已修。
- E000 run2：HTTP staging 路径空格失败；已修。
- E000 run3：通过；日志 experiments/E000-baseline/run3/（已 gitignore）。
- E001 待开始。
- watchdog：pwsh-10509d1bc0c549b5。
