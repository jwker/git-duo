import Foundation

/// 数据层向上层**要令牌**的唯一入口。
///
/// ⚠️ **为什么是协议而不是直接调用**：`GitHubAPI` **不能** import `GitDuoAuth`
/// （依赖铁律：`GitDuoAuth` 依赖 `GitHubAPI`，反向依赖会成环）。而"此刻该用哪个令牌"
/// 与"401 之后怎么刷新"只有编排层知道 —— 它才持有 Keychain 与 single-flight 刷新。
/// 所以这里声明协议、由上层实现并注入：依赖方向不变，能力照样用得上。
///
/// 实现者：`GitDuoAuth.AuthCoordinator`（它的 `validAccessToken()` /
/// `forceRefreshAccessToken()` 从一开始就是按这个用途写的，签名逐字一致）。
///
/// ## 错误约定（重要）
///
/// **凭据已失效**（refresh token 过期 / 被撤销 / 本地凭据损坏）时，实现者**必须**
/// 抛 `GitHubError.unauthorized`；其余失败（断网、5xx、超时）**原样抛出**。
///
/// 这不是形式主义 —— 数据层据此决定"要不要把用户踢回登录页"：
/// - 抛 `.unauthorized` ⇒ 凭据真的没救了，登出是对的（§3.2）
/// - 抛别的错误 ⇒ 只是这次拿不到，**断网 ≠ 登出**（§3.2 第 3 条）
///
/// 把这两者混成一个错误，就会出现"飞行模式下冷启动被踢回登录页"这种事。
public protocol AccessTokenProviding: Sendable {

    /// 取一个当下可用的令牌（已进预刷新窗口则先刷新）。
    ///
    /// - Throws: `GitHubError.unauthorized`（凭据失效）；其余错误原样上抛。
    func validAccessToken() async throws -> String

    /// **强制**刷新一次，不看还剩多久。供数据层在收到 401 之后调用（§3.2 第 2 条）。
    ///
    /// ⚠️ 并发调用**必须共享同一次刷新**（single-flight）—— 否则并发 401 会打出
    /// 一串刷新请求，而 GitHub 会轮换 `refresh_token`，抢着用旧值的那些必然互相作废。
    ///
    /// - Throws: 同 `validAccessToken()`。
    func forceRefreshAccessToken() async throws -> String
}
