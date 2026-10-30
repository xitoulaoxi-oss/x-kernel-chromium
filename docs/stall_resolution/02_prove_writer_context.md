# 02：证明每CPU写入的独占与发布顺序

开始条件：可先审查；合并验证依赖01。预计2–4小时。

状态：READY；本文件为待执行任务。先读 [总任务书与日志规则](00_taskbook.md)。


## 已知实现与待证风险

`trace_ring::record`对seq做load/store并复用槽位，没有在重写前清除commit；它假定每CPU只有一个writer。但run_idle的IDLE_RETURN可在drop IRQ guard之后记录，定时器/重调度IPI也写同一CPU区域。当前没有完整的同核中断/抢占/迁核独占证明。这里是代码层面的风险，不冒充已经捕获到的运行损坏。

## 工作与验收

1. 阅读kernel/AGENTS、code-guidelines的unsafe/concurrency及现有IRQ/抢占封装。逐个列出init/idle/timer/IPI调用的IRQ、抢占、CPU固定条件；检查初始化完成到次核可写的顺序。
2. 用工程现有机制建立极短的同核独占，或实现可证明的重入协议。只换fetch_add不能自动保证槽位发布、metadata与冻结解码一致。避免全局锁、分配、热路径I/O；记录器自身不能触发递归记录。
3. 明确复用槽位的失效、payload写入、commit与seq更新顺序；暂停可能落在任意指令，01解码器必须拒绝半写，不将旧commit位当新payload完成证明。对齐、原子/非原子访问和生命周期要有具体安全依据。
4. 针对嵌套、迁核、绕回及每个暂停位置做模型/必要内核验证；重新构建诊断与关闭版，保存bin/ELF/config。默认关闭的正式路径不得保留记录器开销。

交付：上下文表、设计不变量、最小diff、针对性测试和实际构建记录。没证明写入一致性前，暂停用“缺少事件”推断timer/IPI丢失。
