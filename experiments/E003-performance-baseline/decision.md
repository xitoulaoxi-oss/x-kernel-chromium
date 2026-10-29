# E003 决策

## 运行 1（01:44）：无效，根因已定位

- 5 次运行均在约 0.4 s 内结束，所有宿主指标为 null；
- 根因：perf_run.py 调用 xkwin 时没有传 -Disk；for github 的父目录下没有 delivered/，harness 找不到镜像；
- 已修：perf_run.py 增加 --disk，默认找 ../../delivered/agentos-disk.img（相对 repo）。

## 运行 2（e003fix，单次）：harness 正常，但页面未画完

- 指标：chrome_s=9, renderer_s=41, peak_mem_mb=2029.7, cpu_pct=176.46；
- **first_frame_s 缺失**，zz-final colors=268，仍是空白窗口+spinner；
- 不能作为页面加载/首帧的有效样本；需要先修 perf 启动链或换回标准 x4 流程。

## 运行 3（e003b，5 次）：进行中

- 如果 5 次仍有 first_frame_s 缺失，E003 标记为无效，不进入报告结论。

## 运行 4（E003std，标准 x4 + frame watch）：仍无效

- x4 正常脚本单独跑时是 colors=835；
- 套上 frame watch 后最终帧 colors=262，first frame NOT FOUND；
- 说明问题在 frame watch / c1-perf-x / c2 启动链，不是页面文件；
- E003 仍不写 5 次性能结论。

## 运行 5（e003d，默认 TCG，5 次）

- 5 个类有 n=5：startup、renderer、peak-memory、cpu-usage、qemu-memory-rate；
- **page-load/first_frame 仍缺失**（frame watch 没有首帧）；不能算完整 6 类；
- peak_mem_mb median=2039.8, min=1347.8, max=2083.0, spread=735.2；
- cpu_pct median=193.98, min=60.67, max=195.78；
- run 3 是异常低内存/低 CPU 样本（log_bytes=2278，页面未起）；报告保留，不挑最好值。
- 报告 evidence/reports/perf-report-e003d.json；原始会话在 evidence/perf/e003d*（已忽略）。

## 运行 6（e003f，单次修复验证）

- 修复 1：c1-perf-x 在 Xorg socket 后等 3s 再起 JWM，JWM 后等 3s；
- 修复 2：frame watch 改为 10s 间隔 / 300s 窗口（2s/5s 会阻止页面绘制）；
- 结果：first_frame_s=50.038（bracket 40.037..50.038），colors 835；
- 这是首个有效的 host first-frame 样本；5 次 e003g 运行中。
