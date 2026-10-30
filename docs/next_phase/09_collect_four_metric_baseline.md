# 09_collect_four_metric_baseline: 完成同版本四项至少五轮基线

优先级：GATE。依赖：06–08。状态：PLANNED，尚未执行。

工作目录：`D:\x-kernel-dsh-bridge\submission\for github`。

## 已知问题

现有x4b是6次请求、4次有效：run05为上传失败，run06为浏览器角色接口失败；不能把两个失败都称同一种启动故障。首帧/启动到load只有n=4，renderer与客机内存n=0，原报告保留为不合格历史。

## 本次只做

先做一轮校准，确认四个字段都有真实来源，再跑至少五个完整有效轮次。记录所有请求轮次、错误类别、原始值、分辨率、中位数、范围和失败率。固定纯TCG、4核/4G及设备/页面/代码配置，不并行运行其它QEMU负载。

## 完成标准

四项各n≥5，来源可复算且属于同一冻结候选；所有失败仍在总账。五个有效样本不能被描述为五次请求全部成功。缺字段、时钟未校准、PID不明、上传失败均返回非零/不合格。

## 边界与交付

不把宿主QEMU峰值或早退轮次146MB充作客机Chromium峰值。三项优化只在此闸门通过后进入。

交付：代码差异或明确定位结论、固定命令/版本、结果JSON、原始日志索引和下一步。原始实验新增在 `experiments/FINALS-RUNS/<new-UTC>/next-phase/09/`，不得覆盖旧失败。新文件只用英文命名；单轮未解决时如实写PARTIAL/FAIL。

## 必须先读

- `evidence/2026-10-30/finals-tasks/task05/result.json`
- `evidence/baseline/x4b/run05/harness-error.txt`
- `evidence/baseline/x4b/run06/harness-error.txt`
