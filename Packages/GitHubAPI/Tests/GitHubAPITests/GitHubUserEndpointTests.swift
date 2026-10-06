import Foundation
import Testing

@testable import GitHubAPI

/// `GitHubUserEndpoint` 的规格 —— TECH_SPEC §3.1 步骤 8：换到令牌后立刻 `GET /user` 校验有效性。
///
/// 桩件用**本套件自持的 harness**（`StubURLProtocol.makeHarness()`）⇒ 与其它网络套件并行也不互相覆盖。
@Suite("GitHubUserEndpoint · GET /user")
struct GitHubUserEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let token = "ghu_TESTTOKEN"

    private func makeEndpoint(with harness: StubURLProtocol.Harness) -> GitHubUserEndpoint {
        GitHubUserEndpoint(credentials: credentials, session: harness.makeSession())
    }

    // MARK: - 请求形状（不需要网络）

    @Test("GET /user + 三个头；令牌只在 Authorization 里，绝不进 URL")
    func requestShape() throws {
        let request = makeEndpoint(with: StubURLProtocol.makeHarness()).makeRequest(accessToken: token)

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.github.com/user")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == credentials.apiVersion)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
        // 令牌进 URL 会泄进日志、Referer、以及缓存键 —— 一律只走请求头
        #expect(request.url?.absoluteString.contains(token) == false)
    }

    @Test("默认会话不挂 URLCache ⇒ 这个请求的 Authorization 头默认无从落盘")
    func defaultSessionDoesNotPersist() {
        let endpoint = GitHubUserEndpoint(credentials: credentials)

        #expect(endpoint.session.configuration.urlCache == nil)
    }

    // MARK: - 成功路径

    @Test("2xx + 能解出 login ⇒ 返回用户（多余字段忽略）")
    func decodesLogin() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"login":"octocat","id":1,"avatar_url":"https://example.com/a.png"}"#))

        let user = try await makeEndpoint(with: harness).fetchAuthenticatedUser(accessToken: token)

        #expect(user.login == "octocat")
        #expect(harness.requestCount == 1)
    }

    // MARK: - 失败路径（区分"令牌失效"与"服务端故障"——上层据此决定是否登出）

    @Test("401 ⇒ .httpStatus(401)：令牌已失效，上层据此登出")
    func unauthorized() async {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 401))

        do {
            _ = try await makeEndpoint(with: harness).fetchAuthenticatedUser(accessToken: token)
            Issue.record("401 应当抛错")
        } catch {
            #expect((error as? OAuthError) == .httpStatus(401))
        }
    }

    @Test("500 ⇒ .httpStatus(500)：⚠️ 服务端故障 ≠ 令牌失效，上层**不得**据此登出（§3.2）")
    func serverError() async {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 500))

        do {
            _ = try await makeEndpoint(with: harness).fetchAuthenticatedUser(accessToken: token)
            Issue.record("500 应当抛错")
        } catch {
            #expect((error as? OAuthError) == .httpStatus(500))
            #expect((error as? OAuthError) != .httpStatus(401))
        }
    }

    @Test("body 解不出 login ⇒ .invalidResponse（200 也可能是坏数据）")
    func undecodableBody() async {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("<html>not json</html>"))

        do {
            _ = try await makeEndpoint(with: harness).fetchAuthenticatedUser(accessToken: token)
            Issue.record("坏 body 应当抛错")
        } catch {
            #expect((error as? OAuthError) == .invalidResponse)
        }
    }
}
