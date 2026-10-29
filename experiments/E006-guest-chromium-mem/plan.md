# E006 客机 Chromium 内存（1.5G 资格线）

## 口径

用户 2026-10-29 18:50 澄清：1.5G 指**客机内 Chromium 使用的内存**，不是宿主 QEMU 工作集。

## 方法

标准 E002 流程（06 → x1 → x2 → y3 → x4 → x5c），最后运行：

~~~text
guest/chrome-mem.sh
~~~

脚本从每个 Chromium 进程的 /proc/<pid>/statm 读取 resident pages，乘 4 KiB 求和。RSS 求和是保守上界（共享页会重复计），不是 PSS。

## 判据

- 功能：colors=892、双窗口；
- Chromium RSS 总量 <= 1.5G；
- 记录 procs、total_kb、total_mb 和每个进程明细；
- 如需优化，再对 x4/x5c 做单变量（profile、renderer 限制、cache）。

## 备注

E005 的宿主 tb-size=256 结果只作诊断，不作为本口径的证据；xkwin 默认已恢复 QEMU 默认 tcg。
