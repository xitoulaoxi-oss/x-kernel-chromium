# 02：让一次尝试有可靠终态与退出码

状态：WAITING_GATE。依赖01；预算1–2小时。

先读 [总任务书](00_taskbook.md)。本文件是待执行任务，本次复核没有执行这些修改。


## 直接修现有脚本问题

输入：143000/stall-resolution/05/run_stall_attempts.ps1。它以“没有harness-error”判success，等待超时后还可能强杀外层；QEMU检查匹配所有同名进程；没有记录外层真实退出码。

1. 复用现有smoke/functional/xkwin入口，减少自建循环。每次唯一目录和明确run ID，固定Kernel、页面/配置；不能硬编码trace5后在摘要中写trace6。
2. success须有真实退出码0、预期完成标记、对应层级证据。deadline到达且没有终态时为TIMEOUT/INCOMPLETE，不是成功。保留具体阶段和所有尝试分母。
3. 用qemu-owner中的实际PID及会话QMP端口核对归属。先记录外层进程状态和取证，正常结束后回收；只在确实超时且已取证后清理本次拥有的进程，不凭同名进程存活判断本轮成功。
4. 离线负例验证无error+无终态、假metrics、别的QEMU存活均不能PASS；再做一次受控超时和一次正常短会话。默认不自动resume/quit失败现场。

完成点：两份真实终态记录和负例通过。不得在这一任务运行20次或同时改内核/浏览器参数。
