# STATE

## 截止时间

- 硬停止：2026-10-30 09:00（Asia/Hong_Kong）
- 收尾开始：2026-10-30 08:45
- 到点后：停止新实验，保留当前分支/日志，写总结，不再启动新的 QEMU 长期任务。

## 当前最佳

- **口径决定（用户 2026-10-29 18:15）：先按宿主机 QEMU 工作集做 1.5G。**

- 本地最新提交：fd75466（本轮之后会有新提交）
- 远程最新提交：5081473（构建路径修复）
- 当前新构建内核：artifacts/kernel-procfs.bin
  - 大小 8,544,026 B
  - SHA-256 c915565ac145f95335088296edd93b7a9a7c097188781611eb48ba9d1e067785
- 已知可用基线：GitHub Release finals-baseline 的 kernel-procfs.bin（5261ceb3…）
- E000 验证：新构建 c915565… 启动通过（colors=892，两窗口，Alt+Tab 翻转）；**peak_ws≈2.15 GiB，未达 1.5G 资格线**
- E002 通过：30 HB、双窗口、colors=892；guest used 816MB，QEMU peak 2.36GB
- 下一步：**先按宿主 QEMU 工作集做 1.5G 资格线**；定位 E003 frame-watch 首帧失效；再做 5 次性能
- 新迭代：2026-10-29 18:15 起，deadline 2026-10-30 09:00；watchdog pwsh-11b8a52bb69249f8
- 新 goal：goal-f034baa0-9a2a-474e-87fe-a293f6d06e88

## 规则

1. 只操作 for github 和 runs/、experiments/、/tmp；不碰 D6-001。
2. QEMU 一律使用 -snapshot，不写交付镜像。
3. 每个实验一个分支/目录，可回退；不删除失败数据。
4. 性能判断用 5 次中位数；不以单次最好值下结论。
5. 峰值内存必须关注 1.5G 资格线。
6. 不提交 .bin、截图、视频；原始日志留在 experiments/ 下，必要时 gitignore。
7. 到 07:45 不再启动新的 30 分钟任务；到 08:00 强制停止。

## 当前优先级

1. E000：已完成（通过；peak_ws 2.15 GiB）。
2. E001：已完成（observe/monitor/hb/run-finals；warmup 修正）。
3. E002：30min 稳定性通过；QEMU peak 2.36GB，guest used 816MB。
4. E004：内存变体待跑。
5. E003：性能 5 次待跑。
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
- E001：observe/monitor/hb 已实现并提交 df5d108；待 run-finals 联调。
- watchdog：pwsh-10509d1bc0c549b5。

## E002 运行中

- monitor job: pwsh-0c95cc4cb5a44573
- xkwin job: pwsh-decee2b1e41940c2
- 启动 2026-10-29 01:03；预计 30 分钟后结束。
- 结束后用 python host/observe.py experiments/E002-stability30/run --expected-minutes 30 分析。

## Round 2 进度

- E001 工具已提交 df5d108；合成测试 CRASH/HANG/LEAK 命中。
- tests/load-loop.ps1、tests/stability30.ps1 已提交 fc57b5e。
- E002 30min 运行中：monitor pwsh-0c95cc4cb5a44573，xkwin pwsh-decee2b1e41940c2；预计 01:35 左右结束。

- E004：低内存 Chromium 变体已写（x4/x5c-lowmem），待 E003 后测试。

## PAUSED（2026-10-29 01:45 左右，用户关机）

- 所有 QEMU 已无进程；watchdog 已 kill；07:45/08:00 两个 schedule 已删除；goal 已 paused。
- E000 通过；E001 通过；E002 30min 稳定通过；E004 combined 功能通过但内存口径未定；E003 第一次运行无效（0.4s/无指标）。
- 本地有未推送提交；恢复时先读 STATE 与 experiments/INDEX.md。
- 恢复后：先修 E003 harness 调用，再跑负载循环/性能；不要重复 E003 无效数据。

## 2026-10-29 12:22 恢复

- 截止改为 13:45 收尾 / 14:00 硬停止；新 schedule 已建；watchdog 已改到 14:00。
- E002 30min + 10 次负载循环通过；E003 的 5 次性能仍无效（frame watch 首帧缺失）。
- 结果总表：experiments/RESULTS.md。

## STOPPED 2026-10-29 13:15

- 所有 QEMU 已停止；watchdog 已 kill；13:45/14:00 schedules 已删除；goal paused。
- 最后提交 e1777a6；E003 仍 invalid，E002/E004 结果见 experiments/RESULTS.md。

## WRAP 2026-10-29 13:05

- 无 QEMU、无后台 job、无 schedule；
- 本轮因用户要求停止，提前收尾；未完成项：E003 有效 5 次性能、1.5G 口径确认；
- 结果总表 experiments/RESULTS.md，最后提交 fd75466。

## E005 host-first 发现（18:25）

- -accel tcg,tb-size=256 的完整 smoke：宿主 peak 1,448,636,416 B（1.35 GiB），colors=892；
- 对照无 tb-size：2.31–2.36 GB；
- 说明 TCG 翻译缓存是宿主 1.5G 的主要组成；30min 复测已启动（E005-stability30/run）。
- 注意：这是 harness QEMU 参数，最终是否算分取决于统一脚本是否允许/内置。

## 口径修正（2026-10-29 18:50）

- **1.5G 是客机内 Chromium 使用的内存，不是宿主 QEMU 工作集。**
- E002/E005 guest used 816–840MB，作为保守上界 <1.5G；E006 记录。
- E005 host tb-size=256 仅诊断；xkwin 默认已恢复空（QEMU 默认 tcg）。
- chrome-mem per-process RSS 仍有 0 的 bug，不能引用；需要修 ps PID 解析。

## E006 结论（19:50）

- 用户澄清：1.5G 是客机内 Chromium 内存；
- E002 816MB、E005 840MB guest used，作为保守上界 <1.5G；
- chrome-mem per-process RSS 受内核限制（statm/VmRSS=0），不能引用；
- E005 宿主 tb-size 仅诊断，xkwin 默认已恢复。

## E006 完成（19:55）

- 1.5G = 客机 Chromium 内存；guest used 816–840MB，保守上界通过；
- E003d 5 次性能（默认 TCG）启动；首帧可能仍无效，报告中会标注；
- E005 宿主 tb-size 诊断不作为资格方案。

## E003d 5x（19:54）

- 默认 TCG；5 类 n=5：startup/renderer/peak/cpu/qemu-mem；
- page-load/first_frame 缺失；peak median 2039.8MB，spread 735；
- 不是完整 6 类性能基线；不要写成有效首帧。
