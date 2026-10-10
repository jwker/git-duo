import Foundation
import Testing

@testable import GitHubAPI

/// 单用户公开资料 —— `GET /users/{login}`（C 方案，PRD §5.10）。
///
/// 与 `/search/users`（精简对象、搜索桶）相区别：本端点走默认 core 主桶，
/// 返回完整公开资料，点用户行时才补一次。
@Suite("GitHubPublicUserEndpoint · 点开补全的数据源")
struct GitHubPublicUserEndpointTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEndpoint(harness: StubURLProtocol.Harness) -> GitHubPublicUserEndpoint {
        let clock = now
        return GitHubPublicUserEndpoint(
            client: GitHubRESTClient(
                credentials: credentials,
                transport: HTTPTransport(
                    credentials: credentials,
                    session: harness.makeSession(),
                    cache: HTTPResponseCache(configuration: .memoryOnly()),
                    rateLimiter: RateLimiter(
                        policies: RateLimiter.Policy.defaults,
                        clock: { clock },
                        sleeper: { _ in }
                    ),
                    retryPolicy: .none,
                    clock: { clock },
                    sleeper: { _ in }
                )
            )
        )
    }

    @Test("请求形状：路径是 users/{login}，GET，不带查询项")
    func buildsRequestShape() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"login":"torvalds"}"#))

        _ = try await makeEndpoint(harness: harness).loadUser(login: "torvalds")

        let url = try #require(harness.lastRequest?.url)
        #expect(url.path == "/users/torvalds")
        #expect(harness.lastRequest?.httpMethod == "GET")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == nil)
    }

    @Test("解码：完整资料各字段逐个取到")
    func decodesFullProfile() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("""
        {"login":"torvalds","name":"Linus Torvalds","bio":"creator of Linux",
         "public_repos":12,"followers":327008}
        """))

        let result = try await makeEndpoint(harness: harness).loadUser(login: "torvalds")

        #expect(result.login == "torvalds")
        #expect(result.name == "Linus Torvalds")
        #expect(result.bio == "creator of Linux")
        #expect(result.publicRepos == 12)
        #expect(result.followers == 327008)
    }

    @Test("404 ⇒ 抛 notFound（用户不存在）")
    func notFound() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 404))

        await #expect(throws: GitHubError.self) {
            _ = try await makeEndpoint(harness: harness).loadUser(login: "ghost")
        }
    }
}
