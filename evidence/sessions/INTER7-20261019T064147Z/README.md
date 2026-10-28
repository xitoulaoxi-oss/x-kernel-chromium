# JavaScript 交互页渲染（交付推荐内核）

补齐"三页都由交付内核渲染"的最后一块：`index.html` 早已有（`SELF-TEST`，`colors=892`），
`layout.html` 有（`LAYOUT`，`colors=691`），本目录补上 `interaction.html`。

| 项 | 值 |
|---|---|
| 内核 | `artifacts/kernel-procfs.bin`（sha `5261CEB3C11249A7…`） |
| 会话 | `INTER7-20261019T064147Z` |
| 页面 | `interaction.html`，10,991 B，与其余两页同批下发，sha256 前 16 位由客机自校验 |
| 窗口 | `_NET_CLIENT_LIST` = **`0x400003`**（jwm 登记） |
| 渲染判定 | **`colors=886`、`dominant=0.3318`、`blank=False`**，1280×800 |

## 逐次读数

> 截图文件未随仓库发布；下表是逐帧 `.stats.json` 的读数，帧名仅作记录。

| 帧 | colors | blank |
|---|---|---|
| `00-before` | 2 | True |
| `01-after-06-fetch-pages` | 2 | True |
| `02-after-x1-input` | 2 | True |
| `03-after-x2-xorg` | 2 | True |
| `04-after-y3-jwm-stock` | 28 | False |
| `05-after-x7-interaction` | 886 | False |
| `zz-final` | 886 | False |

> 与 `index.html` 的 `835`/`892` 和 `layout.html` 的 `691` 不是同一个数：三页结构不同、画布内容不同，
> 色数天然不同。判定用的是"非空白 + 页面区饱和度"，不是色数比大小（见 `../../../docs/performance.md` §3）。
