# 性能测量

性能数据的目标不是"证明比谁快"，而是**把方法说清楚、让别人能复算**。
本页定义 6 类指标、给出 8 次独立运行的结果，并说明哪些数字不能直接比较。

## 结论

- 同一套脚本、同一批运行，覆盖 **6 类**指标：`startup`、`page-load`、`renderer-creation`、
  `peak-memory`、`cpu-usage`、`qemu-memory-rate`。
- 每类至少有 **6 个**完整样本；关键指标给出中位数、min/max、极差与 CV。
- 全部测量在**纯 TCG**（无 KVM/HVF）下完成，绝对时间偏大，只适合同环境横向自比。
- 原始数据：[perf-report.json](../evidence/reports/perf-report.json)，会话：[evidence/perf/](../evidence/perf/)。

## 指标定义

| 指标 | 类别 | 单位 | 零点 | 测法 | 数据源 | 分辨率 |
|---|---|---|---|---|---|---|
| `xorg_s` | startup | s | 客机 `/tmp/perf.t0` | 等到 `/tmp/.X11-unix/X0` 出现 | 客机串口 | 1 s |
| `jwm_s` | startup | s | 同上 | JWM 被拉起 | 客机串口 | 1 s |
| `chrome_s` | startup | s | 同上 | 1 Hz 监视第一个 `chromium --ozone` 主进程 | 客机串口 | 1 s |
| `first_frame_s` | page-load | s | **宿主发出启动命令** | 2 s 节拍 screendump，第一张满足"页面区饱和度 ≥ 0.06 且色数 ≥ 300 且非空白"的帧 | 宿主 `frame-watch.json` | 2 s |
| `renderer_s` | renderer-creation | s | X 启动 | 1 Hz 扫进程树：`PPid` 属于 `--type=zygote` 的第一个子进程 | 客机串口 | 1 s |
| `peak_mem_mb` | peak-memory | MB | QEMU 进程全生命周期 | `Process.PeakWorkingSet64` | 宿主 `qemu-metrics.json` | 高水位 |
| `cpu_pct` | cpu-usage | % 单核 | 同上 | `TotalProcessorTime ÷ wall_seconds × 100` | 宿主 `qemu-metrics.json` | 全程平均 |
| `cpu_pct_load` | cpu-usage | % 单核 | 启动命令 → 首帧 | 首帧窗口内 QEMU CPU 秒的差 ÷ 该区间墙钟 | 宿主 `frame-watch.json` | 2 s |
| `qemu_mem_pct` | qemu-memory-rate | % 宿主内存 | QEMU 全生命周期 | `PeakWorkingSet64 ÷ host_ram_b × 100` | 宿主 `qemu-metrics.json` | 高水位 |

比值需要的分母（`wall_seconds`、`host_ram_b`、`guest_mem_mb`、`smp_cpus`）由 harness 当场采集，
不写死、不估算。

## 首帧判定：为什么不能只看色数

第一版用"色数 ≥ 100"。实测否掉了这个判据：空白页 + 转圈本身就有 264 种颜色。

| 画面状态 | 色数 | 主导色占比 | 饱和像素占比 | 色数判据 | 饱和度判据 |
|---|---|---|---|---|---|
| 纯桌面（X + JWM） | 28 | 0.960 | 0.000 | 未画出 | 未画出 |
| 浏览器窗口壳 | 91 | 0.753 | 0.040 | 未画出 | 未画出 |
| **空白页 + 转圈** | **264** | 0.680 | **0.040** | **误判为已画出** | 未画出 ✓ |
| 页面内容出现 | 526 | — | 0.107 | 已画出 | 已画出 ✓ |
| 页面完整绘制 | 835 | 0.295 | 0.156 | 已画出 | 已画出 ✓ |

因此采用：

```text
painted = saturation_frac >= 0.06
          and colors >= 300
          and not blank
```

阈值敏感性（同一批帧换阈值重算）：

| 会话 | 色数口径会判定的首帧 | 饱和度口径 | 页面真的画出来了吗 |
|---|---|---|---|
| pf31 | 50.0 s | 54.0 s | 是 |
| pf31b | 48.0 s | 54.1 s | 是 |
| pf32 | 48.0 s | 56.0 s | 是 |
| pf32b | 56.0 s | 62.0 s | 是 |
| pf33 | 50.0 s | 54.0 s | 是 |
| pf33b | 66.1 s | 未判定 | **否（140 s 内一直空白）** |
| pf34 | 66.1 s | 未判定 | **否（140 s 内一直空白）** |
| pf35 | 50.0 s | 56.1 s | 是 |

饱和度阈值在 0.04–0.08 之间结果稳定（每轮差 ≤ 1 帧即 2 s）；
色数口径会**提前 4–6 s**报出首帧，并在两轮"页面根本没画出来"的会话上给出 66.1 s 的假读数。

## 统计结果

数据：[perf-report.json](../evidence/reports/perf-report.json)；会话：`evidence/perf/pf3*`。

| 指标 | 类别 | 逐次原始值 | 中位数 | min | max | 极差 | CV |
|---|---|---|---|---|---|---|---|
| `chrome_s` | startup | 6, 6, 6, 6, 6, 7, 7, 7 | **6** | 6 | 7 | 1 | 8.12% |
| `xorg_s` | startup | 0, 0, 0, 0, 0, 1, 1, 1 | **0** | 0 | 1 | 1 | 138.01% |
| `jwm_s` | startup | 1, 1, 1, 1, 2, 2, 2, 2 | **1.5** | 1 | 2 | 1 | 35.63% |
| `first_frame_s` | page-load | 54.041, 56.043, 54.033, 56.051, 54.059, 62.04 | **55.051** | 54.033 | 62.04 | 8.007 | 5.53% |
| `renderer_s` | renderer-creation | 29, 30, 30, 30, 30, 33, 39, 41 | **30** | 29 | 41 | 12 | 14.21% |
| `peak_mem_mb` | peak-memory | 2013.5, 2020.9, 2024.6, 2060.8, 2061.1, 2074.7, 2078.1, 2105.8 | **2060.95** | 2013.5 | 2105.8 | 92.3 | 1.58% |
| `cpu_pct` | cpu-usage | 93.13, 101.57, 106.88, 107.56, 108.44, 115.3, 197.19, 200.31 | **108** | 93.13 | 200.31 | 107.18 | 33.89% |
| `cpu_pct_load` | cpu-usage | 253.05, 253.29, 255.7, 258.49, 259.03, 261.24 | **257.095** | 253.05 | 261.24 | 8.19 | 1.29% |
| `qemu_mem_pct` | qemu-memory-rate | 6.166, 6.188, 6.199, 6.31, 6.311, 6.353, 6.363, 6.448 | **6.31** | 6.166 | 6.448 | 0.282 | 1.58% |

| 类别 | 指标 | 完整样本 | 是否 ≥ 5 |
|---|---|---|---|
| `cpu-usage` | `cpu_pct`, `cpu_pct_load` | 6 | 是 |
| `page-load` | `first_frame_s` | 6 | 是 |
| `peak-memory` | `peak_mem_mb` | 8 | 是 |
| `qemu-memory-rate` | `qemu_mem_pct` | 8 | 是 |
| `renderer-creation` | `renderer_s` | 8 | 是 |
| `startup` | `chrome_s`, `jwm_s`, `xorg_s` | 8 | 是 |

`xorg_s` 的 CV 高达 138%，但它的取值只有 0 或 1——CV 在"分辨率本身就是最小单位"的量上没有意义。
报告保留它，是为了不替读者做取舍。`jwm_s` 同理。

## 不能忽略的样本

8 次里有 **2 次**页面在 140 s 窗口内没有画出来（`pf33-20261018T174854Z`、`pf34-20261018T173437Z`）。
这两轮的 `cpu_s` 是 382.3 / 376.8 s，其余 6 轮 177.6–220.1 s；`cpu_pct` 是 200.3 / 197.2，
其余 93–115。指向测量期间宿主争用。

处理方式：`first_frame_s` 记为 `not found`，不参与中位数，因此首帧类指标 n=6；
数据原样保留，没有"重跑到好看为止"。**下一次测量应独占宿主**。

## 误差与边界

| 项 | 现状 |
|---|---|
| 首帧分辨率 | 2 s 采样；报抓取完成时刻（上界），并用上一帧给出下界 `first_frame_lo_s` |
| 首帧判据适用面 | 饱和度阈值按 `index.html` 标定；换页面需重标。原始 PNG 未随仓库发布，`frame-watch.json` 与报告保留，可按相同口径复核 |
| 客机侧分辨率 | busybox `date` 只到秒，故启动类指标为 1 s |
| renderer 判据 | "zygote 的第一个子进程"，不是"渲染完成"；子进程 argv 仍是 `--type=zygote` |
| `cpu_pct` | 整个 QEMU 生命周期的平均，含抓帧结束后的空转；看启动负载请用 `cpu_pct_load` |
| `peak_mem_mb` | QEMU 进程工作集，不是客机内某进程的 RSS（本内核给不出 `VmRSS`） |
| 绝对时间 | 纯 TCG，不能与其他硬件横向比绝对值 |

## before/after：旧口径，结论是"没有改善"

任务书要求以"首个可运行版本"为基线做 before/after。本仓库保留了当时的对照，但必须带着口径读：

- 基线：`kernel-keepalive.bin`（首个可运行版本）；
- 最终：`kernel-procfs.bin`；
- 每项 5 / 6 次，取中位数；旧口径的页面加载指标是 `paint_s`（Chromium stderr 日志跨过 10 KB），**不是首帧**。

| 指标 | 类别 | before | after | 相对改善 | 赛题档位 |
|---|---|---|---|---|---|
| `startup_total_s` | startup | 11 | 13.00 | −18.2% | — |
| `chrome_s` | startup | 8 | 10.00 | −25.0% | 0 |
| `paint_s` | page-load | 54 | 58.00 | −7.4% | 0 |
| `renderer_s` | renderer-creation | 20 | 36.00 | −80.0% | 0 |
| `peak_mem_mb` | peak-memory | 2045.30 | 2037.05 | +0.4% | 0 |
| `cpu_s` | cpu-usage | 174.52 | 180.12 | −3.2% | 0 |

**没有任何指标达到 5% 档位。** 更重要的是：

- `renderer_s` 在两枚内核上测的**不是同一件事**：基线缺 SCM_RIGHTS，zygote 反复 fork 重试，
  "第一个子进程"很早成立；最终版交接成功，子进程按需才 fork，读数反而更晚。
  实测 `renderer_forks` 中位数 before=16、after=5，两组内部都稳定——这是行为差异，不是性能回归。
- 两批是"先 base 后 after"的两段式，不是交错 A/B；`chrome_s`/`paint_s` 在两段内部都随时间上升，
  更像宿主状态漂移 + 顺序偏置。

因此这里只主张**方法可复算、负结果如实保留**，不主张任何性能优势。原始报告：
[perf-report-before.json](../evidence/reports/perf-report-before.json)、
[perf-report-after.json](../evidence/reports/perf-report-after.json)、
[perf-before-after.json](../evidence/reports/perf-before-after.json)。

## 独立交叉验证（不同口径，不并入统计）

### CDP 页面目标

用 Chromium DevTools `http://127.0.0.1:9222/json/list` 等 `type: "page"`：

| 轮次 | 1 | 2 | 3 | 4 | 5 | 中位 | 平均 |
|---|---|---|---|---|---|---|---|
| 就绪 (s) | 44 | 49 | 43 | 47 | 40 | **44** | **44.6** |

它测的是"浏览器已经有页面目标"，既不是 renderer 创建，也不是首帧。三者单调递增、互相自洽：

```text
renderer_s 30.0 s  <  CDP 页面目标 44.6 s  <  first_frame_s 55.05 s
```

**任意两个都不能相减**当作"渲染耗时"。

### 客机整机内存增量

同一批启动用 `free -m` 采样（19 个样本，约 5 s 一次）：总内存 2038 MiB 不变，
used 从 584 MiB 升到峰值 878 MiB，**+294 MiB**，Swap 恒 0。

这是整台客机（Xorg + JWM + Chromium + 子进程）的增量，不是 Chromium RSS；
与宿主 `peak_mem_mb`（2060.95 MB）量纲不同，只能做量级一致性判断。

### procfs 能力交叉验证

本仓库交付内核的 `/proc` 只到 `State / PPid / Threads / VmSize` 与 `stat.vsize`；
更完整的 `VmRSS / statm / /proc/stat` 实现在合作分支上验证过（RSS 三接口一致；
procfs 37/37、page_table 24/24 单元测试），但**不是本仓库交付的内核**，
不能顶替本仓库的读数。详见 [limitations.md](limitations.md)。

## 宿主事实

| 项 | 值 |
|---|---|
| OS | Windows 11（10.0.26200） |
| CPU | AMD Ryzen 7 5700X 8-Core Processor（16 逻辑核） |
| 内存 | 32,657 MB |
| QEMU | 11.0.92（`v11.1.0-rc2-12128-gc65ddfcd01`） |
| 加速 | 纯 TCG（无 KVM/HVF） |
| 机器 / CPU | `virt` / `cortex-a72`，4 vCPU，4096 MB |

这些字段由 `perf_run.py` 在测量时现场采集并写入报告，不是手填。

## 复现

```powershell
# 实跑 5 次（约 3–4 分钟/次，纯 TCG）
python host\perf_run.py --repeats 5 --tag pf3 --out evidence\reports\perf-report.json

# 只重建报告，不重跑 QEMU
python host\perf_run.py --reparse --tag pf3 --out evidence\reports\perf-report.json
```

> `frame_stats.py` 需要 `frame-watch.json` 与对应的 `fw-*.png`；本仓库不保存截图，首帧重算需先重跑该会话。

报告会打印 `classes with >=5 samples: 6 -> 6 class coverage`。
