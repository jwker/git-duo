import Foundation
import GitHubAPI
import GitDuoCore
import Testing

@testable import GitDuoAuth

/// `AuthCoordinator` 的行为规格 —— 切片 1 的核心验收。
///
/// 依据：TECH_SPEC §3.1（授权流程八步）、§3.2（刷新与 single-flight）、
///      §3.6（登出与撤销降级）、§3.8（取消 / 失败的出口）、§12.2。
///
/// **不需要 `.serialized`**：桩件状态按命名空间隔离（见 `harness`），套件内部与套件之间都可并行。
/// （早期版本把路由表放在进程级静态变量里、靠 `.serialized` 硬扛 —— 那正是"单跑全绿、全量跑挂"的温床。）
@Suite("AuthCoordinator · 授权编排 / 刷新 / 登出")
struct AuthCoordinatorTests {

    // MARK: - 夹具

    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private static let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private static let tokenEndpointPath = "/login/oauth/access_token"
    private static let revokePath = "/applications/Iv23liTESTclientid/grant"

    // ⚠️ 写成**单行**：raw string（`#"""`）里反斜杠是字面量，用它续行会把 `\` 喂进 JSON。
    private static let successJSON = """
    {"access_token":"ghu_abc","expires_in":28800,"refresh_token":"ghr_xyz","refresh_token_expires_in":15897600,"token_type":"bearer","scope":""}
    """

    private static let refreshedJSON = """
    {"access_token":"ghu_new","expires_in":28800,"refresh_token":"ghr_new","refresh_token_expires_in":15897600,"token_type":"bearer","scope":""}
    """

    private let store = InMemoryTokenStore()

    /// 接口缓存清理器的替身 —— 登出必须调用它（见 `signOutPurgesHTTPCache`）。
    private let purger = SpyCachePurger()

    /// 本套件专属的桩件状态。
    ///
    /// Swift Testing **为每个用例新建一个套件实例** ⇒ 每次测试都拿到一份全新的 harness，
    /// 套件内并行、跨套件并行都不互相踩。
    private let harness = StubURLProtocol.makeHarness()

    private func makeCoordinator() -> AuthCoordinator {
        AuthCoordinator(
            credentials: Self.credentials,
            tokenStore: store,
            session: harness.makeSession(),
            cachePurger: purger,
            clock: { Self.fixedNow }
        )
    }

    private func storedToken(
        access: String = "ghu_old",
        refresh: String = "ghr_old",
        accessExpiresIn: TimeInterval = 8 * 3600,
        refreshExpiresIn: TimeInterval = 15_897_600,
        login: String = "jiangjiang"
    ) -> StoredToken {
        StoredToken(
            accessToken: access,
            refreshToken: refresh,
            accessTokenExpiry: Self.fixedNow.addingTimeInterval(accessExpiresIn),
            refreshTokenExpiry: Self.fixedNow.addingTimeInterval(refreshExpiresIn),
            login: login
        )
    }

    private func callbackURL(code: String, state: String) -> URL {
        URL(string: "gitduo://oauth/callback?code=\(code)&state=\(state)")!
    }

    /// 从授权 URL 里取回 `state` —— 它才是回调该带的值（`beginAuthorization` 不外泄 verifier）。
    private func state(of authorizeURL: URL) throws -> String {
        let items = try #require(
            URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)?.queryItems
        )
        return try #require(items.first { $0.name == "state" }?.value)
    }

    private func loadStored() throws -> StoredToken? {
        try store.load()
    }

    // MARK: - 启动恢复

    @Test("无凭据：直接未认证，且一个请求都不发")
    func restoreWithoutCredentials() async throws {
        harness.setStubs([])
        defer { harness.reset() }

        let state = await makeCoordinator().restore()

        #expect(state == .unauthenticated)
        #expect(harness.requests.isEmpty, "启动不该为了'确认未登录'去打扰 GitHub")
    }

    @Test("凭据新鲜：直接放行，不发请求（启动要快，也要省配额）")
    func restoreWithFreshToken() async throws {
        try store.save(storedToken())
        harness.setStubs([])
        defer { harness.reset() }

        let state = await makeCoordinator().restore()

        #expect(state == .authenticated(login: "jiangjiang"))
        #expect(harness.requests.isEmpty)
    }

    @Test("access token 进入预刷新窗口：刷一次并落盘轮换后的令牌")
    func restoreRefreshesWhenNearExpiry() async throws {
        // 只剩 60 秒 → 落在"过期前 5 分钟"的窗口内
        try store.save(storedToken(accessExpiresIn: 60))
        harness.setStubs([
            .response("POST", Self.tokenEndpointPath, Self.refreshedJSON)
        ])
        defer { harness.reset() }

        let state = await makeCoordinator().restore()

        #expect(state == .authenticated(login: "jiangjiang"))
        let stored = try #require(try loadStored())
        #expect(stored.accessToken == "ghu_new")
        #expect(stored.refreshToken == "ghr_new", "刷新会轮换 refresh_token，两个都要换掉")
        #expect(stored.login == "jiangjiang", "登录名不能因为刷新而丢失")
        #expect(stored.accessTokenExpiry == Self.fixedNow.addingTimeInterval(28_800))
        #expect(harness.count(method: "POST", path: Self.tokenEndpointPath) == 1)
    }

    @Test("refresh token 已过期（6 个月）：清掉残留并回登录页，不发请求")
    func restoreWhenRefreshTokenExpired() async throws {
        try store.save(storedToken(refreshExpiresIn: -1))
        harness.setStubs([])
        defer { harness.reset() }

        let state = await makeCoordinator().restore()

        #expect(state == .unauthenticated)
        #expect(try loadStored() == nil, "过期的凭据必须清掉，否则每次启动都在同一处失败")
        #expect(harness.requests.isEmpty)
    }

    @Test("刷新遇网络故障：**不清凭据**，仍然放行（断网不等于被登出）")
    func restoreKeepsCredentialsOnNetworkFailure() async throws {
        try store.save(storedToken(accessExpiresIn: 60))
        harness.setStubs([
            .response("POST", Self.tokenEndpointPath, status: 500)
        ])
        defer { harness.reset() }

        let state = await makeCoordinator().restore()

        #expect(state == .authenticated(login: "jiangjiang"), "一次断网不该把用户登出")
        #expect(try loadStored() != nil, "凭据必须留着——它很可能还在有效期内")
    }

    @Test("refresh token 被撤销（令牌端点以 200 回传错误）：清凭据并回登录页")
    func restoreSignsOutWhenRefreshTokenRevoked() async throws {
        try store.save(storedToken(accessExpiresIn: 60))
        harness.setStubs([
            .response(
                "POST", Self.tokenEndpointPath,
                #"{"error":"bad_refresh_token","error_description":"The refresh token is invalid."}"#
            )
        ])
        defer { harness.reset() }

        let state = await makeCoordinator().restore()

        #expect(state == .unauthenticated)
        #expect(try loadStored() == nil)
    }

    // MARK: - 发起授权

    @Test("授权 URL：恰好 5 个参数，且**不含** client_secret 与 code_verifier")
    func beginAuthorizationURLShape() async throws {
        let url = try await makeCoordinator().beginAuthorization()
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        #expect(url.path == "/login/oauth/authorize")
        #expect(fields["client_id"] == "Iv23liTESTclientid")
        #expect(fields["redirect_uri"] == "gitduo://oauth/callback")
        #expect(fields["code_challenge_method"] == "S256")
        #expect(fields["state"]?.isEmpty == false)
        #expect(fields["code_challenge"]?.isEmpty == false)
        #expect(fields.count == 5)

        #expect(fields["client_secret"] == nil, "授权 URL 会留在浏览器历史里，绝不能带 secret")
        #expect(fields["code_verifier"] == nil, "verifier 只存内存，绝不外传")
    }

    @Test("每次发起授权都换一个 state（一次性，不可复用）")
    func beginAuthorizationUsesFreshState() async throws {
        let coordinator = makeCoordinator()
        let first = try state(of: try await coordinator.beginAuthorization())
        let second = try state(of: try await coordinator.beginAuthorization())

        #expect(first != second)
    }

    @Test("凭据未配置：拒绝发起授权，不产生注定失败的跳转")
    func beginAuthorizationRefusesWhenNotConfigured() async throws {
        let coordinator = AuthCoordinator(
            credentials: GitHubAppCredentials(
                clientID: "",
                clientSecret: "",
                callbackURL: "gitduo://oauth/callback",
                apiVersion: "2026-03-10"
            ),
            tokenStore: store,
            session: harness.makeSession(),
            clock: { Self.fixedNow }
        )

        await #expect(throws: AuthError.notConfigured) {
            _ = try await coordinator.beginAuthorization()
        }
    }

    // MARK: - 处理回调

    @Test("完整授权：校验 state → 换令牌 → GET /user → 写 Keychain")
    func completeAuthorizationHappyPath() async throws {
        let coordinator = makeCoordinator()
        let authorizeURL = try await coordinator.beginAuthorization()
        let expectedState = try state(of: authorizeURL)

        harness.setStubs([
            .response("POST", Self.tokenEndpointPath, Self.successJSON),
            .response("GET", "/user", #"{"login":"jiangjiang"}"#)
        ])
        defer { harness.reset() }

        let outcome = await coordinator.completeAuthorization(
            callbackURL: callbackURL(code: "the-code", state: expectedState)
        )

        #expect(outcome == .authenticated(login: "jiangjiang"))
        let stored = try #require(try loadStored())
        #expect(stored.accessToken == "ghu_abc")
        #expect(stored.refreshToken == "ghr_xyz")
        #expect(stored.login == "jiangjiang")
        #expect(stored.accessTokenExpiry == Self.fixedNow.addingTimeInterval(28_800))
        #expect(stored.refreshTokenExpiry == Self.fixedNow.addingTimeInterval(15_897_600))
        #expect(harness.count(method: "POST", path: Self.tokenEndpointPath) == 1)
        #expect(harness.count(method: "GET", path: "/user") == 1)
    }

    @Test("换令牌请求体带 client_secret，且 verifier 是本次授权生成的那个")
    func completeAuthorizationSendsPKCEMaterial() async throws {
        let coordinator = makeCoordinator()
        let authorizeURL = try await coordinator.beginAuthorization()
        let expectedState = try state(of: authorizeURL)

        harness.setStubs([
            .response("POST", Self.tokenEndpointPath, Self.successJSON),
            .response("GET", "/user", #"{"login":"jiangjiang"}"#)
        ])
        defer { harness.reset() }

        _ = await coordinator.completeAuthorization(
            callbackURL: callbackURL(code: "the-code", state: expectedState)
        )

        let exchange = try #require(
            harness.requests.first { $0.httpMethod == "POST" }
        )
        let body = try #require(StubURLProtocol.bodyData(of: exchange))
        let fields = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])

        #expect(fields["client_secret"] == "s3cr3t-soft")
        #expect(fields["redirect_uri"] == "gitduo://oauth/callback")
        let verifier = try #require(fields["code_verifier"])
        #expect(verifier.count >= 43, "RFC 7636 §4.1 要求 43–128 字符")

        // verifier 必须与授权 URL 里的 challenge 对应（S256），否则换令牌会被拒
        let items = try #require(URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)?.queryItems)
        let challenge = try #require(items.first { $0.name == "code_challenge" }?.value)
        #expect(PKCE.codeChallenge(for: verifier) == challenge)
    }

    @Test("不是本 App 的回调：静默丢弃，且不碰网络")
    func completeAuthorizationIgnoresForeignScheme() async throws {
        let coordinator = makeCoordinator()
        _ = try await coordinator.beginAuthorization()
        harness.setStubs([])
        defer { harness.reset() }

        let outcome = await coordinator.completeAuthorization(
            callbackURL: URL(string: "evil://oauth/callback?code=x&state=y")!
        )

        #expect(outcome == .ignored)
        #expect(harness.requests.isEmpty)
    }

    @Test("伪装路径（host 不同）：同样丢弃 —— 只比 path 会漏掉它")
    func completeAuthorizationIgnoresDisguisedHost() async throws {
        let coordinator = makeCoordinator()
        _ = try await coordinator.beginAuthorization()
        harness.setStubs([])
        defer { harness.reset() }

        let outcome = await coordinator.completeAuthorization(
            callbackURL: URL(string: "gitduo://evil/callback?code=x&state=y")!
        )

        #expect(outcome == .ignored)
        #expect(harness.requests.isEmpty)
    }

    @Test("state 不匹配：拒绝，且绝不拿这个 code 去换令牌")
    func completeAuthorizationRejectsStateMismatch() async throws {
        let coordinator = makeCoordinator()
        _ = try await coordinator.beginAuthorization()
        harness.setStubs([
            .response("POST", Self.tokenEndpointPath, Self.successJSON)
        ])
        defer { harness.reset() }

        let outcome = await coordinator.completeAuthorization(
            callbackURL: callbackURL(code: "attacker-code", state: "not-the-state")
        )

        #expect(outcome == .failed(.callbackRejected(.stateMismatch)))
        #expect(harness.requests.isEmpty, "state 不对就绝不能把 code 发出去")
        #expect(try loadStored() == nil)
    }

    @Test("用户取消（error=access_denied）：算正常操作，不报错、不写凭据")
    func completeAuthorizationTreatsDenialAsCancelled() async throws {
        let coordinator = makeCoordinator()
        _ = try await coordinator.beginAuthorization()
        harness.setStubs([])
        defer { harness.reset() }

        let outcome = await coordinator.completeAuthorization(
            callbackURL: URL(string: "gitduo://oauth/callback?error=access_denied&error_description=The+user+denied")!
        )

        #expect(outcome == .cancelled, "取消不是错误——文案上不该吓唬用户")
        #expect(harness.requests.isEmpty)
        #expect(try loadStored() == nil)
    }

    @Test("GitHub 回传其他 error：失败，且文案不做网址编码直出")
    func completeAuthorizationReportsServiceError() async throws {
        let coordinator = makeCoordinator()
        _ = try await coordinator.beginAuthorization()
        harness.setStubs([])
        defer { harness.reset() }

        let outcome = await coordinator.completeAuthorization(
            callbackURL: URL(string: "gitduo://oauth/callback?error=bad_verification_code&error_description=Code+expired")!
        )

        #expect(outcome == .failed(.callbackRejected(
            .serviceError(code: "bad_verification_code", description: "Code expired")
        )))
        if case let .failed(error) = outcome {
            let text = error.errorDescription ?? ""
            #expect(!text.contains("+"), "`+` 必须还原成空格，否则用户看到的是 Code+expired")
        }
    }

    @Test("没有等待中的授权就收到回调：按 state 不匹配拒绝（不会凭空登录）")
    func completeAuthorizationWithoutPendingContext() async throws {
        let coordinator = makeCoordinator()
        harness.setStubs([])
        defer { harness.reset() }

        let outcome = await coordinator.completeAuthorization(
            callbackURL: callbackURL(code: "the-code", state: "any-state")
        )

        #expect(outcome == .failed(.callbackRejected(.stateMismatch)))
    }

    @Test("同一个回调投递两次：第二次必须失败（state 一次性）")
    func completeAuthorizationRejectsReplay() async throws {
        let coordinator = makeCoordinator()
        let authorizeURL = try await coordinator.beginAuthorization()
        let expectedState = try state(of: authorizeURL)
        harness.setStubs([
            .response("POST", Self.tokenEndpointPath, Self.successJSON),
            .response("GET", "/user", #"{"login":"jiangjiang"}"#)
        ])
        defer { harness.reset() }

        let callback = callbackURL(code: "the-code", state: expectedState)
        let first = await coordinator.completeAuthorization(callbackURL: callback)
        let second = await coordinator.completeAuthorization(callbackURL: callback)

        #expect(first == .authenticated(login: "jiangjiang"))
        #expect(second == .failed(.callbackRejected(.stateMismatch)))
    }

    @Test("换令牌失败：不写凭据 —— 宁可没登录，也不要半个凭据")
    func completeAuthorizationDoesNotPersistOnExchangeFailure() async throws {
        let coordinator = makeCoordinator()
        let authorizeURL = try await coordinator.beginAuthorization()
        let expectedState = try state(of: authorizeURL)
        harness.setStubs([
            .response(
                "POST", Self.tokenEndpointPath,
                #"{"error":"bad_verification_code","error_description":"The code passed is incorrect or expired."}"#
            )
        ])
        defer { harness.reset() }

        let outcome = await coordinator.completeAuthorization(
            callbackURL: callbackURL(code: "the-code", state: expectedState)
        )

        #expect(outcome == .failed(.oauth(.tokenEndpointError(
            code: "bad_verification_code",
            description: "The code passed is incorrect or expired."
        ))))
        #expect(try loadStored() == nil)
    }

    @Test("GET /user 校验失败（401）：不写凭据，授权视为未完成")
    func completeAuthorizationDoesNotPersistWhenProfileFails() async throws {
        let coordinator = makeCoordinator()
        let authorizeURL = try await coordinator.beginAuthorization()
        let expectedState = try state(of: authorizeURL)
        harness.setStubs([
            .response("POST", Self.tokenEndpointPath, Self.successJSON),
            .response("GET", "/user", "", status: 401)
        ])
        defer { harness.reset() }

        let outcome = await coordinator.completeAuthorization(
            callbackURL: callbackURL(code: "the-code", state: expectedState)
        )

        #expect(outcome == .failed(.oauth(.httpStatus(401))))
        #expect(try loadStored() == nil, "步骤 8 没过就不算登录（§3.1）")
    }

    // MARK: - 令牌供给

    @Test("未登录时索取令牌：抛 GitHubError.unauthorized（不静默返回空串）")
    func validAccessTokenRequiresSession() async throws {
        harness.setStubs([])
        defer { harness.reset() }

        // ⚠️ 出口错误是**归一化后**的 GitHubError，不是内部的 AuthError ——
        //    数据层不认识 AuthError，它只需要"凭据不可用 ⇒ 回登录页"这一个结论。
        await #expect(throws: GitHubError.unauthorized) {
            _ = try await makeCoordinator().validAccessToken()
        }
    }

    @Test("编排层内部仍拿到细分的 AuthError（归一化不污染本包自己的语义）")
    func loadValidAccessTokenKeepsAuthError() async throws {
        harness.setStubs([])
        defer { harness.reset() }

        await #expect(throws: AuthError.notAuthenticated) {
            _ = try await makeCoordinator().loadValidAccessToken()
        }
    }

    @Test("刷新时收到 401：数据层出口抛 unauthorized（refresh token 真的没了）")
    func refreshUnauthorizedMapsToUnauthorized() async throws {
        try store.save(storedToken(accessExpiresIn: 30))
        harness.setStubs([
            .response("POST", Self.tokenEndpointPath, "", status: 401)
        ])
        defer { harness.reset() }

        let provider: any AccessTokenProviding = makeCoordinator()
        await #expect(throws: GitHubError.unauthorized) {
            _ = try await provider.validAccessToken()
        }
    }

    @Test("刷新时收到 500：抛 serverError，**绝不算凭据失效**（§3.2 第 3 条：5xx 不登出）")
    func refreshServerErrorDoesNotInvalidateCredentials() async throws {
        try store.save(storedToken(accessExpiresIn: 30))
        harness.setStubs([
            .response("POST", Self.tokenEndpointPath, "", status: 500)
        ])
        defer { harness.reset() }

        let provider: any AccessTokenProviding = makeCoordinator()
        await #expect(throws: GitHubError.serverError(status: 500)) {
            _ = try await provider.validAccessToken()
        }
        #expect(try loadStored() != nil, "5xx 之后凭据必须原地不动 —— 否则一次服务端抖动就把人登出")
    }

    @Test("令牌端点以 200 回传 error：也算凭据失效（状态码通过 ≠ 成功）")
    func tokenEndpointErrorMapsToUnauthorized() async throws {
        try store.save(storedToken(accessExpiresIn: 30))
        harness.setStubs([
            .response("POST", Self.tokenEndpointPath, #"{"error":"bad_refresh_token"}"#)
        ])
        defer { harness.reset() }

        let provider: any AccessTokenProviding = makeCoordinator()
        await #expect(throws: GitHubError.unauthorized) {
            _ = try await provider.validAccessToken()
        }
    }

    @Test("刷新时网络层失败：抛 .transport，**不是** unauthorized（断网 ≠ 登出）")
    func refreshTransportFailureIsNotUnauthorized() async throws {
        try store.save(storedToken(accessExpiresIn: 30))
        // 空路由表 ⇒ 桩件以 `URLError` 失败，即"拿不到响应"
        harness.setStubs([])
        defer { harness.reset() }

        let provider: any AccessTokenProviding = makeCoordinator()
        var sawTransport = false
        do {
            _ = try await provider.validAccessToken()
            Issue.record("没网就该抛错")
        } catch let error as GitHubError {
            guard case .transport = error else {
                Issue.record("网络层失败必须归为 .transport，实际：\(error)")
                return
            }
            sawTransport = true
        }
        #expect(sawTransport)
        #expect(try loadStored() != nil, "断网绝不能把凭据清掉")
    }

    @Test("令牌新鲜：直接返回，不刷新（省一次往返，也省配额）")
    func validAccessTokenReturnsFreshToken() async throws {
        try store.save(storedToken())
        harness.setStubs([])
        defer { harness.reset() }

        let token = try await makeCoordinator().validAccessToken()

        #expect(token == "ghu_old")
        #expect(harness.requests.isEmpty)
    }

    @Test("令牌进入预刷新窗口：先刷新再返回新令牌")
    func validAccessTokenRefreshesWhenNeeded() async throws {
        try store.save(storedToken(accessExpiresIn: 30))
        harness.setStubs([
            .response("POST", Self.tokenEndpointPath, Self.refreshedJSON)
        ])
        defer { harness.reset() }

        let token = try await makeCoordinator().validAccessToken()

        #expect(token == "ghu_new")
        #expect(harness.count(method: "POST", path: Self.tokenEndpointPath) == 1)
    }

    // MARK: - single-flight

    @Test("并发 5 次强制刷新：令牌端点只收到 1 个请求（并发刷新会互相作废）")
    func refreshIsSingleFlight() async throws {
        try store.save(storedToken(accessExpiresIn: 60))
        harness.setStubs([
            .response("POST", Self.tokenEndpointPath, Self.refreshedJSON, delay: 0.3)
        ])
        defer { harness.reset() }

        let coordinator = makeCoordinator()
        let results = await withTaskGroup(of: Result<String, any Error>.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    do { return .success(try await coordinator.forceRefreshAccessToken()) }
                    catch { return .failure(error) }
                }
            }
            var collected: [Result<String, any Error>] = []
            for await result in group { collected.append(result) }
            return collected
        }

        #expect(results.count == 5)
        for result in results {
            #expect(try result.get() == "ghu_new", "所有调用者都应拿到同一次刷新的结果")
        }
        #expect(
            harness.count(method: "POST", path: Self.tokenEndpointPath) == 1,
            "并发刷新必须共享同一个请求，否则 refresh_token 轮换会互相作废"
        )
    }

    // MARK: - 与数据层接线（HTTPTransport ↔ AuthCoordinator）

    /// 装配一个**真的**走 `AuthCoordinator` 取令牌的 transport。
    ///
    /// 这一段的用意：协议一致性本身是可编译性保证，但"两半合起来到底对不对"
    /// 只有跑一遍才知道 —— 尤其"401 之后重放用的是新令牌"这件事，
    /// 两边各自的单测都覆盖不到。
    private func makeTransport(provider: any AccessTokenProviding) -> HTTPTransport {
        let clock = Self.fixedNow
        return HTTPTransport(
            credentials: Self.credentials,
            tokenProvider: provider,
            session: harness.makeSession(),
            cache: HTTPResponseCache(configuration: .memoryOnly()),
            retryPolicy: .none,
            clock: { clock },
            sleeper: { _ in }
        )
    }

    @Test("接线：数据端点 401 → 强制刷新一次 → 重放一次，且重放带的是**新令牌**")
    func transportRefreshesAndReplaysThroughCoordinator() async throws {
        try store.save(storedToken())  // 8 小时，不在预刷新窗口
        harness.setStubs([
            .response("GET", "/user", "", status: 401),
            .response("POST", Self.tokenEndpointPath, Self.refreshedJSON)
        ])
        defer { harness.reset() }

        let transport = makeTransport(provider: makeCoordinator())

        // 数据端点永远 401 ⇒ 重放那一次同样失败，最终如实报 unauthorized
        await #expect(throws: GitHubError.unauthorized) {
            _ = try await transport.send(.get(URL(string: "https://api.github.com/user")!))
        }

        #expect(
            harness.count(method: "GET", path: "/user") == 2,
            "原请求 + 重放，**只重放一次**（§3.2 第 2 条）"
        )
        #expect(harness.count(method: "POST", path: Self.tokenEndpointPath) == 1)

        let authorizations = harness.requests
            .filter { $0.httpMethod == "GET" && $0.url?.path == "/user" }
            .map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(
            authorizations == ["Bearer ghu_old", "Bearer ghu_new"],
            "重放必须带刷新后的新令牌 —— 拿旧令牌重放等于白刷一次"
        )
    }

    @Test("接线：并发 5 个 401 只触发**一次**刷新（否则 refresh_token 轮换会互相作废）")
    func concurrent401sShareOneRefresh() async throws {
        try store.save(storedToken())
        harness.setStubs([
            .response("GET", "/user", "", status: 401),
            // 延迟制造"刷新还没回来"的窗口 —— 没有它，5 次刷新会一个接一个地跑完，测不出共享
            .response("POST", Self.tokenEndpointPath, Self.refreshedJSON, delay: 0.3)
        ])
        defer { harness.reset() }

        let transport = makeTransport(provider: makeCoordinator())
        let url = URL(string: "https://api.github.com/user")!

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { _ = try? await transport.send(.get(url)) }
            }
        }

        #expect(
            harness.count(method: "POST", path: Self.tokenEndpointPath) == 1,
            "并发 401 必须共享同一次刷新（single-flight 由 AuthCoordinator 保证）"
        )
    }

    // MARK: - 登出

    @Test("登出：先撤销 GitHub 侧授权（DELETE grant，Basic Auth），再清本地凭据")
    func signOutRevokesThenClears() async throws {
        try store.save(storedToken())
        harness.setStubs([
            .response("DELETE", Self.revokePath, status: 204)
        ])
        defer { harness.reset() }

        let outcome = await makeCoordinator().signOut()

        #expect(outcome == .revoked)
        #expect(try loadStored() == nil)

        let revoke = try #require(harness.requests.first)
        #expect(revoke.httpMethod == "DELETE")
        #expect(revoke.url?.path == Self.revokePath)
        let expectedAuth = "Basic " + Data("Iv23liTESTclientid:s3cr3t-soft".utf8).base64EncodedString()
        #expect(revoke.value(forHTTPHeaderField: "Authorization") == expectedAuth)

        let body = try #require(StubURLProtocol.bodyData(of: revoke))
        let fields = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(fields["access_token"] == "ghu_old")
        #expect(
            harness.count(method: "POST", path: Self.tokenEndpointPath) == 0,
            "一次就成 ⇒ 不该多花一个刷新请求（新增的重试只挂在失败路径上）"
        )
    }

    @Test("撤销失败 ⇒ 刷新一次、**拿新令牌再试一次**（少了这一下，登出可能悄悄地没撤销）")
    func signOutRetriesRevokeWithRefreshedToken() async throws {
        try store.save(storedToken())
        harness.setStubs([
            // 手里那张（`ghu_old`）已过期 ⇒ 服务端拒（422）
            .response("DELETE", Self.revokePath, status: 422),
            // 而 `refresh_token` 还在 6 个月内 ⇒ 刷新能拿到 `ghu_new`
            .response("POST", Self.tokenEndpointPath, Self.refreshedJSON, status: 200),
        ])
        defer { harness.reset() }

        let outcome = await makeCoordinator().signOut()

        #expect(outcome == .revokedLocallyOnly, "两次都没成 ⇒ 如实降级，不谎报")
        #expect(try loadStored() == nil)

        let revokes = harness.requests.filter { $0.httpMethod == "DELETE" }
        #expect(
            revokes.count == 2,
            "失败后必须再试一次 —— 少了这一下 GitHub 侧那条旧授权会活下来，下次登录会复用它的权限快照（账号级权限升级后这是唯一的修法）"
        )
        #expect(harness.count(method: "POST", path: Self.tokenEndpointPath) == 1)

        func accessToken(of request: URLRequest) throws -> String? {
            let body = try #require(StubURLProtocol.bodyData(of: request))
            let fields = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
            return fields["access_token"]
        }

        #expect(try accessToken(of: revokes[0]) == "ghu_old")
        #expect(
            try accessToken(of: revokes[1]) == "ghu_new",
            "⚠️ 第二次必须送**刷新后**的那张 —— 仍送旧的话，这一次重试只是白打一遍"
        )
    }

    @Test("连凭据都读不出来 ⇒ **不许报「已撤销」**（那一格根本没发出撤销请求）")
    func signOutDoesNotClaimRevocationWhenCredentialsUnreadable() async throws {
        harness.setStubs([])
        defer { harness.reset() }

        let coordinator = AuthCoordinator(
            credentials: Self.credentials,
            tokenStore: UnreadableTokenStore(),
            session: harness.makeSession(),
            cachePurger: purger,
            clock: { Self.fixedNow }
        )

        let outcome = await coordinator.signOut()

        #expect(
            outcome == .revokedLocallyOnly,
            "没发出过撤销请求就不能说'已撤销 GitHub 侧授权'—— 那是一句没有依据的陈述"
        )
        #expect(harness.requests.isEmpty, "读不出凭据 ⇒ 一次请求都不该发")
        #expect(purger.purgeCount == 1, "本地照样清干净（§3.6：失败不阻塞登出）")
    }

    @Test("撤销失败（422）：**仍清空本地凭据**，只把结局降级")
    func signOutClearsLocallyWhenRevokeFails() async throws {
        try store.save(storedToken())
        harness.setStubs([
            .response("DELETE", Self.revokePath, status: 422)
        ])
        defer { harness.reset() }

        let outcome = await makeCoordinator().signOut()

        #expect(outcome == .revokedLocallyOnly, "降级文案：提示'未能撤销 GitHub 侧授权'")
        #expect(try loadStored() == nil, "撤销失败不阻塞登出（§3.6）")
    }

    @Test("离线撤销（网络错误）：同样本地登出成功")
    func signOutClearsLocallyWhenOffline() async throws {
        try store.save(storedToken())
        harness.setStubs([])   // 无路由 ⇒ 请求失败
        defer { harness.reset() }

        let outcome = await makeCoordinator().signOut()

        #expect(outcome == .revokedLocallyOnly)
        #expect(try loadStored() == nil)
    }

    @Test("无凭据时登出：视为已登出，不发请求")
    func signOutWithoutCredentials() async throws {
        harness.setStubs([])
        defer { harness.reset() }

        let outcome = await makeCoordinator().signOut()

        #expect(outcome == .revoked)
        #expect(harness.requests.isEmpty)
    }

    // MARK: - 登出 · 接口缓存

    @Test("登出必须清掉接口缓存 —— 改写入路径清不掉**已经落盘**的副本")
    func signOutPurgesHTTPCache() async throws {
        try store.save(storedToken())
        harness.setStubs([
            .response("DELETE", Self.revokePath, status: 204)
        ])
        defer { harness.reset() }

        _ = await makeCoordinator().signOut()

        #expect(
            purger.purgeCount == 1,
            "磁盘上的令牌响应副本不受 Keychain 保护，只有这一步会清掉它"
        )
    }

    @Test("撤销失败（降级登出）也必须清缓存 —— 本地清干净才算登出")
    func signOutPurgesHTTPCacheEvenWhenRevokeFails() async throws {
        try store.save(storedToken())
        harness.setStubs([])   // 离线 ⇒ 撤销必然失败
        defer { harness.reset() }

        let outcome = await makeCoordinator().signOut()

        #expect(outcome == .revokedLocallyOnly)
        #expect(purger.purgeCount == 1, "撤销失败只降级提示文案，本地必须清干净（§3.6）")
    }

    @Test("无凭据时登出：不发请求，但缓存照清")
    func signOutWithoutCredentialsStillPurges() async throws {
        harness.setStubs([])
        defer { harness.reset() }

        _ = await makeCoordinator().signOut()

        #expect(
            purger.purgeCount == 1,
            "没有凭据也可能有上一轮遗留的缓存，登出就该清"
        )
    }

    // MARK: - 文案红线

    @Test("错误文案绝不泄漏 secret / 令牌 / 授权码")
    func errorDescriptionsDoNotLeakSecrets() {
        let errors: [AuthError] = [
            .notConfigured,
            .notAuthenticated,
            .refreshTokenExpired,
            .missingAuthorizationContext,
            .callbackRejected(.stateMismatch),
            .callbackRejected(.missingCode),
            .callbackRejected(.missingState),
            .callbackRejected(.serviceError(code: "bad_verification_code", description: "the-code")),
            .credentialStoreFailed,
            .oauth(.notConfigured),
            .oauth(.invalidResponse),
            .oauth(.httpStatus(500)),
            .oauth(.tokenEndpointError(code: "bad_verification_code", description: "the-code")),
            .oauth(.missingAccessToken),
            .oauth(.missingRefreshToken),
            .oauth(.revokeFailed(422))
        ]

        for error in errors {
            let text = error.errorDescription ?? ""
            #expect(!text.isEmpty, "\(error) 没有面向用户的文案")
            #expect(!text.contains("s3cr3t-soft"), "文案泄漏了 secret：\(text)")
            #expect(!text.contains("ghu_"), "文案泄漏了访问令牌：\(text)")
            #expect(!text.contains("ghr_"), "文案泄漏了刷新令牌：\(text)")
            #expect(!text.contains("the-code"), "文案泄漏了授权码：\(text)")
        }
    }

    @Test("只有'凭据失效'类错误才该导致登出；网络故障不算")
    func onlyCredentialErrorsInvalidateSession() {
        #expect(AuthError.refreshTokenExpired.invalidatesCredentials)
        #expect(AuthError.oauth(.httpStatus(401)).invalidatesCredentials)
        #expect(AuthError.oauth(.tokenEndpointError(code: "bad_refresh_token", description: nil))
            .invalidatesCredentials)

        #expect(!AuthError.oauth(.httpStatus(500)).invalidatesCredentials)
        #expect(!AuthError.oauth(.httpStatus(403)).invalidatesCredentials)
        #expect(!AuthError.oauth(.invalidResponse).invalidatesCredentials)
        #expect(!AuthError.notConfigured.invalidatesCredentials)
        #expect(!AuthError.notAuthenticated.invalidatesCredentials)
    }
}

/// 读凭据**直接抛错**的替身 —— 只有它能造出"登出时连撤销请求都没发出去"那一格
/// （`InMemoryTokenStore.load()` 不抛，所以那一格在它身上测不出来）。
///
/// 依据：`TECH_SPEC §3.6` 那条 🔴 的 ② —— 没发过撤销请求就不能报"已撤销"。
private final class UnreadableTokenStore: TokenStore, @unchecked Sendable {

    func save(_ token: StoredToken) throws {}

    func load() throws -> StoredToken? {
        // 形状对齐生产：Keychain 读失败会带着一个 `OSStatus` 出来。
        throw TokenStoreError.unexpectedStatus(-25300)
    }

    func clear() throws {}
}
