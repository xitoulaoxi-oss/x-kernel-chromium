# host/

宿主工具。除特别说明外都是 Python 标准库，不需要安装依赖。

| 工具 | 用途 | 关键参数 |
|---|---|---|
| `xkwin.ps1` | 取证 harness：起 QEMU → 串口送脚本 → QMP 截图 → 量像素；`-FrameWatch` 按节拍抓帧 | `-Kernel`、`-Disk`、`-Script`、`-Upload`、`-Key`、`-FrameWatch`、`-FrameWatchCmd`、`-ServeManifest`、`-Display gtk`、`-Keep`、`-OutDir` |
| `screen_stats.py` | 单张截图的颜色数 / 主色占比 / 空白判定 | `python host/screen_stats.py <png>` |
| `frame_stats.py` | 首帧判定：逐张量色数与饱和度，给上下界与阈值敏感性 | `python host/frame_stats.py <session-dir> [--threshold 100]`；`--self-test` |
| `perf_run.py` | 6 类指标 × n 次 + 中位数/极差/CV；支持只重建报告 | `--repeats 5`、`--tag pf3`、`--out evidence/reports/perf-report.json`、`--reparse` |
| `perf_compare.py` | 由两份报告生成 before/after 对照（JSON + Markdown） | `--before`、`--after`、`--out`、`--md` |
| `ext4.py` | 纯 Python 读 ext4 镜像（没有 WSL/e2fsprogs 时也能查文件） | `python host/ext4.py <img> cat /etc/inittab` |
| `rootfs_audit.py` | 镜像内容清单 + 可回放的 debugfs 脚本 | `inventory`、`diff`、`debugfs-script`、`workcopy` |
| `make_rootfs_manifest.py` | 生成 rootfs 改动清单 | `--check` 只校验源文件 |
| `record-stability.ps1` | 稳定性/演示：GTK 窗口 + 守门人重试 + 定时抓帧 | `-Minutes 32`、`-DisplayMode none` |
| `demo-record.ps1` | 拉起可手动操作的会话（窗口留在桌面上） | 无参数即可 |
| `prepare-pr.ps1` | 把 `patches/upstream/port-to-main/` 拆成分支并打印 push 步骤 | `-GiteeUser`、`-Only`、`-Checkout` |
| `make_gif.py` | 把 screendump 序列合成 GIF（需要 Pillow；生成的 GIF 不提交） | `--dir`、`--out` |
| `observe.py` | 分析会话的崩溃/卡死/泄漏信号，输出 JSON | `python host/observe.py <session> [--expected-minutes 30] [--out observe.json]` |
| `monitor-qemu.ps1` | 运行期间采样 QEMU 工作集，写 `observe.jsonl` | `-OutDir`、`-IntervalSec 15`、`-Minutes 35` |

## 常用命令

```powershell
# 验收
powershell -NoProfile -ExecutionPolicy Bypass -File host\xkwin.ps1 `
  -Tag CHECK -Disk "<image-dir>\agentos-disk.img" `
  -Kernel artifacts\kernel-procfs.bin -ServeManifest guest\serve-pages.txt `
  -Script "guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x4-win1.sh;guest\y6-evidence.sh;guest\x5c-win2.sh" `
  -Key "cmd=sh /tmp/xk-y6-evidence.sh;alt+tab@8;cmd=sh /tmp/xk-y6-evidence.sh" `
  -CommandTimeoutSec 300 -BootTimeoutSec 420 -AfterScriptWait 20 -OutDir "runs\CHECK"

# 性能 5 次
python host\perf_run.py --repeats 5 --tag pf3 --out evidence\reports\perf-report.json

# 只重建报告，不重跑 QEMU
python host\perf_run.py --reparse --tag pf3 --out evidence\reports\perf-report.json

# 首帧重算
python host\frame_stats.py evidence\perf\pf31-20261018T172505Z
```

## 注意

- `powershell -File` 会把 `[string[]]` 参数收成一个逗号串，所以 `-Script` / `-Key` 都是
  **`;` 分隔的标量**，不是一个数组。多值请用分号。
- `-Kernel` 默认找 `artifacts\kernel-procfs.bin`、`artifacts\kernel.bin`。
- `-ServeManifest` 的路径相对仓库根；漏掉会导致页面没进客机（`ERR_FILE_NOT_FOUND`）。
- 宿主峰值内存/CPU 由 harness 在 **QEMU 还活着时**写 `qemu-metrics.json`，必须在 QMP `quit` 之前。
- 本机可能没有 `wmic`、`Get-CimInstance` 被拒；CPU/OS 取注册表，物理内存用
  `GlobalMemoryStatusEx`（kernel32）直接取。
- 仓库不提交视频与截图；`record-stability.ps1` 只在本地抓帧，用于稳定性检查。

## 相关

- 参数与验收：[../docs/verification.md](../docs/verification.md)
- 性能口径：[../docs/performance.md](../docs/performance.md)
- 工程规则：[../docs/engineering-notes.md](../docs/engineering-notes.md)
