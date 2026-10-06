import Foundation

/// 本包**所有出网请求**的唯一通道（TECH_SPEC §4.1 的 `HTTPTransport`）。
///
/// 它把六件"每个端点都必须做对、而每个端点都很容易做错"的事收在一处：
/// 1. **统一请求头**（`Accept` / `X-GitHub-Api-Version` / `User-Agent`，§4.2）
/// 2. **令牌注入**（唯一来源是 `AccessTokenProviding`）
/// 3. **ETag 条件请求**（`If-None-Match` → 304 用本地副本、**不计配额**，§5.2）
/// 4. **401 → 刷新 → 重放一次**（§3.2 第 2 条）
/// 5. **错误归一化**（`GitHubError`，§4.3）
/// 6. **配额闸门**（`RateLimiter`，§4.5 处置策略 2）
///
/// 端点自己不碰这些 —— 于是"某个新端点忘了带版本头""某个端点把 401 当成终态"
/// 这类缺陷在结构上就不可能发生。
///
/// ⚠️ 会话**不挂 `URLCache`**（`GitHubURLSession`，决策 #32）：
/// 系统缓存会把序列化请求对象（含 `Authorization` 头）一并落盘。
/// 需要 HTTP 缓存时走本类型自带的 `HTTPResponseCache`。
public struct HTTPTransport: Sendable {

    public typealias Clock = @Sendable () -> Date

    /// 挂起指定时长。注入而非直接 `Task.sleep` —— 重试退避是秒级等待，
    /// 不注入的话每个重试用例都要真的等。
    public typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    /// ⚠️ GitHub 要求带 `User-Agent`，缺失会直接 403。
    public static let userAgent = "GitDuo/2.0 (iOS)"

    private let credentials: GitHubAppCredentials
    private let tokenProvider: (any AccessTokenProviding)?
    /// internal（而非 private）：供测试断言"默认会话不挂 `URLCache`"（决策 #32）。
    let session: URLSession
    private let retryPolicy: RetryPolicy
    private let clock: Clock
    private let sleeper: Sleeper

    /// 配额闸门（§4.5）。默认策略下只有搜索类桶会真的等 —— 主桶间隔为 0。
    private let rateLimiter: RateLimiter

    /// 响应缓存（L2）。
    ///
    /// **公开**是有意的：首屏"本地优先、网络异步补齐"（§13.1 的 ≤1.5s 预算）
    /// 要求调用方能**先**把上次的数据显示出来 —— 那一步不该绕 transport 走一遍
    /// （否则就变成"先发请求再显示"，预算立刻破）。调用方直接读它即可。
    public let cache: HTTPResponseCache

    public init(
        credentials: GitHubAppCredentials,
        tokenProvider: (any AccessTokenProviding)? = nil,
        session: URLSession? = nil,
        cache: HTTPResponseCache = HTTPResponseCache(),
        rateLimiter: RateLimiter = RateLimiter(),
        retryPolicy: RetryPolicy = .standard,
        clock: @escaping Clock = { Date() },
        sleeper: @escaping Sleeper = { seconds in
            guard seconds > 0 else { return }
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.credentials = credentials
        self.tokenProvider = tokenProvider
        self.session = session ?? GitHubURLSession.shared
        self.cache = cache
        self.rateLimiter = rateLimiter
        self.retryPolicy = retryPolicy
        self.clock = clock
        self.sleeper = sleeper
    }

    // MARK: - 发送

    /// 发一次请求，返回归一化后的响应。
    ///
    /// - Throws: `GitHubError`（非 2xx / 网络层 / 解码）；
    ///           `CancellationError`（任务被取消 —— 搜索防抖依赖这条链）。
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let cached = await cachedEntry(for: request)
        let ifNoneMatch = request.allowsConditionalRequest && !request.forcesReload
            ? cached?.etag
            : nil

        var attempt = 0
        var didAttemptTokenRefresh = false

        while true {
            // ⚠️ 取令牌放在 try/catch **之外**（它是循环体的直接子句，不在下面那个 do 里）。
            //    理由：`GitHubError.unauthorized` 有两种来源 ——
            //    ① **服务端**回了 401（令牌确实不行了，值得刷新重放）
            //    ② **本地**取不到凭据（`AccessTokenProviding` 自己抛的）
            //    两者错误类型相同，但②刷新一万次也是同样的失败（连凭据都没有）。
            //    放在 do 外，"本地取不到"就直接抛出，不会误入刷新分支 —— 最初就是这么错的：
            //    测试期望"取不到令牌 ⇒ 一次请求都不发、一次刷新都不做"，实际却刷新了一次。
            let token = try await accessToken(for: request)

            do {
                let (data, http) = try await performThrottled(
                    request,
                    ifNoneMatch: ifNoneMatch,
                    token: token
                )
                return try await finalize(data, http, request: request, cached: cached)
            } catch let error as GitHubError {
                // 401：刷新一次并重放（**只一次** —— §3.2 第 2 条）。
                // ⚠️ 带**显式令牌**的请求不刷新：那种请求只出现在"令牌还没进 Keychain"的登录窗口，
                //    此刻没有 `refresh_token` 可用，刷新必然失败，只会白搭一次往返。
                // ⚠️ 若刷新本身失败，错误从下面这行直接传播出去，**不会再进这个 catch** ——
                //    这正是我们要的：刷新失败要如实上报（凭据失效 ⇒ .unauthorized 让上层登出；
                //    断网 ⇒ transport 错误，上层不得登出）。
                if case .unauthorized = error,
                   !didAttemptTokenRefresh,
                   tokenProvider != nil,
                   request.explicitToken == nil {
                    didAttemptTokenRefresh = true
                    try await forceRefreshToken()
                    continue
                }

                if attempt < retryPolicy.maximumRetries,
                   retryPolicy.allowsRetry(error, request: request) {
                    attempt += 1
                    try await sleeper(retryPolicy.backoff(beforeAttempt: attempt))
                    continue
                }

                throw error
            }
        }
    }

    // MARK: - 单次尝试

    /// 在**配额闸门之内**做一次尝试（§4.5 处置策略 2）。
    ///
    /// 闸门放在"每一次尝试"上，而不是"整个 `send`"上：重试也是一次真实的配额消耗，
    /// 把它挡在闸门外等于给重试开了一条不受限的后门。
    private func performThrottled(
        _ request: HTTPRequest,
        ifNoneMatch: String?,
        token: String?
    ) async throws -> (Data, HTTPURLResponse) {
        guard let bucket = RateLimiter.Bucket(request.rateLimitResource) else {
            // 未知桶：对它的限额一无所知 ⇒ 不猜，也不拦
            return try await perform(request, ifNoneMatch: ifNoneMatch, token: token)
        }

        if bucket.requiresSerialization {
            // 代码搜索：串行 + 间隔（§4.5）
            return try await rateLimiter.withSlot(bucket) {
                try await self.perform(request, ifNoneMatch: ifNoneMatch, token: token)
            }
        }

        try await rateLimiter.acquire(bucket)
        return try await perform(request, ifNoneMatch: ifNoneMatch, token: token)
    }

    private func perform(
        _ request: HTTPRequest,
        ifNoneMatch: String?,
        token: String?
    ) async throws -> (Data, HTTPURLResponse) {
        let urlRequest = makeURLRequest(request, ifNoneMatch: ifNoneMatch, token: token)

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw GitHubError.transport(URLError(.badServerResponse))
            }
            return (data, http)
        } catch let error as GitHubError {
            throw error
        } catch let error as URLError {
            throw GitHubError.transport(error)
        }
    }

    /// 组装 `URLRequest` —— 统一请求头的**唯一**落点。
    func makeURLRequest(_ request: HTTPRequest, ifNoneMatch: String?, token: String?) -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue

        // 默认头（§4.2）
        var headers: [String: String] = [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": credentials.apiVersion,
            "User-Agent": HTTPTransport.userAgent,
        ]
        // 调用方的头覆盖默认（PR diff 要换 Accept；§4.2）
        for (name, value) in request.headers {
            headers[name] = value
        }
        if let body = request.body, request.method != .get, request.method != .head {
            urlRequest.httpBody = body
            // 只在调用方没指定时补 —— 上传二进制时不能用 application/json
            headers["Content-Type"] = headers["Content-Type"] ?? "application/json"
        }

        for (name, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        if let ifNoneMatch {
            urlRequest.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
        }

        // ⚠️ 令牌只在这里注入，且只进请求头 —— 绝不进 URL、绝不进日志
        if let token {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return urlRequest
    }

    private func accessToken(for request: HTTPRequest) async throws -> String? {
        // 显式令牌优先（登录第 8 步：令牌还没进 Keychain，`AccessTokenProviding` 供不出来）
        if let explicit = request.explicitToken { return explicit }
        guard request.requiresAuthentication, let tokenProvider else { return nil }
        return try await tokenProvider.validAccessToken()
    }

    private func forceRefreshToken() async throws {
        guard let tokenProvider else { throw GitHubError.unauthorized }
        _ = try await tokenProvider.forceRefreshAccessToken()
    }

    // MARK: - 收尾（304 / 错误 / 缓存写入 / 写后失效）

    private func finalize(
        _ data: Data,
        _ http: HTTPURLResponse,
        request: HTTPRequest,
        cached: CachedHTTPResponse?
    ) async throws -> HTTPResponse {
        let headers = HTTPHeaders(response: http)
        let key = CacheKey(request.url)

        // 304：服务端说"你那份还是最新的"。用本地副本，**不消耗配额**（§5.2）
        if http.statusCode == 304, let cached {
            // 刷新 fetchedAt：否则这条会一直"看起来过期"，下次又白问一遍
            let refreshed = CachedHTTPResponse(
                statusCode: cached.statusCode,
                headers: cached.headers,
                body: cached.body,
                // 304 也可能带回新的 ETag，优先用它
                etag: headers["etag"] ?? cached.etag,
                fetchedAt: clock()
            )
            await cache.store(refreshed, for: key)

            return HTTPResponse(
                statusCode: cached.statusCode,
                headers: cached.headers,
                body: cached.body,
                isFromCache: true
            )
        }

        if let error = GitHubError.from(
            status: http.statusCode,
            headers: headers,
            body: data,
            now: clock()
        ) {
            throw error
        }

        // 2xx：写缓存（仅 GET，且调用方没关掉）
        if request.method == .get, request.cachesResponse {
            await cache.store(
                CachedHTTPResponse(
                    statusCode: http.statusCode,
                    headers: headers,
                    body: data,
                    etag: headers["etag"],
                    fetchedAt: clock()
                ),
                for: key
            )
        }

        // 写操作成功 ⇒ 失效相关路径（§5.4）
        for prefix in request.invalidatesPathPrefixes {
            await cache.invalidate(pathPrefix: prefix)
        }

        return HTTPResponse(
            statusCode: http.statusCode,
            headers: headers,
            body: data,
            isFromCache: false
        )
    }

    private func cachedEntry(for request: HTTPRequest) async -> CachedHTTPResponse? {
        guard request.method == .get, request.cachesResponse, !request.forcesReload else {
            return nil
        }
        return await cache.entry(for: CacheKey(request.url))
    }
}
