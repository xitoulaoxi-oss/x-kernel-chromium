# 上游贡献与补丁分层

本仓库的补丁有两类用途，**不要混用**：

1. **重建内核**：用 `patches/x-kernel-solution.patch`，基线 `d3a6ec9`；
2. **提回上游**：用 `patches/upstream/port-to-main/`，基线是**当前 `main`**。

## 为什么不能直接提完整补丁

`x-kernel-solution.patch` 是对着赛题基线 `d3a6ec9` 写的。上游 `main` 已经比它新了 31 个提交，
42 个文件里只有 6 个新增文件还能打上，其余全部冲突。直接提这个补丁，评审无法合并。

`port-to-main/` 里的补丁是**重新生成的**：逐文件算 `diff(当前 main → 我们的改动后文件)`，
只保留"不会回退 main 已有内容"的文件。因此每个都能打在 `main` 上。

## 当前 PR 状态

截至 2026-10-19：

| PR | 分支 / 内容 | 结果 |
|---|---|---|
| Gitee **!1039** | `pr-b-drm-legacy-modeset`：legacy ADDFB、MODE_CURSOR、SET_CLIENT_CAP、DIRTYFB→ENOENT + 回归用例 | ✅ **已合入 `main`**（2026-10-18），6 文件 / +900 −9 |
| Gitee **!1050** | `pr-g-drm-set-property`：MODE_SETPROPERTY、MODE_OBJ_SETPROPERTY | ✅ **已合入 `main`**（2026-10-19），5 文件 / +496 −0 |
| Gitee **!1059** | `pr-f-gem-close-closefb`：GEM_CLOSE、MODE_CLOSEFB | ✅ **已合入 `main`**（2026-10-19），5 文件 / +725 −16 |
| Gitee !1035 | `pr-a-aarch64-sctlr-uct-uci`：EL0 读 `CTR_EL0` 不再 SIGILL | ⛔ 不计分：CI 29 项全绿，但上游告知同一问题已有两个更早 PR |
| Gitee !1049 | `pr-c-tcp-keepalive`：TCP keep-alive 三选项 | ⛔ 不计分：被 `!994` 取代（后者已合入，实现 KEEPIDLE，其余返回 `ENOPROTOOPT`） |
| Gitee !1058 | `pr-d-tmpfs-modes`：`/dev/shm`、`/tmp` → 1777 | ⛔ 不计分：测试通过（2/1 人）、代码问题 0，但上游已有重合实现，作者关闭 |

> **SCM_RIGHTS 已被上游合并**，不要再提交。当前 `main` 的 `net/knet/src/unix/stream.rs` 已有
> `deliver_peeked` / `ancillary_discarded` / `AncillaryData` 以及"Attach ancillary records BEFORE
> publishing the bytes"的注释。若这是队友提交的，团队已经拿到该项，不必重复。

## 补丁目录

| 路径 | 内容 | 基线 | 状态 |
|---|---|---|---|
| `kernel/` | **完整源码树** | `d3a6ec9` + 初赛解法 | 日常开发与构建 |
| `patches/x-kernel-solution.patch` | 初始差异，42 文件 | `d3a6ec9` | 用于审计/干净基线重建 |
| `patches/series/` | 0001–0008 历史分组补丁 | `d3a6ec9` | 只用于按主题审阅；**不含** SCM_RIGHTS / SCTLR，无法重建完整解 |
| `patches/upstream/port-to-main/` | 7 个可提 PR 的补丁 | 当前 `main` | 逐项见下 |
| `patches/upstream/fixes/` | 已推送 PR 的评审修正链 | 各 PR 分支 | **历史记录**，!1039/!1050 合并后不要再重提 |
| `patches/regression/` | 真实 fd / 真实 ioctl 的 DRM 回归用例 | — | 与 0002 配套 |

### port-to-main 逐项

| 补丁 | 内容 | 上游状态 |
|---|---|---|
| `pr-a-aarch64-sctlr-uct-uci.patch` | SCTLR_EL1.UCT/UCI | !1035 已关闭，不计分 |
| `pr-b-drm-legacy-modeset.patch` | DRM legacy modeset + 回归 | !1039 已合并 |
| `pr-c-tcp-keepalive.patch` | TCP_KEEPIDLE/INTVL/CNT | !1049 被 !994 取代 |
| `pr-d-tmpfs-modes.patch` | tmpfs 1777 | !1058 已关闭 |
| `pr-e-inotify-new-files.patch` | inotify 数据结构 | 只有 4 个新文件、未接线（无 `mod` 声明与 syscall 分发），单独提交等于死代码；需要与接线补丁一起评估 |
| `pr-f-gem-close-closefb.patch` | GEM_CLOSE / MODE_CLOSEFB | !1059 已合并 |
| `pr-g-drm-set-property.patch` | MODE_SETPROPERTY / MODE_OBJ_SETPROPERTY | !1050 已合并 |

> `pr-a` 的 UCT/UCI 结论在早期记录里被标注为"未经运行时复核"；后续 !1035 的 CI 与客机实测支持该修复，
> 但上游已有更早实现，所以它的价值是"问题被独立确认"，不是"再提一次"。

## 生成可提 PR 的分支

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File host\prepare-pr.ps1 `
  -GiteeUser <你的 Gitee 登录名>
```

脚本会：

1. 复用或克隆一个 **完整** checkout；
2. 对每个补丁做只读的 `git apply --check`；
3. 基于 `main` 建分支、应用补丁、提交；
4. 打印 push 与建 PR 的步骤。

**它不替你 push。**

### 两个必须注意的点

- **源分支要选你的 fork**（`<you>/x-kernel:pr-a-...`），目标是 `openkylin/x-kernel:main`。
  如果源分支下拉里只有官方分支，说明源选成了官方仓库自己，建不出 PR。
- **`git config user.email` 必须是 Gitee 账号已验证的邮箱**，否则提交不归属到你账号，PR 也不算你的。
- 不要用 `--filter=blob:none` 的部分克隆：`git apply` / `git push` 会按需联网取对象，网络一断就失败。

## `kernel/` 与 tag

完整源码在 [`../kernel/`](../kernel/)。根仓库用 tag 固定决赛基线（例如 `finals-baseline`、`finals-v1`），
而不是再维护一份 git bundle。

- 日常开发：直接改 `kernel/`，构建见 [building.md](building.md)；
- 回馈上游：从 `kernel/` 生成独立 diff，按上面的 `port-to-main` 流程提 PR；
- 初赛的 `first-runnable` / `final` 对应关系已写入 [history.md](history.md) 与 `docs/performance.md`。

## 修正链（历史）

`patches/upstream/fixes/README.md` 记录了 !1039 / !1050 / !1059 在评审过程中收到的修正：
ABI padding、cursor 能力、错误码、序列化、rustfmt/clippy 等。
其中 pr-b / pr-g 的补丁在合并后已成为历史，**不要重提**；保留它们是为了解释"为什么最终代码长这样"。

## 提 PR 前的检查

- [ ] 补丁能打在**当前 main**，不是只打在 `d3a6ec9`
- [ ] 一个 PR 只做一件事，标题说明症状 + 修法
- [ ] 有回归用例，且用真实 fd / 真实 ioctl
- [ ] 不包含 `Cargo.lock` 的本地 vendoring 变动
- [ ] 不重复提交已被上游合并的内容（SCM_RIGHTS、!1039、!1050、!1059）
