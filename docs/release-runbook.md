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

## M5–M8：自动门和候选包

正式构建只能从干净仓库的完整 40 位 commit SHA、受 Git 跟踪且人工批准的 `manifest/upstream-lock.json` 开始。`build/Invoke-QualityGates.ps1` 固定 Pester 5.7.1 和 PSScriptAnalyzer 1.25.0；`build/Build-Package.ps1 -Mode Formal` 还会绑定当前 HEAD、M2 verified 目录和 M7 报告哈希。任何失败都不得上传候选包。

`.github/workflows/resolve-candidate.yml` 只产生待人工审查的 candidate lock；`.github/workflows/build-release.yml` 只上传保留 14 天的候选 ZIP、外部哈希和测试证据。二者默认均为手工触发，GitHub Actions 候选不得直接进入闲鱼交付位。

本地开发可运行：

```powershell
./build/Invoke-QualityGates.ps1 -Mode Developer `
  -PesterModulePath <Pester-5.7.1.psd1> `
  -PSScriptAnalyzerModulePath <PSScriptAnalyzer-1.25.0.psd1> `
  -TestSummaryPath <临时目录>/test-summary.json
```

`-SkipScriptAnalyzer` 只用于开发排错，Formal 模式明确拒绝。Test 模式生成的文件名包含 `TEST-NON-RELEASE`，不能上架。

## M9：全新 Windows 11 x64 人工验收

从候选 ZIP 的精确 SHA-256 开始，按 `evidence/templates/VM-ACCEPTANCE-RUNBOOK.md` 在全新快照完成十二步。截图、录屏、诊断、Defender、卸载、隐私复核和临时 Key 撤销证据必须存在且非空。将模板复制到仓库外证据目录并填写；证据不完整时保持 `pending`。

```powershell
./tools/Test-M9AcceptanceRecord.ps1 `
  -RecordPath <证据目录>/acceptance-record.json `
  -PackagePath <候选目录>/XQ-OpenClaw-Windows-x64-v0.1.0.zip `
  -EvidenceRoot <证据目录>
```

只有门禁通过且有明确人工批准，才计算 acceptance record 自身 SHA-256 并追加 M10 账本。不要把真实测试 Key、原始日志或个人设备截图放入 Git。

## M10：交付位一致性

先填写机器可读商品清单并将状态置为 `ready`，再用 `Update-ReleaseLedger.ps1` 追加精确版本、文件名、ZIP SHA-256 和 M9 记录 SHA-256。历史事件形成可重算哈希链；不得删除、重排或原地修改。同一身份的 `replace` 只能重新绑定完全相同字节；新上游或任何 ZIP 字节变化必须新建 XQ 版本、文件名和完整 M1–M9 记录。

哈希链只有在链头/账本文件被 Git commit、只写对象存储或其他独立不可变记录锚定时才具备篡改证据价值；单独一份可任意重写的 JSON 不能阻止有写权限者重算整条链。每次运营变更后都应立即提交或归档新的账本头哈希。

把文件放入自动交付位后，从交付位重新下载一次，并对实际下载文件执行：

```powershell
./tools/Test-M10Delivery.ps1 `
  -AcceptanceRecordPath <证据目录>/acceptance-record.json `
  -DeliveryZipPath <交付位重新下载的精确版本 ZIP> `
  -LedgerPath <运营目录>/release-ledger.json `
  -ListingManifestPath <运营目录>/product-listing.json `
  -ProductConfigPath ./manifest/product-config.json `
  -LockPath ./manifest/upstream-lock.json `
  -EvidenceRoot <证据目录>
```

暂停或撤回事件立即阻止交付门。交付位文件、M9 记录、approved lock、商品清单或账本任一不一致，都应暂停上架并保留历史证据。
