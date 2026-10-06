import Foundation
import GitHubAPI

/// 认证编排错误。
///
/// 依据：TECH_SPEC §3.1 / §3.2 / §3.6 / §3.8（取消与失败出口表）。
///
/// ⚠️ 文案红线同 `OAuthError`：**不得包含任何令牌、授权码、`client_secret`**
///    —— 它们会被拼进面向用户的提示，也会进日志。只描述"哪一步失败了"。
public enum AuthError: Error, Equatable, Sendable {

    /// `client_id` / `client_secret` 未配置（`Secrets.xcconfig` 缺失或未注入）
    case notConfigured

    /// 本地没有可用凭据 —— 未登录，或刚被清除
    case notAuthenticated

    /// `refresh_token` 已过期（6 个月）⇒ 必须清除凭据、回登录页（§3.2 第 3 条）
    case refreshTokenExpired

    /// 收到回调，但本地没有等待中的授权（进程重启 / 重复投递）⇒ 丢弃该次 `code`
    case missingAuthorizationContext

    /// 回调形状正确但校验未通过（`state` 不符 / 缺 `code` / GitHub 回传 `error`）
    case callbackRejected(OAuthCallback.FailureReason)

    /// 拿到的令牌**没能安全落进 Keychain** —— 不视为已登录（宁可不登录，也不留半个凭据）
    case credentialStoreFailed

    /// 网络 / 令牌端点的错误，直接透传数据层的 `OAuthError`（不重新发明一套平行错误）
    case oauth(OAuthError)
}

extension AuthError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "未配置 GitHub App 凭据"
        case .notAuthenticated:
            return "尚未登录"
        case .refreshTokenExpired:
            return "登录已过期，请重新授权"
        case .missingAuthorizationContext:
            return "登录请求已失效，请重试"
        case let .callbackRejected(reason):
            return Self.message(for: reason)
        case .credentialStoreFailed:
            return "无法安全保存登录凭据，请重试"
        case let .oauth(error):
            return error.errorDescription
        }
    }

    private static func message(for reason: OAuthCallback.FailureReason) -> String {
        switch reason {
        case .stateMismatch:
            // 不向用户解释 CSRF 细节，但要说清"这次登录没成、请重来"
            return "登录校验未通过，请重新授权"
        case .missingCode:
            return "GitHub 未返回授权码，请重新授权"
        case .missingState:
            return "登录校验信息缺失，请重新授权"
        case let .serviceError(code, _):
            // ⚠️ 只带上 code，不拼 description —— 它可能回显请求参数
            return "GitHub 拒绝了本次授权（\(code)）"
        }
    }
}

extension AuthError {

    /// 该错误是否意味着"**凭据已不可用**"，应清除本地凭据并回登录页（§3.2 第 3 条）。
    ///
    /// ⚠️ 必须与"网络暂时不可用"分开：断网、超时、5xx **都不算**。
    ///    混为一谈的后果是一次地铁断网就把用户登出，重新授权——是明确的体验事故。
    var invalidatesCredentials: Bool {
        switch self {
        case .refreshTokenExpired:
            return true
        case let .oauth(error):
            switch error {
            case .httpStatus(401):
                // 刷新时 401 = refresh token 已被撤销 / 失效
                return true
            case .tokenEndpointError:
                // 令牌端点以 200 回传 `error`（如 bad_refresh_token），同样是"凭据不行了"
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
}
