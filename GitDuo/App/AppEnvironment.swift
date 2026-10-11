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

    /// 仓库标签库（切片 7）：**取全部标签 + 新建并选中**（决策 #56）。
    ///
    /// ⚠️ 一个实例服务两处：§4.4 分区二的「筛选」与 §4.10 新建 Issue 页的标签行 ——
    /// 用户裁定这两处**用同一个弹层**（`LabelPickerSheet`），所以底下的用例也是同一个。
    let labelCatalog: LabelCatalog

    /// Star 的领域用例（先确认基准，再幂等切换 —— 决策 #41）。
    let starToggle: ToggleStar

    /// Star 的**可写范围**（TECH_SPEC §3.5.5、决策 #80）—— 「这个仓库点得动那颗星标吗」。
    ///
    /// ## ⚠️ 全 App **只能有这一个实例**
    ///
    /// 它是**跨页共享的一份缓存**（一个会话里只查一次 `GET /user/installations`）。
    /// 两个实例的表现是"同一个仓库在两个页面上一个能点一个不能点"，而两页单看都对
    /// —— 与 `branchMemory` 那条先例同源。
    ///
    /// ⚠️ 它是一份**账号数据** —— 名单是"这个账号装了 GitDuo 的那些账号"，
    /// 换个人登录就变了 ⇒ `signOut()` 必须 `clear()`（§3.6 第 ③ 步）。
    ///
    /// ⚠️ 没有观察价值（各 ViewModel 各持一个 `Bool`，界面不直接绑它），
    /// 所以标 `@ObservationIgnored` —— 同下面 `responseCache` 那条。
    @ObservationIgnored let starWriteScope: StarWriteScopeCache

    /// 搜索取数（四范围分发 + 累加去重 + 按「范围 · 关键词」LRU 缓存 —— 切片 5.5）。
    ///
    /// ⚠️ 它是 `actor`，`SearchViewModel` 直接持有它。**不要**在这里再包一层"每次新建"：
    /// 缓存就活在这个实例里（§4.2 要求切范围"不清空已加载的页"，
    /// 而搜索桶只有 30 次/分钟 —— 每次重进页面都重发一轮是不可接受的）。
    let search: LoadSearch

    /// 搜索用户弹层的资料补全（C 方案：点开才走 `GET /users/{login}`）。
    let userProfile: LoadUserProfile

    // MARK: - 领域用例（切片 6）

    /// 仓库详情页进页取数（头部 + Star 基准，PRD §4.4）。
    let repoDetail: LoadRepoDetail

    /// 代码浏览的取数 —— 目录 + README + **两段式分支解析**（§9.4.1、决策 #55）。
    let repoTree: LoadRepoTree

    /// 文件查看的取数 —— 决策 #54 的三档降级。
    let fileContent: LoadFileContent

    /// 提交列表（分页）与提交详情（§4.4 分区四、§4.7）。
    let repoCommits: LoadRepoCommits

    /// 分支列表（§4.8）。
    let branches: LoadBranches

    /// 删除分支 —— **三重判定的唯一落点**（决策 #53）。
    let deleteBranch: DeleteBranch

    /// 新建分支（含名字校验 → 建 → 记住）。
    let createBranch: CreateBranch

    /// 合并分支（决策 #52）。
    let mergeBranch: MergeBranch

    // MARK: - 领域用例（切片 7）

    /// Issue 详情首屏（详情 + 评论两条独立数据 —— 决策 #57）。
    let issueDetail: LoadIssueDetail

    /// 关闭 / 重新打开 Issue（§4.9 操作区、决策 **#79**）。
    ///
    /// ⚠️ 与 `issueDetail` **共用同一个端点实例**（`GitHubRepoIssuesEndpoint` 无状态），
    /// 理由同下面发评论那一条。
    let issueAction: IssueAction

    /// 发一条评论。**Issue 详情与 PR 详情两页共用**（服务端本来就是同一个资源）。
    let postIssueComment: PostIssueComment

    /// 新建 Issue（§4.10）。
    let createIssue: CreateIssue

    /// PR 详情首屏 + 两个懒加载分区（详情 / 对话 / Commits / 文件 —— §4.11）。
    ///
    /// ⚠️ 它**同时依赖两个端点类**（构造器上就是两个参数）：详情 / 评审 / 文件 / Commits
    /// 在 `GitHubRepoPullsEndpoint`，而评论在 `GitHubRepoIssuesEndpoint`
    /// （决策 #60：PR 的时间线就是 issue 评论）。这不是"拆得太碎"，
    /// 是数据本来就在两个类上。
    let pullDetail: LoadPullDetail

    /// PR 的三个操作：合并（三方式）/ 关闭 / 重新打开（§4.11 操作区、§5.3）。
    let pullAction: PullAction

    // MARK: - 领域用例（切片 8）

    /// 提交一个文件 —— §9.6.1 的四条写通道 + §9.6.3 的「新分支 + PR」三步（决策 #64 / #68）。
    ///
    /// ⚠️ **它是本 App 第一条会往真实仓库写东西的通道**。
    /// 三条写用例（本条 / `renameFile` / `deleteFile`）**共用同一个
    /// `GitHubRepoContentEndpoint` 实例** —— 分开 new 不报错，但缓存会分成几份、
    /// 配额各算各的（同上面 `contentEndpoint` 那条），而出问题时表现是"偶发 403"。
    let saveFile: SaveFile

    /// 重命名（移动）文件 —— §9.6.5，**两步串行**：先 `PUT` 新路径，再 `DELETE` 旧路径（决策 #66②）。
    let renameFile: RenameFile

    /// 删除文件 —— §9.6.5。`sha` **现取**（用户手上没有"那一版"这回事，见 `DeleteFile` 的类型说明）。
    let deleteFile: DeleteFile

    /// §5.8 两个上传出口的**取件与预处理**：>1MB 的图片先自适应压缩（**决策 #71**）、
    /// 网页端显示不出来的格式一律转码（**决策 #72**）。
    ///
    /// ⚠️ 它**不依赖任何端点**（压缩与转码都是纯本地的事），之所以仍然收在这里：
    /// 它要**选一个具体实现**（`GitDuoCore.ImageProcessor` 对 `ImageProcessing` 这层接缝），
    /// 而"哪一个实现"正是组合根该管的事 —— 否则 `AddFileSheet` 里就多出一处
    /// "App 层知道 GitDuoCore 有什么"，而那正是这条接缝存在的理由。
    let uploadIntake: UploadIntake

    // MARK: - 领域用例（切片 9）

    /// 「我的」页的两路取数（昵称 / 简介 + 贡献日历与两个计数 —— 决策 #76）。
    ///
    /// ⚠️ 它**不抛错**：两条路各自降级成 `ProfileSection`，页面据此分块处理
    /// （`LoadProfileOverview` 的类型说明里记着"为什么不打捞部分成功"）。
    let profileOverview: LoadProfileOverview

    /// 「我的 PR / 我的 Issue」两页的取数（单条 part + 排序，决策 #73 / #44）。
    ///
    /// ⚠️ 与 `search` 一样是 **actor**（缓存活在它里面）⇒ 组合根只此一份。
    /// 两页共用它：`kind` 就是它缓存里的键（只有两个可能的键，不需要 LRU）。
    let conversations: LoadMyConversations

    // MARK: - 本地存储

    /// 最近访问（落盘实现见 `UserDefaultsRecentVisitStore`）。
    ///
    /// ⚠️ 它是**账号数据**：`signOut()` 必须清掉（§3.6 第 ③ 步）。
    let recentVisits: any RecentVisitStore

    /// Star 基线快照（增幅要它才算得出来）。
    ///
    /// ⚠️ 同样是**账号数据** —— 留着它，换账号登录会拿着别人的基线算出凭空的增幅。
    let starSnapshots: any StarSnapshotStore

    /// 最近搜索（落盘实现见 `UserDefaultsSearchHistoryStore`）。
    ///
    /// ⚠️ 同样是**账号数据**：`signOut()` 必须清掉（§3.6 第 ③ 步）——
    /// 它记的是"这个人在搜什么"，换个人登录还留着就是别人的行为痕迹。
    let searchHistory: any SearchHistoryStore

    /// 当前分支的**按仓库记忆**（PRD §3.10、TECH_SPEC §9.4.1、决策 #55）。
    ///
    /// ⚠️ 它是**账号数据**：分支名会暴露私有仓库的结构
    /// （`feature/客户XX-报价单改版` 这种名字本身就在泄密）⇒ `signOut()` 必须清掉。
    let branchMemory: any BranchMemoryStore

    /// 评论草稿（决策 #59、PRD §4.9 / §4.11）。
    ///
    /// ⚠️ 它同样是**账号数据**：草稿里可能有还没发布的正文（一段私事、
    /// 一个未公开的漏洞描述）—— 换个人登录还能读出来就是一次真实的泄露
    /// ⇒ `signOut()` 必须清掉（§3.6 第 ③ 步）。
    let commentDrafts: any CommentDraftStore

    // MARK: - 全局 UI 通道

    /// 轻提示的唯一通道（TECH_SPEC §8.4）—— 挂在 `MainTabView` 上，四个 Tab 共用。
    let toast = ToastCenter()

    /// 每个 Tab 各自的导航栈
    let router = Router()

    /// 接口缓存（`HTTPResponseCache`，两个客户端共用同一份）。
    ///
    /// **两个用处**：① 登出时整盘清空（§3.6 第 ③ 步）；
    /// ② 设置页的「清除缓存」要**量一次**再**清一次**（决策 #75）。
    /// 它没有观察价值（不驱动任何界面），所以标 `@ObservationIgnored`；
    /// 但**不能是 `private`** —— 设置页由 `RouteView` 装配，它得能拿到这一份
    /// （在设置页里另建一个 `HTTPResponseCache` 只会让"清缓存"清掉一个空目录，
    /// 而界面上照旧显示已释放多少）。
    @ObservationIgnored let responseCache: HTTPResponseCache

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
        let searchHistory = UserDefaultsSearchHistoryStore()
        let branchMemory = UserDefaultsBranchMemoryStore()
        let commentDrafts = UserDefaultsCommentDraftStore()
        self.recentVisits = visits
        self.starSnapshots = snapshots
        self.searchHistory = searchHistory
        self.branchMemory = branchMemory
        self.commentDrafts = commentDrafts

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
        self.labelCatalog = LabelCatalog(
            source: GitHubRepoLabelsEndpoint(client: client)
        )
        self.starToggle = ToggleStar(
            source: GitHubStarEndpoint(client: client)
        )
        // ⚠️ 「Star 写不写得动」的判据来源（决策 #80）—— 与 `starToggle` 一样，
        //    组合根只此一份：它是一份跨页共享的缓存，而"两个实例"的表现是
        //    同一个仓库在两页上一个能点一个不能点，且两边单看都对。
        self.starWriteScope = StarWriteScopeCache(
            loader: LoadStarWriteScope(source: GitHubInstallationsEndpoint(client: client))
        )
        // ⚠️ 搜索的四个端点**共存于一个适配器**（`GitHubSearchDataSource` 内部由
        //    `GitHubSearchEndpoints` 用**同一个** `client` 生成四个端点）——
        //    在这里 new 四个端点再各传一个，会让缓存分成几份、配额各算各的，而且不报错。
        self.search = LoadSearch(
            source: GitHubSearchDataSource(client: client)
        )
        // 搜索弹层补全：与搜索端点分开（它走 core 主桶、不是 search 桶）。
        self.userProfile = LoadUserProfile(
            source: GitHubPublicUserEndpoint(client: client)
        )

        // ── 切片 6 的四条链路。
        //
        // 四个端点都是同一个 `client` 的薄包装（它们不持有状态 ⇒ 分开 new 不花任何东西），
        // 但**共用一个 client** 是硬要求：否则缓存会分成几份、配额各算各的，而且不报错。
        let contentEndpoint = GitHubRepoContentEndpoint(client: client)
        let commitEndpoint = GitHubRepoCommitEndpoint(client: client)
        let branchEndpoint = GitHubRepoBranchEndpoint(client: client)

        self.repoDetail = LoadRepoDetail(
            detail: GitHubRepoDetailEndpoint(client: client),
            // ⚠️ 复用上面那个 `starToggle`：Star 的「先确认基准、再 ±1」只有一处实现
            //    （决策 #41），这里再 new 一个就把那份规则复制成了两份。
            star: self.starToggle
        )
        self.repoTree = LoadRepoTree(
            contents: contentEndpoint,
            commits: commitEndpoint,
            branches: branchEndpoint
        )
        self.fileContent = LoadFileContent(contents: contentEndpoint)
        self.repoCommits = LoadRepoCommits(source: commitEndpoint)
        self.branches = LoadBranches(source: branchEndpoint)

        // 三条写操作都拿同一个 `branchMemory` —— 记忆的读写必须落在同一个实例上，
        // 否则"建完分支"写下的是 A、"切分支"读的是 B，表现为记忆时有时无。
        self.deleteBranch = DeleteBranch(source: branchEndpoint, memory: branchMemory)
        self.createBranch = CreateBranch(source: branchEndpoint, memory: branchMemory)
        self.mergeBranch = MergeBranch(source: branchEndpoint)

        // ── 切片 7：Issues / PR。
        //
        // ⚠️ 一个端点实例服务三屏（列表 / 详情+评论 / 新建+发评论），
        //    三处**必须是同一个 `issuesEndpoint`** —— 分开 new 不报错，
        //    但缓存会分成几份、配额各算各的（同上面 `contentEndpoint` 那条）。
        //    `GitHubRepoIssuesEndpoint` 无状态，所以共用它零成本。
        let issuesEndpoint = GitHubRepoIssuesEndpoint(client: client)
        self.issueDetail = LoadIssueDetail(source: issuesEndpoint)
        // ⚠️ 关闭 / 重新打开也走同一个实例（决策 #79）：同屏的读写放在一起更好核对。
        self.issueAction = IssueAction(source: issuesEndpoint)
        // ⚠️ Issue 详情页与 PR 详情页**共用这一个实例**：评论是同一个端点
        //    （PR 在服务端就是一种 Issue），两页各造一个只是把同一份规则抄两遍。
        self.postIssueComment = PostIssueComment(source: issuesEndpoint)
        self.createIssue = CreateIssue(source: issuesEndpoint)

        // ⚠️ PR 侧那四条请求全在 `GitHubRepoPullsEndpoint` 上；
        //    而 `LoadPullDetail` 的**评论那一路仍走上面的 `issuesEndpoint`**
        //    （决策 #60 的对照表）⇒ 这里同时用到了两个端点实例，这是有意的。
        //    两者都是同一个 `client` 的薄包装、都无状态 ⇒ 分开 new 零成本。
        let pullsEndpoint = GitHubRepoPullsEndpoint(client: client)
        self.pullDetail = LoadPullDetail(detail: pullsEndpoint, comments: issuesEndpoint)
        self.pullAction = PullAction(source: pullsEndpoint)

        // ── 切片 8：编辑器与提交（三条写通道）。
        //
        // ⚠️ 这一段在 `init` 的**最后**，不是随手放的：`SaveFile` 的「新分支 + PR」
        //    那一档要用 `pullsEndpoint` 建 PR，而它上面才刚造出来（切片 7 那一段）。
        //    往上挪一格就编不过 —— 而那种错看起来像"顺序写错了"，
        //    实际是"这一步确实依赖上一步"。
        //
        // ⚠️ 三个 `files:` 参数都是**同一个** `contentEndpoint`（见上面那条说明）。
        self.saveFile = SaveFile(
            files: contentEndpoint,
            branches: branchEndpoint,
            pulls: pullsEndpoint
        )
        self.renameFile = RenameFile(contents: contentEndpoint, files: contentEndpoint)
        self.deleteFile = DeleteFile(contents: contentEndpoint, files: contentEndpoint)

        // ── 切片 8.7 / 8.8：上传前的图片压缩（决策 #71）与格式转码（决策 #72）。
        //
        // ⚠️ 与上面那三条**没有依赖关系**（它不发网络）—— 放在这里只是因为它属同一片，
        //    而且它同样是一条"选实现"的装配（见 `uploadIntake` 的说明）。
        //    `targetBytes` 走默认值 = `SaveFile.maxContentBytes`：压缩的目标与写通道的上限
        //    必须是**同一个数**，分开写的那天会出现"压到 1.2MB 再被 1MB 的判据拒掉"。
        self.uploadIntake = UploadIntake(processor: ImageProcessor())

        // ── 切片 9：「我的」那条线上的取数。
        //
        // ⚠️ `GitHubProfileDataSource` 要**两个客户端**（REST 取 `/user`、
        //    GraphQL 取日历与两个计数）—— 它们是两个端点、两个配额桶、
        //    两条会各自失败的路径（那个类型的说明里记着这条）。
        //    传的是上面造好的那**同一个** `client` / `graphQL`，
        //    分开 new 会让缓存与配额各算各的，而且不报错。
        self.profileOverview = LoadProfileOverview(
            source: GitHubProfileDataSource(restClient: client, graphQLClient: graphQL)
        )
        // ⚠️ 与搜索页**共用搜索桶**（30 次/分钟）⇒ 这一页用「加载更多」按钮而不是
        //    滚到底自动加载（决策 #44）。端点由适配器按 `kind` 选限定符（决策 #73）。
        self.conversations = LoadMyConversations(
            source: GitHubMyConversationsDataSource(client: client)
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
            warmUpStarWriteScope()
        case .unauthenticated:
            authState = .unauthenticated
        }
        isBootstrapping = false
    }

    /// 把「Star 可写范围」提前查好（**不 await**）。
    ///
    /// ## 为什么值得专门做这一步
    ///
    /// 它决定"那颗星标灰不灰"，而它是**异步**的 ⇒ 不预热的话，用户进第一个仓库详情页时
    /// 会看到按钮**先正常可点、两百毫秒后才变灰**。那一下不是 bug（"还没查到就不拦"是有意的），
    /// 但它是一次**没有必要的视觉抖动**，而消除它的成本只是冷启动多一个主桶请求
    /// （而且这一次查完就缓存住，整个会话不再问）。
    ///
    /// ⚠️ **不 await**：它是首屏之外的事，让它拖慢进主界面是倒过来的取舍。
    /// ⚠️ `AppEnvironment` 是 `@MainActor`，`Task { }` 继承它 —— 这里没有别的线程问题。
    private func warmUpStarWriteScope() {
        Task { _ = await starWriteScope.current() }
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
            // ⚠️ 换了个账号 / 刚授权完 ⇒ 可写范围必须重新查（缓存里那份属于**上一个**账号）。
            //    正常路径下 `signOut()` 已经清过一次，这里是**第二道**：
            //    "清缓存"与"重新查"放在两处，漏了任何一处都表现为
            //    "新账号按旧账号的授权范围画按钮"，而屏幕上完全看不出异常。
            Task {
                await starWriteScope.clear()
                _ = await starWriteScope.current()
            }

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
        //    · 最近搜索（切片的 5 —— 它记的是"这个人在搜什么"）
        //    · 分支记忆（切片 6.4 —— 分支名会暴露私有仓库的结构）
        //    · 评论草稿（切片 7 —— 草稿里可能有还没发布的正文）
        //    · **Star 可写范围**（切片 11 —— 它是"这个账号把 GitDuo 装在哪几个账号上"，
        //      换个人登录，能写的仓库也换了）
        //    · 接口缓存（它存的是**带令牌换来的**响应，换账号后头像是别人的数据）
        await recentVisits.clear()
        await starSnapshots.clear()
        await searchHistory.clear()
        await branchMemory.clear()
        await commentDrafts.clear()
        await starWriteScope.clear()
        // ⚠️ `LoadSearch` 与 `LoadMyConversations` 都是 actor，它们缓存的是
        //    **上一个账号搜出来的结果**（含私有仓库名、他提过的 PR）⇒
        //    与接口缓存同一条：不清就会在新账号的界面上露出来。
        await search.invalidateAll()
        await conversations.invalidateAll()
        // ⚠️ `HTTPResponseCache` 是 actor（它的内存 LRU 要被多个请求并发读写）⇒ 必须 await。
        _ = await responseCache.removeAll()

        // ④ 重置全部导航栈与 Tab 选中项
        router.resetAll()

        authState = .unauthenticated
        // ⚠️ 两句都取自领域层（`ProfileCopy`），**不在这里写字符串**：
        //    降级那句带着「可在设置中手动撤销」—— 少了它，设置页那个兜底入口
        //    就等于不存在（用户只知道"没撤销成功"，不知道还能去哪补救）。
        notice = outcome == .revoked
            ? .info(ProfileCopy.signedOutNotice)
            : .info(ProfileCopy.signOutDegradedNotice)
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
/// 已消解：`RouteView` 的 `.search`（切片 5 → `SearchView` + `search` / `searchHistory` 装配）。
/// 已消解：`RouteView` 的 `.repoDetail` / `.fileView` / `.commitDetail` / `.branches`
///        （切片 6.5 → 四个真页面 + `repoDetail` / `repoTree` / `fileContent` /
///        `repoCommits` / `branches` / `deleteBranch` / `createBranch` / `mergeBranch`
///        八条用例与 `branchMemory` 的装配）。
/// 已消解：`RouteView` 的 `.issueDetail` / `.newIssue` / `.prDetail`
///        （切片 7.5 → 三个真页面 + `issueDetail` / `postIssueComment` / `createIssue` /
///        `pullDetail` / `pullAction` 五条用例与 `commentDrafts` 的装配）。
/// 已消解：`RouteView` 的 `.editor`（切片 8.4 → `EditorView` + `saveFile` / `renameFile` /
///        `deleteFile` 三条写用例的装配）。
/// 已消解：`RouteView` 的 `.stars` / `.settings`（切片 9.4+9.5 →
///        `MyStarsView` / `SettingsView` + `profileOverview` /
///        `conversations` 三条用例与 `conversations` 的登出清缓存）。
///        （`.folders` 也曾在这里 —— 「我的收藏」功能已于 2026-10-11 整体移除。）
/// 已消解：「我的」Tab 根页（切片 9.4 → `ProfileView` 重写，摘掉 `SkeletonScreen`；
///        登出那一行已迁进 `SettingsView`）。
enum SkeletonPlaceholders {
    /// ⚠️ **空数组 = 全 App 没有占位块了**（切片 9 是"占位清零"的那一片）。
    /// 它自己就是完成定义里的那条闸门：再出现任何一个占位，都得在这里加一行
    /// （`AGENTS.md §5.2`）—— 留着不删，登记册就退化成了装饰。
    static let registry: [String] = []
}
