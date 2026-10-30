# Performance measurement status

决赛四项为启动首帧、独立页面加载、renderer 创建延迟和峰值内存，每项至少五次并报告中位数和范围。当前没有完整有效的四项五轮基线，也不发布 before/after 改善百分比。

用户确认：1.5G 限制指客机内 Chromium 使用的内存，包括浏览器、renderer 和相关子进程。项目按用户确认，采用历史客机整体已用内存最高约840MB作为Chromium预算依据（见 evidence/2026-10-30/memory-budget.json），不冒称这是精确逐进程RSS。正式峰值排名仍需统一采样口径；共享页、缓存和采样间隔需要注明。

`host/perf_run.py` 保留历史诊断采集能力，但默认返回未通过；`--collect-only` 明确表示仅采集诊断值。zygote 子进程推测不计作已验证 renderer 创建延迟，QEMU 工作集明确标注为主机指标。子命令退出码和 stderr 一并保留。

CDP 与抓帧会影响时序。未来比较必须冻结源码、页面、内核和启动参数，使用相同平台与计时定义，保留失败率。历史旧读数见 Git 历史，不据此推算当前成绩。

附加复现检查：归档ELF导出二进制与当前运行内核的哈希不一致。正式基线应重建或取得匹配的bin/ELF及配置，不能直接依据旧ELF行号修改当前内核。

## 2026-10-30 measurement attempt

- Rebuilt `kernel-final.bin` with matching `kernel.elf` and config (same build): bin `c50075b6…`, ELF `1b0c758d…`, config `fbd1615b…`.
- Plain x4 launch under a 10 s frame watch: six rounds, four valid. First frame n=4, median 60.046 s, spread 0.013 s; page load n=4, median 51.454 s, spread 3.774 s. Failure rate 2/6.
- Renderer creation n=0: starting a 1 Hz monitor before launch made startup fail 5/5, so those runs were discarded rather than reported. Guest peak memory n=0. Host QEMU peak n=6, median 2058 MB.
- Therefore the four-metric five-round baseline is still not qualified; no before/after percentage is published. Raw: [baseline-x4b.json](../evidence/2026-10-30/finals-tasks/task05/baseline-x4b.json).

## 2026-10-30 metric correction

The `51.454 s` page-load value above is **superseded**: it subtracted the host launch t0 from a browser epoch and included browser startup. The corrected independent page load is `loadEventEnd - navigationStart` on the browser clock. On the same four valid x4b runs it is median **17.56 s** (range 16.77-20.62 s), n=4.

The first-frame value is a sampling bracket, not a 0.013 s point estimate: run01 is `[50.031, 60.044] s` at a 10.013 s frame interval. Renderer creation and guest memory still have n=0 for that set. The versioned protocol and reparse are in `experiments/FINALS-RUNS/20261030T150157Z/next-phase/08/metric-protocol.json`; originals were not modified.


## 2026-10-31 checkpoint clarification

补充纠偏：旧监控5轮中3轮是上传失败，不能据此断言监控导致5/5失败。sample2/3客机整体占用抽样最大值分别938.63/937.60MiB；renderer +37秒仅为wall时钟相对采样器起点的首次发现，不是创建延迟。宿主首帧实现仍需对齐单调时钟。
