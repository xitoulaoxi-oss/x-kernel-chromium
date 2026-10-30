# x-kernel Chromium Runtime

在 AArch64 QEMU 纯 TCG 上运行 x-kernel、Xorg、JWM 和 Chromium。仓库包含完整内核源码、运行工具、官方测试页与精简验收证据。

## 当前状态

截至 2026-10-30：正式 30 分钟 / 10 次加载、JS/CSS 各六项、Linux CSS 对照已有通过记录；首启空白与客机停顿仍可复现，完整验收尚未通过。客机 Chromium 的 1.5G 峰值内存资格和四项五轮性能基线尚未证实，不宣称性能收益或决赛总分。

- [验证结果和成功/失败证据](evidence/README.md)
- [运行与验收说明](tests/USAGE.md)
- [构建说明](docs/building.md)
- [性能定义与限制](docs/performance.md)
- [上游贡献](docs/upstream.md)

## 快速开始

需要 Windows PowerShell 5.1、Python 3.11+、QEMU 8.0+。客机镜像由赛题方提供；内核二进制从 Releases 获取或自行构建。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-finals.ps1 -Mode preflight -Disk "<image-path>" -Kernel artifacts/kernel-procfs.bin
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-finals.ps1 -Mode smoke -Disk "<image-path>"
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-finals.ps1 -Mode functional -Disk "<image-path>"
powershell -NoProfile -ExecutionPolicy Bypass -File tests/run-finals.ps1 -Mode load -Disk "<image-path>"
```

实际 DOM 取证会在 QEMU snapshot 内按需开启客机 CDP 并记录策略变化。禁止在可写原镜像模式使用该调整。窗口色数只作辅助；页面 URL、完成状态和实际检查结果都必须满足判据。失败返回非零并保留日志。

```bash
# WSL2 Ubuntu，从源码构建
bash build/build-kernel.sh
```

## 目录

| 路径 | 用途 |
|---|---|
| kernel/ | 完整 x-kernel 源码和许可证 |
| host/、guest/ | 宿主验收、客机配置和观测工具 |
| host/acceptance/ | 冷启动、稳定性和三场彩排汇总器 |
| tests/、pages/ | 回归用例、一键入口、官方 HTML |
| evidence/ | 当前精简证据、失败样本与来源哈希 |
| build/、patches/、rootfs/ | 构建、上游补丁与镜像配置 |
| docs/ | 架构、方法、限制和复现说明 |

实验缓存、浏览器下载、逐帧截图、编译产物及私人工作日志不进入 Git。历史已提交证据仍在 Git 历史中。见 [文档索引](docs/README.md) 与 [发布约定](docs/publish.md)。

许可证：[Apache-2.0](LICENSE)。第三方来源与声明见 [NOTICE](NOTICE) 和 [kernel/LICENSE](kernel/LICENSE)。
