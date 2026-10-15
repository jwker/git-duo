import Foundation
import Testing

@testable import GitHubAPI

/// 首页置顶（GraphQL）—— TECH_SPEC §9.1、§4.6.1、§4.6.5、§13.2。
///
/// 本套件盯着三件事：
/// 1. **查询形状**：`first` 走变量、`types` 写死、`... on Repository` 不能少；
/// 2. **GraphQL 的命名坑**：`stargazerCount`（单数）≠ REST 的 `stargazers_count`（复数）；
/// 3. **`nodes` 的元素可空**：一个失效置顶只能丢自己，不能把整块首页打崩。
@Suite("GitHubPinnedItemsEndpoint · 置顶仓库（GraphQL）")
struct GitHubPinnedItemsEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEndpoint(harness: StubURLProtocol.Harness) -> GitHubPinnedItemsEndpoint {
        let clock = now
        return GitHubPinnedItemsEndpoint(
            client: GitHubGraphQLClient(
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

    /// 一个字段齐全的置顶节点（形状按 GitHub 的真实响应写，含 GraphQL 的单数 `stargazerCount`）。
    private let fullNode = """
    {"nameWithOwner":"my-git/gitduo","description":"GitHub 客户端 · SwiftUI",
     "isPrivate":true,"stargazerCount":128,"forkCount":12,
     "primaryLanguage":{"name":"Swift"},
     "owner":{"avatarUrl":"https://avatars.githubusercontent.com/u/1?v=4"}}
    """

    /// 把 nodes 的正文套进完整的 GraphQL 响应信封（省得每个用例手拼一遍大括号）。
    private func envelope(nodes: String) -> String {
        #"{"data":{"viewer":{"pinnedItems":{"nodes":["# + nodes + #"]}}}}"#
    }

    // MARK: - 查询形状

    @Test("请求形状：POST /graphql，first 走变量（=6），types 与内联片段写死在查询里")
    func buildsQueryShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(nodes: "")))

        _ = try await makeEndpoint(harness: harness).pinnedRepositories()

        let request = try #require(harness.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.github.com/graphql")
        // 版本头仍由 transport 统一注入（§4.2）—— GraphQL 也不能少
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")

        let body = try #require(harness.lastBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        // 上限走变量：数字一旦进查询文本就再也 grep 不到了，而它是配额预算的一部分（§13.2）
        #expect((json["variables"] as? [String: Any])?["first"] as? Int == 6)
        #expect(
            GitHubPinnedItemsEndpoint.maximumCount == 6,
            "6 就是 GitHub 个人主页置顶栏本身的容量（§9.1）"
        )

        let query = try #require(json["query"] as? String)
        #expect(
            query.contains("types: [REPOSITORY]"),
            "取值集合由 schema 固定（PinnableItem = Repository | Gist），写成变量只会多一个传错的入口"
        )
        #expect(
            query.contains("... on Repository"),
            "nodes 的元素类型是 union，不写内联片段取不到任何仓库字段"
        )
        #expect(query.contains("stargazerCount"), "GraphQL 的星数字段是单数")
        #expect(!query.contains("stargazers_count"), "别把 REST 的复数字段名混进 GraphQL 查询")
    }

    // MARK: - 解码

    @Test("解码：名称 / 描述 / 私有 / Star / Fork / 主语言逐个对得上")
    func decodesFullNode() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(nodes: fullNode)))

        let pinned = try await makeEndpoint(harness: harness).pinnedRepositories()

        #expect(pinned.count == 1)
        let first = try #require(pinned.first)
        #expect(first.nameWithOwner == "my-git/gitduo")
        #expect(first.description == "GitHub 客户端 · SwiftUI")
        #expect(first.isPrivate)
        #expect(first.starCount == 128)
        #expect(first.forkCount == 12)
        #expect(first.primaryLanguage?.name == "Swift")
        #expect(first.owner.avatarUrl.absoluteString == "https://avatars.githubusercontent.com/u/1?v=4")
    }

    @Test("主语言与描述为 null：留 nil 而不是解码失败（空仓库 / 没填简介都很常见）")
    func decodesNullPrimaryLanguage() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                envelope(
                    nodes: #"{"nameWithOwner":"a/b","description":null,"isPrivate":false,"stargazerCount":0,"forkCount":0,"primaryLanguage":null,"owner":{"avatarUrl":"https://avatars.githubusercontent.com/u/2?v=4"}}"#
                )
            )
        )

        let pinned = try await makeEndpoint(harness: harness).pinnedRepositories()

        #expect(pinned.first?.primaryLanguage == nil)
        #expect(pinned.first?.description == nil)
    }

    @Test("星数字段写错成 REST 的复数字段名 ⇒ 解码失败，而不是默默显示 0 个 Star")
    func wrongStarFieldNameFails() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                envelope(
                    // ⚠️ `owner` 带齐了 —— 本条只验证"星数字段名写错"这一种失败，
                    //    别让"缺 owner"也凑巧引起解码失败而把它放过去。
                    nodes: #"{"nameWithOwner":"a/b","isPrivate":false,"stargazers_count":5,"forkCount":1,"owner":{"avatarUrl":"https://avatars.githubusercontent.com/u/3?v=4"}}"#
                )
            )
        )

        // 为什么这是"要的"行为：单数 / 复数只差一个字母，而写错时服务端**不会**报错
        // （它只是没返回那个字段）。默默显示 0 会让用户以为项目没人 star；
        // "这一页拿不到"至少是诚实的。
        do {
            _ = try await makeEndpoint(harness: harness).pinnedRepositories()
            Issue.record("字段名写错就该解码失败")
        } catch let error as GitHubError {
            guard case .decoding = error else {
                Issue.record("应归为 .decoding，实际：\(error)")
                return
            }
        }
    }

    // MARK: - 可空元素（本套件存在的核心理由之一）

    @Test("nodes 里混着 null：只丢那一个，其余照常返回")
    func skipsNullNodes() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(nodes: "null," + fullNode)))

        let pinned = try await makeEndpoint(harness: harness).pinnedRepositories()

        // 失效的置顶（仓库被删 / 安装范围没勾到它）在 schema 里就是可空元素。
        // 声明成 [PinnedRepositoryDTO] 会让**一个**坏掉的置顶把整块首页变成空态。
        #expect(pinned.count == 1)
        #expect(pinned.first?.nameWithOwner == "my-git/gitduo")
    }

    @Test("全部节点都是 null ⇒ 空数组（与「没有置顶」等价，不是错误）")
    func allNullNodesYieldEmpty() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(nodes: "null,null")))

        let pinned = try await makeEndpoint(harness: harness).pinnedRepositories()

        #expect(pinned.isEmpty)
    }

    @Test("没有置顶（nodes 为空）⇒ 空数组且不抛错 —— 视图据此显示空态")
    func emptyPinsAreNotAnError() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(envelope(nodes: "")))

        let pinned = try await makeEndpoint(harness: harness).pinnedRepositories()

        #expect(pinned.isEmpty)
    }

    // MARK: - 200 也可能是失败

    @Test("HTTP 200 + body.errors ⇒ 抛 graphQLErrors（置顶也不例外）")
    func errorsOnHTTP200Throw() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"{"data":null,"errors":[{"message":"Bad credentials","path":["viewer","pinnedItems"]}]}"#
            )
        )

        do {
            _ = try await makeEndpoint(harness: harness).pinnedRepositories()
            Issue.record("body 里有 errors 就不算成功")
        } catch let error as GitHubError {
            guard case let .graphQLErrors(messages, partialData) = error else {
                Issue.record("应归为 .graphQLErrors，实际：\(error)")
                return
            }
            #expect(messages == ["viewer.pinnedItems: Bad credentials"])
            #expect(partialData == nil)
        }
    }
}
