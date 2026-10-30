# 07_calibrate_low_overhead_sampling: 建立低扰动renderer与内存采样

优先级：P2。依赖：01–03；设计可提前，正式试验在06后。状态：PLANNED，尚未执行。

工作目录：`D:\x-kernel-dsh-bridge\submission\for github`。

## 已知问题

所谓1Hz五轮全失败中，run02/03/04是cdp-policy上传失败；只有另两轮进入页面失败。当前资料不足以证明监控本身导致5/5失败。plain x4b未启动renderer计时器，却仍声明1Hz；客机内存结果字段硬编码None，读出的peak变量未使用。

## 本次只做

先修采集链完整性，再讨论频率。对照完全不监控、低频采样和目标频率；逐轮确认监控是否确实启动及首个异常。renderer应由同会话Chromium角色与PID/开始时间关联；优先稀疏创建事件后验匹配，避免每秒遍历全部procfs。

## 完成标准

监控启停、采样时间、丢样/丢事件、角色确认及开销均可检查。至少完成小规模同配置交错对照，基础设施失败单列；没有事件时报告缺失，不能补0或沿用其它轮次PID。

## 边界与交付

已有约840MB客机预算及约937MiB含缓存采样继续有效；此处补的是新候选四项排名基线中的同轮内存数据，不重新阻塞既有项目预算。

交付：代码差异或明确定位结论、固定命令/版本、结果JSON、原始日志索引和下一步。原始实验新增在 `experiments/FINALS-RUNS/<new-UTC>/next-phase/07/`，不得覆盖旧失败。新文件只用英文命名；单轮未解决时如实写PARTIAL/FAIL。

## 必须先读

- `host/baseline_x4b.py`
- `evidence/2026-10-30/finals-tasks/task05/baseline-monitor-perturbed.json`
- `evidence/baseline/x4final/run02/harness-error.txt`
