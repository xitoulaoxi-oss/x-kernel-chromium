# rootfs/

交付镜像的改动清单。**原镜像只读，所有会话都用 `-snapshot` 启动。**

## 范围

只改 4 个文件：新增三张测试页，改写 `/etc/kiosk/url`。
没有二进制、没有 `/init`、没有 `/etc/inittab`、没有库文件。

```text
write index.html        /usr/share/kiosk/official/index.html        5730 B
write interaction.html  /usr/share/kiosk/official/interaction.html 10991 B
write layout.html       /usr/share/kiosk/official/layout.html       11444 B
write kiosk-url         /etc/kiosk/url                                 44 B  file:///usr/share/kiosk/official/index.html
```

| 文件 | 作用 |
|---|---|
| `rootfs-change-manifest.dbg` | debugfs 形式的改动清单，带字节数与 SHA-256 |
| `debugfs-stage/` | 清单引用的暂存文件；由 `host/make_rootfs_manifest.py` 从 `pages/` 生成 |

> `debugfs-stage/` 里的三个 HTML 是**暂存副本**，源文件在 [`../pages/`](../pages/)。
> 保留副本是因为 `debugfs write` 从 staging 目录执行，源路径要短且稳定。

## 应用

在一份**工作副本**上操作，永远不要写原镜像：

```bash
# 1. 制作可写副本（Python，纯用户态）
python host/rootfs_audit.py workcopy --image <image-dir>/agentos-disk.img --out work/agentos-work.img

# 2. 从 staging 目录执行 debugfs
cd rootfs/debugfs-stage
debugfs -w -f ../rootfs-change-manifest.dbg <path-to-working-copy.img>
```

## 重新生成清单

```powershell
python host\make_rootfs_manifest.py           # 重新生成
python host\make_rootfs_manifest.py --check   # 只校验源文件
```

脚本会从 `pages/` 复制三张页面到 `debugfs-stage/`，写入 `kiosk-url`，再生成清单。
清单里的 `# unchanged:` 列出**没有改动**的关键文件（`x11-session`、`inittab`、`chromium`、
`Xorg`、`jwm`、`chromium.conf`），方便逐条核对。

## 为什么不是直接改镜像

赛题方允许改 rootfs，但要求提供 debugfs 信息评估影响。直接交付一个改过的 2 GB 镜像
无法审计；给出"4 条 write + 校验和 + 未改动清单"才是可复核的。

## 注意

- `/run/udev/data/c13:64`、`c13:65`、`/etc/X11/xorg.conf.d/10-xk.conf`、`/tmp/pr`（Chromium profile）
  只在运行期存在，**不进镜像**；
- `/etc/kiosk/url` 的 44 字节内容就是 `file:///usr/share/kiosk/official/index.html`；
- 运行期由 `guest/06-fetch-pages.sh` 每次重新装页面并校验 sha256。
