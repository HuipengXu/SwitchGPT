# SMAppService 真实生命周期验证手册

本文定义完全脱离 ChatGPT Desktop 的 `SMAppService.agent` 验证顺序。目标是证明 recovery-only LaunchAgent 可以被注册、观察、卸载，并且不会形成重复拉起或系统残留。

本文不是执行授权。实际注册会改变当前用户的后台项目状态；只有本节的离线闸门全部通过、真实持久化尝试预算与最小系统变更适配器均经代码审查后，才能执行一次注册。整机重启测试还必须另行获得用户对重启的明确确认。

## 当前状态

- 已生成 Apple Development 签名的 `SwitchGPTLifecycleValidation.app`。
- app 与嵌套 helper 的严格签名、Team ID、代码标识符和精确包结构预检通过。
- Phase B 已于 2026-08-13 经明确确认执行一次：注册观察为 `registeredEnabled`，卸载观察为 `unregistered`。
- Phase C 已于 2026-08-14 经明确确认执行一次：整机重启后为 `deliveredOnCurrentBoot`，无重复投递，随后单次卸载成功。
- Phase C 完成后，旧矩阵的无夹具调试 helper 误读真实 ledger 并写入 duplicate marker；该事件发生在卸载与零残留已证明之后，矩阵已强制临时夹具并恢复 26/26 通过。
- 系统当前只读状态为 `notRegistered`；当前没有外置安装 plist、对应 launchd job 或 recovery 进程。
- 已有独立 target 中的最小 `register()` / `unregister()` 适配器，便于代码审查；验证 host 不依赖或链接该 target。
- one-shot 控制器、并发尝试预算和固定阶段持久 ledger 已经在临时夹具中验证；ledger 没有清除或重置 API，每阶段只能保留一次注册和一次卸载 reservation。
- 默认验证 host 的二进制能力审计拒绝注册/卸载 selector。独立 Phase B host 同时包含且仅包含注册/卸载 selector，不包含自动打开系统设置能力。
- Phase B host 把注册和拥有者清理放在同一个前台命令中；即使注册后的状态不可读、未知或 `notFound`，也会在独立卸载预算内调用一次卸载。
- mutation host 只接受固定 `~/Applications/SwitchGPTLifecycleValidation.app`，拒绝 symlink、其他路径、非当前用户所有或可被组/其他用户写入的安装位置。
- Apple Development 签名 Phase C 候选保留在固定 `~/Applications/SwitchGPTLifecycleValidation.app`；Phase B 和 Phase C ledger 以私有权限保留已消费的 registration 与 unregistration reservation。

因此 Phase B 和 Phase C 均不得重试。系统当前为 `notRegistered`，无外置 plist、launchd job 或 recovery 进程。

## 不变量

整个验证期间必须满足：

1. 不退出、重启或操作 ChatGPT Desktop，不读取或修改它的认证文件。
2. 不把 target identity、认证路径、token、Cookie 或任意 ChatGPT 操作传入 recovery helper。
3. 只使用固定 label `com.switchgpt.recovery-at-login` 和固定命令 `recover-at-login`。
4. 每个验证会话最多保留一次注册尝试和一次卸载尝试；尝试预算必须在调用系统 API 前耐久落盘。
5. `requiresApproval` 是终止自动操作的结果：不重试，不自动打开系统设置。
6. API 报错后只读取一次状态，不轮询，不推断成功，也不自动重试。
7. 在成功证明即时卸载和零残留前，不注销、不重启、不测试升级。
8. 不使用 `launchctl submit`、`KeepAlive`、`sfltool resetbtm` 或循环监控脚本。
9. 注册后不得先移动、覆盖或删除 app；必须先从原 app 实例调用卸载。

## 阶段 A：注册前离线闸门

每项必须同时通过：

```sh
xcrun swift test
xcrun swift run SwitchGPTSafetySimulator matrix
./Scripts/build-lifecycle-validation-app.sh "Apple Development: …"
./Scripts/audit-lifecycle-residue.sh
```

预期证据：

- 121 个单元测试全部通过。
- 26 个跨进程场景全部通过，且并发注册/卸载预算各只有一个进程获得 reservation。
- `validate-bundle = valid`、`registration-preflight = ready`。
- `service-status` 只允许 `notRegistered` 或通过严格预检后的 `notFound`。
- 残留审计的三个布尔值均为 `false`。
- `codesign --verify --deep --strict` 通过；app 与 helper 是同一非空 Team ID。
- helper 代码标识符是 `com.switchgpt.recovery-at-login`，主程序代码标识符是 `com.switchgpt.lifecycle-validation`。
- host 能力审计返回 `mutationSelectorsPresent = false`。
- Phase B 候选能力审计返回注册与卸载 selector 为 `true`，自动打开系统设置 selector 为 `false`。

任一项失败都停止。`notFound` 可能只表示系统尚无后台项目记录，也可能表示服务不可解析，因此它本身绝不是注册许可；必须与完整包结构、签名和标识符预检共同成立。未来系统返回任何未知 status 时统一失败关闭，不得映射为注册候选。

## 阶段 B：即时注册与立即卸载

第一次系统验证只能执行一个同步、显式、前台命令：

1. 将已经验证的 app 安装到一个稳定路径，之后不再移动或覆盖。
2. 记录注册前的只读状态、残留审计和统一日志时间边界。
3. 在整个主验证或应急清理期间持有同一会话的非阻塞跨进程锁，拒绝并发交错。
4. 原子持久化 `registration` 尝试预算。
5. 只调用一次 `SMAppService.agent(plistName:).register()`。
6. API 返回或抛错后只读取一次状态并记录有限枚举。
7. 如果状态为 `requiresApproval`，不请求用户批准；同一个命令立即进入卸载。不得自动重试或打开设置。
8. 如果状态为 `enabled`，只记录有限枚举并立即进入卸载，不等待、不重启。
9. 原子持久化 `unregistration` 尝试预算并只调用一次 `unregister()`。如果注册后的状态读取失败、未知或为 `notFound`，拥有本次 registration reservation 的清理入口仍执行这一次卸载。
10. 读取一次卸载后状态，然后运行残留审计。

即时测试的通过条件是：

- 注册最多调用一次，卸载最多调用一次。
- helper 即使没有夹具环境也只记录一次 `inactive` 并以状态 0 退出。
- 卸载后没有对应 launchd job、安装 plist或 recovery 进程。
- 后续观察窗口内没有新的 recovery helper 启动记录。
- ChatGPT 进程和活动认证文件元数据未变化。

如果卸载未确认，验证立即停止，不进入重启阶段。保留原 app 和尝试记录，不做第二次 API 调用。人工检查系统设置中的“登录项与扩展”，必要时由用户手动关闭对应后台项目；不使用模糊 label 或递归命令清理。

候选构建与安装是分开的。构建不会安装或注册：

```sh
./Scripts/build-lifecycle-activation-app.sh "Apple Development: …"
```

只有获得明确确认后才安装到固定路径并运行包装器：

```sh
./Scripts/install-lifecycle-activation-app.sh --prepare-phase-b-candidate
./Scripts/run-phase-b-immediate-lifecycle.sh --confirm-system-service-mutation
```

包装器会比较执行前后的活动认证文件哈希，只输出 `unchanged` / `changed`，并在执行前、立即卸载后和五秒观察后运行残留审计。如果 mutation host 在拥有 registration reservation 后异常退出，包装器只调用一次受 ownership 与独立预算保护的应急卸载入口。

本次实际结果保存在仓库外的私有验证记录中。注册、卸载和两次零残留观察全部成功，认证哈希未变化。统一日志没有捕获到 helper 的 `inactive` 事件，因此此结果不证明实际投递；投递仍属于 Phase C 的验证目标。公开树不包含本机日志或验证输出。

## 阶段 C：整机重启投递

只有阶段 B 在一次全新验证会话中完整通过后才能安排。本阶段会重启电脑，执行前必须单独获得用户确认，并先确认没有运行中的 Work/Codex 任务。

以下离线合约已在真实系统重启中执行一次：

- `kern.boottime` 只作为非敏感启动周期标识，不包含账号或目标身份。
- 注册预算落盘后、API 调用前写入一次 armed marker；同一启动周期的 helper 只能报告 `armedForReboot`。
- 新启动周期首次投递写入一次 delivery marker；同一周期的第二次投递写入永久 duplicate marker 并失败关闭。
- Phase C host 只有在 `deliveredOnCurrentBoot` 且没有 duplicate marker 时才允许常规卸载。
- 包装器要求 delivery marker 已存在至少五分钟、helper 不在运行、认证哈希不变，才执行一次卸载。

离线候选构建命令不会安装或注册：

```sh
./Scripts/build-lifecycle-reboot-app.sh "Apple Development: …"
```

获得对安装、系统服务变更和整机重启的新确认后，重启前只执行：

```sh
./Scripts/install-lifecycle-reboot-app.sh --prepare-phase-c-candidate
./Scripts/prepare-phase-c-reboot.sh \
  --confirm-system-service-mutation \
  --confirm-reboot-required
```

第二个脚本只武装并注册，不调用任何重启命令。确认没有运行中的 Work/Codex 任务后，由用户单独重启电脑。登录至少五分钟后才运行：

```sh
./Scripts/complete-phase-c-after-reboot.sh --confirm-system-service-mutation
```

1. 重新构建并安装一个未移动的已签名 app，重复阶段 A；已完成的 Phase B 候选被移动到不可执行 mutation 的归档路径，不原位覆盖仍注册的 app。
2. 使用新的耐久会话预算注册一次并确认 `enabled`。
3. 记录日志边界并请求用户确认重启。
4. 重启登录后，观察固定 label 和 `BootRecovery` 日志；不要启动任何目标身份切换。
5. 要求本次启动周期只有一次 helper outcome；无真实恢复状态时必须是 `inactive`。
6. 连续观察至少五分钟，确认没有重新拉起、没有 ChatGPT 副作用。
7. 从原 app 调用一次卸载并完成零残留审计。

注销后重新登录与整机重启不是同一语义。`LaunchOnlyOnce` 在同一次开机中的注销/登录行为保持未验证，不能由整机重启结果外推。

本次实际结果保存在仓库外的私有验证记录中。认证文件在客户端重启后发生同账号凭据刷新，因此原包装器的整文件哈希不变条件失败关闭。email、subject 和 account ID 指纹完全一致；用户看到差异后明确授权了唯一卸载。未来阶段必须在重启前耐久保存无凭据身份指纹，不得仅依赖整文件哈希。公开树不包含本机日志或验证输出。

## 阶段 D：升级生命周期

阶段 C 通过后，已先完成完全脱离系统服务的离线设计与夹具验证；这不是阶段 D 的真实系统执行授权。实现与结果见 [Phase D 离线升级生命周期](PHASE_D_UPGRADE_LIFECYCLE.md)。

离线合约验证：

- 旧 bundle 与候选 bundle 必须使用不同的 artifact 槽位，禁止原位覆盖仍处于注册状态的 bundle。
- 旧服务只允许卸载一次；调用后只观察一次状态。
- 候选包先独立验证，再安装；旧 bundle 在候选安装和注册失败时保持可执行。
- 候选只允许注册一次；`requiresApproval`、状态不确定、身份指纹变化、日志损坏或进程中断都进入 `manualRecoveryRequired`。
- 恢复入口只能观察并补写已经证明的终态，绝不重试注册、卸载、安装或删除旧 bundle。

已完成的离线验证包括：

- 同一账号的凭据刷新只改变认证文件，不改变持久化的 SHA-256 身份指纹。
- 旧服务卸载 → 新包独立安装 → 新服务注册顺序严格成立。
- 候选验证、卸载、安装、注册、审批和恢复中断均有失败关闭测试。
- Phase D 测试 10/10；全量 SwiftPM 测试 121/121；跨进程矩阵 26/26。另有隔离的 UI/mock 与只读协议 AppCore 测试，不接入系统服务。

真实系统阶段仍需单独验证：

- 先卸载旧版本，再替换 app，再注册新版本；不原位覆盖一个仍处于注册状态的 bundle。
- 失败时保留可执行卸载的最后一个已知 app，不留下指向缺失 executable 的服务记录。
- 版本升级测试仍使用 ChatGPT-free helper，不接入真实桌面适配器。

真实 Phase D 尚未授权，不得执行 `SMAppService` 注册/卸载、固定路径 bundle 替换、ChatGPT 操作或新的真实 A/B 测试。

## 失败和紧急停止

出现以下任一情况立即停止自动操作：

- 同一会话出现第二次注册或卸载请求。
- helper 在无新登录/重启的情况下再次启动。
- 状态在 `enabled`、`requiresApproval`、`notFound` 之间异常跳变。
- app、helper 或 plist 的签名、Team ID、代码标识符或结构预检失败。
- 对应 job 无法通过一次卸载消失。
- 任何 ChatGPT 进程、认证元数据或可见登录状态发生变化。

停止后只收集有限枚举日志、精确 label 状态和元数据证据。不得通过循环重试“修复”状态，也不得删除仍可能需要执行卸载的 app。

## 进入真实桌面测试的条件

即使阶段 A–D 全部通过，也只证明 recovery-only 系统激活生命周期，不证明真实 ChatGPT 切换安全。还必须完成真实桌面适配器代码审查、运行中任务检测、完整 Chat/Work/Codex 身份验证和人工恢复手册，并重新获得用户对破坏性 A/B 测试的明确确认。此前 Phase 0 始终为 No-Go。
