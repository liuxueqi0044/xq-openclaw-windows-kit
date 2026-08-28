# M9 Windows 11 x64 虚拟机验收手册

本手册是人工验收流程，不是本机已完成验收的声明。开始时必须从全新 Windows 11 x64 快照执行，并把结果填入 `acceptance-record.json`；模板默认 `pending`，任何缺证据都保持 pending/失败关闭。

## 环境与隐私

使用无个人账号、无个人通知、无个人文件的测试 VM；确认 Defender 开启、WSL2/虚拟化可用、磁盘空间足够。使用限额、可撤销的专用测试凭据，严禁把 Key 写入截图、录屏、报告、日志或 Git。

## 十二步记录

1. 计算待测 ZIP SHA-256，与记录中的 `package.sha256` 完全一致。
2. 解压到全新目录，从包内 `guide/00-开始这里.html` 开始，不要求用户使用终端。
3. 检查官方安装器 Authenticode、来源证明和文件哈希。
4. 运行官方 Hub 安装并记录可见成功标志。
5. 在官方 Hub 选择本地设置，确认 `OpenClawGateway` WSL 创建成功。
6. 在官方 Capabilities/Settings 选择最小能力，初次测试不启用 Node Mode、system.run、屏幕、相机、位置、麦克风或随 Windows 启动。
7. 只在官方界面输入临时模型凭据，完成一次无敏感内容基础对话。
8. 运行 XQ 只读诊断，确认 Hub/WSL/CLI 分层与报告脱敏，无上传。
9. 重启 Windows，确认官方 Hub/Gateway/对话入口仍按预期可用。
10. 按官方流程卸载，记录 App、Gateway、WSL 与用户数据的区别。
11. 检查没有 XQ 创建的服务、计划任务、自启动、远控或 Defender 排除项，并扫描 ZIP 与解压目录。
12. 撤销测试 Key；二次复核录屏、截图、诊断和日志，确认秘密扫描为零。

只有十二步全部 `passed`、五张截图及诊断/Defender/卸载证据存在、隐私复核通过、测试 Key 已撤销，机器门禁脚本才允许 `accepted`。本机无法提供上述证据时不得改状态。
