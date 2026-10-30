# 02_fix_serial_upload_and_markers: 修复上传与完成回执链路

优先级：P0。依赖：01。状态：PLANNED，尚未执行。

工作目录：`D:\x-kernel-dsh-bridge\submission\for github`。

## 已知问题

single2日志中head命令变形且返回127，随后才出现chmod找不到文件；crash日志中可见被半截ANSI包围的__XK7471578__rc=0，但现解析器要求行首，未匹配。设计有边界、会话nonce和超时的协议；不能简单放宽到匹配任何echo文本。

## 本次只做

先离线回放原始字节，再修host/xkwin.ps1与host/command-result.ps1。分别处理小脚本heredoc接收、写盘/重命名/校验、chmod、命令结束回执。任何中间步骤失败立即记录原始错误，不能推进到下一条。

## 完成标准

增加真实日志回放：完整/分片/ANSI交错/错nonce/仅echo/缺结束/非零返回/缺文件。只在结果可确定时返回退出码，否则标记协议异常。随后在snapshot中20次小文件上传均字节数、哈希、退出码一致，并覆盖至少3次新启动的初始上传。

## 边界与交付

只修传输和解析，不同时改内核、GPU参数或延长超时掩盖问题。保留坏样本，禁止把协议失败标成浏览器崩溃。

交付：代码差异或明确定位结论、固定命令/版本、结果JSON、原始日志索引和下一步。原始实验新增在 `experiments/FINALS-RUNS/<new-UTC>/next-phase/02/`，不得覆盖旧失败。新文件只用英文命名；单轮未解决时如实写PARTIAL/FAIL。

## 必须先读

- `experiments/FINALS-RUNS/20261030T110856Z/task04/single2/console.log`
- `experiments/FINALS-RUNS/20261030T110856Z/task09/crash/console.log`
- `host/command-result.ps1`
