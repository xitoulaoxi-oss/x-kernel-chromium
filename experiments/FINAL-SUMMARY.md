# 本轮迭代总结（2026-10-30 停止）

## 结论

- 1.5G 资格线按客机内 Chromium 内存口径：guest used 816–840MB，作为保守上界低于 1.5G。
- E002 30 分钟稳定性 + 10 次负载循环通过。
- E001 观测工具、HTTP 脚本传输、性能采集工具已落地。
- E003 5 次性能仍不完整：有 5 类 n=5 的报告，但 page-load/first-frame 随机缺失；不能写成完整 6 类基线。

## 有效结果

| 项 | 结果 |
|---|---|
| E000 启动 | colors=892；双窗口；Alt+Tab 翻转 |
| E002 30min | 30 个 HB；chrome=16；colors=892；guest used 816MB |
| E002 负载循环 | 10 次 Ctrl+R；colors=892；post-warmup 增长 25.5MB |
| E006 客机内存 | guest used 816–840MB < 1.5G（保守上界） |
| E003 性能 | e003d 5 类 n=5；e003f 单次 first_frame=50.038s；无有效 5 次 page-load |

## 无效/未完成

- E003 随机 blank：标准 x4 5 次仅 2/5 有首帧；--disable-gpu 0/5；关闭后台网络 0/1；x4 等待 150s 仍 blank。
- 内核 /proc/<pid>/statm、status VmRSS、stat RSS 均为 0，per-process Chromium RSS 不可得。
- E005 宿主 tb-size 诊断（peak 1.45GB）不作为 1.5G 资格方案；默认 TCG 已恢复。

## 有效修改

- host/xkwin.ps1：空格路径处理、传输重试、-TbSize 诊断、默认空；
- host/perf_run.py：--disk、10s/300s frame watch；
- guest/c1-perf-x.sh：Xorg/JWM 3s settle；
- guest/http-boot.sh：HTTP 下载脚本，规避串口 heredoc 损坏；
- host/observe.py、monitor-qemu.ps1、guest/hb*.sh：观测工具；
- guest/x4-win1-nogpu/quiet 等失败变体保留在实验记录中，未作为方案。

## 证据

- experiments/RESULTS.md
- evidence/reports/perf-report-e003d.json（5 类部分）
- evidence/reports/perf-report-e003f.json（单次首帧）
- experiments/E002-stability30/decision.md
- experiments/E006-guest-chromium-mem/decision.md
