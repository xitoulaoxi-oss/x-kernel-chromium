# Verification

运行命令见 [tests/USAGE.md](../tests/USAGE.md)，当前结果见 [evidence/README.md](../evidence/README.md)。

页面验收读取实际 URL、readyState、导航身份、完整检查行及总结果；不以色数或标题单独判断。键鼠走真实 QMP 输入，DOM 只读取结果。renderer 角色来自 Chromium API，并与客机 procfs 的 PID、线程数和父进程链核对。

长测要求不少于 1800 秒、每 120 秒加载一次共 10 次，每次出现新的完成导航；还检查心跳连续性、触发偏差及崩溃/OOM标记。截图统一由 QEMU screendump 生成；原图本地保留。

当前仍有首启 about:blank 和输入停顿。单项成功或恢复成功不能作为严格 20 次首次启动全通过的证据。

## 2026-10-30 finals task book

- 01 PASS: same-command success/failure pair; failure's four vCPUs sat at the same idle/`restore_irq` PC (QEMU CPU/wall 0.215) while QMP reported running. See [startup capture](../evidence/2026-10-30/finals-tasks/task01/startup-capture/startup-capture.json).
- 02 PARTIAL: `rearm_local_timer` now arms a 100 ms fallback idle tick instead of disarming. The random stall was not eliminated.
- 03 FAIL: 11/13 first starts passed, not 20/20. Failures C06/C07 are kept.
- 04 FAIL: the single-session functional round stopped at the first DOM check (`about:blank`); no JS/CSS/input pass was spliced in.
- 05 FAIL: six rounds yielded four valid samples for first frame/page load, zero role-confirmed renderer samples and zero guest-memory samples; no four-metric five-round baseline.
- 06-08 BLOCKED, 09 PARTIAL (crash/stop injected, leak not run), 10 BLOCKED.

Full table: [evidence/README.md](../evidence/README.md) and [finals-tasks manifest](../evidence/2026-10-30/finals-tasks/manifest.json).

## 2026-10-30 next phase (12 tasks)

P0 passed: 02 fixed the heredoc delimiter/trim splice and partial-ANSI marker parse (20/20 uploads over 3 cold boots; 6/6 replay); 03 made `-Key` quote-aware, added `wait=`, rejected unknown actions, and separated control-channel/observer errors from target faults.

P1 is partial: 04 has real full-guest stalls but no event-level missing-event trace; 05 found the old two-window `about:blank` failure and passed 4/4 with a first-document check before the second window, but the ordering is not proven and the single-window stall remains.

Gates 06/09/10/11 are blocked, 07 is partial, 08 corrected the metric definitions. No 20/20 or full functional claim is made. Progress package: `submission/release-2026-10-30-next-phase/`.


## 2026-10-31 checkpoint clarification

截至2026-10-31，trace-followup/01–05已提供阶段实现和实测记录；发布前又发现解码器边界问题，仍需修复。首启停顿、完整验收和四项五轮未通过。见 [精简证据](../evidence/2026-10-31/trace-checkpoint/README.md)。
