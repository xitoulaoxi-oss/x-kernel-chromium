# build/

在 WSL2 Ubuntu 中构建仓库内的完整内核树（`kernel/`），并把产物复制到 `artifacts/`。

| 脚本 | 用途 | 用法 |
|---|---|---|
| `build-kernel.sh` | 直接构建 `kernel/`，产物默认 `artifacts/kernel-procfs.bin` | `bash build/build-kernel.sh` |
| `apply-and-build.sh` | 用 `patches/x-kernel-solution.patch` 从干净的 `d3a6ec9` 上游树重建 | `bash build/apply-and-build.sh /path/to/x-kernel` |

## 日常构建（推荐）

```bash
bash build/build-kernel.sh
# 或
NAME=kernel-keepalive.bin CLEAN=yes bash build/build-kernel.sh
```

产物：`artifacts/kernel-procfs.bin`。该目录下的 `*.bin` **不提交到 Git**，用于本地验收或上传到 GitHub Releases。

## 从干净上游重建

用于核对初始补丁是否仍能落在赛题基线 `d3a6ec9` 上：

```bash
git clone https://gitee.com/openkylin/x-kernel.git
cd x-kernel && git checkout d3a6ec9
bash /path/to/repo/build/apply-and-build.sh "$PWD"
```

详细环境、校验和常见问题见 [`../docs/building.md`](../docs/building.md)。

> 不要用 `cargo check` 代替 `make build`：分配器特性来自 Kconfig 生成的快照。
