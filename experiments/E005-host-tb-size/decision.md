# E005 决策（tb-size 256 首轮）

## 结果

- -accel tcg,tb-size=256 的完整 smoke（E005-tb256b）通过：
  - 最终 colors=892、双窗口、Alt+Tab 正常；
  - 宿主 QEMU peak=1,448,636,416 B ≈ 1.35 GiB（<1.5G）；
  - monitor 最大 1378.8 MB；
  - CPU=323.12 s / wall 180 s。
- 对照（无 tb-size 的 E000/E002）：peak 2.31–2.36 GB，CPU 约 211 s / 180 s。

## 判断

- TCG tb-size 是宿主工作集的主要组成之一；256 MiB 能把宿主峰值压到资格线内。
- 代价：CPU 时间上升，可能影响名次分；需要 30 分钟稳定与 5 次性能确认。
- **这是 harness QEMU 参数，不是内核改动**；如果组委会固定 QEMU 参数，本机结果不能直接算决赛。必须先确认统一脚本是否允许/已经设置 tb-size。

## 下一步

- E005 stability30：带 tb-size=256 跑 30 分钟；
- 若通过，再把 xkwin 默认设为 256（保留 -TbSize 覆盖），并跑负载循环/性能。
