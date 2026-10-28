# E003 决策

## 运行 1（2026-10-29 01:44）：无效，不作为数据

- 5 次运行均在约 0.4 s 内结束，所有宿主指标为 null；
- 没有生成 evidence/perf/e003* 会话目录；
- 报告 evidence/reports/perf-report-e003.json 写成 0 类覆盖；
- 原因未查（暂停前未展开）；**不要把这 5 次当作性能结果**。

## 恢复后第一步

- 检查 perf_run.py 调用 xkwin 的完整参数与 harness-error；
- 先手工跑一次 xkwin 验证；
- 修好后再重跑 5 次。
