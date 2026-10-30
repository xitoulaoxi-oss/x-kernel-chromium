# 03：补齐能支持因果定位的事件边界

开始条件：01/02通过。预计2–4小时。

状态：WAITING_GATE；本文件为待执行任务。先读 [总任务书与日志规则](00_taskbook.md)。


## 不能从当前环推断的事情

当前只接idle、部分timer_arm、timer_irq和IPI接收；没有IPI发送/入队/实际调度。100ms fallback分支没有同等timer_arm记录，已有arm事件在实际调用之前，不能直接当硬件已成功设定的证明。

## 工作与验收

1. 把正常deadline与fallback两条arm路径都覆盖，注明事件是请求/完成/状态观察；必要时记录counter、deadline单位、使能和IRQ屏蔽信息，保持字段预算。
2. 加入IPI send/recv及可关联ID、目标CPU，添加runnable enqueue和schedule边界。优先能回答“何时应唤醒、谁发起、是否入队、是否运行”的最小字段，不创建大而全追踪系统。
3. ticks、纳秒deadline与频率换算分别标注；跨CPU只能建立有证据的偏序。idle_return的skip/wake语义分别解释。
4. 正常会话导出一条timer链及一条send→recv→enqueue/schedule相关链；保存覆盖/丢弃与不确定处。事件缺一环不自动计为内核故障，先确认该路径应该发生。

交付：event-coverage.json、真实链与匹配源码/bin/ELF哈希。短对照测诊断开销，不把两次boot-to-shell约9秒当Chromium开销已验证。
