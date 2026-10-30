# 07：修正时间源、发现指标与身份拒绝规则

优先级：P2。开始条件：可先离线处理；真实采集依赖01，有正常会话即可。预算2–4小时。

这是待执行任务，不是完成记录。工作目录为原工程 `D:\x-kernel-dsh-bridge\submission\for github`。

先读 [总计划与统一交付规则](00_review_and_plan.md)，结果新增到trace-followup对应编号目录。


## 本次只做

1. 当前源码 `kernel/core/ksyscall/src/time/queries.rs` 已有CLOCK_MONOTONIC分支。优先用小型静态AArch64 helper调用clock_gettime，验证运行中候选确实支持且时间推进/误差合理；源码有实现不等于当前bin已验证。无需先添加/proc/uptime。sysinfo仅作秒级备选，不作高精度延迟。
2. 宿主 `xkwin.ps1` 截图差值仍用UTC与LastWriteTime，解码器却标成Stopwatch。实现真实单调请求/观测完成时间，UTC只作追溯；修正历史字段标签，不能把旧值追写成单调值。
3. 采样起点和实际浏览器启动点分开记录。同一客机单调时钟下给出launch前后标记与发现区间；采样器先启动的MONO_T0不能直接当浏览器启动时刻。每6秒只是名义扫描周期，实际扫描较慢，区间要用真实时间。
4. `creation_mono_s/creation_after_t0_s` 改成发现时间/区间，除非取得真实创建事件。sample3的+37秒来自wall clock与采样起点，只能叫首次观测；18次匹配是重复观测，不是18个renderer。`proc_start_ticks=0` 不能当有效创建时刻。
5. 解码器不要把“有字段”当“可用于正式基线”；输出clock_valid/role_valid/lifecycle_valid/metric_valid/coverage及原因。所有记录须核对时钟标签一致、缺失/跳变显式失败。
6. 身份正常样本109→121→207/190保留通过；补State为Z/X、GONE、快照未闭合、旧会话和角色时间不匹配的拒绝。当前纯函数在构造的Z+Threads=1样本上会返回ok，不能仅靠Threads>0判断存活。

## 验收与交付

helper真实运行证据、宿主单调采集、同起点的发现区间、严谨有效性字段与身份负例通过。单位维持原始KiB及MiB换算，样本缺失不伪造。无真实创建接口时如实交付发现延迟，不冒充官方renderer创建指标。
