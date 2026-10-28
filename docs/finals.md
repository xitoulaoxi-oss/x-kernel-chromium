# 决赛准备（高级任务）

> 目标不是“能跑”，而是**在统一平台上稳定拿分**：30 分钟稳定、负载循环、双标签/窗口、键鼠输入、JS/CSS 正确性、性能名次、崩溃/卡死/泄漏定位、可复用的一键测试，以及上游回馈。

本页把赛题评分项映射到仓库里已有的能力和还缺的东西。**缺的项不要从仓库里删掉，反而要补。**

## 评分项 → 需要什么

| 决赛评分项 | 分值 | 需要的仓库能力 | 当前状态 |
|---|---:|---|---|
| 图形环境与浏览器稳定运行 | 20 | 30 分钟稳定性、每 2 分钟加载测试页 ×10、无 OOM | 已有 10 分钟稳定性；**缺 30 分钟与负载循环** |
| 浏览器功能完整度 | 20 | 指定页、renderer 多进程、≥2 标签/窗口、键鼠输入、JS、CSS | 已有双窗口/输入/三页渲染；**缺标签页与自动判据** |
| 性能与资源消耗 | 20 | 首帧、页面加载、renderer、峰值内存；5 次中位数；资格线 1.5G | 已有 6 类指标与 8 次数据；**需决赛同口径重跑与基线 tag** |
| 跨层优化与工程创新 | 20 | before/after、跨层优化、3 个上游 patch | 已有 before/after 负结果与 3 个已合并 DRM patch；**需继续找改善点** |
| 观测工具与测试套件 | 10 | 崩溃、卡死、内存泄漏定位；一键运行；使用文档 | **缺三类观测工具与一键入口** |
| 答辩与现场演示 | 10 | 现场可复现、数据可信 | 文档/证据体系已有；需按决赛场景重排 |

## 决赛测试矩阵

在 tests/ 下建立一键入口（当前只有 tests/README.md，脚本待补）：

| 场景 | 建议脚本 | 通过判据 | 证据 |
|---|---|---|---|
| 30 分钟稳定 | tests/stability30.ps1 / guest/s10-stability30.sh | 每分钟采样 Xorg/JWM/Chromium 存活；无 OOM/panic | console、帧统计 JSON |
| 负载循环 | tests/load-loop.ps1 / guest/l1-load-loop.sh | 每 2 分钟加载一次，共 10 次；无卡死、窗口仍在 | console、时间戳 |
| 双标签/窗口 | tests/tabs.ps1 / guest/t2-tabs.sh | _NET_CLIENT_LIST ≥2；Alt+Tab/Ctrl+Tab 后 active 翻转 | console、窗口属性 |
| 键盘回显 | tests/input.ps1 | 页面输入框内容变化；组合键生效 | console、DOM 读数 |
| 鼠标点击跳转 | tests/input.ps1 | 点击后 URL/标题变化 | console、URL |
| JS 交互 | tests/js.ps1 | 交互页 T1–T6 全通过 | 页面输出 |
| CSS 布局 | tests/css.ps1 | 布局页 C1–C6 符合预期 | 页面输出 |
| 性能 5 次 | host/perf_run.py | 每类 n≥5；报告中位数/极差/CV | evidence/reports/ |
| before/after | host/perf_compare.py | 基线 tag + 同口径；如实记录负结果 | 两份报告 |
| 崩溃/卡死/泄漏 | tests/observe.ps1 | 能定位到会话/进程/时间点 | console、qemu-metrics |

> 当前 guest/s9-stability10.sh 只覆盖 10 分钟；决赛 30 分钟建议新增 s10-stability30.sh，不要改 10 分钟脚本的语义。

## 内核与版本

- kernel/ 是完整 x-kernel 源码树；所有内核改动直接在这里做。
- 决赛基线用 git tag 固定：建议 finals-baseline（当前）、finals-v1（第一次优化后）等。
- 每个 tag 配套：
  - 构建产物 artifacts/kernel-*.bin（不提交，上传 Release）；
  - evidence/reports/perf-report-<tag>.json；
  - docs/performance.md 的读数更新。
- 不要把“初赛 600 秒”当“决赛 30 分钟”；时间、负载、内存资格线都要重测。

## 观测工具（10 分）

至少三类，且能一键跑：

1. **崩溃**：监控 guest console 的 panic/SIGSEGV、QEMU 退出码、窗口消失；保留会话目录。
2. **卡死**：心跳（每分钟写时间戳/窗口数）+ 超时判据；不要只靠“看起来没动”。
3. **内存泄漏**：30 分钟/负载循环期间采样宿主 QEMU 工作集与 guest free -m，给出趋势；本内核没有 VmRSS，不要伪造进程 RSS。

输出统一为 JSON + 一行结论，便于答辩展示。

## 团队协作

- main：可构建、可验收；
- feat/<topic>：功能；perf/<topic>：性能；fix/<topic>：缺陷；
- 每个 PR：构建通过 + 一个决赛场景 + 证据目录；
- 内核与工具同仓库（monorepo），PR 可以同时改 kernel/、host/、guest/、tests/；
- 上游 patch 仍按 upstream.md 从 kernel/ 的 diff 生成，不要直接推 monorepo。

## 提交前检查

- [ ] 30 分钟稳定 + 10 次负载循环通过
- [ ] ≥2 标签/窗口可切换；键鼠输入有回显
- [ ] JS/CSS 测试页通过
- [ ] 性能 5 次 × 每类指标，有中位数/极差/CV
- [ ] before/after 有 tag 与原始报告
- [ ] 崩溃/卡死/泄漏三类工具可一键运行
- [ ] 内核二进制已发 Release，仓库不含 *.bin/*.png/*.mp4
- [ ] docs/performance.md、docs/limitations.md 与最新数据一致
