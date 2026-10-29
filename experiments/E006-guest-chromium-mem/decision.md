# E006 客机 Chromium 内存（1.5G 资格线）

## 口径

用户 2026-10-29 18:50 澄清：1.5G 指**客机内 Chromium 使用的内存**，不是宿主 QEMU 工作集。

## 证据

- E002 30 分钟：guest used=816 MB；10 次负载循环后仍持平；
- E005 30 分钟：guest used=840 MB；
- E006 标准双窗口：最终 colors=892，guest used 与 E002 同量级；
- 客机 free used 已包含 Chromium、Xorg、JWM、内核；所以 816–840 MB 是 Chromium 内存的保守上界，低于 1.5G。

## 未完成

guest/chrome-mem.sh 能列出 16 个 Chromium PID，但本内核的 /proc/<pid>/statm 与 status VmRSS 都返回 0，无法得到 per-process RSS/PSS；**不能引用 0，也不能伪造**。只有 guest free used 上界可用。

## 结论

- 按“客机内 Chromium 内存”口径，当前 816–840 MB 低于 1.5G，资格线可通过（保守上界）。
- E005 宿主 tb-size=256 仅诊断，不是本口径优化；xkwin 默认已恢复 QEMU 默认 tcg。
