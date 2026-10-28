# E002 30 分钟稳定性 + 负载循环

## 目标

证明交付内核在双窗口下连续 30 分钟无退出，并记录 QEMU 内存趋势；通过后再做 10 次负载循环。

## 30 分钟稳定性命令

先在后台启动 monitor：

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File host\monitor-qemu.ps1 -OutDir "experiments\E002-stability30\run" -IntervalSec 15 -Minutes 36
~~~

再运行会话（s10 脚本自身运行 30 分钟）：

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File host\xkwin.ps1 -Tag E002 -Disk "D:\x-kernel-dsh-bridge\delivered\agentos-disk.img" -Kernel artifacts\kernel-procfs.bin -ServeManifest guest\serve-pages.txt -Script "guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x4-win1.sh;guest\x5c-win2.sh;guest\s10-stability30.sh" -CommandTimeoutSec 2000 -BootTimeoutSec 420 -AfterScriptWait 20 -OutDir "experiments\E002-stability30\run"
~~~

## 通过判据

- 30 个 HB 行，chrome > 0，Xorg/JWM 存活；
- 最终 screendump 非空白；
- monitor 至少 3 个样本；若内存增长超过阈值，记为 leak 风险；
- 记录 peak_ws，注意 1.5G 资格线。

## 负载循环（30 分钟稳定通过后）

已提供 tests/load-loop.ps1（默认 10 次 × 120 s），可单独启动 monitor 采样。


- 每 2 分钟加载一次测试页，共 10 次；
- 由宿主的 -Key ctrl+r 或新增 l1 脚本完成；
- 记录每次加载后的窗口数与 chromium 进程数。
