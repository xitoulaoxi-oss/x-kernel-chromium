# 08：依次恢复稳定性、性能与决赛交付

开始条件：05有可解释候选，06/07满足采集条件。

状态：WAITING_GATE；本文件为待执行任务。先读 [总任务书与日志规则](00_taskbook.md)。


这是下游任务入口；实际执行仍按每个短任务分别交付，不把所有结果合成一次PASS。

1. 同一冻结候选20/20首次启动、单会话完整功能、当前版本30分钟+10次加载；基础设施失败单列且保留总分母。参照 [旧08](../next_iteration/08_accept_stable_candidate.md)。
2. 同一组至少五轮四项有效数据，报告中位数/范围/首帧区间与时钟/身份/频率。参照 [旧09](../next_iteration/09_collect_five_run_baseline.md)。
3. 追溯首个可运行版本归档，逐项测最多三项跨层优化；收益超过测量不确定度才报百分比。参照 [旧10](../next_iteration/10_measure_three_optimizations.md)。
4. 正常身份和页面就绪后可独立进行真实crash、stop/恢复与有界leak，不必等三项优化完成。参照 [旧11](../next_iteration/11_validate_fault_diagnosis.md)。
5. 最终组合候选三场彩排、干净复现、上游合并核验及精简发布。参照 [旧12](../next_iteration/12_rehearse_and_package.md)。

本次阶段推送不等同最终发布；最终得分、资格与排名依现场统一平台。每次发布保留精简摘要/原始哈希，完整失败日志本地归档。
