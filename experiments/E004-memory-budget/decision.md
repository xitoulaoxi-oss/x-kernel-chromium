# E004 决策（combined 第一轮）

## 结果

- 功能：通过。最终 colors=892，窗口 0x400009/0x400003，Alt+Tab 正常。
- 宿主 QEMU：peak_ws=2,262,237,184 B ≈ 2.11 GiB（基线 E002 为 2.36 GB，约降 97 MB）。
- 客机 free：used=753 MB，buff/cache=213 MB，available=3332 MB（基线 E002 used=816 MB，约降 63 MB）。
- monitor：19 个样本，最后 ws≈2157 MB；3 分钟太短，不能判断泄漏。

## 判断

- 如果 1.5G 是**客机 used** 口径：753 MB 已通过资格线。
- 如果 1.5G 是**宿主 QEMU 工作集**口径：2.11 GiB 仍超，需要更激进的路径；低内存 flags 的 97 MB 不足。
- 口径尚未由组委会脚本固定；E003 性能报告必须同时记录 host peak 与 guest free，不能混用。

## 待办

- disk-only / flags-only 单变量对比（3 分钟 smoke）；
- 若 host 口径必须过线，考虑 TCG/页缓存/更激进启动参数，并先确认是否合规。
