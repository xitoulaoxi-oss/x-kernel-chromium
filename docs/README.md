# 文档索引

本目录只回答"怎么理解、怎么复现、怎么修改"，不重复 README 的项目介绍。
原始数据在 [`../evidence/`](../evidence/)，可执行代码在 [`../host/`](../host/)、[`../guest/`](../guest/)、
[`../build/`](../build/)。

## 按目标选择

| 我想…… | 读这份 |
|---|---|
| 了解系统怎么搭起来、每一层负责什么 | [architecture.md](architecture.md) |
| 从基线重新构建内核 | [building.md](building.md) |
| 跑一遍验收、理解证据怎么采集 | [verification.md](verification.md) |
| 看性能指标定义与原始读数 | [performance.md](performance.md) |
| 知道哪些没实现、为什么 | [limitations.md](limitations.md) |
| 把补丁提回上游 | [upstream.md](upstream.md) |
| 了解项目经历了哪些弯路 | [history.md](history.md) |
| 避免踩串口/编码/路径的坑 | [engineering-notes.md](engineering-notes.md) |
| 查崩溃/卡死/泄漏 | [observability.md](observability.md) |
| 准备决赛 / 高级任务 | [finals.md](finals.md) |
| 上传 GitHub / 发 Release | [publish.md](publish.md) |
| 看赛题背景与原始提交物 | [competition.md](competition.md) |

## 文档约定

- **结论以仓库内可复算的数据为准**。文档里的数字都能在 `evidence/` 找到对应会话或 JSON。
- **历史文档不冒充现状**。已被推翻的结论集中在 [history.md](history.md)，正文不再保留第二份"现状"。
- **路径相对仓库根**。文档里的命令默认在仓库根目录执行；需要 `cd` 的地方会写明。
- **不写"应该能"**。未验证的能力标为"未实现/未验证"，不写成已达成。

## 目录

```text
docs/
├── README.md            本文件
├── architecture.md      系统结构与内核改动分区
├── building.md          从基线重建内核
├── verification.md      验收流程与取证工具
├── performance.md       性能指标、统计与 before/after
├── limitations.md       系统调用缺口与口径说明
├── upstream.md          上游 PR 状态与补丁拆分
├── history.md           研发历程（压缩版）
├── engineering-notes.md 作业规则与诊断方法
├── observability.md     崩溃/卡死/泄漏观测工具
├── finals.md            决赛准备与测试矩阵
├── publish.md           上传 GitHub 与 Release
└── competition.md       赛题背景与原始提交物
```

## 其他位置的说明

| 位置 | 内容 |
|---|---|
| [`../patches/README.md`](../patches/README.md) | 初始补丁、历史分组、上游 PR 补丁 |
| [`../patches/series/README.md`](../patches/series/README.md) | 0001–0008 历史分组补丁的定位 |
| [`../patches/upstream/fixes/README.md`](../patches/upstream/fixes/README.md) | 已推送 PR 的评审修正链 |
| [`../kernel/README.md`](../kernel/README.md) | 完整内核源码（上游 README） |
| [`../artifacts/README.md`](../artifacts/README.md) | 内核构建输出与 Release 校验和 |
| [`../evidence/README.md`](../evidence/README.md) | 会话索引与证据格式 |
| [`../host/README.md`](../host/README.md) | 宿主工具清单 |
| [`../guest/README.md`](../guest/README.md) | 客机脚本清单与执行顺序 |
| [`../tests/README.md`](../tests/README.md) | 决赛场景的一键测试入口 |
