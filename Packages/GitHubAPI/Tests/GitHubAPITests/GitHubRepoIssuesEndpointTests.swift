import Foundation
import Testing

@testable import GitHubAPI

/// 仓库 Issue（列表 / 详情 / 评论 / 新建）—— TECH_SPEC §4.6.2、§4.14、§9.8。
///
/// 核心是那条"**`GET /issues` 会混入 PR**"的固有行为：它不是边缘情况，
/// 而是每个仓库都会遇到的事，判据只有 `pull_request` 字段。
///
/// 切片 7 又加了两条同源的口径：**列表要按状态与标签取**（决策 #56，标签走服务端、
/// 不本地过滤）、**详情是两次请求**（决策 #57，正文与评论各自失败各自重试）。
@Suite("GitHubRepoIssuesEndpoint · 列表 / 详情 / 评论")
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

        _ = try await makeEndpoint(harness: harness).issues(owner: "misoge", repo: "paneltkit", state: "open")

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
            .issues(owner: "misoge", repo: "paneltkit", state: "open")

        #expect(page.items.count == 2, "数据层不过滤 —— 过滤是产品口径，属于调用方")
        #expect(page.items.first?.isPullRequest == false)
        #expect(page.items.last?.isPullRequest == true)
    }

    @Test("过滤后只剩 Issue：一页 30 条里可能只有 9 个 Issue（这不是 bug）")
    func filteringKeepsOnlyIssues() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[" + issueJSON + "," + pullRequestJSON + "]"))

        let page = try await makeEndpoint(harness: harness)
            .issues(owner: "misoge", repo: "paneltkit", state: "open")

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
            .issues(owner: "o", repo: "r", state: "open")

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

        let page = try await makeEndpoint(harness: harness).issues(owner: "o", repo: "r", state: "open")

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

        let page = try await makeEndpoint(harness: harness).issues(owner: "o", repo: "r", state: "open")

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
        _ = try await makeEndpoint(harness: harness)
            .issues(owner: "o", repo: "r", state: "open", cursor: cursor)

        #expect(harness.lastRequest?.url?.absoluteString == cursor.absoluteString)
    }

    // MARK: - 切片 7：状态与标签（决策 #56）

    @Test("列表：state 与 labels 都按参数发出（标签逗号分隔即多选）")
    func sendsStateAndLabels() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        _ = try await makeEndpoint(harness: harness)
            .issues(owner: "o", repo: "r", state: "closed", labels: ["bug", "good first issue"])

        let url = try #require(harness.lastRequest?.url)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "state" }?.value == "closed")
        #expect(query.first { $0.name == "labels" }?.value == "bug,good first issue")
    }

    @Test("⚠️ 列表：标签为空时**不带** `labels` 参数（发空串会被当成「筛一个空名字的标签」）")
    func omitsLabelsWhenEmpty() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        _ = try await makeEndpoint(harness: harness).issues(owner: "o", repo: "r", state: "open")

        let url = try #require(harness.lastRequest?.url)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains { $0.name == "labels" } == false)
    }

    @Test("列表：解出标签数组（仓库详情卡片要用；探索页只是不画）")
    func decodesLabels() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                """
                [{"number":42,"title":"t","state":"open","comments":0,
                  "created_at":"2026-10-06T08:00:00Z","user":{"login":"a"},
                  "labels":[{"name":"bug","color":"d73a4a","description":null},
                            {"name":"docs","color":"0075ca","description":"文档相关"}]}]
                """
            )
        )

        let page = try await makeEndpoint(harness: harness).issues(owner: "o", repo: "r", state: "open")

        let labels = try #require(page.items.first?.labels)
        #expect(labels.map(\.name) == ["bug", "docs"])
        // 色值原样保留、**不带 `#`** —— 美化 / 剥除都留给消费端（`LabelDTO` 的说明）
        #expect(labels.first?.color == "d73a4a")
        #expect(labels.last?.description == "文档相关")
    }

    // MARK: - 切片 7：详情（决策 #57）

    @Test("详情：GET /issues/{n}，解出正文与关闭时间")
    func decodesIssueDetail() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                """
                {"number":42,"title":"登录按钮在真机上不可点","state":"closed",
                 "body":"真机上 `session.start()` 返回 false 后状态没有回退。",
                 "user":{"login":"reviewer-a"},"created_at":"2026-10-06T08:00:00Z",
                 "closed_at":"2026-10-09T08:00:00Z"}
                """
            )
        )

        let detail = try await makeEndpoint(harness: harness).issue(owner: "o", repo: "r", number: 42)

        #expect(harness.lastRequest?.url?.path == "/repos/o/r/issues/42")
        #expect(detail.number == 42)
        #expect(detail.title == "登录按钮在真机上不可点")
        #expect(detail.state == "closed")
        #expect(detail.user?.login == "reviewer-a")
        #expect(detail.closedAt == (try #require(GitHubDate.parse("2026-10-09T08:00:00Z"))))
    }

    @Test("详情：只写标题（body 为 null）⇒ 不崩")
    func detailToleratesMissingBody() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"{"number":1,"title":"只有标题","state":"open","body":null,"user":null,"created_at":"2026-10-06T08:00:00Z","closed_at":null}"#
            )
        )

        let detail = try await makeEndpoint(harness: harness).issue(owner: "o", repo: "r", number: 1)

        #expect(detail.body == nil)
        #expect(detail.user == nil)
        #expect(detail.closedAt == nil)
    }

    // MARK: - 切片 7：评论

    @Test("评论：per_page=100 且按时间正序（讨论要从上往下读）")
    func commentsRequestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        _ = try await makeEndpoint(harness: harness).issueComments(owner: "o", repo: "r", number: 42)

        let url = try #require(harness.lastRequest?.url)
        #expect(url.path == "/repos/o/r/issues/42/comments")
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "per_page" }?.value == "100")
        #expect(query.first { $0.name == "direction" }?.value == "asc")
    }

    @Test("评论：解出 id / 正文 / 作者 / 时间；作者被删号不崩")
    func decodesComments() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                """
                [{"id":901,"body":"已确认，修复在 `feature/auth-fix` 分支。","user":{"login":"you"},
                  "created_at":"2026-10-06T09:00:00Z"},
                 {"id":902,"body":"这条的作者已注销","user":null,"created_at":"2026-10-06T10:00:00Z"}]
                """
            )
        )

        let page = try await makeEndpoint(harness: harness)
            .issueComments(owner: "o", repo: "r", number: 42)

        #expect(page.items.count == 2)
        #expect(page.items.first?.id == 901)
        #expect(page.items.first?.user?.login == "you")
        #expect(page.items.last?.user == nil)
    }

    // MARK: - 切片 7：写（新建 Issue / 发评论）

    @Test("新建 Issue：POST + 请求体带 title / body / labels")
    func createIssuePayload() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"{"number":43,"title":"原型反馈：Issues 不可点开","state":"open","user":{"login":"you"},"created_at":"2026-10-08T08:00:00Z"}"#,
                status: 201
            )
        )

        let detail = try await makeEndpoint(harness: harness).createIssue(
            owner: "o",
            repo: "r",
            title: "原型反馈：Issues 不可点开",
            body: "描述",
            labels: ["bug", "performance"]
        )

        #expect(harness.lastRequest?.httpMethod == "POST")
        #expect(harness.lastRequest?.url?.path == "/repos/o/r/issues")

        let body = try #require(harness.lastBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["title"] as? String == "原型反馈：Issues 不可点开")
        #expect(json["body"] as? String == "描述")
        #expect(json["labels"] as? [String] == ["bug", "performance"])
        #expect(detail.number == 43)
    }

    @Test("新建 Issue：不带标签时请求体里**没有** labels（不是空数组）")
    func createIssueOmitsEmptyLabels() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"number":1,"title":"t","state":"open","created_at":"2026-10-08T08:00:00Z"}"#, status: 201))

        _ = try await makeEndpoint(harness: harness)
            .createIssue(owner: "o", repo: "r", title: "t", body: nil, labels: [])

        let body = try #require(harness.lastBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["labels"] == nil)
        #expect(json["body"] == nil, "空正文不带这个字段（服务端会存成空串）")
    }

    @Test("发评论：POST /issues/{n}/comments，请求体只有 body，回的是服务端那条评论")
    func createCommentPayload() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"{"id":903,"body":"LGTM 下一个就合","user":{"login":"you"},"created_at":"2026-10-08T09:00:00Z"}"#,
                status: 201
            )
        )

        let comment = try await makeEndpoint(harness: harness)
            .createIssueComment(owner: "o", repo: "r", number: 42, body: "LGTM 下一个就合")

        #expect(harness.lastRequest?.httpMethod == "POST")
        #expect(harness.lastRequest?.url?.path == "/repos/o/r/issues/42/comments")

        let body = try #require(harness.lastBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json as? [String: String] == ["body": "LGTM 下一个就合"])
        // ⚠️ 用服务端回的那条，不自己造"刚刚"（时间与 id 都以服务端为准）
        #expect(comment.id == 903)
        #expect(comment.user?.login == "you")
    }
}
