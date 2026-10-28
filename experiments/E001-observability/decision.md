# E001 决策

## 已完成

- host/observe.py：会话级崩溃/卡死/泄漏分析，输出 JSON；
- host/monitor-qemu.ps1：QEMU 工作集/CPU/线程采样，写 observe.jsonl；
- guest/hb.sh、hb-start.sh、hb-dump.sh：客机分钟心跳；
- tests/observe.ps1：一键分析；
- docs/observability.md：判据与用法。

## 验证

- E000 run3 分析：summary=NO_CRASH_HANG_LEAK；leak=insufficient_data（没有 monitor 采样，如实标注）。
- 合成会话（panic + blank + 内存增长）分析：CRASH/HANG/LEAK 全部命中，--strict 返回 1；测试目录已删除。
- guest/hb*.sh 通过 WSL sh -n；monitor-qemu.ps1 通过 PowerShell parser。

## 未完成

- monitor 尚未与一次真实 QEMU 会话联调；
- tests/run-finals.ps1 尚未实现（30min/load-loop/tabs/input/JS/CSS 编排）。
