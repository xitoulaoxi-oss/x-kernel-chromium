# E000 新构建内核最小启动验收

## 目标

确认 artifacts/kernel-procfs.bin（c915565…）能启动 Xorg/JWM/Chromium、显示三页、出现两个窗口并可用 Alt+Tab 切换。

## 命令

从仓库根目录运行，镜像使用交付镜像的 -snapshot：

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File host\xkwin.ps1 -Tag E000b -Disk "D:\x-kernel-dsh-bridge\delivered\agentos-disk.img" -Kernel artifacts\kernel-procfs.bin -ServeManifest guest\serve-pages.txt -Script "guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x4-win1.sh;guest\y6-evidence.sh;guest\x5c-win2.sh" -Key "cmd=sh /tmp/xk-y6-evidence.sh;alt+tab@8;cmd=sh /tmp/xk-y6-evidence.sh;alt+tab@8;cmd=sh /tmp/xk-y6-evidence.sh" -CommandTimeoutSec 300 -BootTimeoutSec 420 -AfterScriptWait 20 -OutDir "experiments\E000-baseline\run2"
~~~

> host/xkwin.ps1 现会把含空格的 -kernel 复制到 TEMP 后再交给 QEMU。

## 通过判据

- P1 ok=3 bad=0
- _NET_CLIENT_LIST 两个 id
- 两次 Alt+Tab 后 _NET_ACTIVE_WINDOW 与 STACKING 双向翻转
- 最终 screendump 非空白，颜色数量级正常

## 记录

- run/console.log
- run/qemu-cmd.txt
- run/*.stats.json
- decision.md
