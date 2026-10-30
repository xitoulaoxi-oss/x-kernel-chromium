# 08_correct_metric_definitions: 纠正计时定义与不确定性

优先级：P2。依赖：01，可与02–05的分析并行。状态：PLANNED，尚未执行。

工作目录：`D:\x-kernel-dsh-bridge\submission\for github`。

## 已知问题

现有page_load_s是browser timeOrigin+loadEventEnd减宿主launch t0，包含浏览器启动，不是独立加载耗时。epoch_delta约34秒本身不能证明时钟同步。首帧四轮落在约50–60秒区间，10秒采样不能支持0.013秒真实性能波动。

## 本次只做

将启动到首帧、已启动浏览器内的独立页面加载、renderer创建、客机内存峰值分别定义。优先同一单调时钟域；需要跨主客机时钟时先测偏差/漂移并记录误差。保存前后边界和采样分辨率。

## 完成标准

形成版本化指标协议；旧数据重解析为区间，不改原文件。run01首帧应至少注明[50.031,60.044]s。renderer保留创建事件定义和角色证明；含缓存总占用按MemTotal-MemFree记录，并注明采样峰值及上界属性。

## 边界与交付

读取到毫秒不代表测量精度达到1ms。改善小于测量分辨率或噪声时不得写收益。历史首个可运行版本须核实已有提交/tag，不能把当前候选倒称历史基线。

交付：代码差异或明确定位结论、固定命令/版本、结果JSON、原始日志索引和下一步。原始实验新增在 `experiments/FINALS-RUNS/<new-UTC>/next-phase/08/`，不得覆盖旧失败。新文件只用英文命名；单轮未解决时如实写PARTIAL/FAIL。

## 必须先读

- `host/baseline_x4b.py`
- `evidence/baseline/x4b/run01/frame-watch.json`
- `evidence/baseline/x4b.json`
