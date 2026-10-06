import Foundation
import GitHubAPI
import GitDuoCore

/// 认证编排 —— 把 §3.1 的八个步骤串成一条可测的流程。
///
/// 依据：TECH_SPEC §3.1（授权流程）、§3.2（刷新）、§3.6（登出与撤销）、§3.8（门禁）。
///
/// 为什么是 `actor`：它持有**可变状态**（等待中的授权上下文、进行中的刷新任务），
/// 而 UI 的取消、后台的预刷新、401 触发的强制刷新会**并发**调用它。
/// 用 actor 让"同一时刻只有一段逻辑在改这些状态"成为编译器保证，而不是靠约定。
///
/// 职责边界：
/// - **在**：生成 verifier/state、校验回调、换令牌、写 Keychain、刷新（single-flight）、登出撤销。
/// - **不在**：打开浏览器窗口（那是 App 层的 `ASWebAuthenticationSession`，系统 API）；
///   §3.6 登出第 ③④ 步（清账号绑定的本地数据、重置导航栈）—— 那些属于各 Feature 与导航层。
public actor AuthCoordinator {

    /// 取当前时刻。注入而非直接调 `Date()`：过期/刷新都是时间相关的判断，
    /// 不注入就只能靠 `sleep` 去测——那种测试又慢又脆。
    public typealias Clock = @Sendable () -> Date

    // MARK: - 对外结果类型

    /// 一次回调处理的结局。
    public enum AuthorizationOutcome: Sendable, Equatable {
        case authenticated(login: String)
        /// 用户在授权页点了取消 —— **正常操作**，回登录页、不报错、不写任何凭据（§3.8）
        case cancelled
        /// 不是给本 App 的回调（形状不符）—— **静默丢弃**，连日志都不必（§3.9 场景 B）
        case ignored
        case failed(AuthError)
    }

    /// 一次登出的结局。
    public enum SignOutOutcome: Sendable, Equatable {
        /// GitHub 侧授权已撤销，本地凭据已清
        case revoked
        /// 未能撤销 GitHub 侧授权（离线 / 422 / 网络错误），**但本地已清**
        /// ⇒ UI 用降级文案，且设置页保留手动撤销入口（§3.6）
        case revokedLocallyOnly
    }

    // MARK: - 内部状态

    /// 等待中的授权上下文。
    ///
    /// ⚠️ 只存内存、绝不落盘（§3.1 要点 1）：`code_verifier` 是"授权码被第三方截获"
    ///    场景唯一有效的防线，写进磁盘等于自己也留了一份。进程重启即失效是**有意的**。
    private struct PendingAuthorization: Sendable {
        let codeVerifier: String
        let state: String
    }

    private let oauthClient: GitHubOAuthClient
    private let userEndpoint: GitHubUserEndpoint
    private let store: any TokenStore

    /// 接口缓存清理器（§3.6 ③ 的"接口与图片缓存"）。
    /// 注入而非直接调 `URLCache.shared`：登出必须清缓存这条行为要能被断言守住。
    private let cachePurger: any HTTPCachePurging

    private let clock: Clock

    private var pending: PendingAuthorization?

    /// 进行中的刷新。**single-flight 的全部实现就是这一个变量**（§3.2 第 4 条）：
    /// 后来的调用者共享同一个 `Task`，而不是各发一个请求——
    /// 并发刷新会让 GitHub 轮换 `refresh_token`，多个请求抢着用旧值必然互相作废。
    private var inFlightRefresh: Task<StoredToken, any Error>?

    // MARK: - 构造

    public init(
        oauthClient: GitHubOAuthClient,
        userEndpoint: GitHubUserEndpoint,
        tokenStore: any TokenStore,
        cachePurger: any HTTPCachePurging,
        clock: @escaping Clock = { Date() }
    ) {
        self.oauthClient = oauthClient
        self.userEndpoint = userEndpoint
        self.store = tokenStore
        self.cachePurger = cachePurger
        self.clock = clock
    }

    /// 便利构造：凭据 + 存储即可，网络会话由本方法转交两处。
    ///
    /// ⚠️ `session` 默认为 `nil`，且**原样**转给 `GitHubOAuthClient` —— 后者借此选一个
    ///    不挂 `URLCache` 的专用会话（令牌响应不得落盘，§3.1 / §3.7）。
    ///    `GitHubUserEndpoint`（`GET /user`）同样**不走 `URLSession.shared`**——
    ///    `URLCache` 连**请求对象**一起落盘，`Authorization` 头会明文进 `Cache.db`
    ///    （2026-10-06 真机实测）；它默认走 `GitHubURLSession.shared`。
    public init(
        credentials: GitHubAppCredentials,
        tokenStore: any TokenStore,
        session: URLSession? = nil,
        cachePurger: any HTTPCachePurging = SystemHTTPCachePurger(),
        clock: @escaping Clock = { Date() }
    ) {
        self.init(
            oauthClient: GitHubOAuthClient(credentials: credentials, session: session),
            userEndpoint: GitHubUserEndpoint(
                credentials: credentials,
                session: session ?? GitHubURLSession.shared
            ),
            tokenStore: tokenStore,
            cachePurger: cachePurger,
            clock: clock
        )
    }

    // MARK: - 启动恢复

    /// 冷启动时决定"直接进主界面还是回登录页"。
    ///
    /// 三种结果对应三种真相，**不可互相混淆**：
    /// - 没有凭据 / 凭据已过期 → `.unauthenticated`（清掉残留，避免每次启动都失败）
    /// - 凭据新鲜 → 直接放行（**不发请求**：启动快，也省配额）
    /// - 需预刷新 → 刷一次；失败时只有在"凭据失效"的情况下才登出
    public func restore() async -> SessionState {
        let loaded: StoredToken?
        do {
            loaded = try store.load()
        } catch {
            // 条目损坏：清掉。留着一个读不出来的凭据，只会让每次启动都在同一处失败
            discardCredentials()
            return .unauthenticated
        }

        guard let stored = loaded else { return .unauthenticated }

        let moment = clock()
        guard !stored.isRefreshTokenExpired(at: moment) else {
            discardCredentials()
            return .unauthenticated
        }

        guard stored.needsRefresh(at: moment) else {
            return .authenticated(login: stored.login)
        }

        do {
            let refreshed = try await singleFlightRefresh(at: moment)
            return .authenticated(login: refreshed.login)
        } catch let error as AuthError where error.invalidatesCredentials {
            discardCredentials()
            return .unauthenticated
        } catch {
            // ⚠️ 网络类失败：**不清凭据**（§3.2 第 3 条只对"失效/被撤销"清）。
            // 此刻 access token 多半仍在有效期内（刚踏进"过期前 5 分钟"的窗口），放行；
            // 后续请求若 401，由数据层触发的"刷新一次并重放"兜底（§3.2 第 2 条）。
            return .authenticated(login: stored.login)
        }
    }

    // MARK: - 步骤 1–3：发起授权

    /// 生成 PKCE 材料并返回授权页 URL，交给 App 层用系统浏览器打开。
    ///
    /// `state` 与 `code_verifier` 留在本 actor 内存里；调用方**拿不到它们**
    /// （也就不可能顺手打印出去）。
    public func beginAuthorization() throws -> URL {
        // ⚠️ 数据层的 `authorizationURL` **只负责拼 URL、不校验配置**（它不知道调用方的策略），
        //    因此"凭据缺失就拦住"是本层的事。不拦的后果不是报错，而是打开一个
        //    `client_id=` 为空的授权页——GitHub 会回一个英文错误页，用户完全不知道发生了什么。
        guard oauthClient.credentials.isConfigured else {
            throw AuthError.notConfigured
        }

        let verifier = PKCE.makeCodeVerifier()
        let state = PKCE.makeState()

        guard let url = oauthClient.authorizationURL(
            state: state,
            codeChallenge: PKCE.codeChallenge(for: verifier)
        ) else {
            throw AuthError.notConfigured
        }

        pending = PendingAuthorization(codeVerifier: verifier, state: state)
        return url
    }

    // MARK: - 步骤 5–8：处理回调

    /// 处理 `gitduo://oauth/callback?…`。
    ///
    /// 全过程八步一次跑完：校验 state → 换令牌 → `GET /user` → 写 Keychain。
    public func completeAuthorization(callbackURL: URL) async -> AuthorizationOutcome {
        let context = pending
        // ⚠️ 一次性：无论成败**立刻作废**。这样同一授权码被重复投递时，
        //    第二次必然落到 stateMismatch —— 这就是"state 一次性"的实现（§3.1 要点 2）。
        pending = nil

        switch OAuthCallback.resolve(callbackURL, expectedState: context?.state) {
        case .ignored:
            return .ignored

        case .cancelled:
            return .cancelled

        case let .failed(reason):
            return .failed(.callbackRejected(reason))

        case let .authorized(code):
            // 走到这里 state 已校验通过，context 必非 nil；此守卫只为让类型系统满意
            guard let context else { return .failed(.missingAuthorizationContext) }

            do {
                let token = try await oauthClient.exchangeCode(
                    code,
                    codeVerifier: context.codeVerifier
                )
                // 步骤 8：立刻验证令牌真的能用，并拿到登录名
                let user = try await userEndpoint.fetchAuthenticatedUser(accessToken: token.accessToken)

                let moment = clock()
                let expiries = token.expiries(now: moment)
                let stored = StoredToken(
                    accessToken: token.accessToken,
                    refreshToken: token.refreshToken,
                    accessTokenExpiry: expiries.access,
                    refreshTokenExpiry: expiries.refresh,
                    login: user.login
                )
                do {
                    try store.save(stored)
                } catch {
                    // 存不进去就**不能算登录成功**：否则界面已进主界面、令牌却不在 Keychain，
                    // 下次启动又回登录页 —— 用户会以为是"随机掉线"
                    return .failed(.credentialStoreFailed)
                }
                return .authenticated(login: user.login)
            } catch let error as OAuthError {
                return .failed(.oauth(error))
            } catch {
                return .failed(.oauth(.invalidResponse))
            }
        }
    }

    // MARK: - 令牌供给（供数据层调用）

    /// 取一个**当下可用**的访问令牌；已进入预刷新窗口则先刷新。
    ///
    /// - Throws: `AuthError.notAuthenticated`（没有凭据）
    public func validAccessToken() async throws -> String {
        let loaded: StoredToken?
        do {
            loaded = try store.load()
        } catch {
            loaded = nil
        }
        guard let stored = loaded else { throw AuthError.notAuthenticated }

        let moment = clock()
        guard stored.needsRefresh(at: moment) else {
            return stored.accessToken
        }
        return try await singleFlightRefresh(at: moment).accessToken
    }

    /// **强制**刷新一次（不看还剩多久）。
    ///
    /// 供数据层在收到 **401** 时调用，随后重放原请求——**只重放一次**（§3.2 第 2 条）。
    /// 并发调用会共享同一次刷新，不会打出一串刷新请求。
    public func forceRefreshAccessToken() async throws -> String {
        try await singleFlightRefresh(at: clock()).accessToken
    }

    // MARK: - 登出

    /// §3.6 的登出：撤销 GitHub 侧授权 → 清空本地凭据 → 清空接口缓存。
    ///
    /// ⚠️ 第 ③④ 步的**大部分**（各 Feature 绑定的本地数据、重置导航栈）**不在这里**：
    ///    那两件事分别属于各 Feature 的存储与导航层，本包不认识它们。
    ///    **唯一的例外是"接口缓存"** —— 它不属于任何 Feature，却是唯一可能把凭据
    ///    留在磁盘上的东西（见 `HTTPCachePurging` 的说明），所以由本层一并收口。
    ///
    /// ⚠️ **撤销失败不阻塞登出**：本地凭据照清（§3.6）。这不是"尽力而为"的敷衍——
    ///    用户按下"退出登录"的意思就是"这台机器上别再能用了"，撤销只是顺手把
    ///    GitHub 侧那条记录也收掉；为了收不掉的那条记录把用户留在登录态，是颠倒主次。
    public func signOut() async -> SignOutOutcome {
        let loaded: StoredToken?
        do {
            loaded = try store.load()
        } catch {
            loaded = nil
        }

        var outcome = SignOutOutcome.revoked
        if let stored = loaded {
            do {
                try await oauthClient.revokeAuthorization(accessToken: stored.accessToken)
            } catch {
                outcome = .revokedLocallyOnly
            }
        }

        discardCredentials()

        // §3.6 ③ 的"接口缓存"。**无条件执行** —— 撤销成败改变的是 GitHub 侧那条记录，
        // 不改变"这台机器上不该再留该账号的痕迹"这个结论。
        // ⚠️ 这一步省不得：改掉令牌的写入路径（`GitHubOAuthClient`）只能阻止**将来**再写，
        //    磁盘上**已经存在**的那份副本只有这里才会清掉。
        cachePurger.purge()

        return outcome
    }

    // MARK: - 内部

    /// **single-flight 刷新**：并发调用共享同一个 `Task`，令牌端点只会收到一次请求。
    private func singleFlightRefresh(at moment: Date) async throws -> StoredToken {
        if let inFlight = inFlightRefresh {
            return try await inFlight.value
        }

        // 捕获局部常量而不是 self：让这个 Task 不依赖 actor 状态，
        // 于是调用方 await 时 actor 能正常被其他调用者进入（否则会死锁在自己身上）
        let client = oauthClient
        let store = self.store
        let task = Task<StoredToken, any Error> {
            try await AuthCoordinator.performRefresh(client: client, store: store, at: moment)
        }

        inFlightRefresh = task
        defer { inFlightRefresh = nil }
        return try await task.value
    }

    private static func performRefresh(
        client: GitHubOAuthClient,
        store: any TokenStore,
        at moment: Date
    ) async throws -> StoredToken {
        let loaded: StoredToken?
        do {
            loaded = try store.load()
        } catch {
            loaded = nil
        }
        guard let current = loaded else { throw AuthError.notAuthenticated }

        guard !current.isRefreshTokenExpired(at: moment) else {
            try? store.clear()
            throw AuthError.refreshTokenExpired
        }

        let refreshed: OAuthToken
        do {
            refreshed = try await client.refresh(refreshToken: current.refreshToken)
        } catch let error as OAuthError {
            throw AuthError.oauth(error)
        }

        // 刷新会轮换 refresh_token（GitHub 的行为），两个过期时刻都要重算
        let expiries = refreshed.expiries(now: moment)
        let updated = StoredToken(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            accessTokenExpiry: expiries.access,
            refreshTokenExpiry: expiries.refresh,
            login: current.login
        )
        do {
            try store.save(updated)
        } catch {
            throw AuthError.credentialStoreFailed
        }
        return updated
    }

    private func discardCredentials() {
        try? store.clear()
        pending = nil
        inFlightRefresh?.cancel()
        inFlightRefresh = nil
    }
}
