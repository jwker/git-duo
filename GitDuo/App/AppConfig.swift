import Foundation

/// App 运行时配置的**唯一读取点**。
///
/// 依据：TECH_SPEC §3.7 / §3.4。
/// - `client_id` 来自 `Secrets.xcconfig`（**git-ignored**）→ build setting → Info.plist；
///   **`client_secret` 永不进入客户端**（无后端 + PKCE 的前提）。
/// - 回调 URL 是**对外契约**：注册后改动需回 GitHub 重配（§3.9）。
enum AppConfig {

    /// GitHub App 的 client_id。本地未配置 `Secrets.xcconfig` 时为空串。
    static var gitHubClientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "GitDuoClientID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 是否已完成凭据配置。未配置时登录页应给出明确提示，而不是发出注定失败的请求。
    static var isConfigured: Bool {
        !gitHubClientID.isEmpty && gitHubClientID != "REPLACE_ME"
    }

    /// 回调 scheme（决策 #15）。⚠️ 裸名 scheme 不符合 RFC 8252 §7.1，收敛方向见 §3.9。
    static let callbackScheme = "gitduo"

    /// 回调完整 URL：`gitduo://oauth/callback`
    static let callbackURL = "gitduo://oauth/callback"

    /// 授权端点（§3.1 步骤 3）
    static let authorizeEndpoint = URL(string: "https://github.com/login/oauth/authorize")!

    /// 换令牌端点（§3.1 步骤 6，**不带 client_secret**）
    static let accessTokenEndpoint = URL(string: "https://github.com/login/oauth/access_token")!

    /// 所有请求必须携带的 API 版本头（§3.6）
    static let apiVersion = "2026-03-10"
}
