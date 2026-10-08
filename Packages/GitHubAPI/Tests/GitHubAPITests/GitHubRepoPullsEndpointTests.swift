import Foundation
import Testing

@testable import GitHubAPI

/// 仓库 PR（列表 / 详情 / 文件 / Commits / 评审 / 合并 / 关闭）
/// —— TECH_SPEC §4.6.2、§4.15、§9.9。
///
/// 靶心是那条"**GitHub 没有独立的 `merged` 状态**"的口径：
/// 合并与被关闭在 `state` 上长得一模一样，只能靠 `merged_at` 分开。
/// 切片 7 又加了一条同样性质的口径：**合并的 200 不等于成功**
/// （响应体里的 `merged` 才是判据，见 `PullMergeOutcome`）。
@Suite("GitHubRepoPullsEndpoint · 列表 / 详情 / 合并")
struct GitHubRepoPullsEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEndpoint(harness: StubURLProtocol.Harness) -> GitHubRepoPullsEndpoint {
        let clock = now
        return GitHubRepoPullsEndpoint(
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

    // MARK: - 请求形状

    @Test("请求形状：state=all（开放 + 已合并/已关闭都要）")
    func buildsRequestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        _ = try await makeEndpoint(harness: harness)
            .pullRequests(owner: "misoge", repo: "paneltkit", state: "all")

        let url = try #require(harness.lastRequest?.url)
        #expect(url.path == "/repos/misoge/paneltkit/pulls")

        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        // PRD §4.15 没规定，原型（事实优先级最高）是混排：两条开放 + 一条已合并。
        // 已合入的 PR 正是 §4.13 那句「查看他人贡献」最直接的证据。
        #expect(query.first { $0.name == "state" }?.value == "all")
        #expect(query.first { $0.name == "sort" }?.value == "created")
        #expect(query.first { $0.name == "direction" }?.value == "desc")
        #expect(query.first { $0.name == "per_page" }?.value == "30")
    }

    // MARK: - 已合并的判定（本套件的靶心）

    @Test("⚠️ 已合并 = state=closed **且** merged_at 非空（GitHub 没有 merged 状态）")
    func mergedNeedsBothStateAndTimestamp() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                """
                [
                  {"number":57,"title":"feat: 仓库详情四分区导航","state":"open","merged_at":null,
                   "head":{"ref":"feature/repo-hub"},"base":{"ref":"main"}},
                  {"number":51,"title":"fix: OAuth 回调地址校验","state":"closed","merged_at":"2026-10-03T08:00:00Z",
                   "head":{"ref":"fix/oauth"},"base":{"ref":"main"}},
                  {"number":49,"title":"chore: 试了一下又关了","state":"closed","merged_at":null,
                   "head":{"ref":"try/x"},"base":{"ref":"main"}}
                ]
                """
            )
        )

        let page = try await makeEndpoint(harness: harness)
            .pullRequests(owner: "o", repo: "r", state: "all")

        #expect(page.items.count == 3)
        #expect(page.items[0].isMerged == false, "还开着")
        #expect(page.items[1].isMerged, "closed + 有 merged_at ⇒ 已合并")
        // 这一条是重点：只看 state 就会把它也算成"已合并"
        #expect(page.items[2].isMerged == false, "closed 但 merged_at 为 null ⇒ 关闭未合并")
    }

    @Test("解码：编号 / 标题 / 状态 / 分支名")
    func decodesPullRequest() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"[{"number":57,"title":"feat: 仓库详情四分区导航","state":"open","merged_at":null,"head":{"ref":"feature/repo-hub","label":"dev-j:feature/repo-hub"},"base":{"ref":"main"}}]"#
            )
        )

        let page = try await makeEndpoint(harness: harness).pullRequests(owner: "o", repo: "r", state: "all")

        let pr = try #require(page.items.first)
        #expect(pr.number == 57)
        #expect(pr.title == "feat: 仓库详情四分区导航")
        #expect(pr.state == "open")
        #expect(pr.mergedAt == nil)
        #expect(pr.head.ref == "feature/repo-hub")
        #expect(pr.base.ref == "main")
    }

    @Test("合并时间：解出 merged_at 本身（不只是判断它在不在）")
    func decodesMergedAt() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"[{"number":51,"title":"t","state":"closed","merged_at":"2026-10-03T08:00:00Z","head":{"ref":"a"},"base":{"ref":"main"}}]"#
            )
        )

        let page = try await makeEndpoint(harness: harness).pullRequests(owner: "o", repo: "r", state: "all")

        let merged = try #require(GitHubDate.parse("2026-10-03T08:00:00Z"))
        #expect(page.items.first?.mergedAt == merged)
    }

    // MARK: - 分页

    @Test("分页：nextCursor 取自 Link 的 rel=next")
    func exposesNextCursor() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"[{"number":1,"title":"t","state":"open","merged_at":null,"head":{"ref":"a"},"base":{"ref":"main"}}]"#,
                headers: [
                    "Link": #"<https://api.github.com/repos/o/r/pulls?state=all&page=2>; rel="next""#
                ]
            )
        )

        let page = try await makeEndpoint(harness: harness).pullRequests(owner: "o", repo: "r", state: "all")

        #expect(page.hasMore)
        #expect(
            page.nextCursor?.absoluteString
                == "https://api.github.com/repos/o/r/pulls?state=all&page=2"
        )
    }

    @Test("续页：直接用服务端给的完整 URL")
    func followsCursorVerbatim() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        let cursor = URL(string: "https://api.github.com/repos/o/r/pulls?state=all&page=2")!
        _ = try await makeEndpoint(harness: harness)
            .pullRequests(owner: "o", repo: "r", state: "all", cursor: cursor)

        #expect(harness.lastRequest?.url?.absoluteString == cursor.absoluteString)
    }

    // MARK: - 切片 7：详情

    /// 一个最小的详情响应 —— 四个必需标量都给了。
    private let detailJSON = """
    {"number":57,"title":"feat: 仓库详情四分区导航","state":"open","merged_at":null,
     "head":{"ref":"feature/repo-hub"},"base":{"ref":"main"},
     "user":{"login":"dev-j"},"updated_at":"2026-10-06T09:00:00Z","body":"正文",
     "additions":842,"deletions":156,"changed_files":12}
    """

    @Test("详情：请求形状 + 解出增删与文件数（**列表端点给不了这三样**）")
    func decodesDetailWithStats() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(detailJSON))

        let detail = try await makeEndpoint(harness: harness)
            .pullRequest(owner: "misoge", repo: "paneltkit", number: 57)

        #expect(harness.lastRequest?.url?.path == "/repos/misoge/paneltkit/pulls/57")
        #expect(detail.number == 57)
        #expect(detail.additions == 842)
        #expect(detail.deletions == 156)
        #expect(detail.changedFiles == 12, "「{N} 个文件」用这个，不是文件那一页的条数")
        #expect(detail.user?.login == "dev-j")
        #expect(detail.base.ref == "main")
    }

    @Test("详情：作者被删号（user 为 null）⇒ 不崩，作者留 nil")
    func detailToleratesDeletedAuthor() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                """
                {"number":1,"title":"t","state":"open","merged_at":null,
                 "head":{"ref":"a"},"base":{"ref":"main"},"user":null,
                 "additions":0,"deletions":0,"changed_files":0}
                """
            )
        )

        let detail = try await makeEndpoint(harness: harness)
            .pullRequest(owner: "o", repo: "r", number: 1)

        #expect(detail.user == nil)
        #expect(detail.updatedAt == nil, "少一个时间不该让整页打不开")
        #expect(detail.body == nil)
    }

    // MARK: - 切片 7：文件 / Commits / 评审

    @Test("文件：per_page=100，且每个文件的 patch 原样带出")
    func decodesFiles() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                """
                [{"filename":"GitDuo/App/AppTabs.swift","status":"modified","additions":46,"deletions":12,
                  "changes":58,"patch":"@@ -12,7 +12,9 @@\\n-  old\\n+  new"},
                 {"filename":"Assets/logo.png","status":"added","additions":0,"deletions":0,
                  "changes":0,"patch":null}]
                """
            )
        )

        let page = try await makeEndpoint(harness: harness)
            .pullFiles(owner: "o", repo: "r", number: 57)

        let url = try #require(harness.lastRequest?.url)
        #expect(url.path == "/repos/o/r/pulls/57/files")
        #expect(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "per_page" }?.value == "100"
        )
        #expect(page.items.count == 2)
        #expect(page.items.first?.patch?.contains("-  old") == true)
        // patch 缺席有两种成因（二进制 / 改动过大），数据层**不做判断**，原样带出去
        #expect(page.items.last?.patch == nil)
    }

    @Test("Commits：走 PR 的子端点，条目形状与提交列表一致")
    func decodesCommits() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"[{"sha":"c881f0b","commit":{"message":"feat: x","author":{"date":"2026-10-06T08:00:00Z"}},"author":{"login":"dev-j"}}]"#
            )
        )

        let page = try await makeEndpoint(harness: harness)
            .pullCommits(owner: "o", repo: "r", number: 57)

        #expect(harness.lastRequest?.url?.path == "/repos/o/r/pulls/57/commits")
        #expect(page.items.first?.sha == "c881f0b")
        #expect(page.items.first?.author?.login == "dev-j")
    }

    @Test("评审：**走 /reviews 而不是 /comments**（决策 #60）")
    func decodesReviewsFromReviewsEndpoint() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                """
                [{"id":1,"user":{"login":"dev-k"},"state":"APPROVED","body":"LGTM",
                  "submitted_at":"2026-10-06T07:00:00Z"},
                 {"id":2,"user":{"login":"dev-m"},"state":"COMMENTED","body":null,"submitted_at":null}]
                """
            )
        )

        let page = try await makeEndpoint(harness: harness)
            .pullReviews(owner: "o", repo: "r", number: 57)

        #expect(
            harness.lastRequest?.url?.path == "/repos/o/r/pulls/57/reviews",
            "行内评论在 /comments —— 审批状态不在那儿"
        )
        #expect(page.items.first?.state == "APPROVED")
        #expect(page.items.first?.body == "LGTM")
        // PENDING 的评审还没提交 ⇒ 时间是 null（不编一个"刚刚"）
        #expect(page.items.last?.submittedAt == nil)
    }

    // MARK: - 切片 7：合并（本套件的第二个靶心）

    @Test("合并：PUT + 请求体只有 merge_method，三种方式原样发出")
    func mergeSendsMethodVerbatim() async throws {
        for method in PullMergeMethod.allCases {
            let harness = StubURLProtocol.makeHarness()
            harness.stub(.json(#"{"sha":"s","merged":true,"message":"ok"}"#))

            let outcome = try await makeEndpoint(harness: harness)
                .mergePull(owner: "o", repo: "r", number: 57, method: method)

            #expect(harness.lastRequest?.httpMethod == "PUT")
            #expect(harness.lastRequest?.url?.path == "/repos/o/r/pulls/57/merge")

            let body = try #require(harness.lastBody)
            let json = try #require(
                try JSONSerialization.jsonObject(with: body) as? [String: String]
            )
            #expect(json == ["merge_method": method.rawValue])

            guard case .merged(let result) = outcome else {
                Issue.record("\(method.rawValue)：应当判为已合并")
                continue
            }
            #expect(result.merged)
        }
    }

    @Test("⚠️ 合并：405 ⇒ .notMergeable（**这不是失败**，是「不能合」的确凿答案）")
    func mergeTreats405AsNotMergeable() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"message":"Pull Request is not mergeable"}"#, status: 405))

        let outcome = try await makeEndpoint(harness: harness)
            .mergePull(owner: "o", repo: "r", number: 57, method: .merge)

        #expect(outcome == .notMergeable)
    }

    @Test("⚠️ 合并：200 但响应体说 merged=false ⇒ 也判 .notMergeable（**只看状态码就会报假成功**）")
    func mergeTrustsBodyOverStatusCode() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"sha":null,"merged":false,"message":"not mergeable"}"#))

        let outcome = try await makeEndpoint(harness: harness)
            .mergePull(owner: "o", repo: "r", number: 57, method: .merge)

        #expect(outcome == .notMergeable)
    }

    @Test("合并：409 冲突照旧抛错（那条要引导去网页端，不能折进 notMergeable）")
    func mergeThrowsOnConflict() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"message":"Merge conflict"}"#, status: 409))

        await #expect(throws: GitHubError.conflict) {
            _ = try await makeEndpoint(harness: harness)
                .mergePull(owner: "o", repo: "r", number: 57, method: .merge)
        }
    }

    @Test("合并：404 照旧抛错（「不存在或无权访问」 —— 与「不能合」是两件事）")
    func mergeThrowsOnNotFound() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"message":"Not Found"}"#, status: 404))

        await #expect(throws: GitHubError.notFound) {
            _ = try await makeEndpoint(harness: harness)
                .mergePull(owner: "o", repo: "r", number: 57, method: .merge)
        }
    }

    // MARK: - 切片 7：关闭 / 重新打开

    @Test("关闭 / 重新打开：PATCH + 请求体只有 state，回的是**服务端给的那份详情**")
    func updateStateSendsPatchAndReturnsServerDetail() async throws {
        for state in ["closed", "open"] {
            let harness = StubURLProtocol.makeHarness()
            harness.stub(.json(detailJSON.replacingOccurrences(of: #""state":"open""#, with: #""state":"\#(state)""#)))

            let detail = try await makeEndpoint(harness: harness)
                .updatePullState(owner: "o", repo: "r", number: 57, state: state)

            #expect(harness.lastRequest?.httpMethod == "PATCH")
            #expect(harness.lastRequest?.url?.path == "/repos/o/r/pulls/57")

            let body = try #require(harness.lastBody)
            let json = try #require(
                try JSONSerialization.jsonObject(with: body) as? [String: String]
            )
            #expect(json == ["state": state])
            #expect(detail.state == state)
        }
    }
}
