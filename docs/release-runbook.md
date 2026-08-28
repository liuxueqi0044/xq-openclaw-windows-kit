# 发布运行手册

## M1：解析候选（只读）

在隔离的工作目录中运行 `build/Resolve-UpstreamCandidate.ps1`，将输出写为 `candidate-lock.json`。该命令只接受固定的 `openclaw/openclaw` 和 repository ID `1103012935`；真实请求固定使用 `https://api.github.com`。它会拒绝 draft、prerelease、错误或重复资产、缺少 checksum、下载重定向离开 GitHub 官方基础设施，以及无效/缺失时间戳的 Authenticode 签名。

候选文件不是正式锁定文件：不得把它重命名、复制或自动写入 `upstream-lock.json`。人工审批必须独立复核 release ID、tag、两个 asset ID、文件名、大小、三方哈希输入、签名主体、指纹、时间戳和固定 commit 的许可证哈希。

## M2：按批准锁构建验证目录

仅在 `upstream-lock.json` 的 `approval.status` 为 `approved`，且完整身份、精确资产、签名策略和哈希字段均通过语义检查时，运行 `build/Fetch-LockedArtifacts.ps1`。输出目录必须是一个此前不存在的路径；脚本不会复用缓存或旧的 verified 目录。

M2 从固定 release ID 重新读取 release metadata，并按固定 asset ID 下载到新建临时目录。安装器只会在以下内容完全匹配后进入 verified 目录：approved lock SHA-256、官方 checksum 内的 SHA-256 与本地 SHA-256；同时必须满足 Authenticode `Valid`、精确主体、精确 thumbprint 与所需时间戳。`LICENSE` 和 `THIRD_PARTY_NOTICES.md` 从 lock 的固定 commit 获取并单独校验哈希。

任何失败都应视为 `REJECTED`：删除本次输出引用，不尝试镜像、历史文件或 `latest` 回退，也不继续 M6 组装。不要把 GitHub Token 放入参数、URL、日志或审批记录。

## 离线测试

运行以下命令验证 M1/M2，而不访问公网：

```powershell
Invoke-Pester .\tests\Unit\M1.Resolve-UpstreamCandidate.Tests.ps1, .\tests\Unit\M2.Verify-OfficialArtifact.Tests.ps1, .\tests\Integration\M1M2.SupplyChain.Tests.ps1
```

这些 fixture 仅为测试，不是上游发布候选，也不得作为正式 lock 或交付文件。
