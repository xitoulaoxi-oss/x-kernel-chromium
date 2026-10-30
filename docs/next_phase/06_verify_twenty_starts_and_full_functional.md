# 06_verify_twenty_starts_and_full_functional: 重新验证首次启动与整轮功能

优先级：GATE。依赖：02–05得到可解释的修复候选。状态：PLANNED，尚未执行。

工作目录：`D:\x-kernel-dsh-bridge\submission\for github`。

## 已知问题

20次不能拼接task03的5/6与task03b的6/7，也不能从不同版本、不同失败轮次择优。全部请求轮次均入账；基础设施失败单列且仍使端到端门槛未通过。只达到工程闸门，不宣称未来绝对零故障。

## 本次只做

冻结一套完整版本，先执行20次独立首次启动；再用同版本、同参数在单会话内验证HTML、renderer、双窗口切换、键盘回显、鼠标真实跳转、JS与CSS。显式记录候选内核，不使用遗留默认参数。

## 完成标准

20/20同版本首次成功、完整退出码与DOM/截图证据；单会话完整功能全通过。任何失败保留并回到对应02/03/04/05，禁止继续堆大批量测量。

## 边界与交付

通过后必须用新候选重跑30分钟和10次加载。旧内核上的长测不能直接覆盖改过timer的候选。

交付：代码差异或明确定位结论、固定命令/版本、结果JSON、原始日志索引和下一步。原始实验新增在 `experiments/FINALS-RUNS/<new-UTC>/next-phase/06/`，不得覆盖旧失败。新文件只用英文命名；单轮未解决时如实写PARTIAL/FAIL。

## 必须先读

- `evidence/2026-10-30/finals-tasks/task03/result.json`
- `evidence/2026-10-30/finals-tasks/task04/result.json`
