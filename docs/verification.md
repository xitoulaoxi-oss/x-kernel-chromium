# 验收与取证

这份文档说明如何从零跑一遍验收，以及如何判断"画面真的出来了"。

## 前提

- Windows 10/11，PowerShell 5.1；
- `qemu-system-aarch64` 在 PATH 中（或设置 `XK_QEMU`）；
- Python 3 在 PATH 中（或设置 `XK_PYTHON`）；
- 赛题方提供的 `agentos-disk.img`（不在仓库内）；
- 推荐内核：从 Releases 下载 `kernel-procfs.bin` 到 `artifacts/`，或运行 `bash build/build-kernel.sh` 生成。

## 五分钟验收

在**仓库根目录**执行：

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

### 期望读数

| 观察点 | 期望值 |
|---|---|
| 最终 screendump | `1280x800 colors≈892 dominant≈0.32 blank=False` |
| 窗口列表 | `_NET_CLIENT_LIST` 两个 id（例如 `0x400009, 0x400003`） |
| 窗口身份 | 两个窗口 `_NET_WM_PID` 相同，`WM_CLASS` 都是 `chromium (/tmp/pr)` |
| 切换 | 两次 Alt+Tab 后 `_NET_ACTIVE_WINDOW` 与 `_NET_CLIENT_LIST_STACKING` 双向翻转 |
| 进程 | 15 个 chromium 相关进程；zygote 之下有 fork 出来的子进程 |
| 页面 | `06-fetch-pages.sh` 打印 `P1 ok=3 bad=0` |

产物落在 `runs\CHECK\`。跑完 QEMU 会自己退出。

### 为什么必须带 `-ServeManifest`

交付镜像里没有三张组委会页面，只有 3,024 B 的占位页。漏掉这个参数会得到
Chromium 的 `ERR_FILE_NOT_FOUND`，截图颜色数只有约 427——看起来像"渲染失败"，
实际上是页面根本没进客机。

## 手动操作

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File host\xkwin.ps1 `
  -Tag DEMO -Disk "<image-dir>\agentos-disk.img" `
  -Kernel artifacts\kernel-procfs.bin `
  -ServeManifest guest\serve-pages.txt `
  -Script "guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\r1-launch.sh" `
  -Display gtk -Keep -AfterScriptWait 30 `
  -CommandTimeoutSec 300 -BootTimeoutSec 420 -OutDir "runs\DEMO"
```

- `-Display gtk` 打开原生窗口；不加则默认 VNC，用客户端连 `127.0.0.1:5900`。
- `-Keep` 让 QEMU 在脚本跑完后保持运行；结束时关窗口或 `taskkill /IM qemu-system-aarch64.exe`。
- 可手动按：`Alt+Tab` 切窗口、`Ctrl+N` 新窗口、`Ctrl+L` 输网址、`Alt+F1` 打开 JWM 菜单。

## 单独渲染一页

三页的脚本只差 URL：

```powershell
# CSS 布局页
powershell -NoProfile -ExecutionPolicy Bypass -File host\xkwin.ps1 `
  -Kernel artifacts\kernel-procfs.bin -ServeManifest guest\serve-pages.txt `
  -Script "guest\06-fetch-pages.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x6-layout.sh" `
  -Tag LAYOUT -CommandTimeoutSec 400 -AfterScriptWait 60

# JavaScript 交互页
powershell -NoProfile -ExecutionPolicy Bypass -File host\xkwin.ps1 `
  -Kernel artifacts\kernel-procfs.bin -ServeManifest guest\serve-pages.txt `
  -Script "guest\06-fetch-pages.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x7-interaction.sh" `
  -Tag INTER -CommandTimeoutSec 400 -AfterScriptWait 60
```

已知读数：`index` `colors=835/847/892`，`interaction` `colors=886`，`layout` `colors=691`。
三个数不同是正常的：页面结构不同，色数不是"越大越好"，判据是**非空白 + 页面区饱和度**。

## 600 秒稳定性

```powershell
$one = 'cmd=sleep 60 && echo S x=$(ps w|grep -c "[X]org") j=$(ps w|grep -c "[j]wm") c=$(ps w|grep -c "[c]hromium")'
$key = ($one,$one,$one,$one,$one,$one,$one,$one,$one,$one) -join ';'

powershell -NoProfile -ExecutionPolicy Bypass -File host\xkwin.ps1 `
  -Kernel artifacts\kernel-procfs.bin -ServeManifest guest\serve-pages.txt `
  -Script "guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x4-win1.sh" `
  -Key "$key" -Tag STAB10P -CommandTimeoutSec 300
```

期望：10 次采样均为 `x=1 j=1 c=11`，11 帧全部 `colors=835`、`blank=False`。
实测见 [`evidence/sessions/STAB10P-20261019T062937Z/`](../evidence/sessions/STAB10P-20261019T062937Z/)。

> `-Key` 直接送进客机会话的 shell 没有 `DISPLAY`/`XAUTHORITY`，所以那条命令里的 `w=`（窗口计数）
> 恒为 0。窗口本身存在，由同会话的 `console.log` 读数与 `INTER7`/`LAYOUT` 的窗口 ID 证明；不要拿这个 0 当"没有窗口"。

## 读一次会话的证据

每个会话目录（例如 `evidence/sessions/R37-MW4-20261016T101127Z/`）包含：

| 文件 | 怎么用 |
|---|---|
| `console.log` | 搜 `_NET_CLIENT_LIST`、`sockopt rejected`、`P1 ok=` 等读数 |
| `NN-after-*.stats.json` | 该帧的 `colors` / `dominant_fraction` / `blank`（PNG 不随仓库发布） |
| `qemu-cmd.txt` | 完整 QEMU 命令行，含实际内核路径 |
| `qemu-metrics.json` | 宿主峰值工作集、CPU 时间与分母 |
| `frame-watch.json` | 帧序列与首帧判定（仅帧观测会话） |
| `run-*.txt` | 各个客机脚本的控制台输出 |

单张 screendump 复核（需本次运行生成的 PNG）：

```powershell
python host\screen_stats.py runs\CHECK\zz-final.png
```

首帧复核需要 `frame-watch.json` 与该会话的 `fw-*.png`；仓库不保存截图，因此复现首帧需先重跑该会话。

## 证据原则

1. **截图成功不等于画面有内容。** 空白页 + 转圈可以有 264 种颜色；必须看饱和度与页面区域。仓库保留 `.stats.json`，但不保存 PNG。
2. **每个数字都有原始文件。** 文档中的读数必须能在 `console.log`、`.stats.json` 或 `*.json` 中找到。
3. **不删失败轮次。** 没画出来就记 `not found`，样本量变化写清楚。
4. **仓库不收录视频与截图。** 验收时由 harness 生成 screendump；录屏不作为依据。

## 工具参数速查

| 参数 | 作用 |
|---|---|
| `-Kernel` | 内核路径（默认 `artifacts\kernel-procfs.bin`） |
| `-Disk` | 交付镜像路径 |
| `-Script` | `;` 分隔的客机脚本，按顺序上传并执行 |
| `-Upload` | 只上传不执行（性能测量前用） |
| `-Key` | `;` 分隔的按键或 `cmd=` 命令，每步截一张图 |
| `-FrameWatch` | `间隔x时长`，例如 `2x140` |
| `-FrameWatchCmd` | t=0 时异步发出的客机命令 |
| `-ServeManifest` | 给客机 HTTP 取件的文件清单 |
| `-Keep` | 跑完不退出 QEMU |
| `-OutDir` | 会话输出目录 |

完整参数与实现见 [`../host/xkwin.ps1`](../host/xkwin.ps1)。
