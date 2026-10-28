# Contributing

感谢你愿意改进这个项目。这里的目标不是"把代码改得更像 Linux"，而是**让每个结论都能被独立复算**：
一个补丁、一条读数、一段证据，必须能对应起来。

## 先读什么

1. [`docs/architecture.md`](docs/architecture.md) —— 系统由哪几层组成，改动落在哪一层；
2. [`docs/limitations.md`](docs/limitations.md) —— 已知缺口，避免把"没实现"当成"回归"；
3. [`docs/engineering-notes.md`](docs/engineering-notes.md) —— 三条硬性作业规则，违反会浪费整轮实验；
4. [`docs/upstream.md`](docs/upstream.md) —— 补丁如何拆成可被上游合并的 PR。

## 仓库约定

| 路径 | 放什么 | 不放什么 |
|---|---|---|
| `kernel/` | 完整 x-kernel 源码（决赛基线） | 构建产物 `target/` |
| `patches/` | 初始补丁、历史分组补丁、上游 PR 补丁、回归用例 | 临时 diff、编辑器备份 |
| `artifacts/` | 本地构建输出与 Release 校验和 | 提交到 Git 的 `*.bin` |
| `host/` | 宿主侧 PowerShell / Python 工具 | 客机内运行的脚本 |
| `guest/` | 通过串口送进客机的 shell 脚本 | 宿主工具 |
| `evidence/` | 原始会话、console、统计 JSON、性能报告 | 截图、视频、经过挑选或修饰的"好看数据" |
| `docs/` | 解释性文档 | 与数据冲突的结论 |
| `tests/` | 决赛场景的一键测试 | 只打印“看起来正常”的假测试 |

`artifacts/*.bin` **不提交**，只用于本地验收或 GitHub Release。需要更新时，先改 `kernel/`，再按
[`docs/building.md`](docs/building.md) 重建，并同步 `artifacts/SHA256SUMS.txt`。

## 开发环境

- **宿主工具**：Windows 10/11 + PowerShell 5.1 + Python 3.9+；`qemu-system-aarch64` ≥ 8.0。
- **内核构建**：WSL2 Ubuntu；Windows 侧无法完整构建（vendored crate 不全）。
- **客机镜像**：赛题方的 `agentos-disk.img`，只读使用，所有会话都用 `-snapshot` 启动。
- **QEMU**：默认 `-M virt -cpu cortex-a72 -smp 4 -m 4G -accel tcg`；禁止 KVM/HVF。

## 改内核代码

1. 直接改 `kernel/`；从当前 `main` 拉分支，不要在工作树上叠加别人的未提交改动。
2. 一个逻辑改动一个提交。**不要把 42 个文件塞进一个 PR**——上游无法评审。
3. 构建并验证：

   ```bash
   bash build/build-kernel.sh
   bash -n build/*.sh
   ```

4. 如果改动要提上游，按 [`docs/upstream.md`](docs/upstream.md) 从 `kernel/` 生成独立 diff，
   确保它能打在**当前 main**上，而不是只打在 `d3a6ec9` 上。
5. 回归用例优先使用真实 fd / 真实 ioctl，不做 mock。参考
   [`patches/regression/io/drmdevice/tests/mode.rs`](patches/regression/io/drmdevice/tests/mode.rs)。
6. 初赛的 `patches/x-kernel-solution.patch` 保留作审计；日常开发不再以它为主。

## 改宿主工具

- 保持 **PowerShell 5.1 兼容**（不要用 `??`、`?` 等新语法）。
- 路径优先用 `$PSScriptRoot` / `pathlib.Path(__file__).parent` 推导，不要写死本机路径。
- 所有相对路径以**仓库根**为基准；`host/xkwin.ps1` 的 workspace 是它的父目录。
- 新增参数时同步更新 `docs/verification.md` 与 `host/README.md`。
- 不得把中文写进 PowerShell 命令参数（见 `docs/engineering-notes.md` 规则 1）。

## 改客机脚本

- 单个脚本必须 **< 1792 字节**；超限请拆成多个脚本，不要放宽上限。
- 脚本名会变成 `/tmp/xk-<filename>`；需要跨脚本调用时按这个路径写。
- 串口一次可靠传输约 4 KB；大文件走 `-ServeManifest` 的 HTTP 通道。
- 脚本要自足：不依赖 `/root` 下的历史文件，不依赖交互式 shell 环境变量。

## 证据与性能

- 新会话目录命名：`<TAG>-<UTC yyyymmddTHHmmssZ>`，例如 `R37-MW4-20261016T101127Z`。
- 每次会话至少保留：`console.log`、`qemu-cmd.txt`、`.stats.json`、`qemu-metrics.json`；截图不提交。
- 不提交 `*.png` / `*.jpg` / `*.gif` / `*.mp4`；CI 会拒绝这些文件。
- **不要删除失败的轮次**。页面没画出来就记 `not found`，不要重跑到好看为止；样本量变化要写出来。
- 性能数据必须用 `host/perf_run.py` 生成，报告写入 `evidence/reports/`。
- 首帧判定用 `host/frame_stats.py` 的饱和度判据，不要用"色数 ≥ 100"单一判据。
- 新增或修改指标时，同步更新 [`docs/performance.md`](docs/performance.md) 的定义表。

## 团队协作

- `main`：始终可构建、可验收；
- `dev`：决赛集成分支（可选）；
- `feat/<topic>`、`perf/<topic>`、`fix/<topic>`：功能、性能、缺陷；
- 每个 PR 至少包含：构建结果、一个决赛场景、证据目录；
- 内核和工具在同一个 monorepo 里，PR 可以同时改 `kernel/`、`host/`、`guest/`、`tests/`。

## 文档

- 中文为主，代码/路径/参数保持原文。
- 文件用 UTF-8（无 BOM）、LF 换行；不要经 PowerShell 文本管道改写（见规则 2）。
- 不确定的结论写"未验证/待查"，不要写成已实现。
- 历史结论如果被推翻，删除或明确标注"已被 X 取代"，不要让两份文档同时成立。
- 仓库**不收录视频与截图**。验收时用 screendump，仓库只提交 console、统计 JSON 与报告。

## 提交与 PR

提交信息用祈使句，说明"改了什么"，正文写"为什么"和"怎么验证"：

```text
net/knet: accept TCP_KEEPIDLE, TCP_KEEPINTVL and TCP_KEEPCNT

A network service that sets the three knobs retried on every rejection and
flooded the serial console.  KEEPIDLE is wired to the smoltcp timer; the other
two are recorded and read back, because smoltcp has no second knob.

Verified: R37-MW4 sockopt rejected=0 (was 36); see evidence/sessions/...
```

PR 描述请填完整模板，并勾选所有适用的检查项。CI 会做 Python/Shell 语法、补丁可解析性、
内核产物校验和、JSON 有效性检查，以及"仓库中不得有视频文件"的检查。

## 首次发布到 GitHub

本目录按普通文件夹交付，**没有**包含 `.git`。首次发布：

```bash
cd "for github"
git init -b main
git add .
git commit -m "Initial public release"
git remote add origin git@github.com:<you>/x-kernel-chromium.git
git push -u origin main
```

推送前确认：

- `git status` 里没有 `runs/`、`*.img`、`*.mp4`（这些已在 `.gitignore` 中排除）；
- 仓库约 23 MB（完整内核源码 + 工具/文档），**不需要 Git LFS**；
- 内核二进制、演示视频、截图都作为 Release 资产或本地输出，不要提交进仓库。
