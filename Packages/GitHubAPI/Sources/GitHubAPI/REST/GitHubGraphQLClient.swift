import Foundation

/// GraphQL 客户端 —— **只在四个场景用**（TECH_SPEC §4.1 / §4.6.5）：
/// PR 详情聚合、Issue 详情聚合、贡献热力图、首页置顶仓库。其余一律 REST。
///
/// 与 REST 客户端一样，它**不做网络**，只负责 GraphQL 特有的那层形状：
/// 组装 `{query, variables}`、把 `POST /graphql` 交给 `HTTPTransport`、
/// 然后处理 GraphQL 最容易骗人的那件事 —— **HTTP 200 也可能是失败**。
///
/// ## 三个必须记住的事实
///
/// 1. **错误在 body 里**：返回 `200 OK` 而 `body.errors` 有值。**绝不能只看状态码**。
/// 2. **会部分成功**：`data` 与 `errors` 同时存在 —— 某个子字段解析失败，其余字段照常返回。
///    此时**抛错但要带上已经拿到的数据**（`GitHubError.graphQLErrors(messages:partialData:)`），
///    否则用户看到的是一整页空白，而内容其实就在响应里。
/// 3. **配额按潜在最大节点数预扣**（§13.2），与"实际返回了几条"无关。
///    所以 `first` 要小、别在大连接下面再开连接 —— 那是"莫名烧光配额"的唯一原因。
///
/// ⚠️ GraphQL 走 `POST`，而 `HTTPMethod.isSafelyRetryable` **只认 GET** ⇒ 它不会被
///    自动退避重试。这是有意的：宁可少一层自愈，也不要在"查询带了副作用"时重放
///    （GitHub 的 mutation 同样走这个端点，二者在方法上不可区分）。
public struct GitHubGraphQLClient: Sendable {

    /// 唯一的出网通道。
    public let transport: HTTPTransport

    private let credentials: GitHubAppCredentials

    /// 无变量查询用的占位 —— 编码为 `{}`。
    ///
    /// 为什么不让 `variables` 可空：GitHub 接受 `{"query":"…"}` 也接受
    /// `{"query":"…","variables":{}}`，而后者少一种形状要处理（也少一种两边写法不一致的可能）。
    public struct EmptyVariables: Encodable, Sendable {
        public init() {}
    }

    public init(credentials: GitHubAppCredentials, transport: HTTPTransport) {
        self.credentials = credentials
        self.transport = transport
    }

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

    // MARK: - 查询

    /// 无变量查询。
    public func query<T: Decodable & Sendable>(
        _ queryText: String,
        as type: T.Type
    ) async throws -> T {
        try await query(queryText, variables: EmptyVariables(), as: T.self)
    }

    /// 带变量查询。
    ///
    /// - Parameter variables: 任何 `Encodable` —— 用带类型的结构体而不是
    ///   `[String: Any]`，变量名写错会在**编译期**报出来，而不是运行时被服务端拒。
    /// - Throws: `GitHubError.graphQLErrors(messages:partialData:)`（含部分成功）、
    ///           `GitHubError.decoding`（形状完全不对，既没 `data` 也没 `errors`）。
    public func query<Variables: Encodable & Sendable, T: Decodable & Sendable>(
        _ queryText: String,
        variables: Variables,
        as type: T.Type
    ) async throws -> T {
        let request = try makeRequest(queryText, variables: variables)
        let response = try await transport.send(request)
        return try Self.decode(response.body, as: T.self)
    }

    /// 组装一次 GraphQL 请求。
    ///
    /// ⚠️ 请求体经 `JSONEncoder` 从结构体编码 —— **不手拼 JSON 字符串**：
    ///    查询文本里全是换行与引号，手拼一个引号没转义就是一个只在特定查询下才炸的 bug。
    func makeRequest<Variables: Encodable & Sendable>(
        _ queryText: String,
        variables: Variables
    ) throws -> HTTPRequest {
        let body: Data
        do {
            body = try JSONEncoder().encode(
                RequestBody(query: queryText, variables: variables)
            )
        } catch {
            throw GitHubError.decoding(error)
        }

        return HTTPRequest(
            method: .post,
            url: credentials.apiBaseURL.appendingPathComponent("graphql"),
            body: body,
            // 条件请求与缓存都是 GET 的事（`HTTPTransport` 只对 GET 生效），显式关掉以免误读
            allowsConditionalRequest: false,
            cachesResponse: false,
            rateLimitResource: .graphql
        )
    }

    // MARK: - 响应解析

    /// 把 GraphQL 响应体解析成 `T`，或抛出携带上下文的错误。
    ///
    /// **两段式**（顺序不能反）：
    /// 1. **快路**：直接按 `Envelope<T>` 解码。成功且无 `errors` ⇒ 完事。
    ///    ⚠️ 部分成功时这条**必然失败**（`T` 里那个出错的子字段拿不到）—— 正是我们要的：
    ///       它把控制权交给慢路，那条路才拿得到 `errors` 与"能用的那部分 data"。
    /// 2. **慢路**：改用 `JSONSerialization` 把 `data` / `errors` 都按**原始 JSON** 取出来。
    ///    这一步必须在**不知道 `T` 形状**的前提下做，否则又会因为同一个字段失败而丢掉全部信息。
    static func decode<T: Decodable>(_ body: Data, as type: T.Type) throws -> T {
        if let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: body),
           (envelope.errors ?? []).isEmpty,
           let data = envelope.data {
            return data
        }
        throw failure(from: body)
    }

    /// 慢路：从原始 JSON 里取出 `errors` 与 `data`，拼成最贴切的 `GitHubError`。
    private static func failure(from body: Data) -> GitHubError {
        guard let root = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            return .decoding(
                DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "GraphQL 响应不是 JSON 对象")
                )
            )
        }

        let messages = errorMessages(from: root["errors"])
        if !messages.isEmpty {
            return .graphQLErrors(messages: messages, partialData: rawJSON(root["data"]))
        }

        // 既没有 errors、`data` 又没能按 `T` 解出来 ⇒ 形状不符（GitHub 不该这么回）
        return .decoding(
            DecodingError.dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription: "GraphQL 响应既没有 errors，data 也不符合预期形状"
                )
            )
        )
    }

    /// 逐条错误拼成可读字符串：`path: message`（无 `path` 时只有 `message`）。
    ///
    /// ⚠️ `path` 的元素**可能是字符串也可能是数组下标（数字）**，所以走 `Any` 逐个 `"\($0)"`，
    ///    而不是断言成 `[String]` —— 后者会让"错误里带下标"的情形整条丢失。
    private static func errorMessages(from value: Any?) -> [String] {
        guard let items = value as? [[String: Any]] else { return [] }

        return items.compactMap { item in
            guard let message = item["message"] as? String else { return nil }
            let path = (item["path"] as? [Any])?.map { "\($0)" } ?? []
            return path.isEmpty ? message : "\(path.joined(separator: ".")): \(message)"
        }
    }

    /// 把 `data` 字段原样变成字节供调用方自行解码；`data` 缺失或为 `null` 时返回 `nil`
    /// （即"完全失败"，没有任何可用数据）。
    private static func rawJSON(_ value: Any?) -> Data? {
        guard let value, !(value is NSNull) else { return nil }
        return try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    }

    // MARK: - 解码用的私有形状

    /// 快路用的信封。`errors` 只用来判断"有没有错"，消息正文由慢路负责
    /// —— 因此 `message` 是可选的：**这里绝不能因为一条错误的形状怪而解码失败**。
    private struct Envelope<T: Decodable>: Decodable {
        let data: T?
        let errors: [Entry]?

        struct Entry: Decodable {
            let message: String?
        }
    }

    private struct RequestBody<Variables: Encodable>: Encodable {
        let query: String
        let variables: Variables
    }
}
