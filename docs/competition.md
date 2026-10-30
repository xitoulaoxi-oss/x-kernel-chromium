# 赛题背景与原始提交物

## 赛题

| 项 | 内容 |
|---|---|
| 赛事 | 中国电子杯 · 第三届高校 ICT 产教融合创新大赛 |
| 赛题 | 赛题六「基于 x-kernel 的 Chromium 运行环境构建与优化」 |
| 命题 | 麒麟软件有限公司 |
| 组别 | 中阶任务 |
| 基线 | `openkylin/x-kernel`，提交 `d3a6ec9` |
| 平台 | AArch64 / QEMU，纯 TCG（初赛禁止 KVM/HVF） |

## 任务要求（与本仓库对应的部分）

1. 让 x-kernel 启动图形会话；
2. 让 Chromium 创建窗口并渲染组委会指定的三类页面：
   - 指定 HTML（`pages/index.html`）
   - JavaScript 交互（`pages/interaction.html`）
   - CSS 布局（`pages/layout.html`）
3. 支持多窗口与窗口切换；
4. 连续稳定运行不少于 10 分钟；
5. 给出系统调用 / 内核接口缺口清单与复现方法；
6. 做性能观测与量化（≥ 5 次、中位数、波动范围）；
7. 把可回馈上游的补丁拆成可合并的 PR；
8. rootfs 改动提供 debugfs 清单。

## 本仓库的完成情况

| 要求 | 状态 | 证据 |
|---|---|---|
| 图形会话 | ✅ Xorg 1280×800 + JWM | [`STAB10P`](../evidence/README.md) |
| 三页渲染 | ✅ `835/847/892`、`886`、`691` | [`RENDER`](../evidence/README.md)、[`INTER7`](../evidence/README.md)、[`LAYOUT`](../evidence/README.md) |
| 多窗口 + 切换 | ✅ 两个窗口，Alt+Tab 双向翻转 | [`R37-MW4`](../evidence/README.md) |
| 10 分钟稳定 | ✅ 600 s × 10 次采样 | [`STAB10P`](../evidence/README.md) |
| 缺口清单 | ✅ 8 条，含复现与 Linux 对照 | [limitations.md](limitations.md) |
| 性能 6 类指标 | ✅ 8 次运行 | [performance.md](performance.md) |
| 上游 PR | ✅ 3 个合入 `main` | [upstream.md](upstream.md) |
| rootfs 清单 | ✅ 3 新增 + 1 改写 | [`rootfs/`](../rootfs/) |

## 原始提交包与仓库的差异

本仓库是从提交包 `D6-001` 重构出来的公开发布版。**功能内容一致**，但为了适合 GitHub 协作，
做了以下取舍：

| 项 | 原提交包 | 本仓库 |
|---|---|---|
| 演示视频（301.5 MB，10 分 11 秒） | 有 | **不收录**（超过 GitHub 单文件限制；验收不依赖录屏） |
| 官方 Word 报告 | 有 | 不收录（正文已合入 README / docs） |
| `提交说明.md` | 有 | 合入本页与根 README |
| `manifest.json`（1,774 条逐文件 SHA-256） | 有 | 改为 `artifacts/SHA256SUMS.txt`（随 Release 校验） |
| 逐轮合并日志（`MERGED_REPORT.md` 等） | 有 | 压缩为 [history.md](history.md) |
| 预编译内核 | `kernel/` | `artifacts/`（`*.bin` 不提交，走 Releases） |
| 改动源码 | `kernel-src-changed/` | `kernel/`（完整源码树） |

原始包仍在提交目录中保留，作为赛题归档；**本仓库不修改它**。

## 验收口径

- 功能证据以 **QEMU monitor `screendump`** 与串口日志为准；
- 录屏只作演示辅助，不作为验收依据——本仓库因此不收录视频；
- 性能数字全部在纯 TCG 下测得，只做同环境自比；
- 所有结论都能在 `evidence/` 找到原始文件，或按文档命令复算。
