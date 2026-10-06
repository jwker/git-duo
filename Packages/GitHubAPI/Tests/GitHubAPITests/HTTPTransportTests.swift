import Foundation
import Testing

@testable import GitHubAPI

/// `HTTPTransport` 的规格 —— TECH_SPEC §4.1–§4.3 / §5.2 / §3.2 第 2 条。
///
/// 桩件用**本套件自持的 harness**（`StubURLProtocol.makeHarness()`），
/// 与其它网络套件并行也不互相覆盖。
///
/// ⚠️ 并发 401 的 **single-flight** 不在本套件验 —— 那是 `AuthCoordinator`
/// 的责任（见 `GitDuoAuth` 的测试）。这里只用桩件验"transport 自己不会重复刷新"。
@Suite("HTTPTransport · 请求头 / ETag / 401 重放 / 重试")
struct HTTPTransportTests {

    private let credentials = GitHubAppCredentials(
        clientID: "Iv23liTESTclientid",
        clientSecret: "s3cr3t-soft",
        callbackURL: "gitduo://oauth/callback",
        apiVersion: "2026-03-10"
    )

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let userURL = URL(string: "https://api.github.com/user")!

    // MARK: - 令牌供给替身

    final class FakeTokenProvider: AccessTokenProviding, @unchecked Sendable {

        private let lock = NSLock()
        private var validCallCount = 0
        private var refreshCallCount = 0
        private var token: String
        /// 两个失败开关**分开** —— 合成一个的话，"验证刷新失败"的场景会退化成
        /// "一开始就取不到令牌"（请求根本发不出去），断言看起来仍然通过，实则测了别的东西。
        private var validFailure: (any Error)?
        private var refreshFailure: (any Error)?

        init(token: String = "ghu_test") {
            self.token = token
        }

        var validCalls: Int { lock.withLock { validCallCount } }
        var refreshCalls: Int { lock.withLock { refreshCallCount } }

        func failValid(with error: (any Error)?) {
            lock.withLock { validFailure = error }
        }

        func failRefresh(with error: (any Error)?) {
            lock.withLock { refreshFailure = error }
        }

        func validAccessToken() async throws -> String {
            let failure = lock.withLock { () -> (any Error)? in
                validCallCount += 1
                return validFailure
            }
            if let failure { throw failure }
            return lock.withLock { token }
        }

        func forceRefreshAccessToken() async throws -> String {
            let failure = lock.withLock { () -> (any Error)? in
                refreshCallCount += 1
                return refreshFailure
            }
            if let failure { throw failure }
            return lock.withLock {
                token += "-new"
                return token
            }
        }
    }

    // MARK: - 装配

    private func makeTransport(
        harness: StubURLProtocol.Harness,
        provider: FakeTokenProvider? = nil,
        cache: HTTPResponseCache? = nil,
        retryPolicy: RetryPolicy = .none
    ) -> HTTPTransport {
        let clock = now
        return HTTPTransport(
            credentials: credentials,
            tokenProvider: provider,
            session: harness.makeSession(),
            cache: cache ?? HTTPResponseCache(configuration: .memoryOnly()),
            retryPolicy: retryPolicy,
            clock: { clock },
            sleeper: { _ in }  // 不真的等：退避是秒级，等待会让套件变慢且与断言无关
        )
    }

    private func seedCache(
        _ transport: HTTPTransport,
        url: URL,
        body: String,
        etag: String?
    ) async {
        await transport.cache.store(
            CachedHTTPResponse(
                statusCode: 200,
                headers: HTTPHeaders(["content-type": "application/json"]),
                body: Data(body.utf8),
                etag: etag,
                fetchedAt: now
            ),
            for: CacheKey(url)
        )
    }

    // MARK: - 统一请求头（§4.2）

    @Test("四个统一请求头一个不少，令牌走 Authorization")
    func injectsStandardHeaders() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"login":"octocat"}"#))
        let provider = FakeTokenProvider(token: "ghu_abc")

        let transport = makeTransport(harness: harness, provider: provider)
        _ = try await transport.send(.get(userURL))

        let request = harness.lastRequest
        #expect(request?.httpMethod == "GET")
        #expect(request?.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request?.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
        #expect(request?.value(forHTTPHeaderField: "User-Agent") == "GitDuo/2.0 (iOS)")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer ghu_abc")
        // 令牌进 URL 会泄进日志、Referer 与缓存键 —— 一律只走请求头
        #expect(request?.url?.absoluteString.contains("ghu_abc") == false)
    }

    @Test("调用方可以覆盖默认 Accept（PR diff 要 application/vnd.github.diff）")
    func callerHeadersOverrideDefaults() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("diff --git a/x b/x"))

        let transport = makeTransport(harness: harness)
        _ = try await transport.send(
            .get(userURL, headers: ["Accept": "application/vnd.github.diff"])
        )

        #expect(harness.lastRequest?.value(forHTTPHeaderField: "Accept") == "application/vnd.github.diff")
        // 其余默认头仍在（只覆盖指定的那一个）
        #expect(harness.lastRequest?.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
    }

    @Test("标注为不需要认证的请求不带 Authorization")
    func anonymousRequestHasNoAuthorization() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("{}"))

        let transport = makeTransport(harness: harness, provider: FakeTokenProvider())
        _ = try await transport.send(
            HTTPRequest(method: .get, url: userURL, requiresAuthentication: false)
        )

        #expect(harness.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("POST 的 body 与 Content-Type 都发出去；GET 不带 body")
    func requestBodyHandling() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("{}", status: 201))

        let transport = makeTransport(harness: harness)
        _ = try await transport.send(
            .sending(.post, to: userURL, body: Data(#"{"title":"x"}"#.utf8))
        )

        #expect(harness.lastRequest?.httpMethod == "POST")
        #expect(harness.lastRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = StubURLProtocol.bodyData(of: harness.lastRequest!)
        #expect(body == Data(#"{"title":"x"}"#.utf8))
    }

    // MARK: - ETag 条件请求（§5.2）

    @Test("缓存里有 ETag ⇒ 自动带 If-None-Match（无需调用方操心）")
    func sendsIfNoneMatchWhenCached() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"login":"octocat"}"#))

        let transport = makeTransport(harness: harness)
        await seedCache(transport, url: userURL, body: #"{"login":"cached"}"#, etag: "W/\"v1\"")

        _ = try await transport.send(.get(userURL))

        #expect(harness.lastRequest?.value(forHTTPHeaderField: "If-None-Match") == "W/\"v1\"")
    }

    @Test("缓存里没有 ETag ⇒ 不带 If-None-Match（空值会问出一个 400）")
    func omitsIfNoneMatchWithoutETag() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("{}"))

        let transport = makeTransport(harness: harness)
        await seedCache(transport, url: userURL, body: "{}", etag: nil)

        _ = try await transport.send(.get(userURL))

        #expect(harness.lastRequest?.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test("304 ⇒ 用本地副本返回，isFromCache 为真，**不消耗配额**（只发了 1 个请求）")
    func notModifiedUsesCachedBody() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 304))

        let transport = makeTransport(harness: harness)
        await seedCache(transport, url: userURL, body: #"{"login":"cached"}"#, etag: "W/\"v1\"")

        let response = try await transport.send(.get(userURL))

        #expect(response.statusCode == 200)  // 对调用方而言就是一条 200
        #expect(response.body == Data(#"{"login":"cached"}"#.utf8))
        #expect(response.isFromCache)
        #expect(harness.requestCount == 1)  // 没有第二个请求 —— 304 就是省在这里
    }

    @Test("304 之后刷新 fetchedAt（否则这条会一直看起来过期，下次又白问一遍）")
    func notModifiedRefreshesFetchTimestamp() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 304))

        let transport = makeTransport(harness: harness)
        await seedCache(transport, url: userURL, body: "{}", etag: "W/\"v1\"")
        _ = try await transport.send(.get(userURL))

        let entry = await transport.cache.entry(for: CacheKey(userURL))
        #expect(entry?.fetchedAt == now)
    }

    @Test("200 ⇒ 把响应与 ETag 写进缓存（下一次才能命中 304）")
    func storesResponseOnSuccess() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"login":"fresh"}"#, headers: ["ETag": "W/\"v2\""]))

        let transport = makeTransport(harness: harness)
        _ = try await transport.send(.get(userURL))

        let entry = await transport.cache.entry(for: CacheKey(userURL))
        #expect(entry?.etag == "W/\"v2\"")
        #expect(entry?.body == Data(#"{"login":"fresh"}"#.utf8))
    }

    @Test("下拉刷新：forcesReload ⇒ 不带 If-None-Match（必然拿到 200）")
    func forcedReloadSkipsConditionalRequest() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"login":"fresh"}"#))

        let transport = makeTransport(harness: harness)
        await seedCache(transport, url: userURL, body: "{}", etag: "W/\"v1\"")

        let response = try await transport.send(.get(userURL, forcesReload: true))

        #expect(harness.lastRequest?.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(!response.isFromCache)
    }

    @Test("写操作成功后按路径前缀失效（§5.4）")
    func writeInvalidatesRelatedPaths() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("{}", status: 201))

        let transport = makeTransport(harness: harness)
        let contents = URL(string: "https://api.github.com/repos/o/r/contents/a.md")!
        let branches = URL(string: "https://api.github.com/repos/o/r/branches")!
        let otherRepo = URL(string: "https://api.github.com/repos/o/other/contents/a.md")!
        for url in [contents, branches, otherRepo] {
            await seedCache(transport, url: url, body: "{}", etag: "e")
        }

        _ = try await transport.send(
            .sending(.put, to: contents, body: Data("{}".utf8), invalidating: ["/repos/o/r/contents"])
        )

        #expect(await transport.cache.entry(for: CacheKey(contents)) == nil)
        // 兄弟路径不受影响
        #expect(await transport.cache.entry(for: CacheKey(branches)) != nil)
        #expect(await transport.cache.entry(for: CacheKey(otherRepo)) != nil)
    }

    // MARK: - 401 → 刷新 → 重放（§3.2 第 2 条）

    @Test("401 ⇒ 强制刷新一次并重放，第二次成功（刷新 1 次、请求 2 次）")
    func unauthorizedTriggersRefreshThenReplay() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub([.empty(status: 401), .json(#"{"login":"octocat"}"#)])
        let provider = FakeTokenProvider(token: "ghu_old")

        let transport = makeTransport(harness: harness, provider: provider)
        let response = try await transport.send(.get(userURL))

        #expect(response.statusCode == 200)
        #expect(provider.refreshCalls == 1)
        #expect(harness.requestCount == 2)
        // 重放时用的是**刷新后**的令牌
        #expect(harness.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer ghu_old-new")
    }

    @Test("重放后仍然 401 ⇒ 抛 unauthorized，且**只刷新一次**（不能变成循环）")
    func replayFailureStopsAfterOneRefresh() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub([.empty(status: 401), .empty(status: 401)])
        let provider = FakeTokenProvider()

        let transport = makeTransport(harness: harness, provider: provider)
        do {
            _ = try await transport.send(.get(userURL))
            Issue.record("连吃两个 401 应当抛错")
        } catch {
            #expect((error as? GitHubError) == .unauthorized)
        }

        #expect(provider.refreshCalls == 1)
        #expect(harness.requestCount == 2)
    }

    @Test("刷新失败且抛 unauthorized ⇒ 原样传播（上层据此登出），不再重放")
    func refreshFailurePropagatesUnauthorized() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 401))
        let provider = FakeTokenProvider()
        provider.failRefresh(with: GitHubError.unauthorized)

        let transport = makeTransport(harness: harness, provider: provider)
        do {
            _ = try await transport.send(.get(userURL))
            Issue.record("刷新失败应当抛错")
        } catch {
            #expect((error as? GitHubError) == .unauthorized)
        }

        #expect(harness.requestCount == 1)  // 没重放
    }

    @Test("⚠️ 刷新因**断网**失败 ⇒ 抛 transport 错误，**不得**报成 unauthorized（断网 ≠ 登出）")
    func refreshFailureByNetworkIsNotUnauthorized() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 401))
        let provider = FakeTokenProvider()
        provider.failRefresh(with: GitHubError.transport(URLError(.notConnectedToInternet)))

        let transport = makeTransport(harness: harness, provider: provider)
        do {
            _ = try await transport.send(.get(userURL))
            Issue.record("刷新失败应当抛错")
        } catch let error as GitHubError {
            // 这条是本套件最重要的一条断言：把网络故障报成"凭据失效"，
            // 会让用户在飞行模式下被踢回登录页 —— §3.2 第 3 条明令禁止。
            #expect(error == .transport(URLError(.notConnectedToInternet)))
            #expect(error != .unauthorized)
        }
    }

    @Test("压根取不到令牌 ⇒ 直接抛错，**一次请求都不发**（而不是发个匿名请求换回 401）")
    func missingTokenFailsBeforeSending() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("{}"))
        let provider = FakeTokenProvider()
        provider.failValid(with: GitHubError.unauthorized)

        let transport = makeTransport(harness: harness, provider: provider)
        do {
            _ = try await transport.send(.get(userURL))
            Issue.record("取不到令牌应当抛错")
        } catch {
            #expect((error as? GitHubError) == .unauthorized)
        }

        #expect(harness.requestCount == 0)
        #expect(provider.refreshCalls == 0)
    }

    // MARK: - 重试（§4.1 的"重试"，具体化为幂等 GET 的有限退避）

    @Test("GET 遇 500 ⇒ 按策略重试，最终成功（请求数 = 1 + 重试次数）")
    func retriesServerErrorsOnGet() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub([.empty(status: 500), .empty(status: 500), .json(#"{"ok":true}"#)])

        let transport = makeTransport(harness: harness, retryPolicy: RetryPolicy(maximumRetries: 2))
        let response = try await transport.send(.get(userURL))

        #expect(response.statusCode == 200)
        #expect(harness.requestCount == 3)
    }

    @Test("GET 遇瞬时网络故障（超时）⇒ 重试")
    func retriesTransientNetworkFailures() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub([.failing(.timedOut), .json(#"{"ok":true}"#)])

        let transport = makeTransport(harness: harness, retryPolicy: RetryPolicy(maximumRetries: 1))
        let response = try await transport.send(.get(userURL))

        #expect(response.statusCode == 200)
        #expect(harness.requestCount == 2)
    }

    @Test("⚠️ 明确没网（notConnectedToInternet）**不重试** —— 重试只会把 2 秒的失败拖成 6 秒")
    func doesNotRetryWhenOffline() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.failing(.notConnectedToInternet))

        let transport = makeTransport(harness: harness, retryPolicy: RetryPolicy(maximumRetries: 2))
        do {
            _ = try await transport.send(.get(userURL))
            Issue.record("没网应当抛错")
        } catch {
            #expect((error as? GitHubError) == .transport(URLError(.notConnectedToInternet)))
        }

        #expect(harness.requestCount == 1)
    }

    @Test("⚠️ 写操作（POST）遇 500 **不重试** —— 重发写请求可能造成用户看不到的重复提交")
    func doesNotRetryWrites() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 500))

        let transport = makeTransport(harness: harness, retryPolicy: RetryPolicy(maximumRetries: 2))
        do {
            _ = try await transport.send(.sending(.post, to: userURL, body: Data("{}".utf8)))
            Issue.record("500 应当抛错")
        } catch {
            #expect((error as? GitHubError) == .serverError(status: 500))
        }

        #expect(harness.requestCount == 1)
    }

    @Test("⚠️ 400 落 serverError 兜底，但**status 不是 5xx** ⇒ 不重试（兜底 case 不能当重试依据）")
    func doesNotRetryNonServerStatusInFallbackCase() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 400))

        let transport = makeTransport(harness: harness, retryPolicy: RetryPolicy(maximumRetries: 2))
        do {
            _ = try await transport.send(.get(userURL))
            Issue.record("400 应当抛错")
        } catch {
            #expect((error as? GitHubError) == .serverError(status: 400))
        }

        #expect(harness.requestCount == 1)
    }

    @Test("不重试的错误：401 刷新后仍失败、404、422 都不该反复问")
    func doesNotRetryNonRetryableStatuses() async throws {
        for status in [404, 409, 422] {
            let harness = StubURLProtocol.makeHarness()
            harness.stub(.empty(status: status))
            let transport = makeTransport(harness: harness, retryPolicy: RetryPolicy(maximumRetries: 2))

            _ = try? await transport.send(.get(userURL))

            #expect(harness.requestCount == 1, "status \(status) 不该被重试")
        }
    }

    // MARK: - 错误归一化与解码

    @Test("403 带 Retry-After ⇒ .rateLimited（不是 .forbidden）")
    func forbiddenWithRetryAfterBecomesRateLimited() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"message":"You have exceeded a secondary rate limit"}"#,
                           status: 403,
                           headers: ["Retry-After": "60"]))

        let transport = makeTransport(harness: harness)
        do {
            _ = try await transport.send(.get(userURL))
            Issue.record("403 应当抛错")
        } catch let error as GitHubError {
            guard case let .rateLimited(_, isSecondary) = error else {
                Issue.record("期望 rateLimited，实际 \(error)")
                return
            }
            #expect(isSecondary)
        }
    }

    @Test("decode 成功；坏 body 抛 decoding（与其余错误同类，调用方不必处理两套）")
    func decodingBehaviour() async throws {
        struct Payload: Decodable, Equatable { let login: String }

        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"login":"octocat"}"#))

        let transport = makeTransport(harness: harness)
        let response = try await transport.send(.get(userURL))

        #expect(try response.decode(Payload.self) == Payload(login: "octocat"))

        let broken = HTTPResponse(
            statusCode: 200,
            headers: HTTPHeaders([:]),
            body: Data("<html>".utf8),
            isFromCache: false
        )
        do {
            _ = try broken.decode(Payload.self)
            Issue.record("坏 body 应当抛错")
        } catch let error as GitHubError {
            guard case .decoding = error else {
                Issue.record("期望 decoding，实际 \(error)")
                return
            }
        }
    }

    @Test("非 HTTP 响应（或桩件没配）⇒ transport 错误，不是裸 URLError")
    func nonHTTPResponseIsNormalised() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.reset()  // 不设桩响应 ⇒ 桩件会以 URLError(.unsupportedURL) 失败

        let transport = makeTransport(harness: harness)
        do {
            _ = try await transport.send(.get(userURL))
            Issue.record("应当抛错")
        } catch let error as GitHubError {
            guard case .transport = error else {
                Issue.record("期望 transport，实际 \(error)")
                return
            }
        }
    }

    @Test("响应里的配额快照可直接读取（设置页展示「剩余配额」用）")
    func responseExposesRateLimit() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json("{}", headers: [
            "X-RateLimit-Limit": "5000",
            "X-RateLimit-Remaining": "4321",
            "X-RateLimit-Reset": "1700003600",
            "X-RateLimit-Resource": "core",
        ]))

        let transport = makeTransport(harness: harness)
        let response = try await transport.send(.get(userURL))

        #expect(response.rateLimit?.remaining == 4321)
        #expect(response.rateLimit?.resource == .core)
    }

    // MARK: - 显式令牌（登录第 8 步）

    @Test("显式令牌覆盖 AccessTokenProviding：给了就用它，且**不**去打扰凭据层")
    func explicitTokenOverridesProvider() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.json(#"{"login":"octocat"}"#))
        let provider = FakeTokenProvider(token: "ghu_from_store")
        let transport = makeTransport(harness: harness, provider: provider)

        _ = try await transport.send(HTTPRequest(
            method: .get,
            url: userURL,
            explicitToken: "ghu_explicit"
        ))

        #expect(harness.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer ghu_explicit")
        #expect(provider.validCalls == 0, "登录窗口里 Keychain 还是空的，去要也是白要")
    }

    @Test("带显式令牌时 401 **不触发刷新**：此刻没有 refresh_token，刷新只会白搭一次必败往返")
    func explicitTokenSkipsRefreshOn401() async throws {
        let harness = StubURLProtocol.makeHarness()
        harness.stub(.empty(status: 401))
        let provider = FakeTokenProvider(token: "ghu_seed")
        let transport = makeTransport(harness: harness, provider: provider)
        let url = userURL

        await #expect(throws: GitHubError.unauthorized) {
            _ = try await transport.send(HTTPRequest(
                method: .get,
                url: url,
                explicitToken: "ghu_explicit"
            ))
        }

        #expect(provider.refreshCalls == 0)
        #expect(harness.requestCount == 1, "不刷新 ⇒ 也就没有重放")
    }
}
