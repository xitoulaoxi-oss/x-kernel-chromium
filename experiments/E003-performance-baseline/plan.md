# E003 性能基线（5 次）

## 目标

用当前构建内核跑 5 次，得到首帧、页面加载、renderer、峰值内存、CPU、QEMU 内存率的中位数与波动；确认 1.5G 资格线。

## 命令

~~~powershell
python host\perf_run.py --repeats 5 --tag e003 --kernel artifacts\kernel-procfs.bin --out evidence\reports\perf-report-e003.json
~~~

## 记录

- evidence/reports/perf-report-e003.json
- evidence/perf/e003*/（运行目录）
- 若某项缺样本，报告保留 n 和原因，不剔除。

## 判据

- 每类 >=5 个完整样本；
- 峰值内存必须对照 1.5G 资格线；
- 与 finals-baseline（旧内核）做同口径 before/after，不用旧代指标。

## 内存口径

在同一会话里同时采集：

- 宿主 QEMU 工作集（qemu-metrics.json / monitor observe.jsonl）；
- 客机 free -m 的 used 与 buff/cache（guest/mem.sh）；

如果 1.5G 指宿主工作集，必须看 page cache；如果指 guest used，不能把 QEMU RSS 当判据。报告里两个数都写，不混用。
