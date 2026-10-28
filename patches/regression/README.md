# patches/regression/ — DRM 回归用例

`io/drmdevice/tests/mode.rs` 是 `0001` / `0002` 的回归用例，随完整解补丁一起进入源码树。

## 特点

- **真实 fd、真实 ioctl**，不 mock 内核接口；
- 覆盖 legacy `ADDFB`、24bpp `CREATE_DUMB`、`MODE_CURSOR`、`SET_CLIENT_CAP`、
  `DIRTYFB` 未知 framebuffer 返回 `ENOENT`；
- 同时断言"已注册 fb 成功"，防止把"一律 ENOENT"当成通过。

## 为什么不做 mock

这套接口的 bug 大多在 **ABI 布局**（结构体大小、padding、命令字）和**返回码**上。
mock 掉 ioctl 后，这些恰恰测不到。真实 ioctl 的价值是：布局写错时，内核会直接返回
`EINVAL`/`ENOTTY`，而不是让测试"看起来通过"。

## 怎么跑

在完整 x-kernel 源码树中（应用完整解补丁后）：

```bash
cd io/drmdevice
cargo test --test mode
```

具体 target 名称由 `0002-drm-regression-manifest.patch` 调整；如果 target 名对不上，
以 `Cargo.toml` 为准。

## 与上游的关系

这些用例随 `!1039` 合入上游；本目录保留原件，方便在 `d3a6ec9` 基线上复核。
