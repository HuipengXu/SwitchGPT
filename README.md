# SwitchGPT

SwitchGPT 是一款面向 macOS 的轻量工具：把你本机使用的多个 ChatGPT 账号放在一个 Dashboard 里，查看套餐、邮箱、Work/Codex 使用额度和当前桌面账号，并在你明确确认后尝试切换 ChatGPT Desktop 的桌面身份。

它适合需要在不同 ChatGPT 账号之间继续 Work/Codex 工作、但不想反复手动查额度和登录的人。账号添加使用官方登录流程；SwitchGPT 不要求你填写 API key，也不是云端账号同步服务。

[下载 macOS 版](https://github.com/HuipengXu/SwitchGPT/releases/download/v0.1.0-alpha.2/SwitchGPT-0.1.0-macOS-arm64.zip) · [查看 Release](https://github.com/HuipengXu/SwitchGPT/releases/tag/v0.1.0-alpha.2) · [产品介绍](https://switchgpt.vercel.app)

> 当前公开版本为 `0.1.0-alpha.2`。它是早期公开测试版；真实的桌面账号切换默认保持实验性质，每次操作都会单独确认。

## 它能做什么

- 在一个 Dashboard 中查看多个本机账号的邮箱、套餐、Work/Codex 周额度和 credits。
- 在菜单栏快速查看额度，并打开账号列表。
- 点击 **Add account**，通过官方登录页面添加另一个账号；登录和验证码由你自己完成。
- 选择目标账号后，经过身份、签名和本地状态检查，再由你确认是否让 ChatGPT Desktop 退出并重新打开一次。
- 切换前要求确认当前没有运行中的 Work/Codex 任务；取消确认或预检失败时不会主动退出 ChatGPT。

## 运行要求

- macOS 14.0 或更高版本。
- Apple silicon Mac（M1、M2、M3、M4 等）。当前公开 ZIP 只提供 `arm64`，不包含 Intel 版本。
- 已安装官方 ChatGPT Desktop，并位于：

  `/Applications/ChatGPT.app`

当前 alpha 版本的添加账号和桌面身份检查依赖这个路径。若 ChatGPT 安装在其他位置，额度查看之外的部分功能可能无法正常工作。

## 安装

### 快速安装（命令合集）

适用于 Apple silicon Mac。整段复制到“终端”执行：

```sh
set -euo pipefail
cd ~/Downloads

curl -fL -O https://github.com/HuipengXu/SwitchGPT/releases/download/v0.1.0-alpha.2/SwitchGPT-0.1.0-macOS-arm64.zip
curl -fL -O https://github.com/HuipengXu/SwitchGPT/releases/download/v0.1.0-alpha.2/SwitchGPT-0.1.0-macOS-arm64.zip.sha256
shasum -a 256 -c SwitchGPT-0.1.0-macOS-arm64.zip.sha256

mkdir -p "$HOME/Applications"
ditto -x -k "SwitchGPT-0.1.0-macOS-arm64.zip" "$HOME/Applications"
open "$HOME/Applications/SwitchGPT.app"
```

### 图形界面安装（简版）

1. 从 [v0.1.0-alpha.2 Release](https://github.com/HuipengXu/SwitchGPT/releases/tag/v0.1.0-alpha.2) 下载 ZIP 和 `.sha256` 文件。
2. 在下载目录执行：

```sh
shasum -a 256 -c SwitchGPT-0.1.0-macOS-arm64.zip.sha256
```

3. 校验显示 `OK` 后，双击 ZIP，把 `SwitchGPT.app` 拖到“应用程序”。
4. 打开 SwitchGPT；首次启动会尝试只读导入当前桌面账号。
5. 点击 **Add account**，在官方登录页面完成登录和双重验证，再回到 SwitchGPT。

这个公开包已经完成 Developer ID 签名和 Apple 公证。macOS 若显示无法验证开发者、文件损坏或签名异常，请先确认下载来源和 SHA-256，不要通过删除隔离属性或关闭 Gatekeeper 来绕过安全检查。

当前 Release 的 SHA-256：

```text
943d1f42637251040d51bf04949757a3effa1c6e921a5a56a3efdc387cf47f40
```

登录过程中不需要把密码、API key 或验证码输入 SwitchGPT。请不要把本地账号目录、认证文件或截图中的敏感信息发到 Issue、聊天或公开仓库。

## 日常使用

### 查看额度

Dashboard 会显示已添加账号的套餐、邮箱、Work/Codex 使用比例和 credits。点击 **Refresh** 可读取最新状态；菜单栏入口也可以快速查看额度和账号列表。

额度是从各账号当前的官方登录状态读取的本地快照，可能受到网络、登录状态和服务端更新延迟影响。它不是对未来可用额度的保证。

### 切换 ChatGPT Desktop 账号

切换是实验功能：

1. 选择目标账号并等待预检完成。
2. 阅读确认框中的源账号、目标账号和重启提示。
3. 保存当前工作，确认没有运行中的 Work/Codex 任务。
4. 明确确认后，ChatGPT Desktop 会退出并重新打开一次。

取消确认不会开始切换。不要在重要任务运行期间尝试，也不要连续重复点击。ChatGPT Desktop 版本变化时，SwitchGPT 可能把当前版本标为未验证并在确认流程中提示风险。

## 卸载和清理本地账号

只卸载应用：退出 SwitchGPT，然后把 `/Applications/SwitchGPT.app` 移到废纸篓即可。卸载不会删除你的 ChatGPT 云端账号或对话。

如果还要删除 SwitchGPT 保存的本地账号档案：

1. 在 Finder 中按 `Command + Shift + G`。
2. 输入 `~/Library/Application Support/SwitchGPT` 并打开。
3. 确认不再需要这些本地账号后，将 `SwitchGPT` 文件夹移到废纸篓。

该目录可能包含用于本机账号管理的认证材料，应像密码一样保护；删除前请确认没有需要保留的账号档案。不要把其中的文件复制到仓库或发给他人。

## 隐私和安全边界

- 账号档案保存在当前 Mac 的本地 Application Support 目录，不上传到 SwitchGPT 服务器。
- 添加账号使用官方登录流程；仓库中没有要求用户粘贴密码、API key、Cookie 或 token 的表单。
- 为了支持桌面身份切换，本地托管档案可能包含认证材料。请保护整个 `~/Library/Application Support/SwitchGPT` 目录，不要分享其中的文件。
- 额度查看和账号添加不等于桌面身份切换；切换始终需要明确操作，并可能退出、重新打开 ChatGPT。
- 这是独立项目，不代表 OpenAI 官方产品、服务或公开背书。

## 常见问题

### 为什么找不到 ChatGPT Desktop？

请先从官方来源安装 ChatGPT Desktop，并确认文件位于 `/Applications/ChatGPT.app`。如果你把它放在其他目录，先移动回“应用程序”后重新打开 SwitchGPT。

### 为什么账号添加一直等待？

确认浏览器中的官方登录已完成，检查网络和 ChatGPT Desktop 是否正常安装，然后在 SwitchGPT 的添加账号区域取消并重新开始。不要在等待时反复点击多个添加入口。

### 为什么看不到额度？

点击 **Refresh**，确认账号仍处于登录状态，并检查网络连接。如果服务端暂时没有返回额度，稍后再试；这不会自动改变桌面账号。

### 为什么切换按钮不可用或被阻止？

通常是目标账号仍在刷新、预检未通过，或者没有确认“当前没有运行中的 Work/Codex 任务”。先保存工作并停止相关任务，再重新从目标账号发起一次切换。

### 切换失败怎么办？

当前流程包含一次性失败恢复路径。出现失败提示后不要手动复制认证文件、删除随机目录或连续重试；先按界面提示等待恢复并重新打开 Dashboard。反馈问题时只提供错误文字、macOS 版本和 SwitchGPT 版本，删除邮箱、token、Cookie、认证文件和本地路径中的个人信息。

## 从源码运行（开发者）

需要 Xcode Command Line Tools 和 Swift 6 工具链：

```sh
git clone https://github.com/HuipengXu/SwitchGPT.git
cd SwitchGPT

xcrun swift test
xcrun swift run SwitchGPTSafetySimulator matrix
./script/build_and_run.sh --verify
```

本地运行官网：

```sh
cd website
npm ci
npm run dev
```

更完整的安全边界、测试说明和贡献约定请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)、[SECURITY.md](SECURITY.md) 以及 [docs/](docs/) 中的文档。

## 许可证

[MIT](LICENSE)
