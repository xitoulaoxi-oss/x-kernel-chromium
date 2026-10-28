# 工程规则与诊断方法

这些规则不是风格偏好，是实际踩坏过实验之后总结出来的。

## 规则 1：不要把非 ASCII 放进 PowerShell 命令

`powershell.exe -Command` / `-File` 的参数会按系统 ANSI 代码页（中文环境是 GBK）重新编码。
命令里的中文到达脚本时已经是乱码；把 `[Console]::OutputEncoding` 设成 UTF-8 **不能**修好——
实测 `"中文测试"` 经管道传给 Python 后收到的是 `[0x9518, 0x5938, 0x8151, ...]`。
曾有一次 `-Inject` 因为路径含中文拼出乱码路径，整轮取证白跑。

做法：

- 仓库内路径一律 ASCII（`artifacts/`、`guest/`、`host/` 等）；
- 需要中文正文时，用工具写文件，不要经 shell 参数传递；
- 镜像路径可以是中文，但要用参数传入并确认编码，不要拼进命令字符串。

## 规则 2：不要用 shell 文本管道改写 UTF-8 文档

`Get-Content -Raw | Set-Content -Encoding UTF8` 会按 GBK 读出再写回。
一个 41,978 B 的 UTF-8 文件会变成 51,830 B 的乱码，且**不可完全恢复**。

做法：

- 改文档用 Python，显式 `encoding='utf-8'`、`newline='\n'`、不写 BOM；
- 改之前先备份；
- 批量替换先小范围验证，再全量执行。

## 规则 3：串口一次只能可靠地送约 4 KB

实测：34 B、4 KB 的脚本逐字节正确；6,307 B 的脚本到达时出现 `>ins.` 与截断的 `if`；
2,530 B 的脚本在不按行限速时把 `chromium` 变成 `chromiu-disable-features=Vulkan: not found`。

做法：

- `host/xkwin.ps1` 的 `Send-Heredoc` 按行分块（每 12 行停 60 ms）；
- 客机脚本一律 **< 1792 B**；需要更长逻辑就拆成多个脚本再串起来；
- 大文件不要走串口：用一次性的 HTTP 上传服务器（`-ServeManifest`），388 KB 的探针二进制秒级到位；
  串口分块传同样内容会被回显淹没并损坏。

## 诊断顺序

客机里某个进程"起来了但没进展"时，第一件事是读：

```sh
cat /proc/<pid>/stat   # 字段 3 = state
cat /proc/<pid>/wchan
```

| 读数 | 含义 | 方向 |
|---|---|---|
| `st=S` + `wchan` 非空 | 真正阻塞，`wchan` 给出内核函数 | 查等待对象 |
| `st=R` + `wchan` 空 | **忙等**（烧 CPU 不推进） | 查循环 / 重试 / 轮询 |
| `st=D` | 不可中断睡眠（I/O） | 查块设备 / 文件系统 |

本项目的 Chromium 卡死实测是 `st=R` / `wchan` 空（忙等），前几轮按"阻塞"方向排查因此白走。

**推论**：用"计数器为 0"做否证，必须写明**观测窗口**。同一计数器在浏览器连网前恒为 0，
连网后才出现；`sockopt rejected: (6, 4)`（`IPPROTO_TCP` / `TCP_KEEPIDLE`）就是这样被漏掉的一例。

## 判据要在稳定期读

`_NET_CLIENT_LIST` 在启动后 25 秒读是空（JWM 还没登记），10 分钟后读就有值。
用"启动后立刻读"判定"窗口列表恒为空"会得出错误结论。
稳定性判据固定为**连续 600 秒、10 次采样**。

## screendump 判据

- 只看色数会被"空白页 + 转圈"骗（264 色）；
- 本项目用"页面区饱和度 ≥ 0.06 且色数 ≥ 300 且非空白"；
- 每个 screendump 必须有 `.stats.json`，否则不作为证据；截图本身不随仓库发布。

## 沙箱与提权边界

| 操作 | 默认档 | 一次性提权 |
|---|---|---|
| `wsl.exe -e <cmd>` | 拒绝 `Wsl/E_ACCESSDENIED` | 成功 |
| 渲染 docx（需要 spawn LibreOffice） | 失败 `spawn EPERM` | 成功 |
| `git fetch`（需要信号管道） | 失败 `couldn't create signal pipe` | 成功 |

所以：**内核构建只能在 WSL 里做**；读其产物、渲染文档、建 git 仓库可能需要一次性提权。
这是环境约束，不是项目缺陷；遇到时按"最小必要权限"申请一次，不要反复重试。

## 相关

- 传输与 harness 细节：[verification.md](verification.md)
- 构建环境：[building.md](building.md)
- 证据格式：[evidence/README.md](../evidence/README.md)
