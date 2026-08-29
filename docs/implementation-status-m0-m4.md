# M0–M4 实现与验收状态

验收角色：Sol（架构、代码审查、集成与最终把关）  
实现分工：Terra（M0–M2）、Luna（M3–M4）  
状态日期：2026-08-28

## 结论

M0–M4 的源码实现已通过当前阶段验收，可以进入 M5–M10 开发；它们尚不构成可销售 ZIP，也不授权上架。

| 模块 | 当前结论 | 已验证内容 | 尚待发布阶段验证 |
|---|---|---|---|
| M0 | 通过 | Win11 x64 唯一范围、Hub + managed WSL 主路径、schema、G1–G9、命令 allowlist、失败关闭 | 与 M5–M10 的持续一致性 |
| M1 | 代码与离线集成通过 | 固定 repository ID、稳定版筛选、精确资产、candidate 不覆盖 approved lock、恶意 API URI 拒绝 | GitHub API 限流解除后的真实候选解析 |
| M2 | 代码与离线集成通过 | approved lock、GitHub asset.digest 与本地哈希、错误签名/时间戳、许可证、失败无 verified 输出 | 真实官方 EXE 的 Authenticode 与发布 asset.digest 正向验证 |
| M3 | 通过 | 离线资源、五步入口、内部链接、无孤立页面、非官方/费用/凭据/售后/最小权限文案 | 固定上游版本后的界面截图与非技术用户走查 |
| M4 | 通过（停止态路径） | 严格 allowlist、策略篡改拒绝、Hub/WSL/CLI 分层、停止态不启动 WSL、WinPS 5.1、CMD、超时、大输出、脱敏 | 已运行 managed WSL Gateway 内三个只读命令的 VM 验证 |

## Sol 复核中打回并修正的问题

- 将所有测试从系统旧 Pester 3.4 迁移到统一的 Pester 5.7.1；
- 阻止恶意 `ApiBaseUri` 在失败前接收 GitHub Token；
- 保持许可证 API base64 原始字节，不做 UTF-8 往返改写；
- 候选阶段也拒绝无效签名、空发布者、异常指纹和缺失时间戳；
- 诊断策略由“检查禁止词”升级为 executable/arguments/context 精确匹配；
- 增加 running-only WSL guard，确保诊断不会启动已停止的 `OpenClawGateway`；
- 解决外部进程大输出管道死锁与超时返回；
- 修正官方 Hub 实际安装路径 `%LOCALAPPDATA%\OpenClawTray`；
- 对 JSON、camelCase、短 token 和无效 JSON 做统一脱敏；
- 加入最终脱敏幂等门，不把仍需替换的文本写入报告；
- 修复 Windows PowerShell 5.1 对无 BOM 中文脚本的解析失败；
- 将 CMD 启动器固定为 ASCII + CRLF，并修复默认路径初始化；
- 增加最小权限页面入口和“所有指南页面从开始页可达”的检查。

## 已执行证据

- `build/Test-ProductPolicy.ps1`：通过；
- Pester 5.7.1：33 passed / 0 failed / 0 skipped；
- PowerShell AST：所有 `.ps1` / `.psm1` 无解析错误；
- JSON：所有 JSON 文件可解析，M0 策略通过 schema/语义校验；
- Windows PowerShell 5.1 与 CMD 启动器均真实生成可读 TXT；
- 本机真实识别到已签名的 OpenClaw Companion 0.6.12；
- 诊断前后 `OpenClawGateway` 均保持 `Stopped`，证明停止态检查没有启动发行版；
- 报告中的 Windows 用户路径已替换为 `[USER]`。

## 当前阻断项

以下事项完成前不得上架：

1. M5 完整隐私与秘密 corpus；
2. 人工批准的真实 `upstream-lock.json`；
3. 真实上游安装器、GitHub asset.digest、签名、LICENSE 和 notices 正向验证；
4. M6–M8 的确定性打包、完整自动门和 CI；
5. M9 全新 Windows 11 x64 VM 安装、对话、重启、诊断、卸载和 Defender 证据；
6. M10 交付位 ZIP hash 与 VM 批准 hash 一致性。
