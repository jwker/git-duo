import Foundation

/// `GET /user` —— 用访问令牌换回"我是谁"。
///
/// 依据：TECH_SPEC §3.1 步骤 8、§3.6、§4.1。
///
/// **2026-10-06 起改走 `GitHubRESTClient`**（切片 2.6）：本类型再也没有自己的会话、
/// 请求头拼装与状态码判断 —— 那三件事现在只有一处（`HTTPTransport`）。
/// 于是它自动获得了统一版本头、错误归一化、配额闸门，以及**结构性不落盘**的会话。
///
/// ## 它为什么还单独存在
///
/// 因为 `GET /user` 有一个别的端点都没有的处境：**登录第 8 步调用它时，令牌还没进 Keychain**
/// ——"先验证再落盘"是有意的顺序（验证不过就不算登录，宁可没登录也不留半个凭据）。
/// 所以它用 `HTTPRequest.explicitToken` 把令牌**显式**交给 transport，
/// 而不是走 `AccessTokenProviding`（那一刻那里是空的）。
///
/// ## 对外契约仍是 `OAuthError`（兼容层）
///
/// ⚠️ 本类型是切片 1 的产物，调用方 `AuthCoordinator.completeAuthorization` 与已验收的
///    测试都按 `OAuthError` 分支。迁移只换实现、不换契约 —— 所以下面有一张
///    `GitHubError → OAuthError` 的**折返表**。
///    **新端点请直接用 `GitHubRESTClient` 拿 `GitHubError`，不要照抄这个模式**：
///    有了这张表，本包里就同时存在两套错误词汇，它只是为了让一次迁移不惊动上层。
public struct GitHubUserEndpoint: Sendable {

    private let client: GitHubRESTClient

    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    var session: URLSession { client.transport.session }

    public init(client: GitHubRESTClient) {
        self.client = client
    }

    /// 便利构造：默认会话**不挂 `URLCache`**（决策 #32）—— `URLCache` 会把**序列化后的
    /// 请求对象**一并落盘，`Authorization` 头会明文进 `Cache.db`（2026-10-06 真机实测）。
    ///
    /// 缓存显式取 `memoryOnly`：本类型唯一的调用是"一次性验证令牌"，缓存它没有价值，
    /// 而且此处**不该**触碰磁盘 —— 磁盘上的那份应该由 App 层那一个共享缓存负责。
    ///
    /// - Parameter session: 仅测试需要注入桩件（`StubURLProtocol`）。
    public init(credentials: GitHubAppCredentials, session: URLSession? = nil) {
        self.init(
            client: GitHubRESTClient(
                credentials: credentials,
                session: session,
                cache: HTTPResponseCache(configuration: .memoryOnly())
            )
        )
    }

    /// 校验令牌并取回登录名。
    ///
    /// - Throws: `OAuthError.httpStatus(_)`（非 2xx —— **401 表示令牌已失效**）、
    ///           `OAuthError.invalidResponse`（网络层失败 / body 解不出 `login`）。
    public func fetchAuthenticatedUser(accessToken: String) async throws -> AuthenticatedUser {
        do {
            let response = try await client.send(HTTPRequest(
                method: .get,
                url: client.url("user"),
                // 一次性有效性校验：不读也不写缓存（免得把"某枚一次性令牌能用"固化下来）
                cachesResponse: false,
                // 显式令牌：登录窗口里 Keychain 还是空的
                explicitToken: accessToken
            ))
            return try response.decode(AuthenticatedUser.self)
        } catch let error as GitHubError {
            throw Self.legacy(error)
        }
    }

    /// internal：供测试直接断言请求形状，无需起网络桩件。
    func makeRequest(accessToken: String) -> URLRequest {
        client.transport.makeURLRequest(
            HTTPRequest(
                method: .get,
                url: client.url("user"),
                cachesResponse: false,
                explicitToken: accessToken
            ),
            ifNoneMatch: nil,
            token: accessToken
        )
    }

    // MARK: - 兼容层

    /// 把数据层的 `GitHubError` 折回本类型的对外契约 `OAuthError`。
    ///
    /// ⚠️ 这是一张**兼容层**，不是"另一套错误词汇"的正当理由。它存在只是为了让
    ///    切片 2.6 的这次迁移**不惊动**已验收的上层：`AuthCoordinator` 与它的测试
    ///    至今按 `OAuthError` 分支，改契约会把"登录失败怎么办"这条已验证的路径一起掀掉。
    ///
    /// 折返时保住的最关键一点：**401 与 5xx 仍然是两回事** ——
    /// 前者让上层登出，后者绝不（§3.2 第 3 条）。
    static func legacy(_ error: GitHubError) -> OAuthError {
        switch error {
        case .unauthorized:
            return .httpStatus(401)

        case .forbidden, .rateLimited:
            // 权限不足与配额耗尽，GitHub 回的都是 403（§4.5）
            return .httpStatus(403)

        case .notFound:
            return .httpStatus(404)

        case .conflict:
            return .httpStatus(409)

        case .validation:
            return .httpStatus(422)

        case let .serverError(status):
            return .httpStatus(status)

        case .transport, .decoding, .graphQLErrors:
            // 拿不到 HTTP 响应、或响应形状不对 —— `OAuthError` 里对应的是"无法识别的响应"
            // （GraphQL 错误不该从这里冒出来，真冒出来也按"形状不对"处理）
            return .invalidResponse
        }
    }
}
