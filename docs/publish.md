# 发布到 GitHub

本目录是普通文件夹，**没有**包含 .git。下面给出从零上传、创建 Release、团队协作的命令。

## 1. 初始化并提交（PowerShell）

~~~powershell
cd "D:\x-kernel-dsh-bridge\submission\for github"

git init -b main
git config user.name  "你的 GitHub 显示名"
git config user.email "你的 GitHub 已验证邮箱"

git add .
git status --short

git commit -m "Initial finals monorepo: full x-kernel tree + harness + docs"
~~~

提交前检查：

~~~powershell
# artifacts 下应该只有 README.md / SHA256SUMS.txt
git ls-files artifacts
# 以下命令不应输出任何截图/视频
git ls-files | Select-String '\.(png|mp4|mkv|mov)$'
~~~

## 2. 在 GitHub 建仓库并推送

### 方式 A：网页建空仓库（不勾 README/.gitignore）

在 GitHub 新建空仓库 x-kernel-chromium，然后：

~~~powershell
git remote add origin https://github.com/<your-user>/x-kernel-chromium.git
git push -u origin main
~~~

### 方式 B：用 gh CLI 一步完成

~~~powershell
gh auth login
gh repo create x-kernel-chromium --public --source . --remote origin --push
~~~

### SSH（可选）

~~~powershell
git remote set-url origin git@github.com:<your-user>/x-kernel-chromium.git
git push -u origin main
~~~

> HTTPS 推送需要 Personal Access Token（不是 GitHub 密码）；SSH 需要本机已配置 key。
> 如果推送因体积中断，先执行：
>
>     git config http.postBuffer 524288000
>     git config http.version HTTP/1.1
>     git push --verbose -u origin main

## 3. 上传内核 Release

内核二进制在 artifacts/ 下，但被 .gitignore 排除；用 Release 上传：

~~~powershell
git tag -a finals-v1 -m "finals baseline: build + 10 min stability"
git push origin finals-v1

gh release create finals-v1 `
  "artifacts/kernel-procfs.bin" `
  "artifacts/kernel-keepalive.bin" `
  --title "finals-v1" `
  --notes "x-kernel full tree + kernel binaries; see docs/finals.md"
~~~

没有 gh 时：GitHub 网页 → Releases → Draft a new release → 选择/创建 tag → 上传两个 .bin。

> 每次决赛基线都建议新建 tag（finals-baseline、finals-v1、finals-v2），
> Release 与 docs/performance.md 的读数一一对应。

## 4. 队友开始编译

~~~powershell
git clone https://github.com/<your-user>/x-kernel-chromium.git
cd x-kernel-chromium

# WSL2 Ubuntu 内
bash build/build-kernel.sh
# 产物：artifacts/kernel-procfs.bin（本地，不提交）
~~~

分支建议：

~~~powershell
git checkout -b feat/your-topic
# 修改 kernel/、host/、guest/ 或 tests/
git add .
git commit -m "feat: ..."
git push -u origin feat/your-topic
~~~

## 5. 提交前检查

- git status 不含 artifacts/ 下的 .bin、截图、视频；
- bash build/build-kernel.sh 能产出 kernel.bin；
- 至少跑一个 docs/finals.md 里的场景；
- 更新 docs/performance.md 或 evidence/reports/ 的对应数据；
- PR 模板里的检查项全部勾选。

# 确认内核二进制被忽略（会打印 .gitignore 规则）
git check-ignore -v artifacts/kernel-procfs.bin
~~~

## 2. 在 GitHub 建仓库并推送

### 方式 A：网页建空仓库（不勾 README/.gitignore）

在 GitHub 新建空仓库 x-kernel-chromium，然后：

~~~powershell
git remote add origin https://github.com/<your-user>/x-kernel-chromium.git
git push -u origin main
~~~

### 方式 B：用 gh CLI 一步完成

~~~powershell
gh auth login
gh repo create x-kernel-chromium --public --source . --remote origin --push
~~~

### SSH（可选）

~~~powershell
git remote set-url origin git@github.com:<your-user>/x-kernel-chromium.git
git push -u origin main
~~~

> HTTPS 推送需要 Personal Access Token（不是 GitHub 密码）；SSH 需要本机已配置 key。
> 如果推送因体积中断，先执行：
> ~~~powershell
> git config http.postBuffer 524288000
> git config http.version HTTP/1.1
> git push --verbose -u origin main
> ~~~

## 3. 上传内核 Release

内核二进制在 artifacts/ 下，但被 .gitignore 排除；用 Release 上传：

~~~powershell
git tag -a finals-v1 -m "finals baseline: build + 10 min stability"
git push origin finals-v1

gh release create finals-v1 `
  "artifacts/kernel-procfs.bin" `
  "artifacts/kernel-keepalive.bin" `
  --title "finals-v1" `
  --notes "x-kernel full tree + kernel binaries; see docs/finals.md"
~~~

没有 gh 时：GitHub 网页 → Releases → Draft a new release → 选择/创建 tag → 上传两个 .bin。

> 每次决赛基线都建议新建 tag（finals-baseline、finals-v1、finals-v2），
> Release 与 docs/performance.md 的读数一一对应。

## 4. 队友开始编译

~~~powershell
git clone https://github.com/<your-user>/x-kernel-chromium.git
cd x-kernel-chromium

# WSL2 Ubuntu 内
bash build/build-kernel.sh
# 产物：artifacts/kernel-procfs.bin（本地，不提交）
~~~

分支建议：

~~~powershell
git checkout -b feat/your-topic
# 修改 kernel/、host/、guest/ 或 tests/
git add .
git commit -m "feat: ..."
git push -u origin feat/your-topic
~~~

## 5. 提交前检查

- git status 不含 artifacts/ 下的 .bin、截图、视频；
- bash build/build-kernel.sh 能产出 kernel.bin；
- 至少跑一个 docs/finals.md 里的场景；
- 更新 docs/performance.md 或 evidence/reports/ 的对应数据；
- PR 模板里的检查项全部勾选。
