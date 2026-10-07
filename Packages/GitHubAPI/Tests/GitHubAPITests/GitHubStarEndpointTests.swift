import Foundation
import Testing

@testable import GitHubAPI

/// Star / 取消 Star —— TECH_SPEC §4.6.2、§4.6.4、§4.13。
///
/// 三条容易被当成"细节"、实际会伤人的东西：
/// 1. 两个端点都回 **204 且没有响应体** ⇒ 绝不解码，否则"Star 成功"会变成"解码失败"；
/// 2. `isStarred` 用 **204 / 404** 表达"已 Star / 没 Star"（404 在这里不是"仓库不存在"）；
/// 3. 写操作之后**必须失效两份缓存**，否则本地 ±1 会被缓存里的旧响应打回原值。
@Suite("GitHubStarEndpoint · Star 写操作")
struct GitHubStarEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEndpoint(
        harness: StubURLProtocol.Harness,
        cache: HTTPResponseCache
    ) -> GitHubStarEndpoint {
        let clock = now
        return GitHubStarEndpoint(
            client: GitHubRESTClient(
                credentials: credentials,
                transport: HTTPTransport(
                    credentials: credentials,
                    session: harness.makeSession(),
                    cache: cache,
                    retryPolicy: .none,
                    clock: { clock },
                    sleeper: { _ in }
                )
            )
        )
    }

    private func makeKey(_ urlString: String) -> CacheKey {
        CacheKey(URL(string: urlString)!)
    }

    private func makeCachedResponse() -> CachedHTTPResponse {
        CachedHTTPResponse(
            statusCode: 200,
            headers: HTTPHeaders([:]),
            body: Data(#"{"stargazers_count":2341}"#.utf8),
            etag: "W/\"abc\"",
            fetchedAt: now
        )
    }

    // MARK: - 请求形状

    @Test("star：PUT /user/starred/{owner}/{repo}")
    func starUsesPut() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 204))

        try await makeEndpoint(harness: harness, cache: HTTPResponseCache(configuration: .memoryOnly()))
            .star(owner: "misoge", repo: "paneltkit")

        let request = try #require(harness.lastRequest)
        #expect(request.httpMethod == "PUT")
        #expect(
            request.url?.absoluteString == "https://api.github.com/user/starred/misoge/paneltkit",
            "写的是「你与这个仓库的关系」，不是仓库本身 —— 所以不需要对仓库的任何权限"
        )
    }

    @Test("unstar：DELETE 同一个路径")
    func unstarUsesDelete() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 204))

        try await makeEndpoint(harness: harness, cache: HTTPResponseCache(configuration: .memoryOnly()))
            .unstar(owner: "misoge", repo: "paneltkit")

        let request = try #require(harness.lastRequest)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.absoluteString == "https://api.github.com/user/starred/misoge/paneltkit")
    }

    @Test("204 且响应体为空 ⇒ 不抛错（不解码空 body）")
    func emptyBodyDoesNotThrow() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 204))

        // 只要这里不抛，就说明我们确实"只读状态码、没去解一个空 body"。
        try await makeEndpoint(harness: harness, cache: HTTPResponseCache(configuration: .memoryOnly()))
            .star(owner: "o", repo: "r")

        #expect(harness.requestCount == 1)
    }

    // MARK: - isStarred（±1 的基准）

    @Test("isStarred：204 ⇒ true")
    func isStarredTrueOn204() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 204))

        let starred = try await makeEndpoint(
            harness: harness,
            cache: HTTPResponseCache(configuration: .memoryOnly())
        ).isStarred(owner: "misoge", repo: "paneltkit")

        #expect(starred)
        #expect(
            harness.lastRequest?.url?.absoluteString
                == "https://api.github.com/user/starred/misoge/paneltkit"
        )
    }

    @Test("isStarred：404 ⇒ false（这里的 404 **不是**「仓库不存在」）")
    func isStarredFalseOn404() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"message":"Not Found"}"#, status: 404))

        let starred = try await makeEndpoint(
            harness: harness,
            cache: HTTPResponseCache(configuration: .memoryOnly())
        ).isStarred(owner: "o", repo: "r")

        #expect(starred == false)
    }

    @Test("isStarred：500 必须抛出去，不能吞成「没 Star」")
    func isStarredServerErrorThrows() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"message":"boom"}"#, status: 500))

        do {
            _ = try await makeEndpoint(
                harness: harness,
                cache: HTTPResponseCache(configuration: .memoryOnly())
            ).isStarred(owner: "o", repo: "r")
            Issue.record("5xx 不该被解释成「没 Star 过」")
        } catch let error as GitHubError {
            guard case .serverError = error else {
                Issue.record("应归为 .serverError，实际：\(error)")
                return
            }
        }
        // 为什么：把 5xx / 断网吞成 false，界面会显示 `Star · N`（未 Star），
        // 而你其实早就 Star 过了 —— 再点一下就会把一个幂等的 PUT 当成"新增一颗星"，
        // 于是屏幕上的计数比真实值多 1。
    }

    // MARK: - 写后失效（本套件存在的核心理由之二）

    @Test("Star 成功后：`/user/starred` 与该仓库详情两份缓存都失效")
    func starInvalidatesBothCaches() async throws {
        let harness = StubURLProtocol.makeHarness()
        let cache = HTTPResponseCache(configuration: .memoryOnly())
        harness.stub(.empty(status: 204))

        let starredList = makeKey("https://api.github.com/user/starred?per_page=30")
        let detail = makeKey("https://api.github.com/repos/misoge/paneltkit")
        // 一个**不该**被误伤的邻居：同一 owner 下的另一个仓库
        let neighbour = makeKey("https://api.github.com/repos/misoge/other")
        await cache.store(makeCachedResponse(), for: starredList)
        await cache.store(makeCachedResponse(), for: detail)
        await cache.store(makeCachedResponse(), for: neighbour)

        try await makeEndpoint(harness: harness, cache: cache)
            .star(owner: "misoge", repo: "paneltkit")

        #expect(await cache.entry(for: starredList) == nil, "不失效的话，刚 Star 完进「我的 Star」看不到它")
        #expect(
            await cache.entry(for: detail) == nil,
            "不失效的话，本地的 +1 会被缓存里的旧响应打回原值 —— 星数自己弹回去了"
        )
        #expect(await cache.entry(for: neighbour) != nil, "前缀失效不该误伤同 owner 的其它仓库")
    }

    @Test("取消 Star 同样失效两份缓存")
    func unstarInvalidatesBothCaches() async throws {
        let harness = StubURLProtocol.makeHarness()
        let cache = HTTPResponseCache(configuration: .memoryOnly())
        harness.stub(.empty(status: 204))

        let starredList = makeKey("https://api.github.com/user/starred")
        let detail = makeKey("https://api.github.com/repos/o/r")
        await cache.store(makeCachedResponse(), for: starredList)
        await cache.store(makeCachedResponse(), for: detail)

        try await makeEndpoint(harness: harness, cache: cache).unstar(owner: "o", repo: "r")

        #expect(await cache.entry(for: starredList) == nil)
        #expect(await cache.entry(for: detail) == nil)
    }

    @Test("查询是否已 Star **不**失效任何缓存（它是读，不是写）")
    func isStarredDoesNotInvalidate() async throws {
        let harness = StubURLProtocol.makeHarness()
        let cache = HTTPResponseCache(configuration: .memoryOnly())
        harness.stub(.empty(status: 204))

        let detail = makeKey("https://api.github.com/repos/o/r")
        await cache.store(makeCachedResponse(), for: detail)

        _ = try await makeEndpoint(harness: harness, cache: cache).isStarred(owner: "o", repo: "r")

        #expect(await cache.entry(for: detail) != nil)
    }
}
