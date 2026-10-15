import Foundation
import Testing

@testable import GitHubAPI

/// 切片 6 / 7 / 8 数据层的**配额桶守卫**（TECH_SPEC §4.5、§13.2）。
///
/// ## 为什么需要这一套
///
/// `HTTPRequest.rateLimitResource` 的默认值是 `.core`，而 `.core` 是**不限速**的
/// （间隔 0）—— 于是"本该声明成 `.search` 却忘了"这种事**不会有任何提示**：
/// 编译过得去、测试过得去、跑起来也正常，直到某天配额被打爆。
/// 反过来，切片 6 起这些路由**全部在主桶上**（5,000/小时，靠 ETag 压住），
/// 一条都不该落到搜索桶 —— 而这个"全都不是搜索"的事实同样不会自己说话。
/// 切片 8 的三条写（`PUT` / `DELETE contents`、`POST pulls`）同样在主桶。
///
/// ## 怎么验（这里有意绕开"默认值"
///
/// 给限流器一份**每个桶间隔都非 0** 的策略表，于是每一次请求都会在
/// `nextAllowedAt(_:)` 上留下痕迹。于是可以**正面**断言：
///
/// - `.core` **被写过** ⇒ 这条路由确实声明了主桶；
/// - `.search` / `.codeSearch` **从没被写过** ⇒ 它没有误用搜索桶。
///
/// 比"断言它没被限速"强：后者对 `.core` 与"压根没声明"这两种情况给出同一个结果。
@Suite("切片 6/7/8 数据层 · 配额桶守卫")
struct RepoEndpointQuotaTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// 每个桶都有间隔 —— 否则 `.core`（间隔 0）不会在 `nextAllowedAt` 上留痕。
    private static let probePolicies: [RateLimiter.Bucket: RateLimiter.Policy] = [
        .core: RateLimiter.Policy(minimumInterval: 10),
        .search: RateLimiter.Policy(minimumInterval: 10),
        .codeSearch: RateLimiter.Policy(minimumInterval: 10),
        .graphql: RateLimiter.Policy(minimumInterval: 10),
    ]

    /// 跑一条路由，断言它落在主桶。
    private func assertCoreBucket(
        _ route: String,
        stub response: StubURLProtocol.Response,
        body: @Sendable (GitHubRESTClient) async throws -> Void
    ) async {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(response)

        let clock = now
        let limiter = RateLimiter(
            policies: Self.probePolicies,
            clock: { clock },
            // 不真的等 —— 我们只关心"哪个桶被记账了"
            sleeper: { _ in }
        )
        let client = GitHubRESTClient(
            credentials: credentials,
            transport: HTTPTransport(
                credentials: credentials,
                session: harness.makeSession(),
                cache: HTTPResponseCache(configuration: .memoryOnly()),
                rateLimiter: limiter,
                retryPolicy: .none,
                clock: { clock },
                sleeper: { _ in }
            )
        )

        do {
            try await body(client)
        } catch {
            Issue.record("\(route)：请求本身失败了（\(error)）—— 这一条要先修好再看配额")
            return
        }

        #expect(await limiter.nextAllowedAt(.core) != nil, "\(route)：没有落在主桶")
        #expect(await limiter.nextAllowedAt(.search) == nil, "\(route)：误用了 Search 桶")
        #expect(await limiter.nextAllowedAt(.codeSearch) == nil, "\(route)：误用了代码搜索桶")
        #expect(await limiter.nextAllowedAt(.graphql) == nil, "\(route)：误用了 GraphQL 桶")
    }

    private static let emptyPage = StubURLProtocol.Response.json("[]")
    private static let noContent = StubURLProtocol.Response.empty(status: 204)

    /// 跑一条路由，断言它落在**搜索桶**（切片 9.2 起需要：那里终于有一条**该**走搜索桶的路由）。
    ///
    /// 与 `assertCoreBucket` 是同一套探针，只是换了个断言方向 —— 两处都要有，
    /// 因为 `.core` 与 `.search` 的"漏声明"会往两个相反的方向错：
    /// 该主桶的落到搜索桶 ⇒ 30/分钟那个桶会被打爆；
    /// 该搜索桶的落到主桶 ⇒ 主桶被当不限速用（§4.5），而两者都**不会报错**。
    private func assertSearchBucket(
        _ route: String,
        stub response: StubURLProtocol.Response,
        body: @Sendable (GitHubRESTClient) async throws -> Void
    ) async {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(response)

        let clock = now
        let limiter = RateLimiter(
            policies: Self.probePolicies,
            clock: { clock },
            sleeper: { _ in }
        )
        let client = GitHubRESTClient(
            credentials: credentials,
            transport: HTTPTransport(
                credentials: credentials,
                session: harness.makeSession(),
                cache: HTTPResponseCache(configuration: .memoryOnly()),
                rateLimiter: limiter,
                retryPolicy: .none,
                clock: { clock },
                sleeper: { _ in }
            )
        )

        do {
            try await body(client)
        } catch {
            Issue.record("\(route)：请求本身失败了（\(error)）—— 这一条要先修好再看配额")
            return
        }

        #expect(await limiter.nextAllowedAt(.search) != nil, "\(route)：没有落在搜索桶")
        #expect(await limiter.nextAllowedAt(.core) == nil, "\(route)：误用了主桶（它只有 30 次/分钟）")
        #expect(await limiter.nextAllowedAt(.codeSearch) == nil, "\(route)：误用了代码搜索桶")
        #expect(await limiter.nextAllowedAt(.graphql) == nil, "\(route)：误用了 GraphQL 桶")
    }

    private static let fileJSON = StubURLProtocol.Response.json(
        #"{"name":"f","path":"f","sha":"s","size":1,"type":"file","encoding":"base64","content":"aA=="}"#
    )
    private static let branchListJSON = StubURLProtocol.Response.json(
        #"[{"name":"main","commit":{"sha":"s"},"protected":false}]"#
    )
    /// ⚠️ 单分支端点回的是**对象**，不是数组 —— 拿列表那一份会解不出来。
    private static let singleBranchJSON = StubURLProtocol.Response.json(
        #"{"name":"main","commit":{"sha":"s"},"protected":false}"#
    )
    /// `PUT /contents` 的响应 —— 两个 `sha` 有意写成不同的值（见 `FileWriteResultDTO`）。
    private static let fileWriteResultJSON = StubURLProtocol.Response.json(
        #"{"content":{"name":"f","path":"f","sha":"blob","size":2,"type":"file"},"commit":{"sha":"commit","message":"m"}}"#,
        status: 201
    )
    private static let compareJSON = StubURLProtocol.Response.json(
        #"{"status":"ahead","ahead_by":1,"behind_by":0,"total_commits":1}"#
    )
    private static let refJSON = StubURLProtocol.Response.json(
        #"{"ref":"refs/heads/x","object":{"sha":"s"}}"#,
        status: 201
    )
    private static let mergeJSON = StubURLProtocol.Response.json(
        #"{"sha":"s","merged":true}"#,
        status: 201
    )
    private static let repoJSON = StubURLProtocol.Response.json(
        #"{"full_name":"o/r","default_branch":"main","stargazers_count":1,"forks_count":0,"subscribers_count":0,"owner":{"avatar_url":"https://avatars.githubusercontent.com/u/1?v=4"}}"#
    )
    private static let commitDetailJSON = StubURLProtocol.Response.json(
        #"{"sha":"s","commit":{"message":"m","author":{"date":"2026-10-05T08:00:00Z"}}}"#
    )
    private static let listItemJSON = StubURLProtocol.Response.json(
        #"[{"sha":"s","commit":{"message":"m","author":{"date":"2026-10-05T08:00:00Z"}},"author":null}]"#
    )

    // MARK: - 仓库头部

    @Test("`GET /repos/{o}/{r}` —— 主桶")
    func repositoryIsCore() async {
        await assertCoreBucket("repos/{o}/{r}", stub: Self.repoJSON) { client in
            _ = try await GitHubRepoDetailEndpoint(client: client).repository(owner: "o", repo: "r")
        }
    }

    // MARK: - 代码浏览（5 条）

    @Test("代码浏览 7 条路由 —— 全部主桶（**一条都不能落到搜索桶**；含切片 8 的两条写）")
    func contentRoutesAreCore() async {
        await assertCoreBucket("contents（目录）", stub: Self.emptyPage) { client in
            _ = try await GitHubRepoContentEndpoint(client: client).contents(owner: "o", repo: "r")
        }
        await assertCoreBucket("contents（文件）", stub: Self.fileJSON) { client in
            _ = try await GitHubRepoContentEndpoint(client: client)
                .contents(owner: "o", repo: "r", path: "f")
        }
        await assertCoreBucket("contents raw", stub: .empty(status: 200)) { client in
            _ = try await GitHubRepoContentEndpoint(client: client)
                .rawFile(owner: "o", repo: "r", path: "f")
        }
        await assertCoreBucket("readme", stub: .empty(status: 200)) { client in
            _ = try await GitHubRepoContentEndpoint(client: client).readme(owner: "o", repo: "r")
        }
        await assertCoreBucket("readme（404 ⇒ nil）", stub: .json("{}", status: 404)) { client in
            _ = try await GitHubRepoContentEndpoint(client: client).readme(owner: "o", repo: "r")
        }
        // ⚠️ 写操作**同样占主桶**（`PUT` / `DELETE /contents` 不是搜索端点）。
        //    这里最容易发生的错是"新写的端点忘了声明" —— 而它的表现是"静默多用主桶"，
        //    不会报错，只会在某天配额打爆时才发现。
        await assertCoreBucket("contents（PUT 写）", stub: Self.fileWriteResultJSON) { client in
            _ = try await GitHubRepoContentEndpoint(client: client).putFile(
                owner: "o", repo: "r", path: "f", message: "m",
                content: Data("hi".utf8), sha: nil, branch: "main"
            )
        }
        await assertCoreBucket("contents（DELETE 删）", stub: Self.noContent) { client in
            try await GitHubRepoContentEndpoint(client: client).deleteFile(
                owner: "o", repo: "r", path: "f", message: "m", sha: "s", branch: "main"
            )
        }
    }

    // MARK: - 提交（2 条）

    @Test("提交 2 条路由 —— 全部主桶")
    func commitRoutesAreCore() async {
        await assertCoreBucket("commits（列表）", stub: Self.listItemJSON) { client in
            _ = try await GitHubRepoCommitEndpoint(client: client).commits(owner: "o", repo: "r")
        }
        await assertCoreBucket("commits/{sha}（详情）", stub: Self.commitDetailJSON) { client in
            _ = try await GitHubRepoCommitEndpoint(client: client).commit(owner: "o", repo: "r", sha: "s")
        }
    }

    // MARK: - 分支（6 条）

    @Test("分支 6 条路由 —— 全部主桶（含三条写操作）")
    func branchRoutesAreCore() async {
        await assertCoreBucket("branches（列表）", stub: Self.branchListJSON) { client in
            _ = try await GitHubRepoBranchEndpoint(client: client).branches(owner: "o", repo: "r")
        }
        await assertCoreBucket("branches/{branch}", stub: Self.singleBranchJSON) { client in
            _ = try await GitHubRepoBranchEndpoint(client: client).branch(owner: "o", repo: "r", name: "main")
        }
        await assertCoreBucket("compare", stub: Self.compareJSON) { client in
            _ = try await GitHubRepoBranchEndpoint(client: client)
                .compare(owner: "o", repo: "r", base: "a", head: "b")
        }
        await assertCoreBucket("git/refs（建）", stub: Self.refJSON) { client in
            _ = try await GitHubRepoBranchEndpoint(client: client)
                .createBranch(owner: "o", repo: "r", name: "x", sha: "s")
        }
        await assertCoreBucket("git/refs（删）", stub: Self.noContent) { client in
            try await GitHubRepoBranchEndpoint(client: client).deleteBranch(owner: "o", repo: "r", name: "x")
        }
        await assertCoreBucket("merges", stub: Self.mergeJSON) { client in
            _ = try await GitHubRepoBranchEndpoint(client: client)
                .merge(owner: "o", repo: "r", base: "main", head: "topic")
        }
    }

    // MARK: - 切片 7：Issues / PR 共 14 条路由（+ 切片 8 追加的 1 条建 PR）
    //
    // ⚠️ 这 15 条**全在主桶**（`.core`）—— 与 §4.14 / §4.15 的探索两页同一个桶（§9.8.1）。
    //    一条都不能落到搜索桶：Search 桶只有 30/分钟，而这些路由是**点进一页就会连发几条**
    //    （详情 = 正文 + 评论两条），落错桶的表现是"翻两个 PR 就 403"，而单看代码看不出来。

    private static let issueDetailJSON = StubURLProtocol.Response.json(
        #"{"number":42,"title":"t","state":"open","created_at":"2026-10-06T08:00:00Z"}"#
    )
    private static let createdJSON = StubURLProtocol.Response.json(
        #"{"id":903,"body":"b","created_at":"2026-10-08T09:00:00Z"}"#,
        status: 201
    )
    private static let labelJSON = StubURLProtocol.Response.json(
        #"{"name":"bug","color":"d73a4a","description":null}"#,
        status: 201
    )
    private static let pullDetailJSON = StubURLProtocol.Response.json(
        """
        {"number":57,"title":"t","state":"open","merged_at":null,
         "head":{"ref":"a"},"base":{"ref":"main"},
         "additions":1,"deletions":1,"changed_files":1}
        """
    )
    private static let pullMergeJSON = StubURLProtocol.Response.json(
        #"{"sha":"s","merged":true,"message":"ok"}"#
    )

    @Test("Issue 5 条路由 —— 全部主桶（列表 / 详情 / 评论读 / 评论写 / 新建）")
    func issueRoutesAreCore() async {
        await assertCoreBucket("issues（列表）", stub: Self.emptyPage) { client in
            _ = try await GitHubRepoIssuesEndpoint(client: client)
                .issues(owner: "o", repo: "r", state: "open", labels: ["bug"])
        }
        await assertCoreBucket("issues/{n}（详情）", stub: Self.issueDetailJSON) { client in
            _ = try await GitHubRepoIssuesEndpoint(client: client).issue(owner: "o", repo: "r", number: 42)
        }
        await assertCoreBucket("issues/{n}/comments（读）", stub: Self.emptyPage) { client in
            _ = try await GitHubRepoIssuesEndpoint(client: client)
                .issueComments(owner: "o", repo: "r", number: 42)
        }
        await assertCoreBucket("issues/{n}/comments（写）", stub: Self.createdJSON) { client in
            _ = try await GitHubRepoIssuesEndpoint(client: client)
                .createIssueComment(owner: "o", repo: "r", number: 42, body: "b")
        }
        await assertCoreBucket("issues（新建）", stub: Self.issueDetailJSON) { client in
            _ = try await GitHubRepoIssuesEndpoint(client: client)
                .createIssue(owner: "o", repo: "r", title: "t")
        }
    }

    @Test("标签 2 条路由 —— 全部主桶（列出 / 新建）")
    func labelRoutesAreCore() async {
        await assertCoreBucket("labels（列表）", stub: Self.emptyPage) { client in
            _ = try await GitHubRepoLabelsEndpoint(client: client).labels(owner: "o", repo: "r")
        }
        await assertCoreBucket("labels（新建）", stub: Self.labelJSON) { client in
            _ = try await GitHubRepoLabelsEndpoint(client: client)
                .createLabel(owner: "o", repo: "r", name: "bug", color: "d73a4a")
        }
    }

    @Test("PR 8 条路由 —— 全部主桶（列表 / 详情 / 文件 / Commits / 评审 / 合并 / 改状态 / **切片 8 的建 PR**）")
    func pullRoutesAreCore() async {
        await assertCoreBucket("pulls（列表）", stub: Self.emptyPage) { client in
            _ = try await GitHubRepoPullsEndpoint(client: client)
                .pullRequests(owner: "o", repo: "r", state: "all")
        }
        await assertCoreBucket("pulls/{n}（详情）", stub: Self.pullDetailJSON) { client in
            _ = try await GitHubRepoPullsEndpoint(client: client)
                .pullRequest(owner: "o", repo: "r", number: 57)
        }
        await assertCoreBucket("pulls/{n}/files", stub: Self.emptyPage) { client in
            _ = try await GitHubRepoPullsEndpoint(client: client)
                .pullFiles(owner: "o", repo: "r", number: 57)
        }
        await assertCoreBucket("pulls/{n}/commits", stub: Self.emptyPage) { client in
            _ = try await GitHubRepoPullsEndpoint(client: client)
                .pullCommits(owner: "o", repo: "r", number: 57)
        }
        await assertCoreBucket("pulls/{n}/reviews", stub: Self.emptyPage) { client in
            _ = try await GitHubRepoPullsEndpoint(client: client)
                .pullReviews(owner: "o", repo: "r", number: 57)
        }
        await assertCoreBucket("pulls/{n}/merge", stub: Self.pullMergeJSON) { client in
            _ = try await GitHubRepoPullsEndpoint(client: client)
                .mergePull(owner: "o", repo: "r", number: 57, method: .squash)
        }
        await assertCoreBucket("pulls/{n}（改状态）", stub: Self.pullDetailJSON) { client in
            _ = try await GitHubRepoPullsEndpoint(client: client)
                .updatePullState(owner: "o", repo: "r", number: 57, state: "closed")
        }
        await assertCoreBucket("pulls（建）", stub: Self.pullDetailJSON) { client in
            _ = try await GitHubRepoPullsEndpoint(client: client)
                .createPull(owner: "o", repo: "r", title: "t", head: "topic", base: "main")
        }
    }

    // MARK: - 默认会话不挂 URLCache（决策 #32）

    @Test("九个端点的**默认**会话都不挂 URLCache（决策 #32：令牌会跟着序列化请求对象落盘）")
    func defaultSessionsDoNotUseURLCache() {
        let plain = GitHubRESTClient(credentials: credentials)

        #expect(GitHubRepoDetailEndpoint(client: plain).session.configuration.urlCache == nil)
        #expect(GitHubRepoContentEndpoint(client: plain).session.configuration.urlCache == nil)
        #expect(GitHubRepoCommitEndpoint(client: plain).session.configuration.urlCache == nil)
        #expect(GitHubRepoBranchEndpoint(client: plain).session.configuration.urlCache == nil)
        // 切片 7 三个（含两个新的写入口）
        #expect(GitHubRepoIssuesEndpoint(client: plain).session.configuration.urlCache == nil)
        #expect(GitHubRepoPullsEndpoint(client: plain).session.configuration.urlCache == nil)
        #expect(GitHubRepoLabelsEndpoint(client: plain).session.configuration.urlCache == nil)
        // 切片 9 两个（资料读 + 我的会话列表）
        #expect(GitHubViewerProfileEndpoint(client: plain).session.configuration.urlCache == nil)
        #expect(GitHubSearchIssuesEndpoint(client: plain).session.configuration.urlCache == nil)
    }

    // MARK: - 切片 9（我的页 / 我的会话）

    @Test("`GET /user`（我的页资料）—— 主桶")
    func viewerProfileIsCore() async {
        await assertCoreBucket("user（资料）", stub: Self.viewerProfileJSON) { client in
            _ = try await GitHubViewerProfileEndpoint(client: client).loadProfile()
        }
    }

    @Test("⚠️ 我的会话列表 —— **搜索桶**（与搜索页共用；单条 part ⇒ 每翻一页 1 格）")
    func myConversationsUsesSearchBucket() async {
        // ⚠️ 这一条与上面整片"全部主桶"相反，是本项目**第二条**该走搜索桶的路由
        //   （第一条是搜索页自己）。它落到主桶时**不会报错** —— 表现是搜索桶的
        //   30 次/分钟从没被算过，而这一页其实在悄悄地用别人（搜索页）的额度。
        await assertSearchBucket("search/issues（我的会话）", stub: Self.searchIssuesJSON) { client in
            _ = try await GitHubSearchIssuesEndpoint(client: client).search(
                query: "author:@me is:pull-request",
                sort: "updated",
                order: "desc"
            )
        }
    }

    private static let viewerProfileJSON = StubURLProtocol.Response.json(
        #"{"login":"octocat","name":null,"bio":null,"followers":1}"#
    )

    private static let searchIssuesJSON = StubURLProtocol.Response.json(
        #"{"total_count":0,"incomplete_results":false,"items":[]}"#
    )
}
