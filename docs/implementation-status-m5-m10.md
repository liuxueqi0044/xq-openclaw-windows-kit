# M5–M10 实现与验收状态

状态日期：2026-08-28

## 结论

M5–M10 的源码、策略、工作流和模板已完成当前阶段验收；这只允许进入真实候选与人工验收流程，不授权生成或销售正式商品。真实 `upstream-lock.json`、正式候选、VM 证据和交付位均尚未提供，因此 M9/M10 的外部状态保持 pending。

| 模块 | 实现结论 | 独立验证 | 发布前仍需完成 |
|---|---|---|---|
| M5 | 通过 | 统一脱敏模块；125 条语料；嵌套对象、URL 编码、JWT、provider token、Windows 用户路径、幂等和失败关闭 | 对真实 M9 证据再次扫描 |
| M6 | 通过（Test 模式） | 空 staging、精确白名单、reparse/ADS/扩展名限制、固定时间戳与顺序、两次 ZIP 字节相同、解压复验 | 用 approved lock 和真实 M2 verified 输入执行 Formal |
| M7 | 通过 | Pester 5.7.1、PSScriptAnalyzer 1.25.0、报告/覆盖率哈希与 commit 绑定、62/62 测试、关键模块覆盖率 ≥85%、0 finding | 在干净 CI runner 复跑 Formal |
| M8 | 配置通过 | 手工候选与正式候选工作流分离；只读权限；action 固定完整 SHA；上传 ZIP/hash/双份测试证据 | 在 GitHub Actions 对批准 commit 实际运行 |
| M9 | 门禁实现通过 | accepted schema、十二步、日期、五张唯一截图、录屏、非空证据、路径逃逸/reparse/ADS、秘密扫描、Key 撤销和人工批准 | 全新 Windows 11 x64 VM 的真实安装、对话、诊断、重启、卸载与 Defender 证据 |
| M10 | 门禁实现通过 | ready 商品清单、approved lock/产品配置/M9/ZIP 一致性、完整账本哈希链、篡改/重排/暂停/撤回/跨版本隔离 | 实际上架文件重新下载并通过精确 SHA-256 门 |

## Sol 终审修正

- 将 M5 收敛为唯一共享模块，消除诊断脚本的重复脱敏实现，并修复重复脱敏不幂等；
- Formal 构建绑定 clean HEAD、受跟踪的唯一 approved lock、M2 verified 结果和 M7 报告；
- 要求 staged 与 extracted 两阶段复验 provenance、离线引用、秘密、哈希和正式签名；
- 移除默认定时 Actions，避免未授权的私有仓库额度消耗；
- 修复 M9 合法控制字段触发秘密扫描误报，同时保留所有非约束值的原文扫描；
- 修复 release ledger 的非法重新发布和替换漏洞：同名版本不得变更 ZIP 或 M9 审批字节，且追加前重新验证整条链；
- 修复 M10 只看“相关历史事件”而未绑定当前活动 hash 的问题，改为验证当前身份的完整活动快照。

## 验证记录

- Pester 5.7.1：62/62 通过，0 skipped；M5 脱敏与 M10 账本纯逻辑合计命令覆盖率 89.45%（门槛 85%）；
- PSScriptAnalyzer 1.25.0：`build/` 与 `tools/` 共 0 finding；
- PowerShell 7 AST：28 个 `.ps1/.psm1` 文件通过；JSON：31 个文件可解析；
- M0 产品策略语义门通过；
- 两次隔离 Test 打包 ZIP SHA-256 完全一致，条目顺序固定；
- Windows PowerShell 5.1 AST 与真实 CMD 诊断启动器通过；诊断前后 `OpenClawGateway` 保持 stopped，报告通过 M5 最终扫描且不含本机用户名路径。

## 未满足的正式发布条件

1. 审批并提交真实 `manifest/upstream-lock.json`；
2. 对真实官方安装器、GitHub asset.digest、签名、时间戳、许可证和 notices 完成正向 M2 验证；
3. 在 GitHub Actions 由完整 commit SHA 生成正式候选；
4. 对候选的同一 SHA-256 在全新 Windows 11 x64 VM 完成 M9；
5. 在闲鱼自动交付位重新下载正式 ZIP，并让 M10 门禁验证其哈希和活动账本状态。
