import Foundation
import Testing

@testable import GitHubAPI

/// 代码搜索 —— `GET /search/code`（TECH_SPEC §4.6.1、§9.2、PRD §4.2、决策 #48）。
///
/// 本套件盯三件事：
/// 1. **`Accept: text-match` 是功能开关不是协商** —— 不带照样 200、只是没有 `text_matches`，
///    所以首屏与**每一页续页**都必须带上它（漏了的症状是"前 30 条有预览、后面全没有"）；
/// 2. **配额桶必须是 `codeSearch`**（约 10 次/分钟，是四个范围里最紧的一档）；
/// 3. 解码：`language` / `text_matches` 都按可选处理（官方文档示例不含前者）。
@Suite("GitHubSearchCodeEndpoint · 代码范围的数据源")
struct GitHubSearchCodeEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// 代码搜索桶的间隔是 60/9 秒（按 9 保守预算）—— 不注入假时钟每个用例都要真的等。
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
    ) -> GitHubSearchCodeEndpoint {
        let clock = now
        return GitHubSearchCodeEndpoint(
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

    private func envelope(items: String, total: Int = 7, incomplete: Bool = false) -> String {
        #"{"total_count":"# + String(total) + #","incomplete_results":"#
            + (incomplete ? "true" : "false")
            + #","items":["# + items + #"]}"#
    }

    /// 字段齐全的一条：带 `text_matches` 与 `language`。
    private let fullItem = """
    {"name":"App.swift","path":"Sources/App/App.swift","sha":"abc123",
     "repository":{"full_name":"my-git/gitduo"},
     "language":"Swift",
     "text_matches":[{"fragment":"let window = SwiftUIWindow()"}]}
    """

    // MARK: - 请求形状（本套件存在的核心理由：那个 Accept）

    @Test("请求形状：路径 search/code，q / per_page，**不带 sort**")
    func buildsRequestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(items: "")))

        _ = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "SwiftUIWindow language:swift", perPage: 30)

        let url = try #require(harness.lastRequest?.url)
        #expect(url.path == "/search/code")

        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "q" }?.value == "SwiftUIWindow language:swift")
        #expect(items.first { $0.name == "per_page" }?.value == "30")
        #expect(items.first { $0.name == "sort" } == nil)
        #expect(harness.lastRequest?.httpMethod == "GET")
    }

    @Test("⚠️ Accept 是 text-match 媒体类型，且**恰好一个值**（覆盖默认，不与之并存）")
    func sendsTextMatchAccept() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(items: "")))

        _ = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "SwiftUIWindow")

        // 不带它服务端照样 200，只是永远没有 text_matches ⇒ 结果行永远少一行预览。
        // 而那不会报错，只会被当成"这个范围本来就长这样"。
        #expect(
            harness.lastRequest?.value(forHTTPHeaderField: "Accept")
                == "application/vnd.github.text-match+json"
        )
    }

    @Test("⚠️ 续页**同样**带 text-match 的 Accept（漏了 ⇒ 第一页有预览、后面全没有）")
    func cursorPageKeepsTextMatchAccept() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                envelope(items: ""),
                headers: ["Link": #"<https://api.github.com/search/code?q=x&page=2>; rel="next""#]
            )
        )

        let endpoint = makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
        let first = try await endpoint.search(query: "SwiftUIWindow")
        let cursor = try #require(first.nextCursor)

        _ = try await endpoint.search(query: "SwiftUIWindow", cursor: cursor)

        #expect(
            harness.lastRequest?.value(forHTTPHeaderField: "Accept")
                == "application/vnd.github.text-match+json"
        )
        #expect(harness.lastRequest?.url?.absoluteString == cursor.absoluteString)
    }

    // MARK: - 配额桶

    @Test("配额桶：走 codeSearch（约 10/min 那一档），不是 search，更不是 core")
    func usesCodeSearchBucket() async throws {
        let harness = StubURLProtocol.makeHarness()
        let limiter = makeRateLimiter()
        harness.stub(.json(envelope(items: "")))

        _ = try await makeEndpoint(harness: harness, rateLimiter: limiter)
            .search(query: "SwiftUIWindow")

        // 漏声明 `.codeSearch` 不会报错，只会按别的桶放行 —— 而这一档比 search 还紧三倍。
        #expect(await limiter.nextAllowedAt(.codeSearch) != nil)
        #expect(await limiter.nextAllowedAt(.search) == nil)
        #expect(await limiter.nextAllowedAt(.core) == nil)
    }

    // MARK: - 解码

    @Test("解码：path / language / repository.full_name / text_matches 逐个取到")
    func decodesFullItem() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(items: fullItem, total: 42)))

        let result = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "SwiftUIWindow")

        #expect(result.totalCount == 42)
        let item = try #require(result.items.first)
        #expect(item.path == "Sources/App/App.swift")
        #expect(item.language == "Swift")
        #expect(item.repository.fullName == "my-git/gitduo")
        #expect(item.textMatches?.first?.fragment == "let window = SwiftUIWindow()")
    }

    @Test("⚠️ 不带 text-match 媒体类型时的响应：没有 text_matches 键 ⇒ nil，不是解码失败")
    func decodesItemWithoutTextMatches() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                envelope(
                    items: #"{"name":"a.swift","path":"a.swift","repository":{"full_name":"o/r"},"language":null}"#
                )
            )
        )

        let result = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "foo")

        // language 也是可选：官方文档示例不含它，认不出类型的文件就是 null。
        let item = try #require(result.items.first)
        #expect(item.textMatches == nil)
        #expect(item.language == nil)
    }

    // MARK: - 兜底

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

        // 代码那一档只有约 10 次/分钟 —— 白花一格换必然的 422 更伤。
        #expect(harness.requestCount == 0)
    }
}
