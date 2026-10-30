# 11_validate_fault_scenarios: 重做身份可证的真实故障诊断

优先级：P3。依赖：03和稳定就绪链；不必等待三项优化完成。状态：PLANNED，尚未执行。

工作目录：`D:\x-kernel-dsh-bridge\submission\for github`。

## 已知问题

当前pick只按Chromium父进程和线程数，尚不能证明PID154是renderer。FAULT_CRASH/STOP证明信号调用成功，不等同于已定位崩溃主体。tmpfs增长脚本明确不是Chromium泄漏，也不应这样归因。

## 本次只做

三个独立snapshot分别做崩溃、停止/恢复、受控内存持续增长。先由Chromium API确认renderer PID，再核对procfs身份/开始时间；短guest脚本负责信号、状态查询与CONT，避免复杂-Key命令。

## 完成标准

崩溃有正确主体和退出/信号证据；停止有T状态、存活证明和CONT恢复；增长有时间序列、控制/释放对照及归属。observer报告区分真实目标故障与通道/观测失败。

## 边界与交付

未配置心跳不能仅因无HB判卡顿。Crashpad遇到ptrace未实现需单独记录，不把其报错直接解释为内核死锁。增长测试设置上限且不依赖OOM制造结论。

交付：代码差异或明确定位结论、固定命令/版本、结果JSON、原始日志索引和下一步。原始实验新增在 `experiments/FINALS-RUNS/<new-UTC>/next-phase/11/`，不得覆盖旧失败。新文件只用英文命名；单轮未解决时如实写PARTIAL/FAIL。

## 必须先读

- `guest/fault-renderer.sh`
- `guest/fault-growth.sh`
- `evidence/2026-10-30/finals-tasks/task09/result.json`
- `evidence/2026-10-30/finals-tasks/task09/crash-observe.json`
