import Foundation
import Testing

@testable import GitHubAPI

/// 会话（Issue / PR）搜索 —— `GET /search/issues`（TECH_SPEC §4.6.2、§9.2、**决策 #47**）。
///
/// 本套件盯四件事：
/// 1. **`q` 原样发出去**：`is:issue` / `is:pull-request` 由领域层拼（`SearchQueryBuilder`），
///    本端点既不添加也不剥掉 —— 同一条门槛**不该有两处实现**（子串那份更弱）；
/// 2. **配额桶必须是 `search`**（这个范围每翻一页消耗 **2 格**，决策 #47 明写的代价）；
/// 3. 解码：**类型由响应决定**（`pull_request` 字段的存在性），PR 的 `merged_at` 可为 null；
/// 4. 空关键词就地拦掉。
@Suite("GitHubSearchIssuesEndpoint · 会话范围的数据源（决策 #47）")
struct GitHubSearchIssuesEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

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
    ) -> GitHubSearchIssuesEndpoint {
        let clock = now
        return GitHubSearchIssuesEndpoint(
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

    private func envelope(items: String, total: Int = 3, incomplete: Bool = false) -> String {
        #"{"total_count":"# + String(total) + #","incomplete_results":"#
            + (incomplete ? "true" : "false")
            + #","items":["# + items + #"]}"#
    }

    /// 一条 Issue（没有 `pull_request` 键）。
    private let issueItem = """
    {"number":42,"title":"登录页在深色模式下错位","state":"open",
     "updated_at":"2026-10-07T08:00:00Z",
     "repository_url":"https://api.github.com/repos/my-git/gitduo"}
    """

    /// 一条**已合并**的 PR（`state: closed` + `merged_at` 有值）。
    private let mergedPRItem = """
    {"number":7,"title":"修复令牌落盘","state":"closed",
     "updated_at":"2026-10-06T10:00:00Z",
     "repository_url":"https://api.github.com/repos/my-git/gitduo",
     "pull_request":{"merged_at":"2026-10-06T11:00:00Z"}}
    """

    // MARK: - 请求形状

    @Test("请求形状：路径 search/issues，q **原样**（含领域层拼好的 is: 限定符）")
    func buildsRequestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(items: "")))

        _ = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "登录 is:issue", perPage: 30)

        let url = try #require(harness.lastRequest?.url)
        #expect(url.path == "/search/issues")

        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        // 端点不碰 q —— 少了 is: 限定符服务端会 422，而"该不该拼"的判定在领域层（唯一实现）。
        #expect(items.first { $0.name == "q" }?.value == "登录 is:issue")
        #expect(items.first { $0.name == "per_page" }?.value == "30")
        #expect(items.first { $0.name == "sort" } == nil)
    }

    @Test("q 不带 is: 限定符也**原样发出**（门槛在领域层，这里不拦第二遍 —— 有意为之）")
    func sendsQualifierlessQueryVerbatim() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(items: "")))

        _ = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "登录")

        // 钉住"不在这一层再写一份子串判断"：那份判断会把引号里的 is:issue 也算中，
        // 而且两处实现迟早分叉。真正的拦截在 SearchQueryBuilder（已单测）。
        let url = try #require(harness.lastRequest?.url)
        let items = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        #expect(items.first { $0.name == "q" }?.value == "登录")
    }

    // MARK: - 配额桶

    @Test("配额桶：走 search 桶（这个范围每翻一页要发两条 ⇒ 2 格）")
    func usesSearchBucket() async throws {
        let harness = StubURLProtocol.makeHarness()
        let limiter = makeRateLimiter()
        harness.stub(.json(envelope(items: "")))

        _ = try await makeEndpoint(harness: harness, rateLimiter: limiter)
            .search(query: "登录 is:pull-request")

        #expect(await limiter.nextAllowedAt(.search) != nil)
        #expect(await limiter.nextAllowedAt(.codeSearch) == nil)
    }

    // MARK: - 解码（类型与合并判定都在这一段）

    @Test("解码 Issue：没有 pull_request 键 ⇒ isPullRequest 为 false")
    func decodesIssue() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(items: issueItem, total: 15)))

        let result = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "登录 is:issue")

        #expect(result.totalCount == 15)
        let item = try #require(result.items.first)
        #expect(!item.isPullRequest)
        #expect(item.number == 42)
        #expect(item.state == "open")
        #expect(item.repositoryURL.absoluteString == "https://api.github.com/repos/my-git/gitduo")
        let updated = try #require(GitHubDate.parse("2026-10-07T08:00:00Z"))
        #expect(item.updatedAt == updated)
    }

    @Test("解码已合并 PR：state=closed 且 merged_at 有值")
    func decodesMergedPR() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(items: mergedPRItem)))

        let result = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "登录 is:pull-request")

        let item = try #require(result.items.first)
        #expect(item.isPullRequest)
        let merged = try #require(GitHubDate.parse("2026-10-06T11:00:00Z"))
        #expect(item.pullRequest?.mergedAt == merged)
    }

    @Test("解码关闭未合并的 PR：merged_at 为 null ⇒ nil（「已关闭」≠「已合并」）")
    func decodesClosedUnmergedPR() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                envelope(
                    items: """
                    {"number":9,"title":"没人跟进了","state":"closed",
                     "updated_at":"2026-10-01T00:00:00Z",
                     "repository_url":"https://api.github.com/repos/o/r",
                     "pull_request":{"merged_at":null}}
                    """
                )
            )
        )

        let result = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
            .search(query: "x is:pull-request")

        let item = try #require(result.items.first)
        #expect(item.isPullRequest)
        // nil 就是"关闭但没合并"—— 不猜、不补值，判定收在 PullRequestState(state:mergedAt:)。
        #expect(item.pullRequest?.mergedAt == nil)
    }

    // MARK: - 兜底与分页

    @Test("空关键词：就地抛 .validation，且**一次请求都不发**")
    func emptyQueryNeverGoesOut() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(items: "")))

        do {
            _ = try await makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
                .search(query: "  ")
            Issue.record("空关键词应当就地拦掉")
        } catch let error as GitHubError {
            guard case .validation = error else {
                Issue.record("应归为 .validation，实际：\(error)")
                return
            }
        }

        #expect(harness.requestCount == 0)
    }

    @Test("分页：续页原样用 Link 里的完整 URL")
    func followsCursorVerbatim() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                envelope(items: ""),
                headers: [
                    "Link": #"<https://api.github.com/search/issues?q=%E7%99%BB%E5%BD%95&page=2>; rel="next""#
                ]
            )
        )

        let endpoint = makeEndpoint(harness: harness, rateLimiter: makeRateLimiter())
        let first = try await endpoint.search(query: "登录 is:issue")
        let cursor = try #require(first.nextCursor)

        _ = try await endpoint.search(query: "登录 is:issue", cursor: cursor)
        #expect(harness.lastRequest?.url?.absoluteString == cursor.absoluteString)
    }
}
