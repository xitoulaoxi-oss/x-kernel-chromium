# 04_trace_idle_wakeup: 定位真正的全客机失去推进

优先级：P1。依赖：01–03。状态：PLANNED，尚未执行。

工作目录：`D:\x-kernel-dsh-bridge\submission\for github`。

## 已知问题

旧run4长时间四核同PC、QMP仍running是停顿证据，但旧bin与重建符号身份尚需核对，不能据此排除所有其它原因。新C07在100ms兜底tick后仍停顿，说明该补丁尚非充分修复。检查实际timer deadline/控制位、计数器、IRQ屏蔽/待处理中断、runqueue与唤醒序号。

## 本次只做

仅针对控制通道正常、启动后时钟与串口均停止的样本排查。冻结bin/ELF后，在idle进入、timer rearm、timer IRQ、远端唤醒/IPI、入队/出队边界记录少量可关联事件。优先每CPU内存环形记录与事后导出，避免在热路径持续打串口。

## 完成标准

至少一对同版本成功/失败轨迹指出首个缺失事件：定时器未触发、IRQ未交付、唤醒未入队、调度未运行或其它具体边界。候选修复需有针对此边界的回归和一次单变量对照，之后才进入06。

## 边界与交付

100ms tick保留为待评估候选，不当作已证实修复，也不盲目缩短周期凑通过。SMP数量、GIC模式等只作单独诊断对照，不能替换正式平台评分配置。

交付：代码差异或明确定位结论、固定命令/版本、结果JSON、原始日志索引和下一步。原始实验新增在 `experiments/FINALS-RUNS/<new-UTC>/next-phase/04/`，不得覆盖旧失败。新文件只用英文命名；单轮未解决时如实写PARTIAL/FAIL。

## 必须先读

- `evidence/2026-10-30/finals-tasks/task01/startup-capture/startup-capture.json`
- `experiments/FINALS-RUNS/20261030T110856Z/task03b/C07/console.log`
- `kernel/task/ktask/src/api.rs`
