import Foundation
import GitHubAPI
import GitDuoAuth
import GitDuoCore
import GitDuoDesign
import GitDuoKit

/// 组合根 —— **唯一的依赖装配点**。
///
/// 依据：TECH_SPEC §2.4。
/// 铁律：View / ViewModel **不得自行构造客户端**，一律从 environment 取。
@MainActor
@Observable
final class AppEnvironment {

    // MARK: - 状态

    /// 认证状态（驱动 `RootView` 的门禁二分）
    var authState: AuthState = .unauthenticated

    /// 启动恢复是否仍在进行。
    /// 用它把"启动那一瞬"与"确实未登录"分开——否则冷启动会先闪一下登录页，
    /// 再跳进主界面（已登录用户每次启动都看得到，很廉价但很显眼的瑕疵）。
    var isBootstrapping = true

    /// 登录失败 / 登出降级的一次性提示
    var notice: AuthNotice?

    // MARK: - 依赖

    /// 凭据存储。生产实现是 Keychain（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`，§3.3）。
    let tokenStore: any TokenStore

    /// 认证编排（`GitDuoAuth`）——生成 PKCE、换令牌、刷新、登出撤销都在里面。
    let authCoordinator: AuthCoordinator

    /// **唯一**的出网通道（`GitHubAPI`）。所有端点共用它 ⇒ 共用同一份缓存、
    /// 同一个配额闸门、同一套重试策略（切片 2 的核心决定）。
    let restClient: GitHubRESTClient

    /// GraphQL 通道（`GitHubAPI`）。与 REST **不是**同一条隧道：
    /// 只有置顶仓库走它（§9.1），而 GitHub 的 GraphQL 配额是**独立的一个桶**
    /// ⇒ 两边的限流器有意不共用（`HTTPTransport` 各带各的 `RateLimiter`）。
    /// 缓存**共用同一份**：缓存键里有完整请求形态，两种协议不会撞键，
    /// 而分成两份只会让同一份磁盘目录被两个 LRU 各写一遍。
    let graphQLClient: GitHubGraphQLClient

    // MARK: - 领域用例（切片 4 起）

    /// 仓库列表的取数动作（`GitDuoKit` 的领域层）。
    let repositories: LoadRepositoriesPage

    /// 首页置顶仓库（`viewer.pinnedItems`，一次查询取回全部）。
    let pinnedRepositories: LoadPinnedRepositories

    /// 探索榜（Search 限定符 + 缓存 + Star 增幅）。
    let trending: LoadTrendingBoard

    /// 他人仓库详情（四路并发）。
    let repoInsights: LoadRepoInsights

    /// 探索 Issues 列表（切片 4）。
    let repoIssues: LoadRepoIssues

    /// 探索 PR 列表（切片 4）。
    let repoPulls: LoadRepoPulls

    /// Star 的领域用例（先确认基准，再幂等切换 —— 决策 #41）。
    let starToggle: ToggleStar

    // MARK: - 本地存储

    /// 最近访问（落盘实现见 `UserDefaultsRecentVisitStore`）。
    ///
    /// ⚠️ 它是**账号数据**：`signOut()` 必须清掉（§3.6 第 ③ 步）。
    let recentVisits: any RecentVisitStore

    /// Star 基线快照（增幅要它才算得出来）。
    ///
    /// ⚠️ 同样是**账号数据** —— 留着它，换账号登录会拿着别人的基线算出凭空的增幅。
    let starSnapshots: any StarSnapshotStore

    // MARK: - 全局 UI 通道

    /// 轻提示的唯一通道（TECH_SPEC §8.4）—— 挂在 `MainTabView` 上，四个 Tab 共用。
    let toast = ToastCenter()

    /// 每个 Tab 各自的导航栈
    let router = Router()

    /// 接口缓存（`HTTPResponseCache`，两个客户端共用同一份）。
    ///
    /// 留着这个引用**只为一件事**：登出时整盘清空（§3.6 第 ③ 步）。
    /// 它没有观察价值（不驱动任何界面），所以标 `@ObservationIgnored`。
    @ObservationIgnored private let responseCache: HTTPResponseCache

    /// 系统浏览器胶水（无逻辑，因此不注入、不可替身）
    @ObservationIgnored private let webAuth = WebAuthenticationSession()

    init(
        tokenStore: any TokenStore = KeychainTokenStore(),
        credentials: GitHubAppCredentials = AppConfig.credentials
    ) {
        self.tokenStore = tokenStore

        // ⚠️ 先造编排、再把它当令牌供给器传给数据层 —— 顺序不能反：
        //    数据层的每个请求都要向它要令牌（决策 #33：出口只有这一个）。
        let coordinator = AuthCoordinator(credentials: credentials, tokenStore: tokenStore)
        self.authCoordinator = coordinator

        // 两个客户端共用这一份缓存（见 `graphQLClient` 的说明）。
        let cache = Self.makeHTTPCache()
        self.responseCache = cache

        let client = GitHubRESTClient(
            credentials: credentials,
            tokenProvider: coordinator,
            cache: cache
        )
        let graphQL = GitHubGraphQLClient(
            credentials: credentials,
            tokenProvider: coordinator,
            cache: cache
        )
        self.restClient = client
        self.graphQLClient = graphQL

        // 本地存储先造：`trending` 的 Star 增幅依赖 `starSnapshots`。
        let visits = UserDefaultsRecentVisitStore()
        let snapshots = UserDefaultsStarSnapshotStore()
        self.recentVisits = visits
        self.starSnapshots = snapshots

        self.repositories = LoadRepositoriesPage(
            source: GitHubRepositoryEndpoint(client: client)
        )
        self.pinnedRepositories = LoadPinnedRepositories(
            source: GitHubPinnedItemsEndpoint(client: graphQL)
        )
        self.trending = LoadTrendingBoard(
            source: GitHubSearchRepositoriesEndpoint(client: client),
            snapshots: snapshots
        )
        self.repoInsights = LoadRepoInsights(
            source: GitHubRepoInsightsEndpoint(client: client)
        )
        self.repoIssues = LoadRepoIssues(
            source: GitHubRepoIssuesEndpoint(client: client)
        )
        self.repoPulls = LoadRepoPulls(
            source: GitHubRepoPullsEndpoint(client: client)
        )
        self.starToggle = ToggleStar(
            source: GitHubStarEndpoint(client: client)
        )
    }

    /// 接口缓存（§5.1 的 L2：内存 + 磁盘，**自建**，绝不启用系统 `URLCache` —— 决策 #32）。
    ///
    /// 目录由组合根注入（而不是在包内拼路径）：包不知道 App 的容器长什么样，
    /// 测试则指向临时目录。放在 `Caches/` 下 —— 它是"可丢弃的加速器"，
    /// 系统在空间紧张时可以清理，登出时也会被显式清空（§3.6）。
    private static func makeHTTPCache() -> HTTPResponseCache {
        var configuration = HTTPResponseCache.Configuration.standard
        configuration.directory = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("GitDuoCache", isDirectory: true)
        return HTTPResponseCache(configuration: configuration)
    }

    // MARK: - 启动

    /// 冷启动时决定进主界面还是登录页。
    func bootstrap() async {
        switch await authCoordinator.restore() {
        case let .authenticated(login):
            authState = .authenticated(login: login)
        case .unauthenticated:
            authState = .unauthenticated
        }
        isBootstrapping = false
    }

    // MARK: - 登录

    /// 点「使用 GitHub 登录」→ 系统浏览器 → 回调 → 换令牌 → 进主界面。
    func signIn() async {
        guard case .unauthenticated = authState else { return }

        notice = nil
        authState = .authenticating

        do {
            let authorizeURL = try await authCoordinator.beginAuthorization()
            let callbackURL = try await webAuth.authenticate(
                url: authorizeURL,
                callbackScheme: AppConfig.callbackScheme
            )
            apply(await authCoordinator.completeAuthorization(callbackURL: callbackURL))
        } catch {
            // 已被别处的回调处理完了（见 `apply` 里的守卫）——不要再改动状态
            guard case .authenticating = authState else { return }
            authState = .unauthenticated
            if !WebAuthenticationSession.isUserCancellation(error) {
                notice = .error(error.localizedDescription)
            }
        }
    }

    /// 系统把 `gitduo://` 交回 App 时的入口（`onOpenURL`）。
    func handleCallback(_ url: URL) async {
        apply(await authCoordinator.completeAuthorization(callbackURL: url))
    }

    /// 把编排层的结局落到 UI 状态。
    private func apply(_ outcome: AuthCoordinator.AuthorizationOutcome) {
        switch outcome {
        case let .authenticated(login):
            authState = .authenticated(login: login)
            notice = nil

        case .cancelled, .ignored:
            // 用户取消 / 不是给我们的回调：回登录页，**不报错**（§3.8 出口表）
            if case .authenticating = authState { authState = .unauthenticated }

        case let .failed(error):
            // ⚠️ 这道守卫不是多余的：回调可能被投递两次——`ASWebAuthenticationSession`
            //    自己拦一次，系统 `onOpenURL` 再转一次。若不加守卫，第二次必然拿到的
            //    `stateMismatch`（state 是一次性的）会把**刚成功的登录**打回登录页。
            guard case .authenticating = authState else { return }
            authState = .unauthenticated
            notice = .error(error.errorDescription ?? "登录失败，请重试")
        }
    }

    // MARK: - 登出

    /// §3.6 的登出四步。①② 在 `AuthCoordinator`（能单测）；③④ 在这里——
    /// 它们分别依赖各 Feature 的存储与导航层，编排层不认识这些。
    func signOut() async {
        let outcome = await authCoordinator.signOut()

        // ③ 清空与该账号绑定的本地数据。已接入的：
        //    · 最近访问（含"当时是否可写"的归属）
        //    · Star 基线快照（留着它会拿旧账号的基线算出凭空的增幅）
        //    · 接口缓存（它存的是**带令牌换来的**响应，换账号后头像是别人的数据）
        //    尚未接入（落地时补在这一处）：收藏夹与归属映射（切片 9）、
        //    搜索历史（切片 5）、按仓库的分支记忆（切片 6）。
        await recentVisits.clear()
        await starSnapshots.clear()
        // ⚠️ `HTTPResponseCache` 是 actor（它的内存 LRU 要被多个请求并发读写）⇒ 必须 await。
        _ = await responseCache.removeAll()

        // ④ 重置全部导航栈与 Tab 选中项
        router.resetAll()

        authState = .unauthenticated
        notice = outcome == .revoked
            ? .info("已退出登录 · 已同时撤销 GitHub 侧授权")
            : .info("已退出登录 · 本机令牌已清除（未能撤销 GitHub 侧授权）")
    }
}

// MARK: - 提示

/// 登录页的一次性提示（错误或说明）。
enum AuthNotice: Equatable {
    case error(String)
    case info(String)

    var text: String {
        switch self {
        case let .error(text), let .info(text): text
        }
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

// MARK: - 骨架期占位登记

/// ⚠️ 任何以**占位**（stub）形式存在的类型都必须登记在此（AGENTS.md §5.2）；
/// 真实实现落地时把对应条目**一并删除**——留着不删，登记册就退化成了装饰。
///
/// 已消解：`TokenStore` 的 Keychain 实现（切片 1 → `KeychainTokenStore`，前置条件 P4）。
/// 已消解：`GitHubGraphQLClient` 的"尚无调用方"（切片 4 → 首页置顶经 `pinnedRepositories` 调用）。
enum SkeletonPlaceholders {
    static let registry: [String] = [
        "「我的」Tab 根页（`ProfileView` 仍是骨架屏，切片 9）",
        "`RouteView` 里仍走 `SkeletonScreen` 的推入页：搜索（5）· 仓库详情（4 的写侧）· "
            + "文件查看 / 编辑器 / 提交详情 / 分支（6）· Issue 与 PR 详情 / 新建（7）· "
            + "我的 Star / 我的收藏 / 设置（9）"
    ]
}
