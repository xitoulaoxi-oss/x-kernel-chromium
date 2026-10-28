# 观测工具：崩溃 / 卡死 / 泄漏

这套工具只读 harness 产物，不启动 QEMU；它把一次会话的 console、截图统计、QEMU 指标和内存采样汇总成一份 JSON。

## 组成

| 工具 | 作用 |
|---|---|
| `host/observe.py` | 分析一个会话目录，输出 crash / hang / leak 判断 |
| `host/monitor-qemu.ps1` | 在 QEMU 运行期间每 15 s 记录 QEMU 工作集、CPU、线程数到 `observe.jsonl` |
| `guest/hb.sh` | 客机每分钟打印 `HB t=... chrome=... mem_mb=...` |
| `guest/hb-start.sh` | 在客机后台启动心跳 |
| `guest/hb-dump.sh` | 打印心跳历史，供 console 解析 |

## 用法

1. 在跑会话前另开一个 PowerShell 后台任务启动 monitor：

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File host\monitor-qemu.ps1 -OutDir "experiments\E002-stability30\run" -IntervalSec 15 -Minutes 35
~~~

2. 在客机脚本序列里先执行 `hb-start.sh`，结束前执行 `hb-dump.sh`：

~~~text
guest/06-fetch-pages.sh
guest/x1-input.sh
guest/x2-xorg.sh
guest/y3-jwm-stock.sh
guest/x4-win1.sh
guest/x5c-win2.sh
guest/hb-start.sh
...
guest/hb-dump.sh
~~~

3. 会话结束后分析：

~~~powershell
python host\observe.py experiments\E002-stability30\run `
  --expected-minutes 30 `
  --out experiments\E002-stability30\run\observe.json
~~~

## 判据

| 类型 | 判据 |
|---|---|
| 崩溃 | console 命中 panic / SIGSEGV / SIGILL / SIGABRT / Aw Snap / OOM / QEMU fatal，或 harness-error.txt 非空 |
| 卡死 | 没有最终截图统计、最终帧 blank、最终颜色数 <300、心跳数明显少于预期、最后一次心跳 chrome=0 |
| 泄漏 | monitor 至少 3 个样本；末值−初值 ≥ 256 MB 且线性斜率 ≥ 2 MB/min |

阈值可以用 `--leak-mb`、`--leak-slope` 调整。**没有足够样本时输出 `insufficient_data`，不要当成“没有泄漏”。**

## 判读原则

- 崩溃和卡死以**会话目录里的原始文件**为准，不以对话描述为准。
- 1.5G 峰值内存资格线看 `qemu_metrics.peak_working_set_b`，并对照 `observe.jsonl` 的趋势。
- 截图文件不随仓库发布；`.stats.json` 和 console 保留。
