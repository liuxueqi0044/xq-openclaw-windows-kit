# XQ OpenClaw Windows Kit

面向 Windows 11 x64 普通用户的 OpenClaw 离线中文配置与排错资料包源码。

本仓库不修改、重签或重新封装 OpenClaw 官方二进制。正式发布必须使用经人工批准的精确上游版本锁，并通过来源、SHA-256、Authenticode、离线内容、隐私和虚拟机验收门。

当前已实现范围：M0–M4。

## 状态

M0–M4 已通过架构审查、Pester 5.7.1 自动测试、PowerShell AST/JSON 解析检查，以及 Windows PowerShell 5.1 真实只读诊断冒烟测试。

本仓库仍**不是可上架版本**：尚无人工批准的真实 `upstream-lock.json`，也未完成 M5–M10、最终 ZIP、官方安装器实物验证和 Windows 11 全流程 VM 验收。

## 已实现模块

- M0：产品策略、兼容性与安全基线；
- M1：官方上游候选解析与人工审批前 lock；
- M2：固定资产、checksum、Authenticode 与许可证验证；
- M3：完全离线的中文五步引导与售后边界；
- M4：Hub / Managed WSL / Native CLI 分层只读诊断。

## 开发验证

需要 PowerShell 7 和 Pester 5.7.1：

```powershell
./build/Test-ProductPolicy.ps1
Invoke-Pester -Path ./tests -Output Detailed
```

诊断工具面向 Windows PowerShell 5.1 运行；`tools/运行诊断工具.cmd` 只对该次进程使用 ExecutionPolicy Bypass，不修改永久策略。

详细状态见 [`docs/implementation-status-m0-m4.md`](docs/implementation-status-m0-m4.md)。
