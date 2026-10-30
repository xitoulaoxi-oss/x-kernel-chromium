# 10_measure_cross_layer_optimizations: 按实际瓶颈做最多三项优化

优先级：P3。依赖：09。状态：PLANNED，尚未执行。

工作目录：`D:\x-kernel-dsh-bridge\submission\for github`。

## 已知问题

100ms兜底tick是可靠性候选，不自动算性能改善；需要测空闲CPU、IRQ频率与新延迟，明确代价。5%/15%/30%对应赛题档次，但结果必须超过测量噪声。

## 本次只做

从启动、页面/缓冲区、renderer/IPC调度中选择最多三项有证据的瓶颈。每项独立补丁、独立回归、相同协议至少五轮before/after。另保留相对首个可运行版本的可追溯对照。

## 完成标准

每项有根因/路径证据、同口径原始样本、统计、失败率和回归；无收益或退化如实保留并可撤回候选。

## 边界与交付

不预先认定memfd、零拷贝、DRM或调度器就是瓶颈；不将三个验收脚本修复包装为三项跨层性能优化。

交付：代码差异或明确定位结论、固定命令/版本、结果JSON、原始日志索引和下一步。原始实验新增在 `experiments/FINALS-RUNS/<new-UTC>/next-phase/10/`，不得覆盖旧失败。新文件只用英文命名；单轮未解决时如实写PARTIAL/FAIL。

## 必须先读

- `docs/performance.md`
- `kernel/task/ktask/src/api.rs`
