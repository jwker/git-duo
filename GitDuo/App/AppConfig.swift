import Foundation

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

    /// 授权端点（§3.1 步骤 3）
    static let authorizeEndpoint = URL(string: "https://github.com/login/oauth/authorize")!

    /// 换令牌端点（§3.1 步骤 6，**必须携带 `client_secret`**）
    static let accessTokenEndpoint = URL(string: "https://github.com/login/oauth/access_token")!

    /// 撤销整项授权（登出时调用，§3.6）：
    /// `DELETE /applications/{client_id}/grant`，Basic Auth 用 `client_id` : `client_secret`。
    /// 未配置 client_id 时返回 nil（调用方直接走"仅清本地"的降级路径）。
    static var revokeGrantURL: URL? {
        guard !gitHubClientID.isEmpty else { return nil }
        return URLComponents(string: "https://api.github.com/applications/\(gitHubClientID)/grant")?.url
    }

    /// 所有请求必须携带的 API 版本头（§3.6）
    static let apiVersion = "2026-03-10"

    private static func infoValue(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        value.isEmpty || value == "REPLACE_ME"
    }
}
