# evidence/

每一次真实运行的原始产物。**文档里的读数都能在这里找到对应文件。**

```text
evidence/
├── sessions/     单次会话（功能、稳定性、侦察）
├── perf/         性能批次（每轮一个目录，含日志与指标）
└── reports/      汇总 JSON、旧口径归档、上游 CI 记录
```

## 会话目录里有什么

| 文件 | 含义 |
|---|---|
| `console.log` | 串口全量日志；读数主要在这里 |
| `NN-after-*.stats.json` | 该帧的 `colors` / `dominant_fraction` / `blank`（PNG 不随仓库发布） |
| `frame-watch.json` | 帧观测序列与首帧判定的原始输入 |
| `qemu-metrics.json` | 宿主 QEMU 的峰值工作集、CPU 时间与分母 |
| `qemu-cmd.txt` | 完整 QEMU 命令行（含实际内核路径） |
| `run-*.txt` | 各客机脚本的控制台输出 |
| `README.md` | 少数会话的专项说明 |

> **截图成功 ≠ 画面有内容。** 验收时看 screendump 与 `.stats.json`，尤其 `blank` 与主导色占比；
> 仓库只保留统计 JSON，不保存 PNG。首帧判定用 `frame-watch.json` 的饱和度，不用单一色数。

## 功能会话

| 目录 | 证明了什么 |
|---|---|
| `SCM-20261015T140943Z` | SCM_RIGHTS 生效 → 窗口首次出现（`colors=336`，此前全是 `colors=1`） |
| `SIGILL-20261015T141526Z` | UCT/UCI 生效 → 崩溃页消失（`colors=421`，进入 ERR_FILE_NOT_FOUND） |
| `RENDER-20261015T141742Z` | 组委会页面首次完整渲染（`colors=835`，三页 sha256 在客机内全对） |
| `STAB10-20261015T142007Z` | 单窗口连续 600 秒，10 次采样全绿 |
| `R37-RENDER-20261016T093412Z` | 渲染复现（同一读数 `835 / 0.2951`） |
| `R37-MW4-20261016T101127Z` | ★ 两窗口 + Alt+Tab 双向读数；`sockopt rejected=0` |
| `R37-PROC4-20261016T104040Z` | 进程树：zygote 之下的 fork 子进程（renderer 判据） |
| `R38-STAB10B-20261016T105334Z` | `kernel-keepalive.bin` 双窗口 600 秒全绿 |
| `R38-REC-20261016T110627Z` | 27 帧演示素材 + procfs 字段取证（`Threads/VmSize/PPid`）+ 键盘链路 |
| `chromium-gui-20261016T131345Z` | tmpfs `statfs` 报真实容量（`2086512 32352 2054160 2%`） |
| `chromium-gui-20261016T141245Z` | `/dev/shm`、`/tmp` 权限 `drwxrwxrwt` |
| `LAYOUT-20261019T021243Z` | `layout.html` 渲染 `colors=691`、`blank=False` |
| `PROC-CHECK-20261019T052522Z` | 交付内核 `/proc` 只到 `State/PPid/Threads/VmSize` + `stat.vsize` |
| `AF6B-20261019T054919Z` | `AF_INET6` 返回 `EAFNOSUPPORT`，IPv4 回环正常 |
| `STAB10P-20261019T062937Z` | ★ 推荐内核双窗口 600 秒，11 帧全部 `colors=835`；`x=1 j=1 c=11` |
| `INTER7-20261019T064147Z` | `interaction.html` 渲染 `colors=886` |
| `SELF-TEST-2026-10-16` | 只用仓库内文件跑出的自证（`colors=892`） |

## 性能批次

| 目录 | 口径 | 说明 |
|---|---|---|
| `perf/base1…base5-*` | 旧口径 | `kernel-keepalive.bin`；before 基线 |
| `perf/aft1…aft5-*` | 旧口径 | `kernel-procfs.bin`；after |
| `perf/pf31…pf35-*` | **新口径** | 首帧来自 screendump、renderer 1 Hz、宿主 CPU/内存率；8 次运行 |
| `sessions/pf21…pf25-*` | 旧口径 | `paint_s` 时代的功能/性能混合样本，仅作历史 |

指标定义与统计见 [`../docs/performance.md`](../docs/performance.md)。

## 汇总报告

| 文件 | 内容 |
|---|---|
| `reports/perf-report.json` | 新口径 6 类指标 × 8 次、中位数/极差/CV、宿主信息 |
| `reports/perf-report-before.json` | before 批次（旧口径） |
| `reports/perf-report-after.json` | after 批次（旧口径） |
| `reports/perf-before-after.json` | before/after 量化对照 |
| `reports/archive/perf-report-v1-proxy.json` | 更早的 `paint_s` 代理口径，保留以便对照 |
| `reports/upstream-ci/keepalive-in-guest.txt` | 交付内核 TCP keep-alive 的客机回读记录 |

## 内核与路径

早期会话的 `qemu-cmd.txt` 里可能写 `artifacts/kernel-scmrights.bin`——
那是当年工作区的路径，对应本仓库 [`../artifacts/kernel-scmrights.bin`](../artifacts/kernel-scmrights.bin)
（与 `kernel-procfs.bin` 内容相同）。完整对照见 [`../artifacts/README.md`](../artifacts/README.md)。

## 原则

- **不删失败轮次**：页面没画出来就记 `not found`，不重跑到好看为止；
- **不做二次加工**：`.stats.json` 是当场统计；截图不随仓库发布；
- **不收录视频与截图**：验收时由 harness 生成 screendump，仓库只保留 console 与 JSON。
