import Foundation
import Testing

@testable import GitHubAPI

/// 用户搜索 —— `GET /search/users`（TECH_SPEC §4.6.1、§9.2、PRD §4.2）。
///
/// 本套件盯三件事：
/// 1. **配额桶必须是 `search`**（与探索榜、搜索页其余三个范围**共用**同一档，30/分钟）；
/// 2. ⚠️ **人数/昵称/简介缺席时仍要解得出** —— 官方 schema 声明它们可选、
///    官方文档示例里干脆没有；声明成必需会让**整个用户范围整页空白**；
/// 3. 续页原样用服务端给的 URL。
@Suite("GitHubSearchUsersEndpoint · 用户范围的数据源")
struct GitHubSearchUsersEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// 注入假时钟 + 空 sleeper：搜索桶间隔 2 秒，不注入的话每个用例都要真的等。
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
    ) -> GitHubSearchUsersEndpoint {
        let clock = now
        return GitHubSearchUsersEndpoint(
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

    private func envelope(items: String, total: Int = 12, incomplete: Bool = false) -> String {
        #"{"total_count":"# + String(total) + #","incomplete_results":"#
            + (incomplete ? "true" : "false")
            + #","items":["# + items + #"]}"#
    }

    /// 字段齐全的一条。
    private let fullItem = """
    {"login":"dev-j","name":"jiangjiang","bio":"my-git · iOS / SwiftUI 开发",
     "public_repos":3,"followers":21}
    """

    // MARK: - 请求形状

    @Test("请求形状：q / per_page 两个查询项，路径是 search/users，**不带 sort**")
    func buildsRequestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(items: "")))

        _ = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "swiftui", perPage: 30)

        let url = try #require(harness.lastRequest?.url)
        #expect(url.path == "/search/users")

        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "q" }?.value == "swiftui")
        #expect(items.first { $0.name == "per_page" }?.value == "30")
        // PRD §4.2 没规定排序 ⇒ 一个 sort 参数都不带，让服务端按相关性排。
        #expect(items.first { $0.name == "sort" } == nil)
        #expect(items.first { $0.name == "order" } == nil)
        #expect(harness.lastRequest?.httpMethod == "GET")
    }

    @Test("配额桶：走的是 search 桶（不是默认的 core）")
    func usesSearchBucket() async throws {
        let harness = StubURLProtocol.makeHarness()
        let limiter = makeRateLimiter()
        harness.stub(.json(envelope(items: "")))

        _ = try await makeEndpoint(harness: harness, rateLimiter: limiter).search(query: "tom")

        // 漏声明 `rateLimitResource: .search` 不会报错，只会按 `.core`（间隔 0）放行。
        // `.core` 的间隔是 0 ⇒ 它永远不会在 nextAllowed 里留痕，于是"search 非 nil"
        // 恰好等于"这条请求确实走了 search 桶"。
        #expect(await limiter.nextAllowedAt(.search) != nil)
        #expect(await limiter.nextAllowedAt(.core) == nil)
    }

    // MARK: - 解码（本套件存在的核心理由）

    @Test("解码：四个可选字段都在时逐个取到")
    func decodesFullItem() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(items: fullItem, total: 1234)))

        let result = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "dev")

        #expect(result.totalCount == 1234, "结果标题里的 N 就是它（决策 #44）")
        let item = try #require(result.items.first)
        #expect(item.login == "dev-j")
        #expect(item.name == "jiangjiang")
        #expect(item.bio == "my-git · iOS / SwiftUI 开发")
        #expect(item.publicRepos == 3)
        #expect(item.followers == 21)
    }

    @Test("⚠️ 官方文档示例那种**只有 login / id / avatar_url**的条目：解得出，四个字段全为 nil")
    func decodesItemWithoutProfileFields() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                envelope(
                    items: #"{"login":"mojombo","id":1,"avatar_url":"https://x","type":"User","score":1}"#
                )
            )
        )

        let result = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "mojombo")

        // 这一条是重点：把 public_repos / followers 声明成必需 ⇒ 这里整页解码失败，
        // 而用户看到的是"用户范围搜不出任何东西"。
        let item = try #require(result.items.first)
        #expect(item.login == "mojombo")
        #expect(item.name == nil)
        #expect(item.bio == nil)
        #expect(item.publicRepos == nil, "nil = 不知道，不是 0")
        #expect(item.followers == nil, "nil = 不知道，不是 0")
    }

    @Test("明确写了 null 的字段同样落 nil（而不是解码失败）")
    func decodesExplicitNulls() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(envelope(items: #"{"login":"a","name":null,"bio":null,"public_repos":null,"followers":null}"#))
        )

        let result = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "a")

        let item = try #require(result.items.first)
        #expect(item.name == nil)
        #expect(item.publicRepos == nil)
        #expect(item.followers == nil)
    }

    // MARK: - 兜底与分页

    @Test("空关键词：就地抛 .validation，且**一次请求都不发**")
    func emptyQueryNeverGoesOut() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(items: "")))

        do {
            _ = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
                .search(query: "   ")
            Issue.record("空关键词应当就地拦掉")
        } catch let error as GitHubError {
            guard case .validation = error else {
                Issue.record("应归为 .validation，实际：\(error)")
                return
            }
        }

        #expect(harness.requestCount == 0, "空 q 必然 422，而那次失败照样扣搜索配额")
    }

    @Test("分页：nextCursor 取自 Link 的 rel=next；续页原样用那个完整 URL")
    func followsCursorVerbatim() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                envelope(items: fullItem),
                headers: ["Link": #"<https://api.github.com/search/users?q=tom&page=2>; rel="next""#]
            )
        )

        let endpoint = makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
        let first = try await endpoint.search(query: "tom")
        #expect(first.hasMore)
        #expect(
            first.nextCursor?.absoluteString
                == "https://api.github.com/search/users?q=tom&page=2"
        )

        let cursor = try #require(first.nextCursor)
        _ = try await endpoint.search(query: "tom", cursor: cursor)
        #expect(harness.lastRequest?.url?.absoluteString == cursor.absoluteString)
    }
}
