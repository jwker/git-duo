import Foundation
import GitHubAPI

/// `AuthCoordinator` 对**数据层**的出口：`AccessTokenProviding`（决策 #31 / §4.1）。
///
/// 为什么落在这里而不是让 `App` 层自己包一层：数据层（`HTTPTransport`）在
/// "401 之后该不该刷新"这件事上**必须**知道"拿不到令牌"与"没网"的区别，
/// 而这两件事的真相只有编排层知道。把它接上，是让"断网 ≠ 登出"这条纪律
/// 从"约定"变成"类型上做得到、且单一落点"。
///
/// ## 错误归一化（这是本文件存在的理由）
///
/// `AuthCoordinator` 内部讲的是**细粒度**的 `AuthError`（`notAuthenticated` /
/// `refreshTokenExpired` / `oauth(...)`），而数据层只认识**两分法**的 `GitHubError`：
/// 「凭据不可用 ⇒ 该回去了」与「这次没拿到 ⇒ 别动用户」。
///
/// 两种词汇表都合理 —— 强行合并只会让一边别扭：
/// - 编排层需要细分（`notConfigured` 是打包配置问题，不该提示用户"重新登录"）；
/// - 数据层**不能**细分（它 import 不到 `AuthError`，也不该懂登录流程）。
///
/// 所以归一化只发生在**这一个出口**上，且映射表是显式的（下方 `asGitHubError`），
/// 每一条都有测试守着 —— 一张隐式的映射表，半年后没人说得清某个 case 归到哪边。
///
/// ⚠️ **未知错误一律原样上抛，不做兜底包装**。这不是偷懒：
/// 把不认识的错误包成 `GitHubError.transport` 会**谎称**它是网络问题，
/// 而调用方会据此给出"检查你的网络"这种错误引导。宁可让它以原样冒到最上层
/// （`AuthError` 自带 `LocalizedError` 文案），也不要编一个像模像样的假结论。
extension AuthCoordinator: AccessTokenProviding {}

extension AuthError {

    /// 该错误在**数据层视角**下等价于哪种 `GitHubError`；`nil` 表示"数据层不该改写它，
    /// 原样上抛"。
    ///
    /// 判据只有一条：**重试有没有意义**。
    /// - 有意义的（没网、超时）⇒ 不该出现在这里（那类错误根本不是 `AuthError`），走原样上抛；
    /// - 没意义的（凭据没了、被撤销了）⇒ `.unauthorized`，让上层收摊回登录页。
    var asGitHubError: GitHubError? {
        switch self {
        case .notAuthenticated:
            // 本地一条凭据都没有 —— 刷新一万次也一样，只有重新授权能救
            return .unauthorized

        case .refreshTokenExpired:
            // `refresh_token` 6 个月到期（且 Keychain 已在本包里清掉）⇒ 必须重登（§3.2 第 3 条）
            return .unauthorized

        case let .oauth(error):
            switch error {
            case .httpStatus(401):
                // 刷新时收到 401 = refresh token 已被撤销 / 失效
                return .unauthorized

            case .tokenEndpointError:
                // 令牌端点以 **200** 回传 `error`（如 `bad_refresh_token`）—— 状态码通过 ≠ 成功，
                // 同样是"凭据不行了"。漏掉这一条，用户会卡在"一直刷新、一直失败"里。
                return .unauthorized

            case .missingAccessToken, .missingRefreshToken:
                // 成功路径下的异常数据。尤其 `missingRefreshToken`：本项目**必须**拿到它才能
                // 静默刷新（§3.2），拿不到就等于一次性凭据 ⇒ 只能重登。
                return .unauthorized

            case let .httpStatus(status):
                // 令牌端点回了别的非 2xx（5xx / 403 …）：**服务端或网关的问题**，
                // 不是用户凭据的问题 ⇒ 绝不能报成 unauthorized（那会把用户登出）。
                return .serverError(status: status)

            case .notConfigured, .invalidResponse, .revokeFailed:
                // 配置缺失 / 响应形状看不懂 / 撤销失败：都不是"凭据不可用"，原样上抛
                return nil
            }

        case .notConfigured,
             .missingAuthorizationContext,
             .callbackRejected,
             .credentialStoreFailed:
            // 登录路径上的错误，本不该从令牌供给里冒出来；真冒出来了也原样上抛，
            // 不要在这里替它们编一个"凭据失效"的结论
            return nil
        }
    }
}

extension AuthCoordinator {

    /// 数据层出口的错误归一化 —— **唯一的落点**。
    ///
    /// - `AuthError` ⇒ 查映射表（`asGitHubError`），表里没有就原样抛；
    /// - `URLError` ⇒ `.transport`（断网/超时的**本体**就是它，`GitHubTransport` 的
    ///   `throws GitHubError` 契约靠这一步成立）；
    /// - 其余 ⇒ 原样抛。
    static func asTokenProviderError(_ error: any Error) -> any Error {
        if let authError = error as? AuthError, let mapped = authError.asGitHubError {
            return mapped
        }
        if let urlError = error as? URLError {
            return GitHubError.transport(urlError)
        }
        return error
    }
}
