# guest/

客机侧 shell 脚本。由宿主 harness 通过串口送进客机执行，脚本落到 `/tmp/xk-<filename>`。

## 两条硬约束

1. **单个脚本必须小于 1792 字节。** 超过会被串口 heredoc 拼接，实测尾部会粘到下一条命令上，
   而字节数校验抓不到。
2. **脚本名会变成 `/tmp/xk-<文件名>`。** 宿主侧 `-Key "cmd=sh /tmp/xk-y6-evidence.sh"`
   依赖它已经被上传。

大文件不要走串口：`host/xkwin.ps1` 用一次性 HTTP 服务器（`-ServeManifest`）供客机 `wget`。

## 成功路径

| 顺序 | 脚本 | 作用 |
|---|---|---|
| 1 | `06-fetch-pages.sh` | 从宿主 HTTP 取三张页面，**在客机内**核对字节数与 SHA-256，并改写 `/etc/kiosk/url` |
| 2 | `x1-input.sh` | 写 `/run/udev/data/c13:64`、`c13:65`（键鼠）；设备号从 `/sys` 推导。**镜像无 udevd，不写就没有输入** |
| 3 | `x2-xorg.sh` | Xorg：modesetting + `AccelMethod none` + `ShadowFB` + `SWcursor` |
| 4 | `y3-jwm-stock.sh` | 用**镜像自带**的 `/etc/system.jwmrc` 起 JWM（Alt+Tab 的 `nextstacked` 就来自它） |
| 5 | `x4-win1.sh` | 起 Chromium 窗口 1（`index.html`），等窗口出现 |
| 6 | `y6-evidence.sh` | 读数：窗口列表、`_NET_WM_PID`、`WM_CLASS`、Xorg 输入段 |
| 7 | `x5c-win2.sh` | 同 profile + `--new-window` 开窗口 2（`interaction.html`）；失败则退回"第二实例、独立 profile" |
| 8 | `s9-stability10.sh` | 10 分钟稳定性采样（每分钟一行） |
| 9 | `v1-verify-procfs.sh` | 验证 `/proc` 字段（需传 `go`） |
| 10 | `x8b-roles-late.sh` | 诊断：进程树 + 线程数，用来证明 renderer 子进程（晚采样 150 s） |

## 页面与窗口

| 脚本 | 页面 |
|---|---|
| `x4-win1.sh` | `index.html`（指定 HTML） |
| `x5c-win2.sh` | `interaction.html`（JS 交互） |
| `x6-layout.sh` | `layout.html`（CSS 布局） |
| `x7-interaction.sh` | `interaction.html`（交互页专项） |

## 性能

| 脚本 | 作用 |
|---|---|
| `c1-perf-x.sh` | 起 Xorg + JWM，写 `/tmp/perf.t0`（客机侧共同零点） |
| `c2-perf-prep.sh` | 清 profile / 清 marks；**必须在测量窗口之外** |
| `c2-perf-launch.sh` | t=0：一条控制台命令起 Chromium 后立刻返回，并把 1 Hz 监视器挂到后台 |
| `c2-perf-monitor.sh` | 1 Hz 里程碑：`chrome_s`、`renderer_s`（含 pid 与线程数） |
| `c1-perf-harvest.sh` | 收割：等到需要的里程碑后把 `/tmp/perf.marks` 打到串口 |
| `c1-perf-chrome.sh` | 旧口径（日志跨 10 KB），**仅供复算旧会话**，新数据不用 |

## 稳定性观测

| 脚本 | 作用 |
|---|---|
| `hb.sh` | 每分钟打印 `HB t=... chrome=... mem_mb=...` |
| `hb-start.sh` | 在客机后台启动心跳 |
| `hb-dump.sh` | 打印心跳历史，供 console 解析 |
| `chrome-mem.sh` | 汇总客机 Chromium 进程 RSS（1.5G 资格线口径） |

## 手动演示 / 帧采集

| 脚本 | 作用 |
|---|---|
| `r1-launch.sh` / `r2-win2.sh` | 演示：发起即返回；`r2` 需传 `go` 才真开窗 |
| `rec-chrome.sh` / `rec-ready.sh` | 拉起 kiosk 单窗口并等标题变成页面标题（`rec-ready` 最多重试 3 次） |

这些脚本用于**手动操作与帧采集**。仓库不收录视频与截图；验收仍以运行时生成的 screendump 与 console 为准。

## 必须记住的结论

- **第二次调用 Chromium 必须带 `--no-sandbox`**：不带会直接退出
  （`Running as root without --no-sandbox is not supported`），根本走不到"把 URL 交给已运行实例"。
- **不要用 `--type=renderer` 找 renderer**：这个 build 不重写子进程 argv，renderer 的 cmdline 仍是
  `--type=zygote`。判据是**进程树**（`PPid` 指向 zygote）＋**线程数**。
- **启动必须是一条命令**：`c2-perf-launch.sh` 由宿主在帧观测 t=0 用一行命令发出，
  上传、profile 清理都不能写在里面（会被算进页面加载延迟）。
- **不要等监视器退出**：`c1-perf-harvest.sh` 只等 `chrome_s`/`renderer_s`。
  实测出现过监视器写完里程碑后不再写 `done=1` 的情况，等它会白等 200 s，还会拖坏 `cpu_pct` 的分母。
- **只有第一个脚本可以带 `pkill` 类清理动作**：后续脚本的 `pkill` 会拆掉前面的会话，
  历史上曾被误判成"Xorg 会死"。

## 页面来源

`serve-pages.txt` 按仓库根解析，指向 [`../pages/`](../pages/) 的三个文件：

```text
pages/index.html
pages/interaction.html
pages/layout.html
```

客机取件后在**客机内**校验 sha256，打印 `P1 ok=3 bad=0`。

## 相关

- 验收命令：[../docs/verification.md](../docs/verification.md)
- 宿主 harness：[../host/README.md](../host/README.md)
- 工程规则：[../docs/engineering-notes.md](../docs/engineering-notes.md)
