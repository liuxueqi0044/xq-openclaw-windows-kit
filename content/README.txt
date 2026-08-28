XQ Windows 配置与排错资料包（适用于 OpenClaw）
====================================================

版本：XQ v0.1.0
上游版本：以包内 SOURCE-AND-VERSION.json / 已批准版本锁为准
支持范围：Windows 11 x64；标准路径为官方 Windows Hub + 本地托管 OpenClawGateway WSL Gateway。

从哪里开始
----------
双击 guide\00-开始这里.html。全部页面、样式和图片（如有）均为本地文件，断网也可阅读。
主流程只有五步：准备与安全 → 安装官方 Hub → 官方 Hub 本地设置 → 用户自行输入凭据并测试对话 → 验证、更新或卸载。

重要边界
--------
- 本资料包由 XQ 制作，不是 OpenClaw 官方商品，不代表官方授权或合作。
- 包内官方安装器保持原样；XQ 不修改、重签或重新封装官方二进制。
- 模型凭据、API Key、密码、验证码和 Cookie 只在官方界面输入，绝不发给卖家或售后。
- OpenClaw、模型、网络和云资源可能分别收费；XQ 不承诺免费、永久、无限或必定兼容。
- XQ 不会自行添加服务、计划任务、开机启动、隐藏服务、远控、第三方插件或遥测。
- 用户在官方 OpenClaw 界面主动开启的官方后台组件属于官方行为，不是 XQ 创建的服务。

只读诊断
--------
运行 tools\运行诊断工具.cmd。它只探测有限的 Windows、Hub、OpenClawGateway WSL 和额外原生 CLI 状态，使用版本、doctor JSON、gateway status JSON 三条只读命令。
每个探针独立超时，失败会变成 finding；报告写入新文件，不覆盖旧文件，不上传、不提权。
工具不读取完整环境变量、配置、会话、浏览器数据、SSH 目录、剪贴板或原始日志。

PowerShell 说明
--------------
CMD 启动器只对本次进程使用 -NoProfile -ExecutionPolicy Bypass，以应对下载 ZIP 的 Mark-of-the-Web；不会永久修改执行策略、关闭 Defender 或添加排除项。OpenClaw-XQ-Diagnose.ps1 全文可检查。

更新、卸载与售后
----------------
更新必须使用新 XQ 包、新版本锁和新来源证明，不用旧证明验证新文件。卸载按官方流程确认 App、Gateway、WSL 与用户数据的区别。
售后只接受已脱敏的必要 finding 和复现步骤；不要发送任何秘密、完整配置或原始日志。
