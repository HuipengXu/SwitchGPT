# SwitchGPT Safety Core

`SwitchGPTSafetyCore` 是 Phase 0 的纯 Swift 事务状态机。它当前只操作测试夹具，不知道 ChatGPT 路径、真实认证文件、token、`launchd`、进程命令或 UI。配套的 `SwitchGPTSafetySimulator` 只负责在系统临时目录中启动一次性测试子进程，不控制真实客户端。

## 已实现的不变量

- 在任何桌面副作用前，先以 `700/600` 权限持久化原身份作为唯一恢复身份。
- 新切换入口 `beginSwitch` 与重启恢复入口 `recover` 分离。
- `recover` 会永久切换为 `recoveryOnly`，绝不继续或重新发起目标账号切换。
- 每个事务目录只能使用一次，包括已完成事务。
- 使用 `flock` 提供跨进程全局互斥；进程崩溃或系统重启会自动释放锁。
- 目标启动预算最多一次，回滚启动预算最多一次；预算在启动副作用之前落盘。
- 如果在回滚启动预算落盘后崩溃，恢复过程不会猜测或再次启动；无法证明原身份已经运行时进入 `manualRecoveryRequired`。
- 终态恢复幂等，不增加停止或启动次数。
- 持久状态只保存身份标签、阶段、次数和枚举错误原因，不保存原始错误文本或凭据。
- 解码时拒绝空身份、未知 schema、恢复身份不等于原身份或启动预算超过一次的状态。
- 状态使用同目录独占临时文件写入，先同步文件，再原子 `rename`，最后同步事务目录；新建事务目录也同步父目录。
- 持久状态带独立 envelope schema 和 SHA-256 内容校验，拒绝截断、意外篡改和超过 1 MiB 的状态。该校验用于检测损坏，不是抵御同一用户恶意重写的 MAC。
- 事务目录必须是当前用户拥有的 `700` 真目录；状态和锁必须是当前用户拥有、单链接的 `600` 普通文件。symlink、hard link、宽权限或路径替换会在任何桌面副作用前被拒绝。

## 状态恢复原则

新事务可以沿目标路径执行：

`prepared → stoppingForTarget → installingTarget → startingTarget → verifyingTarget → committed`

任何普通失败或进程重启都会进入只恢复路径：

`rollbackStopping → rollbackRestoring → rollbackStarting → rollbackVerifying → rolledBack`

如果无法在硬启动预算内证明恢复完成，则进入 `manualRecoveryRequired` 并停止，不循环重试。

## 当前测试范围

测试使用临时目录中的 `account-a` / `account-b` 标记模拟客户端和系统重启，覆盖：

- 正常单次切换。
- 目标身份验证失败后单次回滚。
- 在准备、安装目标、预占目标启动、目标已启动等阶段崩溃。
- 在预占回滚启动和回滚已启动阶段崩溃。
- 重启后只恢复原身份，不重试目标身份。
- 回滚启动预算耗尽后转人工恢复，不循环。
- 终态恢复幂等。
- 并发事务锁。
- 事务目录不可复用。
- 状态目录、状态文件和锁文件权限。
- 持久状态 schema 与不变量校验。
- 截断、校验和不匹配、超大状态，以及状态/锁/目录的 symlink、hard link 和宽权限拒绝。
- 临时文件同步后、原子替换前的写入失败不会留下新状态或触发桌面副作用。
- 原子替换并同步父目录后的失败会留下可由新实例读取并执行 recovery-only 的耐久状态。

运行：

```sh
xcrun swift test
```

## 跨进程崩溃矩阵

`SwitchGPTSafetySimulator` 将每个场景限制在系统临时目录下、名称以 `switchgpt-safety-` 开头的独立根目录中。它不接受仓库目录或任意路径，不使用 `launchd`，不创建 daemon，也不包含真实 ChatGPT 或认证文件路径。矩阵结束后删除全部夹具。

矩阵使用真正的子进程边界，而不是在同一进程中抛出模拟错误：

- 5 个目标切换检查点、4 个回滚检查点，以及 2 个耐久写入边界通过 `_exit(97)` 异常退出。
- 每次异常退出后，由新启动的恢复子进程调用 recovery-only 入口。
- 验证恢复进程不会再次启动目标身份，目标启动和回滚启动各不超过一次。
- 在回滚启动预算已经持久化、但不能证明启动是否发生的歧义窗口，进入 `manualRecoveryRequired` 并保持停止，不重试。
- 另有正常提交、目标身份验证失败回滚，以及跨进程 `flock` 竞争场景。
- 两个写入边界分别验证：已同步临时状态但尚未 `rename` 时沿旧耐久状态恢复；`rename` 并同步事务目录后沿新耐久状态恢复。
- 预先启动的 recovery-only helper 阻塞等待事务锁：正常提交时只读终态退出，事务进程异常退出时恢复一次；两个 helper 竞争时第二个只读回滚终态，不增加启动次数。
- 模拟系统重启后 recovery-only 入口被连续投递两次：非终态只回滚一次，回滚启动歧义仍保持 `manualRecoveryRequired`，已提交事务不被反向回滚。

运行：

```sh
xcrun swift run SwitchGPTSafetySimulator matrix
```

当前结果为 26/26 场景通过，其中 17 个场景发生真实异常子进程退出；SwiftPM 单元测试为 121/121。boot 场景已调用独立 `SwitchGPTBootRecovery` executable，覆盖无命令、错误命令、无夹具环境、危险根目录、损坏状态、并发执行及内部目录 symlink 逃逸。Phase C 测试进一步验证同期开机不被误认成重启、新开机投递只记录一次、重复投递永久告警、后续开机与损坏证据失败关闭，以及注册武装发生在系统 mutation 之前。Phase D 夹具测试另外覆盖无凭据身份指纹、旧包保留、独立 artifact 槽位、升级失败关闭和恢复入口不重试。AppCore 测试覆盖 mock 额度读取、只读协议解码、模拟切换、超过两个账号的管理以及 `700/600` 本地 mock 状态持久化、损坏 JSON 和 symlink 拒绝。连续运行后没有遗留模拟器进程或临时矩阵目录。

## 尚未证明

- 真实 ChatGPT Desktop 适配器。
- 与真实桌面生命周期集成、能够在进程或系统重启后被可靠唤起的 one-shot supervisor。
- 已完成本地开发签名 Phase C 候选的真实整机重启唯一投递与零残留验证；同一次开机中的注销/再登录和升级生命周期仍未验证。
- Phase D 目前只完成离线夹具验证；真实 bundle 升级、`SMAppService` mutation 和升级后的系统清理仍未验证。
- Chat/Work/Codex 三个可见身份的一致验证。
- 运行中任务检测与用户确认 UI。
- Keychain 凭据封装和临时认证物化。
- 真实客户端版本兼容策略与升级禁用。

因此，`SwitchGPTSafetyCore` 仍只是安全核心和夹具模拟器；可运行的 `SwitchGPTApp` 是另一个完全隔离的 UI/mock 目标。UI/mock 外壳不解除当前 Phase 0 对真实切换的 No-Go。
