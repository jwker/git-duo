import Foundation

/// OAuth 流程错误。
///
/// 依据：TECH_SPEC §3.1 / §3.2 / §3.6 / §3.8（取消与失败出口表）。
///
/// ⚠️ 所有 case 的 `description`（见 `LocalizedError`）**不得包含任何令牌、授权码或 secret**——
/// 它们会被拼进面向用户的文案，也会进日志。只描述"哪一步失败了"。
public enum OAuthError: Error, Equatable {

    /// `client_id` / `client_secret` 未配置（`Secrets.xcconfig` 缺失）
    case notConfigured

    /// 响应不是 HTTP 响应，或 body 结构无法解析
    case invalidResponse

    /// 令牌端点的非 2xx 状态码
    case httpStatus(Int)

    /// 令牌端点以 200 返回的业务错误（`error` / `error_description`）
    case tokenEndpointError(code: String, description: String?)

    /// 响应里没有 `access_token`（成功路径下的异常数据）
    case missingAccessToken

    /// 响应里没有 `refresh_token`（本项目**必须**拿到它才能做静默刷新，§3.2）
    case missingRefreshToken

    /// 撤销授权失败（非 2xx）—— 调用方应**降级但不阻塞**登出（§3.6）
    case revokeFailed(Int)
}

extension OAuthError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "未配置 GitHub App 凭据"
        case .invalidResponse:
            return "GitHub 返回了无法识别的响应"
        case let .httpStatus(code):
            return "GitHub 返回了 HTTP \(code)"
        case let .tokenEndpointError(code, _):
            // ⚠️ 刻意不拼 description：它可能回显请求参数
            return "授权码换取令牌失败（\(code)）"
        case .missingAccessToken:
            return "GitHub 未返回访问令牌"
        case .missingRefreshToken:
            return "GitHub 未返回刷新令牌"
        case let .revokeFailed(code):
            return "撤销 GitHub 侧授权失败（HTTP \(code)）"
        }
    }
}
