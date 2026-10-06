import Foundation

/// GitHub App 的凭据与端点配置。
///
/// 依据：TECH_SPEC §3.1（授权流程）、§3.7（App 标识与配置）、决策 #30。
///
/// ⚠️ **为什么把凭据做成注入的配置结构体**：GitHubAPI 是数据层，**不得反向依赖 App 层**
/// （AGENTS.md 架构铁律）。`AppConfig`（读 Info.plist）住在 App target，
/// 由它在组合根处构造本结构体注入。GitHubAPI 内部**不读任何全局配置**。
///
/// ⚠️ `clientSecret` 是**软机密**（§3.7 / 决策 #30）：只允许随「换令牌 / 刷新 / 撤销」三条请求发出，
/// 不进日志、不进崩溃上报、不进缓存。本类型刻意**不实现 `CustomStringConvertible`**，
/// 也不提供 `description`——避免被 `\\(credentials)` 之类插值无意打印。
public struct GitHubAppCredentials: Sendable, Equatable {

    public var clientID: String
    public var clientSecret: String
    /// 回调 URL —— **对外契约**，与 GitHub App 注册值必须逐字一致（§3.9）
    public var callbackURL: String
    /// 所有 API 请求携带的 `X-GitHub-Api-Version`（§3.6）
    public var apiVersion: String

    public var authorizeEndpoint: URL
    public var accessTokenEndpoint: URL
    public var apiBaseURL: URL

    public static let defaultAuthorizeEndpoint = URL(string: "https://github.com/login/oauth/authorize")!
    public static let defaultAccessTokenEndpoint = URL(string: "https://github.com/login/oauth/access_token")!
    public static let defaultAPIBaseURL = URL(string: "https://api.github.com")!

    public init(
        clientID: String,
        clientSecret: String,
        callbackURL: String,
        apiVersion: String,
        authorizeEndpoint: URL = GitHubAppCredentials.defaultAuthorizeEndpoint,
        accessTokenEndpoint: URL = GitHubAppCredentials.defaultAccessTokenEndpoint,
        apiBaseURL: URL = GitHubAppCredentials.defaultAPIBaseURL
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.callbackURL = callbackURL
        self.apiVersion = apiVersion
        self.authorizeEndpoint = authorizeEndpoint
        self.accessTokenEndpoint = accessTokenEndpoint
        self.apiBaseURL = apiBaseURL
    }

    /// `client_id` 与 `client_secret` 是否都已就位。
    /// ⚠️ 两项**都要**：换令牌强制要求 `client_secret`（决策 #30），只填 `client_id` 会卡在第 6 步。
    public var isConfigured: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty
    }

    /// 撤销整项授权的端点：`DELETE /applications/{client_id}/grant`（§3.6）。
    /// 未配置 `client_id` 时返回 `nil`，调用方直接走"仅清本地"的降级路径。
    public var revokeGrantURL: URL? {
        guard !clientID.isEmpty else { return nil }
        return apiBaseURL.appendingPathComponent("applications/\(clientID)/grant")
    }
}
