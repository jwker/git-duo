import Foundation
import Testing

@testable import GitHubAPI

/// 仓库 PR 列表（只读，开放 + 已合并）—— TECH_SPEC §4.6.2、§4.15。
///
/// 靶心是那条"**GitHub 没有独立的 `merged` 状态**"的口径：
/// 合并与被关闭在 `state` 上长得一模一样，只能靠 `merged_at` 分开。
@Suite("GitHubRepoPullsEndpoint · 只读 PR 列表")
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

        _ = try await makeEndpoint(harness: harness).pullRequests(owner: "misoge", repo: "paneltkit")

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
            .pullRequests(owner: "o", repo: "r")

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

        let page = try await makeEndpoint(harness: harness).pullRequests(owner: "o", repo: "r")

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

        let page = try await makeEndpoint(harness: harness).pullRequests(owner: "o", repo: "r")

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

        let page = try await makeEndpoint(harness: harness).pullRequests(owner: "o", repo: "r")

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
            .pullRequests(owner: "o", repo: "r", cursor: cursor)

        #expect(harness.lastRequest?.url?.absoluteString == cursor.absoluteString)
    }
}
