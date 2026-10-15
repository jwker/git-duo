import Foundation
import Testing

@testable import GitHubAPI

/// 他人仓库详情的四路数据 —— TECH_SPEC §9.11、§4.6.3。
///
/// 本套件盯的是**四个真实存在、且都不会报错的坑**：
/// 1. `subscribers_count` vs `watchers_count`（后者是 stargazers 的历史别名）；
/// 2. `releases/latest` 用 **404 表示"没有版本"**；
/// 3. `contributors` 对空仓库回 **204 而不是 200 + `[]`**；
/// 4. 匿名贡献者的 `login` 是 **null**，不该让整段解码失败。
@Suite("GitHubRepoInsightsEndpoint · 仓库头部 / 语言 / 版本 / 贡献者")
struct GitHubRepoInsightsEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEndpoint(harness: StubURLProtocol.Harness) -> GitHubRepoInsightsEndpoint {
        let clock = now
        return GitHubRepoInsightsEndpoint(
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

    /// ⚠️ 特意让 `watchers_count`（2341，等于 stargazers）与 `subscribers_count`（45）**不相等**
    /// —— 相等的话这个坑就验不出来了。
    private let fullRepoJSON = """
    {
      "full_name":"misoge/paneltkit",
      "description":"SwiftUI 自适应布局工具库",
      "topics":["swiftui","layout","ios"],
      "license":{"key":"mit","name":"MIT License","spdx_id":"MIT"},
      "default_branch":"main",
      "stargazers_count":2341,
      "forks_count":88,
      "watchers_count":2341,
      "subscribers_count":45,
      "pushed_at":"2026-10-06T10:00:00Z",
      "permissions":{"push":false,"pull":true},
      "owner":{"avatar_url":"https://avatars.githubusercontent.com/u/1?v=4"}
    }
    """

    // MARK: - 仓库头部

    @Test("解码：头部字段逐个对得上（含 topics / license / default_branch / pushed_at）")
    func decodesRepository() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(fullRepoJSON))

        let repo = try await makeEndpoint(harness: harness)
            .repository(owner: "misoge", repo: "paneltkit")

        #expect(repo.fullName == "misoge/paneltkit")
        #expect(repo.description == "SwiftUI 自适应布局工具库")
        #expect(repo.topics == ["swiftui", "layout", "ios"])
        #expect(repo.license?.spdxID == "MIT")
        #expect(repo.license?.name == "MIT License")
        #expect(repo.defaultBranch == "main", "分支解析规则的输入（§9.4.1）")
        #expect(repo.starCount == 2341)
        #expect(repo.forkCount == 88)
        // ⚠️ `try #require` **写在 `#expect` 外面**：放里面会让 swift-testing 的宏
        //    报一条"`#require` 是多余的"假警告（它以为 `parse` 不返回 `nil`）。
        //    这不是风格问题 —— 本项目要求零编译警告，而这条警告只在全量重编时才会出现。
        let pushedAt = try #require(GitHubDate.parse("2026-10-06T10:00:00Z"))
        #expect(repo.pushedAt == pushedAt)
        #expect(repo.permissions?.push == false, "可写性判定的唯一来源（§9.11）")
    }

    @Test("⚠️ Watch 计数取的是 subscribers_count，不是大 52 倍的 watchers_count")
    func watcherCountComesFromSubscribers() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(fullRepoJSON))

        let repo = try await makeEndpoint(harness: harness)
            .repository(owner: "misoge", repo: "paneltkit")

        // 读错字段**不会报错**，只会让 `Watch · 2,341` 与旁边的 `Star · 2,341` 显示成同一个数
        // —— 一个"看着很合理"的错值，几乎不可能在评审时被发现。
        #expect(repo.watcherCount == 45)
        #expect(repo.watcherCount != repo.starCount)
    }

    @Test("`topics` 整段缺失 ⇒ nil（与空数组等价），不是整页报错")
    func missingTopicsIsNil() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"{"full_name":"a/b","default_branch":"main","stargazers_count":1,"forks_count":0,"subscribers_count":0,"owner":{"avatar_url":"https://avatars.githubusercontent.com/u/2?v=4"}}"#
            )
        )

        let repo = try await makeEndpoint(harness: harness)
            .repository(owner: "a", repo: "b")

        #expect(repo.topics == nil)
        #expect(repo.license == nil)
        #expect(repo.pushedAt == nil)
        #expect(repo.permissions == nil, "未认证 / 无权限时 GitHub 不返回 permissions ⇒ 解释成不可写")
    }

    @Test("请求路径就是 repos/{owner}/{repo}（不额外带查询串）")
    func repositoryPathShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(fullRepoJSON))

        _ = try await makeEndpoint(harness: harness).repository(owner: "misoge", repo: "paneltkit")

        #expect(harness.lastRequest?.url?.absoluteString == "https://api.github.com/repos/misoge/paneltkit")
        #expect(harness.lastRequest?.httpMethod == "GET")
    }

    // MARK: - 语言构成

    @Test("语言：解出「语言 → 字节数」的字典（官方只给字节数，不给百分比）")
    func decodesLanguages() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"Swift":72000,"Shell":18000,"Ruby":10000}"#))

        let languages = try await makeEndpoint(harness: harness)
            .languages(owner: "misoge", repo: "paneltkit")

        #expect(languages == ["Swift": 72000, "Shell": 18000, "Ruby": 10000])
        #expect(languages.values.reduce(0, +) == 100_000)
    }

    @Test("空仓库：`/languages` 回空对象 ⇒ 空字典，不是失败")
    func emptyLanguagesIsFine() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("{}"))

        let languages = try await makeEndpoint(harness: harness)
            .languages(owner: "a", repo: "b")

        #expect(languages.isEmpty)
    }

    // MARK: - Latest Release（404 的例外）

    @Test("Latest Release：解出 tag / 正文 / 发布时间，并给出资产条数")
    func decodesLatestRelease() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                """
                {"tag_name":"v2.1.0","name":"2.1.0","body":"新增 Hinge 感知布局容器",
                 "published_at":"2026-10-03T08:00:00Z","draft":false,"prerelease":false,
                 "assets":[{"name":"a.zip","size":12},{"name":"b.zip","size":34},{"name":"c.zip","size":56}]}
                """
            )
        )

        let release = try await makeEndpoint(harness: harness)
            .latestRelease(owner: "misoge", repo: "paneltkit")

        let unwrapped = try #require(release)
        #expect(unwrapped.tagName == "v2.1.0")
        #expect(unwrapped.body == "新增 Hinge 感知布局容器")
        // 同上：`#require` 必须在 `#expect` 外面（见本条的第一个用例）
        let publishedAt = try #require(GitHubDate.parse("2026-10-03T08:00:00Z"))
        #expect(unwrapped.publishedAt == publishedAt)
        #expect(unwrapped.assetCount == 3, "「资产 (3)」按钮只关心个数，所以资产条目故意不声明字段")
    }

    @Test("⚠️ 404 ⇒ nil（很多仓库有 tag 但没有 published release，这是**正常结果**）")
    func latestRelease404MeansNone() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"message":"Not Found"}"#, status: 404))

        let release = try await makeEndpoint(harness: harness)
            .latestRelease(owner: "misoge", repo: "paneltkit")

        // 这一步不做的后果很具体：一个只是没发过版本的仓库，整个详情页会显示成"加载失败"。
        #expect(release == nil)
    }

    @Test("⚠️ 但 500 **必须抛出去** —— 不能把它也吞成「没有版本」")
    func latestReleaseServerErrorThrows() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"message":"boom"}"#, status: 500))

        do {
            _ = try await makeEndpoint(harness: harness)
                .latestRelease(owner: "misoge", repo: "paneltkit")
            Issue.record("5xx 不该被解释成「这个仓库没有版本」")
        } catch let error as GitHubError {
            guard case .serverError = error else {
                Issue.record("应归为 .serverError，实际：\(error)")
                return
            }
        }
        // 为什么：把 5xx / 断网也吞成 nil，用户会看到"这个仓库没有版本"，
        // 而事实是服务端挂了或网络断了 —— "断网 ≠ 没有数据"。
    }

    // MARK: - 贡献者

    @Test("贡献者：解出条目，并带 per_page=100（一页取回，用于推导总数）")
    func decodesContributors() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"[{"login":"octocat","avatar_url":"https://avatars.githubusercontent.com/u/1","contributions":32},{"login":"dev-j","avatar_url":"https://avatars.githubusercontent.com/u/2","contributions":18}]"#
            )
        )

        let page = try await makeEndpoint(harness: harness)
            .contributors(owner: "misoge", repo: "paneltkit")

        #expect(page.items.count == 2)
        #expect(page.items.first?.login == "octocat")
        #expect(page.items.first?.avatarURL?.contains("avatars.githubusercontent.com") == true)
        #expect(GitHubRepoInsightsEndpoint.contributorPageSize == 100)

        let url = try #require(harness.lastRequest?.url)
        #expect(url.path == "/repos/misoge/paneltkit/contributors")
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first { $0.name == "per_page" }?.value == "100")
    }

    @Test("⚠️ 空仓库回 204 ⇒ 空列表（不是「加载失败」）")
    func contributors204IsEmpty() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 204))

        let page = try await makeEndpoint(harness: harness)
            .contributors(owner: "misoge", repo: "paneltkit")

        // 官方文档明确：`Response if repository is empty` 是 **204 No Content**。
        // 直接用 `client.page(...)` 会拿一个空 body 去解 `[T]` ⇒ 解码失败，
        // 于是"还没有贡献者"被显示成"加载失败"。
        #expect(page.items.isEmpty)
        #expect(!page.hasMore)
    }

    @Test("匿名贡献者（login / avatar_url 为 null）⇒ 不崩，原样保留 nil")
    func anonymousContributorDoesNotBreakDecoding() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"[{"login":null,"avatar_url":null,"contributions":3},{"login":"octocat","avatar_url":"https://a/u/1","contributions":2}]"#
            )
        )

        let page = try await makeEndpoint(harness: harness)
            .contributors(owner: "misoge", repo: "paneltkit")

        // 把 login 声明成必需 `String` 会让**一个**匿名贡献者把整个数组打掉，
        // 表现是"这个仓库的贡献者整块显示不出来"，而它其实只差一个名字。
        #expect(page.items.count == 2)
        #expect(page.items.first?.login == nil)
        #expect(page.items.last?.login == "octocat")
    }

    @Test("贡献者超过一页：hasMore 为真 ⇒ 界面只能说「100 位以上」")
    func contributorsOverOnePageExposeHasMore() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"[{"login":"a","avatar_url":null,"contributions":1}]"#,
                headers: [
                    "Link": #"<https://api.github.com/repos/o/r/contributors?per_page=100&page=2>; rel="next""#
                ]
            )
        )

        let page = try await makeEndpoint(harness: harness)
            .contributors(owner: "o", repo: "r")

        #expect(page.hasMore)
        #expect(
            page.nextCursor?.absoluteString
                == "https://api.github.com/repos/o/r/contributors?per_page=100&page=2"
        )
    }
}
