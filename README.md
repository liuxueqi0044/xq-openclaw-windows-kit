# XQ OpenClaw Windows Kit

[![Build candidate package](https://github.com/liuxueqi0044/xq-openclaw-windows-kit/actions/workflows/build-release.yml/badge.svg)](https://github.com/liuxueqi0044/xq-openclaw-windows-kit/actions/workflows/build-release.yml)
[![Resolve upstream candidate](https://github.com/liuxueqi0044/xq-openclaw-windows-kit/actions/workflows/resolve-candidate.yml/badge.svg)](https://github.com/liuxueqi0044/xq-openclaw-windows-kit/actions/workflows/resolve-candidate.yml)

面向 Windows 11 x64 的 OpenClaw 官方发行物验证、离线中文引导、只读诊断和确定性打包工具链。

Security-focused Windows configuration and diagnostic toolkit for OpenClaw, featuring upstream verification, offline guidance, deterministic packaging, privacy-preserving diagnostics, and automated release gates.

> [!IMPORTANT]
> 这是独立的社区兼容项目，不是 OpenClaw 官方产品或授权发行版。本仓库不修改、重签或冒充 OpenClaw 官方二进制。

## 为什么做这个项目

Windows Agent 安装包的风险不只在“能不能启动”，还包括：

- 下载来源是否真的属于官方仓库；
- 安装器是否与官方 digest、SHA-256 和签名一致；
- 中文教程是否能完全离线阅读；
- 诊断报告是否可能泄露 API Key、Token、用户名或会话内容；
- 同一个版本能否生成内容一致、可追溯的交付 ZIP；
- 自动测试通过以后，是否仍然要求真实 Windows VM 人工验收。

本仓库把这些要求实现为可以测试、可以审计、失败时拒绝发布的 PowerShell 工具链。

## 当前状态

| 范围 | 状态 |
| --- | --- |
| M0–M8 策略、供应链、内容、诊断、隐私、打包、测试和 CI | 已实现 |
| 官方 Windows Hub `v2026.7.1` 上游锁 | 已人工批准并固定 |
| GitHub Actions 候选构建 | 已成功运行 |
| 最终正式 ZIP | 尚未发布 |
| 中英文 Windows 11 x64 全流程 VM 验收 | 待执行 |
| 闲鱼商品上架状态 | 未批准 |

“代码实现完成”不等于“商品已经验收”。缺少真实 VM 证据、最终交付哈希或人工发布批准时，任何候选包都不能宣称为正式商品。

## 发布链路

```text
官方 GitHub Release
        │
        ▼
只读解析候选版本
        │
        ▼
人工审核并固定 upstream-lock.json
        │
        ▼
下载并验证 repository / asset / digest / SHA-256 / Authenticode
        │
        ▼
运行 Pester、静态分析、隐私门和内容门
        │
        ▼
白名单组装与确定性 ZIP
        │
        ▼
Windows 11 x64 双语 VM 人工验收
        │
        ▼
不可变 release ledger 与最终交付哈希核验
```

详细设计见 [架构说明](docs/architecture.md)、[质量门](docs/quality-gates.md)和[发布运行手册](docs/release-runbook.md)。

## 已实现模块

- **M0 产品基线**：支持范围、最小权限和商业承诺边界；
- **M1 候选解析**：只读发现官方 Release，不自动批准；
- **M2 供应链验证**：固定仓库身份、Release、Asset、digest、SHA-256、签名者和许可证；
- **M3 离线内容**：中文五步引导、FAQ、最小权限和售后边界；
- **M4 只读诊断**：Hub / Managed WSL / Native CLI 分层检查；
- **M5 隐私门**：结构化脱敏、文本兜底扫描和失败关闭策略；
- **M6 确定性打包**：显式 allowlist、隔离 staging、解压复验和稳定 ZIP；
- **M7 质量门**：固定 Pester / PSScriptAnalyzer 版本；
- **M8 CI**：只读候选解析与人工触发的正式候选构建；
- **M9 VM 验收**：十二步 Windows 11 x64 人工证据协议；
- **M10 交付治理**：商品清单、release ledger、交付一致性和售后 SOP。

## 仓库结构

```text
build/       上游解析、下载验证、质量门与确定性打包
content/     离线中文指南和售后边界
docs/        架构、ADR、质量门与发布手册
evidence/    VM 验收和发布证据模板
manifest/    产品配置、上游锁与 JSON Schema
policy/      打包、诊断、签名、隐私和发布策略
tests/       单元、集成、隐私、安全与打包测试
tools/       只读诊断、脱敏和交付核验工具
```

## 本地开发验证

环境：

- Windows 11 x64；
- PowerShell 7；
- Pester 5.7.1；
- PSScriptAnalyzer 1.25.0。

```powershell
./build/Test-ProductPolicy.ps1

./build/Invoke-QualityGates.ps1 -Mode Developer `
  -PesterModulePath <Pester-5.7.1.psd1> `
  -PSScriptAnalyzerModulePath <PSScriptAnalyzer-1.25.0.psd1>
```

诊断入口兼容 Windows PowerShell 5.1。`tools/运行诊断工具.cmd` 只为当前诊断进程设置执行参数，不修改系统永久策略。

## 安全和隐私

- 仓库和构建产物不得包含真实 API Key、Token、Cookie、密码、SSH Key、会话或原始日志；
- 诊断工具只读、不提权、不修复、不上传；
- 下载失败、hash 不一致、签名不符合策略或许可证锁不一致时必须失败关闭；
- 构建包只复制显式允许的文件；
- GitHub Actions 使用最小 `contents: read` 权限和固定 action commit；
- 安全问题请遵循 [SECURITY.md](SECURITY.md)，不要在公开 Issue 中提交密钥或私人日志。

`tests/Fixtures` 中的密钥形状、用户路径、邮件地址和 `.exe` 文件均为明确标记的合成测试数据。两个 `.exe` fixture 都是 15 字节的普通测试文本，不是可执行程序，也不是 OpenClaw 安装器。

## 上游与交付边界

- OpenClaw 本体来自其[官方 Windows 仓库](https://github.com/openclaw/openclaw-windows-node)；
- 本仓库不提交官方安装器，不在 GitHub Release 中提供付费交付 ZIP；
- `manifest/upstream-lock.json` 记录经审核的上游版本身份，但不包含用户凭据；
- 上游软件、商标和发行物继续适用各自许可证与权利声明；
- XQ 提供的是配置整理、来源验证、中文引导、诊断和约定范围内的支持。

## 项目许可

本仓库公开用于作品展示和安全审阅，不自动授予复制、修改、再发布或商业销售 XQ 原创代码与内容的许可。详情见 [LICENSE](LICENSE)。

OpenClaw 及构建时获取的第三方组件不受该文件重新许可，仍遵循它们各自的许可证。

## 进一步阅读

- [文档索引](docs/README.md)
- [M0–M4 实现状态](docs/implementation-status-m0-m4.md)
- [M5–M10 实现状态](docs/implementation-status-m5-m10.md)
- [ADR：官方 Hub 与 Managed WSL 路径](docs/adr/0001-primary-hub-managed-wsl-path.md)
- [ADR：只读诊断](docs/adr/0002-read-only-diagnostic-posture.md)
