# 交付内核的 `/proc` 能力实测（2026-10-19）

> 原始测量记录，未改写。边界说明见 [`../../../docs/limitations.md`](../../../docs/limitations.md)，证据索引见 [`../../README.md`](../../README.md)。


一次针对性探测，用途是确认**本仓库交付的内核**到底提供哪些 `/proc` 字段。结论与本仓库
`patches/x-kernel-solution.patch` 的 `procfs/docs/design.md` 一致：

| 接口 | 交付内核现状 | 实测输出 |
|---|---|---|
| `/proc/<pid>/status` 的 `State` / `PPid` / `Threads` / `VmSize` | ✅ 有 | `VmSize: 2104 kB`、`Threads: 1` |
| `/proc/<pid>/stat` 的 `vsize`（字段 23） | ✅ 有 | `vsize=2162688`（= 2104 kB，与 status 一致） |
| `/proc/<pid>/status` 的 **`VmRSS`** | ❌ **没有这一行** | — |
| `/proc/<pid>/stat` 的 `rss`（字段 24） | ❌ 恒 0 | `rss=0` |
| `/proc/<pid>/statm` | ❌ 未实现 | — |
| `/proc/stat`、`/proc/uptime`、`/proc/loadavg` | ❌ 未实现 | — |

## 为什么不做成 0 而是缺失

补丁的 `procfs/docs/design.md` 写明了取舍：

> `VmRSS` is absent rather than zero-filled because the MM keeps no resident-page
> accounting … a fabricated number here is indistinguishable from a measured one for
> every reader downstream.

即：**没有驻留页计数就宁可缺字段，也不填 0** —— 填 0 会让 `ps`/`top` 报出"RSS=0"，
读者无法分辨"没实现"和"真的是 0"。这也正是此前一轮把 `peak_rss_kb=0` 当成结果的原因。

## 与合作分支的关系（重要）

同一时刻由组员在**另一条分支**上完成了更完整的 procfs 实现（`VmRSS`、`statm`、
`/proc/stat`、`/proc/uptime`、`loadavg`、稀疏页表遍历），并在独立 QEMU 上做了
RSS 三接口一致性对照（64 MiB 逐页写入 → 65636 KiB，三接口读数一致）与
procfs 37/37、page_table 24/24 单元测试。

**那些读数属于该分支的构建**（`build_id b672434f…` / `bfec558f…`），**不是**本仓库
交付的 `artifacts/kernel-procfs.bin`（`build_id 815e69c2…`）。两者不能互相顶替：
本仓库内的任何 `/proc` 相关结论只以本目录的实测输出为准。

合作分支的完整报告未随本仓库发布；本目录只保留交付内核的实测输出。

## 复现

```powershell
cd <repo>
powershell -NoProfile -ExecutionPolicy Bypass -File host\xkwin.ps1 `
  -Kernel artifacts\kernel-procfs.bin `
  -Script "guest\v1-verify-procfs.sh" `
  -Command "sh /tmp/xk-v1-verify-procfs.sh go" `
  -Tag PROC-CHECK -CommandTimeoutSec 300
```
