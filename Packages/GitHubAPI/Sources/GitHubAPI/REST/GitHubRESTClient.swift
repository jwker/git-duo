import Foundation

/// REST 客户端 —— **本包 90% 能力的落点**（TECH_SPEC §4.1）。
///
/// 它本身**不做网络**：所有请求都交给 `HTTPTransport`（统一请求头 / 令牌 / ETag / 401 重放 /
/// 错误归一化 / 配额闸门）。本类型只负责 REST 特有的那层形状：
///
/// - **路径 → URL**（含查询串；`.appendingPathComponent` 的斜杠归一化在这里做一次）
/// - **JSON 解码**（`Decodable` → 领域 DTO 由调用方定义）
/// - **`Link` 头的分页**（`Page<T>`，§4.4）
///
/// ⚠️ **不在这里按资源写方法**（`getUser()` / `listRepos()` …）：那会让本类型变成
///    一个"每加一个页面就得改一次"的巨型文件，而每个方法里的实质内容只有一行 URL。
///    端点各自成结构体（见 `GitHubUserEndpoint` 的做法），共用本客户端。
///
/// ⚠️ **不承载 `isLoading` / `error` / `canLoadMore`**：那是各列表 ViewModel 的 `state`（§4.4）。
///    数据层一旦开始记"加载中"，分页逻辑就没法脱离 UI 单测了。
public struct GitHubRESTClient: Sendable {

    /// 唯一的出网通道。**公开**：调用方经常需要直接用原始请求（diff 原文要换 `Accept`）、
    /// 或者读它的 `cache` 做"本地优先"首屏。
    public let transport: HTTPTransport

    private let credentials: GitHubAppCredentials

    public init(credentials: GitHubAppCredentials, transport: HTTPTransport) {
        self.credentials = credentials
        self.transport = transport
    }

    /// 便利构造：直接按 transport 的参数装配（组合根用这个，少一层嵌套）。
    public init(
        credentials: GitHubAppCredentials,
        tokenProvider: (any AccessTokenProviding)? = nil,
        session: URLSession? = nil,
        cache: HTTPResponseCache = HTTPResponseCache(),
        rateLimiter: RateLimiter = RateLimiter(),
        retryPolicy: RetryPolicy = .standard
    ) {
        self.init(
            credentials: credentials,
            transport: HTTPTransport(
                credentials: credentials,
                tokenProvider: tokenProvider,
                session: session,
                cache: cache,
                rateLimiter: rateLimiter,
                retryPolicy: retryPolicy
            )
        )
    }

    // MARK: - URL 组装

    /// 把 REST 路径（相对 `api.github.com`）拼成完整 URL。
    ///
    /// - Parameter path: 形如 `"user"` / `"repos/apple/swift/contents"`。
    ///   前导斜杠可有可无 —— 两种写法都有人写，谁都以为自己对，所以在这里统一。
    /// - Parameter query: 查询项。**用 `URLQueryItem` 而不是手拼字符串**：
    ///   搜索的 `q` 里全是 `:` `/` 空格，手拼等于自己实现一遍百分号编码，必然出错。
    public func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        let normalized = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let base = credentials.apiBaseURL.appendingPathComponent(normalized)

        guard !query.isEmpty else { return base }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.queryItems = query
        return components?.url ?? base
    }

    // MARK: - 原始请求

    /// 直接发一个自建请求 —— 写操作、换 `Accept` 取原文（diff / patch）都走这里。
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await transport.send(request)
    }

    // MARK: - 读：单对象

    /// `GET` 一个 JSON 对象并解码。
    ///
    /// - Parameter forcesReload: 下拉刷新用。**不带** `If-None-Match` ⇒ 必然拿到 200 与新数据。
    /// - Parameter rateLimitResource: 搜索类端点必须显式传 `.search` / `.codeSearch`，
    ///   否则会把最紧的配额当成主桶来发（§4.5）。
    public func get<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem] = [],
        as type: T.Type,
        forcesReload: Bool = false,
        rateLimitResource: RateLimitResource = .core
    ) async throws -> T {
        let response = try await transport.send(
            .get(
                url(path, query: query),
                forcesReload: forcesReload,
                rateLimitResource: rateLimitResource
            )
        )
        return try response.decode(T.self)
    }

    // MARK: - 读：分页列表

    /// `GET` 一页列表。下一页地址取自响应头 `Link: rel="next"`（§4.4）。
    public func page<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem] = [],
        as type: T.Type,
        forcesReload: Bool = false,
        rateLimitResource: RateLimitResource = .core
    ) async throws -> Page<T> {
        let response = try await transport.send(
            .get(
                url(path, query: query),
                forcesReload: forcesReload,
                rateLimitResource: rateLimitResource
            )
        )
        return try Page(items: response.decode([T].self), headers: response.headers)
    }

    /// 续上一页 —— 直接用上一页的 `nextCursor`（**完整 URL**）。
    ///
    /// ⚠️ 为什么不自己拼 `?page=n`：GitHub 的 `next` 可能带 `?page=` 之外的参数
    ///    （搜索的游标形式就是如此），自己拼会在那些端点上**悄悄翻错页**。
    /// - Parameter rateLimitResource: 与首页保持一致 —— 搜索续页同样占搜索桶。
    public func page<T: Decodable & Sendable>(
        at cursor: URL,
        as type: T.Type,
        rateLimitResource: RateLimitResource = .core
    ) async throws -> Page<T> {
        let response = try await transport.send(.get(cursor, rateLimitResource: rateLimitResource))
        return try Page(items: response.decode([T].self), headers: response.headers)
    }
}
