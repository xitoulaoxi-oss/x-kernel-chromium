# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 的结构；
版本号从公开整理版开始，不追溯此前的内部轮次编号。

## 2.0.0 - 2026-10-28

决赛版 monorepo 结构。

### Added

- `kernel/`：完整 x-kernel 源码树（`d3a6ec9` + 初赛解法），组员 clone 一次即可构建。
- `build/build-kernel.sh`：直接构建 `kernel/` 并输出到 `artifacts/`。
- `docs/finals.md`：决赛评分映射、30 分钟稳定性、负载循环、观测工具与测试矩阵。

### Changed

- 内核二进制改为 GitHub Release 资产；`artifacts/*.bin` 不再提交。
- 补丁从“日常构建入口”改为“审计/上游拆分入口”；日常开发直接改 `kernel/`。

### Removed

- `kernel-changes/`（由完整 `kernel/` 取代）。
- `patches/solution.bundle`（由 `kernel/` + git tag 取代）。
- `build/wsl-build.sh`（overlay 同步不再需要）。

## 1.0.0 - 2026-10-19

首个面向公开协作的整理版本。功能内容与此前提交的 `D6-001` 一致，但目录与文档经过重构：

### Added

- `docs/` 下的完整文档集：架构、构建、验收、性能、边界、上游、历史、工程规则。
- 根目录 `CONTRIBUTING.md`、`CHANGELOG.md`、`LICENSE`、`NOTICE`。
- GitHub Actions 基础检查（Python/Shell 语法、补丁解析、产物校验和、JSON、禁止视频）。
- `artifacts/` 与 `kernel-changes/` 的独立说明，明确"预编译产物"与"部分源码快照"的区别。

### Changed

- `kernel-src-changed/` → `kernel-changes/`。
- `kernel/` → `artifacts/`（避免与内核源码目录混淆）。
- 补丁按用途分层：`patches/series/`（历史分组）、`patches/upstream/`（可提 PR 的补丁与修正）、
  `patches/regression/`（回归用例）。
- 原始会话归入 `evidence/sessions/`，汇总报告归入 `evidence/reports/`。
- 根 README 精简为项目总览；验收、性能、边界等细节移入 `docs/`，不再在多份文档中重复。
- 宿主工具与构建脚本的默认路径同步到新目录结构。

### Removed

- 提交专用的 `manifest.json` 与生成/校验脚本（清单与旧目录绑定，重构后不再成立；
  内核产物改用标准 `SHA256SUMS`）。
- 提交专用的 Word 报告生成脚本与 `提交说明.md`（内容已合入 `docs/competition.md` 与根 README）。
- 316 MB 演示视频、27 帧 GIF 与全部截图（817 个 PNG/GIF，约 34.6 MB）；仓库只保留 console、统计 JSON 与报告，截图不随仓库发布。
- 重复/过时的合并日志：`MERGED_REPORT.md`、`ROUND-*.md`、`SUCCESS-SUMMARY.md`、
  `plan1016.md`、旧版 `docs/README.md` 等，压缩为 `docs/history.md` 单一叙事。
- 旧口径性能说明 `PERF-BEFORE-AFTER.md` 的独立副本；结论并入 `docs/performance.md`，
  原始 JSON 仍保留在 `evidence/reports/`。

