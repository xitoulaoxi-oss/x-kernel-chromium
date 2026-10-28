# 包自证：用本包自己的内容跑一次（2026-10-16）

> 历史记录（2026-10-16 的自证会话）。当时使用的路径与现在不同，读数本身未改写；证据索引见 [`../../README.md`](../../README.md)。


这一份是**整理完成之后、只用仓库内文件跑出来的一次验收**，
用来证明仓库是自足的。

## 命令（从仓库根目录执行）

```powershell
cd <repo>
powershell -NoProfile -ExecutionPolicy Bypass -File host\xkwin.ps1 -Tag ACCEPT -Kernel artifacts\kernel-procfs.bin -ServeManifest guest\serve-pages.txt -Script "guest\06-fetch-pages.sh;guest\x1-input.sh;guest\x2-xorg.sh;guest\y3-jwm-stock.sh;guest\x4-win1.sh;guest\y6-evidence.sh;guest\x5c-win2.sh" -Key "cmd=sleep 20;alt+tab@8;cmd=sh /tmp/xk-y6-evidence.sh;alt+tab@8;cmd=sleep 20;cmd=sh /tmp/xk-y6-evidence.sh" -CommandTimeoutSec 300 -BootTimeoutSec 420 -AfterScriptWait 60 -OutDir "runs\ACCEPT"
```

## 读数

| 项 | 值 |
|---|---|
| 最终 screendump | `1280x800 colors=892 dominant=0.321 blank=False` |
| 窗口 | `_NET_CLIENT_LIST` 两个 id；两个窗口 `_NET_WM_PID` 相同、`WM_CLASS` 都是 `chromium (/tmp/pr)` |
| 切换 | 两次 Alt+Tab，`_NET_ACTIVE_WINDOW` 与 `_NET_CLIENT_LIST_STACKING` 双向翻转 |
| 输入链路 | Xorg 日志：`config/udev: Adding input device QEMU Virtio Keyboard` → `Using input driver 'libinput'` |
| 页面 | 由 `guest/06-fetch-pages.sh` 从宿主取入并在客机内校验 sha256 |
| 宿主指标 | `peak_ws=2,294,333,440 B`、`cpu=271.42 s`（宿主 QEMU 进程） |

> 截图文件未随仓库发布；本目录保留 console、指标与统计 JSON。

## 一个必须提醒的坑

**忘了 `-ServeManifest` 就会 ERR_FILE_NOT_FOUND。** 第一次自检就少写了这个参数，
画面上是 Chromium 的 "Your file couldn't be accessed"，颜色数只有 427——看起来像"渲染失败"，
其实是三张页面没有装进客机。交付镜像里只有 3,024 B 的占位页，页面必须每次运行都装。
