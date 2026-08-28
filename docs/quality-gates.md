# M7 自动质量门

构建运行时固定为 PowerShell 7：确定性 ZIP 使用 .NET `Path.GetRelativePath` 和固定的 `ZipArchive` 实现，Windows PowerShell 5.1 不能执行 M6/M7 构建入口。用户运行的诊断工具仍按其自身支持范围处理。

`build/Invoke-QualityGates.ps1` 固定 Pester 5.7.1 与 PSScriptAnalyzer 1.25.0，并在正式门禁中要求后者。`-SkipScriptAnalyzer` 仅允许本地开发排错；不得在 CI、候选产物或发布审批中使用。

当前仅排除三条命名/交互风格规则：`PSUseApprovedVerbs`、`PSUseSingularNouns` 和 `PSUseShouldProcessForStateChangingFunctions`。原因是仓库已有的 `Redact-*`、`*Findings` 等名称构成 M4/M5 已测试的领域接口，而 `New-XqFinding`、`New-XqRedactionContext`、`New-XqGitHubHeaders` 只创建内存对象，不改变外部状态，不适用 `ShouldProcess`。这些例外不关闭语法、安全、自动变量、别名、空 catch、编码或危险命令等规则；新增例外必须先在本文档记录原因、影响范围和移除条件。

`SHA256SUMS.txt` 覆盖每个包内交付文件，唯独不能覆盖自身（否则会形成不可满足的自哈希循环）；ZIP 外部的 `.sha256` 文件覆盖整个 ZIP。

Pester 同时对两个高风险纯逻辑核心启用命令覆盖率门：统一脱敏模块 `XQ.Redaction.psm1` 与不可变发布账本 `Update-ReleaseLedger.ps1`，合计覆盖率必须不低于 85%。JaCoCo 报告的 SHA-256 写入 M7 summary，并由 Formal 打包再次校验；其他依赖真实签名制品或 Windows VM 的路径由 M2、M6 和 M9 独立门覆盖，不能用 fixture 覆盖率替代真实验收。
