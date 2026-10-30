# 边界与已知缺口

这份清单只收**可复现、指向具体位置、能给出 Linux 对照**的缺口。
"看起来像 bug 的症状"、"自己造成的现象"、"已撤回的猜测"不在此列。

## 系统调用 / 内核接口缺口

| # | 缺口 | 位置 / 证据 | 复现 | Linux 对照 | 状态 |
|---|---|---|---|---|---|
| 1 | `inotify_init1` 被路由到 `sys_dummy_fd`，恒 `ENOSYS` | `core/ksyscall/src/dispatch.rs`、`posix/fs/src/io.rs` | 客机 `inotifyd` 启动报 `inotify_init() failed: Function not implemented (38)` | 返回全新 fd，`IN_NONBLOCK`/`IN_CLOEXEC` 生效 | ✅ 已修（补丁 0004–0007） |
| 2 | inotify 无事件源：有 fd 与 watch 表，但加了 watch 也收不到事件 | `process/kfd_objects/src/inotify.rs` | 加 watch 后 `inotifyd` 挂起，`/tmp/id.log` 为 0 字节 | `read` 阻塞到有事件，按 `struct inotify_event` 返回 | ✅ 已修（0005–0007） |
| 3 | `FIONREAD`（`0x541b`）在匿名 inode 文件上未实现 | `fs/kvfs/src/file.rs` 有 `ioctl`；`InotifyFops` 未覆写 | `inotifyd: ioctl 0x541b failed: Not a tty` | 返回队列中待读字节数 | ✅ 已修（`InotifyFops::ioctl`） |
| 4 | DRM legacy modeset（`ADDFB`/`MODE_CURSOR`）与 `SET_CLIENT_CAP` 缺失 | `io/drmdevice/src/card0.rs` 落到 `EOPNOTSUPP` | 修前 Xorg modesetting 起不来；修后 `current 1280 x 800` | 完整 KMS ioctl 面，legacy 接口仍可用 | ✅ 已修，且 **Gitee !1039 已合入** |
| 5 | `landlock_create_ruleset` 未实现 | 仅定义 syscall 号 `api/linux_sysno/src/arch/aarch64.rs` | 每次 Chromium 启动必现 `Unimplemented syscall: landlock_create_ruleset` | `attr=NULL,size=0,flags=VERSION` 时返回 ABI 版本号（探测用，零成本） | ❌ 待实现 |
| 6 | `prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, …)` → `ENOSYS` | `core/ksyscall/src/task/ctl.rs`；`docs/security.md` 把它写成"有意契约" | 安装 BPF 过滤器返回 `ENOSYS` | 返回 0、过滤器生效；与 `PR_SET_NO_NEW_PRIVS`（本内核**已实现**）配套 | ⚠️ 契约是否成立需重新论证 |
| 7 | `ptrace` 未实现 | 无实现 | gdb / crashpad 无法附加；客机日志 `ptrace` `ENOSYS` | `PTRACE_ATTACH`/`SEIZE` 可用 | ❌ 待实现 |
| 8 | `AF_INET6` 不支持 | 无 `/proc/net/if_inet6`；交付内核 `posix/net/src/socket.rs` 无 `AF_INET6` 分支 | `ping -6 ::1` → `Address family not supported by protocol`；`ping 127.0.0.1` 正常 | 正常 | ❌ 仅影响 IPv6（证据 [`AF6B`](../evidence/README.md)） |

> 第 5–8 条都不阻塞当前目标（图形会话 + 页面渲染 + 多窗口），但会持续产生日志噪音或限制工具链。
> `PR_SET_NO_NEW_PRIVS` 曾被列为缺口，实测**已实现**，已从清单撤回。

## 其他未实现 / 未验证

| 项 | 现状 | 影响 |
|---|---|---|
| 镜像自动进 kiosk 会话 | 内核把 `/sbin/init` 当子进程启动，busybox init 要求自己是 PID 1（`init: must be run as PID 1`），`/etc/inittab` 的 `tty1::respawn:…` 不执行 | 图形会话需由脚本/手工拉起；`patches/series/0003` 是这次尝试，目的未达成，保留是为了与已提交内核一致 |
| `VmRSS` / `statm` / `/proc/stat` / `uptime` / `loadavg` | 未实现。**刻意缺字段而非填 0**：MM 没有驻留页计数，填 0 会让 `ps`/`top` 报 "RSS=0"，读者无法区分"未实现"与"真是 0" | 客机内 `top`/`ps` 的内存列不可用；合作分支另有完整实现，**不随本仓库交付** |
| `/proc/sys/fs/inotify/*` | 不存在；`cat /proc/sys/fs/inotify/max_user_watches` → No such file or directory | 只造成一条 ERROR 行 |
| `Failed to initialize cpuinfo` | 根因待查（`/proc/cpuinfo` 字段不全） | Chromium 降级到保守的 CPU 特性假设，影响 SIMD 路径选择，不影响正确性 |
| `EVIOCGABS`（绝对轴） | 未实现 | 只影响 `virtio-tablet` 这类绝对坐标指针；本项目用相对指针 `virtio-mouse-pci`，鼠标点击与跳转正常 |
| before/after 的百分比改善 | 已按同口径补跑 5+5 次，结论是**确无改善** | 这是实测负结果，不是未实现；详见 [performance.md](performance.md) |

## 三条口径说明（不是缺陷）

### 1. 绝对性能不可横向比较

全部测量在纯 TCG（无 KVM/HVF）下完成，绝对时间偏大。任务书初赛本来也不比较绝对值。
本仓库只主张**方法可复算、口径自洽**，不主张比别的实现快。

### 2. `kernel/` 是完整源码树

`kernel/` 现在是完整 x-kernel 源码（基线 `d3a6ec9` + 初赛解法），不是部分快照。
上游文档里的相对链接（例如 `net/knet/docs/design.md` 指向 `../src/*`）在完整树中可正常查看。

### 3. 客机内 `top` 的 CPU 百分比不可信

合作分支实测发现短周期计数异常（同一区间进程 `utime+stime` 增长 120–127 tick，
系统 `busy` 只增长 22–29 tick，另一区间集中增长 381 tick），原因未定。
因此本仓库**不用客机 `top` 的百分比**作性能结论；`cpu_pct` / `cpu_pct_load` 都是宿主测 QEMU 进程 CPU 时间，
不经过客机 `/proc/stat`，不受影响。

## 怎么确认这些结论

```powershell
# /proc 实际能力
powershell -NoProfile -ExecutionPolicy Bypass -File host\xkwin.ps1 `
  -Kernel artifacts\kernel-procfs.bin -Script "guest\v1-verify-procfs.sh" `
  -Command "sh /tmp/xk-v1-verify-procfs.sh go" -Tag PROC-CHECK -CommandTimeoutSec 300

# IPv6
powershell -NoProfile -ExecutionPolicy Bypass -File host\xkwin.ps1 `
  -Kernel artifacts\kernel-procfs.bin `
  -Command 'ls /proc/net; cat /proc/net/if_inet6 2>&1; ping -6 -c1 -W1 ::1 2>&1; ping -c1 -W1 127.0.0.1 2>&1' `
  -Tag AF6B -CommandTimeoutSec 300
```

对应原始会话：[`PROC-CHECK`](../evidence/README.md)、
[`AF6B`](../evidence/README.md)。
