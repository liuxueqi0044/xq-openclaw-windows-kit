# XQ OpenClaw Windows Kit

面向 Windows 11 x64 普通用户的 OpenClaw 离线中文配置与排错资料包源码。

本仓库不修改、重签或重新封装 OpenClaw 官方二进制。正式发布必须使用经人工批准的精确上游版本锁，并通过来源、SHA-256、Authenticode、离线内容、隐私和虚拟机验收门。

当前源码实现范围：M0–M10。

## 状态

M0–M10 的代码、策略、工作流和证据模板已通过架构复核、62 项 Pester 5.7.1 测试、PSScriptAnalyzer 1.25.0、PowerShell AST/JSON 解析检查、确定性测试打包，以及 Windows PowerShell 5.1 真实只读诊断冒烟测试。

这表示“实现已验收”，不表示“商品已验收”。本仓库仍**不是可上架版本**：尚无人工批准的真实 `upstream-lock.json`、正式 CI 候选、官方安装器实物正向验证、最终正式 ZIP、Windows 11 全流程 VM 证据及闲鱼交付位哈希核验。模板保持 `pending`，测试包带 `TEST-NON-RELEASE` 标记。

## 已实现模块

- M0：产品策略、兼容性与安全基线；
- M1：官方上游候选解析与人工审批前 lock；
- M2：固定资产、GitHub `asset.digest`、Authenticode 与许可证验证；
- M3：完全离线的中文五步引导与售后边界；
- M4：Hub / Managed WSL / Native CLI 分层只读诊断；
- M5：统一结构化脱敏、文本兜底扫描与失败关闭隐私门；
- M6：白名单隔离组装、解压复验和确定性 ZIP；
- M7：固定 Pester/PSScriptAnalyzer 版本的自动质量门；
- M8：只读候选解析与正式候选构建 GitHub Actions；
- M9：Windows 11 x64 十二步人工验收记录、证据与机器门；
- M10：商品清单、不可变哈希链 release ledger、交付一致性门和售后 SOP。

## 开发验证

需要 PowerShell 7、Pester 5.7.1 和 PSScriptAnalyzer 1.25.0：

```powershell
./build/Test-ProductPolicy.ps1
./build/Invoke-QualityGates.ps1 -Mode Developer `
  -PesterModulePath <Pester-5.7.1.psd1> `
  -PSScriptAnalyzerModulePath <PSScriptAnalyzer-1.25.0.psd1>
```

诊断工具面向 Windows PowerShell 5.1 运行；`tools/运行诊断工具.cmd` 只对该次进程使用 ExecutionPolicy Bypass，不修改永久策略。

详细状态见 [`docs/implementation-status-m0-m4.md`](docs/implementation-status-m0-m4.md) 和 [`docs/implementation-status-m5-m10.md`](docs/implementation-status-m5-m10.md)。
