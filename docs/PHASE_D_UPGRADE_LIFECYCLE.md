# Phase D：离线升级生命周期

Phase D 目前只覆盖 recovery-only helper 的离线夹具验证，不是系统服务变更授权，也不连接 ChatGPT Desktop、真实认证文件、`launchd` 或任何账号切换适配器。

## 目标

验证升级 recovery bundle 时的最小安全顺序：

1. 记录当前账号的无凭据身份指纹与旧/新 bundle 描述。
2. 在覆盖或移动任何 bundle 之前，耐久记录 `prepared` 阶段。
3. 只调用一次旧服务卸载，并只观察一次结果。
4. 旧 bundle 保持可执行，新 bundle 使用不同的 artifact 槽位独立安装。
5. 只调用一次新 bundle 注册，并只观察一次结果。
6. 只有服务明确指向新 bundle、两个 bundle 都可执行时才提交。
7. 任意失败、审批等待、身份变化、损坏日志或中断都进入 `manualRecoveryRequired`，不自动重新注册、卸载、安装或删除旧 bundle。

## 持久化边界

`Sources/SwitchGPTLifecycleContract/UpgradeLifecycle.swift` 提供：

- `StableAccountIdentityFingerprint`：只在内存中接收 provider、account ID、subject 和可选 email，持久化内容只有 SHA-256 指纹；因此同一账号的正常凭据刷新不会被误判为身份变化。
- `StableAccountIdentityFingerprintStore`：`700/600` 私有、写一次的身份基线；不提供重置 API。
- `LifecycleUpgradeJournal`：由独立 marker 文件组成的写一次阶段日志，阶段顺序为 `prepared → oldServiceUnregistered → candidateInstalled → candidateRegistered → committed`。
- `LifecycleBundleDescriptor.artifactID`：明确区分旧包与新包的安装槽位，禁止把 Phase D 降级为原位覆盖。
- `LifecycleUpgradeController.recover`：恢复入口只观察并在已证明新包已注册时补写终态；它不携带目标账号，也不调用注册、卸载或安装重试。

持久化日志只保存 bundle 元数据、枚举阶段、枚举失败原因和哈希指纹，不保存 token、Cookie、密码、`auth.json` 或原始身份字段。

## 验证

```sh
xcrun swift test --filter UpgradeLifecycleTests
```

覆盖 10 个场景：成功顺序、候选包预检失败、旧服务卸载不确定、候选安装失败、注册/审批失败、崩溃后只观察恢复、身份指纹变化、同一 artifact 槽位拒绝和损坏日志失败关闭。

当前结果：Phase D 10/10；全量 SwiftPM 测试 160/160；跨进程 Safety 矩阵 26/26。另有隔离的 AppCore 真实额度、托管登录、终态回执、UI、协议解码和运行时控制面测试，不接入本阶段的系统服务生命周期。

## 未授权范围

以下内容仍然不能执行：

- 对真实 `SMAppService` 做 Phase D 注册/卸载或升级。
- 覆盖或移动固定路径的已安装 bundle。
- 读取或修改 ChatGPT Desktop、`~/.codex/auth.json` 或任何认证目录。
- 重新进行真实 A/B 身份切换、重启或注销登录。

只有完成独立的代码审查、离线包验证、人工恢复演练并获得新的明确系统 mutation 确认后，才可以讨论真实 Phase D；即便如此，也不会解除完整 Chat/Work/Codex 身份切换仍为 No-Go 的结论。当前已获批准的 UI/mock 外壳不扩大本阶段授权。
