# x-kernel Chromium Runtime

> 在 **x-kernel**（AArch64 / QEMU 纯 TCG）上运行 **X11 + JWM + Chromium**：多窗口、三类测试页渲染、Alt+Tab 切换、连续 600 秒稳定。

[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Platform: Windows + QEMU](https://img.shields.io/badge/platform-Windows%20%2B%20QEMU-lightgrey.svg)](docs/verification.md)
[![Upstream: openkylin/x-kernel](https://img.shields.io/badge/upstream-openkylin%2Fx--kernel-2f6f9f.svg)](https://gitee.com/openkylin/x-kernel)

## 这是什么

本项目把 **openkylin/x-kernel** 移植到能跑现代 Chromium 的程度，并在 QEMU 的 AArch64 虚拟机上完成一次端到端的图形验收：

- 启动 Xorg（1280×800）与 JWM；
- Chromium 创建**多个网页窗口**，分别渲染指定 HTML、JavaScript 交互页、CSS 布局页；
- 用 **Alt+Tab** 在窗口间切换；
- 图形会话连续 **600 秒**无退出；
- 把内核缺口、修复、性能读数和原始日志都留在仓库里，可逐项复算。

本仓库现在是一个 **monorepo**：`kernel/` 是完整 x-kernel 源码（决赛基线，基于 `d3a6ec9` + 初赛解法），根目录提供**构建脚本、宿主/客机工具、测试页、文档与证据**。内核二进制通过 GitHub Releases 分发，不进 Git。

> 仓库不包含录屏视频，也不保存截图。验收时由 harness 通过 QEMU monitor `screendump` 取帧；仓库只保留串口日志、像素统计 JSON 与性能报告，避免把演示素材当成测量证据。

## 已验证的能力

| 验收项 | 实测读数 | 证据 |
|---|---|---|
| 图形会话 | Xorg 1280×800 + JWM + `_NET_SUPPORTING_WM_CHECK` | [`STAB10P`](evidence/sessions/STAB10P-20261019T062937Z/) |
| 连续 ≥ 10 分钟 | 600 s × 10 次采样全绿 | [`STAB10P`](evidence/sessions/STAB10P-20261019T062937Z/)、[`R38-STAB10B`](evidence/sessions/R38-STAB10B-20261016T105334Z/) |
| Chromium 创建窗口 | `_NET_CLIENT_LIST` 两个 id | [`R37-MW4`](evidence/sessions/R37-MW4-20261016T101127Z/) |
| 静态页渲染 | `colors=835 / 847 / 892` | [`RENDER`](evidence/sessions/RENDER-20261015T141742Z/)、[`SELF-TEST`](evidence/sessions/SELF-TEST-2026-10-16/) |
| JS 交互页 | `colors=886`，1280×800 | [`INTER7`](evidence/sessions/INTER7-20261019T064147Z/) |
| CSS 布局页 | `colors=691`，`blank=False` | [`LAYOUT`](evidence/sessions/LAYOUT-20261019T021243Z/) |
| 多窗口 + Alt+Tab | `_NET_ACTIVE_WINDOW` 与 STACKING 双向翻转 | [`R37-MW4`](evidence/sessions/R37-MW4-20261016T101127Z/) |
| renderer 多进程 | zygote 之下的子进程（`PPid` + `Threads`） | [`R37-PROC4`](evidence/sessions/R37-PROC4-20261016T104040Z/) |
| 性能 6 类指标 | 8 次独立运行，中位数 + 极差 + CV | [`perf-report.json`](evidence/reports/perf-report.json) |
| 上游回馈 | 3 个补丁合入 `openkylin/x-kernel:main` | [`docs/upstream.md`](docs/upstream.md) |

> 截图文件不随仓库发布；表中“证据”链接指向会话的 console、统计 JSON 与报告。

## 仓库结构

```text
.
├── artifacts/          本地构建输出与 Release 校验和（*.bin 不提交）
├── build/              构建内核的 WSL 脚本
├── docs/               架构、构建、验收、性能、决赛、边界、上游、历史
├── evidence/           原始会话、console、统计 JSON、汇总报告
├── guest/              客机侧 shell 脚本（串口上传）
├── host/               宿主取证 harness 与 Python 工具
├── kernel/             完整 x-kernel 源码（决赛基线）
├── pages/              三类测试页（组委会提供）
├── patches/            初始补丁、历史分组、上游 PR 补丁、回归用例
├── rootfs/             rootfs 改动的 debugfs 清单与暂存文件
└── tests/              决赛场景的一键测试入口（待补脚本）
```

完整目录与文档索引见 [`docs/README.md`](docs/README.md)。

## 快速开始

### 前置条件

| 项 | 要求 |
|---|---|
| 宿主机 | Windows 10/11（harness 使用 PowerShell 5.1 + 原生 QEMU） |
| QEMU | `qemu-system-aarch64` ≥ 8.0；本项目验证于 11.0.92，纯 TCG（无 KVM/HVF） |
| Python | 3.9+（像素统计、性能汇总） |
| 客机镜像 | `agentos-disk.img` 由赛题方提供，**不在本仓库内** |
| 内核 | 从 GitHub Releases 下载 `kernel-procfs.bin` 到 `artifacts/`，或按文档构建（默认也输出到 `artifacts/`） |

### 五分钟验收

在仓库根目录执行（把 `<image-dir>` 换成镜像所在目录）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File host\xkwin.ps1 `
  -Tag CHECK -Disk "<image-dir>\agentos-disk.img" `
  -Kernel artifacts\kernel-procfs.bin `
  -ServeManifest guest\serve-pages.txt `
  -Script "guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x4-win1.sh;guest\y6-evidence.sh;guest\x5c-win2.sh" `
  -Key "cmd=sh /tmp/xk-y6-evidence.sh;alt+tab@8;cmd=sh /tmp/xk-y6-evidence.sh;alt+tab@8;cmd=sh /tmp/xk-y6-evidence.sh" `
  -CommandTimeoutSec 300 -BootTimeoutSec 420 -AfterScriptWait 20 `
  -OutDir "runs\CHECK"
```

期望读数：

| 观察点 | 期望值 |
|---|---|
| 最终 screendump | `1280x800 colors≈892 dominant≈0.32 blank=False` |
| 窗口列表 | `_NET_CLIENT_LIST` 两个 id |
| 窗口身份 | 两窗口 `_NET_WM_PID` 相同，`WM_CLASS` 都是 `chromium (/tmp/pr)` |
| 切换 | 两次 Alt+Tab 后 `_NET_ACTIVE_WINDOW` 与 `_NET_CLIENT_LIST_STACKING` 双向翻转 |
| 页面 | `06-fetch-pages.sh` 打印 `P1 ok=3 bad=0` |

> `-ServeManifest` 不能漏。漏掉会得到 Chromium 的 `ERR_FILE_NOT_FOUND`（颜色数只有约 427），
> 看起来像"渲染失败"，实际是三张页面没进客机。

手动操作（Alt+Tab、Ctrl+N、Ctrl+L）见 [`docs/verification.md`](docs/verification.md)。

## 从源码构建

构建机需要 **WSL2 Ubuntu**。内核源码就在 [`kernel/`](kernel/)：

```bash
bash build/build-kernel.sh
# 产物：artifacts/kernel-procfs.bin（*.bin 不提交到 Git）
```

也可以手动构建：

```bash
cd kernel
cp platforms/kplat-aarch64/qemu_defconfig .config
make defconfig
make build
# target/xkmake/kplat-aarch64/release/kernel.bin
```

要在干净的上游基线上复核初赛补丁，仍可用：

```bash
git clone https://gitee.com/openkylin/x-kernel.git
cd x-kernel && git checkout d3a6ec9
bash /path/to/repo/build/apply-and-build.sh "$PWD"
```

细节、校验和常见问题见 [`docs/building.md`](docs/building.md)；内核二进制从 Releases 获取或本地构建，见 [`artifacts/README.md`](artifacts/README.md)。

## 团队协作

- `main` 保持可构建；功能分支用 `feat/...`、`perf/...`，合并前至少跑一次构建 + 最小验收。
- 内核改动直接改 `kernel/`；要回馈上游时，再按 [`docs/upstream.md`](docs/upstream.md) 拆成独立 patch。
- before/after 用 git tag 固定基线；每轮原始数据放 `evidence/reports/`。
- 决赛场景（30 分钟、负载循环、双标签、输入、JS/CSS、观测工具）见 [`docs/finals.md`](docs/finals.md)。
- 首次上传、建仓库与发 Release 的命令见 [`docs/publish.md`](docs/publish.md)。

## 上游贡献

当前有 3 个 DRM 补丁合入 `openkylin/x-kernel:main`：

| PR | 内容 | 状态 |
|---|---|---|
| Gitee `!1039` | legacy ADDFB / MODE_CURSOR / SET_CLIENT_CAP | ✅ 已合入 |
| Gitee `!1050` | MODE_SETPROPERTY / MODE_OBJ_SETPROPERTY | ✅ 已合入 |
| Gitee `!1059` | GEM_CLOSE / MODE_CLOSEFB | ✅ 已合入 |

拆分支、重新生成可合并补丁的流程见 [`docs/upstream.md`](docs/upstream.md) 与 [`patches/README.md`](patches/README.md)。

## 已知边界

- `/proc` 仅有 `State / PPid / Threads / VmSize` 与 `stat.vsize`；`VmRSS / statm / /proc/stat` 未实现（刻意缺字段，不填 0）。
- `landlock_create_ruleset`、`ptrace`、`AF_INET6` 尚未实现。
- 镜像自带的 `/sbin/init` 不能作为 PID 1 运行，图形会话需由脚本/手工拉起。
- 所有性能数字都在**纯 TCG**下测得，只适合横向自比，不宜与其他硬件比绝对值。

完整 8 条缺口与复现方法见 [`docs/limitations.md`](docs/limitations.md)。

## 文档

| 文档 | 内容 |
|---|---|
| [`docs/README.md`](docs/README.md) | 文档索引与阅读顺序 |
| [`docs/architecture.md`](docs/architecture.md) | 系统结构、启动链路、内核改动分区 |
| [`docs/building.md`](docs/building.md) | 从基线重建内核 |
| [`docs/verification.md`](docs/verification.md) | 验收命令、期望读数、取证工具 |
| [`docs/performance.md`](docs/performance.md) | 6 类指标、首帧判定、原始数据、before/after |
| [`docs/limitations.md`](docs/limitations.md) | 系统调用缺口与口径说明 |
| [`docs/upstream.md`](docs/upstream.md) | 上游 PR 状态与补丁拆分 |
| [`docs/history.md`](docs/history.md) | 研发历程（压缩版） |
| [`docs/engineering-notes.md`](docs/engineering-notes.md) | 三条硬性作业规则与诊断方法 |
| [`docs/finals.md`](docs/finals.md) | 决赛评分映射、30 分钟/负载循环/观测/测试矩阵 |
| [`docs/publish.md`](docs/publish.md) | 上传 GitHub、创建仓库与 Release 的命令 |
| [`docs/competition.md`](docs/competition.md) | 赛题背景与原始提交物说明 |

## 贡献

欢迎 issue 与 PR。开始之前请读 [`CONTRIBUTING.md`](CONTRIBUTING.md)。修改内核代码时请保持"一个补丁一件事"，
并附上可复现的命令与证据；不接受只在描述里声称"已修复"的提交。

## 许可与致谢

本项目以 **Apache-2.0** 发布，与上游 x-kernel 的许可证一致。内核源码的版权归 openKylin 及上游贡献者所有，
详见 [`NOTICE`](NOTICE) 与 [`LICENSE`](LICENSE)。
