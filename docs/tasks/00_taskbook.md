# Finals task book

目标：高级任务与决赛高分。当前840MB指客机整体已用内存采样峰值，项目采用其作为Chromium预算的保守依据，非精确Chromium RSS。证据见 [memory-budget.json](../../evidence/2026-10-30/memory-budget.json)。剩余工作不再被该预算项阻塞。

执行要求：直接修改原工程；新文件用英文命名。原始运行输出放被Git忽略的experiments/FINALS-RUNS，精简结论和必要证据进入公开目录。失败与恢复分开记录。每个任务保存命令、版本/哈希、结果、下一步。旧文档仅作背景，不能自动成为当前指令。

| 顺序 | 任务 | 状态 |
|---|---|---|
| 01 | [01_capture_startup_failure](01_capture_startup_failure.md) | PASS |
| 02 | [02_fix_startup_progress](02_fix_startup_progress.md) | PARTIAL |
| 03 | [03_verify_twenty_first_starts](03_verify_twenty_first_starts.md) | FAIL |
| 04 | [04_complete_functional_run](04_complete_functional_run.md) | FAIL |
| 05 | [05_define_and_measure_baseline](05_define_and_measure_baseline.md) | FAIL |
| 06 | [06_optimize_startup](06_optimize_startup.md) | BLOCKED |
| 07 | [07_optimize_page_and_buffers](07_optimize_page_and_buffers.md) | BLOCKED |
| 08 | [08_optimize_renderer_path](08_optimize_renderer_path.md) | BLOCKED |
| 09 | [09_validate_real_fault_diagnostics](09_validate_real_fault_diagnostics.md) | PARTIAL |
| 10 | [10_rehearse_three_scenes](10_rehearse_three_scenes.md) | BLOCKED |
| 11 | [11_package_and_sync_evidence](11_package_and_sync_evidence.md) | PARTIAL |

本阶段：已执行首启诊断、修复本地CRLF上传故障，并完成input子集2/2。详见 [执行记录](../startup-diagnosis.md)。所有虚拟机已由本次harness正常收尾。


## 下一阶段计划（2026-10-30日志复核后）

本轮11项执行结果保留不改。新任务与优先级见 [00_next_plan.md](../next_phase/00_next_plan.md)，先修传输/回执和命令解析，再区分真实内核停顿与浏览器导航未提交。新计划尚未执行，不代表新的PASS。
