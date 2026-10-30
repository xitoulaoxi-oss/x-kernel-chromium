# Performance measurement status

决赛四项为启动首帧、独立页面加载、renderer 创建延迟和峰值内存，每项至少五次并报告中位数和范围。当前没有完整有效的四项五轮基线，也不发布 before/after 改善百分比。

用户确认：1.5G 限制指客机内 Chromium 使用的内存，包括浏览器、renderer 和相关子进程。可靠的逐进程驻留统计与峰值采样仍未补齐；主机 QEMU 工作集、客机 `free` used、VmSize 均不能直接证明该资格线。RSS 求和还可能重复计算共享页。

`host/perf_run.py` 保留历史诊断采集能力，但默认返回未通过；`--collect-only` 明确表示仅采集诊断值。zygote 子进程推测不计作已验证 renderer 创建延迟，QEMU 工作集明确标注为主机指标。子命令退出码和 stderr 一并保留。

CDP 与抓帧会影响时序。未来比较必须冻结源码、页面、内核和启动参数，使用相同平台与计时定义，保留失败率。历史旧读数见 Git 历史，不据此推算当前成绩。
