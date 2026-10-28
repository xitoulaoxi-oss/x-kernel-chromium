# E000 决策

## 第一次尝试（run/）

- 结果：失败。
- 现象：QEMU 报 Could not open 'github\artifacts\kernel-procfs.bin'，QEMU 在串口端口打开前退出。
- 根因：仓库路径 for github 含空格；QEMU/Windows 对 -kernel 路径的空格处理不可靠。
- 处理：host/xkwin.ps1 在路径含空格时复制 kernel 到 TEMP 的无空格路径，再启动 QEMU。

## 第二次尝试（run2/）

- 待测。

## 第二次尝试（run2/）

- 结果：失败。
- 现象：QEMU 启动成功，但 upload server 退出：
  server.py: error: unrecognized arguments: github\\experiments\\E000-baseline\\run2\\stage
- 根因：同样来自路径空格，Start-Process 把 python http.server 的 --directory 参数拆开。
- 处理：host/xkwin.ps1 在 staging 路径含空格时，复制到 TEMP 的无空格目录再启动 HTTP server。

## 第三次尝试（run3/）

- 待测（job pwsh-0274750a0ba74a70）。

## 第三次尝试（run3/）

- 结果：**通过**。
- 读数：最终 zz-final 1280x800 colors=892 dominant=0.321 blank=False；
  _NET_CLIENT_LIST = 0x400009, 0x400003；两次 Alt+Tab 后 active 与 stacking 双向翻转；
  chrome=15；键盘输入被 libinput 识别。
- 内核：build_id f8beec3c…，git_commit 5081473，git_dirty=true。
- 宿主 QEMU：peak_ws=2,308,759,552 B（约 2.15 GiB），cpu=211.95 s。
- **注意：峰值内存高于决赛资格线 1.5G，E003/E004 必须处理**；这不是构建失败，是性能/资源问题。
- harness 修复：kernel 路径含空格时复制到 TEMP；staging 路径含空格时复制到 TEMP。
