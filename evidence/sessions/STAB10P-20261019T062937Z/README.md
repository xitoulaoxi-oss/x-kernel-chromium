# 10 分钟稳定性（交付推荐内核，600 s，11 次采样）

本目录专门回答一个此前没被满足的问题：**仓库推荐的内核 `kernel-procfs.bin` 自己有没有 10 分钟稳定性证据**。
此前那轮稳定（`R38-STAB10B`）用的是 `kernel-keepalive.bin`，与本目录不是同一枚内核。

| 项 | 值 |
|---|---|
| 内核 | `artifacts/kernel-procfs.bin`，sha256 `5261CEB3C11249A7…`（= `kernel-scmrights.bin`） |
| 会话 | `STAB10P-20261019T062937Z` |
| 分辨率 | 1280×800 |
| 时长 | **600 s**（10 次采样，每次 60 s） |
| 采样内容 | 客机 `ps w` 的 Xorg/jwm/chromium 计数 + 一次 `screendump` 的统计 |

## 逐帧读数

| 帧 | colors | blank |
|---|---|---|
| `06-after-step-cmd` | 835 | False |
| `07-after-step-cmd` | 835 | False |
| `08-after-step-cmd` | 835 | False |
| `09-after-step-cmd` | 835 | False |
| `10-after-step-cmd` | 835 | False |
| `11-after-step-cmd` | 835 | False |
| `12-after-step-cmd` | 835 | False |
| `13-after-step-cmd` | 835 | False |
| `14-after-step-cmd` | 835 | False |
| `15-after-step-cmd` | 835 | False |
| `zz-final` | 835 | False |

**11 次采样全部 `colors=835`、`dominant=0.2951`、`blank=False`，无黑屏、无花屏、无差异。**

> 截图文件未随仓库发布；上表来自逐次 `.stats.json` 的读数。

## 进程活性（每 60 秒一次）

10 次采样全部为 `x=1 j=1 c=11`：**Xorg 1 个、jwm 1 个、chromium 11 个进程，全程无退出**。
这正是"compositor 无退出"的判据。

> 说明：同一条命令里还打了一个 `w=`（窗口计数），读数恒为 0。原因是这条命令由 harness 的
> `-Key` 直接送进客机会话，那个 shell 没有 `DISPLAY`/`XAUTHORITY` 环境，`xprop` 查不到 root 属性。
> **窗口本身存在**——同一会话的渲染读数就是完整页面，且窗口 ID 在 `INTER7` 与
> `LAYOUT` 会话里均为 `0x400003`。此处如实记录，不用失真的 0 冒充读数。

## 复现

```powershell
cd <repo>
$one = 'cmd=sleep 60 && echo S x=$(ps w|grep -c "[X]org") j=$(ps w|grep -c "[j]wm") c=$(ps w|grep -c "[c]hromium")'
$key = ($one,$one,$one,$one,$one,$one,$one,$one,$one,$one) -join ';'
powershell -NoProfile -ExecutionPolicy Bypass -File host\xkwin.ps1 `
  -Kernel artifacts\kernel-procfs.bin -ServeManifest guest\serve-pages.txt `
  -Script "guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x4-win1.sh" `
  -Key "$key" -Tag STAB10P -CommandTimeoutSec 300
```
