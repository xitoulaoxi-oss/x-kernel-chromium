# patches/series/ — 历史分组补丁

这 8 个补丁是**按主题分组的历史快照**，用于审阅"每一步想做什么"，不是可叠加的补丁序列。

| 补丁 | 主题 | 说明 |
|---|---|---|
| `0001-drm-legacy-modeset-and-client-cap.patch` | DRM legacy modeset | legacy `ADDFB`、`CREATE_DUMB` 24bpp、`MODE_CURSOR`、`SET_CLIENT_CAP` |
| `0002-drm-regression-manifest.patch` | DRM 回归 | 把 `io/drmdevice/tests` 拆成两个 target，便于客机交叉编译 |
| `0003-init-hand-off-to-busybox-init.patch` | init 交接 | ⚠️ 已应用但**目的未达成**：busybox init 要求自己是 PID 1 |
| `0004-inotify-real-fd-and-watch-table.patch` | inotify fd + watch 表 | 事件源尚未接上 |
| `0005-inotify-event-delivery.patch` | inotify 事件队列 | 8 字节对齐、`EINVAL` 语义 |
| `0006-inotify-vfs-create-hook.patch` | VFS `IN_CREATE` 钩子 | — |
| `0007-inotify-notifier-injection.patch` | 钩子注入 + `IN_DELETE` | — |
| `0008-sockopt-rejection-log.patch` | `ENOPROTOOPT` 日志 | 诊断用；正是它暴露了 TCP_KEEPIDLE 缺口 |

## 为什么不能用来重建

- **缺两处决定性修复**：AF_UNIX 流上的 `SCM_RIGHTS`、`SCTLR_EL1.UCT/UCI`；
- 也缺 TCP keep-alive 与 procfs 字段；
- 彼此不独立：`0004`/`0005`/`0006` 都改 `process/kfd_objects/src/inotify.rs`，
  `0004`/`0007` 都改 `core/ksyscall/src/dispatch.rs`，是递进修改，不能顺序全打。

**重建只用 [`../x-kernel-solution.patch`](../x-kernel-solution.patch)。**

## 仍然有用的地方

- 按主题对照"这个子系统改了哪些点"；
- 复现早期会话时，确认当时的内核包含哪一部分；
- 写上游 PR 时作为拆分参考（但真正要提的是 `../upstream/port-to-main/`）。
