# E010 决策（关闭后台网络）

## 变体

x4-win1-quiet：在原 flags 上增加：

- --disable-background-networking
- --disable-component-update
- --disable-sync
- --no-first-run / --no-default-browser-check
- --disable-domain-reliability / --metrics-recording-only / --disable-breakpad

## 结果

- 单次 frame watch 30 帧，found=false；final colors=261；
- Chromium 日志仍有大量 CreatePlatformSocket/SSL 错误，但页面仍未绘制；
- 关闭后台网络不解决 blank。

## 结论

- 随机 blank 不是后台网络/更新请求导致；
- 也不是 GL/llvmpipe（E008 0/5）、等待不足（x4 150s 仍 blank）；
- 仍是未定位的 Chromium/Xorg/DRM 绘制问题。
