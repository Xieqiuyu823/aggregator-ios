# Aggregator iOS 客户端

这是 [wzdnzd/aggregator](https://github.com/wzdnzd/aggregator) 的配套 iOS 应用。应用使用 GitHub API 触发工作流、查看运行记录，并保存用户提供的订阅链接；采集、检测及转换仍由 GitHub Actions 执行。它不是 VPN 客户端，不在手机上运行原项目。

## 准备 GitHub 仓库

1. Fork 上游 aggregator 仓库到自己的 GitHub 账号，在 fork 的 **Actions** 页面启用工作流。
2. 准备一个 Gist 和一个具有 Gist 写入权限的令牌。在 fork 的 **Settings → Secrets and variables → Actions** 中添加：
   - `GIST_PAT`：用于写入 Gist 的令牌。
   - `GIST_LINK`：`用户名/gist_id`，例如 `alice/0123456789abcdef`，不是完整 URL。
3. Collect 工作流用于收集并写入 Gist；Refresh 用于刷新已有订阅。如需运行完整的 Process 工作流，还须按[原项目文档](https://github.com/wzdnzd/aggregator/blob/main/README_CN.md)准备配置，并设置 `SUBSCRIBE_CONF` 和所选存储后端需要的 `PUSH_TOKEN`。
4. 在 GitHub Actions 页面先手动运行一次，确认工作流及输出正常。完成后从 Gist 获取目标文件的 Raw URL，并添加到 App 的订阅链接中。订阅结果可能含有敏感信息，请妥善保管链接。

工作流的 dispatch 分支决定使用哪个分支上的工作流定义；当前上游的工作流 checkout 明确指定 `main`，因此实际执行的代码来自 `main`。若在其他分支开发，需自行调整工作流 checkout 配置。GitHub 定时任务可能延迟或暂停，免费额度、权限和仓库设置也可能影响运行。Collect 和 Refresh 使用同一 concurrency group，新任务可能取消正在运行的任务。

## 在 Xcode 中运行

需要 macOS、Xcode 16 或更新版本，以及 iOS 16 或更新版本的模拟器或设备。

1. 打开 `AggregatorApp.xcodeproj`。
2. 真机运行时，在 target 的 **Signing & Capabilities** 选择自己的 Team，并将 Bundle Identifier 改成唯一值。
3. 选择模拟器或设备，运行 `AggregatorApp` scheme。
4. 在 App 中填写 fork 的仓库所有者、仓库名、分支和 GitHub 个人访问令牌。令牌需对该仓库具有 **Actions: read and write** 和 **Contents: read** 权限；令牌与上面用于写入 Gist 的令牌用途不同。选择最小所需权限并设置过期时间。私有仓库、组织策略及 SSO 还可能需要额外授权。
5. 保存后刷新状态，手动触发所需工作流；在 Actions 日志中查看失败详情。

App 使用系统框架，无需下载第三方 SDK。GitHub 令牌和订阅链接存储于设备 Keychain；仓库信息存储在设备本地。请勿将任何令牌提交到仓库、粘贴进 issue 或截图分享。

## 通过 GitHub Actions 构建未签名 IPA

将本 iOS 工程推送到自己的 GitHub 仓库，在该仓库的 Actions 页面启用并手动运行 **Build unsigned iOS IPA**。成功后从运行详情的 Artifacts 下载 `AggregatorApp-unsigned`。工作流使用 macOS 运行器，不需要证书或 Team ID；运行器可用性和使用额度取决于 GitHub 账号及仓库设置。

也可在有 Xcode 的 Mac 上执行 `bash Scripts/build_unsigned_ipa.sh`，产物位于 `build/ipa/AggregatorApp-unsigned.ipa`。脚本检查应用、arm64 架构、签名残留和压缩包完整性，并输出 SHA-256。**未签名 IPA 不能直接安装**，需要先使用有效签名重签。构建工作流所在的 iOS 工程仓库，与 App 操作的 aggregator 工作流仓库可以不同。

## 限制

- GitHub 成功接受触发请求不代表采集成功，最终结果以运行记录和 GitHub Actions 日志为准。
- App 保存一个手动添加的订阅链接，不自动发现工作流的输出，也不处理订阅内容。
- iOS 不负责后台定时采集；请使用 GitHub Actions 的调度。
- 需要能访问 GitHub API。上游修改工作流名称、文件名或接口后，客户端可能需要同步更新。
