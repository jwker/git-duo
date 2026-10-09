import Foundation
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 他人仓库详情的状态（PRD §4.13、TECH_SPEC §9.11）。
///
/// ## 它管三件不同节奏的事
///
/// | | 数据 | 何时取 |
/// |---|---|---|
/// | 页面四路数据 | `GET /repos` + `languages` + `releases/latest` + `contributors` | 进页一次（并发四路） |
/// | Star 基准 | `GET /user/starred/{o}/{r}` | 详情回来之后 —— 它需要详情里的星数 |
/// | 目录 + README | `GET /contents` 等 | 详情回来之后 —— 它要 `defaultBranch` |
///
/// 第三条走 **`RepoTreeSession`**（§4.4 的「代码」分区用的是同一个会话）：
/// 分支两段式解析、记忆失效回落、副标题逐条补填那几条规则只有一个落点。
///
/// ## ⚠️ 一路失败 ⇒ 整页失败（有意如此）
///
/// 看起来"分别降级"更友好，但 §8.5 把加载 / 失败态**三档统一**了、
/// 并明写"各页面不得自行发挥"。分区块各自失败要再定义一套"块级失败态"，
/// 那是新的产品口径，不该由实现顺手定。`LoadRepoInsights` 里有完整理由。
///
/// ⚠️ 上面那条**不适用于目录**：它落在第 ⑤ / ⑥ 分区里、由 `RepoTreeSection`
/// 自带块级失败态（那是 §8.5 三档在"分区"这一层上的正常用法，
/// 与"整页失败"不是同一件事 —— §4.4 的代码分区也是这么处理的）。
@MainActor
@Observable
final class ExploreRepoViewModel {

    private(set) var insights: LoadState<RepoInsights> = .idle

    /// 目录浏览的会话（当前分支 + 目录页 + 分支列表 + 副标题补填）。
    ///
    /// ⚠️ 它是**只读浏览**的那一半：可切分支（记忆照写）、不可增删合并 ——
    /// 后者由 `BranchSheet(isReadOnly: true)` 那一侧决定，与本类型无关。
    let tree: RepoTreeSession

    /// Star 的当前状态。`nil` = 基准还没确认（详情没好，或那次查询失败了）。
    ///
    /// ⚠️ 基准失败**不抛错、不让整页失败**（`ToggleStar.initialState` 的降级）：
    /// 页面的头部、语言构成、贡献者与它无关。用户点下去时会先补一次基准查询。
    private(set) var star: StarState?

    /// Star 请求在途 ⇒ 按钮内联 loading + 禁用（§8.5「操作类」）。
    private(set) var isTogglingStar = false

    /// **这个仓库的 Star 点得动吗**（TECH_SPEC §3.5.5、决策 #80）。
    ///
    /// ⚠️ **本页是这条限制影响最大的屏** —— 它出现的每一条数据（趋势榜 / 搜索）
    /// 都是**别人的仓库**，而别人的仓库**写不了**。所以这里大量条目会是灰的，
    /// 那不是坏了，是如实。
    ///
    /// ⚠️ 初值 `true` 与 `RepoDetailViewModel` 同一个理由：`StarWriteScope` 的规则是
    /// "**还没查到就不拦**"。差别在于本页**真的会用到 `false`**（那一页基本用不到）。
    private(set) var starWritable = true

    /// 这个仓库现在在哪个收藏夹里；`nil` = 没收藏过（PRD §4.13 的 ② 分区）。
    ///
    /// ## ⚠️ 它是**纯本地**的，与 Star 那一套完全不同
    ///
    /// GitHub 没有"收藏夹"这个资源（§9.12：连读接口都没有）⇒ 这一块
    /// **永远不发请求、永远不会失败**，也就不需要 Baseline 那一套
    /// （对照 `star`：它得先 `GET /user/starred/{o}/{r}` 确认基准，决策 #41）。
    /// 它只有"还没读出来"这一瞬（首帧），没有"读错了"。
    private(set) var favoriteFolder: String?

    /// 「选择收藏列表」弹层要画的那份清单（夹名 + 项目数）。
    ///
    /// ⚠️ 与 `favoriteFolder` **同一次读回来**（`loadFavorite()` 里两行），
    /// 所以不存在"勾在哪"与"清单里有没有它"对不上的中间帧。
    private(set) var folderSummaries: [FolderSummary] = []

    /// **弹层内**那一行校验提示（`nil` = 不显示）。
    ///
    /// ⚠️ 本页只有 `.emptyName` 那一档用它（新建收藏夹）。另外两档（建成 / 重名复用）
    /// 都会**关掉弹层** ⇒ 照旧 `toast.show(…)` —— 弹层不在的时候提示条看得见。
    /// 而 `.emptyName` 那一档**弹层留着**（用户还得接着打字），提示条会被弹层整块盖住
    /// ⇒ 必须画在弹层里（决策 #77 / 偏差第 45 条；详见 `FoldersViewModel.sheetHint`）。
    private(set) var sheetHint: String?

    /// 相对时间现算用的"现在"。由视图在渲染那刻传进来（见 `open` 处的说明）。
    var now: Date { .now }

    private let loader: LoadRepoInsights
    private let starToggle: ToggleStar
    private let starScope: StarWriteScopeCache
    private let visits: any RecentVisitStore
    private let folders: any FolderStore
    private let toast: ToastCenter

    let fullName: String

    init(
        fullName: String,
        path: RepoPath,
        loader: LoadRepoInsights,
        treeLoader: LoadRepoTree,
        branches: LoadBranches,
        starToggle: ToggleStar,
        starScope: StarWriteScopeCache,
        memory: any BranchMemoryStore,
        visits: any RecentVisitStore,
        folders: any FolderStore,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.loader = loader
        self.starToggle = starToggle
        self.starScope = starScope
        self.visits = visits
        self.folders = folders
        self.toast = toast
        self.tree = RepoTreeSession(
            fullName: fullName,
            path: path,
            loader: treeLoader,
            branches: branches,
            memory: memory
        )
    }

    // MARK: - 生命周期

    /// 进页：**先记访问，再取数**。
    ///
    /// 顺序不能反：万一取数失败，这次访问也确实发生了 —— 而"最近访问"记的是
    /// "用户打开过它"，不是"它成功显示了"。
    func start() async {
        // ⚠️ `canWrite: false` **是事实、不是猜测**：能走到本页，只可能是因为路由
        //    在进入前就把它判成了他人仓库（`HomeView` / `ReposView` / `ExploreView` 三处入口）。
        //    这正是 `RecentVisitStore.record(fullName:canWrite:at:)` 要调用方显式传参的原因 ——
        //    零额外请求、零猜测（TECH_SPEC §7.2）。
        await visits.record(fullName: fullName, canWrite: false, at: Date())

        // ⚠️ 收藏状态**排在四路取数之前**：它是本地的（§9.12），一瞬就回来，
        //    排在后面只会让 ② 分区在那几秒里显示成"没收藏过"—— 而它并不是没读出来，
        //    是我们**还没去读**（那正是 §8.5 说的"加载中 ≠ 无数据"那种错）。
        await loadFavorite()

        // ⚠️ 「Star 写不写得动」也排在这里（稳态下是缓存命中，组合根冷启动就预热过）。
        //    本页这一问**基本上每次都是有意义的** —— 它进来的多半是别人的仓库。
        await resolveStarWritable()

        guard !insights.hasFinished else { return }
        await load()
    }

    func refresh() async {
        // 收藏也重读一次：它可能在**另一个入口**被改过（「我的收藏」管理页、
        // 或别的仓库详情页），而这两处读的是同一份本地数据（§9.12 末段）。
        await loadFavorite()
        // 可写范围同理：稳态下白做不了什么，但**第一次没问到**时（断网进的页）
        // 这里是唯一的重试出口 —— `StarWriteScopeCache` 有意不缓存失败。
        await resolveStarWritable()
        await load()
    }

    // MARK: - Star

    func toggleStar() async {
        guard let current = star, !isTogglingStar else { return }

        isTogglingStar = true
        defer { isTogglingStar = false }

        do {
            let (next, action) = try await starToggle.toggle(current)
            star = next
            toast.show(StarCopy.toast(for: action))
        } catch {
            // ⚠️ 失败**不改动任何计数**（`ToggleStar.toggle` 保证这一点），
            //    按钮恢复可点（`defer` 收起 loading），并给一条提示。
            //    ⚠️ 提示按**成因**分流（决策 #80）：本页的失败**绝大多数就是**
            //       "越出安装范围" —— 这一页里基本全是别人的仓库。
            //       而通用句 `操作失败 · 请重试` 会把用户送向一条永远不会成功的重试。
            toast.show(StarCopy.failureMessage(for: error))
        }
    }

    /// 问一次「这个仓库写不写得动」（口径同 `RepoDetailViewModel.resolveStarWritable`）。
    private func resolveStarWritable() async {
        starWritable = await starScope.current().canWrite(fullName: fullName)
    }

    // MARK: - 目录（转发给会话）

    /// 打开切换弹层时取分支列表。
    func loadBranches() async {
        await tree.loadBranches()
    }

    /// 切到另一条分支 —— 只影响这一页的目录与 README（本页没有提交列表要清）。
    func switchBranch(to name: String) async {
        guard let defaultBranch = insights.value?.detail.defaultBranch else { return }
        guard await tree.switchBranch(to: name, defaultBranch: defaultBranch) else { return }
        // 只读浏览也能切分支 ⇒ 切成功要给一句（与 §4.4 同一句）。
        toast.show(BranchCopy.switchedToast(branch: name))
    }

    // MARK: - 收藏（纯本地，PRD §4.13 的 ② 分区 / §5.5 / §5.6）

    /// 读一次本地收藏状态：**这个仓库属于哪个夹** + **清单里各夹几项**。
    ///
    /// 进页一次；之后每次变更（收藏 / 换夹 / 取消 / 新建并收藏）再读一次。
    /// ⚠️ 它**不出网**（§9.12）⇒ 不需要"在途"标志，也不会失败。
    func loadFavorite() async {
        favoriteFolder = await folders.folder(ofRepo: fullName)
        folderSummaries = await folders.summaries()
    }

    /// 没收藏时那颗按钮：收进默认夹（原型 `favNow`）。
    ///
    /// ⚠️ 首次收藏的提示里带着「再点可选择列表」—— 那是**一次性引导**，
    /// 而它必须兑现：用户第一次点的时候并不知道"再点一下能换夹"
    /// （`FolderCopy.favoritedToDefault` 的说明）。所以两句**不能合并**。
    func favoriteToDefault() async {
        let outcome = await folders.move(repo: fullName, to: FolderDefaults.name)
        await loadFavorite()

        switch outcome {
        case let .moved(previous, current):
            toast.show(previous == nil
                ? FolderCopy.favoritedToDefault
                : FolderCopy.favorited(to: current))
        case let .unchanged(folder):
            // 这一支从"未收藏"那颗按钮进来时不可达（它就是按"不在任何夹里"画的）。
            // 留着是因为**不能靠"界面的分支"来保证领域层的一致性** ——
            // 另一处刚好把它收了进来时，说"已收藏到「X」"仍然是对的。
            toast.show(FolderCopy.favorited(to: folder))
        case .unknownFolder:
            // 默认夹是存储的不变量（一定存在）⇒ 到不了这里；真到了也不静默吞掉。
            toast.show(ActionCopy.failed)
        }
    }

    /// 弹层里点了某一项（原型 `pickFav`）。
    ///
    /// ⚠️ **点已选中的那个夹 = 取消收藏**（不是"什么都不做"）——
    /// `FolderCopy.listSheetHint` 逐字写着「再点已选列表取消收藏」。
    /// 这是本页唯一一个"取消收藏"的入口（列表行上没有）。
    func pickFolder(_ name: String) async {
        if favoriteFolder == name {
            // 返回值只在"另一处刚好也把它删了"时才是 `false`（两处操作同一份本地数据）
            // —— 而那时成品状态与那句提示说的**完全一致**（它现在不在收藏里），
            // 所以不看返回值（`remove` 的说明也写了这种情形不是失败）。
            await folders.remove(repo: fullName)
            await loadFavorite()
            toast.show(FolderCopy.removed)
            return
        }

        let outcome = await folders.move(repo: fullName, to: name)
        await loadFavorite()

        switch outcome {
        case let .moved(_, current):
            toast.show(FolderCopy.favorited(to: current))
        case let .unchanged(folder):
            toast.show(FolderCopy.favorited(to: folder))
        case .unknownFolder:
            // 清单就是从 `folderSummaries` 画的 ⇒ 理论上点不出一个不存在的夹。
            toast.show(ActionCopy.failed)
        }
    }

    /// 弹层里「新建收藏夹…」→ 创建并把这个仓库放进去（原型 `createFav`、PRD §5.6 前半）。
    ///
    /// ⚠️ 重名时走 **`duplicateInRepository`**（"已存在，已为你选中"）而不是管理页那一句
    /// —— 两个入口在这一步**有意不同**（§9.12），差别就在这半句话上。
    ///
    /// - Returns: **这一张弹层该不该关**。空名 ⇒ `false`（留在弹层里改；提示画在**弹层内**，
    ///   因为它这一档不关弹层 —— 提示条会被弹层盖住，决策 #77）；建成或重名复用 ⇒ `true`
    ///   （原型两条路都是 `closeSheet()`；那两档关掉弹层之后照旧走提示条）。
    ///   弹层的 `sheet` 状态在本视图手上，所以由调用点据此决定 ——
    ///   在这里持有一个"该不该关"的布尔量会变成第二份真相。
    func createFolderAndFavorite(name: String) async -> Bool {
        // 这一次的结果说了算，先清上一次的。
        sheetHint = nil

        let outcome = await folders.createAndFavorite(name: name, repo: fullName)
        await loadFavorite()

        switch outcome {
        case let .created(name):
            toast.show(FolderCopy.created(name))
            return true
        case .reused:
            toast.show(FolderCopy.duplicateInRepository)
            return true
        case .emptyName:
            // ⚠️ 这一档 `return false`（弹层留着）—— 提示与返回值必须**同向**：
            //    若哪天改成 `return true`，这句话就没人看得见了（弹层关掉、而它没走提示条）。
            sheetHint = FolderCopy.emptyName
            return false
        }
    }

    // MARK: - 内部

    private func load() async {
        // 已有内容时**不切到 loading**（§8.5：下拉刷新不遮挡已有内容）。
        let hadContent = insights.value != nil
        if !hadContent { insights.begin() }

        do {
            let value = try await loader.load(fullName: fullName, now: Date())
            insights.succeed(value)
            // 详情到手才知道星数 ⇒ Star 基准必须在这之后问。
            star = await starToggle.initialState(fullName: fullName, starCount: value.detail.starCount)
            // ⚠️ 目录也排在详情之后：它要 `defaultBranch`。
            await tree.load(defaultBranch: value.detail.defaultBranch)
        } catch {
            if hadContent {
                // ⚠️ 正本在 `GitDuoKit.RefreshCopy`（切片 7.4 收口）。
                toast.show(RefreshCopy.failed)
            } else {
                insights.fail(Self.failure(from: error))
            }
        }
    }

    /// 把任意错误收敛成 `GitHubError`（同其余 ViewModel 的口径：
    /// 映射失败归 `.decoding`，**不是** `.transport`）。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }

    /// ⚠️ **决策缺口**：PRD §7 的「提示 / 校验」一节给了 Star 成功与取消的两句，
    /// **没有给失败那一句**。那一句 (「操作失败 · 请重试」) 仍然按"陈述事实 + 可重试"措辞，
    /// 但它**从这里搬走了** —— 切片 7.4 收口到 `GitDuoKit.ActionCopy.failed`
    /// （正本；本文件原有一份同值副本 `starFailedToast`）。
    /// 已登记到 `REVIEW-CHECKLIST.md §5`，等拍板后与 PRD 一起改（改一处即可）。
}

/// 探索仓库详情的可见文案（PRD §4.13 / §7）。
enum ExploreRepoCopy {

    /// 三个「数据拿到了但是空的」状态 —— 文案收在**领域层**
    /// （`RepoInsightNotice`，与 `ExploreBoardNotice` 同一做法），这里只做转发，
    /// 避免视图里出现字面量。
    static var noLanguages: String { RepoInsightNotice.noLanguages }
    static var noRelease: String { RepoInsightNotice.noRelease }
    static var noContributors: String { RepoInsightNotice.noContributors }

    static let myFoldersSection = "我的收藏（私人整理 · 仅自己可见）"
    static let languageSection = "语言构成"
    static let releaseSection = "Latest Release"

    /// 第 ⑤ 分区的小节标题 —— 根目录是 `文件浏览`，子目录里带 ` · {path}`（原型逐字）。
    ///
    /// - Parameter path: 当前目录。传 `nil` 或根路径即为根目录。
    static func fileSection(path: RepoPath?) -> String {
        guard let path, !path.isRoot else { return fileSectionBase }
        return "\(fileSectionBase) · \(path.raw)"
    }

    private static let fileSectionBase = "文件浏览"

    // ⚠️ 第 ⑥ 分区的小节标题（`README.md`）**已删** —— 它原先在这里有一个
    //    `readmeSection`，值与 `RepoCopy.readmeSectionTitle` **完全相同**。
    //    两处各存一份时，"把标题改成 `README`"只会改到其中一页。
    //    现在两页共用 `RepoCopy.readmeSectionTitle`（由 `RepoTreeSection` 渲染）。

    static let collaborationSection = "参与协作"
    static let releaseAssetsHint = "资产与源码下载依赖仓库的 Release 页面"

    static let issuesRowTitle = "Issues"
    static let issuesRowSubtitle = "浏览与参与讨论 · 无关闭权限"
    static let pullsRowTitle = "Pull Requests"
    static let pullsRowSubtitle = "查看他人贡献 · 可评论不可合并"

    static let skeletonNote = "加载中…"
    static let failureTitle = "加载失败 · 点击重试"
    static let retry = "重试"

    /// ⚠️ 「刷新失败」那一句**不在这里** —— 切片 7.4 收口到
    /// `GitDuoKit.RefreshCopy.failed`（正本，PRD §7 没有这条，是 §8.5 推出来的）。

    static let sourceCodeButton = LatestRelease.sourceCodeButtonTitle
}
