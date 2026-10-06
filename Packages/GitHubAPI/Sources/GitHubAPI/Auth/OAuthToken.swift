import Foundation

/// 令牌端点返回的一整套令牌。
///
/// 依据：TECH_SPEC §3.1 步骤 7、§3.2。
/// - `expiresIn` = `28800`（8 小时）；`refreshTokenExpiresIn` = `15897600`（约 6 个月）。
/// - ⚠️ GitHub App 用户令牌的 `scope` **恒为空串**——真实权限 = App 声明权限 ∩ 用户权限 ∩ 安装仓库范围，
///   因此**不得**用 `scope` 判断能力（§3.4）。
/// - ⚠️ 本类型是数据层的 DTO；落盘用的是 GitDuoCore 的 `StoredToken`，
///   两者**不共用类型**（GitHubAPI 不得依赖 GitDuoCore）。映射在 App 层完成。
public struct OAuthToken: Sendable, Equatable {

    public let accessToken: String
    public let refreshToken: String
    public let tokenType: String
    /// `access_token` 有效期（秒）
    public let expiresIn: TimeInterval
    /// `refresh_token` 有效期（秒）
    public let refreshTokenExpiresIn: TimeInterval
    public let scope: String

    public init(
        accessToken: String,
        refreshToken: String,
        tokenType: String,
        expiresIn: TimeInterval,
        refreshTokenExpiresIn: TimeInterval,
        scope: String = ""
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.refreshTokenExpiresIn = refreshTokenExpiresIn
        self.scope = scope
    }

    /// 由"当前时刻"推导出两个过期时刻。`now` 显式传入以便测试。
    public func expiries(now: Date) -> (access: Date, refresh: Date) {
        (access: now.addingTimeInterval(expiresIn),
         refresh: now.addingTimeInterval(refreshTokenExpiresIn))
    }
}

/// 令牌端点的**原始**响应形状（含错误分支）。
///
/// ⚠️ 一个容易踩的坑：GitHub 的 `POST /login/oauth/access_token` 在**出错时也可能返回 HTTP 200**，
/// 把错误放在 body 的 `error` / `error_description` 里。因此**不能只看状态码**。
struct TokenEndpointResponse: Decodable {
    var accessToken: String?
    var tokenType: String?
    var expiresIn: Int?
    var refreshToken: String?
    var refreshTokenExpiresIn: Int?
    var scope: String?
    var error: String?
    var errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
        case scope
        case error
        case errorDescription = "error_description"
    }
}
