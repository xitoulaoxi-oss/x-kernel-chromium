# 交付内核的 IPv6 支持实测（2026-10-19）

用于确认"`AF_INET6` 返回 `EAFNOSUPPORT`"这条结论是否仍然成立——**此前仓库内没有任何日志提到它**，
所以这次直接测。

| 探测 | 输出 | 判定 |
|---|---|---|
| `ls /proc/net` | 无 `if_inet6` | 内核未注册 IPv6 |
| `cat /proc/net/if_inet6` | `can't open ...: No such file or directory` | 同上 |
| `ping -6 -c1 -W1 ::1` | `ping: can't create raw socket: **Address family not supported by protocol**` | **`EAFNOSUPPORT`** |
| `ping -c1 -W1 127.0.0.1` | `--- 127.0.0.1 ping statistics ---`（正常） | IPv4 路径可用 |

结论：**`AF_INET6` 确未实现**，返回 `EAFNOSUPPORT`；IPv4 回环正常。本会话不验证外网访问。
这与 Chromium 日志里的 97 号错误（`EAFNOSUPPORT`）一致。

源码侧佐证：交付内核基于 `d3a6ec9`，其 `posix/net/src/socket.rs` 不含 `AF_INET6` 分支；
较新的上游（`upstream-main`，`8fd7a45`）已在该文件出现 `AF_INET6`，说明这是"上游后来补上的能力"，
不是我们改动造成的。

## 复现

```powershell
cd <repo>
powershell -NoProfile -ExecutionPolicy Bypass -File host\xkwin.ps1 `
  -Kernel artifacts\kernel-procfs.bin `
  -Command 'ls /proc/net; cat /proc/net/if_inet6 2>&1; ping -6 -c1 -W1 ::1 2>&1; ping -c1 -W1 127.0.0.1 2>&1' `
  -Tag AF6B -CommandTimeoutSec 300
```
