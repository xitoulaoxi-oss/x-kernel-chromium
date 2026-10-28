# 构建内核

本仓库是 **monorepo**：完整 x-kernel 源码在 [`kernel/`](../kernel/)，宿主/客机工具在根目录。
日常构建直接在 `kernel/` 里做，不需要再 clone 上游或打补丁。

## 环境

| 项 | 要求 |
|---|---|
| 构建机 | **WSL2 Ubuntu**（Windows 侧无法完整构建：vendored crate 不全，且没有 POSIX 构建环境） |
| 工具链 | 由 `kernel/rust-toolchain.toml` 固定；先装好 rustup |
| 基线 | 赛题基线 `d3a6ec9` + 初赛解法（已包含在 `kernel/`） |
| 构建入口 | 仓库自带 `make build`（xkmake） |
| 网络 | 首次构建需要拉取依赖；离线环境需要自备 `vendor/` |

> **不要用 `cargo check` 代替 `make build`**：分配器特性来自 Kconfig 生成的快照，
> 只有项目构建流程会生成它。

## 日常构建（推荐）

在仓库根目录：

```bash
bash build/build-kernel.sh
# 产物：artifacts/kernel-procfs.bin（*.bin 不提交到 Git）
```

等价的手动步骤：

```bash
cd kernel
cp platforms/kplat-aarch64/qemu_defconfig .config
make defconfig
make build

# 产物
ls -l target/xkmake/kplat-aarch64/release/kernel.bin
```

复制到发行目录：

```bash
cp target/xkmake/kplat-aarch64/release/kernel.bin ../artifacts/kernel-procfs.bin
```

## 构建脚本的可调变量

`build/build-kernel.sh`：

| 变量 | 默认 | 说明 |
|---|---|---|
| `KERNEL` | `<repo>/kernel` | 源码树 |
| `OUT` | `<repo>/artifacts` | 产物目录 |
| `NAME` | `kernel-procfs.bin` | 产物文件名 |
| `DEFCONFIG` | `platforms/kplat-aarch64/qemu_defconfig` | 配置 |
| `CLEAN=yes` | `no` | 构建前 `make clean` |

## 从干净上游复核初赛补丁

`kernel/` 已经包含改动；如果要验证 `patches/x-kernel-solution.patch` 仍能落在干净的
`d3a6ec9` 上：

```bash
git clone https://gitee.com/openkylin/x-kernel.git
cd x-kernel
git checkout d3a6ec9
bash /path/to/repo/build/apply-and-build.sh "$PWD"
```

它只用于审计/复现，不是日常开发路径。

## 产物与校验

| 文件 | 字节 | SHA-256 |
|---|---|---|
| `kernel-procfs.bin` | 8,544,026 | `5261ceb3c11249a75ebe0f3477d5af28ae604cf62e6576ace5d09079442c8459` |
| `kernel-keepalive.bin` | 8,544,026 | `7eca45acee9de2dce3cb0945b3bad18088e635a0f1841f127384abd077c2d403` |
| `kernel-baseline.bin` | 8,437,530 | `fa956a34c985b0e8f204a843baf7a15eebd60217c05e79308fa73ba523efa82f` |

`artifacts/*.bin` **不提交**；发布时作为 GitHub Release 资产上传。
`artifacts/SHA256SUMS.txt` 保留在仓库，用于校验下载/本地构建的产物。

```bash
cd artifacts && sha256sum -c SHA256SUMS.txt
```

**不要期待逐字节复现**：Rust 构建会嵌入路径与时间戳。正确的复现标准是
"能正常启动并复现读数"，而不是哈希必须相同。

## 构建后的自检

1. 用新内核跑一次最小验收（见 [verification.md](verification.md)），确认窗口与页面渲染。
2. 如果改了源码，更新 `patches/x-kernel-solution.patch`（用于审计/上游拆分）和
   `artifacts/SHA256SUMS.txt`。
3. 不要用旧内核配新证据，也不要用新内核配旧读数——每份证据的 `qemu-cmd.txt` 里都有实际内核路径。
4. 决赛基线用 git tag 固定（如 `finals-baseline`），构建产物上传 Release。

## 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| `patch does not apply` | 上游 checkout 不是干净的 `d3a6ec9`，或有未提交改动；重新 clone 或 `git stash` |
| Windows 侧 `make build` 失败 | 必须用 WSL2 Ubuntu |
| 构建成功但内核起不来 | 检查是否完整构建、是否用了旧的 `target/`；必要时 `CLEAN=yes` |
| 产物只有 1.3 MB / 明显偏小 | 复制过程被截断；核对字节数与 SHA-256 |
| 依赖拉取失败 | 配置代理，或准备离线 `vendor/` |
| `wsl.exe` 被沙箱拒绝 | 某些受限环境需要一次性提权；见 [engineering-notes.md](engineering-notes.md) |

## 相关

- [`../kernel/README.md`](../kernel/README.md) —— 上游内核说明
- [`../build/build-kernel.sh`](../build/build-kernel.sh)
- [`../build/apply-and-build.sh`](../build/apply-and-build.sh)
