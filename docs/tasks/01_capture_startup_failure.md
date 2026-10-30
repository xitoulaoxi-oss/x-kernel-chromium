# 01_capture_startup_failure

状态：PARTIAL

操作：收集首次启动的浏览器/Xorg日志、进程、客机时钟、meminfo和QMP CPU状态。

完成标准：同一命令保存成功与失败；找到首个异常及所属边界。

边界：只加有界诊断，不改浏览器渲染参数或内核行为。

交付：代码或明确定位结论、实际执行日志、结果JSON与简短交接说明。

工作目录：`D:\x-kernel-dsh-bridge\submission\for github`。原始日志：`experiments/FINALS-RUNS/<UTC>/`。

本阶段进展：已完成有界诊断采样；首轮发现本地脚本CRLF故障，修复后单轮页面成功。随机空白/停顿的内核或浏览器根因尚未确认。
