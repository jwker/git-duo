import Foundation
import Testing

@testable import GitHubAPI

/// 仓库详情页（自己的仓库）的头部 —— `GET /repos/{owner}/{repo}`，PRD §4.4。
///
/// 本套件只钉两件与切片 6 直接相关的事：
/// ① 头部必须带出 **`default_branch`** —— 它是分支解析的起点（§9.4.1），缺了就只能猜 `main`；
/// ② **Watch 数读 `subscribers_count`**，不是 `watchers_count`（后者是 Star 数的别名，
///    读错不会报错，只会让 `Watch · 2,341` 与旁边的 `Star · 2,341` 长成同一个数）。
///
/// 其余字段的完整口径由 `GitHubRepoInsightsEndpointTests` 覆盖（同一个 DTO）。
@Suite("GitHubRepoDetailEndpoint · 仓库头部")
struct GitHubRepoDetailEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEndpoint(harness: StubURLProtocol.Harness) -> GitHubRepoDetailEndpoint {
        let clock = now
        return GitHubRepoDetailEndpoint(
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

    @Test("请求形状：路径正确，不带任何查询串（默认分支由服务端自己挑）")
    func requestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"full_name":"o/r","default_branch":"trunk","stargazers_count":1,"forks_count":2,"subscribers_count":3,"owner":{"avatar_url":"https://avatars.githubusercontent.com/u/1?v=4"}}"#))

        _ = try await makeEndpoint(harness: harness).repository(owner: "cli", repo: "cli")

        let url = try #require(harness.lastRequest?.url)
        #expect(url.path == "/repos/cli/cli")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == nil)
    }

    @Test("解码：default_branch 是分支解析的起点；可写性来自 permissions")
    func decodesDefaultBranchAndPermissions() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                """
                {"full_name":"o/r","description":"一个仓库","default_branch":"main",
                 "stargazers_count":1240,"forks_count":88,"subscribers_count":37,
                 "permissions":{"admin":false,"push":true,"pull":true},
                 "owner":{"avatar_url":"https://avatars.githubusercontent.com/u/1?v=4"}}
                """
            )
        )

        let detail = try await makeEndpoint(harness: harness).repository(owner: "o", repo: "r")

        #expect(detail.fullName == "o/r")
        #expect(detail.defaultBranch == "main")
        // ⚠️ subscribers_count 才是 Watch 数
        #expect(detail.watcherCount == 37)
        #expect(detail.starCount == 1240)
        #expect(detail.permissions?.push == true)
    }

    @Test("⚠️ permissions 缺席 ⇒ nil（由领域层解释成**不可写**）—— 本层不补默认值")
    func permissionsAbsentStaysNil() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(#"{"full_name":"o/r","default_branch":"main","stargazers_count":0,"forks_count":0,"subscribers_count":0,"owner":{"avatar_url":"https://avatars.githubusercontent.com/u/1?v=4"}}"#)
        )

        let detail = try await makeEndpoint(harness: harness).repository(owner: "o", repo: "r")

        // 补一个"默认可写"会让用户点进编辑器、改完文件、提交时才吃 403
        #expect(detail.permissions == nil)
    }
}
