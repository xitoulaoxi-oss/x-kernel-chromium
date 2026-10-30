# Verification

运行命令见 [tests/USAGE.md](../tests/USAGE.md)，当前结果见 [evidence/README.md](../evidence/README.md)。

页面验收读取实际 URL、readyState、导航身份、完整检查行及总结果；不以色数或标题单独判断。键鼠走真实 QMP 输入，DOM 只读取结果。renderer 角色来自 Chromium API，并与客机 procfs 的 PID、线程数和父进程链核对。

长测要求不少于 1800 秒、每 120 秒加载一次共 10 次，每次出现新的完成导航；还检查心跳连续性、触发偏差及崩溃/OOM标记。截图统一由 QEMU screendump 生成；原图本地保留。

当前仍有首启 about:blank 和输入停顿。单项成功或恢复成功不能作为严格 20 次首次启动全通过的证据。
