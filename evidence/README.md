# Validation evidence

本目录保留可复核的成功与失败记录，完整本地实验、备份、截图和下载缓存不进入 Git。

| 检查 | 结果 | 证据 |
|---|---|---|
| 30 分钟 + 10 次加载 | PASS：1800.43s、10 次新导航、30 次心跳、最大偏差 0.10s | [汇总](2026-10-30/stability/stability-load.json)、[原始串口](2026-10-30/stability/console.log) |
| JS / CSS 自动检查 | 各 6/6 | [JS](2026-10-30/functional/js.json)、[CSS](2026-10-30/functional/css.json) |
| Linux CSS 对照 | 同版本、同视口几何和样式匹配 | [比较](2026-10-30/css/comparison.json) |
| 键鼠与 renderer | 早先会话通过；后续输入停顿 | [输入](2026-10-30/functional/input.json)、[进程身份](2026-10-30/functional/process-identity.json) |
| 完整功能 / 首次启动 | 未通过：about:blank 与 400s 超时 | [空白页](2026-10-30/failures/windows/page-check.json)、[超时](2026-10-30/failures/input/harness-error.txt) |
| Chromium 内存预算 | 采用客机整体已用内存最高840MB作为预算依据；不是精确RSS | [测量记录](2026-10-30/memory-budget.json) |

长测的外层命令会话退出码因对话中断未恢复；客机完成标记、最终截图统计和完整时序已保存，严格汇总重新运行返回 PASS。Linux 对照为 x86_64 headless，不能替代正式 AArch64 QEMU 性能评测。

`functional/combined-attempts.json` 是跨失败与补测的证据汇总，2/5 不表示一轮完整通过。截图由 QEMU screendump 产生并保留在本地；当前 Git 策略仍不提交图片或视频。

## Historical records

旧会话与重复逐帧 JSON 已从当前目录移除。旧版已跟踪证据仍可在 [精简前提交](https://github.com/xitoulaoxi-oss/x-kernel-chromium/tree/9612b12aa5935dafa0c6898ffe8735859e1034e9/evidence) 查阅；所有本地完整记录另行归档。未改写 Git 历史。

[manifest.json](manifest.json) 保存每个公开文件对应的原始路径及处理前后 SHA-256。公开副本仅规范编码、移除终端控制码和主机路径，不改测量值。

## Subsequent task execution

[Startup diagnostics and CRLF fix](../docs/startup-diagnosis.md): corrected local shell-script line endings, added pre-upload rejection, reran an actual startup successfully, and passed a fresh input/renderer subset 2/2. Previous failures remain. This does not certify a complete functional run or twenty first starts.

## 2026-10-30 finals task book (01-11)

| 任务 | 结果 | 关键证据 |
|---|---|---|
| 01 抓取首次启动失败 | PASS | [同命令成功/失败、四 vCPU 同一空闲 PC、QEMU CPU 0.215](2026-10-30/finals-tasks/task01/startup-capture/startup-capture.json) |
| 02 修复启动推进 | PARTIAL | [空闲 tick 修复与未消除的随机停顿](2026-10-30/finals-tasks/task02/result.json) |
| 03 二十次首次启动 | FAIL：11/13 | [两次尝试，失败保留](2026-10-30/finals-tasks/task03/result.json) |
| 04 一轮完整功能 | FAIL：首次 DOM 即 about:blank | [结果](2026-10-30/finals-tasks/task04/result.json) |
| 05 四项指标基线 | FAIL：2 项 n=4，renderer/客机峰值 n=0 | [原始基线](2026-10-30/finals-tasks/task05/baseline-x4b.json) |
| 06-08 三项优化 | BLOCKED | [06](2026-10-30/finals-tasks/task06/result.json)、[07](2026-10-30/finals-tasks/task07/result.json)、[08](2026-10-30/finals-tasks/task08/result.json) |
| 09 真实故障诊断 | PARTIAL：crash/stop 注入成功但诊断被超时打断；leak 未运行 | [结果](2026-10-30/finals-tasks/task09/result.json) |
| 10 三场景彩排 | BLOCKED | [结果](2026-10-30/finals-tasks/task10/result.json) |
| 11 打包与同步 | PARTIAL：证据包已生成，未推送 | 本目录 + `submission/release-2026-10-30-final/` |

`finals-tasks/manifest.json` 记录 25 个公开证据文件的 SHA-256。原始会话、截图和逐帧日志仍在被 Git 忽略的 `experiments/FINALS-RUNS/20261030T110856Z/`；公开目录只保留结论、失败证据和可复核 JSON。


## 2026-10-31 trace checkpoint

[结果、边界与哈希](2026-10-31/trace-checkpoint/README.md)。完整实验日志本地保留，公开目录只留代表证据。
