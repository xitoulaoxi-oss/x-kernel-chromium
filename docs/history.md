# 研发历程（压缩版）

这不是逐轮流水账。这里只保留**改变了判断**的节点：哪些假设被否证、哪一处修复让画面出现、
哪些结论后来被推翻。原始读数都在 `evidence/`，可以逐条回查。

## 一、黑屏期：日志冻在 764 字节（10-14 ～ 10-15）

最初的目标很直接：让镜像自带的 X11 kiosk 会话起来，再让 Chromium 显示页面。
实际看到的是：Xorg 能起、JWM 能起、Chromium 主进程和 zygote 也能起，但 renderer 永远不出现，
浏览器日志**恒定停在 764 字节**，屏幕全黑（`colors=1`）。

期间逐一排查并否证了八个方向：

| 假设 | 否证方式 |
|---|---|
| GL / EGL 初始化 | `--use-gl=disabled --disable-gpu` 仍是 764 B |
| 忙等 / syscall 风暴 | 10 秒窗口 syscall 总量仅 +2000，`writev`/`ioctl` 零增长 |
| 反复重启子进程 | 间隔 8 秒两次 PID 快照：新增 0、消失 0 |
| 权限 / uid | 以 root 直跑（不经 `su`）同样无窗口 |
| inotify 缺失 | 补丁 0004–0007 后报错行消失，但窗口仍未出现 |
| D-Bus 缺失 | `--disable-features=DBus` 无效 |
| xcb / Xlib 差异 | `xkbcomp` 以 kiosk 身份 rc=0 并生成 61 KB 键映射 |
| socket 选项被拒 | 内核加日志后实测 `rejected=0` |

也走过几条弯路，后来都写进了 [engineering-notes.md](engineering-notes.md)：

- 多脚本串跑时，后一个脚本的 `pkill` 拆掉了前一个的会话，被误判成"Xorg 会死"；
- 启动后 25 秒读 `_NET_CLIENT_LIST` 是空的（JWM 还没登记），被误判成"窗口从未创建"；
- 用 `--type=renderer` 在进程表里找 renderer，永远找不到——这个 build 不重写子进程 argv。

## 二、两个真正的根因（10-15，第 23–24 轮）

组员的日志里已经出现过两条关键线索。把它们移植进主线后，问题一次收敛。

### 1. AF_UNIX 流上的 SCM_RIGHTS 完全缺失

Chromium 的 Mojo 用 `sendmsg + SCM_RIGHTS` 传 fd。`net/knet` 的 unix stream 传输层只搬字节，
把 `SendOptions::ancillary` 丢掉了；子进程收不到 fd，`EnsureConnected` 超时，renderer 不出现。

修法不是"加一个字段"，而是把控制消息当成一条与字节流同步的通道：

- `AncillaryData` 由 `Box` 改 `Arc`，因为 `MSG_PEEK` 必须借用而不是移动；
- 新增 `ControlRecord` / `StreamControl` FIFO，记录"这批控制数据属于哪一段字节"；
- `recv` 以队首记录为**接收屏障**，绝不跨记录合并两次 `sendmsg` 的 rights；
- `posix/net` 侧按 `cmsg_len` 对齐步进，限制 `SCM_MAX_FD=253`。

证据：`SCM-20261015T140943Z`，修复后窗口首次出现，读数 `colors=336`（此前所有轮次都是 `colors=1`）。

### 2. SCTLR_EL1.UCT/UCI 导致 EL0 读 CTR_EL0 触发 SIGILL

SCM_RIGHTS 修好后，页面显示 Chromium 崩溃页 `Aw, Snap! Error code: SIGILL`。
根因是复位值下 `SCTLR_EL1.UCT/UCI = 0`，EL0 读 `CTR_EL0` 陷入 EL1，内核未认领，异常以 SIGILL 交给用户态；
libgcc 的缓存同步辅助函数正好读 `CTR_EL0`。

修法：`init_mmu()` 里放行 UCT/UCI（VHE 配置除外）。
证据：`SIGILL-20261015T141526Z`，崩溃页消失；紧接着 `RENDER-20261015T141742Z` 出现
`colors=835`，屏幕上就是组委会页面。同日的 `STAB10` 完成单窗口 600 秒稳定。

## 三、多窗口与输入链路（10-16，第 26 轮）

单窗口稳定后，目标是两个网页窗口 + Alt+Tab。

- 第二个窗口必须复用同一个 `--user-data-dir`，并用 `--new-window` 把 URL 交给已运行实例；
- 第二次调用**必须同样带 `--no-sandbox`**，否则进程直接退出（`Running as root without --no-sandbox`），
  根本走不到"交接 URL"那一步；
- Alt+Tab 的 `nextstacked` 绑定来自镜像自带的 `/etc/system.jwmrc`，不需要也不应该覆盖它；
- 输入设备需要写 `/run/udev/data/c13:*` 的 `ID_INPUT_MOUSE`/`ID_INPUT_KEYBOARD`，
  因为镜像里没有 udevd，libinput 否则看不到 virtio 键鼠。

同一轮还修了 TCP keep-alive：Chromium 的 network service 反复设置
`TCP_KEEPIDLE/INTVL/CNT`，被拒后重试刷屏，把串口淹没，导致 harness 的文件指纹校验连续失败。
修复后 `R37-MW4` 的 `sockopt rejected` 从 36 降到 0。

## 四、评分项补强（10-16 ～ 10-18，第 27 轮之后）

- **procfs**：补 `State / PPid / Threads / VmSize` 与 `stat.vsize`，并用 `PPid + Threads` 证明
  renderer 子进程真的存在。`VmRSS` 刻意不填 0。
- **稳定性**：最终内核 + 双窗口，600 秒 × 10 次采样。
- **性能**：从代理口径 `paint_s`（日志跨 10 KB）改为 screendump 首帧 `first_frame_s`；
  renderer 从 5 s 采样改为 1 Hz；加入宿主 CPU / 内存率。共 8 次运行，6 类指标。
- **before/after**：按同口径补跑 5 + 5 次，结论是**没有百分比改善**；如实保留负结果。
- **上游**：把 DRM legacy modeset、SETPROPERTY、GEM_CLOSE/CLOSEFB 拆成独立 PR。

## 五、最终验收（10-19）

| 会话 | 证明了什么 |
|---|---|
| `LAYOUT-20261019T021243Z` | `layout.html` 渲染 `colors=691`，三页至此都有渲染读数 |
| `PROC-CHECK-20261019T052522Z` | 交付内核的 `/proc` 只到 `State/PPid/Threads/VmSize` + `stat.vsize` |
| `AF6B-20261019T054919Z` | `AF_INET6` 返回 `EAFNOSUPPORT`，IPv4 正常 |
| `STAB10P-20261019T062937Z` | 推荐内核双窗口 600 秒，11 次采样全部 `colors=835` |
| `INTER7-20261019T064147Z` | `interaction.html` 渲染 `colors=886` |
| `SELF-TEST-2026-10-16` | 只用包内文件跑出的自证（`colors=892`） |

上游在 10-18 / 10-19 合入 `!1039`、`!1050`、`!1059` 三个 DRM 补丁。
详细状态见 [upstream.md](upstream.md)。

## 被推翻的结论

| 当时的结论 | 现在的事实 | 为什么会错 |
|---|---|---|
| Chromium 从未创建窗口 | ✅ 两个窗口，`_NET_CLIENT_LIST` 两个 id | 在启动后 25 秒读，JWM 还没登记 |
| 页面无法渲染（`colors=1`） | ✅ `835 / 847 / 892 / 886 / 691` | SCM_RIGHTS + UCT/UCI 两个根因未除 |
| 三张测试页只有一张能渲染 | ✅ 三页都有渲染读数 | 后续补了 `layout` 与 `interaction` 的会话 |
| 瓶颈是 seccomp / ptrace | ❌ 加 `--no-sandbox` 后能起 | seccomp 只在"不加该参数"时才致命 |
| Xorg 会在 Chromium 连接后死掉 | ❌ Xorg 全程健康 | 后一个脚本的 `pkill` 拆了会话 |
| `PR_SET_NO_NEW_PRIVS` 缺失 | ❌ 早已实现 | 早期清单未逐个核对源码 |
| `renderer` 可以用 `--type=renderer` 找到 | ❌ 子进程 argv 仍是 `--type=zygote` | 这个 build 不重写 argv，必须看进程树 |
| 性能 before/after 有改善 | ❌ 无改善，且两段式有顺序偏置 | 旧口径 `paint_s` + 非交错采样 |

> **外网访问**曾在演示素材中观察到（bilibili / 4399），但仓库不收录视频与截图，也没有可复算的画面数据，
> 因此不作为验收结论。IPv4 本机回环由 `AF6B` 会话证明可用。

## 留下的教训

1. **先读 `/proc/<pid>/stat` 的 `state` 与 `wchan`**，再猜"阻塞在哪个 syscall"。忙等（`R`）和阻塞（`S`）
   要修的地方完全不同。
2. **窗口类判据要在稳定期读**。启动后立刻读 `_NET_CLIENT_LIST` 会得到假阴性。
3. **screendump 必须量像素**。空白页 + 转圈有 264 色；"有颜色"不等于"画出来了"。
4. **传输是窄带**。单脚本 < 1792 B、单次可靠传输约 4 KB；超限拆脚本，不要放宽校验。
5. **失败样本要保留**。页面没画出来就记 `not found`，不要重跑到好看为止。
6. **一个补丁一件事**。42 文件的巨型补丁无法被上游评审，也无法回滚。

## 现在的状态

功能目标已达成；剩下的主要是系统调用缺口、`/proc` 完整性和上游合并策略，
见 [limitations.md](limitations.md) 与 [upstream.md](upstream.md)。
