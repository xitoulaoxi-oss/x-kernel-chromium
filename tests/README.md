# tests/

决赛场景的一键测试入口。

当前已有：

- `observe.ps1`：调用 `host/observe.py` 分析一个会话；
- `stability30.ps1`：30 分钟稳定性；
- `load-loop.ps1`：每 2 分钟 Ctrl+R 重载一次，共 10 次；
- `lowmem-smoke.ps1`：E004 低内存 Chromium 变体的双窗口 smoke。
- 崩溃/卡死/泄漏工具与判据见 [../docs/observability.md](../docs/observability.md)。

以下场景仍待补：


1. 30 分钟稳定性；
2. 每 2 分钟加载一次、共 10 次的负载循环；
3. 双标签/窗口与 Alt+Tab；
4. 键盘回显、鼠标点击跳转；
5. JS 交互、CSS 布局；
6. 崩溃、卡死、内存泄漏三类观测。

每个脚本应：

- 从仓库根运行，接受镜像路径与内核路径；
- 输出一段可粘贴的摘要，并把原始数据落到 `evidence/`；
- 失败时返回非零退出码，不能只打印“看起来正常”。
