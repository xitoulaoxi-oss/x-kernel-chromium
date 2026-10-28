# CSS 布局测试页渲染证据（2026-10-19）

> 原始测量记录，未改写。指标口径见 [`../../../docs/performance.md`](../../../docs/performance.md)，证据索引见 [`../../README.md`](../../README.md)。


本目录记录一次**完整冷启动**：交付内核 → Xorg → jwm → Chromium → 渲染 `layout.html`。
用途是补上此前唯一缺失的一页渲染读数（`index.html`、`interaction.html` 已有）。

| 项 | 值 |
|---|---|
| 内核 | `artifacts/kernel-procfs.bin`（git_commit `d3a6ec9`，`git_dirty=true`） |
| 磁盘 | 交付镜像 `agentos-disk.img`（`-snapshot`，不写回） |
| QEMU | virt / cortex-a72 / 4 vCPU / 4 GB / 纯 TCG |
| 客机分辨率 | **1280×800** |
| 页面 | `layout.html`，11,444 B，sha256 前 16 位 `a1b04f9aba81b4b7`（客机内自校验） |

## 关键读数

| 阶段 | 读数 | 文件 |
|---|---|---|
| 三页下发 | `ok=3 bad=0`；index 5,730 / interaction 10,991 / layout 11,444 字节，sha256 全部匹配 | `console.log` |
| X 起来 | `xsock=yes`，Xorg 日志 2,764 B | `console.log` |
| jwm 起来 | `_NET_SUPPORTING_WM_CHECK` = `0x200001`；`colors=28`（桌面） | `console.log`、`03-after-y3-jwm-stock.stats.json` |
| Chromium 窗口 | `_NET_CLIENT_LIST` = **`0x400003`**；t=45 s 起 `wins=1` | `console.log` |
| **布局页渲染** | **`colors=691`，`dominant=0.2855`，`blank=False`** | `04-after-x6-layout.stats.json`、`zz-final.stats.json` |
| QEMU 峰值工作集 | 见 qemu-metrics.json | `qemu-metrics.json` |

> 对照：`index.html` 在既有会话里是 `colors=835 / 847 / 892`；布局页结构更简单，
> 691 色属于正常量级。判定用的是「非空白 + 页面区饱和度」，不是单一色数（见
> `../../../docs/performance.md` §3）。

## 复现

```powershell
cd <repo>
powershell -NoProfile -ExecutionPolicy Bypass -File host\xkwin.ps1 `
  -Kernel artifacts\kernel-procfs.bin `
  -ServeManifest guest\serve-pages.txt `
  -Script "guest\06-fetch-pages.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x6-layout.sh" `
  -Tag LAYOUT -CommandTimeoutSec 400 -AfterScriptWait 120
```

四个客机脚本都可单独复核（见 `guest/`）；`x6-layout.sh` 与既有的 `x4-win1.sh` 唯一的差别是 URL
（一个 `index.html`，一个 `layout.html`），启动参数逐字相同。

> 截图由**宿主**用 QMP `screendump` 生成，不是主机屏幕录像——按赛题要求，
> 录屏不作验收依据。截图本身不随仓库发布；本目录保留 `console.log` 与统计 JSON。
