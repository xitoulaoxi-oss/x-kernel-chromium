# E004 峰值内存压到 1.5G 的实验

## 已知事实

- E000（新构建、双窗口、完整三页）宿主 QEMU 峰值 2,308,759,552 B ≈ 2.15 GiB。
- 决赛性能资格线：页面加载完成且峰值内存不超过 1.5G。
- 需要先确认组委会测的是 QEMU 进程工作集、客机 used，还是 Chromium 进程 RSS；E003 报告会同时记录宿主 peak 与客机 free。

## 单独变量

一次只改一个变量，每个变体跑 5 分钟 smoke + monitor；有明显改善再做 30 分钟稳定。

| 变体 | 改动 | 预期 |
|---|---|---|
| E004a | profile 从 /tmp（tmpfs）移到 /root（磁盘镜像） | 减少 tmpfs 占用，可能有 I/O 代价 |
| E004b | --renderer-process-limit=1 + --process-per-site | 减少 renderer 进程数 |
| E004c | --disk-cache-size=1 + --media-cache-size=1 | 减少缓存 |
| E004d | --js-flags=--max-old-space-size=128 | 限制 JS 堆 |
| 组合 | 上述全部 | 可能压到 1.5G 以下，但可能影响渲染/速度 |

已写入：

- guest/x4-win1-lowmem.sh（E004a+b+c+d 组合）
- guest/x5c-win2-lowmem.sh

## 判据

- 功能：双窗口、三页、Alt+Tab 不回归；
- 内存：monitor 的 peak/趋势与 qemu-metrics 的 peak；
- 性能：首帧/页面加载不出现明显回退（5 次中位数）；
- 稳定性：30 分钟无退出、无 OOM。

## 注意

- 1.5G 若指客机 used，优化方向与 QEMU 工作集不同；不要用错口径。
- 不要用 --single-process 换内存：会破坏多进程评分。

## E002 早期观测（2026-10-29 01:06）

- QEMU 工作集在会话约 3 分钟时已达 2.15 GiB，尚未到 30 分钟；
- 说明 2.3 GiB 不是只出现在最后，低内存优化必须在窗口稳定后就生效；
- 客机 HB 的 mem_mb 仍待 s10 开始后读取。

已提供 tests/lowmem-smoke.ps1。
