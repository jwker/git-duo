import Foundation
import Testing

@testable import GitHubAPI

/// 仓库 Issue 列表（只读）—— TECH_SPEC §4.6.2、§4.14。
///
/// 核心是那条"**`GET /issues` 会混入 PR**"的固有行为：它不是边缘情况，
/// 而是每个仓库都会遇到的事，判据只有 `pull_request` 字段。
@Suite("GitHubRepoIssuesEndpoint · 只读 Issue 列表")
struct GitHubRepoIssuesEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEndpoint(harness: StubURLProtocol.Harness) -> GitHubRepoIssuesEndpoint {
        let clock = now
        return GitHubRepoIssuesEndpoint(
            client: GitHubRESTClient(
                credentials: credentials,
                transport: HTTPTransport(
                    credentials: credentials,
                    session: harness.makeSession(),
                    cache: HTTPResponseCache(configuration: .memoryOnly()),
                    retryPolicy: .none,
                    clock: { clock },
                    sleeper: { _ in }
                )
            )
        )
    }

    /// 一个普通 Issue（没有 `pull_request` 字段）。
    private let issueJSON = """
    {"number":42,"title":"登录按钮在真机上不可点","state":"open","comments":3,
     "created_at":"2026-10-06T08:00:00Z","user":{"login":"reviewer-a"}}
    """

    /// 一个**长得完全一样、但带 `pull_request`** 的条目 —— 它其实是个 PR。
    private let pullRequestJSON = """
    {"number":57,"title":"feat: 仓库详情四分区导航","state":"open","comments":0,
     "created_at":"2026-10-06T09:00:00Z","user":{"login":"dev-j"},
     "pull_request":{"url":"https://api.github.com/repos/o/r/pulls/57","merged_at":null}}
    """

    // MARK: - 请求形状

    @Test("请求形状：state=open + sort/direction/per_page 写全")
    func buildsRequestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        _ = try await makeEndpoint(harness: harness).openIssues(owner: "misoge", repo: "paneltkit")

        let url = try #require(harness.lastRequest?.url)
        #expect(url.path == "/repos/misoge/paneltkit/issues")

        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        // PRD §4.14 的说明行就是「开放 {N} 个」⇒ 本切片只取开放式
        #expect(query.first { $0.name == "state" }?.value == "open")
        // 显式写全，不依赖服务端默认值（它们也决定缓存键）
        #expect(query.first { $0.name == "sort" }?.value == "created")
        #expect(query.first { $0.name == "direction" }?.value == "desc")
        #expect(query.first { $0.name == "per_page" }?.value == "30")
    }

    // MARK: - PR 混入（本套件的靶心）

    @Test("⚠️ 混进来的 PR：靠 pull_request 字段认出来，而不是靠标题或作者")
    func distinguishesPullRequests() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[" + issueJSON + "," + pullRequestJSON + "]"))

        let page = try await makeEndpoint(harness: harness)
            .openIssues(owner: "misoge", repo: "paneltkit")

        #expect(page.items.count == 2, "数据层不过滤 —— 过滤是产品口径，属于调用方")
        #expect(page.items.first?.isPullRequest == false)
        #expect(page.items.last?.isPullRequest == true)
    }

    @Test("过滤后只剩 Issue：一页 30 条里可能只有 9 个 Issue（这不是 bug）")
    func filteringKeepsOnlyIssues() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[" + issueJSON + "," + pullRequestJSON + "]"))

        let page = try await makeEndpoint(harness: harness)
            .openIssues(owner: "misoge", repo: "paneltkit")

        let issues = page.items.filter { !$0.isPullRequest }
        #expect(issues.count == 1)
        #expect(issues.first?.number == 42)
    }

    // MARK: - 解码

    @Test("解码：编号 / 标题 / 状态 / 评论数 / 创建时间 / 作者")
    func decodesIssue() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[" + issueJSON + "]"))

        let page = try await makeEndpoint(harness: harness)
            .openIssues(owner: "o", repo: "r")

        let issue = try #require(page.items.first)
        #expect(issue.number == 42)
        #expect(issue.title == "登录按钮在真机上不可点")
        #expect(issue.state == "open")
        #expect(issue.comments == 3)
        #expect(issue.user?.login == "reviewer-a")
        #expect(issue.createdAt == (try #require(GitHubDate.parse("2026-10-06T08:00:00Z"))))
    }

    @Test("作者被删号（user 为 null）⇒ 不崩，作者留 nil")
    func deletedAuthorDoesNotBreakDecoding() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"[{"number":1,"title":"t","state":"open","comments":0,"created_at":"2026-10-06T08:00:00Z","user":null}]"#
            )
        )

        let page = try await makeEndpoint(harness: harness).openIssues(owner: "o", repo: "r")

        #expect(page.items.first?.user == nil)
        #expect(page.items.first?.title == "t")
    }

    // MARK: - 分页

    @Test("分页：nextCursor 取自 Link 的 rel=next")
    func exposesNextCursor() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                "[" + issueJSON + "]",
                headers: [
                    "Link": #"<https://api.github.com/repos/o/r/issues?state=open&page=2>; rel="next""#
                ]
            )
        )

        let page = try await makeEndpoint(harness: harness).openIssues(owner: "o", repo: "r")

        #expect(page.hasMore)
        #expect(
            page.nextCursor?.absoluteString
                == "https://api.github.com/repos/o/r/issues?state=open&page=2"
        )
    }

    @Test("续页：直接用服务端给的完整 URL")
    func followsCursorVerbatim() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        let cursor = URL(string: "https://api.github.com/repos/o/r/issues?state=open&page=3")!
        _ = try await makeEndpoint(harness: harness).openIssues(owner: "o", repo: "r", cursor: cursor)

        #expect(harness.lastRequest?.url?.absoluteString == cursor.absoluteString)
    }
}
