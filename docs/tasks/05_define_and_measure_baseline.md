# 05_define_and_measure_baseline

状态：PENDING

操作：固定首帧、独立加载、renderer创建、峰值内存定义，采集至少5轮。

完成标准：中位数、范围、失败率、原始样本和同平台配置；区分采样上界与精确延迟。

边界：已有840MB客机预算记录，不重复作为其它任务阻塞。正式排名内存仍用统一采样协议。

交付：代码或明确定位结论、实际执行日志、结果JSON与简短交接说明。

工作目录：`D:\x-kernel-dsh-bridge\submission\for github`。原始日志：`experiments/FINALS-RUNS/<UTC>/`。

构建要求：源码、配置、bin与带符号ELF必须同源并保留哈希；归档ELF导出的bin与运行内核哈希不同，应先纠正这条复现链。
