# 06：落实单调时钟和正确的观测指标

开始条件：可独立离线推进，真实验证需一个就绪会话。预计2–4小时。

状态：READY；本文件为待执行任务。先读 [总任务书与日志规则](00_taskbook.md)。


## 工作与验收

1. 在实际候选上验证小型静态AArch64 clock_gettime(CLOCK_MONOTONIC) helper；源码已有分支不等于bin通过。先复用接口，不因无/proc/uptime就扩大内核改动。
2. 宿主首帧请求/完成均用同一单调基点；UTC仅追溯，不用文件mtime相减冒充Stopwatch。历史数据保留旧标签和采样区间。
3. 浏览器launch前后在客机同一时钟记录标记，和先启动的采样器t0分开。没有真实创建事件时输出renderer首次发现区间；+37秒wall相对采样起点不能改名创建延迟。
4. 页面加载用同一浏览器Navigation Timing相减；内存保留原始KiB、MiB与客机总量口径。采样间距用实际时间，不把sleep2写成严格2秒。

交付：实际helper与host时钟验证、明确metric_valid字段与缺失原因、可复算的一个试采。保留938.63MiB历史较高抽样值及用户约840MB预算依据；不称精确Chromium RSS，不拼接五轮。
