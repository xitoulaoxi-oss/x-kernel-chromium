# 01_freeze_and_classify: 统一版本与失败账本

优先级：P0。依赖：无。状态：PLANNED，尚未执行。

工作目录：`D:\x-kernel-dsh-bridge\submission\for github`。

## 已知问题

bin c50075b6…、ELF 1b0c758d…、配置fbd1615b…为当前候选链；旧run4使用kernel-procfs，task03冻结为idlefix 8ab6882b…，不得混称同一字节版本。校验每轮实际bin/ELF/config、源码补丁、页面与参数；同代码不同build元数据必须给出代码段一致性依据。

## 本次只做

读取现有freeze、QEMU实参、构建与harness-result，将每轮明确归为上传/命令协议、全客机停顿、浏览器无窗口、DOM未提交、观测器失败。候选统一显式传入kernel-final，不依赖可能残留kernel-eoi的脚本默认值。

## 完成标准

形成run-ledger.json和版本矩阵，每条失败都有首个异常与原始路径。保留端到端成功率，同时单列基础设施失败和已进入Chromium阶段的失败。2/13仅是两次遇错即停批次的描述，不能称已测得长期15%故障率。

## 边界与交付

现有28份精简证据SHA-256全部匹配，无需重做已完成的证据校验。已有约840MB内存预算和当前候选同次构建记录继续沿用，不把它们重新设为所有工作的阻塞项。

交付：代码差异或明确定位结论、固定命令/版本、结果JSON、原始日志索引和下一步。原始实验新增在 `experiments/FINALS-RUNS/<new-UTC>/next-phase/01/`，不得覆盖旧失败。新文件只用英文命名；单轮未解决时如实写PARTIAL/FAIL。

## 必须先读

- `evidence/2026-10-30/finals-tasks/status.json`
- `evidence/2026-10-30/finals-tasks/task02/result.json`
- `experiments/FINALS-RUNS/20261030T110856Z/task03/freeze.json`
