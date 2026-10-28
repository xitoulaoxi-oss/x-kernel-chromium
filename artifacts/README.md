# artifacts/

**内核二进制不提交到 Git。** 本目录保留校验和与说明；`*.bin` 是本地构建输出或从 GitHub Releases 下载的资产。

| 文件 | 字节 | SHA-256（前 16 位） | 用途 |
|---|---|---|---|
| `kernel-procfs.bin` | 8,544,026 | `5261CEB3C11249A7` | **推荐**：完整解；600 秒稳定、三页渲染、性能 8 次都用它 |
| `kernel-keepalive.bin` | 8,544,026 | `7ECA45ACEE9DE2DC` | 上一枚：无 procfs 字段；双窗口 + Alt+Tab 与首个渲染证据用它，也是 before/after 的基线 |
| `kernel-baseline.bin` | 8,437,530 | `FA956A34C985B0E8` | 早期版本：图形会话可起，Chromium 未渲染；仅作历史参考 |
| `kernel-scmrights.bin` | 8,544,026 | `5261CEB3C11249A7` | 与 `kernel-procfs.bin` **内容完全相同**，保留早期日志里的文件名 |

## 获取内核

- **从 Releases 下载**：把对应版本的 `kernel-procfs.bin` 放到本目录；
- **本地构建**：`bash build/build-kernel.sh`，默认输出到本目录；
- **校验**：

```bash
cd artifacts
sha256sum -c SHA256SUMS.txt
```

Windows：

```powershell
Get-ChildItem artifacts\*.bin | ForEach-Object {
  "{0}  {1}" -f (Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLower(), $_.Name
}
```

## 发布

内核二进制作为 GitHub Release 资产上传，例如：

```powershell
gh release create finals-v1 artifacts\kernel-procfs.bin artifacts\kernel-keepalive.bin `
  --title "finals-v1" --notes "30 min stability / load loop / performance baseline"
```

**不要手工替换这些文件。** 更新流程是：改 `kernel/` → 构建 → 更新 `SHA256SUMS.txt` → 重跑验收 → 发 Release。
