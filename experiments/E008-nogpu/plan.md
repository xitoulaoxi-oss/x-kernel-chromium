# E008 软件合成首帧稳定性

## 假设

标准 x4 的随机 blank（5 次只有 2 次首帧）来自 llvmpipe/ANGLE 的 GL 合成竞态，不是等待不足。

## 变体

guest/x4-win1-nogpu.sh：

~~~text
--disable-gpu --disable-gpu-compositing
~~~

其余 profile、URL、Xorg/JWM 不变。

## 单次 smoke（2026-10-29 21:25）

- first_frame_s=70.064（bracket 60.042..70.064）
- colors=835，final=835
- QEMU peak 2.12GB

## 5 次

E008-nogpu5/run1..5，10s/300s frame watch；运行中。

## 判据

- 5/5 找到首帧；
- 与 e003d 的 5 类报告分开记录：startup/renderer 来自 e003d，page-load 来自本组；
- 不把两组数据说成同一次 6 类运行。
