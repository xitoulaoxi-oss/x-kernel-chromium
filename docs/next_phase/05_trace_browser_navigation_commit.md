# 05_trace_browser_navigation_commit: 区分无窗口与about:blank

优先级：P1。依赖：01–03；可与04独立分析，QEMU串行运行。状态：PLANNED，尚未执行。

工作目录：`D:\x-kernel-dsh-bridge\submission\for github`。

## 已知问题

C06诊断命令仍能返回，不能与C07全客机停顿合并为一种根因。single中两个窗口已创建，目标列表URL对应index，但实际DOM是about:blank。对比先等待首文档再建第二窗口的顺序，记录此顺序改变的影响。

## 本次只做

对C06与single分别取证：browser/zygote/GPU/renderer角色、窗口创建、target URL、实际document URL及readyState。单窗口先记录首文档状态，再发第二窗口请求；分别确认导航是否提交、页面是否绘制、输入是否送达正确窗口。

## 完成标准

失败稳定落在明确阶段，并有对应日志/PID/导航身份；至少一个同命令成功对照。若修复阶段排序，等待必须有界、记入首次启动耗时，成功仍需真实DOM与截图；不能用reload/restart冒充首次启动。

## 边界与交付

不重复盲试已做过的in-process-gpu、no-zygote、EOI模式等组合。disable-gpu的2/2也不是可靠性证明；只有新的直接证据才能提出参数候选。

交付：代码差异或明确定位结论、固定命令/版本、结果JSON、原始日志索引和下一步。原始实验新增在 `experiments/FINALS-RUNS/<new-UTC>/next-phase/05/`，不得覆盖旧失败。新文件只用英文命名；单轮未解决时如实写PARTIAL/FAIL。

## 必须先读

- `experiments/FINALS-RUNS/20261030T110856Z/task03/C06/failure-diagnostics.txt`
- `experiments/FINALS-RUNS/20261030T110856Z/task04/single/step-07-page.json`
- `experiments/FINALS-RUNS/20261030T110856Z/task04/run-single.ps1`
