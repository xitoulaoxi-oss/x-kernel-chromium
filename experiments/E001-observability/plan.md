# E001 崩溃 / 卡死 / 泄漏观测工具

## 目标

为决赛“观测工具与测试套件”10 分补齐三类可复用的定位能力，并提供一个一键入口。

## 设计

### 崩溃

- 扫描 guest console：panic、SIGSEGV、SIGILL、segfault、Aw Snap、QEMU exit；
- 记录 QEMU 退出码、最后 200 行 console、qemu-cmd、metrics；
- 输出 crash.json + 一行结论。

### 卡死

- guest 心跳：每分钟写时间戳、窗口数、chromium 进程数；
- host 看门狗：超过 N 分钟无心跳或窗口数异常，判定 hang；
- 保留 console 尾部与最后的 screendump stats。

### 泄漏

- 30 分钟/负载循环期间采样宿主 QEMU WorkingSet 与 guest free -m；
- 输出趋势（斜率、峰值、增量）与阈值判断；
- 不伪造 VmRSS；只用 QEMU 工作集与整机内存。

## 交付

- tests/observe.ps1：三类检查的统一入口；
- tests/run-finals.ps1：串 30min / load-loop / tabs / input / JS / CSS / perf；
- docs/observability.md：用法与判据；
- 每次运行的 evidence 摘要。

## 验收

- 人为制造/模拟一次崩溃、一次 hang、一次内存增长，工具都能给出文件与结论；
- 一键运行不需要人工读 console；
- 文档给出命令与输出字段说明。
