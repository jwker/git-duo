import Foundation

/// 编排层对外的会话状态。
///
/// 依据：TECH_SPEC §3.8 / §8.1。
///
/// 这是**领域侧**的状态，只有"已认证 / 未认证"两态——
/// 「授权中」是 UI 的中间态（App 层的 `AuthState` 有它），编排层不需要知道：
/// 它要么还没拿到凭据，要么已经拿到了。
public enum SessionState: Sendable, Equatable {

    /// 无有效凭据 —— 应展示登录页
    case unauthenticated

    /// 已登录。`login` 是本地数据的命名空间键（§7.2，为将来多账号预留）
    case authenticated(login: String)

    public var login: String? {
        if case let .authenticated(login) = self { return login }
        return nil
    }

    public var isAuthenticated: Bool { login != nil }
}
