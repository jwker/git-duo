import Foundation
import Testing

@testable import GitHubAPI

/// `GitHubInstallationsEndpoint` 的规格 —— `GET /user/installations`（TECH_SPEC §3.5.4 / **§3.5.5**、§4.6.4）。
///
/// ## 这个端点回答"Star 写得动吗"
///
/// GitHub App 的用户令牌，**写 Star 只对「App 安装范围内的仓库」有效**
/// （2026-10-09 真机实测：自己的仓库 `PUT` 204、别人的仓库 403
/// `Resource not accessible by integration`，REST 与 GraphQL 两条路同样被拒）。
/// 所以「本 App 装在哪些账号上」这一个集合就是判据的来源，而它由本端点给出。
///
/// ## 这组断言守的是什么
///
/// 不是"能不能解出 JSON"（那太容易对），而是三件**错了都不报错**的事：
/// ① 查询串没丢（`per_page=100`）—— 丢了只会静默少拿到几个安装；
/// ② `login` 缺失的条目**被丢掉**而不是变成空串 —— 空串会在判定那一侧变成
///    "有个没名字的账号装了 GitDuo"，而那会让某个仓库的按钮莫名其妙可点；
/// ③ 它**只取第一页**（有意为之，见类型说明）—— 别哪天顺手加个续页循环。
@Suite("GitHubInstallationsEndpoint · GET /user/installations")
struct GitHubInstallationsEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private func makeEndpoint(with harness: StubURLProtocol.Harness) -> GitHubInstallationsEndpoint {
        GitHubInstallationsEndpoint(
            client: GitHubRESTClient(credentials: credentials, session: harness.makeSession())
        )
    }

    // MARK: - 请求形状

    @Test("GET /user/installations?per_page=100 —— 查询串必须真的发出去")
    func requestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"total_count":0,"installations":[]}"#))

        _ = try await makeEndpoint(with: harness).installedAccounts()

        let request = try #require(harness.lastRequest)
        #expect(request.httpMethod == "GET")
        // ⚠️ 断言完整 URL（不是只看 path）—— 查询串有没有丢只有它能看出来，
        //    而丢了的表现是"安装少列了几个"，在界面上完全看不出来。
        #expect(request.url?.absoluteString == "https://api.github.com/user/installations?per_page=100")
    }

    // MARK: - 成功路径

    @Test("取 `account.login`，多余的字段一概忽略（当下只有 1 个安装——实测就是那样）")
    func decodesLogins() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("""
        {
          "total_count": 1,
          "installations": [
            {
              "id": 12345678,
              "account": { "login": "jwker", "id": 1, "type": "User" },
              "repository_selection": "all",
              "permissions": { "contents": "write" }
            }
          ]
        }
        """))

        let accounts = try await makeEndpoint(with: harness).installedAccounts()

        #expect(accounts == ["jwker"])
    }

    @Test("多个安装（自己 + 组织）全部取回，顺序照服务端")
    func decodesMultipleAccounts() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("""
        {"total_count":2,"installations":[
          {"account":{"login":"jwker"},"repository_selection":"all"},
          {"account":{"login":"my-git"},"repository_selection":"selected"}
        ]}
        """))

        #expect(try await makeEndpoint(with: harness).installedAccounts() == ["jwker", "my-git"])
    }

    @Test("⚠️ `login` 缺失的条目**被丢掉**，绝不补一个空串")
    func dropsEntriesWithoutLogin() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("""
        {"total_count":3,"installations":[
          {"account":{"login":"jwker"}},
          {"account":{}},
          {"account":{"login":"my-git"}}
        ]}
        """))

        // ⚠️ 一个空串会在 `StarWriteScope` 那一侧变成"名字为空的账号装了 GitDuo"——
        //    不会报错，只会让某个仓库的按钮莫名其妙可点。
        #expect(try await makeEndpoint(with: harness).installedAccounts() == ["jwker", "my-git"])
    }

    @Test("一个安装都没有（用户没装过）⇒ 空数组，不是错误")
    func zeroInstallations() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"total_count":0,"installations":[]}"#))

        #expect(try await makeEndpoint(with: harness).installedAccounts().isEmpty)
    }

    // MARK: - 失败路径（调用方据此折叠成 `.unknown`）

    @Test("非 2xx ⇒ 抛 `GitHubError`（由 `LoadStarWriteScope` 折叠成 `.unknown`）")
    func failurePropagates() async {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 500))

        do {
            _ = try await makeEndpoint(with: harness).installedAccounts()
            Issue.record("500 应当抛错")
        } catch {
            #expect((error as? GitHubError) == .serverError(status: 500))
        }
    }

    @Test("body 形状不对（`installations` 缺失）⇒ 抛解码错误，**不是**「零个安装」")
    func undecodableBodyIsNotAnEmptyList() async {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"total_count":0}"#))

        do {
            _ = try await makeEndpoint(with: harness).installedAccounts()
            Issue.record("缺 `installations` 应当抛错")
        } catch {
            // ⚠️ 折成空数组就等于说"你没装过 GitDuo"——
            //    那会让**所有**仓库的 Star 都变灰，而原因其实是一次坏响应。
            #expect(error is GitHubError)
        }
    }

    @Test("断网 ⇒ `.transport`（与 5xx 是两个东西）")
    func transportFailure() async {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.failing(.notConnectedToInternet))

        do {
            _ = try await makeEndpoint(with: harness).installedAccounts()
            Issue.record("断网应当抛错")
        } catch {
            guard let githubError = error as? GitHubError, case .transport = githubError else {
                Issue.record("应当是 .transport，实际是 \(error)")
                return
            }
        }
    }

    // MARK: - 会话语义

    @Test("只发一次请求、且不续页（用户装过的 App 是个位数，续页换不来任何东西）")
    func singleRequestNoPagination() async throws {
        let harness = StubURLProtocol.makeHarness()
        // 带一个"还有下一页"的 Link 头 —— 本端点**不该**理它。
        harness.stub(.json(
            #"{"total_count":200,"installations":[{"account":{"login":"jwker"}}]}"#,
            headers: ["Link": "<https://api.github.com/user/installations?per_page=100&page=2>; rel=\"next\""]
        ))

        _ = try await makeEndpoint(with: harness).installedAccounts()

        #expect(harness.requestCount == 1)
    }
}
