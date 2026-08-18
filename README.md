# SwitchGPT

GitHub: [HuipengXu/SwitchGPT](https://github.com/HuipengXu/SwitchGPT)

SwitchGPT 是一个面向 macOS 的轻量原生工具，用来查看多个 ChatGPT 账号的会员等级与 Work/Codex 额度，并在明确、安全的实验边界内切换 ChatGPT Desktop 账号。

项目当前是公开发布的 **0.1.0-alpha.1**。app 会只读导入当前账号，也支持添加任意数量的本机账号；真实切换属于每次均需明确确认的实验功能。2026-08-16 的真实 A→B→A 与独立授权的 B→A→B 失败回滚均已通过，后者由 append-only 私有回执确认最终 B、目标/回滚各启动一次及零生命周期残留。本次 arm64 Release 已完成 Developer ID 签名、Apple 公证、staple、Gatekeeper 与解包复验。公开源码来自经过严格审计的单提交导出树；真实切换仍保持默认关闭并要求每次确认。

开始开发前，请先阅读：

- [Safety Core 设计与测试边界](docs/SAFETY_CORE.md)
- [One-shot Recovery Supervisor 协议](docs/ONE_SHOT_SUPERVISOR.md)
- [macOS Recovery Activation 安全契约](docs/MACOS_RECOVERY_ACTIVATION.md)
- [SMAppService 真实生命周期验证手册](docs/SMAPPSERVICE_VALIDATION_RUNBOOK.md)
- [Phase D 离线升级生命周期](docs/PHASE_D_UPGRADE_LIFECYCLE.md)
- [公开发布合约](docs/PUBLIC_RELEASE.md)
- [macOS 分发与公证](docs/MACOS_DISTRIBUTION.md)
- [真实账号切换验收手册](docs/REAL_ACCOUNT_SWITCH_TEST_RUNBOOK.md)
- [安全政策](SECURITY.md)
- [贡献指南](CONTRIBUTING.md)

## 当前进度与下一步

三个真实账号已通过 app 托管的官方登录与隔离只读额度路径并列验证，套餐可区分 Plus 与 Free。Phase 0 的真实切换安全闸门也已通过：签名独立 app/helper 路径完成 A→B→A，以及单独授权的 B→A→B 失败回滚；每个方向的启动预算均固定为一次，最终身份由不含凭据的 append-only 私有回执确认，且无 transaction、helper 或系统服务残留。

旧版故障注入使用的 `launchctl submit` 控制器曾触发 KeepAlive 重启循环。该机制已永久移除，并由运行时和公开仓库审计共同拒绝。当前实现使用独立 supervisor、首个桌面副作用前就绪的同队 recovery helper、私有快照、原子认证替换与失败恢复。真实切换始终在实际操作前明确标记为实验功能并要求确认；私有验证记录和用户特定基线不会进入公开 Git 历史。

已新增安全专用的 SwiftPM 包：`SwitchGPTSafetyCore` 在临时文件夹具上实现恢复优先的 one-shot 状态机，`SwitchGPTSafetySimulator` 用真实子进程退出和新进程恢复运行故障矩阵。二者与真实 ChatGPT、认证文件和系统启动服务完全隔离；可通过以下命令验证：

```sh
xcrun swift test
xcrun swift run SwitchGPTSafetySimulator matrix
```

当前共有 177 个单元测试；跨进程矩阵覆盖 26 个场景，其中 17 个场景发生真实的异常子进程退出。测试覆盖签名 host 身份、同队 helper、认证文件原子安装与恢复、非阻塞 app 托管登录、会员等级、邮箱与点数解析、活动身份对账、切换前目标账号单独刷新、ChatGPT 已验证/未验证版本分类、symlink/权限拒绝、recovery 就绪顺序，以及运行时控制面禁止 submitted-job 控制器、UI 绕过 supervisor 和非显式公证提交。

Phase C 的一次性整机重启生命周期已经完成并永久消费注册/卸载预算；Phase D 的升级生命周期已完成无 ChatGPT 的离线夹具验证。两者保留为安全设计证据，不会被公开 Release 脚本重新执行。运行 `./Scripts/run-phase-d-offline-validation.sh` 只会重复临时夹具测试和跨进程矩阵。

## 当前可运行版本：真实额度 + 显式确认的实验切换

首次启动若仍是旧 demo 状态，app 会自动导入当前真实账号。点击“Add account”会立即启动官方 OpenAI 网页登录，不再要求填写显示名或描述；SwitchGPT 自动创建并管理权限受限的账号存储，不要求普通用户理解或选择目录。所有额度读取都使用 `refreshToken: false` 并 pin 12 位身份指纹。app 同时读取 `account/read` 的邮箱与套餐类型，在 Dashboard 和菜单栏下拉中直接用邮箱区分账号，并显示 Free、Plus、Pro、Business 等会员等级。顶部 macOS 状态栏仍只显示额度，不显示邮箱；下拉菜单中的长邮箱在中间省略并保留域名，Dashboard 空间不足时同样使用中间截断。旧账号会在下一次只读刷新时自动补齐邮箱。账号数量不设上限；本地 `600` 状态文件保存邮箱、内部路径、会员等级和身份指纹，不保存 token 内容，邮箱值不得进入仓库、日志或公开诊断。

点击菜单栏额度后，可直接在账号列表中选择非当前账号进行切换，不再打开 Dashboard。菜单入口与 Dashboard 共用同一套已验收的真实事务编排：先只读刷新目标账号，再执行签名、身份与私有存储预检，随后要求用户明确确认 ChatGPT 会重启并勾选当前没有运行中的 Work/Codex 任务。取消或预检失败时不会退出 ChatGPT。Dashboard 显示的数据超过五分钟才自动读取；状态栏菜单每次打开都会读取，闲置后台最多每三小时读取一次。

SwitchGPT 不提供独立 Settings 页面；安全确认属于每次真实切换流程本身，而非可被长期关闭的偏好。运行时始终要求固定路径的官方签名 ChatGPT、正确的 Bundle ID、OpenAI Team ID、signing identifier、签名独立的 SwitchGPT host、同队嵌入式 helper 和身份固定的账号文件。精确版本/build 已验证时照常显示；官方签名但尚未验证的版本会在同一份明确确认中标明风险，仍可尝试一次。ChatGPT 重启后无法验证目标身份时，既有 one-shot 事务只会恢复原账号并使用一次回滚启动预算，不会重试目标。签名、路径、身份或私有存储的任何歧义仍会在退出 ChatGPT 前失败关闭。额度查看和添加账号不受版本分类影响；公开版本的支持范围仍必须在 Release 配置和说明中明确。

运行方式：

```sh
./script/build_and_run.sh
./script/build_and_run.sh --verify
```

脚本会构建 `dist/SwitchGPT.app`，嵌入并单独签名 `SwitchGPTRecoverySupervisor`，再以真正的 macOS app bundle 启动。构建/启动脚本只停止同名 SwitchGPT 进程，不接触 ChatGPT、认证文件、launchd 或 `SMAppService`；只有用户完成当次明确确认，真实事务才可能开始。

## Release checklist

公开 GitHub 仓库、创建 tag、GitHub Release 或分发二进制前必须完成：

1. 审计并冻结准确的公开 Git 历史与 Release 配置；
2. `xcrun swift test`、26/26 跨进程矩阵和公开仓库审计；
3. 使用 Developer ID Application 身份签名公开二进制，完成 Apple 公证、staple 与 Gatekeeper 验证（当前 arm64 `0.1.0 (1)` 已通过）；
4. 只把公开源码、测试、文档和脱敏构建材料放入 GitHub，排除用户特定基线、schema 导出和本机日志；
5. 产品负责人已确认当前名称和图标获得 OpenAI 私下授权；仓库不保存私下通信内容，也不暗示 OpenAI 对产品的公开背书。

当前私有 `main` 含有历史验证材料，不能直接改变可见性。工作树干净时运行
`./Scripts/prepare-public-release-repo.sh`，会在 `.build/public-release-repo`
生成无 remote、单提交、白名单来源的候选仓库，并同时执行严格工作树与完整
Git 历史审计；该脚本不会 push、创建 tag 或修改 GitHub 可见性。

品牌发布审查已由产品负责人确认完成，当前名称和图标按已获得的私下授权发布；详见
[品牌发布审查](docs/BRAND_RELEASE_REVIEW.md)。公开仓库使用隔离的单提交脱敏树，
不包含私下授权通信、用户特定基线、协议 schema 或本机日志。

产品介绍站：线上地址为 [website-eight-sandy-66.vercel.app](https://website-eight-sandy-66.vercel.app)，本地运行 `cd website && npm ci && npm run dev`。该站点使用克制的中性色与少量语义色，不使用官方文案或官方关联声明；真实账号切换明确标记为默认关闭的实验功能。

本地准备归档时使用 Developer ID Application 身份运行：

```sh
SWITCHGPT_SIGNING_IDENTITY="Developer ID Application: …" \
  ./Scripts/package-release.sh
```

完整 Developer ID、公证、staple 和 Gatekeeper 流程见 [macOS 分发与公证](docs/MACOS_DISTRIBUTION.md)。`0.1.0 (1)` arm64 产物已获 Apple Notary Service 接受并完成 staple；最终 ZIP 及其解包 app 均通过 `Notarized Developer ID` Gatekeeper assessment、严格签名复验和 SHA-256 校验。
