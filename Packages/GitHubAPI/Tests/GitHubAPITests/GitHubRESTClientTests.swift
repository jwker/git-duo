import Foundation
import Testing

@testable import GitHubAPI

/// `GitHubRESTClient` 的规格 —— 路径拼装 / 解码 / `Link` 分页（TECH_SPEC §4.1 / §4.4）。
///
/// 桩件用**本套件自持的 harness**，与其它网络套件并行也不互相覆盖。
@Suite("GitHubRESTClient · 路径 / 解码 / 分页")
struct GitHubRESTClientTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// 一个只返回 `login` 的最小 DTO。
    private struct User: Codable, Sendable, Equatable {
        let login: String
    }

    private struct Repo: Codable, Sendable, Equatable {
        let name: String
    }

    private func makeClient(
        harness: StubURLProtocol.Harness,
        rateLimiter: RateLimiter = RateLimiter()
    ) -> GitHubRESTClient {
        let clock = now
        return GitHubRESTClient(
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
    }

    // MARK: - 路径拼装

    @Test("路径拼装：前导斜杠可有可无，两种写法必须得到同一个 URL")
    func normalizesLeadingSlash() {
        let client = makeClient(harness: StubURLProtocol.makeHarness())

        let withoutSlash = client.url("repos/apple/swift")
        let withSlash = client.url("/repos/apple/swift")

        #expect(withoutSlash.absoluteString == "https://api.github.com/repos/apple/swift")
        #expect(withoutSlash == withSlash, "两种写法都有人写，谁都以为自己对 —— 差异必须在入口被吃掉")
    }

    @Test("查询项走 URLQueryItem：搜索里的 `:` `/` 空格必须被正确百分号编码")
    func encodesQueryItems() {
        let client = makeClient(harness: StubURLProtocol.makeHarness())

        let url = client.url(
            "search/repositories",
            query: [
                URLQueryItem(name: "q", value: "swift ui repo:apple/swift"),
                URLQueryItem(name: "per_page", value: "30")
            ]
        )

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(components?.queryItems?.first { $0.name == "q" }?.value == "swift ui repo:apple/swift")
        #expect(components?.queryItems?.first { $0.name == "per_page" }?.value == "30")
        #expect(!url.absoluteString.contains(" "), "URL 里绝不能出现裸空格 —— 那说明是手拼的")
    }

    // MARK: - 单对象

    @Test("get：解出对象，且请求落在拼好的 URL 上")
    func getsAndDecodes() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"login":"octocat"}"#))
        let client = makeClient(harness: harness)

        let user = try await client.get("user", as: User.self)

        #expect(user == User(login: "octocat"))
        #expect(harness.lastRequest?.url?.absoluteString == "https://api.github.com/user")
        #expect(harness.lastRequest?.httpMethod == "GET")
    }

    @Test("get 带查询项：请求 URL 里带上全部查询串（缓存键必须含完整查询串，§5.2）")
    func getCarriesQuery() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))
        let client = makeClient(harness: harness)

        _ = try await client.get(
            "user/repos",
            query: [URLQueryItem(name: "affiliation", value: "owner")],
            as: [Repo].self
        )

        #expect(harness.lastRequest?.url?.absoluteString == "https://api.github.com/user/repos?affiliation=owner")
    }

    // MARK: - 分页

    @Test("page：解出数组，下一页取自 `Link: rel=next`")
    func pageReadsLinkHeader() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"[{"name":"swift"},{"name":"swift-corelibs"}]"#,
                headers: [
                    "Link": #"<https://api.github.com/user/repos?page=2>; rel="next", <https://api.github.com/user/repos?page=9>; rel="last""#
                ]
            )
        )
        let client = makeClient(harness: harness)

        let page = try await client.page("user/repos", as: Repo.self)

        #expect(page.items == [Repo(name: "swift"), Repo(name: "swift-corelibs")])
        #expect(page.nextCursor?.absoluteString == "https://api.github.com/user/repos?page=2")
        #expect(page.hasMore)
    }

    @Test("page：没有 Link 头 ⇒ 到底了（不伪造下一页）")
    func pageWithoutLinkIsLast() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))
        let client = makeClient(harness: harness)

        let page = try await client.page("user/repos", as: Repo.self)

        #expect(page.isEmpty)
        #expect(page.nextCursor == nil)
        #expect(!page.hasMore)
    }

    @Test("page(at:)：直接请求**完整游标 URL**，不自己拼页码")
    func pageAtCursorUsesFullURL() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"[{"name":"swift"}]"#))
        let client = makeClient(harness: harness)

        // ⚠️ 游标故意带一个"自己拼页码拼不出来"的参数形态
        let cursor = URL(string: "https://api.github.com/user/repos?q=swift&per_page=30&page=2")!
        let page = try await client.page(at: cursor, as: Repo.self)

        #expect(page.items == [Repo(name: "swift")])
        #expect(
            harness.lastRequest?.url?.absoluteString == cursor.absoluteString,
            "GitHub 的 next 可能带 `?page=` 之外的参数，自己拼会在那些端点悄悄翻错页"
        )
    }

    // MARK: - 原始请求

    @Test("send：调用方自建请求原样发出（换 Accept 取 diff 原文走这条）")
    func sendPassesRequestThrough() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("diff --git a/x b/x", headers: ["Content-Type": "application/vnd.github.diff"]))
        let client = makeClient(harness: harness)

        let url = client.url("repos/apple/swift/pulls/1")
        let response = try await client.send(
            .get(url, headers: ["Accept": "application/vnd.github.diff"], cachesResponse: false)
        )

        #expect(String(data: response.body, encoding: .utf8) == "diff --git a/x b/x")
        #expect(harness.lastRequest?.value(forHTTPHeaderField: "Accept") == "application/vnd.github.diff")
    }

    // MARK: - 配额桶透传

    @Test("搜索桶确实透传到了闸门：`.search` 请求会按策略等待（不是按主桶放过）")
    func searchResourceIsThrottled() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        let slept = SleepRecorder()
        let limiter = RateLimiter(
            policies: [.search: RateLimiter.Policy(minimumInterval: 2)],
            clock: { self.now },
            sleeper: { seconds in await slept.record(seconds) }
        )
        let client = makeClient(harness: harness, rateLimiter: limiter)

        _ = try await client.page(
            "search/repositories",
            query: [URLQueryItem(name: "q", value: "swift")],
            as: Repo.self,
            rateLimitResource: .search
        )

        // 第一次不该等（桶是空的）；把同样请求再发一次，这一次必须等满 2 秒
        _ = try await client.page(
            "search/repositories",
            query: [URLQueryItem(name: "q", value: "swift")],
            as: Repo.self,
            rateLimitResource: .search
        )

        let intervals = await slept.intervals
        #expect(intervals == [2], "同桶第二次请求必须等满最小间隔，实际等到：\(intervals)")
    }

    /// 记录限流器要睡的时长（替身 sleeper）。
    private actor SleepRecorder {
        private(set) var intervals: [TimeInterval] = []

        func record(_ seconds: TimeInterval) {
            intervals.append(seconds)
        }
    }
}
