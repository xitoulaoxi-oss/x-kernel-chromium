# upstream/fixes/ —— 已推送 PR 的评审修正链

> **历史记录（PR 评审修正链，截至 2026-10-19）。** !1039 / !1050 / !1059 合并后，本目录只用于解释"最终代码为什么长这样"；**不要重提**。当前状态见 [`../../../docs/upstream.md`](../../../docs/upstream.md)。


这些补丁**不是**独立 PR，`host/prepare-pr.ps1` 不会读这个目录（它只扫 `patches/upstream/port-to-main/*.patch`）。
它们用于在对应 PR 分支已经推送之后，追加修正再 amend 进原提交。

---

## pr-b-rustfmt-fix.patch

**为什么存在**：PR `!1039` 第一次跑 CI 时 `Check: Rustfmt` 失败（Jenkins #2392）。rustfmt 报 4 处：

| 位置 | 问题 | 修法 |
|---|---|---|
| `card0.rs` `SET_CLIENT_CAP` 分支 | 三个 `DRM_CLIENT_CAP_*` 拆成 3 行 | 合成一行（正好 100 列） |
| `card0.rs` `MODE_CURSOR` handler | `dev.set_cursor(...)` 5 参数挤一行 | 一参数一行 |
| 同上（第二处） | 同上 | 同上 |
| `card0.rs` `impl` 签名 | `) -> VfsResult<usize> {` 与 `if` **挤在同一行** | 拆成两行 |

最后一条是**真实缺陷**（补丁生成时行尾粘连），不是风格偏好。

---

## pr-b-review-p0p6.patch

**为什么存在**：上游 AI review（`x-cibot`，24 项）指出的缺陷，逐条对应见下表。
**必须用这个补丁取代「按 review 建议直接把测试常量改成 0xc018_64a3」** —— 那条建议是错的。

### P0（致命）：`MODE_CURSOR` 结构体布局错，cursor 路径对真实客户端不可达

| | 修前 | Linux uapi | 修后 |
|---|---|---|---|
| `drm_mode_cursor` | 6×u32 = 24 B，`pad` 占位 | **7×u32 = 28 B**（`width`,`height` 在 `y` 与 `handle` 之间） | 7×u32 = 28 B |
| `drm_mode_cursor2` | 8×u32 = 32 B | **9×u32 = 36 B** | 9×u32 = 36 B |
| 注册命令字 | `0xc01864a3` / `0xc02064bb` | **`0xc01c64a3` / `0xc02464bb`** | 与 uapi 一致 |

修前分发是整值精确匹配，真实客户端发 `0xc01c64a3` → 永不命中 → 仍回 EOPNOTSUPP；
即便命中，`handle` 也会从偏移 16（应为 24）读出垃圾值。**即该 PR 的招牌功能实际未生效。**

### 其余

| 项 | 问题 | 修法 |
|---|---|---|
| **P1** | `SET_CLIENT_CAP` 测试常量写成 `_IOWR`（`0xc010640d`），驱动注册的是 `_IOW`（`0x4010640d`）→ 测试打不到 handler，"未知能力→EOPNOTSUPP" 断言因命令未注册而**假通过** | 常量改为 `0x4010640d` |
| **P2** | cursor 用例用 `crtc_id = 0`，驱动要求 `0x10` → 修好编号后仍 EINVAL 失败 | 用例改用 `CRTC_ID`，并补 MOVE / BO（含 `handle=0` 隐藏）/ 未知 CRTC 四个分支 |
| **P4** | `client_caps` 只写不读，注释声称的"可观察效果"不成立 | `MODE_ATOMIC` 在未协商 `DRM_CLIENT_CAP_ATOMIC` 时返回 EOPNOTSUPP —— 位图有了消费点，同时正面回应 IK946N 第 4 条（要求客户端回落 legacy） |
| **P5** | legacy `ADDFB` 接受 `depth` 1..=32 却固定登记 XRGB8888 | 收窄为 `depth ∈ {24, 32}` |
| **P6** | `#[allow(dead_code)]` 违反 CG-024 | 删除该未使用函数，并移除随之无用的 `c_void` 导入 |

---

## pr-b-review-clippy-args.patch

**为什么存在**：Jenkins #2399 在 `Build Artifact: kplat-x86_64` 失败：

```
error: this function has too many arguments (8/7)
  --> io/drmdevice/src/card0.rs:1479:5
   = note: `-D clippy::too-many-arguments` implied by `-D warnings`
```

P0 给 `set_cursor` 加了 `width`/`height`，参数变成 8 个，撞上 clippy 默认阈值 7，
而工作区是 `-D warnings`。

**没有用 `#[expect(clippy::too_many_arguments)]` 绕**：CG-024 限制 lint 例外，
而这个 PR 已经因为一处 `#[allow(dead_code)]` 被记过一笔，再添一个正好撞在枪口上。

改法是把参数收进 `CursorRequest`：`set_cursor(&self, request: CursorRequest)`，
2 个参数。两个 handler（`MODE_CURSOR` / `MODE_CURSOR2`）只差 hotspot，现在都构造同一个请求。

**位置 `x`/`y` 刻意不进结构体**：驱动没有光标平面，MOVE 被接受但无效果（原来就是
`_x`/`_y` 忽略），而一个从不被读取的字段在 `-D warnings` 下会触发 `dead_code`。
结构体 5 个字段（`crtc_id`/`flags`/`width`/`height`/`handle`）全部有读取点。

---

## pr-b-review-cursor-capability.patch

**为什么存在**：`c79a3b8d` 上的 AI review 报了 3 项，其中一项是**真实的行为回归**。

### ① 指针会消失（真回归）

> 新增的 `set_cursor()` 对 MODE_CURSOR/CURSOR2 一律返回 `Ok(0)`，既不记录位置也不安装图像，
> 但 `GET_CAP` 仍对外宣告 64x64 光标能力。客户端读到非 0 光标尺寸并安装成功后，会认为
> 硬件光标可用而不再自绘指针，**实际指针不会显示**。

打补丁前：MODE_CURSOR 返回 EOPNOTSUPP → Xorg 用软件光标 → 指针可见。
打补丁后：BO 返回成功 → Xorg 装硬件光标 → 什么都没有 → **指针没了**。

**修法**：把「合法图像」的 BO 请求改回 `EOPNOTSUPP`（即补丁前那条路径的答案，也是被验证过能显示
指针的配置），MOVE 仍返回成功（避免 init 中止），**格式错误的请求仍是 EINVAL**。
这样既没有假装硬件光标，也没有让初始化失败。

### ② 测试里的假通过

`mode.rs` 用 `let _ =` 丢弃了 ADDFB2(ARGB8888) 的返回值 —— 无论成功、EOPNOTSUPP 还是布局漂移，
用例都会通过。改成显式断言「成功 + fb_id 非 0」，并补 `RMFB` 释放，避免污染后续用例。

### ③ `client_caps` 还剩一个没人读的位

`DRM_CLIENT_CAP_UNIVERSAL_PLANES` 被接受并置位，但没有代码读它。**不改行为**（客户端会读
setter 的返回值，拒绝反而可能让它放弃），只把字段文档和 `SET_CLIENT_CAP` 的注释收窄到事实：
只有 `ATOMIC` 被 `DrmModeAtomic` 消费，其余是记录而非生效。

验证：`set_cursor` 的四种结局齐全、5 个 `CursorRequest` 字段全部有读取点（否则 `-D warnings`
会因 `dead_code` 失败）、测试 5 项断言到位、新增行 ≤100 列。

---

## pr-b-review-p3-move-test.patch

**为什么存在**：`io/drmdevice` 是 workspace 成员，`<crate>/tests/*.rs` 会被 Cargo 自动注册为
**宿主集成测试 target**，必须能在裸 Cargo 下编译（`make check_host_tests`）—— 但该用例需要真实
`/dev/dri/card0` 且仅限 Linux 64 位。仓库既有约定是放独立包。

迁移结果（根 `Cargo.toml` 已 `exclude` `"io/drmdevice/abi-tests/*"`，无需改动）：

```
io/drmdevice/tests/mode.rs
  → io/drmdevice/abi-tests/drm-mode/mode.rs     （内容逐字节一致）
  + io/drmdevice/abi-tests/drm-mode/Cargo.toml  （[workspace] 独立 + [lib] path）
  + io/drmdevice/abi-tests/drm-mode/README.md   （构建/运行/设备占用说明）
```

**依赖顺序**：P3 的删除段落匹配的是 **P0–P6 之后**的文件内容，所以两个补丁必须按序应用。

---

## 应用方式（顺序不能反）

```powershell
cd C:\Users\a\x-kernel-pr
git checkout pr-b-drm-legacy-modeset
git apply <repo>\patches\upstream\fixes\pr-b-review-p0p6.patch
git apply <repo>\patches\upstream\fixes\pr-b-review-p3-move-test.patch
git add -A
git commit --amend --no-edit
git push --force-with-lease fork pr-b-drm-legacy-modeset:pr-b-drm-legacy-modeset
```

**如果 p0p6 与 p3 已经应用并推送过**（`835a62f6` 即如此），只需补 clippy 那一个：

```powershell
cd C:\Users\a\x-kernel-pr
git apply <repo>\patches\upstream\fixes\pr-b-review-clippy-args.patch
git add -A
git commit --amend --no-edit
git push --force-with-lease fork pr-b-drm-legacy-modeset:pr-b-drm-legacy-modeset
```

**当前进度（HEAD `ae3607e7`）**：`p0p6`、`p3-move`、`clippy-args` **均已应用并推送**，
`clippy-args` 的 `--check` 会失败属正常（内容已存在）。只剩一个要打：

```powershell
cd C:\Users\a\x-kernel-pr
git apply <repo>\patches\upstream\fixes\pr-b-review-cursor-capability.patch
git add -A
git commit --amend --no-edit
git push --force-with-lease fork pr-b-drm-legacy-modeset:pr-b-drm-legacy-modeset
```

> `port-to-main/pr-b-drm-legacy-modeset.patch` 仍是**首次推送时**的版本（含上述全部问题）。
> 从零重建该分支时，须依次应用：`pr-b-drm-legacy-modeset.patch` → `pr-b-rustfmt-fix.patch`
> → `pr-b-review-p0p6.patch` → `pr-b-review-clippy-args.patch` → `pr-b-review-p3-move-test.patch`。
> （`pr-b-review-clippy-args.patch` 只改 `card0.rs`，`p3` 只动测试文件，两者互不影响，顺序可互换。）

---

## pr-g-review-abi-pad-and-test.patch

**为什么存在**：PR `!1050`（head `e42b06c1`）的 x-cibot 复审（2026-10-18 11:08，`<!-- x-review:summary -->`）
结论是**需继续修改**，扣掉已修正的 3 条与判定不再适用的 1 条后只剩两条，本补丁逐条对应：

| # | 位置 | 问题 | 修法 |
|---|---|---|---|
| 1 | `drm.rs` `DrmModeObjSetProperty` | `obj_type` 之后有 4 字节**隐式 padding**。`handle_raw` 在 handler 成功后无条件 `arg.write_vm(ptr)`，会把未初始化的内核字节写给用户态，违反 `UserWrite` 的 safety 契约，也与本 crate 既有约定不符（`DrmVersion`、`DrmModeFbCmd2`、`DrmModeGetPlaneRes`、`DrmModeObjGetProperties` 都有显式 `abi_pad`） | 显式加 `pub abi_pad: u32` 并改注释。字段偏移与 24 字节布局不变，`const _: [(); 24]` 仍然成立 |
| 2 | `card0.rs` 0xAB / 0xBA | 两个用户可见命令**没有任何运行期覆盖**。命令字由 `iowr::<T>()` 按 `size_of::<T>()` 编码，「命令字 ↔ 客户端结构体」只能靠调用验证：布局漂移不会编译失败，只会让调用静默落到 `EOPNOTSUPP` | 新增独立包 `io/drmdevice/abi-tests/drm-set-property/`（根 `Cargo.toml` 的 `io/drmdevice/abi-tests/*` 已在 `exclude` 里，不需要改工作区）。用例用**硬编码命令字**（`0xc01064ab` / `0xc01864ba`）并用本地 `repr(C)` 尺寸重推 `_IOWR` 断言相等，覆盖未知对象 / 未知属性 → `ENOENT`、非法值 → `EINVAL`、成功路径 → 0，结束时把连接器属性恢复原值 |

### 同一 PR 的 CI 失败记录（不是代码问题，仅作对照）

| 构建 | 失败项 | 原因 | 处理 |
|---|---|---|---|
| `#2422` | `Check: Rustfmt` | 新 `impl` 被整块插进了 `impl DrmIoctl for DrmModeObjGetProperties` 体内，rustfmt 报 `implementation is not supported in \`trait\`s or \`impl\`s` 并中止解析 | 已修：`port-to-main/pr-g-drm-set-property.patch` 现已是修复后的版本（`pr-g-fix-placement.patch` 因此会 `--check` 失败，属正常） |
| `#2422` | 其余 21 项 | 被 rustfmt 失败 `⏭` 跳过 | 同上 |
| `#2432` | `Failed in branch riscv64 @ xkernel-agent && docker && vhost-vsock && container-vsock` | riscv64 执行节点的标签匹配 / 制品归档异常，与 diff 无关 | 重跑即可 |

### 应用方式

```powershell
cd C:\Users\a\x-kernel-pr
git checkout pr-g-drm-set-property
git apply <repo>\patches\upstream\fixes\pr-g-review-abi-pad-and-test.patch
git add -A
git commit --amend --no-edit
git push --force-with-lease fork pr-g-drm-set-property:pr-g-drm-set-property
```

> ⚠️ **Windows PowerShell 5.1 不支持 `&&`**：写成 `git add -A && git commit --amend --no-edit`
> 会整行报 `标记“&&”不是此版本中的有效语句分隔符`（ParserError），**两个命令都不会执行** ——
> 结果是补丁已 `git apply` 进工作区，但既没 stage 也没提交，此时 `git push` 只会回
> `Everything up-to-date`。请逐行执行，或改用 `pwsh`（PowerShell 7+）。

从零重建该分支的顺序（**本机已逐条验证**：四条打完后两文件与 head `e42b06c1` 逐字节一致）：

```powershell
git apply patches\upstream\port-to-main\pr-g-drm-set-property.patch
git apply patches\upstream\fixes\pr-g-rustfmt-call-width.patch
git apply patches\upstream\fixes\pr-g-blob-publish-window.patch
git apply patches\upstream\fixes\pr-g-review-abi-pad-and-test.patch
```

> `io/drmdevice/abi-tests/*` 不在内核 workspace 里，CI **不会**自动跑这条用例，
> 与既有 `drm-identity` 一致：需要在独立 guest 上手工构建执行（见该目录 README）。

---

## pr-g-review-errno-einval.patch

**为什么存在**：维护者 `luodeb`（Debin）2026-10-18 16:53 对照 Linux 6.8 复核 errno 语义，指出本 PR 的 errno
方向反了 —— 未知属性应为 **`EINVAL`**，不是 `ENOENT`；并指出 `set_one_property` 的 rustdoc 引用了现代内核
里并不存在的 `drm_mode_setproperty_user()`。核对 `v6.8` 源码（`drivers/gpu/drm/drm_mode_object.c`、
`drivers/gpu/drm/drm_connector.c`）确认其结论：

| 事实 | 出处 |
|---|---|
| `drm_mode_obj_set_property_ioctl()` 的 `ret` 初值即 `-EINVAL` | drm_mode_object.c |
| 未知对象（`drm_mode_object_find()` 失败）→ `-ENOENT` | 同上 |
| 已知对象 + 未知属性 → `goto out_unref`，`ret` 未被改写 → **`-EINVAL`** | 同上 |
| `DRM_IOCTL_MODE_SETPROPERTY` 的 handler `drm_connector_property_set_ioctl()` 只是把 `obj_type` 固定为 `DRM_MODE_OBJECT_CONNECTOR` 的薄包装 | drm_connector.c |
| `drm_atomic_set_property()` 只会被已查到的属性调用，未知属性到不了那里 | drm_atomic.c |

也就是说：`MODE_ATOMIC` 原本返回的 `EINVAL` 才是 Linux 值，**两个新入口的 `ENOENT` 偏了**；
此前判为「有意保留的可观察差异」的那条意见需要按此重新定性。

**改动**（3 个文件、6 个 hunk）：

| 文件 | 改动 |
|---|---|
| `io/drmdevice/src/card0.rs` `set_one_property` | `apply_prop` 返回 `Ok(false)` 的分支由 `VfsError::NotFound` 改为 `VfsError::InvalidInput`（对外 `ENOENT` → `EINVAL`），并加一行说明：只有对象查表失败才是 `ENOENT` |
| 同文件 rustdoc | 删掉「新入口 `ENOENT` 才对、atomic 应跟随」那段错误依据，改写为按 `drm_mode_obj_set_property_ioctl()` 的三条路径（对象不存在 / 属性不存在 / 值非法）说明；顺带把 0xAB 的 handler 注释直接指名 `drm_connector_property_set_ioctl()` |
| `io/drmdevice/abi-tests/drm-set-property/` | 两处「未知属性 → `ENOENT`」断言改为 `EINVAL`（未知对象仍 `ENOENT`），用例 README 同步 |

**验证**：对 head `41dd0dc7` 的 `git apply --check` / 实打 / 反向 = 0；改后 0xAB、0xBA、0xBC 三个入口对同一错误的
返回值一致，客户端无法据 errno 反推走的是哪个入口。

**应用方式**：

```powershell
cd C:\Users\a\x-kernel-pr
git checkout pr-g-drm-set-property
git apply <repo>\patches\upstream\fixes\pr-g-review-errno-einval.patch
git add -A
git commit --amend --no-edit
git push --force-with-lease fork pr-g-drm-set-property:pr-g-drm-set-property
```

> `present_fb` 与 state 提交之间的并发窗口（x-cibot 11:33 复审的低置信项）本次仍未改：
> `MODE_ATOMIC` 同形，彻底修法要给三个入口引入串行化，属独立变更。

---

## pr-g-present-serialization.patch（**可选**，针对 x-cibot 复审的最后一跳）

**为什么存在**：x-cibot 从 11:07 到 17:49 连续 4 轮复审都把这条件列为「仍需作者处理」：
`present_fb` 在 `drop(state)` 之后调用，两个客户端并发写同一 plane 的 `FB_ID` 时，先提交者可能把
已被淘汰的旧 fb 呈现到屏幕，屏幕与 `MODE_OBJ_GETPROPERTIES` 回报的 `plane_fb_id` 长期不一致，
而 `present_fb` 查不到 fb 时静默返回，调用方无从察觉。

**改法**（`io/drmdevice/src/card0.rs`，5 个 hunk）：

| 位置 | 改动 |
|---|---|
| `DrmCard` | 新增 `commit_lock: Mutex<()>`（带 rustdoc 说明触发场景与锁序） |
| `DrmCard::new` | `commit_lock: Mutex::new(())` |
| `set_one_property` | 进函数先取 `commit_lock`，直到 present 结束 |
| `MODE_ATOMIC::handle` | 提交段开始前取 `commit_lock` |

锁序固定为 `commit_lock` → `state` → `apply_prop` 用的内层 map；`present_fb` 仍在 `state` 释放后调用，
所以**没有**把 display HAL 调用塞进 `state` 临界区（`MODE_OBJ_GETPROPERTIES` 等读者不受影响）。

**没有覆盖的**：legacy `MODE_SETCRTC`/`MODE_CRTC_PAGE_FLIP`/`MODE_DIRTYFB` 三条路径不发布 `state`，
本次不动；它们与 atomic 提交混用同一 CRTC 本就不受支持。

**验证**：对 head `41ce6b8f` 的正向 `--check`、实打、反向 `--check` 全为 0；
**本机没有 Rust 工具链，未做编译验证**，编译结论只能等 CI。逻辑改动仅 4 处加锁 + 1 个字段。

**要不要用**：这条复审自己标了「低置信、缺少复现证据」，前几轮也明确不作为阻塞项。若想一次关掉复审，
就把它和 errno 补丁一起 amend；若判断风险不值，就保持现状，维护者只要求过 errno 那条。

```powershell
cd C:\Users\a\x-kernel-pr
git checkout pr-g-drm-set-property
git apply <repo>\patches\upstream\fixes\pr-g-present-serialization.patch
git add -A
git commit --amend --no-edit
git push --force-with-lease fork pr-g-drm-set-property:pr-g-drm-set-property
```

---

## 合并结论与待跟进（2026-10-19 更新）

- `!1039`（`pr-b-drm-legacy-modeset`）、`!1050`（`pr-g-drm-set-property`）与
  `!1059`（`pr-f-gem-close-closefb`）**均已合并**。本目录里 pr-b / pr-g 的补丁自此只是历史记录，
  不要重提；分支重建顺序也失去意义。
- **已随 !1050 合并（最终 head `f84b481c`）**：
  `pr-g-review-abi-pad-and-test.patch`（`abi_pad` + 回归包）、`pr-g-review-errno-einval.patch`
  （未知属性 → `EINVAL`、rustdoc 重写、断言同步）、`pr-g-present-serialization.patch`
  （`commit_lock` 串行化）**三者全部合入**。
- `!1058`（`pr-d-tmpfs-modes`）**已关闭，不重提**。早期记录曾把它判为"空操作"，
  但 PR 的最终结论是"上游已有重合实现"；两者都指向"不再提交"，以 PR 状态为准。
- **始终不要重提 SCM_RIGHTS**：上游 `main` 已包含该实现。
