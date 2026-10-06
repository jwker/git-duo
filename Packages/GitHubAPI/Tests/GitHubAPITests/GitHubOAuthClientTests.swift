import Foundation
import Testing

@testable import GitHubAPI

/// `GitHubOAuthClient` 的行为规格。
///
/// 依据：TECH_SPEC §3.1（步骤 3 / 6）、§3.2（刷新）、§3.6（撤销）、决策 #30。
/// `.serialized`：`StubURLProtocol` 的桩响应是进程内共享状态，并行会互相覆盖。
@Suite("GitHubOAuthClient · 授权 / 换令牌 / 刷新 / 撤销", .serialized)
struct GitHubOAuthClientTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private func makeClient() -> GitHubOAuthClient {
        GitHubOAuthClient(credentials: credentials, session: StubURLProtocol.makeSession())
    }

    private func formFields(_ request: URLRequest) throws -> [String: String] {
        let data = try #require(
            StubURLProtocol.bodyData(of: request),
            "请求体读不到（httpBody 与 httpBodyStream 都为空）"
        )
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: String])
    }

    private let successJSON = #"{"access_token":"ghu_abc","expires_in":28800,"refresh_token":"ghr_xyz","refresh_token_expires_in":15897600,"token_type":"bearer","scope":""}"#

    // MARK: - 步骤 3：授权 URL

    @Test("授权 URL 恰好带 5 个参数，且**既不含 client_secret 也不含 code_verifier**")
    func authorizationURLShape() throws {
        let url = try #require(makeClient().authorizationURL(state: "st-1", codeChallenge: "ch-1"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        #expect(url.scheme == "https")
        #expect(url.host == "github.com")
        #expect(url.path == "/login/oauth/authorize")

        #expect(fields["client_id"] == "Iv23liTESTclientid")
        #expect(fields["redirect_uri"] == "gitduo://oauth/callback")
        #expect(fields["state"] == "st-1")
        #expect(fields["code_challenge"] == "ch-1")
        #expect(fields["code_challenge_method"] == "S256")
        #expect(fields.count == 5, "参数个数必须是 5，多一个都说明改了协议形状")

        // 授权 URL 会出现在地址栏 / 浏览器历史里：绝不能带 secret 或 verifier（§3.1 / 铁律 10）
        #expect(fields["client_secret"] == nil)
        #expect(fields["code_verifier"] == nil)

        // 拒绝一切静默授权路径（§3.9 缓解项 4）
        #expect(fields["prompt"] == nil)
    }

    @Test("授权 URL 的 challenge 与 PKCE 的 S256 输出一致（两端形状对齐）")
    func authorizationURLMatchesPKCE() throws {
        let verifier = PKCE.makeCodeVerifier()
        let url = try #require(makeClient().authorizationURL(
            state: PKCE.makeState(),
            codeChallenge: PKCE.codeChallenge(for: verifier)
        ))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(fields["code_challenge"] == PKCE.codeChallenge(for: verifier))
    }

    // MARK: - 步骤 6：换令牌

    @Test("换令牌请求体恰好 5 个字段，且**必须**含 client_secret（决策 #30 的 Required）")
    func exchangeRequestShape() throws {
        let request = try makeClient().makeExchangeRequest(code: "the-code", codeVerifier: "the-verifier")
        let fields = try formFields(request)

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://github.com/login/oauth/access_token")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")

        #expect(fields["client_id"] == "Iv23liTESTclientid")
        #expect(fields["client_secret"] == "s3cr3t-soft")
        #expect(fields["code"] == "the-code")
        #expect(fields["redirect_uri"] == "gitduo://oauth/callback")
        #expect(fields["code_verifier"] == "the-verifier")
        #expect(fields.count == 5)
    }

    @Test("换令牌成功：解析出 access / refresh / 有效期")
    func exchangeSuccess() async throws {
        StubURLProtocol.stub(.json(successJSON))
        defer { StubURLProtocol.reset() }

        let token = try await makeClient().exchangeCode("the-code", codeVerifier: "the-verifier")

        #expect(token.accessToken == "ghu_abc")
        #expect(token.refreshToken == "ghr_xyz")
        #expect(token.expiresIn == 28_800)
        #expect(token.refreshTokenExpiresIn == 15_897_600)
        #expect(token.scope == "", "GitHub App 用户令牌的 scope 恒为空串（§3.4）")
        #expect(StubURLProtocol.requestCount == 1)
    }

    @Test("令牌端点以 HTTP 200 返回业务错误时也必须失败 —— 不能只看状态码")
    func exchangeBusinessErrorDespite200() async throws {
        StubURLProtocol.stub(.json(
            #"{"error":"bad_verification_code","error_description":"The code passed is incorrect or expired."}"#,
            status: 200
        ))
        defer { StubURLProtocol.reset() }

        let client = makeClient()
        await #expect(throws: OAuthError.tokenEndpointError(
            code: "bad_verification_code",
            description: "The code passed is incorrect or expired."
        )) {
            _ = try await client.exchangeCode("bad", codeVerifier: "v")
        }
    }

    @Test("响应缺 refresh_token 时失败 —— 静默刷新依赖它（§3.2）")
    func exchangeMissingRefreshToken() async throws {
        StubURLProtocol.stub(.json(#"{"access_token":"ghu_abc","expires_in":28800,"token_type":"bearer"}"#))
        defer { StubURLProtocol.reset() }

        let client = makeClient()
        await #expect(throws: OAuthError.missingRefreshToken) {
            _ = try await client.exchangeCode("c", codeVerifier: "v")
        }
    }

    @Test("响应缺 access_token 时失败")
    func exchangeMissingAccessToken() async throws {
        StubURLProtocol.stub(.json(#"{"refresh_token":"ghr_xyz","expires_in":28800}"#))
        defer { StubURLProtocol.reset() }

        let client = makeClient()
        await #expect(throws: OAuthError.missingAccessToken) {
            _ = try await client.exchangeCode("c", codeVerifier: "v")
        }
    }

    @Test("非 2xx 状态码映射为 httpStatus")
    func exchangeHTTPError() async throws {
        StubURLProtocol.stub(.empty(status: 500))
        defer { StubURLProtocol.reset() }

        let client = makeClient()
        await #expect(throws: OAuthError.httpStatus(500)) {
            _ = try await client.exchangeCode("c", codeVerifier: "v")
        }
    }

    @Test("响应不是 JSON 时映射为 invalidResponse（不崩溃）")
    func exchangeNonJSONBody() async throws {
        StubURLProtocol.stub(.json("<html>502 Bad Gateway</html>"))
        defer { StubURLProtocol.reset() }

        let client = makeClient()
        await #expect(throws: OAuthError.invalidResponse) {
            _ = try await client.exchangeCode("c", codeVerifier: "v")
        }
    }

    // MARK: - 刷新

    @Test("刷新请求恰好 4 个字段：grant_type + client_secret 都在（官方 Required）")
    func refreshRequestShape() throws {
        let request = try makeClient().makeRefreshRequest(refreshToken: "ghr_xyz")
        let fields = try formFields(request)

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://github.com/login/oauth/access_token")
        #expect(fields["grant_type"] == "refresh_token")
        #expect(fields["refresh_token"] == "ghr_xyz")
        #expect(fields["client_id"] == "Iv23liTESTclientid")
        #expect(fields["client_secret"] == "s3cr3t-soft")
        #expect(fields.count == 4)
        #expect(fields["code_verifier"] == nil, "刷新不需要 code_verifier")
    }

    @Test("刷新成功：拿到轮换后的新令牌")
    func refreshSuccess() async throws {
        StubURLProtocol.stub(.json(
            #"{"access_token":"ghu_new","expires_in":28800,"refresh_token":"ghr_new","refresh_token_expires_in":15897600,"token_type":"bearer","scope":""}"#
        ))
        defer { StubURLProtocol.reset() }

        let token = try await makeClient().refresh(refreshToken: "ghr_old")
        #expect(token.accessToken == "ghu_new")
        #expect(token.refreshToken == "ghr_new")
    }

    @Test("过期时刻由「当前时刻 + 有效期」推导（8 小时 / 6 个月）")
    func tokenExpiries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let token = OAuthToken(
            accessToken: "a", refreshToken: "r", tokenType: "bearer",
            expiresIn: 28_800, refreshTokenExpiresIn: 15_897_600
        )
        let expiries = token.expiries(now: now)
        #expect(expiries.access == now.addingTimeInterval(8 * 3600))
        #expect(expiries.refresh == now.addingTimeInterval(15_897_600))
    }

    // MARK: - 撤销（登出用，§3.6）

    @Test("撤销请求：DELETE 到 /applications/{client_id}/grant，Basic Auth = base64(id:secret)")
    func revokeRequestShape() throws {
        let request = try makeClient().makeRevokeRequest(accessToken: "ghu_abc")
        let fields = try formFields(request)

        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.absoluteString
                == "https://api.github.com/applications/Iv23liTESTclientid/grant")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")

        let expected = "Basic " + Data("Iv23liTESTclientid:s3cr3t-soft".utf8).base64EncodedString()
        #expect(request.value(forHTTPHeaderField: "Authorization") == expected)

        #expect(fields["access_token"] == "ghu_abc")
        #expect(fields.count == 1)
        // 鉴权走 Basic(id:secret)，**不能**把待撤销的令牌放进 Authorization 头
        #expect(request.value(forHTTPHeaderField: "Authorization")?.contains("ghu_abc") == false)
    }

    @Test("撤销成功：204；404 也算已撤销（幂等，重复登出不该报失败）")
    func revokeAcceptsSuccessAndNotFound() async throws {
        StubURLProtocol.stub(.empty(status: 204))
        defer { StubURLProtocol.reset() }
        try await makeClient().revokeAuthorization(accessToken: "ghu_abc")

        StubURLProtocol.stub(.empty(status: 404))
        try await makeClient().revokeAuthorization(accessToken: "ghu_abc")
    }

    @Test("撤销失败：422 → revokeFailed（调用方降级但不阻塞登出，§3.6）")
    func revokeReportsFailure() async throws {
        StubURLProtocol.stub(.empty(status: 422))
        defer { StubURLProtocol.reset() }

        let client = makeClient()
        await #expect(throws: OAuthError.revokeFailed(422)) {
            try await client.revokeAuthorization(accessToken: "ghu_abc")
        }
    }

    // MARK: - 缓存（令牌响应不得落盘，§3.1 / §3.7）

    @Test("默认会话**不挂 URLCache** —— 令牌响应无从落盘")
    func defaultSessionHasNoCache() {
        let client = GitHubOAuthClient(credentials: credentials)

        #expect(
            client.session.configuration.urlCache == nil,
            "带磁盘缓存的会话会把换令牌响应写进 Library/Caches/<bundle>/Cache.db"
        )
        #expect(client.session.configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }

    @Test("三条令牌请求都显式声明非缓存策略（防会话被换回 .shared）")
    func tokenRequestsAreNonCaching() throws {
        let client = makeClient()

        let exchange = try client.makeExchangeRequest(code: "c-1", codeVerifier: "v-1")
        let refresh = try client.makeRefreshRequest(refreshToken: "ghr_xyz")
        let revoke = try client.makeRevokeRequest(accessToken: "ghu_abc")

        for (name, request) in [("换令牌", exchange), ("刷新", refresh), ("撤销", revoke)] {
            #expect(
                request.cachePolicy == GitHubOAuthClient.nonCachingPolicy,
                "\(name)请求落到了缓存策略上：令牌请求命中缓存 = 把令牌交给缓存"
            )
        }
    }

    // MARK: - 未配置

    @Test("凭据未配置时拒绝构造请求 —— 不发出注定失败的调用")
    func refusesWhenNotConfigured() throws {
        let client = GitHubOAuthClient(
            credentials: GitHubAppCredentials(
                clientID: "",
                clientSecret: "",
                callbackURL: "gitduo://oauth/callback",
                apiVersion: "2026-03-10"
            ),
            session: StubURLProtocol.makeSession()
        )

        #expect(client.credentials.isConfigured == false)
        #expect(client.credentials.revokeGrantURL == nil)
        #expect(throws: OAuthError.notConfigured) {
            _ = try client.makeExchangeRequest(code: "c", codeVerifier: "v")
        }
        #expect(throws: OAuthError.notConfigured) {
            _ = try client.makeRefreshRequest(refreshToken: "r")
        }
        #expect(throws: OAuthError.notConfigured) {
            _ = try client.makeRevokeRequest(accessToken: "a")
        }
    }

    @Test("只填 client_id、缺 client_secret 同样视为未配置（决策 #30：两项都要）")
    func halfConfiguredIsNotConfigured() {
        let credentials = GitHubAppCredentials(
            clientID: "Iv23liTESTclientid",
            clientSecret: "",
            callbackURL: "gitduo://oauth/callback",
            apiVersion: "2026-03-10"
        )
        #expect(credentials.isConfigured == false)
    }

    @Test("错误文案绝不回显 secret 或授权码")
    func errorDescriptionsDoNotLeakSecrets() {
        let errors: [OAuthError] = [
            .notConfigured,
            .invalidResponse,
            .httpStatus(500),
            .tokenEndpointError(code: "bad_verification_code", description: "…"),
            .missingAccessToken,
            .missingRefreshToken,
            .revokeFailed(422)
        ]
        for error in errors {
            let text = error.errorDescription ?? ""
            #expect(!text.contains("s3cr3t-soft"), "错误文案泄漏了 secret：\(text)")
            #expect(!text.contains("the-code"), "错误文案泄漏了授权码：\(text)")
            #expect(!text.isEmpty)
        }
    }
}
