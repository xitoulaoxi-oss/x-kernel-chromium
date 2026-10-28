# patches/

补丁按**用途**分层。先看这张表，不要拿到一个补丁就往树上打。

| 目录 / 文件 | 用途 | 基线 | 能重建推荐内核吗 |
|---|---|---|---|
| `x-kernel-solution.patch` | **完整解**，42 文件 | `d3a6ec9` | ✅ 能 |
| `series/` | 0001–0008 历史分组快照 | `d3a6ec9` | ❌ 不能（缺 SCM_RIGHTS / UCT/UCI / keep-alive / procfs） |
| `upstream/port-to-main/` | 面向当前上游 `main` 的 PR 补丁 | `main` | ❌ 不能（只含可合并的子集） |
| `upstream/fixes/` | 已推送 PR 的评审修正链 | 各 PR 分支 | ❌ 不能 |
| `regression/` | 真实 fd / 真实 ioctl 的回归用例 | — | — |

## 完整解

> 日常开发直接用 [`../kernel/`](../kernel/) 的完整源码树；本补丁用于**审计**和从干净的 `d3a6ec9` 重建，不是日常构建入口。

```bash
git clone https://gitee.com/openkylin/x-kernel.git
cd x-kernel && git checkout d3a6ec9
git apply --check /path/to/patches/x-kernel-solution.patch
git apply /path/to/patches/x-kernel-solution.patch
```

或者直接：

```bash
bash /path/to/repo/build/apply-and-build.sh "$PWD"
```

覆盖范围（42 文件）：

| 子系统 | 解决的问题 |
|---|---|
| AF_UNIX + SCM_RIGHTS | Chromium Mojo 传 fd；缺失导致 renderer 永不出现 |
| ARM64 `SCTLR_EL1.UCT/UCI` | EL0 读 `CTR_EL0` 触发 SIGILL |
| DRM legacy modeset | Xorg modesetting 的 `ADDFB` / `CREATE_DUMB` 24bpp / `MODE_CURSOR` / `SET_CLIENT_CAP` / `DIRTYFB` |
| inotify | 真 fd、watch 表、事件队列、VFS 钩子、`FIONREAD` |
| tmpfs | `statfs` 容量、`/dev/shm` 与 `/tmp` 的 1777 |
| TCP / socket | keep-alive 三选项、非阻塞收发不被 `EINTR` 打断 |
| procfs | `State/PPid/Threads/VmSize` 与 `stat.vsize` |
| 诊断 | syscall 计数器、init 交接（未达成） |

## series/：历史分组补丁

```text
0001-drm-legacy-modeset-and-client-cap.patch
0002-drm-regression-manifest.patch
0003-init-hand-off-to-busybox-init.patch
0004-inotify-real-fd-and-watch-table.patch
0005-inotify-event-delivery.patch
0006-inotify-vfs-create-hook.patch
0007-inotify-notifier-injection.patch
0008-sockopt-rejection-log.patch
```

**不要按顺序全部应用，也不要用它们重建内核。** 它们是同一批工作的递进快照：
0004/0005/0006 都改 `process/kfd_objects/src/inotify.rs`，0004/0007 都改 `core/ksyscall/src/dispatch.rs`；
且缺少两处决定性修复。详见 [series/README.md](series/README.md)。

## upstream/：面向上游的补丁

- `port-to-main/`：逐文件 `diff(main → 我们)`，只保留不回退 main 的文件，所以每个都能打在 main 上；
- `fixes/`：PR 评审过程中收到的修正，**!1039 / !1050 合并后已成为历史**，不要重提。

当前 PR 状态、拆分支流程与注意事项见 [../docs/upstream.md](../docs/upstream.md)。

## regression/：DRM 回归用例

`regression/io/drmdevice/tests/mode.rs` 用真实 fd、真实 ioctl 驱动 legacy modeset、
`CREATE_DUMB`、`MODE_CURSOR`、`SET_CLIENT_CAP` 与 `DIRTYFB`，不做 mock。
见 [regression/README.md](regression/README.md)。

## 内核源码与 tag

完整源码在 [`../kernel/`](../kernel/)；根仓库用 git tag 固定决赛基线（例如 `finals-baseline`、`finals-v1`）。
初赛的 `baseline-d3a6ec9` / `first-runnable` / `final` 关系已经固化在源码树与历史文档里，不再单独维护 git bundle。

## 不在补丁里的东西

| 项 | 原因 |
|---|---|
| `Cargo.lock` | 本机离线 vendoring 的产物；按上游规范应单独成一个 commit |
| `xtask/xkmake/src/qemu.rs`、`arch/kcpu_slot/Cargo.toml`、`boot/kernel_elf_parser/tests/test_dynamic.rs` | 只存在于 Windows 侧的尝试性改动，WSL 构建树里没有也不需要 |
| `vendor/` | 本机离线 crate 缓存，非源码 |

## 检查

```bash
# 完整解能否打在干净基线上
git -C /path/to/x-kernel apply --check /path/to/repo/patches/x-kernel-solution.patch

# 所有补丁文件格式是否有效
for p in $(find patches -name '*.patch'); do git apply --numstat "$p" >/dev/null || echo "BAD $p"; done
```
