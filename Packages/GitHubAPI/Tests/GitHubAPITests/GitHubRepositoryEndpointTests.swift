import Foundation
import Testing

@testable import GitHubAPI

/// 仓库列表数据层：DTO 形状 + 端点请求形状（TECH_SPEC §4.6.2 / §6.2）。
///
/// 桩件用**本套件自持的 harness**，与其它网络套件并行也不互相覆盖。
@Suite("GitHubRepositoryEndpoint · DTO 解码与请求形状")
struct GitHubRepositoryEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEndpoint(harness: StubURLProtocol.Harness) -> GitHubRepositoryEndpoint {
        let clock = now
        return GitHubRepositoryEndpoint(
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

    /// 一个字段齐全的仓库对象（形状按 GitHub 的真实响应写）。
    private let fullRepoJSON = """
    {
      "full_name": "my-git/gitduo",
      "private": true,
      "description": "GitHub 客户端 · SwiftUI",
      "language": "Swift",
      "stargazers_count": 124000,
      "forks_count": 12600,
      "permissions": {"admin": true, "maintain": true, "push": true, "triage": true, "pull": true},
      "owner": {"avatar_url": "https://avatars.githubusercontent.com/u/1?v=4"}
    }
    """

    // MARK: - DTO 解码

    @Test("DTO：字段齐全时逐个解出（含 permissions 全集）")
    func decodesFullRepo() throws {
        let repo = try JSONDecoder().decode(RepositoryDTO.self, from: Data(fullRepoJSON.utf8))

        #expect(repo.fullName == "my-git/gitduo")
        #expect(repo.isPrivate)
        #expect(repo.description == "GitHub 客户端 · SwiftUI")
        #expect(repo.language == "Swift")
        #expect(repo.starCount == 124_000)
        #expect(repo.forkCount == 12_600)
        #expect(repo.permissions?.push == true)
        #expect(repo.permissions?.admin == true)
        #expect(repo.owner.avatarURL?.absoluteString == "https://avatars.githubusercontent.com/u/1?v=4")
    }

    @Test("DTO：`language` / `description` 为 null 或缺失都不该崩 —— 它们在真实响应里很常见")
    func decodesNullables() throws {
        let json = """
        {"full_name":"my-git/empty","private":false,"description":null,
         "stargazers_count":0,"forks_count":0,
         "owner":{"avatar_url":"https://avatars.githubusercontent.com/u/2?v=4"}}
        """
        let repo = try JSONDecoder().decode(RepositoryDTO.self, from: Data(json.utf8))

        #expect(repo.description == nil)
        #expect(repo.language == nil)
        #expect(repo.permissions == nil, "未认证 / 无权限时 GitHub 不返回 permissions")
    }

    @Test("DTO：`permissions` 只给部分键也必须解得出来（协作者可能没有 admin / maintain）")
    func decodesPartialPermissions() throws {
        let json = """
        {"full_name":"other/repo","private":false,"stargazers_count":1,"forks_count":0,
         "permissions":{"push":true,"pull":true},
         "owner":{"avatar_url":"https://avatars.githubusercontent.com/u/3?v=4"}}
        """
        let repo = try JSONDecoder().decode(RepositoryDTO.self, from: Data(json.utf8))

        #expect(repo.permissions?.push == true)
        #expect(repo.permissions?.admin == nil)
        #expect(repo.permissions?.maintain == nil)
        #expect(repo.permissions?.triage == nil)
    }

    @Test("DTO：缺 `stargazers_count` ⇒ **解码失败**，而不是默默当成 0")
    func missingStarCountFailsLoudly() {
        // ⚠️ `owner` 现在也是必需的（走查第 72 条）—— 这个"缺一个恒存在字段就响亮失败"
        //    的口径对它同样成立，所以这条夹具把 `owner` 带上、只缺 `stargazers_count`。
        let json = #"{"full_name":"a/b","private":false,"forks_count":0,"owner":{"avatar_url":null}}"#

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(RepositoryDTO.self, from: Data(json.utf8))
        }
        // 为什么这样是对的：显示 0 个 Star 是一个**看起来正常的错值**，
        // 用户会以为项目没人关注；解码失败至少会说"这页拿不到"。
    }

    // MARK: - 请求形状

    @Test("listRepos：affiliation 三个值写全 + sort=updated + per_page=30")
    func listReposRequestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        _ = try await makeEndpoint(harness: harness).listRepos()

        let url = try #require(harness.lastRequest?.url)
        #expect(url.absoluteString.hasPrefix("https://api.github.com/user/repos?"))
        let items = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        #expect(
            items.first { $0.name == "affiliation" }?.value
                == "owner,collaborator,organization_member",
            "只拉 owner 会让组织仓库与协作仓库永远不出现在「仓库」Tab"
        )
        #expect(items.first { $0.name == "sort" }?.value == "updated")
        #expect(items.first { $0.name == "per_page" }?.value == "30")
        #expect(harness.lastRequest?.httpMethod == "GET")
    }

    @Test("listStarred：走 `user/starred`（Starred 段是**另一份数据源**，不是本地过滤出来的）")
    func listStarredRequestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        _ = try await makeEndpoint(harness: harness).listStarred()

        let url = try #require(harness.lastRequest?.url)
        #expect(url.absoluteString.hasPrefix("https://api.github.com/user/starred?"))
    }

    @Test("listRepos(cursor:)：直接请求完整游标 URL，不再补查询串")
    func listReposFollowsCursor() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        let cursor = URL(string: "https://api.github.com/user/repos?affiliation=owner&page=2")!
        _ = try await makeEndpoint(harness: harness).listRepos(cursor: cursor)

        #expect(
            harness.lastRequest?.url?.absoluteString == cursor.absoluteString,
            "续页必须用服务端给的 URL —— 自己拼 page=n 会在带其它参数的端点上翻错页"
        )
    }

    @Test("分页：下一页取自 `Link: rel=next`，并原样交给调用方")
    func pageExposesNextCursor() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"["# + fullRepoJSON + #"]"#,
                headers: [
                    "Link": #"<https://api.github.com/user/repos?page=2>; rel="next""#
                ]
            )
        )

        let page = try await makeEndpoint(harness: harness).listRepos()

        #expect(page.items.count == 1)
        #expect(page.items.first?.fullName == "my-git/gitduo")
        #expect(page.nextCursor?.absoluteString == "https://api.github.com/user/repos?page=2")
        #expect(page.hasMore)
    }

    @Test("端点继承 transport 的统一请求头（版本头不能靠端点自己记得带）")
    func inheritsVersionHeader() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("[]"))

        _ = try await makeEndpoint(harness: harness).listRepos()

        #expect(harness.lastRequest?.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
        #expect(harness.lastRequest?.value(forHTTPHeaderField: "Accept")?.contains("application/vnd.github+json") == true)
    }
}
