# 成果复核与实施任务书：把事件环从草案做成真实取证链

日期：2026-10-31（香港时间）。本轮复核对象为 `experiments/FINALS-RUNS/20261031T002500Z/iteration/`。读取01/02/03/05/06/07六项result、五份现存handoff、关键原始日志及实际代码；03未找到handoff，04/08–12尚无执行目录。本次只复核与写计划，未改业务/内核源代码、启动QEMU或执行发布。

## 结论与已完成成果

**01/02/06在各自声明范围内有真实成果，保留完成结论；主阻塞是03仍只有草案，04因此无法定位真实停顿。** 后续重点是实现而不是再次讨论环的必要性。宿主导出通道已经可用，但测试对象是宿主放入的128B不可变记录，不能等同内核事件链。

| 事项 | 本次独立检查 | 接下来的边界 |
|---|---|---|
| 01流式回执 | LF边界/ANSI echo修复保留；本次五个PowerShell检查及18项观测全部通过；真实日志含rc=0、上传哈希和预期rc=7 | B3仍出现eecho，说明送达/终端输入问题尚存；不是回退重做LF解析 |
| 02宿主读取 | record.bin哈希及校验重算通过；旧日志中running/paused读取一致，地址错误和坏记录拒绝 | 只证明通道；实际代码自动cont且未落实容量/短读保护，不适合直接取失败现场 |
| 03每CPU环 | result明确未改内核、未构建、无符号导出 | 草案还缺时间戳、头部容量及一致性细节；拆为02–05小任务 |
| 05导航对照 | 后批A3/3、B2/3，其中B3是命令通道失败；有效浏览器结果A3/3、B2/2 | 两组均无浏览器反例，不能证明B解决因果；另有前批6次失败须记入总尝试 |
| 06身份 | 重算同会话join通过：browser109，renderer207/190，父链经121且State=S | 当前正常样本可信；用于故障注入前还须补死进程/时间范围拒绝 |
| 07采样 | sample3原始37个内存点峰值960100KiB=937.60MiB；页面17.2678秒，首帧区间[40.042,50.044]秒 | 仍用wall；+37秒是观测时间；宿主Stopwatch标签不符实际UTC实现，尚非正式四项基线 |

## 新发现与修正依据

1. **事件环草案尚不能直接实现其排序目标。** 每条32B只有seq/state/kind/arg0/arg1，没有timer counter；但规则要求跨CPU按counter排序。4×1024×32已是131072B，header/控制区/padding另需预算。没有消费游标不能报告精确未读丢失数。下一步先用真实结构和模型补齐这些不变量，再构建。
2. **导出器会改变现场。** `host/qmp_memory_export.py`读取后自动cont，异常时可能不落报告；1MiB上限未在代码落实。独立16字节输入验证触发unpack异常。旧成功通道测试不受此否定；真实现场模式要冻结后读、保留停止态并写完整报告。
3. **A/B总账不能只留后六次。** `ab-results-pre.json`有6次非0，六份failed-pre归档存在；后批6次为5成功/1通道失败。共12次跨修复前后尝试应全部留账，不能当作同版本浏览器可靠率，更不能删除前批。原pre条目指向后来复用的目录，需建立归档映射。
4. **renderer“创建”标签过度解释。** `decode_perf_v2.py`仅将扫描PID与会话后段SystemInfo列表关联，+37秒是从采样器MONO_T0到首次发现，不是可证的创建延迟；18条匹配是重复观测。proc_start_ticks=0无有效起点，角色快照晚于扫描也有生命周期局限。
5. **时钟与采样频率仍不规范。** 宿主截图以DateTime/文件时间相减，解码器却称Stopwatch；客机循环sleep2再扫描，实际间隔会大于名义2/6秒。当前源码已有CLOCK_MONOTONIC syscall，应先在实际bin验证小helper，勿因无uptime文件直接扩大内核改动。
6. **正常身份核验不等于已覆盖所有死目标。** 当前assess只看Pid/Threads/父链，纯函数负例State=Z且Threads=1仍返回ok。需在注入前加强状态与时间校验；旧06的实际S状态正例仍有效。
7. **内存摘要应包含更高的已测值。** sample2的41个原始点峰值为961160KiB=938.63MiB，略高于sample3。sample2没有renderer角色匹配而不合格，但其内存测量不能因此删除。sample1无有效监控点，三轮不是三个完整性能样本。

## 先执行哪些

首批只做01、02、03：命令送达的小修可与环格式设计穿插，随后真实构建静态存储。预算分别约2–3、1–2、2–4小时，仅作投入参考。03必须交出bin/ELF与客机写入header的宿主读取证明，不能再用“设计已定”结束为COMPLETED。

第二批04→05，先拿真实timer/唤醒链，再取得可靠冻结dump。06用这条链捕获同版本成功/停顿对照并找第一个缺失事件。07的计时与身份代码可以提前独立推进；所有QEMU实验串行，不让监测、导航和根因实验共享会话。

之后做08有界扰动小试；09负责衔接原任务08–12。导航若没有新可证伪假设，不继续扩大A/B。20次首启、五轮正式基线和优化收益继续等待对应门槛，真实故障诊断可在身份与就绪条件满足时先准备。

## 编号短任务

| 编号 | 任务 | 开始条件/预算 |
|---|---|---|
| 01 | [确认命令送达并保存全部尝试](01_repair_command_delivery.md) | 可立即开始，预算2–3小时。 |
| 02 | [修正事件环格式与容量预算](02_finalize_ring_layout.md) | 可立即开始；不运行客机，预算1–2小时。 |
| 03 | [实现默认关闭的静态事件存储并构建](03_build_static_trace_storage.md) | 02通过；预算2–4小时。 |
| 04 | [接入少量真实timer与唤醒事件](04_capture_timer_wakeup_events.md) | 03通过；预算2–4小时。 |
| 05 | [让导出器适用于真实停顿现场](05_export_frozen_trace.md) | 03可开始小记录验证，04后做完整事件导出；预算1–3小时。 |
| 06 | [找首个缺失事件并验证单一补丁](06_locate_stall_and_fix.md) | 04、05可用，01达到送达验收；一轮假设预算4–8小时。 |
| 07 | [修正时间源、发现指标与身份拒绝规则](07_correct_time_and_identity_metrics.md) | 可先离线处理；真实采集依赖01，有正常会话即可。预算2–4小时。 |
| 08 | [验证采样扰动并有界复查导航策略](08_compare_observer_and_navigation.md) | 01、07通过；与其它QEMU实验串行。预算2–4小时。 |
| 09 | [回到稳定性、正式基线与决赛交付](09_reenter_acceptance_gates.md) | 06有可解释候选；01、07、08满足相应验收。 |

## 执行与交付规则

工作目录为 `D:\x-kernel-dsh-bridge\submission\for github`。新结果写入 `experiments/FINALS-RUNS/<new-UTC>/trace-followup/<NN>/`，只追加英文名文件。每任务至少提交result.json、handoff.md、实际diff或无代码变更说明、环境/命令/退出码、版本哈希和原始证据索引。字段含全部请求数、有效数、错误分类、首个未知边界与下一步。

- 每轮一个假设/一个主要变量，明确结束条件；运行超预算仍未解决就PARTIAL交接，不把设计、构建、通道测试、真实事件、根因和最终验收混成同一种完成。
- 不重跑有副作用的命令修补缺回执，不猜丢失rc；不对取证现场自动恢复。每次实验唯一目录，修复前后的失败都留账。
- 默认关闭诊断，完整环暂定不超过192KiB，单次导出不超过1MiB；只在有证据需要时调整并记录。正式性能对照不得混入开关/配置差异。
- 内核改动按AGENTS及工程构建/代码规范；性能工作按工程performance-analysis，先声明指标再取同条件对照。本轮未构建或跑客机，不将源码存在当实际bin已经通过。
- 保留上一轮14_plan_status.json原始状态，本轮重新给出待实施状态；无修改、提交、push、tag或删日志的操作记录不得冒称已执行。

## 复核记录与旧任务入口

- [本次复核审计、测试输出与来源哈希](10_review_audit.json)。
- [本计划状态](11_plan_status.json)，新任务尚未实施。
- [上一轮计划](../next_iteration/00_review_and_plan.md)及[执行状态](../next_iteration/14_plan_status.json)。
- [本轮结果入口](../../experiments/FINALS-RUNS/20261031T002500Z/iteration/01/result.json)、[环草案](../../experiments/FINALS-RUNS/20261031T002500Z/iteration/03/result.json)、[导出契约](../../experiments/FINALS-RUNS/20261031T002500Z/iteration/02/export-contract.json)。
- [A/B前批](../../experiments/FINALS-RUNS/20261031T002500Z/iteration/05/ab-results-pre.json)、[A/B后批](../../experiments/FINALS-RUNS/20261031T002500Z/iteration/05/ab-results.json)、[sample2较高内存](../../experiments/FINALS-RUNS/20261031T002500Z/iteration/07/sample2/perf-decode.json)、[sample3有效采集字段](../../experiments/FINALS-RUNS/20261031T002500Z/iteration/07/sample3/perf-decode.json)。

当前工程预算沿用用户确认约840MB历史客机占用，并保留此次约938.63MiB采样上界；不改称精确Chromium RSS或精确连续峰值。最终得分依统一平台与现场证据，现有进度不足以预测排名分。


<!-- post-checkpoint-20261031 -->

[推送后的新任务书](../stall_resolution/00_taskbook.md)：阶段分支已保存，先补取证完整性，再定位真实停顿。
