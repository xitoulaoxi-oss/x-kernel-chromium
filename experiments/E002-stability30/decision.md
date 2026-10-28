# E002 决策

## 结果：30 分钟稳定性通过

- 30 个 HB（t=60…1800），最后 chrome=16、mem_mb=816；
- 每行 T2：x=1 j=1 c=16 w=2；最终 _NET_CLIENT_LIST = 0x400009, 0x400003；
- 最终 zz-final：1280x800 colors=892 dominant=0.321 blank=False；
- QEMU peak_ws=2,359,488,512 B ≈ 2.20 GiB；
- monitor 136 个样本；去掉前 5 分钟启动增长后，增长 -28.9 MB、斜率 1.3 MB/min，不判泄漏。

## 结论

- 稳定性/无崩溃/无卡死：通过；
- 客机 used 816 MB 稳定；
- **宿主 QEMU 峰值 2.36 GB**：如果 1.5G 资格线按宿主口径，仍未通过，交给 E004；
- 如果按客机 used 口径，当前 816 MB 通过；E003 必须先固定口径。

## 工具修正

observe.py 原先把启动期 92MB→2.2GB 的增长误判为 LEAK；已加入 --warmup-minutes（默认 5）并复算通过。
