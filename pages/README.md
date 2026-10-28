# pages/

赛题方指定的三类测试页，保持**逐字节不变**。

| 文件 | 字节 | SHA-256 | 测什么 |
|---|---|---|---|
| `index.html` | 5,730 | `831cf28f3748940b…` | 指定 HTML：布局完整性、表格、列表、表单、图片 |
| `interaction.html` | 10,991 | `58130daa4a2f426f…` | JavaScript 交互：DOM、事件、定时器、JSON、Promise |
| `layout.html` | 11,444 | `a1b04f9aba81b4b7…` | CSS 布局：flex、grid、盒模型、定位 |

完整 SHA-256 与客机内校验见 [`../rootfs/rootfs-change-manifest.dbg`](../rootfs/rootfs-change-manifest.dbg)。

## 怎么进客机

交付镜像里没有这三张页面，只有 3,024 B 的占位页。每次运行：

1. 宿主用 `-ServeManifest guest/serve-pages.txt` 起 HTTP 服务；
2. 客机 `06-fetch-pages.sh` 取三张页面到 `/usr/share/kiosk/official/`；
3. 客机内核对字节数与 SHA-256，打印 `P1 ok=3 bad=0`；
4. 改写 `/etc/kiosk/url` 指向 `index.html`。

## 渲染读数

| 页面 | 实测 colors | 会话 |
|---|---|---|
| `index.html` | `835`（另有 847 / 892） | `RENDER-20261015T141742Z`、`SELF-TEST-2026-10-16` |
| `interaction.html` | `886` | `INTER7-20261019T064147Z` |
| `layout.html` | `691` | `LAYOUT-20261019T021243Z` |

三个数不同是正常的：页面结构不同，判据是**非空白 + 页面区饱和度**，不是色数比大小。
截图由 harness 在验收时生成，不随仓库发布。

## 不要做什么

- 不要为了"更好看"改页面内容；
- 不要把页面放进补丁或内核源码；
- 不要用旧读数配新页面——`06-fetch-pages.sh` 会在客机内校验 SHA-256。
