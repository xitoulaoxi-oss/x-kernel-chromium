# E005 宿主 QEMU 工作集：TCG tb-size 诊断

## 背景

E002 在 guest used 816 MB 的情况下，宿主 QEMU 峰值仍有 2.36 GB。差值可能主要来自：

- QEMU TCG 翻译块缓存（默认值随 guest RAM 变化）；
- guest page cache / QEMU 映射页；
- QEMU 自身堆、virtio、VNC 等。

用户已明确：**先按宿主 QEMU 工作集做 1.5G 资格线**。

## 方法

给 xkwin 加实验参数 -TbSize（MiB），只改 QEMU 的 -accel 参数：

~~~text
-accel tcg,tb-size=256
~~~

其余命令、镜像、脚本、-snapshot 不变。用 host/monitor-qemu.ps1 采样宿主工作集，比较峰值。

## 变体

| 变体 | tb-size | 目的 |
|---|---:|---|
| E005a | 256 | 先看是否能显著降低 |
| E005b | 512 | 折中 |
| E005c | 128 | 下界/功能 |

## 判据

- 功能：双窗口、colors=892；
- 内存：宿主 QEMU peak；
- 若 256 能降到 1.5G 附近，再判断组委会统一 QEMU 是否允许该参数；**不能把只在本机 harness 生效的参数当成决赛成绩**。

## 注意

这是诊断实验，不等于已提交的跨层优化。
