# SwitchGPT

GitHub: [HuipengXu/SwitchGPT](https://github.com/HuipengXu/SwitchGPT)

SwitchGPT 是一个面向 macOS 的轻量原生工具，用来查看多个 ChatGPT Plus 账号的 Work/Codex 额度，并为未来的完整身份切换保留清晰、安全的实验边界。

项目当前是 **0.1.0-alpha 源码预览**。默认 app 只使用 mock 数据，真实 ChatGPT 身份切换和失败回滚没有接入 UI。源码仓库可以公开供审阅与协作，但在安全的真实 A↔B 验收通过前不会创建公开 tag、GitHub Release 或分发二进制。

开始开发前，请先阅读：

- [Safety Core 设计与测试边界](docs/SAFETY_CORE.md)
- [One-shot Recovery Supervisor 协议](docs/ONE_SHOT_SUPERVISOR.md)
- [macOS Recovery Activation 安全契约](docs/MACOS_RECOVERY_ACTIVATION.md)
- [SMAppService 真实生命周期验证手册](docs/SMAPPSERVICE_VALIDATION_RUNBOOK.md)
- [Phase D 离线升级生命周期](docs/PHASE_D_UPGRADE_LIFECYCLE.md)
- [公开发布合约](docs/PUBLIC_RELEASE.md)
- [真实账号切换验收手册](docs/REAL_ACCOUNT_SWITCH_TEST_RUNBOOK.md)
- [安全政策](SECURITY.md)
- [贡献指南](CONTRIBUTING.md)

## 当前进度与下一步

两个 Plus 账号已分别通过独立 `CODEX_HOME` 并列读取额度，且账号 A 的桌面认证状态在验证前后没有变化。

单次桌面 Codex A→B 和 B→A 身份切换在私有技术验证中曾成功，但故障注入使用的 `launchctl submit` 控制器触发了 KeepAlive 重启循环。该控制器已卸载并隔离，当前客户端安全恢复到账号 A。该私有验证记录和用户特定基线不会进入公开 Git 历史。

2026-08-15 的发布闸门复验再次证明这种 submitted-job 宿主不安全：A→B 元数据验证完成后，恢复阶段出现客户端重复重启，测试被判定失败并人工恢复到 A。两个临时任务均已移除，服务状态回到 `notRegistered`。运行时代码、构建脚本和公开审计现在明确禁止 `launchctl submit`；在全新 supervisor 设计通过纯离线验证前，不再执行真实账号测试。

Phase 0 的自动真实切换安全回滚条件尚未满足。公开 tag 或二进制发布前仍必须完成一次重新设计后的受控真实 A→B→A 验收，覆盖 Chat/Work/Codex 身份、历史任务、失败回滚和会话完整性。源码公开不代表该功能可用。2026-08-13 的 Phase B 已证明唯一次注册/卸载和零残留；2026-08-14 的 Phase C 进一步在真实整机重启后证明了新启动周期唯一投递、五分钟无重复观察和单次卸载零残留。公开仓库只保留不含凭据的安全设计与可复验测试，不发布本机验证日志。

已新增安全专用的 SwiftPM 包：`SwitchGPTSafetyCore` 在临时文件夹具上实现恢复优先的 one-shot 状态机，`SwitchGPTSafetySimulator` 用真实子进程退出和新进程恢复运行故障矩阵。二者与真实 ChatGPT、认证文件和系统启动服务完全隔离；可通过以下命令验证：

```sh
xcrun swift test
xcrun swift run SwitchGPTSafetySimulator matrix
```

当前共有 122 个单元测试；跨进程矩阵覆盖 26 个场景，其中 17 个场景发生真实的异常子进程退出。除既有安全核心外，新增验证 Phase C 启动周期区分、写入一次的武装与投递证据、重复投递永久告警、损坏与 symlink 失败关闭、注册准备失败不发生系统 mutation，以及运行时控制面禁止 submitted-job 控制器。

Phase C Apple Development 签名候选已安装并执行一次真实整机重启验证。验收窗口内结果为 `deliveredOnCurrentBoot`，无 duplicate marker，helper 退出，随后单次卸载并两次证明 `notRegistered` 与零残留。客户端重启时同一账号的凭据发生正常刷新，暴露出“整体认证文件哈希必须不变”过于严格；该问题现在由 Phase D 的无凭据身份指纹与同账号刷新判定覆盖。完成后又发现并修复了矩阵的无夹具隔离缺陷；其写入的真实 duplicate marker 按 write-once 规则保留，系统仍为 `notRegistered` 与零残留。Phase C 的注册/卸载预算均已消费，不得重试；Phase 0 保持 No-Go。

Phase D 已完成离线设计与夹具验证：旧 bundle 只卸载一次，新 bundle 使用独立 artifact 槽位安装，只有注册结果明确指向新 bundle 才提交；失败时保留旧 bundle 并进入人工恢复，不自动重试或删除。该实现仍不连接真实 ChatGPT 或 `SMAppService`，因此不改变 Phase 0 的 No-Go 结论。运行 `./Scripts/run-phase-d-offline-validation.sh` 可重复执行 Phase D 10/10 与跨进程矩阵。

## 当前可运行版本：只读 + 模拟

已加入独立的 `SwitchGPTAppCore` 与 `SwitchGPTApp`：主窗口和菜单栏可以同时看到初始 Personal、Work 以及后来添加的任意数量 mock 账号。顶部摘要显示当前账号的周额度；只有返回数据包含 5 小时窗口时才显示竖线和 5 小时额度。工具栏可添加 mock 账号，非当前 mock 账号可从卡片上下文菜单移除。预览账号和当前选择会保存为不含凭据的本地 mock 元数据；点击非当前账号只会打开确认 sheet，明确显示“no desktop account changed”。

AppCore 同时包含一个未接入默认 UI 的只读 app-server reader：它要求预先 pin 的身份短哈希，并把受限 `CODEX_HOME` staging 到仓库外临时目录后才查询，避免把凭据写回源目录。账号 onboarding 和真实只读数据接线仍需单独验证。

运行方式：

```sh
./script/build_and_run.sh
./script/build_and_run.sh --verify
```

脚本会构建 `dist/SwitchGPT.app`，优先使用本机 Apple Development 身份签名，随后以真正的 macOS app bundle 启动。它只停止同名 SwitchGPT 进程，不接触 ChatGPT、认证文件、launchd 或 `SMAppService`。真实切换仍保留为最后的明确实验功能，未接入当前 UI。即使真实 A↔B 验收通过，公开 alpha 也不会默认为用户执行真实切换。

## Release checklist

创建公开 tag、GitHub Release 或分发二进制前必须完成：

1. 真实 A↔B 受控验收，并保存不含凭据的证据；
2. `xcrun swift test`、26/26 跨进程矩阵和公开仓库审计；
3. 使用 Apple Development 或 Developer ID 身份完成 Release bundle 签名验证；
4. 只把公开源码、测试、文档和脱敏构建材料放入 GitHub，排除用户特定基线、schema 导出和本机日志。

公开源码仓库仅提供 mock/read-only alpha 与安全研究材料；本项目当前没有公开 GitHub Release。

产品介绍站：线上地址为 [website-eight-sandy-66.vercel.app](https://website-eight-sandy-66.vercel.app)，本地运行 `cd website && npm ci && npm run dev`。该站点使用纯黑白的 OpenAI-inspired 编辑风格，但不使用 OpenAI 标识、官方文案或官方关联声明；真实账号切换明确标记为当前版本未包含的实验功能。

本地准备归档时使用 Developer ID Application 身份运行：

```sh
SWITCHGPT_SIGNING_IDENTITY="Developer ID Application: …" \
  ./Scripts/package-release.sh
```
