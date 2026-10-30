# 03_fix_step_encoding_and_diagnostic_truth: 修复步骤编码与故障分类

优先级：P0。依赖：02。状态：PLANNED，尚未执行。

工作目录：`D:\x-kernel-dsh-bridge\submission\for github`。

## 已知问题

stop用例中的sh -c带内部分号，被拆成未闭合引号，原始控制台出现>续行。修正该路径后，更新observe分类：控制通道异常、未配置心跳、无进程退出证据分别标记，不自动拼成CRASH+HANG。

## 本次只做

复查-Key按分号拆分的边界。优先把复杂命令放入已验证上传的短guest脚本，通过简单参数调用；如增加结构化steps文件，须保留旧接口兼容并在开机前校验。明确wait动作，不能把sleep 5当键盘按键。

## 完成标准

离线解析保留引号内分号，或整个用例改用短脚本避免分隔歧义；未知动作明确拒绝。正常命令和注入后的只读命令均可返回完成回执。短会话未启用心跳不得仅因缺HB判HANG。

## 边界与交付

目前真实信号确已送达一个Chromium子进程，但fault-renderer.sh只按父进程名与线程数挑选，不能证明PID154是renderer；真实renderer注入需在11中补身份核验。

交付：代码差异或明确定位结论、固定命令/版本、结果JSON、原始日志索引和下一步。原始实验新增在 `experiments/FINALS-RUNS/<new-UTC>/next-phase/03/`，不得覆盖旧失败。新文件只用英文命名；单轮未解决时如实写PARTIAL/FAIL。

## 必须先读

- `experiments/FINALS-RUNS/20261030T110856Z/task09/run-faults.ps1`
- `experiments/FINALS-RUNS/20261030T110856Z/task09/stop/console.log`
- `guest/fault-renderer.sh`
- `host/observe.py`
