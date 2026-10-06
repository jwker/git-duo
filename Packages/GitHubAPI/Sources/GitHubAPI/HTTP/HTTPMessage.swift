import Foundation

/// HTTP 方法。
public enum HTTPMethod: String, Sendable, CaseIterable {
    case get = "GET"
    case head = "HEAD"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"

    /// 是否可**自动**重试。
    ///
    /// ⚠️ 这里**只认 GET**，虽然按 HTTP 语义 `PUT` / `DELETE` 也是幂等的。
    /// 原因很具体：仓库内容的写操作并不真的幂等 —— 例如
    /// `PUT /repos/{o}/{r}/contents/{path}` 带同一个 `sha` 提交，
    /// 第二次会因 `sha` 已过期而返回 **409**。自动重试会让用户看到"提交失败"，
    /// 而其实第一次已经成功了 —— 这种"假失败"比不重试危险得多。
    public var isSafelyRetryable: Bool { self == .get }
}

/// 一次请求的描述。
///
/// 只描述"要什么"，不含缓存与令牌的决策 —— 后者由 `HTTPTransport` 统一决定，
/// 这样每个端点都不必（也不可能）各自把缓存策略写歪。
public struct HTTPRequest: Sendable {

    public var method: HTTPMethod
    public var url: URL

    /// 额外的请求头，**覆盖** transport 的默认值（例如 PR diff 要把 `Accept`
    /// 换成 `application/vnd.github.diff`，§4.2）。
    ///
    /// ⚠️ 不要在这里塞 `Authorization` —— 令牌由 transport 统一注入，
    /// 两处都能设就会有人从别的地方拿到令牌（而令牌只该来自 `AccessTokenProviding`）。
    public var headers: [String: String]

    public var body: Data?

    /// 是否需要令牌。默认 `true`；少数端点（如 `GET /rate_limit`）可匿名。
    public var requiresAuthentication: Bool

    /// 是否允许条件请求（GET 默认允许，§5.2）。
    public var allowsConditionalRequest: Bool

    /// 强制跳过缓存、直接要新数据（下拉刷新）。此时**不带** `If-None-Match`，
    /// 也就必然拿到 200。
    public var forcesReload: Bool

    /// 是否把成功响应写进缓存。实时性强的端点（配额查询）应关掉。
    public var cachesResponse: Bool

    /// 写操作成功后要失效的**路径前缀**（§5.4「任意写操作成功 ⇒ 失效该仓库下的相关路径」）。
    ///
    /// 例：提交文件后失效 `/repos/o/r/contents`、`/repos/o/r/commits`、`/repos/o/r/branches`。
    public var invalidatesPathPrefixes: [String]

    /// 本次请求消耗的是**哪个配额桶**（§4.5）。
    ///
    /// ⚠️ 默认 `.core` 是安全的：主桶 5,000/小时并且靠 ETag 压着，不需要人工限速。
    ///    **搜索类请求必须显式声明** —— `search` 是 30/分钟、代码搜索约 10/分钟，
    ///    是全局最紧的两档；声明漏了不会有任何报错，只会安安静静地把配额打爆。
    public var rateLimitResource: RateLimitResource

    /// **显式令牌** —— 绕过 `AccessTokenProviding`，直接把这一枚令牌交给 transport。
    ///
    /// ⚠️ 只有一个合法用途：**登录流程的第 8 步**（`GET /user` 验证刚换到的令牌）。
    ///    那一刻令牌**还没写进 Keychain** —— "先验证再落盘"是有意的顺序（验证不过就不算登录，
    ///    宁可没登录也不留半个凭据），于是 `AccessTokenProviding` 此刻根本供不出它。
    ///
    /// ⚠️ 语义上有两处不同，别当成"另一种带 Authorization 的方式"：
    /// 1. **不会向 `AccessTokenProviding` 要令牌**（优先级最高，给了就用它）；
    /// 2. **401 也不触发刷新** —— 此刻还没有 `refresh_token` 可用，刷新只会白白多一次必败的往返。
    ///
    /// ⚠️ 新端点**不要**用它。它存在的唯一理由是"令牌尚未入库"这个先有鸡还是先有蛋的窗口；
    ///    其余所有请求都该由 transport 从 `AccessTokenProviding` 取令牌
    ///    —— 那样令牌的**出口只有一个**。
    ///
    /// ⚠️ 它只进请求头，绝不出现在 URL、日志或缓存键里（与其余令牌路径同一条纪律）。
    public var explicitToken: String?

    public init(
        method: HTTPMethod,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        requiresAuthentication: Bool = true,
        allowsConditionalRequest: Bool = true,
        forcesReload: Bool = false,
        cachesResponse: Bool = true,
        invalidatesPathPrefixes: [String] = [],
        rateLimitResource: RateLimitResource = .core,
        explicitToken: String? = nil
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.requiresAuthentication = requiresAuthentication
        self.allowsConditionalRequest = allowsConditionalRequest
        self.forcesReload = forcesReload
        self.cachesResponse = cachesResponse
        self.invalidatesPathPrefixes = invalidatesPathPrefixes
        self.rateLimitResource = rateLimitResource
        self.explicitToken = explicitToken
    }

    // MARK: - 便利构造

    public static func get(
        _ url: URL,
        headers: [String: String] = [:],
        forcesReload: Bool = false,
        cachesResponse: Bool = true,
        rateLimitResource: RateLimitResource = .core
    ) -> HTTPRequest {
        HTTPRequest(
            method: .get,
            url: url,
            headers: headers,
            forcesReload: forcesReload,
            cachesResponse: cachesResponse,
            rateLimitResource: rateLimitResource
        )
    }

    public static func sending(
        _ method: HTTPMethod,
        to url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        invalidating paths: [String] = [],
        rateLimitResource: RateLimitResource = .core
    ) -> HTTPRequest {
        HTTPRequest(
            method: method,
            url: url,
            headers: headers,
            body: body,
            invalidatesPathPrefixes: paths,
            rateLimitResource: rateLimitResource
        )
    }
}

/// 一次响应。
public struct HTTPResponse: Sendable {

    public let statusCode: Int
    public let headers: HTTPHeaders
    public let body: Data

    /// 是否来自本地缓存（304 命中）。
    ///
    /// ⚠️ 这个值不是给 UI 看的("正在用缓存"不该显示给用户)，而是给**配额与调试**用的：
    /// 304 不消耗配额(§5.2)，统计命中率时靠它区分。
    public let isFromCache: Bool

    public init(statusCode: Int, headers: HTTPHeaders, body: Data, isFromCache: Bool) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.isFromCache = isFromCache
    }

    /// 本次响应携带的配额快照（头里没有则为 `nil`）。
    public var rateLimit: RateLimitSnapshot? { RateLimitSnapshot(headers: headers) }

    /// 解码响应体。
    ///
    /// - Throws: `GitHubError.decoding` —— 保持与其余错误同类，调用方不必处理两套错误类型。
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: body)
        } catch {
            throw GitHubError.decoding(error)
        }
    }
}
