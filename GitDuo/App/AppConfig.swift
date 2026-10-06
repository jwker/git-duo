import Foundation
import GitHubAPI

/// App 运行时配置的**唯一读取点**。
///
/// 依据：`TECH_SPEC` §3.4 / §3.6 / §3.7（决策 #30）。
/// - `client_id` 与 `client_secret` 均来自 `Secrets.xcconfig`（**git-ignored**）→ build setting → Info.plist。
/// - `client_secret` 是**平台强制内嵌**的「**软机密**」：GitHub 不区分 public / confidential 客户端，
///   换令牌时 `client_secret` 为 Required ⇒ 无法规避（§3.1）。它挡得住随手 curl 调接口，
///   **挡不住反编译** ⇒ 只允许出现在「换令牌 / 刷新 / 撤销」三条请求里，
///   **不进日志、不进崩溃上报、不进任何缓存**；**真正的防线是 PKCE + 一次性 `state`**（§3.9）。
/// - 回调 URL 是**对外契约**：注册后改动需回 GitHub 重配（§3.9）。
enum AppConfig {

    /// GitHub App 的 client_id。本地未配置 `Secrets.xcconfig` 时为空串。
    static var gitHubClientID: String { infoValue("GitDuoClientID") }

    /// GitHub App 的 client_secret。**软机密**，仅用于换令牌 / 刷新 / 撤销授权（见类型注释）。
    static var gitHubClientSecret: String { infoValue("GitDuoClientSecret") }

    /// 是否已完成凭据配置。未配置时登录页应给出明确提示，而不是发出注定失败的请求。
    /// ⚠️ 两项都要有：换令牌强制要求 `client_secret`（决策 #30），只填 client_id 会卡在第 6 步。
    static var isConfigured: Bool {
        !isPlaceholder(gitHubClientID) && !isPlaceholder(gitHubClientSecret)
    }

    /// 回调 scheme（决策 #15）。⚠️ 裸名 scheme 不符合 RFC 8252 §7.1，收敛方向见 §3.9。
    static let callbackScheme = "gitduo"

    /// 回调完整 URL：`gitduo://oauth/callback`
    static let callbackURL = "gitduo://oauth/callback"

    /// 所有请求必须携带的 API 版本头（§3.6）
    static let apiVersion = "2026-03-10"

    /// 组装成数据层要的凭据结构 —— 组合根**唯一一次**把配置交给下层的地方。
    ///
    /// ⚠️ 端点的 URL（授权页 / 换令牌 / 撤销 grant）**不在这里定义**：
    ///    它们属于 `GitHubAppCredentials`（`GitHubAPI`），由它按 `client_id` 派生。
    ///    本文件早先也存过一份，两份真相必然漂移（登出端点就是例子）——已删除。
    static var credentials: GitHubAppCredentials {
        GitHubAppCredentials(
            clientID: gitHubClientID,
            clientSecret: gitHubClientSecret,
            callbackURL: callbackURL,
            apiVersion: apiVersion
        )
    }

    private static func infoValue(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        value.isEmpty || value == "REPLACE_ME"
    }
}
