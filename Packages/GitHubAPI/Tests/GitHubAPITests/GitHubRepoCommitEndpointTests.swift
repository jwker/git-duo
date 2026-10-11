import Foundation
import Testing

@testable import GitHubAPI

/// 提交：列表 / 详情。
/// TECH_SPEC §4.6.2 / §9.5。
/// （「某一文件的最近一条」于 2026-10-11 随决策 #49 一起删除。）
///
/// 靶心是**列表与详情的字段差**（列表没有 `files` / `stats`）与
/// **`authoredAt` 的回落链** —— 后者是"宁可解码失败也不编一个时间"那条纪律的落点。
@Suite("GitHubRepoCommitEndpoint · 列表 / 详情")
struct GitHubRepoCommitEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEndpoint(harness: StubURLProtocol.Harness) -> GitHubRepoCommitEndpoint {
        let clock = now
        return GitHubRepoCommitEndpoint(
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

    /// 一条最小可用的列表项 JSON（作者时间齐备）。
    private func listItemJSON(
        sha: String = "abc1234def",
        message: String = "feat: 仓库详情四分区导航",
        login: String = "dev-j"
    ) -> String {
        """
        {"sha":"\(sha)",
         "commit":{"message":"\(message)",
                   "author":{"name":"Jiang","email":"j@example.com","date":"2026-10-05T08:00:00Z"}},
         "author":{"login":"\(login)","avatar_url":"https://avatars.example/u/1"}}
        """
    }

    // MARK: - 列表：请求形状

    @Test("列表：sha={分支} + per_page=30（显式写全，不依赖服务端默认值）")
    func listRequestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        _ = try await makeEndpoint(harness: harness)
            .commits(owner: "o", repo: "r", branch: "feature/repo-hub")

        let url = try #require(harness.lastRequest?.url)
        #expect(url.path == "/repos/o/r/commits")

        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "sha" }?.value == "feature/repo-hub")
        #expect(query.first { $0.name == "per_page" }?.value == "30")
    }

    @Test("列表：分支为 nil ⇒ **不带** sha（服务端才用默认分支）")
    func listOmitsBranchWhenNil() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        _ = try await makeEndpoint(harness: harness).commits(owner: "o", repo: "r", branch: nil)

        let url = try #require(harness.lastRequest?.url)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "sha" } == nil)
        #expect(query.first { $0.name == "per_page" }?.value == "30")
    }

    @Test("列表续页：直接用服务端给的完整 URL")
    func listFollowsCursorVerbatim() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        let cursor = URL(string: "https://api.github.com/repos/o/r/commits?sha=main&page=2")!
        _ = try await makeEndpoint(harness: harness).commits(owner: "o", repo: "r", cursor: cursor)

        #expect(harness.lastRequest?.url?.absoluteString == cursor.absoluteString)
    }

    // MARK: - 列表：字段

    @Test("列表：sha / 信息 / 作者账号 / 头像 / 作者时间")
    func listDecodesFields() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[\(listItemJSON())]"))

        let page = try await makeEndpoint(harness: harness).commits(owner: "o", repo: "r")

        let item = try #require(page.items.first)
        #expect(item.sha == "abc1234def")
        #expect(item.commit.message == "feat: 仓库详情四分区导航")
        #expect(item.author?.login == "dev-j")
        #expect(item.author?.avatarURL == URL(string: "https://avatars.example/u/1"))
        #expect(item.authoredAt == GitHubDate.parse("2026-10-05T08:00:00Z"))
    }

    @Test("列表：顶层 `author: null` ⇒ nil（邮箱没关联账号 / 账号已删），不失败")
    func listToleratesNullAuthor() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                """
                [{"sha":"s1",
                  "commit":{"message":"chore","author":{"name":"J","email":"j@e.com","date":"2026-10-05T08:00:00Z"}},
                  "author":null}]
                """
            )
        )

        let item = try #require(
            try await makeEndpoint(harness: harness).commits(owner: "o", repo: "r").items.first
        )
        #expect(item.author == nil)
        // 时间仍然拿得到 —— 它来自 commit.author，不是顶层 author
        #expect(item.authoredAt == GitHubDate.parse("2026-10-05T08:00:00Z"))
    }

    // MARK: - authoredAt 的回落链（本套件的靶心）

    @Test("⚠️ commit.author 整个缺席 ⇒ 回落到 commit.committer.date")
    func authoredAtFallsBackToCommitter() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                """
                [{"sha":"s1",
                  "commit":{"message":"chore",
                            "committer":{"name":"J","email":"j@e.com","date":"2026-10-06T09:00:00Z"}},
                  "author":{"login":"dev-j"}}]
                """
            )
        )

        let item = try #require(
            try await makeEndpoint(harness: harness).commits(owner: "o", repo: "r").items.first
        )
        #expect(item.authoredAt == GitHubDate.parse("2026-10-06T09:00:00Z"))
    }

    @Test("⚠️ author 与 committer 都没有时间 ⇒ **解码失败**（宁可整页报错，也不编一个时间）")
    func missingDatesFailLoudly() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"[{"sha":"s1","commit":{"message":"chore"}}]"#))

        // 补一个 1970 年会让列表行写着"1970 年提交" —— 一个"看着合理"的错值。
        // 结构真的变了时，"整个列表报错"才是我们想看到的信号。
        await #expect(throws: GitHubError.self) {
            _ = try await makeEndpoint(harness: harness).commits(owner: "o", repo: "r")
        }
    }

    // MARK: - 详情

    @Test("详情：stats + files（含 patch）逐个对")
    func detailDecodesStatsAndFiles() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                """
                {"sha":"deadbeef",
                 "commit":{"message":"feat: 仓库详情四分区导航\\n\\n正文一段。",
                           "author":{"name":"J","email":"j@e.com","date":"2026-10-05T08:00:00Z"}},
                 "author":{"login":"dev-j"},
                 "stats":{"additions":12,"deletions":4,"total":16},
                 "files":[
                   {"filename":"GitDuo/App/Tabs.swift","additions":12,"deletions":4,
                    "status":"modified","patch":"@@ -1,2 +1,3 @@\\n a\\n+b"},
                   {"filename":"Assets/logo.png","additions":0,"deletions":0,"status":"added"}
                 ]}
                """
            )
        )

        let detail = try await makeEndpoint(harness: harness)
            .commit(owner: "o", repo: "r", sha: "deadbeef")

        #expect(harness.lastRequest?.url?.path == "/repos/o/r/commits/deadbeef")
        #expect(detail.sha == "deadbeef")
        #expect(detail.stats == CommitStatsDTO(additions: 12, deletions: 4, total: 16))
        #expect(detail.files.count == 2)
        #expect(detail.files[0].filename == "GitDuo/App/Tabs.swift")
        #expect(detail.files[0].status == "modified")
        #expect(detail.files[0].patch?.contains("+b") == true)
        // ⚠️ 二进制文件的 patch 缺席是**正常**的（服务端给不出文本 diff），
        //    数据层原样带出去，判"是不是二进制"是领域层的事
        #expect(detail.files[1].patch == nil)
    }

    @Test("详情：`files` 缺席 ⇒ 空数组；`stats` 缺席 ⇒ nil（都不失败）")
    func detailToleratesMissingFilesAndStats() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                """
                {"sha":"s1",
                 "commit":{"message":"chore","author":{"date":"2026-10-05T08:00:00Z"}}}
                """
            )
        )

        let detail = try await makeEndpoint(harness: harness).commit(owner: "o", repo: "r", sha: "s1")

        #expect(detail.files.isEmpty)
        #expect(detail.stats == nil)
    }
}
