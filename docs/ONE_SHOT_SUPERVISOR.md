# One-shot Recovery Supervisor 协议

本文记录已经在临时夹具和签名 app bundle 中验证的 recovery-only helper 协议。当前实现包含默认关闭的真实 ChatGPT 适配器，不安装 `launchd` job，不创建 daemon；嵌入式 helper 覆盖事务进程崩溃，系统重启恢复尚未与真实事务目录接线。

`IndependentSwitchSupervisor` 现在把交互事务入口进一步收紧为两个先决条件：执行器必须是目标 ChatGPT 之外的独立 app，且 recovery-only 进程必须在耐久 `prepared` 状态之后、任何停止客户端动作之前完成就绪。submitted job、嵌入式开发宿主、目标 app 自身、目标 app 内嵌套的 helper、目标 app 祖先进程以及预期 bundle 外的可执行文件都会在持久状态和桌面副作用前被拒绝。

## 已验证协议

事务进程按以下顺序执行：

1. 取得事务目录的独占 `flock`。
2. 耐久持久化 `prepared` 状态及唯一恢复身份。
3. 在仍持有锁时启动一个 recovery-only helper。
4. helper 创建就绪标记，然后阻塞等待同一把独占锁；它不会轮询、重启或调用目标切换入口。
5. 事务进程继续执行并最终释放锁，或者异常退出并由内核释放锁。
6. helper 取得锁后只读取一次耐久状态：终态直接退出；非终态永久切为 `recoveryOnly` 并执行一次受预算约束的回滚。
7. helper 写入完成标记并退出。

交互入口不会直接暴露给未来真实适配器。运行时静态契约要求真实 UI/adapter 只能调用 `IndependentSwitchSupervisor`；底层 `SwitchTransactionEngine.beginSwitch` 仅供 Safety Core、自身 supervisor 和隔离模拟器使用。

这利用了 `flock` 的进程生命周期语义：事务进程无论正常返回还是 `_exit`，文件描述符关闭时锁都会释放。helper 不需要判断事务进程 PID 是否仍存在。

## 跨进程证据

临时夹具矩阵覆盖：

- 正常提交：helper 等到锁释放后读到 `committed`，不执行回滚。
- 事务进程在目标安装后异常退出：helper 取得锁并恢复原身份一次。
- 事务进程在目标启动后异常退出，同时有两个 helper 等待：两个 helper 依次取得锁，但第二个只看到 `rolledBack` 终态；原身份启动总数仍为一次。
- 模拟重启恢复入口连续投递两次：未完成事务只回滚一次；回滚启动预算已消耗的歧义窗口保持停止和 `manualRecoveryRequired`；已提交事务保持目标身份且不执行回滚。

因此，重复 helper 或重复 boot-entry 投递不会放大停止或启动副作用；安全性由持久阶段、启动预算、互斥锁和终态幂等共同提供，而不是依赖“恰好只启动了一个 helper”或“系统恰好只投递一次”。

## 已知边界

- helper 只覆盖事务进程崩溃。Phase C 已在真实 macOS 整机重启后验证 recovery-only helper 唯一投递；它仍未接入真实事务状态或 ChatGPT 适配器。
- 阻塞等待本身没有超时；如果事务进程永久挂起但仍持锁，helper 不会越过锁执行。真实设计需要由独立、可审计的超时策略处理，但不得通过循环拉起客户端实现。
- 真实适配器、认证文件安装器和进程控制器已在 2026-08-16 完成一次真实 A↔B→A；失败回滚的最终身份证据仍需在新授权下用 append-only 终态回执重新验收。
- host evidence 由签名 app 自身从 `Bundle.main`、Security.framework 和进程祖先链采集；主 app 与嵌入 helper 的 Team ID 和 signing identifier 必须通过 strict 校验，UI 不能自声明这些值。
- 已建立受限 LaunchAgent 的静态配置契约、独立 boot executable 和 Phase C write-once 投递证据；签名候选已在真实系统重启中完成唯一投递与零残留验证。详见 `docs/MACOS_RECOVERY_ACTIVATION.md`。

## 真实集成前仍需满足

1. 系统唤起入口只能调用 recovery-only API，不能携带或推导目标身份。
2. 唤起必须有明确消费语义；重复投递只能观察同一终态。
3. 不使用会在正常退出后自动重新拉起事务执行器的 KeepAlive 配置。
4. helper 与主事务都必须受同一全局锁和同一耐久启动预算约束。
5. 先在完全脱离 ChatGPT 的重启夹具中验证，再请求新的真实 A/B 测试确认。
