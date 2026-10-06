import Foundation
import Testing

@testable import GitHubAPI

/// `GitHubGraphQLClient` 的规格 —— TECH_SPEC §4.1 / §4.3 / §4.6.5 / §13.2。
///
/// 本套件的靶心是**三件 GraphQL 特有的骗人之处**：
/// 1. `200 OK` 也可能是失败（错误在 body 的 `errors` 里）；
/// 2. 会**部分成功**（`data` 与 `errors` 并存）—— 抛错但不能把已拿到的数据丢掉；
/// 3. 变量/查询文本不能手拼 JSON（引号与换行）。
@Suite("GitHubGraphQLClient · body.errors 与部分成功")
struct GitHubGraphQLClientTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - DTO

    private struct Viewed: Codable, Sendable, Equatable {
        let login: String
    }

    /// 部分成功时用来解 `viewer.login` 的形状（见 `partialSuccessCarriesData`）。
    private struct ViewerLogin: Codable, Sendable, Equatable {
        struct Viewer: Codable, Sendable, Equatable {
            let login: String
        }
        let viewer: Viewer
    }

    /// 首页置顶仓库的响应形状（§4.6.5 的第四个场景）。
    private struct PinnedResponse: Codable, Sendable, Equatable {
        struct Viewer: Codable, Sendable, Equatable {
            struct PinnedItems: Codable, Sendable, Equatable {
                struct Repo: Codable, Sendable, Equatable { let nameWithOwner: String }
                let nodes: [Repo]
            }
            let pinnedItems: PinnedItems
        }
        let viewer: Viewer
    }

    private struct PinnedVariables: Encodable, Sendable {
        let first: Int
        /// 这个字段名是错的（真实查询用小写 `types`）—— 用来证明"变量名写错"
        /// 是调用方的事，本层只负责原样编码。
        let types: String
    }

    private func makeClient(harness: StubURLProtocol.Harness) -> GitHubGraphQLClient {
        let clock = now
        return GitHubGraphQLClient(
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
    }

    // MARK: - 成功路径

    @Test("成功：`data` 解出目标类型")
    func decodesData() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"data":{"login":"octocat"}}"#))
        let client = makeClient(harness: harness)

        let viewed = try await client.query("query { viewer { login } }", as: Viewed.self)

        #expect(viewed == Viewed(login: "octocat"))
    }

    @Test("请求形状：POST /graphql，体里带 query 与 variables，且声明 graphql 配额桶")
    func buildsRequestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"data":{"viewer":{"pinnedItems":{"nodes":[]}}}}"#))
        let client = makeClient(harness: harness)

        _ = try await client.query(
            "query($first: Int!) { viewer { pinnedItems(first: $first) { nodes { nameWithOwner } } } }",
            variables: PinnedVariables(first: 6, types: "REPOSITORY"),
            as: PinnedResponse.self
        )

        let request = try #require(harness.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.github.com/graphql")
        // 版本头与 User-Agent 仍由 transport 统一注入（§4.2）—— GraphQL 也不能少
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")

        let body = try #require(harness.lastBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect((json["query"] as? String)?.contains("pinnedItems") == true)
        #expect((json["variables"] as? [String: Any])?["first"] as? Int == 6)
        #expect((json["variables"] as? [String: Any])?["types"] as? String == "REPOSITORY")
    }

    @Test("无变量查询：variables 编码为 `{}`（不是省略，也不是 null）")
    func emptyVariablesEncodeAsObject() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"data":{"login":"octocat"}}"#))
        let client = makeClient(harness: harness)

        _ = try await client.query("query { viewer { login } }", as: Viewed.self)

        let body = try #require(harness.lastBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["variables"] is [String: Any], "`variables` 必须是对象；null / 缺失会让服务端另一种报错")
    }

    // MARK: - 错误在 body 里

    @Test("HTTP 200 + errors：必须抛错（绝不能只看状态码就当好结果）")
    func errorsOnHTTP200Throw() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"data":null,"errors":[{"message":"Bad credentials"}]}"#))
        let client = makeClient(harness: harness)

        do {
            _ = try await client.query("query { viewer { login } }", as: Viewed.self)
            Issue.record("body 里有 errors 就不算成功")
        } catch let error as GitHubError {
            guard case let .graphQLErrors(messages, partialData) = error else {
                Issue.record("应归为 .graphQLErrors，实际：\(error)")
                return
            }
            #expect(messages == ["Bad credentials"])
            #expect(partialData == nil, "`data` 为 null ⇒ 没有任何可用数据")
        }
    }

    @Test("多条错误：拼成 `path: message`（path 里带数组下标也要能取出来）")
    func joinsMessagesWithPath() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"{"errors":[{"message":"Field 'x' doesn't exist","path":["viewer","pinnedItems"]},{"message":"boom","path":["viewer","pinnedItems","nodes",0]},{"message":"no path"}]}"#
            )
        )
        let client = makeClient(harness: harness)

        do {
            _ = try await client.query("query { viewer { login } }", as: Viewed.self)
            Issue.record("应当抛错")
        } catch let error as GitHubError {
            guard case let .graphQLErrors(messages, _) = error else {
                Issue.record("应归为 .graphQLErrors，实际：\(error)")
                return
            }
            #expect(messages == [
                "viewer.pinnedItems: Field 'x' doesn't exist",
                // `0` 是数字下标：断言成 [String] 会让这一条整条丢失
                "viewer.pinnedItems.nodes.0: boom",
                "no path"
            ])
        }
    }

    // MARK: - 部分成功（本套件存在的核心理由）

    @Test("部分成功：抛错，但**必须带上已经拿到的 data**（不能把 90% 的内容丢掉）")
    func partialSuccessCarriesData() async throws {
        let harness = StubURLProtocol.makeHarness()
        // viewer.login 拿到了；pinnedItems 那一支出错 ⇒ GitHub 两种都给
        harness.stub(
            .json(
                #"{"data":{"viewer":{"login":"octocat"}},"errors":[{"message":"Field 'pinnedItems' doesn't exist","path":["viewer","pinnedItems"]}]}"#
            )
        )
        let client = makeClient(harness: harness)

        do {
            _ = try await client.query("query { viewer { login pinnedItems { nodes { nameWithOwner } } } }", as: Viewed.self)
            Issue.record("有 errors 就应当抛错")
        } catch let error as GitHubError {
            guard case let .graphQLErrors(messages, partialData) = error else {
                Issue.record("应归为 .graphQLErrors，实际：\(error)")
                return
            }
            #expect(messages == ["viewer.pinnedItems: Field 'pinnedItems' doesn't exist"])

            // 关键断言：调用方仍能从那部分数据里解出它想要的东西
            let recovered = try #require(partialData, "部分成功的响应必须带上 data")
            let payload = try JSONDecoder().decode(ViewerLogin.self, from: recovered)
            #expect(payload.viewer.login == "octocat")
        }
    }

    @Test("部分成功：`data` 里的残缺字段不妨碍取到完整的那部分")
    func partialDataIsRawJSONNotTyped() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(
            .json(
                #"{"data":{"viewer":{"pinnedItems":{"nodes":[{"nameWithOwner":"apple/swift"}],"totalCount":"NOT_A_NUMBER"}}},"errors":[{"message":"partial"}]}"#
            )
        )
        let client = makeClient(harness: harness)

        do {
            // `PinnedResponse` 解不出来（totalCount 不在 DTO 里也无所谓），但这里用的是更复杂的形状：
            // 只要 errors 非空就一定走错误分支，与 T 能否解码无关。
            _ = try await client.query("query { viewer { pinnedItems { nodes { nameWithOwner } } } }", as: PinnedResponse.self)
            Issue.record("有 errors 就应当抛错")
        } catch let error as GitHubError {
            guard case let .graphQLErrors(_, partialData) = error else {
                Issue.record("应归为 .graphQLErrors，实际：\(error)")
                return
            }
            let recovered = try #require(partialData)
            let json = try #require(try JSONSerialization.jsonObject(with: recovered) as? [String: Any])
            #expect(json["viewer"] != nil, "慢路必须在**不知道 T 形状**的前提下把 data 原样留下")
        }
    }

    // MARK: - 形状完全不对

    @Test("既没有 errors 也没有 data：算解码失败（不当成成功，也不编一个 GraphQL 错误）")
    func neitherDataNorErrorsIsDecodingFailure() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"something":"else"}"#))
        let client = makeClient(harness: harness)

        do {
            _ = try await client.query("query { viewer { login } }", as: Viewed.self)
            Issue.record("形状不符应当报错")
        } catch let error as GitHubError {
            guard case .decoding = error else {
                Issue.record("应归为 .decoding，实际：\(error)")
                return
            }
        }
    }

    @Test("响应体不是 JSON：算解码失败（不崩、不空过）")
    func nonJSONBodyIsDecodingFailure() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("<html>we are down</html>"))
        let client = makeClient(harness: harness)

        do {
            _ = try await client.query("query { viewer { login } }", as: Viewed.self)
            Issue.record("非 JSON 应当报错")
        } catch let error as GitHubError {
            guard case .decoding = error else {
                Issue.record("应归为 .decoding，实际：\(error)")
                return
            }
        }
    }

    // MARK: - HTTP 层错误仍由 transport 归一化

    @Test("HTTP 401：仍归为 .unauthorized（GraphQL 不另搞一套 HTTP 错误语义）")
    func httpUnauthorizedStaysUnauthorized() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("", status: 401))
        let client = makeClient(harness: harness)

        await #expect(throws: GitHubError.unauthorized) {
            _ = try await client.query("query { viewer { login } }", as: Viewed.self)
        }
    }
}
