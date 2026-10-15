import Foundation
import Testing

@testable import GitHubAPI

/// 仓库搜索（探索双榜 + 搜索页「仓库」范围）—— TECH_SPEC §4.6.3、§9.10.1、§13.2、决策 #37。
///
/// 本套件盯三件事：
/// 1. **配额桶必须是 `search`** —— 漏声明不会报错，只会静默打爆 30/分钟那一档；
/// 2. **空关键词必须就地拦掉** —— 否则白花一格搜索配额换一个必然的 422；
/// 3. **续页原样用服务端给的 URL** —— 自己拼 `?page=n` 在搜索端点上会翻错页。
@Suite("GitHubSearchRepositoriesEndpoint · 探索双榜的数据源")
struct GitHubSearchRepositoriesEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// 注入假时钟 + 空 sleeper 的限流器：搜索桶的间隔是 **2 秒**，
    /// 不注入的话每个用例都要真的等（而我们要断言的是"桶被用了"，不是"真的限速了"）。
    private func makeRateLimiter() -> RateLimiter {
        let clock = now
        return RateLimiter(
            policies: RateLimiter.Policy.defaults,
            clock: { clock },
            sleeper: { _ in }
        )
    }

    private func makeEndpoint(
        harness: StubURLProtocol.Harness,
        rateLimiter: RateLimiter
    ) -> GitHubSearchRepositoriesEndpoint {
        let clock = now
        return GitHubSearchRepositoriesEndpoint(
            client: GitHubRESTClient(
                credentials: credentials,
                transport: HTTPTransport(
                    credentials: credentials,
                    session: harness.makeSession(),
                    cache: HTTPResponseCache(configuration: .memoryOnly()),
                    rateLimiter: rateLimiter,
                    retryPolicy: .none,
                    clock: { clock },
                    sleeper: { _ in }
                )
            )
        )
    }

    /// 一个字段齐全的搜索结果条目。
    private let fullItem = """
    {"full_name":"misoge/paneltkit","description":"SwiftUI 自适应布局工具库 · Swift",
     "language":"Swift","stargazers_count":2341,
     "created_at":"2026-08-05T09:00:00Z","pushed_at":"2026-10-06T10:00:00Z",
     "owner":{"avatar_url":"https://avatars.githubusercontent.com/u/1?v=4"}}
    """

    private func envelope(items: String, incomplete: Bool = false) -> String {
        #"{"total_count":1234,"incomplete_results":"#
            + (incomplete ? "true" : "false")
            + #","items":["# + items + #"]}"#
    }

    // MARK: - 请求形状

    @Test("请求形状：q / sort / order / per_page 四个查询项写全，路径是 search/repositories")
    func buildsRequestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(items: "")))

        _ = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "created:>=2026-07-08 stars:>50", sort: "stars", perPage: 30)

        let url = try #require(harness.lastRequest?.url)
        #expect(url.path == "/search/repositories")

        let items = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        #expect(
            items.first { $0.name == "q" }?.value == "created:>=2026-07-08 stars:>50",
            "限定符串由领域层（ExploreQueryBuilder）拼好，端点只负责原样发出去"
        )
        #expect(items.first { $0.name == "sort" }?.value == "stars")
        #expect(items.first { $0.name == "order" }?.value == "desc", "默认降序")
        #expect(items.first { $0.name == "per_page" }?.value == "30")
        #expect(harness.lastRequest?.httpMethod == "GET")
    }

    @Test("配额桶：走的是 search 桶（不是默认的 core）")
    func usesSearchBucket() async throws {
        let harness = StubURLProtocol.makeHarness()
        let limiter = makeRateLimiter()
        harness.stub(.json(envelope(items: "")))

        _ = try await makeEndpoint(harness: harness, rateLimiter: limiter)
            .search(query: "stars:>50", sort: "stars")

        // ⚠️ 漏声明 `rateLimitResource: .search` 不会有任何报错 ——
        // 只会让这条请求按 `.core`（间隔 0）放行，于是"30 次/分钟"这条硬限
        // 在客户端彻底失效，直到某次连点被服务端 403 拦下。
        //
        // 断言手法：`acquire(_:)` 只对 `minimumInterval > 0` 的桶记录 nextAllowed，
        // 而 `.core` 的间隔就是 0 ⇒ 它永远为 nil。于是"search 非 nil"恰好等于
        // "这条请求确实走了 search 桶"。
        // ⚠️ `await` 先取值再断言：`#expect` 宏内联 `await` 在本工具链上不可靠。
        let searchNext = await limiter.nextAllowedAt(.search)
        #expect(searchNext != nil)
    }

    @Test("对照：仓库列表走 core 桶，不该碰 search 桶")
    func coreRequestsDoNotTouchSearchBucket() async throws {
        let harness = StubURLProtocol.makeHarness()
        let limiter = makeRateLimiter()
        harness.stub(.json("[]"))

        let clock = now
        let repos = GitHubRepositoryEndpoint(
            client: GitHubRESTClient(
                credentials: credentials,
                transport: HTTPTransport(
                    credentials: credentials,
                    session: harness.makeSession(),
                    cache: HTTPResponseCache(configuration: .memoryOnly()),
                    rateLimiter: limiter,
                    retryPolicy: .none,
                    clock: { clock },
                    sleeper: { _ in }
                )
            )
        )
        _ = try await repos.listRepos()

        let searchNext = await limiter.nextAllowedAt(.search)
        #expect(searchNext == nil)
    }

    // MARK: - 空关键词（本套件存在的核心理由之一）

    @Test("空关键词：就地抛 .validation，且**一次请求都不发**")
    func emptyQueryNeverGoesOut() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(items: "")))

        do {
            _ = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
                .search(query: "   ", sort: "stars")
            Issue.record("空关键词应当就地拦掉")
        } catch let error as GitHubError {
            guard case .validation = error else {
                Issue.record("应归为 .validation，实际：\(error)")
                return
            }
        }

        // 这一条是重点：GitHub 对空 q 回 422，而那次失败**照样消耗搜索配额**
        // （30 次/分钟，与探索页、搜索页共用同一个桶）。
        #expect(harness.requestCount == 0, "拦在出网之前 —— 否则白花一格配额换一个必然的失败")
    }

    // MARK: - 解码

    @Test("解码：条目字段 + incomplete_results")
    func decodesItems() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(items: fullItem)))

        let result = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "stars:>50", sort: "stars")

        #expect(result.items.count == 1)
        let item = try #require(result.items.first)
        #expect(item.fullName == "misoge/paneltkit")
        #expect(item.language == "Swift")
        #expect(item.starCount == 2341)

        let created = try #require(GitHubDate.parse("2026-08-05T09:00:00Z"))
        let pushed = try #require(GitHubDate.parse("2026-10-06T10:00:00Z"))
        #expect(item.createdAt == created)
        #expect(item.pushedAt == pushed)
        #expect(!result.incompleteResults)
        #expect(!result.hasMore)
    }

    @Test("incomplete_results=true 会被带出来（那是「这一页少了东西」的唯一信号）")
    func carriesIncompleteResults() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(items: fullItem, incomplete: true)))

        let result = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "stars:>50", sort: "stars")

        #expect(result.incompleteResults)
    }

    @Test("从不推送过的仓库：pushed_at 为 null ⇒ nil，不是解码失败")
    func decodesNullPushedAt() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                envelope(
                    items: #"{"full_name":"a/b","description":null,"language":null,"stargazers_count":51,"created_at":"2026-09-01T00:00:00Z","pushed_at":null,"owner":{"avatar_url":"https://avatars.githubusercontent.com/u/2?v=4"}}"#
                )
            )
        )

        let result = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "stars:>50", sort: "stars")

        #expect(result.items.first?.pushedAt == nil)
        #expect(result.items.first?.language == nil)
    }

    // MARK: - 分页

    @Test("分页：nextCursor 取自 Link 的 rel=next")
    func exposesNextCursor() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                envelope(items: fullItem),
                headers: [
                    "Link": #"<https://api.github.com/search/repositories?q=stars%3A%3E50&page=2>; rel="next""#
                ]
            )
        )

        let result = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "stars:>50", sort: "stars")

        #expect(result.hasMore)
        #expect(
            result.nextCursor?.absoluteString
                == "https://api.github.com/search/repositories?q=stars%3A%3E50&page=2"
        )
    }

    @Test("续页：直接用服务端给的完整 URL，**不再补 q / sort**")
    func followsCursorVerbatim() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(items: "")))

        let cursor = URL(
            string: "https://api.github.com/search/repositories?q=stars%3A%3E50&page=2"
        )!
        _ = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "stars:>50", sort: "stars", cursor: cursor)

        // 搜索的 next 链接带的是服务端自己拼好的完整查询串；自己再补一遍 q / sort
        // 会得到"看着一模一样、实际两个参数各出现两次"的 URL —— 服务端按第一个取，
        // 于是翻出来的是第一页的数据（表现为"加载更多没有新内容"）。
        #expect(harness.lastRequest?.url?.absoluteString == cursor.absoluteString)
    }

    @Test("续页同样占 search 桶（把整页翻完，一次都不该落到 core）")
    func cursorPageAlsoUsesSearchBucket() async throws {
        let harness = StubURLProtocol.makeHarness()
        let limiter = makeRateLimiter()
        harness.stub(.json(envelope(items: "")))

        let cursor = URL(string: "https://api.github.com/search/repositories?page=2")!
        _ = try await makeEndpoint(harness: harness, rateLimiter: limiter)
            .search(query: "stars:>50", sort: "stars", cursor: cursor)

        let searchNext = await limiter.nextAllowedAt(.search)
        #expect(searchNext != nil)
    }
}
