# 下一阶段任务书：先证明取证可信，再定位启动停顿

日期：2026-10-31（香港时间）。已推送阶段分支 [checkpoint/trace-ring-20261031](https://github.com/xitoulaoxi-oss/x-kernel-chromium/tree/checkpoint/trace-ring-20261031)，并经远端查询核对阶段提交 `8992cf0b6a0c83bf5493f876e271775ba8efc3dd`。本文件在推送成功后生成，包含8个短任务；新任务尚未执行。

## 已保存的成果及下一步判断

阶段提交保存累计命令协议修复、候选100ms idle fallback、默认关闭的真实事件环、开启/关闭构建配置、冻结导出和精简证据。9组发布前回归/语法检查通过；真实构建与QEMU结果来自既有日志，本次没有重新运行。详见 [公开阶段证据](../../evidence/2026-10-31/trace-checkpoint/README.md)。

**先处理发布前新发现的记录完整性问题，再开始真实停顿的因果分析。** 满容量环目前1024条只解出1023条，且未来seq=9000可在metadata seq=1时通过；这些已由新增模型探针复现。写入端的同核IRQ/抢占独占仍需证明；现事件还缺IPI发送、入队、实际调度及fallback arm覆盖。已有4092条事件表明链路能工作，不足以自动证明“缺某事件就是内核漏唤醒”。

## 执行顺序

首批01/02/04，02先审查真实调用上下文，01和04先做离线负例。预计1–2、2–4、1–2小时，仅为投入预算。不能只交新草案；每项分别交补丁、失败用例变为通过的证据与边界。

第二批03补真实事件边界，之后05捕获同一版本正常/真实停顿对照并做单一修复。06可提前独立实现时钟，07验证身份与采样开销；所有QEMU实验串行。08在门槛成立后再恢复验收、五轮、优化、诊断和彩排。

| 编号 | 短任务 | 初始状态 |
|---|---|---|
| 01 | [修复解码窗口与异常记录校验](01_fix_ring_decoder.md) | READY |
| 02 | [证明每CPU写入的独占与发布顺序](02_prove_writer_context.md) | READY |
| 03 | [补齐能支持因果定位的事件边界](03_complete_wakeup_events.md) | WAITING_GATE |
| 04 | [保留中途导出失败的全部证据](04_harden_capture_failures.md) | READY |
| 05 | [捕获真实停顿并做一个可解释修复](05_capture_stall_and_fix.md) | WAITING_GATE |
| 06 | [落实单调时钟和正确的观测指标](06_validate_metric_clocks.md) | READY |
| 07 | [验证身份负例与采样扰动](07_validate_identity_and_observer.md) | WAITING_GATE |
| 08 | [依次恢复稳定性、性能与决赛交付](08_run_acceptance_gates.md) | WAITING_GATE |

## 统一工作与日志规则

- 工作目录：`D:\x-kernel-dsh-bridge\submission\for github`。每个新任务结果追加到 `experiments/FINALS-RUNS/<new-UTC>/stall-resolution/<NN>/`，英文文件名；不得覆盖旧dump、失败或结果。
- 最少交付result.json、handoff.md、实际diff、环境/命令/退出码、bin/ELF/config/page哈希、所有尝试分母及证据索引。PLANNED/READY不是已完成；未解决写PARTIAL和下一条可证伪问题。
- 诊断默认关闭，当前环164224B，上限预算192KiB；单次导出上限1MiB。无界中断日志、盲目扩批和混用不同bin/ELF均不能代替定位。
- 真实目标命令不因丢回执而自动重跑，取证不默认恢复现场。记录器/工具错误、全客机停顿、浏览器无窗口和DOM失败分别记类。
- 正式比较不得混用监控频率、诊断开关或不同页面；客机总占用、逐进程RSS、抽样峰值与连续峰值分别标注。当前不承诺优化收益或决赛总分。

## 发布记录

[阶段发布记录](10_publication_record.json)保存已核对的阶段提交、测试与精简范围；[任务状态](09_plan_status.json)独立记录本阶段任务。本任务书会随随后文档提交同步到相同阶段分支。完整原始实验、895项旧基线会话文件、重复submission包及二进制保留本地，没有在本次推送中全量加入。
