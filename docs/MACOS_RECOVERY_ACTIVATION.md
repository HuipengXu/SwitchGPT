# macOS Recovery Activation 安全契约

本文记录系统登录后唤起 recovery-only 入口的候选设计、签名 app-bundle 验证和 Phase B 即时生命周期结果。仓库同时包含默认只读 host 和隔离的 mutation host；后者已于 2026-08-13 经明确确认执行一次注册和立即卸载。系统当前为 `notRegistered`，没有残留 job、外置 plist 或 recovery 进程。

## 候选结论

当前候选是 app bundle 内的 per-user LaunchAgent，由正式产品未来通过 `SMAppService.agent(plistName:)` 注册。配置文件位于 app bundle 的 `Contents/Library/LaunchAgents`，恢复 executable 位于同一签名 bundle 的 `Contents/Library/LaunchServices`。

没有选择普通 Login Item helper。Apple 的 `SMAppService.register()` 文档明确说明：Login Item helper 在崩溃或非零退出后会被系统重新启动。这与 SwitchGPT 的硬性要求冲突——任何恢复入口都不能因为自身错误形成重启循环。

也没有选择 LaunchDaemon。恢复的是当前登录用户的本机状态，不需要 root 权限或系统级生命周期。

参考：

- [SMAppService.register()](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29)
- [Updating helper executables from earlier versions of macOS](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)
- [Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)

## 严格白名单配置

仓库中的 canonical plist 只允许以下六个键：

- `Label = com.switchgpt.recovery-at-login`
- `BundleProgram = Contents/Library/LaunchServices/SwitchGPTBootRecovery`
- `ProgramArguments = [SwitchGPTBootRecovery, recover-at-login]`
- `RunAtLoad = true`
- `LaunchOnlyOnce = true`
- `LimitLoadToSessionType = Aqua`

`BundleProgram` 使用 app-bundle 相对路径，符合 `SMAppService` 的 bundle 内 helper 布局。`RunAtLoad` 使 agent 在用户登录、job 被加载时运行；`LaunchOnlyOnce` 限制同一启动周期只运行一次。

白名单拒绝任何额外键，包括即使值为 `false` 的 `KeepAlive`。以下触发或重启来源均被测试拒绝：

- `KeepAlive` 及 `SuccessfulExit` / `Crashed` 条件。
- `StartInterval`、`StartCalendarInterval`。
- `WatchPaths`、`QueueDirectories`。
- `MachServices`、`Sockets`。
- `Program` 绝对路径或外部 `BundleProgram`。
- 额外参数、目标身份或目标切换命令。

因此，该配置不能表达周期运行、文件监听、IPC 按需重启或常驻行为。

## Boot Recovery executable

`SwitchGPTBootRecovery` 只接受固定命令 `recover-at-login`。它不能接受目标身份，也没有 begin-switch 入口。

当前 executable 仍是技术验证夹具：它只在显式提供 `SWITCHGPT_SAFETY_ROOT` 时访问系统临时目录下以 `switchgpt-safety-` 开头的夹具；没有该环境变量时返回 `inactive`。仓库路径或其他路径返回 `unsafeState`。它不包含真实 ChatGPT、认证文件或进程适配器。

所有结果都映射为有限枚举：

- `inactive`
- `recovered`
- `terminal`
- `manualRecoveryRequired`
- `unsafeState`
- `invalidInvocation`

进程对所有枚举结果都以状态 0 退出。这样恢复错误不会被表达成要求服务管理器重新启动 executable；安全结果仍通过有限枚举输出，未来应写入权限受限的审计状态，而不是输出原始错误。

## 已验证内容

- canonical XML 与 Swift 生成的配置逐字段一致。
- XML 和 binary plist 均经过同一白名单验证器。
- 12 个配置契约测试覆盖危险键、外部路径、额外参数及布尔类型混淆。
- 5 个 boot-entry 单元测试覆盖无事务、错误命令、终态、重复恢复和损坏状态。
- 跨进程矩阵使用独立 `SwitchGPTBootRecovery` executable 执行重复启动恢复；未完成事务只恢复一次，歧义状态保持人工恢复，已提交事务不回滚。
- 无命令、错误命令、无夹具环境、危险根目录和损坏状态均安全结束，不产生桌面夹具副作用。
- 两个 boot executable 并发执行时仍只有一个报告 `recovered`，原身份只启动一次。
- 桌面夹具子目录被 symlink 到另一个临时根目录时拒绝执行，目标夹具保持零副作用。

## 签名最小 app bundle 离线闸门

`Scripts/build-lifecycle-validation-app.sh` 会在被 `.gitignore` 排除的 `.build/lifecycle-validation/` 中组装 `SwitchGPTLifecycleValidation.app`。该包不是产品 UI，仅包含以下最小结构：

- `Contents/MacOS/SwitchGPTLifecycleHost`：只接受包验证、注册预检和系统状态读取命令，不提供系统变更入口。
- `Contents/Library/LaunchServices/SwitchGPTBootRecovery`：带嵌入式 `Info.plist` 的临时夹具 recovery-only executable。
- `Contents/Library/LaunchAgents/com.switchgpt.recovery-at-login.plist`：canonical 白名单配置。
- `Contents/Info.plist`：固定 bundle identifier、host executable、最低系统版本和 `LSUIElement`。

`LifecycleBundleContract` 对 `Info.plist` 和关键目录使用精确白名单，拒绝额外文件、错误 executable、非普通文件、hard link、symlink helper 和危险 LaunchAgent 键。签名前、签名后均由包内 host 自检。

本机离线验证已通过：

- 使用本机 Apple Development 身份签名，host 与 recovery executable 属于同一非空 Team ID。
- 主包及嵌套 executable 均启用 hardened runtime；没有声明 entitlements。
- `codesign --verify --deep --strict` 通过。
- 注册预检还要求主程序和 helper 的代码标识符精确匹配固定契约；同团队但放错 executable 也会失败关闭。
- 签名 host 只依赖 `status` target；真实 `register()` / `unregister()` 适配器位于不被 host 依赖的独立 target 中。构建脚本对最终 host 执行二进制能力审计，拒绝注册/卸载 selector。
- 源码和脚本没有 `launchctl` 变更路径。
- 未创建系统 job、登录项或已安装 plist；不接触 ChatGPT 或真实认证状态。

Phase B 前本机只读状态为 `notFound`。由于 `notFound` 也可能表示服务不可解析，控制器只有在严格包结构、签名、Team ID 和代码标识符预检全部通过后才把它视为一次注册候选。Phase B 卸载后状态已变为 `notRegistered`。

`spctl` 会拒绝这个本地开发签名包，因为它不是 Developer ID 分发并且没有公证。这不属于签名损坏，也不影响当前仅限本机的离线结构验证；不能把本地开发签名结论外推为可分发状态。

重建本地验证包：

```sh
./Scripts/build-lifecycle-validation-app.sh "Apple Development: …"
```

不传身份时脚本使用 ad-hoc 签名，只适合检查组装流程，不能替代本机 Apple Development 签名结果。

另有隔离的 Phase B 候选构建脚本：

```sh
./Scripts/build-lifecycle-activation-app.sh "Apple Development: …"
```

该脚本只在 `.build/lifecycle-activation/` 生成签名包，不安装、不注册。它使用独立 `SwitchGPTLifecycleActivationHost`，二进制能力审计要求同时存在注册与卸载 selector，并拒绝自动打开系统设置 selector。mutation host 还要求包位于精确的 `~/Applications/SwitchGPTLifecycleValidation.app`、使用显式确认参数、持有同一 Phase B 会话的跨进程互斥锁，并用不可重置的持久 reservation 限制注册和拥有者卸载各一次。默认只读包仍不链接 mutation target。

Phase B 已按 [SMAppService 真实生命周期验证手册](SMAPPSERVICE_VALIDATION_RUNBOOK.md) 在明确确认后执行一次。固定路径候选与已消费 ledger 保留；当前没有 launchd job、外置安装 plist 或 recovery 进程。详细本机证据保存在仓库外的私有验证记录中，公开树不包含该输出；不得重试该阶段。

## Phase C 整机重启投递证据

Phase C 候选先在 `.build/lifecycle-reboot/` 离线验证，随后在明确确认后安装到固定路径并执行一次真实整机重启验证。它沿用相同的严格 bundle 和签名契约，并使用完全不含 ChatGPT 数据的启动周期证据：

- `kern.boottime` 被规范化为仅含数字的启动周期标识。
- 注册 reservation 已耐久落盘后、调用 `register()` 前，写入一次 armed marker。
- helper 在相同启动周期只返回 `armedForReboot`，不会写入投递成功。
- 新启动周期首次执行写入一次 delivered marker。
- 同一启动周期第二次执行写入不可清除的 duplicate marker；后续自动验收全部停止。
- Phase C registration、unregistration、证据写入和 helper 共用同一会话锁与私有 `700/600` ledger。

Apple Development 签名候选已通过严格嵌套签名、相同 Team ID、hardened runtime、无额外 entitlement 和二进制能力审计。真实结果为 `deliveredOnCurrentBoot`、无 duplicate marker、helper 退出，五分钟观察后单次卸载为 `unregistered` 并零残留。离线与本机证据保存在仓库外的私有验证记录中，公开树不包含该输出。

## 仍未验证

- 已完成一次固定路径的 `register()` / `unregister()` 和零残留观察，但没有捕获到 helper 的 `inactive` 日志，不能据此证明实际投递。
- Phase C 已验证无需用户批准时的真实注册、整机重启唯一投递和卸载零残留；尚未验证 `requiresApproval` 分支。
- `LaunchOnlyOnce` 的整机启动周期语义不应被推断为覆盖同一次开机中的注销再登录；当前候选只承诺整机重启恢复，注销场景保持未验证。
- 尚未验证 macOS 更新或 app 升级后 `LaunchOnlyOnce` 的实际生命周期行为。
- boot executable 已在 Phase C 接入只含启动周期证据的真实私有持久目录，但尚未接入真实切换事务或桌面适配器。

签名 app-bundle 闸门、Phase B 即时注册/卸载和 Phase C 整机重启投递均已通过。这仍只是完全不含 ChatGPT 操作的 recovery-only 生命周期证据；不得据此恢复真实 A/B 测试。后续边界见 [SMAppService 真实生命周期验证手册](SMAPPSERVICE_VALIDATION_RUNBOOK.md)。
